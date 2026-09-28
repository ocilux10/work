-- BALLOON COMBAT – SERVER
-- All tweakable numbers live in ReplicatedStorage > BalloonCombat > Config.
-- Hook XP / stats to the "PlayerKilled" BindableEvent parented to this script:
--   script.PlayerKilled.Event:Connect(function(killerPlayer, victimModel, victimPlayer, tags) ... end)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local folder = RS:WaitForChild("BalloonCombat")
local Config = require(folder:WaitForChild("Config"))
local Remotes = folder:WaitForChild("Remotes")
local SwingRemote, ShootRemote, Effect = Remotes.Swing, Remotes.Shoot, Remotes.Effect

local PlayerKilled = Instance.new("BindableEvent")
PlayerKilled.Name = "PlayerKilled"
PlayerKilled.Parent = script
-- fired on every hit that does damage: (attackerPlayer, victimModel, victimPlayer, damage) - used for assists
local PlayerDamaged = Instance.new("BindableEvent")
PlayerDamaged.Name = "PlayerDamaged"
PlayerDamaged.Parent = script
-- fired on every balloon shot: (player, fromPos, toPos, hitSomething) - used for the kill replay
local PlayerShot = Instance.new("BindableEvent")
PlayerShot.Name = "PlayerShot"
PlayerShot.Parent = script
-- fired on every melee swing: (player) - used for the kill replay
local PlayerSwung = Instance.new("BindableEvent")
PlayerSwung.Name = "PlayerSwung"
PlayerSwung.Parent = script

------------------------------------------------------------ BALLOON TEMPLATE
local source = SS:WaitForChild(Config.BalloonName)
local template = source:Clone()
template.Name = "BalloonTemplate"
template.Anchored = false
template.CanCollide = false
template.CanQuery = false
template.CanTouch = false
template.Massless = true
template.Parent = folder -- replicated copy so clients can build the viewmodel

local function scaleBalloon(part, s)
	part.Size *= s
	for _, a in part:GetChildren() do
		if a:IsA("Attachment") then a.Position *= s end
		if a:IsA("Attachment") then
			for _, b in a:GetChildren() do
				if b:IsA("Beam") then b.Width0 *= s b.Width1 *= s end
			end
		end
	end
	-- skin VFX (ServerStorage > Balloon: rings / glow / particles) shrink and grow with the balloon too
	for _, d in part:GetDescendants() do
		if d:IsA("Beam") and d.Name:sub(1, 3) == "FX_" then
			d.Width0 *= s d.Width1 *= s d.CurveSize0 *= s d.CurveSize1 *= s
		elseif d:IsA("ParticleEmitter") then
			local kps = {}
			for _, k in d.Size.Keypoints do table.insert(kps, NumberSequenceKeypoint.new(k.Time, k.Value * s, k.Envelope * s)) end
			d.Size = NumberSequence.new(kps)
			d.Speed = NumberRange.new(d.Speed.Min * s, d.Speed.Max * s)
		elseif d:IsA("PointLight") then
			d.Range *= s
		end
	end
end

------------------------------------------------------------ STATE
local state = {} -- [player] = {lastSwing, lastShot}
local lastHit = {} -- [humanoid] = {dir=Vector3, time}

local function getState(p)
	local st = state[p]
	if not st then st = {lastSwing = 0, lastShot = 0} state[p] = st end
	return st
end

local function aliveCharacter(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and char:FindFirstChild("Head") then return char, hum end
end

local function humanoidFromPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then return hum, model end
		model = model:FindFirstAncestorOfClass("Model")
	end
end

local function isHeadPart(part)
	if part.Name == "Head" then return true end
	if part:FindFirstAncestorOfClass("Accessory") then
		for _, w in part:GetChildren() do
			if w:IsA("JointInstance") or w:IsA("WeldConstraint") then
				if (w.Part0 and w.Part0.Name == "Head") or (w.Part1 and w.Part1.Name == "Head") then return true end
			end
		end
		-- fallback: accessory attached with a head attachment (hats, hair, face, earbuds...)
		local att = part:FindFirstChildWhichIsA("Attachment")
		if att then
			local n = att.Name
			return n == "HatAttachment" or n == "HairAttachment" or n == "FaceFrontAttachment" or n == "FaceCenterAttachment"
		end
		return false
	end
	return false
end

local function displayName(model)
	local p = Players:GetPlayerFromCharacter(model)
	return p and NameBadge.Of(p) or model.Name, p
end

------------------------------------------------------------ RAGDOLL
local function ragdoll(model, hum)
	if model:GetAttribute("Ragdolled") then return end
	model:SetAttribute("Ragdolled", true)
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 then
			local a0 = Instance.new("Attachment") a0.Name = "RagA0" a0.CFrame = m.C0 a0.Parent = m.Part0
			local a1 = Instance.new("Attachment") a1.Name = "RagA1" a1.CFrame = m.C1 a1.Parent = m.Part1
			local bs = Instance.new("BallSocketConstraint")
			bs.Attachment0 = a0
			bs.Attachment1 = a1
			bs.LimitsEnabled = true
			bs.UpperAngle = 60
			bs.TwistLimitsEnabled = true
			bs.TwistLowerAngle = -45
			bs.TwistUpperAngle = 45
			bs.Parent = m.Part0
			m.Enabled = false
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false -- anchored dummies need this to fall
			if not p:FindFirstAncestorOfClass("Accessory") and p.Name ~= "HeldBalloon" then
				p.CanCollide = (p ~= root)
			end
			if not p.Anchored then pcall(function() p:SetNetworkOwner(nil) end) end
		end
	end
	hum.PlatformStand = true
	local info = lastHit[hum]
	if info and os.clock() - info.time < 1 then
		local v = info.dir.Unit * Config.RagdollFling + Vector3.new(0, Config.RagdollUpwardFling, 0)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and not p.Anchored then
				p.AssemblyLinearVelocity = v
			end
		end
	end
end

------------------------------------------------------------ HUMANOID SETUP
-- HEALTH REGEN: after Config.RegenDelay seconds without taking damage, heal Config.RegenPerSecond HP/s
local lastDamaged = {} -- [humanoid] = os.clock() of last damage

local function setupHumanoid(model, hum)
	hum.MaxHealth = Config.MaxHealth
	hum.Health = Config.MaxHealth
	local prev = hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < prev then lastDamaged[hum] = os.clock() end
		prev = h
	end)
	hum.BreakJointsOnDeath = not Config.RagdollOnDeath
	hum.Died:Connect(function()
		if Config.RagdollOnDeath then ragdoll(model, hum) end
	end)
end

------------------------------------------------------------ HELD BALLOON (what other players see)
-- raise the right arm so the character visibly holds the balloon up (replicates to everyone)
local function getShoulder(char)
	local torso = char:FindFirstChild("Torso")
	local m = torso and torso:FindFirstChild("Right Shoulder")
	if m then return m, false end
	local ua = char:FindFirstChild("RightUpperArm")
	m = ua and ua:FindFirstChild("RightShoulder")
	return m, true
end
local function raiseArm(char, on)
	local motor, r15 = getShoulder(char)
	if not motor then return end
	-- remember the arm's normal pose on the joint itself (survives between calls)
	if motor:GetAttribute("HoldBaseC0") == nil then motor:SetAttribute("HoldBaseC0", motor.C0) end
	local base = motor:GetAttribute("HoldBaseC0")
	local a = math.rad(on and (Config.HoldArmRaise or 80) or 0)
	-- live servers can have the shoulder joint locked ("C0 is read only"): then the arm just isn't raised,
	-- but the balloon must still be given (that error used to stop the balloon from ever being created)
	local ok = pcall(function()
		motor.C0 = base * (r15 and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, 0, a))
	end)
	if not ok then return nil end
	return motor
end

-- the balloon this player has equipped (ReplicatedStorage > BalloonSkins), ready to hold
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local function balloonFor(char)
	local p = Players:GetPlayerFromCharacter(char)
	local b = p and Skins.Model(p:GetAttribute("EquippedSkin")) or template:Clone()
	b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.Massless = false, false, false, false, true
	return b
end

local function giveBalloon(char)
	-- R6 "Right Arm" or R15 "RightHand", whichever shows up first
	local hand = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
	local t0 = os.clock()
	while not hand and os.clock() - t0 < 3 do
		task.wait()
		hand = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
	end
	if not hand then return end
	local old = char:FindFirstChild("HeldBalloon")
	if old then old:Destroy() end
	local b = balloonFor(char)
	b.Name = "HeldBalloon"
	-- size in hand: Config.HeldBalloonScale (all balloons) x that balloon's Size in BalloonSkins > SkinConfig
	local owner = Players:GetPlayerFromCharacter(char)
	scaleBalloon(b, Config.HeldBalloonScale * Skins.Size(owner and owner:GetAttribute("EquippedSkin")))
	local grip = hand:FindFirstChild("RightGripAttachment")
	local knot = b:FindFirstChild("StringPoint1")
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = b
	-- raise the arm, then counter-rotate the balloon so it stays upright in the raised hand
	local motor
	if (Config.HoldArmRaise or 0) ~= 0 then
		local okRaise, m = pcall(raiseArm, char, true)
		motor = okRaise and m or nil
	end
	local upright = CFrame.new()
	if motor then upright = (motor.C0 * motor.C1:Inverse()).Rotation:Inverse() end
	-- the balloon floats on a string above the hand, a little out to the side so it's clear of the arm
	local gripPos = grip and grip.Position or Vector3.new(0, -hand.Size.Y / 2, 0)
	local side = Config.HeldBalloonSide or 0.9
	local len = Config.HeldStringLength or 2.2
	local knotOffset = knot and knot.Position or Vector3.new(0, -b.Size.Y / 2, 0)
	w.C0 = CFrame.new(gripPos) * upright * CFrame.new(side, len, 0) * CFrame.Angles(0, 0, -math.rad(12))
	w.C1 = CFrame.new(knotOffset)
	w.Parent = b
	-- the string: hand -> bottom of the balloon
	local a0 = Instance.new("Attachment")
	a0.Name = "HeldStringHand"
	a0.Position = gripPos
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Name = "HeldStringKnot"
	a1.Position = knotOffset
	a1.Parent = b
	local str = Instance.new("Beam")
	str.Name = "HeldString"
	str.Attachment0, str.Attachment1 = a0, a1
	str.Width0, str.Width1 = Config.HeldStringWidth or 0.05, Config.HeldStringWidth or 0.05
	str.Color = ColorSequence.new(Config.HeldStringColor or Color3.fromRGB(235, 235, 235))
	str.FaceCamera = true
	str.Segments = 6
	str.CurveSize0, str.CurveSize1 = 0.25, -0.15 -- a little slack
	str.LightInfluence = 1
	str.Parent = b
	-- tidy up the hand attachment with the balloon
	b.Destroying:Connect(function() a0:Destroy() end)
	b.AncestryChanged:Connect(function(_, parent) if not parent then a0:Destroy() end end)
	b.Parent = char
end

local function setHeldVisible(char, visible)
	local b = char and char:FindFirstChild("HeldBalloon")
	if not b then return end
	b.Transparency = visible and 0 or 1
	for _, d in b:GetDescendants() do
		if d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("Light") then d.Enabled = visible end
	end
end

------------------------------------------------------------ DAMAGE
-- WHO CAN HURT WHO
-- NPCs / dummies: anyone in combat mode can hit them (practice).
-- Players: ONLY when both are in the same match -> both have the same "MatchId" attribute.
--   Your future game / matchmaking script does:   player:SetAttribute("InArena", true)   (combat mode on)
--                                                 player:SetAttribute("MatchId", "<same id for both fighters>")
--   and clears MatchId (set it to nil) when the match ends.
-- In the practice arena nobody has a MatchId, so players can't damage each other.
local function canDamage(attacker, victimPlayer)
	if not victimPlayer then return true end
	if victimPlayer == attacker then return false end
	local a, v = attacker:GetAttribute("MatchId"), victimPlayer:GetAttribute("MatchId")
	if a == nil or a ~= v then return false end
	-- no friendly fire: same MatchTeam can't hurt each other (set by MatchmakingServer)
	local ta = attacker:GetAttribute("MatchTeam")
	if ta ~= nil and ta == victimPlayer:GetAttribute("MatchTeam") then return false end
	return true
end

local function applyDamage(attacker, hum, model, damage, hitPos, isHead, isMelee, dir)
	if hum.Health <= 0 then return end
	local victimName, victimPlayer = displayName(model)
	if not canDamage(attacker, victimPlayer) then return end
	if Config.TeamCheck and victimPlayer and attacker.Team and victimPlayer.Team == attacker.Team and not attacker.Neutral then
		return
	end
	if model:FindFirstChildOfClass("ForceField") then return end

	lastHit[hum] = {dir = dir, time = os.clock()}
	local attackerChar, attackerHum = aliveCharacter(attacker)
	local distance = attackerChar and math.floor((attackerChar.Head.Position - hitPos).Magnitude + 0.5) or 0
	local airborne = attackerHum and (function()
		local st = attackerHum:GetState()
		return st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping
	end)()

	hum:TakeDamage(damage)
	PlayerDamaged:Fire(attacker, model, victimPlayer, damage, hitPos, isHead, isMelee)
	Effect:FireClient(attacker, "Damage", {pos = hitPos, amount = damage, head = isHead, melee = isMelee, target = model})

	if hum.Health <= 0 then
		local tags = {}
		if isHead then table.insert(tags, {name = "HEADSHOT", xp = Config.XP.Headshot}) end
		if airborne then table.insert(tags, {name = "JUMPSHOT", xp = Config.XP.Jumpshot}) end
		local longShot = not isMelee and distance >= (Config.LongShotDistance or 75)
		if longShot then table.insert(tags, {name = "LONGSHOT", xp = Config.XP.LongShot or 25}) end
		if isMelee then table.insert(tags, {name = "MELEE", xp = Config.XP.Melee}) end
		table.insert(tags, {name = "KILL", xp = Config.XP.Kill})
		-- XP only counts in real matches: dummy / practice kills show +0 XP
		local realKill = victimPlayer ~= nil and attacker:GetAttribute("MatchId") ~= nil
		if not realKill then
			for _, t in tags do t.xp = 0 end
		end
		local totalXP = 0
		for _, t in tags do totalXP += t.xp end
		Effect:FireClient(attacker, "Kill", {victim = victimName, tags = tags, distance = distance, victimModel = model,
			victimUserId = victimPlayer and victimPlayer.UserId or nil})
		-- KILL FEED: in a match only the players in that match see it; in the practice arena only the killer does
		local feed = {killer = NameBadge.Of(attacker), victim = victimName, head = isHead, melee = isMelee,
			distance = distance, longShot = longShot, xp = totalXP, jump = airborne == true,
			killerId = attacker.UserId, victimId = victimPlayer and victimPlayer.UserId or nil}
		local matchId = attacker:GetAttribute("MatchId")
		if matchId ~= nil then
			for _, pl in Players:GetPlayers() do
				if pl:GetAttribute("MatchId") == matchId then Effect:FireClient(pl, "Feed", feed) end
			end
		else
			Effect:FireClient(attacker, "Feed", feed)
		end
		PlayerKilled:Fire(attacker, model, victimPlayer, tags)
	end
end

------------------------------------------------------------ MELEE (hitbox, flat damage)
SwingRemote.OnServerEvent:Connect(function(player, look)
	if not player:GetAttribute("InArena") or player:GetAttribute("CombatLocked") then return end
	if typeof(look) ~= "Vector3" or look.Magnitude < 0.5 or look.Magnitude ~= look.Magnitude then return end
	local char = aliveCharacter(player)
	if not char then return end
	local st = getState(player)
	local now = os.clock()
	if now - st.lastSwing < Config.MeleeCooldown * 0.85 then return end
	if not player:GetAttribute("NoReload") and now - st.lastShot < (Config.ShootCooldown + (Config.InflateTime or 0)) * 0.85 then return end
	st.lastSwing = now
	Effect:FireAllClients("Swing", {player = player})
	PlayerSwung:Fire(player)

	look = look.Unit
	local head = char.Head
	local boxCF = CFrame.lookAt(head.Position, head.Position + look) * CFrame.new(0, 0, -Config.MeleeRange / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char}
	local parts = workspace:GetPartBoundsInBox(boxCF, Vector3.new(Config.MeleeHitboxWidth, Config.MeleeHitboxWidth, Config.MeleeRange), params)

	-- hit the closest humanoid in the box
	local best, bestModel, bestDist, bestPart
	for _, part in parts do
		local hum, model = humanoidFromPart(part)
		if hum and hum.Health > 0 and model ~= char and canDamage(player, Players:GetPlayerFromCharacter(model)) then
			local d = (part.Position - head.Position).Magnitude
			if not bestDist or d < bestDist then
				best, bestModel, bestDist, bestPart = hum, model, d, part
			end
		end
	end
	if best then
		local torso = bestModel:FindFirstChild("UpperTorso") or bestModel:FindFirstChild("Torso") or bestPart
		applyDamage(player, best, bestModel, Config.MeleeDamage, torso.Position, false, true, look)
	end
end)

------------------------------------------------------------ LAG COMPENSATION
-- The shooter aims at where THEIR screen shows the target, which is a little in the past
-- (their ping + Roblox's smoothing of other players). For moving targets that can be several studs off
-- from where the server has them now. So we remember where every character was over the last second
-- and also accept a hit that lines up with where the target was when the shooter saw them.
local HISTORY_TIME = 1
local INTERP_DELAY = 0.1 -- roughly how far behind the client shows other players
local history = {} -- [model] = { {t, rootCF}, ... } oldest first

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local h = history[char]
			if not h then h = {} history[char] = h end
			table.insert(h, {t, root.CFrame})
			while #h > 0 and t - h[1][1] > HISTORY_TIME do table.remove(h, 1) end
		end
	end
	for char in history do
		if not char.Parent then history[char] = nil end
	end
end)

-- where `part` (inside `model`) was at time `t`, using the recorded root position
local function rewoundPosition(model, part, t)
	local h = history[model]
	local root = model:FindFirstChild("HumanoidRootPart")
	if not h or #h == 0 or not root then return nil end
	local cf = h[1][2]
	for i = #h, 1, -1 do
		if h[i][1] <= t then
			local a, b = h[i], h[i + 1]
			if b then
				local alpha = (t - a[1]) / math.max(b[1] - a[1], 1e-4)
				cf = a[2]:Lerp(b[2], math.clamp(alpha, 0, 1))
			else
				cf = a[2]
			end
			break
		end
	end
	-- keep the part's offset from the root (arms/head move with the body)
	return (cf * root.CFrame:ToObjectSpace(part.CFrame)).Position
end

------------------------------------------------------------ SHOOT (hitscan)
local NO_RELOAD_GAP = 0.12 -- seconds between throws when the reload cooldown is off (aim training setting)
local function losClear(origin, target, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local dir = target - origin
	local r = workspace:Raycast(origin, dir, params)
	if not r then return true end
	-- allow the ray to stop on another character (it'd be their body in the way)
	if humanoidFromPart(r.Instance) then return true end
	return (r.Position - origin).Magnitude >= dir.Magnitude - 2
end

ShootRemote.OnServerEvent:Connect(function(player, origin, dir, hitPart, hitPos)
	if not player:GetAttribute("InArena") or player:GetAttribute("CombatLocked") or player:GetAttribute("ShootLocked") then return end
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return end
	if dir.Magnitude < 0.5 or dir.Magnitude ~= dir.Magnitude then return end
	local char = aliveCharacter(player)
	if not char then return end
	local st = getState(player)
	local now = os.clock()
	-- (aim training with Reload Cooldown off = NoReload: only a tiny gap between throws)
	local noReload = player:GetAttribute("NoReload") == true
	local gap = noReload and NO_RELOAD_GAP or (Config.ShootCooldown + (Config.InflateTime or 0))
	if now - st.lastShot < gap * 0.85 then return end
	st.lastShot = now
	dir = dir.Unit

	local head = char.Head
	if (origin - head.Position).Magnitude > 12 then origin = head.Position end

	local endPos = origin + dir * Config.ShootRange
	local hitSomething = false

	if typeof(hitPos) == "Vector3" and (hitPos - origin).Magnitude <= Config.ShootRange + 5 then
		endPos = hitPos
		hitSomething = true
	end

	if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and hitPart:IsDescendantOf(workspace) and hitSomething then
		local hum, model = humanoidFromPart(hitPart)
		if hum and hum.Health > 0 and model ~= char then
			local reach = hitPart.Size.Magnitude / 2 + Config.HitTolerance
			local closeEnough = (hitPart.Position - hitPos).Magnitude <= reach
			if not closeEnough and Players:GetPlayerFromCharacter(model) then
				-- lag compensation: check where the target was when the shooter saw them
				local ok, ping = pcall(function() return player:GetNetworkPing() end)
				local back = math.clamp((ok and ping or 0.1) + INTERP_DELAY, 0, 0.6)
				local past = rewoundPosition(model, hitPart, os.clock() - back)
				closeEnough = past ~= nil and (past - hitPos).Magnitude <= reach
			end
			if closeEnough and losClear(origin, hitPos, {char, model}) then
				local isHead = isHeadPart(hitPart)
				applyDamage(player, hum, model, isHead and Config.HeadshotDamage or Config.BodyshotDamage, hitPos, isHead, false, dir)
			end
		end
	end

	-- visuals for everyone else + hide the balloon until it regrows
	local held = char:FindFirstChild("HeldBalloon")
	local from = held and held.Position or head.Position
	Effect:FireAllClients("Shot", {shooter = player, from = from, to = endPos, pop = hitSomething})
	PlayerShot:Fire(player, from, endPos, hitSomething)
	setHeldVisible(char, false)
	task.delay(noReload and NO_RELOAD_GAP or Config.ShootCooldown, function()
		if player.Character == char then setHeldVisible(char, true) end
	end)
end)

------------------------------------------------------------ PLAYERS
local function onCharacter(player, char)
	-- StreamingEnabled: keep every player's character on every screen all the time. Matches move people
	-- far away (holding spot / arenas); a character that streams out and back in can come back without its
	-- held balloon and with frozen animations / position for the other players.
	pcall(function() char.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	-- no spawn shield: remove the ForceField a SpawnLocation gives (it blocks all damage and shows a bubble)
	char.ChildAdded:Connect(function(c)
		if c:IsA("ForceField") then task.defer(function() c:Destroy() end) end
	end)
	local ff = char:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end
	local hum = char:WaitForChild("Humanoid")
	setupHumanoid(char, hum)
	if player:GetAttribute("InArena") then giveBalloon(char) end
	local st = getState(player)
	st.lastShot = 0
	st.lastSwing = 0
	if not Config.HealthRegen then
		task.spawn(function()
			local regen = char:WaitForChild("Health", 3)
			if regen then regen:Destroy() end
		end)
	end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then onCharacter(p, p.Character) end
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
end
Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

------------------------------------------------------------ LOBBY <-> ARENA
local function hookArena(p)
	p:GetAttributeChangedSignal("InArena"):Connect(function()
		local char = p.Character
		if not char then return end
		if p:GetAttribute("InArena") then
			giveBalloon(char)
			local st = getState(p)
			st.lastShot, st.lastSwing = 0, 0
		else
			local b = char:FindFirstChild("HeldBalloon")
			if b then b:Destroy() end
			raiseArm(char, false)
		end
	end)
end
Players.PlayerAdded:Connect(hookArena)
-- changed balloon while holding one: swap it
local function hookSkin(p)
	p:GetAttributeChangedSignal("EquippedSkin"):Connect(function()
		local char = p.Character
		if char and p:GetAttribute("InArena") and char:FindFirstChild("HeldBalloon") then giveBalloon(char) end
	end)
end
Players.PlayerAdded:Connect(hookSkin)
for _, p in Players:GetPlayers() do hookSkin(p) end
for _, p in Players:GetPlayers() do hookArena(p) end

------------------------------------------------------------ DUMMIES (NPCs in Workspace)
local function registerDummy(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or Players:GetPlayerFromCharacter(model) then return end
	if model:GetAttribute("CombatRegistered") then return end
	model:SetAttribute("CombatRegistered", true)
	-- models with the "CustomRespawn" attribute are respawned by their own script (e.g. TrampolineDummies)
	local backup = (not model:GetAttribute("CustomRespawn") and Config.DummyRespawnTime > 0) and model:Clone() or nil
	if backup then backup:SetAttribute("CombatRegistered", nil) end
	local parent = model.Parent
	setupHumanoid(model, hum)
	hum.Died:Connect(function()
		if not backup then return end
		task.wait(Config.DummyRespawnTime)
		local fresh = backup:Clone()
		model:Destroy()
		fresh.Parent = parent
		registerDummy(fresh)
	end)
end

for _, m in workspace:GetDescendants() do
	if m:IsA("Humanoid") and m.Parent and m.Parent:IsA("Model") then registerDummy(m.Parent) end
end
-- NPCs spawned later (trampoline dummies, respawns) get health / ragdoll / damage too
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		task.defer(function()
			if d.Parent and d.Parent:IsA("Model") then registerDummy(d.Parent) end
		end)
	end
end)

-- regen loop (players only)
task.spawn(function()
	local STEP = 0.1
	while true do
		task.wait(STEP)
		local delay, rate = Config.RegenDelay or 10, Config.RegenPerSecond or 10
		if rate > 0 then
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and hum.Health < hum.MaxHealth
					and os.clock() - (lastDamaged[hum] or 0) >= delay then
					hum.Health = math.min(hum.MaxHealth, hum.Health + rate * STEP)
				end
			end
		end
	end
end)

-- clean old hit info
task.spawn(function()
	while true do
		task.wait(10)
		for hum in lastHit do
			if not hum.Parent then lastHit[hum] = nil end
		end
		for hum in lastDamaged do
			if not hum.Parent then lastDamaged[hum] = nil end
		end
	end
end)
