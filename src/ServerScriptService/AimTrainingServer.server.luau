-- AIM TRAINING (server) - a private practice room per player, entered from the lobby door (ArenaServer asks
-- "Aim Training or Practice Arena?"). Everything the player picks is in their settings (Aim Training menu,
-- GameSettings > the "Target" / "Movement" / "Box" / "Challenge" tabs) and read here live.
-- LOOK: ServerStorage > AimTraining > Room (the room: move / restyle anything, keep "Spawn" and "Board"),
--       Bot (the default bot = a copy of the Noob), Disc (bullseye - "Head" = the middle), Orb ("Head" = the ball).
-- Bots and targets have real match health (BalloonCombat > Config: MaxHealth / HeadshotDamage / BodyshotDamage).
-- Stats go on the player as attributes: AimShots / AimHits / AimHeads / AimKills, AimCh* for the timed challenge,
-- AimBest = best time for the current challenge length (saved).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local GS = require(RS:WaitForChild("GameSettings"))
local Config = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))
local Assets = SS:WaitForChild("AimTraining")
local Combat = script.Parent:WaitForChild("BalloonCombatServer")
local PlayerShot = Combat:WaitForChild("PlayerShot")
local PlayerDamaged = Combat:WaitForChild("PlayerDamaged")
local PlayerKilled = Combat:WaitForChild("PlayerKilled")

local ORIGIN = Vector3.new(-9000, 300, 0) -- rooms are built out here, one after another
local SPACING = 800
local RESPAWN_TIME = {Bot = 0.9, Disc = 0.35, Orbs = 0.1} -- seconds before a dead target comes back
local THROW_SPEED = 85 -- studs / second of the bots' balloons (slow enough to dodge)
local COUNTDOWN = 3

local shared = RS:WaitForChild("AimTraining")
local Remote = shared:FindFirstChild("Remote") or Instance.new("RemoteEvent")
Remote.Name = "Remote"
Remote.Parent = shared
local rooms = workspace:FindFirstChild("AimRooms") or Instance.new("Folder")
rooms.Name = "AimRooms"
rooms.Parent = workspace

local bestStore
pcall(function() bestStore = DataStoreService:GetDataStore("AimTrainingBest_v1") end)
local bestCache = {} -- [userId] = {[goal] = seconds}

local sessions = {} -- [player] = session
local usedSlots = {}

------------------------------------------------------------ SETTINGS (the player's saved prefs over the defaults)
local function settingsOf(p)
	local t = {}
	local raw = p:GetAttribute("Setting_Prefs")
	if type(raw) == "string" then
		local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(d) == "table" then t = d end
	end
	return function(key)
		local v = t[key]
		if v == nil then
			local d = GS.ByKey[key]
			return d and d.Default
		end
		return v
	end
end

------------------------------------------------------------ BOX
local function boxSize(s)
	return s.get("AimBoxWidth"), s.get("AimBoxDepth"), s.get("AimBoxHeight")
end
local function clampInBox(s, pos, margin)
	local w, d = boxSize(s)
	local l = s.boxCF:PointToObjectSpace(pos)
	local mx, mz = math.max(w / 2 - margin, 0), math.max(d / 2 - margin, 0)
	return s.boxCF * Vector3.new(math.clamp(l.X, -mx, mx), l.Y, math.clamp(l.Z, -mz, mz))
end
local function randomInBox(s, margin, y)
	local w, d = boxSize(s)
	local mx, mz = math.max(w / 2 - margin, 0), math.max(d / 2 - margin, 0)
	return s.boxCF * Vector3.new((math.random() * 2 - 1) * mx, y or 0, (math.random() * 2 - 1) * mz)
end

local function buildBox(s)
	if s.box then s.box:Destroy() end
	local get = s.get
	local look = s.spawnCF.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local floorY = s.floorY
	local center = Vector3.new(s.spawnCF.Position.X, floorY, s.spawnCF.Position.Z) + flatLook * get("AimDistance")
	s.boxCF = CFrame.lookAt(center, center + flatLook)
	local w, d, h = boxSize(s)
	local m = Instance.new("Model")
	m.Name = "Box"
	local color = GS.ToColor(get("AimBoxColor"))
	local show = get("AimBoxShow")
	local tr = show and get("AimBoxTransparency") or 1
	local function wall(size, offset)
		local p = Instance.new("Part")
		p.Name = "Wall"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = size
		p.CFrame = s.boxCF * CFrame.new(offset)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = tr
		p.Parent = m
	end
	wall(Vector3.new(w, h, 0.2), Vector3.new(0, h / 2, d / 2))
	wall(Vector3.new(w, h, 0.2), Vector3.new(0, h / 2, -d / 2))
	wall(Vector3.new(0.2, h, d), Vector3.new(w / 2, h / 2, 0))
	wall(Vector3.new(0.2, h, d), Vector3.new(-w / 2, h / 2, 0))
	-- floor tint + outline
	local vol = Instance.new("Part")
	vol.Name = "Volume"
	vol.Anchored, vol.CanCollide, vol.CanQuery, vol.CanTouch, vol.CastShadow = true, false, false, false, false
	vol.Size = Vector3.new(w, h, d)
	vol.CFrame = s.boxCF * CFrame.new(0, h / 2, 0)
	vol.Transparency = 1
	vol.Parent = m
	if show and get("AimBoxOutline") then
		local sb = Instance.new("SelectionBox")
		sb.Adornee = vol
		sb.Color3 = color
		sb.LineThickness = 0.08
		sb.SurfaceTransparency = 1
		sb.Parent = vol
	end
	local tint = Instance.new("Part")
	tint.Name = "FloorTint"
	tint.Anchored, tint.CanCollide, tint.CanQuery, tint.CanTouch, tint.CastShadow = true, false, false, false, false
	tint.Size = Vector3.new(w, 0.05, d)
	tint.CFrame = s.boxCF * CFrame.new(0, 0.05, 0)
	tint.Color = color
	tint.Material = Enum.Material.Neon
	tint.Transparency = show and math.clamp(0.6 + tr * 0.35, 0, 1) or 1
	tint.Parent = m
	m.Parent = s.room
	s.box = m
end

------------------------------------------------------------ TARGETS
local descCache = {} -- [lower username] = HumanoidDescription or false
local function avatarDesc(name)
	if type(name) ~= "string" or name == "" then return nil end
	local key = name:lower()
	if descCache[key] ~= nil then return descCache[key] or nil end
	local desc
	local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
	if ok and id then
		local ok2, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, id)
		if ok2 then desc = d end
	end
	descCache[key] = desc or false
	return desc
end

local ANIMS = {Walk = "rbxassetid://180426354", Idle = "rbxassetid://180435571", Jump = "rbxassetid://125750702"}

local function bottomOffset(model)
	local cf, size = model:GetBoundingBox()
	return model:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
end

local function makeModel(s, kind)
	if kind == "Bot" then
		local name = s.get("AimAvatar")
		local desc = avatarDesc(name)
		if desc then
			local ok, m = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R6)
			if ok and m then
				m.Name = name
				local anim = m:FindFirstChild("Animate") if anim then anim:Destroy() end
				return m
			end
		elseif type(name) == "string" and name ~= "" and not s.warned[name] then
			s.warned[name] = true
			Remote:FireClient(s.player, "Notice", ("Couldn't find a player called %s - using the Noob"):format(name))
		end
		return Assets.Bot:Clone()
	elseif kind == "Disc" then
		return Assets.Disc:Clone()
	end
	local m = Assets.Orb:Clone()
	local size = s.get("AimOrbSize")
	m.Head.Size = Vector3.one * size
	return m
end

local spawnTarget -- forward

local function faceCF(s, pos)
	-- looking at the player (flat), from pos
	local char = s.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local at = root and root.Position or s.spawnCF.Position
	at = Vector3.new(at.X, pos.Y, at.Z)
	if (at - pos).Magnitude < 0.1 then at = pos - s.boxCF.LookVector end
	return CFrame.lookAt(pos, at)
end

local function removeTarget(s, t)
	local i = table.find(s.targets, t)
	if i then table.remove(s.targets, i) end
end

local function onTargetDied(s, t)
	if not t.alive then return end
	t.alive = false
	local kind = t.kind
	if kind ~= "Bot" then
		-- discs / orbs pop straight away
		local head = t.model:FindFirstChild("Head")
		if head then
			local fx = Instance.new("Part")
			fx.Shape = Enum.PartType.Ball
			fx.Anchored, fx.CanCollide, fx.CanQuery, fx.CanTouch = true, false, false, false
			fx.Material = Enum.Material.Neon
			fx.Color = head.Color
			fx.Size = Vector3.one * math.max(head.Size.Y, 1)
			fx.CFrame = head.CFrame
			fx.Parent = s.room
			TweenService:Create(fx, TweenInfo.new(0.2), {Size = fx.Size * 2.2, Transparency = 1}):Play()
			game:GetService("Debris"):AddItem(fx, 0.3)
		end
		task.defer(function() if t.model then t.model:Destroy() end end)
	else
		task.delay(1.2, function() if t.model then t.model:Destroy() end end)
	end
	removeTarget(s, t)
	local token = s.token
	task.delay(RESPAWN_TIME[kind] or 0.8, function()
		if s.alive and s.token == token and #s.targets < s.get("AimCount") then spawnTarget(s) end
	end)
end

spawnTarget = function(s)
	local kind = s.get("AimType")
	if kind ~= "Bot" and kind ~= "Disc" and kind ~= "Orbs" then kind = "Bot" end
	local token = s.token
	local model = makeModel(s, kind) -- (can wait a moment the first time a username is looked up)
	if not s.alive or s.token ~= token or #s.targets >= math.clamp(s.get("AimCount"), 1, 6) then model:Destroy() return end
	-- (avatar models come with the Head as their PrimaryPart: everything here works from the root)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then model.PrimaryPart = hrp end
	model:SetAttribute("CustomRespawn", true) -- (we bring it back, not the combat script)
	model:SetAttribute("AimOwner", s.player.UserId)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or not model.PrimaryPart then model:Destroy() return end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local offY = bottomOffset(model)
	local _, _, h = boxSize(s)
	local t = {model = model, hum = hum, root = model.PrimaryPart, kind = kind, alive = true, sign = math.random() < 0.5 and 1 or -1}
	local size = model:GetExtentsSize()
	local margin = math.max(size.X, size.Z) / 2 + 0.3
	t.margin = margin
	if kind == "Orbs" then
		local r = model.Head.Size.Y / 2
		t.pos = randomInBox(s, r + 0.2, math.clamp(1.5 + math.random() * (h - 3), r + 0.3, math.max(h - r - 0.3, r + 0.3)))
		t.margin = r + 0.2
		t.offY = 0
	else
		t.pos = randomInBox(s, margin, 0)
		t.offY = offY
	end
	model:PivotTo(faceCF(s, t.pos + Vector3.new(0, t.offY, 0)))
	model.Parent = s.targetsFolder
	if kind == "Bot" then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then d.Anchored = false end
		end
		hum.AutoRotate = false
		hum.WalkSpeed = s.get("AimSpeed")
		pcall(function() t.root:SetNetworkOwner(nil) end)
		-- always turned toward you
		local att = Instance.new("Attachment") att.Name = "AimFace" att.Parent = t.root
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.RigidityEnabled = true
		ao.CFrame = t.root.CFrame.Rotation
		ao.Parent = t.root
		t.align = ao
		-- walk / idle animations
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		t.tracks = {}
		for n, id in ANIMS do
			local a = Instance.new("Animation") a.AnimationId = id
			local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
			if ok then t.tracks[n] = tr tr.Looped = n ~= "Jump" end
		end
		if t.tracks.Idle then t.tracks.Idle:Play() end
	else
		for _, d in model:GetDescendants() do if d:IsA("BasePart") then d.Anchored = true end end
	end
	hum.HealthChanged:Connect(function(v) if v <= 0 then onTargetDied(s, t) end end)
	hum.Died:Connect(function() onTargetDied(s, t) end)
	table.insert(s.targets, t)
	-- brain: pick strafes inside the box
	task.spawn(function()
		while t.alive and s.alive do
			local get = s.get
			if not get("AimMoving") then
				t.goal = nil
				task.wait(0.2)
				continue
			end
			local turn = s.boxCF * CFrame.Angles(0, math.rad(get("AimStrafeAngle")), 0)
			local axes = {}
			if get("AimLeftRight") then table.insert(axes, turn.RightVector) end
			if get("AimForwardBack") then table.insert(axes, turn.LookVector) end
			if #axes == 0 then t.goal = nil task.wait(0.2) continue end
			local axis = axes[math.random(#axes)]
			-- mostly side to side like a real player (A / D), sometimes the same way twice
			if math.random() < 0.8 then t.sign = -t.sign end
			local lo, hi = get("AimStrafeMin"), get("AimStrafeMax")
			if hi < lo then lo, hi = hi, lo end
			local dist = lo + math.random() * (hi - lo)
			local cur = t.pos
			local goal = clampInBox(s, cur + axis * t.sign * dist, t.margin)
			if (goal - cur).Magnitude < dist * 0.4 then
				t.sign = -t.sign
				goal = clampInBox(s, cur + axis * t.sign * dist, t.margin)
			end
			if get("AimJump") and math.random(100) <= get("AimJumpChance") then t.jumpAt = os.clock() end
			t.goal = goal
			local timeout = (goal - cur).Magnitude / math.max(get("AimSpeed"), 1) + 0.7
			local t0 = os.clock()
			while t.alive and s.alive and t.goal and os.clock() - t0 < timeout and get("AimMoving") do
				local d = goal - t.pos
				if Vector3.new(d.X, 0, d.Z).Magnitude < 0.5 then break end
				task.wait(0.03)
			end
			t.goal = nil
			local pause = get("AimPause")
			if pause > 0 then task.wait(pause * (0.6 + math.random() * 0.8)) end
		end
	end)
	return t
end

local function clearTargets(s)
	s.token += 1
	for _, t in s.targets do
		t.alive = false
		if t.model then t.model:Destroy() end
	end
	table.clear(s.targets)
end
local function fillTargets(s)
	local n = math.clamp(s.get("AimCount"), 1, 6)
	while #s.targets > n do
		local t = table.remove(s.targets)
		t.alive = false
		t.model:Destroy()
	end
	for _ = #s.targets + 1, n do spawnTarget(s) end
end

------------------------------------------------------------ MOVING THEM (every frame)
RunService.Heartbeat:Connect(function(dt)
	for _, s in sessions do
		if s.alive and s.boxCF then
			local speed = s.get("AimSpeed")
			for _, t in s.targets do
				if t.alive and t.model.Parent then
					if t.kind == "Bot" then
						local root = t.root
						if root.Parent then
							t.pos = root.Position - Vector3.new(0, t.offY, 0)
							t.hum.WalkSpeed = speed
							local moving = false
							if t.goal then
								local d = t.goal - t.pos
								d = Vector3.new(d.X, 0, d.Z)
								if d.Magnitude > 0.3 then t.hum:Move(d.Unit) moving = true else t.hum:Move(Vector3.zero) end
							else
								t.hum:Move(Vector3.zero)
							end
							if t.jumpAt then t.jumpAt = nil t.hum.Jump = true if t.tracks.Jump then t.tracks.Jump:Play(0.1) end end
							-- never outside the box (pushed back in if something shoves them out)
							local inside = clampInBox(s, t.pos, t.margin - 0.3)
							if (Vector3.new(inside.X, 0, inside.Z) - Vector3.new(t.pos.X, 0, t.pos.Z)).Magnitude > 0.5 then
								root.CFrame = CFrame.new(inside + Vector3.new(0, t.offY, 0)) * root.CFrame.Rotation
								root.AssemblyLinearVelocity = Vector3.zero
							end
							if t.align then t.align.CFrame = faceCF(s, root.Position).Rotation end
							local walk, idle = t.tracks.Walk, t.tracks.Idle
							if walk and idle then
								if moving and not walk.IsPlaying then walk:Play(0.15) idle:Stop(0.15)
								elseif not moving and walk.IsPlaying then walk:Stop(0.15) idle:Play(0.15) end
								if walk.IsPlaying then walk:AdjustSpeed(speed / 16) end
							end
						end
					else
						-- discs / orbs slide (no legs)
						if t.goal then
							local d = t.goal - t.pos
							d = Vector3.new(d.X, 0, d.Z)
							local step = math.min(d.Magnitude, speed * dt)
							if step > 0 then t.pos += d.Unit * step end
						end
						t.pos = clampInBox(s, t.pos, t.margin)
						local hop = 0
						if t.jumpAt then
							local a = (os.clock() - t.jumpAt) / 0.55
							if a >= 1 then t.jumpAt = nil else hop = math.sin(a * math.pi) * 4 end
						end
						t.model:PivotTo(faceCF(s, t.pos + Vector3.new(0, t.offY + hop, 0)))
					end
				end
			end
		end
	end
end)

------------------------------------------------------------ BOTS THROWING BACK
-- exactly like a player's throw: it hits (or misses) the moment they throw. Their Accuracy = chance to hit you,
-- Their Headshots = how many of those hits are on your head. You see the same balloon shot players see.
local Effect = RS:WaitForChild("BalloonCombat"):WaitForChild("Remotes"):WaitForChild("Effect")
local function throwAt(s, t)
	local p = s.player
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart"))
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not head or not torso or not hum or hum.Health <= 0 then return end
	local botHead = t.model:FindFirstChild("Head")
	if not botHead then return end
	local hand = t.model:FindFirstChild("Right Arm") or t.model:FindFirstChild("RightHand") or botHead
	local from = hand.Position + Vector3.new(0, 1.2, 0)
	-- can they even see you?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {t.model, char, s.box}
	if workspace:Raycast(botHead.Position, torso.Position - botHead.Position, params) then return end
	local hit = math.random() * 100 < s.get("AimShootAccuracy")
	local isHead = hit and math.random() * 100 < s.get("AimShootHeadshot")
	local to
	if hit then
		to = isHead and head.Position or torso.Position
	else
		-- a near miss past you
		local side = torso.CFrame.RightVector * ((math.random() < 0.5 and -1 or 1) * (2.5 + math.random() * 2))
		to = torso.Position + side + Vector3.new(0, math.random() * 2 - 0.5, 0)
		to = from + (to - from).Unit * ((to - from).Magnitude + 20)
	end
	-- the throw you see (same effect as another player's throw)
	Effect:FireClient(p, "Shot", {shooter = {Character = t.model}, from = from, to = to, pop = hit})
	if hit then
		hum:TakeDamage(isHead and Config.HeadshotDamage or Config.BodyshotDamage)
		Remote:FireClient(p, "Hurt", to)
	end
end

------------------------------------------------------------ STATS + CHALLENGE
local function publish(s)
	local p, st = s.player, s.stats
	p:SetAttribute("AimShots", st.shots)
	p:SetAttribute("AimHits", st.hits)
	p:SetAttribute("AimHeads", st.heads)
	p:SetAttribute("AimKills", st.kills)
end
local function publishBest(s)
	local goal = s.get("AimChallengeKills")
	local b = bestCache[s.player.UserId]
	s.player:SetAttribute("AimBest", b and b[tostring(goal)] or nil)
end

PlayerShot.Event:Connect(function(p)
	local s = sessions[p]
	if not s then return end
	s.stats.shots += 1
	publish(s)
end)
PlayerDamaged.Event:Connect(function(attacker, model, _, _, _, isHead, isMelee)
	local s = sessions[attacker]
	if not s or not model or model:GetAttribute("AimOwner") ~= attacker.UserId then return end
	if not isMelee then
		s.stats.hits += 1
		if isHead then s.stats.heads += 1 end
	end
	publish(s)
end)
PlayerKilled.Event:Connect(function(attacker, model)
	local s = sessions[attacker]
	if not s or not model or model:GetAttribute("AimOwner") ~= attacker.UserId then return end
	s.stats.kills += 1
	publish(s)
	local ch = s.challenge
	if ch and ch.running then
		ch.kills += 1
		attacker:SetAttribute("AimChKills", ch.kills)
		if ch.kills >= ch.goal then
			local time = math.floor((workspace:GetServerTimeNow() - ch.start) * 100 + 0.5) / 100
			ch.running = false
			s.challenge = nil
			local uid = attacker.UserId
			bestCache[uid] = bestCache[uid] or {}
			local key = tostring(ch.goal)
			local prev = bestCache[uid][key]
			local newBest = prev == nil or time < prev
			if newBest then
				bestCache[uid][key] = time
				local data = table.clone(bestCache[uid])
				task.spawn(function()
					if bestStore then pcall(function() bestStore:SetAsync(tostring(uid), data) end) end
				end)
			end
			attacker:SetAttribute("AimChTime", time)
			attacker:SetAttribute("AimChNewBest", newBest)
			attacker:SetAttribute("AimChState", "done")
			publishBest(s)
		end
	end
end)

local function startChallenge(s)
	local p = s.player
	local goal = s.get("AimChallengeKills")
	local start = workspace:GetServerTimeNow() + COUNTDOWN
	s.challenge = {goal = goal, start = start, kills = 0, running = false}
	local ch = s.challenge
	p:SetAttribute("AimChGoal", goal)
	p:SetAttribute("AimChKills", 0)
	p:SetAttribute("AimChStart", start)
	p:SetAttribute("AimChState", "countdown")
	p:SetAttribute("AimChTime", nil)
	p:SetAttribute("AimChNewBest", nil)
	-- fresh targets for a fair start
	clearTargets(s)
	task.delay(COUNTDOWN, function()
		if s.challenge ~= ch or not s.alive then return end
		ch.running = true
		p:SetAttribute("AimChState", "running")
		fillTargets(s)
	end)
end
local function cancelChallenge(s)
	if not s.challenge then return end
	s.challenge = nil
	s.player:SetAttribute("AimChState", nil)
	fillTargets(s)
end

------------------------------------------------------------ ENTER / LEAVE
local function loadBest(uid)
	if bestCache[uid] then return end
	bestCache[uid] = {}
	if not bestStore then return end
	local ok, data = pcall(function() return bestStore:GetAsync(tostring(uid)) end)
	if ok and type(data) == "table" then bestCache[uid] = data end
end

local SIGNATURE_KEYS = {"AimType", "AimCount", "AimAvatar", "AimOrbSize"}
local BOX_KEYS = {"AimDistance", "AimBoxShow", "AimBoxWidth", "AimBoxDepth", "AimBoxHeight", "AimBoxColor", "AimBoxTransparency", "AimBoxOutline"}
local function sig(s, keys)
	local t = {}
	for _, k in keys do table.insert(t, tostring(s.get(k))) end
	return table.concat(t, "|")
end

local function leave(p)
	local s = sessions[p]
	if not s then return end
	sessions[p] = nil
	s.alive = false
	usedSlots[s.slot] = nil
	clearTargets(s)
	if s.room then s.room:Destroy() end
	for _, a in {"AimTraining", "AimSpawn", "AimShots", "AimHits", "AimHeads", "AimKills", "AimChGoal", "AimChKills", "AimChStart", "AimChState", "AimChTime", "AimChNewBest", "AimBest"} do
		p:SetAttribute(a, nil)
	end
end

local function enter(p)
	local existing = sessions[p]
	if existing then return existing.spawnCF end
	local slot = 1
	while usedSlots[slot] do slot += 1 end
	usedSlots[slot] = true
	local room = Assets.Room:Clone()
	room.Name = "Room_" .. p.UserId
	room:PivotTo(CFrame.new(ORIGIN + Vector3.new(0, 0, (slot - 1) * SPACING)))
	pcall(function() room.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer end)
	local targetsFolder = Instance.new("Folder")
	targetsFolder.Name = "Targets"
	targetsFolder.Parent = room
	room.Parent = rooms
	pcall(function() room:AddPersistentPlayer(p) end)
	local spawnPart = room:FindFirstChild("Spawn", true)
	local floor = room.PrimaryPart
	local spawnCF = CFrame.new(spawnPart.Position + Vector3.new(0, 3.5, 0)) * spawnPart.CFrame.Rotation
	local s = {
		player = p, slot = slot, room = room, targetsFolder = targetsFolder, spawnCF = spawnCF,
		floorY = floor.Position.Y + floor.Size.Y / 2, targets = {}, token = 0, alive = true, warned = {},
		stats = {shots = 0, hits = 0, heads = 0, kills = 0}, get = settingsOf(p),
	}
	sessions[p] = s
	s.sig, s.boxSig = sig(s, SIGNATURE_KEYS), sig(s, BOX_KEYS)
	buildBox(s)
	p:SetAttribute("AimTraining", true)
	p:SetAttribute("AimSpawn", spawnCF)
	publish(s)
	task.spawn(function()
		loadBest(p.UserId)
		if sessions[p] == s then publishBest(s) end
	end)
	task.spawn(fillTargets, s)
	-- bots throwing back
	task.spawn(function()
		while s.alive do
			task.wait(s.get("AimShootRate") * (0.7 + math.random() * 0.6))
			if s.alive and s.get("AimShootBack") and not s.menuOpen then
				local bots = {}
				for _, t in s.targets do if t.alive and t.kind == "Bot" then table.insert(bots, t) end end
				if #bots > 0 then throwAt(s, bots[math.random(#bots)]) end
			end
		end
	end)
	pcall(function() p:RequestStreamAroundAsync(spawnCF.Position, 5) end)
	return spawnCF
end

-- the player changed a setting: re-read and rebuild what changed
local function onPrefs(p)
	local s = sessions[p]
	if not s then return end
	s.get = settingsOf(p)
	local newSig, newBox = sig(s, SIGNATURE_KEYS), sig(s, BOX_KEYS)
	if newBox ~= s.boxSig then
		s.boxSig = newBox
		buildBox(s)
		for _, t in s.targets do t.pos = clampInBox(s, t.pos, t.margin) end
		if newSig == s.sig then
			-- box moved (distance): put everyone back inside it
			for _, t in s.targets do
				if t.kind == "Bot" then
					t.pos = randomInBox(s, t.margin, 0)
					t.root.CFrame = CFrame.new(t.pos + Vector3.new(0, t.offY, 0)) * t.root.CFrame.Rotation
				end
			end
		end
	end
	if newSig ~= s.sig then
		local onlyCount = s.get("AimType") == s.lastType and newSig:gsub("^[^|]*|[^|]*", "") == s.sig:gsub("^[^|]*|[^|]*", "")
		s.sig = newSig
		if onlyCount then fillTargets(s) else clearTargets(s) fillTargets(s) end
	end
	s.lastType = s.get("AimType")
	publishBest(s)
end

local function watch(p)
	local pending = false
	p:GetAttributeChangedSignal("Setting_Prefs"):Connect(function()
		if pending then return end
		pending = true
		task.delay(0.25, function() pending = false onPrefs(p) end)
	end)
	p:GetAttributeChangedSignal("InArena"):Connect(function() if not p:GetAttribute("InArena") then leave(p) end end)
	p:GetAttributeChangedSignal("MatchId"):Connect(function() if p:GetAttribute("MatchId") ~= nil then leave(p) end end)
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do watch(p) end
Players.PlayerRemoving:Connect(leave)

Remote.OnServerEvent:Connect(function(p, action, arg)
	local s = sessions[p]
	if not s then return end
	if action == "StartChallenge" then startChallenge(s)
	elseif action == "CancelChallenge" then cancelChallenge(s)
	elseif action == "MenuOpen" then
		s.menuOpen = arg == true
	elseif action == "ResetStats" then
		s.stats = {shots = 0, hits = 0, heads = 0, kills = 0}
		publish(s)
	end
end)

-- ArenaServer: script.Enter:Invoke(player) -> the spawn CFrame in their room; script.Leave:Invoke(player)
local enterFn = script:FindFirstChild("Enter") or Instance.new("BindableFunction")
enterFn.Name = "Enter"
enterFn.OnInvoke = enter
enterFn.Parent = script
local leaveFn = script:FindFirstChild("Leave") or Instance.new("BindableFunction")
leaveFn.Name = "Leave"
leaveFn.OnInvoke = leave
leaveFn.Parent = script
