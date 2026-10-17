-- BOTS: AI players that fight like real ones (settings: ServerStorage > Bots > BotConfig)
--   local Bots = require(ServerStorage.Bots.BotService)
--   local bot = Bots.Spawn({CFrame = cf, Team = 1, MatchId = "...", Difficulty = "Medium", Target = player})
--   bot.Model / bot.Humanoid / bot.Name / bot.UserId (the avatar's id: headshots) / bot.Alive
--   Bots.Despawn(bot)   Bots.All()   Bots.Died (BindableEvent: bot)
-- MATCHES (MatchmakingServer uses these):
--   Bots.Identity()           -> {Name, UserId} not used by any other bot right now (Bots.Release(identity) frees it)
--   Bots.New(opts)            -> a bot with no body yet (opts: Identity, Team, MatchId, Difficulty)
--   Bots.Place(bot, cframe)   -> (re)builds its body there with full health (yields while the avatar loads)
--   bot:SetAttribute / bot:GetAttribute  -> like a player's ("Frozen", "CombatLocked", "ShootLocked", "MatchKills" ...)
-- Enemies = players / bots in the same MatchId on the other team. With no MatchId (testing) it fights bot.Target.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SSS = game:GetService("ServerScriptService")

local Config = require(script.Parent:WaitForChild("BotConfig"))
local MoveCfg = require(RS:WaitForChild("MovementConfig"))
local Combat = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))
local Effect = RS:WaitForChild("BalloonCombat"):WaitForChild("Remotes"):FindFirstChild("Effect")

local M = {}
M.Died = Instance.new("BindableEvent")
-- hooks (MatchmakingServer sets these): OnHit(bot, victimChar, amount, isHead, isMelee, killed), OnShot(bot, from, to, hit)
M.OnHit = nil
M.OnShot = nil
local bots = {}
local folder = workspace:FindFirstChild("Bots") or Instance.new("Folder")
folder.Name = "Bots"
folder.Parent = workspace
-- one Configuration per bot with its attributes, so every client can see it (Tab scoreboard)
local MM = RS:WaitForChild("Matchmaking")
local tagFolder = MM:FindFirstChild("BotTags") or Instance.new("Folder")
tagFolder.Name = "BotTags"
tagFolder.Parent = MM

local function diff(name)
	return Config.Difficulties[name or Config.Difficulty] or Config.Difficulties.Medium
end

------------------------------------------------------------ NAMES + LOOKS (never two the same at once)
local usedNames, usedIds = {}, {}
function M.Identity()
	local pool = {}
	for _, n in Config.Names do if not usedNames[n] then table.insert(pool, n) end end
	if #pool == 0 then pool = Config.Names end
	local name = pool[math.random(#pool)]
	usedNames[name] = true
	local ids = {}
	for _, id in Config.AvatarUserIds do if not usedIds[id] then table.insert(ids, id) end end
	if #ids == 0 then ids = Config.AvatarUserIds end
	local userId = ids[math.random(#ids)]
	usedIds[userId] = true
	return {Name = name, UserId = userId, Level = math.random(Config.LevelMin or 3, Config.LevelMax or 40)}
end
function M.Release(identity)
	if not identity then return end
	usedNames[identity.Name] = nil
	usedIds[identity.UserId] = nil
end

------------------------------------------------------------ THE BODY
-- a real avatar (BotConfig.AvatarUserIds) with the standard fair body + R15
local descCache = {}
local function buildModel(name, userId)
	local desc = descCache[userId]
	if not desc then
		local ok, d = pcall(function() return Players:GetHumanoidDescriptionFromUserId(userId) end)
		if ok and d then
			descCache[userId] = d
			desc = d
		end
	end
	desc = desc and desc:Clone() or Instance.new("HumanoidDescription")
	desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale = 1, 1, 1, 1
	desc.BodyTypeScale, desc.ProportionScale = 0, 0
	desc.Torso, desc.LeftArm, desc.RightArm, desc.LeftLeg, desc.RightLeg, desc.Head = 0, 0, 0, 0, 0, 0
	for _, k in {"ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation", "MoodAnimation"} do pcall(function() desc[k] = 0 end) end
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then
		warn("[Bots] couldn't build a body: " .. tostring(model))
		return nil
	end
	model.Name = name
	-- (Roblox's Animate is a LocalScript - it can't run on a server body: this script animates it)
	local animate = model:FindFirstChild("Animate") if animate then animate:Destroy() end
	return model
end

------------------------------------------------------------ ANIMATIONS (the same ones players use)
local function loadTracks(hum, lobby)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local t = {}
	local function load(id, looped, prio)
		if type(id) ~= "string" or not id:match("%d") then return nil end
		local a = Instance.new("Animation") a.AnimationId = id
		local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
		if not ok or not tr then return nil end
		tr.Looped = looped tr.Priority = prio
		return tr
	end
	local A, C = MoveCfg.Anims or {}, Combat.Animations or {}
	local function cid(n) return type(C[n]) == "table" and C[n].Id or (type(C[n]) == "string" and C[n]) or nil end
	-- (in the lobby: the normal idle a player has there, not the fighting one)
	t.Idle = load((not lobby and cid("FightIdle")) or A.Idle, true, Enum.AnimationPriority.Idle)
	t.Walk = load(A.Walk, true, Enum.AnimationPriority.Movement)
	t.Run = load(A.RunFight or A.Run, true, Enum.AnimationPriority.Movement)
	t.Jump = load(A.Jump, false, Enum.AnimationPriority.Movement)
	t.Fall = load(A.Fall, true, Enum.AnimationPriority.Movement)
	t.Slide = load(A.Slide, true, Enum.AnimationPriority.Action)
	t.Climb = load(A.Climb, false, Enum.AnimationPriority.Action)
	t.Hold = not lobby and load(cid("ItemHold"), true, Enum.AnimationPriority.Action) or nil
	t.Throw = load(cid("Throw"), false, Enum.AnimationPriority.Action2)
	t.Swing = load(cid("Swing") or cid("Melee"), false, Enum.AnimationPriority.Action2)
	return t
end

------------------------------------------------------------ WHO TO FIGHT
-- (a Player has no .Model - asking for it errors, so check what it is first)
local function charOf(e) if typeof(e) == "Instance" then return e.Character end return e.Model end
local function aliveRoot(e)
	local c = charOf(e)
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if h and r and h.Health > 0 then return r, h, c end
	return nil
end
local function enemiesOf(bot)
	local list = {}
	if bot.MatchId then
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("MatchId") == bot.MatchId and p:GetAttribute("MatchTeam") ~= bot.Team
				and p:GetAttribute("InArena") and not p:GetAttribute("Spectating") then
				table.insert(list, p)
			end
		end
		for _, b in bots do if b ~= bot and b.MatchId == bot.MatchId and b.Team ~= bot.Team and b.Alive then table.insert(list, b) end end
	elseif bot.Target and bot.Target.Parent then
		table.insert(list, bot.Target)
	end
	return list
end
local function nearestEnemy(bot)
	local best, bestD
	for _, e in enemiesOf(bot) do
		local r = aliveRoot(e)
		if r then
			local d = (r.Position - bot.Root.Position).Magnitude
			if not bestD or d < bestD then best, bestD = e, d end
		end
	end
	return best, bestD
end
local function canSee(bot, c)
	local head = bot.Model:FindFirstChild("Head")
	local tgt = c and (c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart"))
	if not head or not tgt then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {bot.Model, c, folder}
	return workspace:Raycast(head.Position, tgt.Position - head.Position, params) == nil
end

------------------------------------------------------------ ATTACKS (the same damage as a player's)
local function hurt(bot, victimChar, amount, isHead, isMelee)
	local vh = victimChar:FindFirstChildOfClass("Humanoid")
	if not vh or vh.Health <= 0 then return end
	local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
	if victimPlayer and (victimPlayer:GetAttribute("AdminGod") or victimPlayer:GetAttribute("Spectating")) then return end
	if victimChar:FindFirstChildOfClass("ForceField") then return end
	vh:TakeDamage(amount)
	-- who did it (the match / kill feed read these)
	victimChar:SetAttribute("LastHitByBot", bot.Name)
	vh:SetAttribute("LastHitByBotAt", os.clock())
	if M.OnHit then
		local ok, err = pcall(M.OnHit, bot, victimChar, amount, isHead, isMelee, vh.Health <= 0)
		if not ok then warn("[Bots] OnHit: " .. tostring(err)) end
	end
end
local function locked(bot, shooting)
	if bot:GetAttribute("Frozen") or bot:GetAttribute("CombatLocked") then return true end
	return shooting and bot:GetAttribute("ShootLocked") == true
end
local function throwAt(bot, c, D)
	local head = c:FindFirstChild("Head")
	local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart")
	local bHead = bot.Model:FindFirstChild("Head")
	if not (head and torso and bHead) then return end
	if bot.Tracks.Throw then bot.Tracks.Throw:Play(0.05) end
	task.wait(0.12) -- (a short wind-up, so you can see it coming)
	if not bot.Alive or not c.Parent or locked(bot, true) then return end
	local held = bot.Model:FindFirstChild("HeldBalloon")
	local hand = bot.Model:FindFirstChild("RightHand") or bHead
	local from = (held and held:IsA("BasePart") and held.Position) or (hand.Position + Vector3.new(0, 1, 0))
	local hit = math.random() * 100 < D.Accuracy
	local isHead = hit and math.random() * 100 < (D.Headshots or 0)
	local to
	if hit then
		to = (isHead and head or torso).Position
	else
		local side = torso.CFrame.RightVector * ((math.random() < 0.5 and -1 or 1) * (2.5 + math.random() * 3))
		to = torso.Position + side + Vector3.new(0, math.random() * 2.5 - 0.8, 0)
		to = from + (to - from).Unit * ((to - from).Magnitude + 25)
	end
	if Effect then Effect:FireAllClients("Shot", {shooter = {Character = bot.Model}, from = from, to = to, pop = hit}) end
	if M.OnShot then pcall(M.OnShot, bot, from, to, hit) end
	-- the balloon leaves the hand and grows back over the reload, like a player's
	if held and held:IsA("BasePart") then
		local keep = held:GetAttribute("BotBaseT") or held.Transparency
		held:SetAttribute("BotBaseT", keep)
		held.Transparency = 1
		task.delay(Combat.ShootCooldown or 0.8, function() if held.Parent then TweenService:Create(held, TweenInfo.new(Combat.InflateTime or 0.2), {Transparency = keep}):Play() end end)
	end
	if hit then
		task.delay(math.min((to - from).Magnitude / 300, 0.3), function()
			if bot.Alive and c.Parent then hurt(bot, c, isHead and Combat.HeadshotDamage or Combat.BodyshotDamage, isHead, false) end
		end)
	end
end
local function swingAt(bot, c, D)
	if bot.Tracks.Swing then bot.Tracks.Swing:Play(0.05) end
	if Effect then Effect:FireAllClients("Swing", {player = {Character = bot.Model}}) end
	task.wait(0.1)
	if not bot.Alive or not c.Parent or locked(bot, false) then return end
	local r = c:FindFirstChild("HumanoidRootPart")
	if r and (r.Position - bot.Root.Position).Magnitude <= (Combat.MeleeRange or 6) + 1 and math.random() * 100 < D.MeleeAccuracy then
		hurt(bot, c, Combat.MeleeDamage or 75, false, true)
	end
end

------------------------------------------------------------ MOVING
local climbParams = RaycastParams.new()
climbParams.FilterType = Enum.RaycastFilterType.Exclude
local function obstacleAhead(bot, dir)
	climbParams.FilterDescendantsInstances = {bot.Model, folder}
	local knee = bot.Root.Position - Vector3.new(0, 1.5, 0)
	local hit = workspace:Raycast(knee, dir * 3.5, climbParams)
	if not hit or not hit.Instance.CanCollide then return nil end
	-- how tall is it? (look down from above for its top)
	local top = workspace:Raycast(hit.Position + dir * 0.6 + Vector3.new(0, 25, 0), Vector3.new(0, -30, 0), climbParams)
	return top and (top.Position.Y - (bot.Root.Position.Y - 3)) or 30
end
local function playMove(bot, name, speed)
	if bot.Move ~= name then
		for n, tr in {Idle = bot.Tracks.Idle, Walk = bot.Tracks.Walk, Run = bot.Tracks.Run, Fall = bot.Tracks.Fall, Slide = bot.Tracks.Slide} do
			if tr then if n == name then tr:Play(0.15) elseif tr.IsPlaying then tr:Stop(0.15) end end
		end
		bot.Move = name
	end
	local tr = bot.Tracks[name]
	if tr and speed then tr:AdjustSpeed(speed) end
end

------------------------------------------------------------ THE BRAIN (10 times a second)
local function think(bot, dt)
	local D = bot.D
	local now = os.clock()
	local hum, root = bot.Humanoid, bot.Root
	if bot:GetAttribute("Frozen") or root.Anchored then hum:Move(Vector3.zero) playMove(bot, "Idle") return end
	local enemy, dist = nearestEnemy(bot)
	local er, ec
	if enemy then
		local r, _, c = aliveRoot(enemy)
		er, ec = r, c
	end
	local moveDir = Vector3.zero
	local speed = MoveCfg.WalkSpeed or 16
	if er then
		local flat = Vector3.new(er.Position.X - root.Position.X, 0, er.Position.Z - root.Position.Z)
		local toward = flat.Magnitude > 0.1 and flat.Unit or root.CFrame.LookVector
		local side = Vector3.new(-toward.Z, 0, toward.X)
		-- strafe one way, then the other (harder to hit)
		if now >= (bot.NextStrafe or 0) then
			bot.StrafeDir = (math.random() < 0.5) and -1 or 1
			bot.NextStrafe = now + D.StrafeChange * (0.6 + math.random() * 0.8)
			bot.Sprinting = math.random() < D.SprintChance
		end
		if dist > D.PreferMax then moveDir = toward + side * bot.StrafeDir * 0.35
		elseif dist < D.PreferMin then moveDir = -toward + side * bot.StrafeDir * 0.6
		else moveDir = side * bot.StrafeDir + toward * (math.random() - 0.5) * 0.3 end
		if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
		speed = bot.Sprinting and (MoveCfg.SprintSpeed or 26) or (MoveCfg.WalkSpeed or 16)
		-- face them (how fast = AimTurnSpeed)
		local want = CFrame.lookAt(root.Position, root.Position + toward)
		bot.Align.CFrame = bot.Align.CFrame:Lerp(want.Rotation, math.min(1, dt * D.AimTurnSpeed))
		-- ATTACKS: it has to have seen them for ReactionTime first
		local seen = canSee(bot, ec)
		if seen then bot.SeenSince = bot.SeenSince or now else bot.SeenSince = nil end
		if seen and now - bot.SeenSince >= D.ReactionTime and not bot.Busy and not locked(bot, false) then
			if dist <= (Combat.MeleeRange or 6) + 1.5 and now >= (bot.NextSwing or 0) then
				bot.NextSwing = now + (Combat.MeleeCooldown or 0.75) + 0.2
				bot.Busy = true
				task.spawn(function() pcall(swingAt, bot, ec, D) bot.Busy = false end)
			elseif dist > 7 and now >= (bot.NextThrow or 0) and not locked(bot, true) then
				bot.NextThrow = now + (Combat.ShootCooldown or 0.8) + (Combat.InflateTime or 0) + D.ThrowDelay * (0.6 + math.random() * 0.8)
				bot.Busy = true
				task.spawn(function() pcall(throwAt, bot, ec, D) bot.Busy = false end)
			end
		end
	else
		bot.SeenSince = nil
	end
	-- SLIDE (while running)
	if bot.SlideUntil and now < bot.SlideUntil then
		speed = MoveCfg.SlideSpeed or 42
		moveDir = bot.SlideDir
	elseif moveDir.Magnitude > 0 and bot.Sprinting and now >= (bot.NextSlide or 0) and math.random() < D.SlideChance * dt then
		bot.SlideUntil = now + 0.55
		bot.SlideDir = moveDir
		bot.NextSlide = now + 0.55 + (MoveCfg.SlideCooldown or 0.6) + 1
		local model = bot.Model
		model:SetAttribute("Sliding", true)
		task.delay(0.55, function() if model.Parent then model:SetAttribute("Sliding", nil) end end)
	end
	-- JUMP / CLIMB what's in the way, and the odd dodge jump
	if moveDir.Magnitude > 0 then
		local h = obstacleAhead(bot, moveDir)
		if h then
			if h <= 6.5 then
				hum.Jump = true
			elseif D.Climb and h <= (D.ClimbMax or 16) and now >= (bot.NextClimb or 0) then
				bot.NextClimb = now + 1
				if bot.Tracks.Climb then bot.Tracks.Climb:Play(0.05) end
				root.AssemblyLinearVelocity = Vector3.new(moveDir.X * 6, math.sqrt(2 * workspace.Gravity * (h + 2)), moveDir.Z * 6)
			else
				-- too tall: go round it
				moveDir = Vector3.new(-moveDir.Z, 0, moveDir.X) * (bot.StrafeDir or 1)
			end
		elseif math.random() < D.JumpChance * dt and er then
			hum.Jump = true
		end
	end
	hum.WalkSpeed = speed
	hum:Move(moveDir)
	-- animation by how it's really moving
	local v = root.AssemblyLinearVelocity
	local fs = Vector3.new(v.X, 0, v.Z).Magnitude
	if bot.SlideUntil and now < bot.SlideUntil then playMove(bot, "Slide")
	elseif hum.FloorMaterial == Enum.Material.Air and v.Y < -3 then playMove(bot, "Fall")
	elseif fs > 0.8 then
		if fs > (MoveCfg.WalkSpeed or 16) + 1 then playMove(bot, "Run", math.clamp(fs / (MoveCfg.SprintSpeed or 26), 0.6, 1.5))
		else playMove(bot, "Walk", math.clamp(fs / (MoveCfg.WalkSpeed or 16), 0.5, 1.5)) end
	else playMove(bot, "Idle") end
end

------------------------------------------------------------ A BOT (the "player" - its body comes and goes)
local Bot = {}
Bot.__index = Bot
function Bot:SetAttribute(k, v)
	self.Attrs[k] = v
	self.Tag:SetAttribute(k, v)
	if self.Model and self.Model.Parent then self.Model:SetAttribute(k, v) end
end
function Bot:GetAttribute(k)
	return self.Attrs[k]
end

function M.New(opts)
	opts = opts or {}
	if not Config.Enabled and not opts.Force then return nil end
	local id = opts.Identity or M.Identity()
	local tag = Instance.new("Configuration")
	tag.Name = id.Name
	local bot = setmetatable({
		Name = id.Name, DisplayName = id.Name, UserId = id.UserId, Identity = id, IsBot = true,
		Team = opts.Team, MatchId = opts.MatchId, Target = opts.Target, D = diff(opts.Difficulty),
		Alive = false, Attrs = {}, Tag = tag, Tracks = {},
		DespawnOnDeath = opts.DespawnOnDeath, DespawnAfter = opts.DespawnAfter,
	}, Bot)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("BotName", id.Name)
	bot:SetAttribute("BotUserId", id.UserId)
	bot:SetAttribute("Level", id.Level or 1)
	bot:SetAttribute("Device", "PC")
	bot:SetAttribute("Ping", math.random(25, 90))
	if opts.MatchId then bot:SetAttribute("MatchId", opts.MatchId) end
	if opts.Team then bot:SetAttribute("MatchTeam", opts.Team) end
	tag.Parent = tagFolder
	bots[bot] = bot
	return bot
end

-- (re)builds the bot's body at cf (yields while the avatar loads). Returns true when it's standing there.
-- lobby = true: standing around like a player in the lobby (no balloon, normal idle) - the bots waiting on a pad
function M.Place(bot, cf, lobby)
	if not bots[bot] then return false end
	local old = bot.Model
	bot.Alive = false
	if bot.DiedConn then bot.DiedConn:Disconnect() bot.DiedConn = nil end
	local model = buildModel(bot.Name, bot.UserId)
	if old then old:Destroy() end
	if not model or not bots[bot] then
		if model then model:Destroy() end
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	model.PrimaryPart = root
	hum.DisplayName = bot.Name
	hum.AutoRotate = false
	hum.BreakJointsOnDeath = false
	model:SetAttribute("CustomRespawn", true) -- (the dummy respawner leaves it alone)
	for k, v in bot.Attrs do model:SetAttribute(k, v) end
	model:PivotTo(cf)
	-- it always faces where it's looking (like a player in first person)
	local att = Instance.new("Attachment", root)
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = true
	align.CFrame = cf.Rotation
	align.Parent = root
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	bot.Model, bot.Character, bot.Humanoid, bot.Root, bot.Align = model, model, hum, root, align
	bot.Move, bot.Busy, bot.SeenSince, bot.SlideUntil = nil, false, nil, nil
	model.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	-- (BalloonCombatServer registers it as a target: health, ragdoll on death)
	local t0 = os.clock()
	while not model:GetAttribute("CombatRegistered") and os.clock() - t0 < 2 do task.wait() end
	hum.MaxHealth = Combat.MaxHealth or 100
	hum.Health = hum.MaxHealth
	bot.Tracks = loadTracks(hum, lobby)
	if bot.Tracks.Idle then bot.Tracks.Idle:Play() end
	if lobby then
		bot.Alive = true
		return true
	end
	-- the balloon arm stays still like a player's (players' screens hold their own arm still; a bot's is done here):
	-- the right arm's joints become welds, so the walk / idle animations can't swing the balloon around
	local armParts = {RightUpperArm = true, RightLowerArm = true, RightHand = true}
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 and armParts[m.Part1.Name] then
			local w = Instance.new("Weld")
			w.Name = m.Name -- (BalloonCombatServer still finds "RightShoulder" if it raises the arm)
			w.Part0, w.Part1, w.C0, w.C1 = m.Part0, m.Part1, m.C0, m.C1
			local parent = m.Parent
			m:Destroy()
			w.Parent = parent
		elseif m:IsA("AnimationConstraint") and m.Attachment0 and m.Attachment1 and m.Attachment1.Parent
			and armParts[m.Attachment1.Parent.Name] then
			-- NEW AVATAR JOINTS (no Motor6Ds): the animated joint goes off and a rigid one holds the arm in its rest pose
			local r = Instance.new("RigidConstraint")
			r.Name = m.Name .. "Hold"
			r.Attachment0, r.Attachment1 = m.Attachment0, m.Attachment1
			r.Parent = m.Parent
			m.Enabled = false
		end
	end
	-- a balloon in its hand, like a player's
	local bcs = SSS:FindFirstChild("BalloonCombatServer")
	local give = bcs and bcs:FindFirstChild("GiveBalloon")
	if give then
		local ok, err = pcall(give.Invoke, give, model)
		if not ok then warn("[Bots] GiveBalloon: " .. tostring(err)) end
	else
		warn("[Bots] BalloonCombatServer has no GiveBalloon - bots won't hold a balloon (use the updated BalloonCombatServer)")
	end
	if bot.Tracks.Hold then bot.Tracks.Hold:Play(0.2) end
	bot.Alive = true
	bot.DiedConn = hum.Died:Connect(function()
		if not bot.Alive or bot.Model ~= model then return end
		bot.Alive = false
		hum:Move(Vector3.zero)
		align.Enabled = false
		-- (the stiff balloon arm goes limp with the rest of the body)
		for _, r in model:GetDescendants() do if r:IsA("RigidConstraint") and r.Name:match("Hold$") then r:Destroy() end end
		M.Died:Fire(bot)
		if bot.DespawnOnDeath then
			task.delay(bot.DespawnAfter or 4, function() if bot.Model == model and not bot.Alive then M.Despawn(bot) end end)
		end
	end)
	return true
end

-- quick test bot (admin / Studio): spawns straight away and goes when it dies
function M.Spawn(opts)
	opts = opts or {}
	if opts.DespawnOnDeath == nil then opts.DespawnOnDeath = true end
	local bot = M.New(opts)
	if not bot then return nil end
	if not M.Place(bot, opts.CFrame or CFrame.new(0, 10, 0)) then
		M.Despawn(bot)
		return nil
	end
	return bot
end

-- keepIdentity = true: its name / look stay reserved (the same bot is about to be made again somewhere else)
function M.Despawn(bot, keepIdentity)
	if not bot then return end
	bots[bot] = nil
	bot.Alive = false
	if bot.DiedConn then bot.DiedConn:Disconnect() bot.DiedConn = nil end
	if not keepIdentity then M.Release(bot.Identity) end
	if bot.Model then bot.Model:Destroy() end
	if bot.Tag then bot.Tag:Destroy() end
end
function M.All() local t = {} for b in bots do table.insert(t, b) end return t end
function M.ByModel(model) for b in bots do if b.Model == model then return b end end return nil end
function M.IsBot(x) return type(x) == "table" and x.IsBot == true end
function M.Config() return Config end

RunService.Heartbeat:Connect(function(dt)
	for b in bots do
		if b.Alive and b.Model and b.Model.Parent and b.Root.Parent then
			b.acc = (b.acc or 0) + dt
			if b.acc >= 0.1 then
				local step = b.acc
				b.acc = 0
				local ok, err = pcall(think, b, step)
				if not ok then warn("[Bots] " .. tostring(err)) end
			end
		end
	end
end)

return M
