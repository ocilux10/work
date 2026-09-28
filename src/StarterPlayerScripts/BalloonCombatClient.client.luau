-- BALLOON COMBAT – CLIENT
-- First-person viewmodel, LMB swing / RMB shoot input, flying balloon visuals, pop FX.
-- Tweak numbers in ReplicatedStorage > BalloonCombat > Config.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local ReloadShapes = require(game:GetService("ReplicatedStorage"):WaitForChild("ReloadBarBuilder"))
local GSR = require(game:GetService("ReplicatedStorage"):WaitForChild("GameSettings"))
local reloadSet -- set(fraction) of the reload shape (rebuilt when its settings change)
local reloadScale
GSR.Changed:Connect(function(key) if table.find(ReloadShapes.Keys, key) then reloadSet = nil end end)
local camera = workspace.CurrentCamera

local folder = RS:WaitForChild("BalloonCombat")
local Config = require(folder:WaitForChild("Config"))
local Remotes = folder:WaitForChild("Remotes")
local SwingRemote, ShootRemote, Effect = Remotes.Swing, Remotes.Shoot, Remotes.Effect
local template = folder:WaitForChild("BalloonTemplate")
-- balloon skins (ReplicatedStorage > BalloonSkins): your equipped one in your hand, everyone's own on their throws
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local previewSkin -- (Balloons menu > Inspect > Wielded: this balloon in your hands for a look)
local function mySkin() return previewSkin or player:GetAttribute("EquippedSkin") end
local SFX = require(RS:WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig

local function inArena()
	return player:GetAttribute("InArena") == true
end

local fxFolder = Instance.new("Folder")
fxFolder.Name = "BalloonFX_Local"
fxFolder.Parent = workspace

------------------------------------------------------------ HELPERS
local function scaleBalloon(part, s)
	part.Size *= s
	for _, a in part:GetChildren() do
		if a:IsA("Attachment") then a.Position *= s end
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

-- the string beam goes; a skin's own effects (beams named FX_...) stay
local function stripBeams(part)
	for _, d in part:GetDescendants() do
		if d:IsA("Beam") and d.Name:sub(1, 3) ~= "FX_" then d.Enabled = false end
	end
end
-- your own third-person balloon is hidden on your screen: its effects too
local function hideAllFX(part)
	for _, d in part:GetDescendants() do
		if (d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("Light")) and d.Enabled then d.Enabled = false end
	end
end

local function lerpKeys(keys, t)
	-- keys = {{time, CFrame}, ...} sorted by time
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local alpha = (t - a[1]) / (b[1] - a[1])
			alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep
			return a[2]:Lerp(b[2], alpha)
		end
	end
	return keys[#keys][2]
end

------------------------------------------------------------ POP FX
local function popAt(pos, color)
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new(0.35, 0)
	pe.Speed = NumberRange.new(12, 24)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Lifetime = NumberRange.new(0.25, 0.45)
	pe.Drag = 6
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(20)

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Size = Vector3.one * 0.6
	flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = true, false, false, false, false
	flash.Transparency = 0.2
	flash.CFrame = CFrame.new(pos)
	flash.Parent = fxFolder
	TweenService:Create(flash, TweenInfo.new(0.15), {Size = Vector3.one * 3.5, Transparency = 1}):Play()

	SFX.Play("Pop", att)
	Debris:AddItem(flash, 0.3)
	Debris:AddItem(att, 2)
end

------------------------------------------------------------ FLYING BALLOON (visual only, hitscan already happened)
local function flyBalloon(from, to, doPop, skinId)
	local b = (skinId and Skins.Model(skinId)) or template:Clone()
	b.CanCollide, b.CanQuery, b.CanTouch = false, false, false
	scaleBalloon(b, Config.ShotVisualScale * Skins.Size(skinId)) -- (SkinConfig Size = per balloon)
	stripBeams(b)
	b.Anchored = true
	b.Transparency = Config.ShotVisualTransparency
	local color = b.Color
	local dist = (to - from).Magnitude
	if dist < 0.1 then
		if doPop then popAt(to, color) end
		b:Destroy()
		return
	end
	local rot = CFrame.lookAt(from, to).Rotation * CFrame.Angles(-math.pi / 2, 0, 0) -- top of balloon points forward
	b.CFrame = CFrame.new(from) * rot
	b.Parent = fxFolder

	-- TRAIL: an invisible carrier that follows the balloon (without its spin) and leaves a fading streak
	local carrier
	local trailLife = Config.ShotTrailLifetime or 0.25
	if Config.ShotTrail ~= false then
		carrier = Instance.new("Part")
		carrier.Name = "ShotTrail"
		carrier.Size = Vector3.one * 0.1
		carrier.Transparency = 1
		carrier.Anchored, carrier.CanCollide, carrier.CanQuery, carrier.CanTouch, carrier.CastShadow = true, false, false, false, false
		carrier.CFrame = CFrame.lookAt(from, to)
		local w = Config.ShotTrailWidth or 0.5
		local a0 = Instance.new("Attachment") a0.Position = Vector3.new(-w / 2, 0, 0) a0.Parent = carrier
		local a1 = Instance.new("Attachment") a1.Position = Vector3.new(w / 2, 0, 0) a1.Parent = carrier
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.FaceCamera = true
		trail.Lifetime = trailLife
		trail.MinLength = 0
		local trailColor = Config.ShotTrailColor or color
		trail.Color = ColorSequence.new(trailColor, trailColor:Lerp(Color3.new(1, 1, 1), 0.4))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, Config.ShotTrailTransparency or 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0.15) -- thick at the balloon, thin at the tail
		trail.LightEmission = Config.ShotTrailGlow or 0.6
		trail.Parent = carrier
		carrier.Parent = fxFolder
	end

	local duration = math.min(dist / Config.ShotVisualSpeed, Config.ShotMaxTravelTime or math.huge)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) / duration
		if t >= 1 then
			conn:Disconnect()
			b:Destroy()
			if carrier then
				carrier.CFrame = CFrame.lookAt(to, to + (to - from).Unit)
				Debris:AddItem(carrier, trailLife + 0.1) -- let the streak fade out
			end
			if doPop then popAt(to, color) end
			return
		end
		local pos = from:Lerp(to, t)
		b.CFrame = CFrame.new(pos) * rot * CFrame.Angles(0, t * 20, 0)
		if carrier then carrier.CFrame = CFrame.lookAt(pos, to) end
	end)
end

------------------------------------------------------------ VIEWMODEL
local vm = Instance.new("Model")
vm.Name = "BalloonViewmodel"

local function vmPart(name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = vm
	return p
end

-- ARM LAYOUT (camera space: +X right, +Y up, -Z forward). Tweak these to move the arms.
local R_SHOULDER, R_HAND_POS = Vector3.new(1.75, -1.45, -0.9), Vector3.new(0.85, -0.55, -2.5)
local L_SHOULDER, L_HAND_POS = Vector3.new(-1.75, -1.45, -0.9), Vector3.new(-0.95, -0.65, -2.4)
local ARM_THICK = 0.65
local ARM_EXTRA = 1.2 -- sleeve keeps going this far behind the shoulder (off-screen)
local R_POSE, R_LEN = CFrame.lookAt(R_SHOULDER, R_HAND_POS), (R_HAND_POS - R_SHOULDER).Magnitude
local L_POSE, L_LEN = CFrame.lookAt(L_SHOULDER, L_HAND_POS), (L_HAND_POS - L_SHOULDER).Magnitude

-- Sleeves are named like R6 arms and the viewmodel gets a Humanoid,
-- so a copy of the player's Shirt renders on them (arms match their clothes).
local function sleeve(name, len)
	local p = vmPart(name, Vector3.new(ARM_THICK, len + ARM_EXTRA, ARM_THICK), Config.ArmColor)
	return p
end
local vmHumanoid = Instance.new("Humanoid")
vmHumanoid.RigType = Enum.HumanoidRigType.R6
vmHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
vmHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
vmHumanoid.RequiresNeck = false
vmHumanoid.EvaluateStateMachine = false
vmHumanoid.Parent = vm
local function cuff(name)
	return vmPart(name, Vector3.new(ARM_THICK + 0.02, ARM_THICK + 0.02, 0.1), Color3.new(1, 0.8, 0.6))
end
local rSleeve, lSleeve = sleeve("Right Arm", R_LEN), sleeve("Left Arm", L_LEN)
local ARM_ROT = CFrame.Angles(math.pi / 2, 0, 0) -- part's -Y (the "hand" end of an R6 arm) points down the arm

local function applyClothes(char)
	for _, c in vm:GetChildren() do
		if c:IsA("Shirt") then c:Destroy() end
	end
	-- Shirt textures are tiny (a few pixels per stud) so stretched over arms right in front of the camera
	-- they look blurry / low-res. Default is crisp solid sleeves (Config.ArmColor); set
	-- Config.ShirtOnArms = true in BalloonCombat > Config to go back to showing the player's shirt.
	if not Config.ShirtOnArms then
		rSleeve.Color, lSleeve.Color = Config.ArmColor, Config.ArmColor
		return
	end
	local shirt = char:FindFirstChildOfClass("Shirt")
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local arm = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
	local color
	if shirt then
		shirt:Clone().Parent = vm
		color = arm and arm.Color -- shows through any see-through parts of the shirt
	else
		color = torso and torso.Color -- no shirt: use their top/torso colour
	end
	color = color or Config.ArmColor
	rSleeve.Color, lSleeve.Color = color, color
end
local rHand, lHand = cuff("RightHand"), cuff("LeftHand")
rHand.Transparency, lHand.Transparency = 1, 1 -- no cuff cap: the sleeve's own end face shows (smooth, like Knife Duels)
-- dress the first-person arms like this character (skin + shirt). Yours normally, the killer's in the final kill replay.
local function dressArms(char)
	if not char then return end
	local skin = Config.HandColor
	if not skin then
		local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
		skin = arm and arm.Color or Color3.new(1, 0.8, 0.6)
	end
	rHand.Color, lHand.Color = skin, skin
	applyClothes(char)
end

local vmBalloon, balloonBaseSize, knot, knotOffset, vmSkinId
local vmFX = {} -- the skin's effects on the first-person balloon (hidden while it's thrown / regrowing)
local function setVMSkin(id)
	if vmBalloon and vmSkinId == id then return end
	if vmBalloon then vmBalloon:Destroy() end
	vmSkinId = id
	vmBalloon = Skins.Model(id) or template:Clone()
	vmBalloon.Name = "Balloon"
	vmBalloon.CanCollide, vmBalloon.CanQuery, vmBalloon.CanTouch = false, false, false
	scaleBalloon(vmBalloon, Config.ViewmodelBalloonScale * Skins.Size(id)) -- (SkinConfig Size = per balloon)
	stripBeams(vmBalloon)
	vmBalloon.Anchored = true
	vmBalloon.CastShadow = false
	vmBalloon.Parent = vm
	balloonBaseSize = vmBalloon.Size
	knot = vmBalloon:FindFirstChild("StringPoint1")
	knotOffset = Vector3.new(0, -balloonBaseSize.Y / 2 * 0.97, 0) -- bottom tip of the balloon = the knot you hold
	table.clear(vmFX)
	for _, d in vmBalloon:GetDescendants() do
		if (d:IsA("Beam") and d.Enabled) or d:IsA("ParticleEmitter") or d:IsA("Light") then table.insert(vmFX, d) end
	end
end
setVMSkin(mySkin())
player:GetAttributeChangedSignal("EquippedSkin"):Connect(function() if not previewSkin then setVMSkin(mySkin()) end end)
local vmFXOn = true
local function showVMFX(on)
	if vmFXOn == on then return end
	vmFXOn = on
	for _, d in vmFX do d.Enabled = on end
end


-- INSPECT (F / mobile inspect button): the hand brings the balloon up in front of you, it spins round, then goes back
local INSPECT_TIME = Config.InspectTime or 2.4
local INSPECT_KEYS = {
	{0, CFrame.new()},
	-- arm reaches OUT to the side and forward, holding the balloon away to look at it
	{0.22, CFrame.new(0.55, 0.3, -0.45) * CFrame.Angles(math.rad(-8), math.rad(-30), math.rad(-18))},
	{0.5, CFrame.new(0.65, 0.4, -0.55) * CFrame.Angles(math.rad(-4), math.rad(-36), math.rad(-12))},
	{0.8, CFrame.new(0.55, 0.32, -0.5) * CFrame.Angles(math.rad(-10), math.rad(-26), math.rad(-22))},
	{1, CFrame.new()},
}
local inspectStart = -100
local function inspecting(now) return (now - inspectStart) < INSPECT_TIME end

-- MELEE COMBO: every swing alternates between these two (same damage). Times are 0-1 of Config.SwingAnimTime.
-- The balloon swings with the arm (tilts + trails behind it): BalloonSwingTilt / BalloonSwingFollow in Config.
local SWING_A = { -- 1) big slash from the right, across to the left
	{0, CFrame.new()},
	{0.18, CFrame.new(0.55, 0.45, 0.3) * CFrame.Angles(math.rad(35), math.rad(-55), math.rad(-35))},   -- wind up high right
	{0.42, CFrame.new(-1.4, -0.05, -0.9) * CFrame.Angles(math.rad(-20), math.rad(85), math.rad(45))},  -- strike across
	{0.6, CFrame.new(-1.55, -0.2, -0.7) * CFrame.Angles(math.rad(-28), math.rad(95), math.rad(50))},   -- follow through
	{1, CFrame.new()},
}
local SWING_B = { -- 2) backhand: from low left, rising up to the right
	{0, CFrame.new()},
	{0.18, CFrame.new(-0.9, -0.25, -0.1) * CFrame.Angles(math.rad(-10), math.rad(70), math.rad(40))},  -- wind across low left
	{0.42, CFrame.new(0.75, 0.5, -0.95) * CFrame.Angles(math.rad(30), math.rad(-70), math.rad(-40))},  -- strike up right
	{0.6, CFrame.new(0.85, 0.6, -0.7) * CFrame.Angles(math.rad(38), math.rad(-80), math.rad(-45))},    -- follow through
	{1, CFrame.new()},
}
local SWING_KEYS = SWING_A
local swingVariant, seenSwing = 2, -100 -- (which of the two the current swing is)
local THROW_KEYS = {
	{0, CFrame.new()},
	{0.3, CFrame.new(-0.2, 0.2, -0.7) * CFrame.Angles(math.rad(-25), math.rad(10), 0)},  -- push forward
	{1, CFrame.new()},
}

------------------------------------------------------------ STATE
local lastSwing, lastShot = -100, -100
-- FINAL KILL REPLAY (MatchUI > MatchClient drives it): the arms + balloon are shown as if you were the killer
local replayMode, replayToken = false, 0
-- LIVE SPECTATE (StarterPlayerScripts > LiveSpectateClient): the watched player's arms + balloon on your screen
local spectateMode, spectateTarget, spectateFree = false, nil, false
local spectateModel -- replays: a stand-in character (not a Player) to look through
local hiddenChar -- the watched player's body, hidden on this screen so it doesn't block the view
local function hideBody(char, on)
	if not char then return end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = on and 1 or 0 end
	end
end
local INFLATE_TIME = Config.InflateTime or 0.4
local swingStart, throwStart, regrowStart = -100, -100, -100
-- MOBILE THROW HOLD (Config.ThrowHold): MobileControls sets the ThrowHolding attribute while the throw button is held
local holdK = 0
local holdTrack, holdTrackChar
local function holdPose()
	local H = Config.ThrowHold or {}
	local o, a = H.PoseOffset or Vector3.new(0.25, 0.3, 0.45), H.PoseAngles or Vector3.new(30, -10, -15)
	return CFrame.new(o) * CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z))
end
local function setHoldAnim(on)
	local H = Config.ThrowHold or {}
	local char = player.Character
	if on then
		if (H.AnimationId or "") == "" or not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then return end
		if not holdTrack or holdTrackChar ~= char then
			local anim = Instance.new("Animation")
			anim.AnimationId = H.AnimationId
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			if not ok then return end
			holdTrack, holdTrackChar = track, char
			holdTrack.Priority = Enum.AnimationPriority.Action
		end
		holdTrack:Play(H.FadeTime or 0.1, 1, H.AnimationSpeed or 1)
	elseif holdTrack then
		holdTrack:Stop(H.FadeTime or 0.1)
	end
end
player:GetAttributeChangedSignal("ThrowHolding"):Connect(function()
	setHoldAnim(player:GetAttribute("ThrowHolding") == true)
end)
local balloonReady = true
local lifeToken = 0
local sway = CFrame.new()
local lastCamCF = camera.CFrame
local bobT = 0
local armSwingK = 0
local armT = 0

local function getChar()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then return char, hum end
end

local function onCharacter(char)
	lifeToken += 1
	balloonReady = true
	lastSwing, lastShot = -100, -100
	regrowStart = -100
	local skin = Config.HandColor
	if not skin then
		local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
		local t0 = os.clock()
		while not arm and os.clock() - t0 < 2 do
			task.wait()
			arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
		end
		skin = arm and arm.Color or Color3.new(1, 0.8, 0.6)
	end
	rHand.Color = skin
	lHand.Color = skin
	vm.Parent = inArena() and camera or nil
	applyClothes(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Shirt") or c:IsA("BodyColors") then task.defer(applyClothes, char) end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Shirt") then task.defer(applyClothes, char) end
	end)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function() vm.Parent = nil end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

------------------------------------------------------------ ACTIONS
-- the match countdown / end screen locks combat (MatchmakingServer sets "CombatLocked")
local function combatLocked()
	return player:GetAttribute("CombatLocked") == true
end

local swingHeld = false -- (the melee key is being held down: keeps swinging)
local function trySwing()
	if not (inArena() or previewSkin) or combatLocked() then return end
	inspectStart = -100 -- attacking cancels an inspect
	local char = getChar()
	if not char or not balloonReady then return end
	local now = os.clock()
	if now - regrowStart < INFLATE_TIME then return end -- still inflating
	if now - lastSwing < Config.MeleeCooldown then return end
	lastSwing = now
	swingStart = now
	-- (Wielded preview in the Balloons menu: just the look, nothing is hit)
	if not previewSkin then SwingRemote:FireServer(camera.CFrame.LookVector) end
	SFX.Play("Swing")
end

-- aim training with Settings > Target > Reload Cooldown off (AimTrainingServer sets NoReload)
local NO_RELOAD_GAP = 0.12
local function noReloadOn() return player:GetAttribute("NoReload") == true end

local function tryShoot()
	if not (inArena() or previewSkin) or combatLocked() or player:GetAttribute("ShootLocked") then return end
	inspectStart = -100
	local char = getChar()
	if not char or not balloonReady then return end
	local now = os.clock()
	if now - regrowStart < INFLATE_TIME then return end -- still inflating
	local noReload = noReloadOn()
	if now - lastShot < (noReload and NO_RELOAD_GAP or Config.ShootCooldown) then return end
	lastShot = now
	throwStart = now
	balloonReady = false

	local camCF = camera.CFrame
	local origin, dir = camCF.Position, camCF.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- ignore players you can't damage (anyone not in your match), so shots go through them to what's behind
	local ignore = {char, camera, fxFolder}
	local myMatch = player:GetAttribute("MatchId")
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character and (myMatch == nil or other:GetAttribute("MatchId") ~= myMatch) then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(origin, dir * Config.ShootRange, params)

	-- AIM ASSIST (Config.ShotAssistRadius): if the exact line missed everyone, a fatter "ball" along the same
	-- line counts anyone it touches - as long as no wall is in the way. 0 = pixel-perfect.
	local assist = Config.ShotAssistRadius or 0
	local function isCharacterPart(part)
		local m = part and part:FindFirstAncestorOfClass("Model")
		while m do
			if m:FindFirstChildOfClass("Humanoid") then return true end
			m = m:FindFirstAncestorOfClass("Model")
		end
		return false
	end
	if assist > 0 and not (result and isCharacterPart(result.Instance)) then
		local wallDist = result and (result.Position - origin).Magnitude or Config.ShootRange
		local ok, fat = pcall(function()
			return workspace:Spherecast(origin, assist, dir * Config.ShootRange, params)
		 end)
		-- spherecasts ignore things they START inside, so this only catches targets ahead of you
		if ok and fat and isCharacterPart(fat.Instance) then
			local d = (fat.Position - origin).Magnitude
			if d <= wallDist + 0.5 then
				-- aim at the part itself (the server checks line of sight to this point)
				local target = fat.Instance.Position

				local los = workspace:Raycast(origin, target - origin, params)
				if not los or isCharacterPart(los.Instance) then
					result = {Instance = los and los.Instance or fat.Instance, Position = los and los.Position or target}
				end
			end
		end
	end

	if not previewSkin then ShootRemote:FireServer(origin, dir, result and result.Instance, result and result.Position) end

	local to = result and result.Position or (origin + dir * Config.ShootRange)
	local from = vmBalloon.Position
	-- tell the UI when the balloon reaches the target, so the damage number appears on arrival
	player:SetAttribute("ShotArriveAt", os.clock() + math.min((to - from).Magnitude / Config.ShotVisualSpeed, Config.ShotMaxTravelTime or math.huge))
	flyBalloon(from, to, result ~= nil, mySkin())
	SFX.Play("Shoot")

	local token = lifeToken
	task.delay(noReload and NO_RELOAD_GAP or Config.ShootCooldown, function()
		if token ~= lifeToken then return end
		balloonReady = true
		-- (no reload: it's back full size straight away, no inflating)
		regrowStart = noReload and (os.clock() - INFLATE_TIME) or os.clock()
		if (inArena() or previewSkin) and not noReload then SFX.Play("BalloonInflate") end
	end)
end

-- HOLD TO KEEP SWINGING: keep the melee key held = swings again every time the cooldown is up
swingHeld = false
RunService.Heartbeat:Connect(function()
	if not swingHeld or not (inArena() or previewSkin) or player:GetAttribute("TabHeld") then return end
	if UIS:GetFocusedTextBox() then return end
	if not GSR.IsDown("Swing") then swingHeld = false return end
	if os.clock() - lastSwing >= Config.MeleeCooldown then trySwing() end
end)

------------------------------------------------------------ LOBBY / ARENA MODE
local LeaveArena = Remotes:WaitForChild("LeaveArena")
local COMBAT_UI = {"Crosshair", "ReloadBar", "LMB", "RMB", "HealthBar"}

local LOBBY_HUD = {Buttons = true, XpBar = true, Bottom = true, Top = true, Quests = true}
local lastMainState
local function applyMode()
	local arena = inArena()
	-- camera
	if arena and Config.ForceFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		UIS.MouseIconEnabled = false -- the crosshair replaces it
	else
		player.CameraMode = Enum.CameraMode.Classic
		UIS.MouseIconEnabled = true
		-- pop the camera back out to third person
		player.CameraMinZoomDistance = 10
		task.delay(0.1, function()
			if not inArena() then player.CameraMinZoomDistance = 0.5 end
		end)
	end
	-- viewmodel
	vm.Parent = (previewSkin or replayMode or (spectateMode and not spectateFree) or (arena and getChar())) and camera or nil
	-- UI
	local pg = player:FindFirstChild("PlayerGui")
	local ui = pg and pg:FindFirstChild("BalloonCombatUI")
	if ui then
		for _, n in COMBAT_UI do
			local g = ui:FindFirstChild(n)
			-- (Wielded preview: just the crosshair)
			if g and g:IsA("GuiObject") and n ~= "ReloadBar" then g.Visible = arena or (previewSkin ~= nil and n ~= "HealthBar") end -- (Wielded preview: crosshair + melee / throw cooldowns)
		end
		local rb = ui:FindFirstChild("ReloadBar")
		if rb and not arena then rb.Visible = false end
		local rh = ui:FindFirstChild("ReloadHolder")
		if rh and not arena then rh.Visible = false end
	end
	-- lobby UI (Main): everything on in the lobby, everything off in the arena
	-- except the LEAVE button, which is only on in the arena
	local main = pg and pg:FindFirstChild("Main")
	local inMatch = player:GetAttribute("MatchId") ~= nil -- in a real match (MatchmakingServer): no lobby UI, no leave button
	-- (only when you actually go between lobby / arena / match - not on every call, e.g. the Balloons menu's
	-- wielded preview ending, which used to shut whatever menu was open)
	local mainState = tostring(arena) .. tostring(inMatch) .. tostring(main)
	local changedMode = mainState ~= lastMainState
	lastMainState = mainState
	if main then
		-- (the Balloons menu's inspect screen hides the lobby UI - BalloonsClient sets InspectingBalloon)
		main.Enabled = not player:GetAttribute("InspectingBalloon")
		for _, g in (changedMode and main:GetChildren() or {}) do
			if g:IsA("GuiObject") then
				if g:GetAttribute("ManagedPopup") then
					-- popups (player profile, duel prompt) open/close themselves; just force them shut in combat
					if arena or inMatch then g.Visible = false end
				elseif g.Name == "PracticeArenaLeave" then
					-- phones use the top bar leave button instead (StarterPlayerScripts > LeaveTopbarButton)
					local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
					g.Visible = arena and not inMatch and not mobile
				else
					if g:GetAttribute("LobbyVisible") == nil then g:SetAttribute("LobbyVisible", g.Visible) end
					-- (the lobby HUD is always a lobby thing, even if a menu had it hidden the first time we looked)
					if LOBBY_HUD[g.Name] then g:SetAttribute("LobbyVisible", true) end
					g.Visible = (not arena) and (not inMatch) and g:GetAttribute("LobbyVisible")
				end
			end
		end
	end
	-- combat UI (BalloonCombatUI): only the kill feed / popups stay up in the lobby
	if ui then ui.Enabled = true end
end

local hookedLeave
local function hookLeaveButton()
	local main = player.PlayerGui:FindFirstChild("Main")
	local leave = main and main:FindFirstChild("PracticeArenaLeave")
	local btn = leave and leave:FindFirstChild("Leave", true)
	if btn and btn:IsA("GuiButton") and hookedLeave ~= btn then
		hookedLeave = btn
		btn.Activated:Connect(function() LeaveArena:FireServer() end)
	end
end

player:GetAttributeChangedSignal("InArena"):Connect(applyMode)
-- practice arena in / out sounds (matches have their own)
local wasInArena = inArena()
player:GetAttributeChangedSignal("InArena"):Connect(function()
	local now = inArena()
	if now == wasInArena then return end
	wasInArena = now
	if player:GetAttribute("MatchId") ~= nil then return end
	SFX.Play(now and "ArenaEnter" or "ArenaLeave")
end)
player:GetAttributeChangedSignal("MatchId"):Connect(applyMode)
player.CharacterAdded:Connect(function()
	task.wait(0.2) -- let the ScreenGuis respawn first
	hookLeaveButton()
	applyMode()
end)
task.spawn(function()
	player:WaitForChild("PlayerGui"):WaitForChild("Main", 10)
	hookLeaveButton()
	applyMode()
end)

local function tryInspect()
	if not (inArena() or previewSkin) or not getChar() or not balloonReady then return end
	local now = os.clock()
	if inspecting(now) then return end
	if now - swingStart < Config.SwingAnimTime or now - throwStart < Config.ThrowAnimTime then return end
	if now - regrowStart < INFLATE_TIME then return end
	inspectStart = now
	SFX.Play("Inspect")
end

-- the mobile buttons (StarterGui > MobileControls) fire these
local ClientActions = folder:WaitForChild("ClientActions")
ClientActions.Event:Connect(function(action, a, b)
	if action == "Swing" then trySwing()
	elseif action == "Shoot" then tryShoot()
	elseif action == "Inspect" then tryInspect()
	-- Balloons menu > Inspect > Wielded: your arms holding this balloon (a = the balloon Id), until PreviewEnd
	elseif action == "PreviewStart" then
		previewSkin = a
		setVMSkin(a)
		balloonReady, inspectStart = true, -100
		lastShot, lastSwing, swingStart, throwStart, regrowStart = -100, -100, -100, -100, -100
		dressArms(player.Character)
		vm.Parent = camera
		applyMode() -- (crosshair on)
	elseif action == "PreviewEnd" then
		previewSkin = nil
		setVMSkin(mySkin())
		inspectStart = -100
		applyMode()
	-- final kill replay: play the killer's arms / throws / swings on this screen
	elseif action == "ReplayStart" then
		replayMode = true
		replayToken += 1
		local killer = typeof(a) == "number" and Players:GetPlayerByUserId(a)
		if killer and killer.Character then dressArms(killer.Character) end
		balloonReady, inspectStart = true, -100
		lastShot, lastSwing, swingStart, throwStart, regrowStart = -100, -100, -100, -100, -100
		vm.Parent = camera
		local ui = player.PlayerGui:FindFirstChild("BalloonCombatUI")
		local ch = ui and ui:FindFirstChild("Crosshair")
		if ch and ch:IsA("GuiObject") then ch.Visible = true end
	elseif action == "ReplayEnd" then
		replayMode = false
		replayToken += 1
		dressArms(player.Character) -- back to your own arms
		balloonReady = true
		lastShot, lastSwing, swingStart, throwStart, regrowStart = -100, -100, -100, -100, -100
		applyMode()
	elseif action == "ReplayShot" and replayMode then
		-- a = where the shot landed, b = popped something
		local now = os.clock()
		lastShot, throwStart = now, now
		balloonReady = false
		if typeof(a) == "Vector3" then flyBalloon(vmBalloon.Position, a, b == true) end
		SFX.Play("Shoot")
		local token = replayToken
		task.delay(Config.ShootCooldown, function()
			if token ~= replayToken then return end
			balloonReady = true
			regrowStart = os.clock()
			SFX.Play("BalloonInflate")
		end)
	elseif action == "ReplaySwing" and replayMode then
		local now = os.clock()
		lastSwing, swingStart = now, now
		SFX.Play("Swing")
	-- live spectate: a = the watched player's UserId (SpectateStart / SpectateTarget), a = true/false (SpectateFreecam)
	elseif action == "SpectateStart" or action == "SpectateTarget" then
		spectateMode = true
		if hiddenChar then hideBody(hiddenChar, false) hiddenChar = nil end
		spectateTarget = typeof(a) == "number" and Players:GetPlayerByUserId(a) or nil
		spectateModel = typeof(a) == "Instance" and a or nil
		if spectateTarget and spectateTarget.Character then dressArms(spectateTarget.Character) end
		if spectateModel then dressArms(spectateModel) end
		balloonReady, inspectStart = true, -100
		lastShot, lastSwing, swingStart, throwStart, regrowStart = -100, -100, -100, -100, -100
		applyMode()
	elseif action == "SpectateFreecam" then
		spectateFree = a == true
		if spectateFree and hiddenChar then hideBody(hiddenChar, false) hiddenChar = nil end
		applyMode()
	-- replays: the watched player's throws / swings on the first-person arms (a = where it landed, b = popped)
	elseif action == "SpectateShot" and spectateMode then
		local now = os.clock()
		lastShot, throwStart = now, now
		balloonReady = false
		if typeof(a) == "Vector3" then flyBalloon(vmBalloon.Position, a, b == true) end
		SFX.Play("Shoot")
		local token = spectateModel
		task.delay(Config.ShootCooldown, function()
			if spectateModel ~= token then return end
			balloonReady = true
			regrowStart = os.clock()
		end)
	elseif action == "SpectateSwing" and spectateMode then
		local now = os.clock()
		lastSwing, swingStart = now, now
		SFX.Play("Swing")
	elseif action == "SpectateEnd" then
		spectateMode, spectateTarget, spectateFree, spectateModel = false, nil, false, nil
		if hiddenChar then hideBody(hiddenChar, false) hiddenChar = nil end
		dressArms(player.Character)
		balloonReady = true
		lastShot, lastSwing, swingStart, throwStart, regrowStart = -100, -100, -100, -100, -100
		applyMode()
	end
end)

local pcHoldInput -- the key / mouse button being held to wind up a throw (PC, Instant Throw off)
local GS = require(game:GetService("ReplicatedStorage"):WaitForChild("GameSettings")) -- keybinds (Settings > Controls)
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if GS.Is("Inspect", input) then
		tryInspect()
		return
	end
	if GS.Is("LeaveArena", input) and inArena() and player:GetAttribute("MatchId") == nil then
		LeaveArena:FireServer()
		return
	end
	-- holding Tab frees the mouse (StarterPlayerScripts > TabMenu): clicks are for the UI then, not attacks
	if player:GetAttribute("TabHeld") then return end
	if GS.Is("Swing", input) then
		swingHeld = true
		trySwing()
	elseif GS.Is("Shoot", input) then
		-- right click or Q by default. Settings > Instant Throw ON = throw on press;
		-- OFF = hold to wind up (hold pose / Config.ThrowHold animation), let go to throw
		if GS.Get("InstantThrow") then
			tryShoot()
		elseif (inArena() or previewSkin) and not combatLocked() then
			pcHoldInput = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
			player:SetAttribute("ThrowHolding", true)
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	if GS.Is("Swing", input) then swingHeld = false end
	if not pcHoldInput then return end
	if input.KeyCode == pcHoldInput or input.UserInputType == pcHoldInput then
		pcHoldInput = nil
		player:SetAttribute("ThrowHolding", nil)
		tryShoot()
	end
end)
-- leaving the arena / dying / a match lock while holding just cancels the throw
local function cancelPcHold()
	if pcHoldInput then pcHoldInput = nil player:SetAttribute("ThrowHolding", nil) end
end
player:GetAttributeChangedSignal("InArena"):Connect(function() if not inArena() then cancelPcHold() end end)
player.CharacterAdded:Connect(cancelPcHold)

------------------------------------------------------------ THIRD-PERSON ARM SWING (what other players see)
-- shoulder angle (radians) added ON TOP of the raised holding pose, over time
local ARM_SWING_KEYS = {{0, 0}, {0.3, 1.3}, {0.6, -1.0}, {1, 0}}   -- wind up overhead, slash down, back to holding
local ARM_SWING_KEYS_B = {{0, 0}, {0.3, -0.7}, {0.6, 1.5}, {1, 0}} -- combo swing 2: down low first, then up
local armCombo = setmetatable({}, {__mode = "k"}) -- [character] = which swing is next (other players' combos)
local ARM_THROW_KEYS = {{0, 0}, {0.25, 1.4}, {0.55, -0.4}, {1, 0}}  -- pull back overhead, throw forward, back to holding
local armBase, armToken, armBusy, armLast = {}, {}, {}, {}
local function lerpNum(keys, t)
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local x = (t - a[1]) / (b[1] - a[1])
			x = x * x * (3 - 2 * x)
			return a[2] + (b[2] - a[2]) * x
		end
	end
	return keys[#keys][2]
end
local function animateArm(char, keys, duration)
	if not char then return end
	local torso = char:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild("Right Shoulder")
	local r15 = false
	if not motor then
		local ua = char:FindFirstChild("RightUpperArm")
		motor = ua and ua:FindFirstChild("RightShoulder")
		r15 = true
	end
	if not motor then return end
	if not armBusy[motor] then armBase[motor] = motor.C0 end -- current pose (arm raised while holding the balloon)
	local base = armBase[motor]
	armBusy[motor] = true
	local token = (armToken[motor] or 0) + 1
	armToken[motor] = token
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if armToken[motor] ~= token or not motor.Parent then conn:Disconnect() return end
		-- the server changed the pose mid-swing (e.g. left the arena) -> stop
		if motor.C0 ~= armLast[motor] and armLast[motor] ~= nil then armBusy[motor] = false conn:Disconnect() return end
		local t = math.clamp((os.clock() - t0) / duration, 0, 1)
		local a = lerpNum(keys, t)
		-- joint can be locked on live servers ("C0 is read only"): skip the swing instead of erroring every frame
		if not pcall(function() motor.C0 = base * (r15 and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, 0, a)) end) then
			armLast[motor] = nil
			armBusy[motor] = false
			conn:Disconnect()
			return
		end
		armLast[motor] = motor.C0
		if t >= 1 then
			pcall(function() motor.C0 = base end)
			armLast[motor] = nil
			armBusy[motor] = false
			conn:Disconnect()
		end
	end)
end

-- keep the balloon-holding arm up: after the walk/run animations run, cut their effect on the right shoulder
-- (runs for every character holding a balloon, so everyone sees the arm raised)
RunService.PreSimulation:Connect(function()
	local keep = Config.HoldArmSway or 0.12
	for _, plr in Players:GetPlayers() do
		local c = plr.Character
		if c and c:FindFirstChild("HeldBalloon") then
			local torso = c:FindFirstChild("Torso")
			local m = torso and torso:FindFirstChild("Right Shoulder")
			if not m then
				local ua = c:FindFirstChild("RightUpperArm")
				m = ua and ua:FindFirstChild("RightShoulder")
			end
			if m then m.Transform = CFrame.new():Lerp(m.Transform, keep) end
		end
	end
end)

-- other players' shots / swings
Effect.OnClientEvent:Connect(function(kind, data)
	-- live spectate: the watched player's throws / swings play on the first-person arms too
	if spectateMode and spectateTarget then
		local who = kind == "Shot" and data.shooter or data.player
		if who == spectateTarget then
			local now = os.clock()
			if kind == "Shot" then
				lastShot, throwStart = now, now
				balloonReady = false
				local target = spectateTarget
				task.delay(Config.ShootCooldown, function()
					if spectateTarget ~= target then return end
					balloonReady = true
					regrowStart = os.clock()
				end)
			elseif kind == "Swing" then
				lastSwing, swingStart = now, now
			end
		end
	end
	if kind == "Shot" and data.shooter ~= player then
		local skin = typeof(data.shooter) == "Instance" and data.shooter:IsA("Player") and data.shooter:GetAttribute("EquippedSkin") or nil
		flyBalloon(data.from, data.to, data.pop, skin)
		if typeof(data.from) == "Vector3" then SFX.Play("Shoot", data.from) end
		animateArm(data.shooter.Character, ARM_THROW_KEYS, Config.ThrowAnimTime * 1.6)
	elseif kind == "Swing" and data.player ~= player then
		local c = data.player.Character
		if c then armCombo[c] = not armCombo[c] end
		animateArm(c, (c and armCombo[c] == false) and ARM_SWING_KEYS_B or ARM_SWING_KEYS, Config.SwingAnimTime * 1.3)
		local head = data.player.Character and data.player.Character:FindFirstChild("Head")
		if head then SFX.Play("Swing", head) end
	end
end)

------------------------------------------------------------ RENDER LOOP
local function setCooldownBar(boxName, frac)
	-- LMB / RMB boxes live in BalloonCombatUI (falls back to Main if moved back)
	local pg = player.PlayerGui
	local holder = pg:FindFirstChild("BalloonCombatUI")
	local box = holder and holder:FindFirstChild(boxName)
	if not box then
		local main = pg:FindFirstChild("Main")
		box = main and main:FindFirstChild(boxName)
	end
	local cd = box and box:FindFirstChild("Cooldown")
	if cd then cd.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1)) end
end

RunService:BindToRenderStep("BalloonViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local now = os.clock()
	local shotFrac = noReloadOn() and 0 or 1 - (now - lastShot) / (Config.ShootCooldown + INFLATE_TIME)
	local swingFrac = 1 - (now - lastSwing) / Config.MeleeCooldown
	setCooldownBar("RMB", shotFrac)

	-- reload bar on the crosshair: shape / colours / size / distance = Settings > Crosshair > Reload Bar
	-- (ReplicatedStorage > ReloadBarBuilder; the bar's look = StarterGui > BalloonCombatUI > ReloadBar)
	local ui = player.PlayerGui:FindFirstChild("BalloonCombatUI")
	local reload = ui and ui:FindFirstChild("ReloadBar")
	if reload then
		if reload.Visible then reload.Visible = false end -- (just the design; the shape is built in ReloadHolder)
		local holder = ui:FindFirstChild("ReloadHolder")
		if not holder then
			holder = Instance.new("Frame")
			holder.Name = "ReloadHolder"
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromOffset(0, 0)
			holder.ZIndex = reload.ZIndex
			holder.Parent = ui
			reloadSet = nil
		end
		local vy = workspace.CurrentCamera.ViewportSize.Y
		local screenScale = math.clamp(vy / 800, 0.6, 1.6)
		if reloadScale ~= screenScale then reloadScale = screenScale reloadSet = nil end
		if not reloadSet then reloadSet = ReloadShapes.Build(holder, ReloadShapes.Options(GSR, screenScale), reload) end
		-- sits on the crosshair
		local ch = ui:FindFirstChild("Crosshair")
		if ch then
			local c = ch.AbsolutePosition + ch.AbsoluteSize / 2 - ui.AbsolutePosition
			holder.Position = UDim2.fromOffset(c.X, c.Y)
		end
		local reloading = shotFrac > 0 and shotFrac <= 1 and (inArena() or previewSkin or replayMode or (spectateMode and not spectateFree))
		holder.Visible = reloading
		if reloading then reloadSet(1 - shotFrac) end -- fills up as the balloon comes back
	end
	setCooldownBar("LMB", math.max(swingFrac, balloonReady and 0 or shotFrac))

	local char = getChar()
	if spectateMode then
		-- live spectate: through the watched player's eyes (their body is hidden on this screen)
		if spectateFree or not (spectateTarget or spectateModel) then
			if vm.Parent then vm.Parent = nil end
			return
		end
		char = spectateModel or spectateTarget.Character
		-- they died: no arms, and their body shows (the camera rides the ragdoll - LiveSpectateClient / ReplayClient)
		local shum = char and char:FindFirstChildOfClass("Humanoid")
		if char and (char:GetAttribute("SpecDead") or (not spectateModel and shum and shum.Health <= 0)) then
			if vm.Parent then vm.Parent = nil end
			if hiddenChar then hideBody(hiddenChar, false) hiddenChar = nil end
			return
		end
		if vm.Parent ~= camera then vm.Parent = camera end
		if char ~= hiddenChar then
			if hiddenChar then hideBody(hiddenChar, false) end
			hiddenChar = char
		end
		if char then hideBody(char, true) end
	elseif replayMode then
		-- replay: always drawn, even if you're dead / spectating
		if vm.Parent ~= camera then vm.Parent = camera end
	elseif not char or vm.Parent ~= camera then
		return
	end

	-- replay PAUSED (ReplayClient sets SpecPaused on the stand-in): the arms / balloon freeze exactly where they are
	if spectateMode and char and char:GetAttribute("SpecPaused") then
		lastShot += dt lastSwing += dt swingStart += dt throwStart += dt regrowStart += dt inspectStart += dt
		dt = 0
	end

	-- hide our own third-person balloon
	local held = char and char:FindFirstChild("HeldBalloon")
	if held then
		held.LocalTransparencyModifier = 1
		hideAllFX(held)
	end

	local camCF = camera.CFrame

	-- sway
	local delta = lastCamCF:ToObjectSpace(camCF)
	lastCamCF = camCF
	local rx, ry = delta:ToEulerAnglesYXZ()
	local k = 3 * Config.Sway
	local target = CFrame.Angles(math.clamp(-rx * k, -0.12, 0.12), math.clamp(-ry * k, -0.12, 0.12), 0)
	sway = sway:Lerp(target, math.min(1, dt * 10))

	-- walk bob
	local root = char and char:FindFirstChild("HumanoidRootPart")
	-- (replays: the stand-in doesn't really move, so ReplayClient passes its speed as the SpecVel attribute)
	local vel = (spectateMode and char and char:GetAttribute("SpecVel")) or (root and root.AssemblyLinearVelocity) or Vector3.zero
	-- (anchored = frozen for the countdown / a replay: its leftover velocity would make the arms pump)
	if not spectateMode and ((root and root.Anchored) or player:GetAttribute("Frozen")) then vel = Vector3.zero end
	local speed = (vel * Vector3.new(1, 0, 1)).Magnitude
	bobT += dt * speed * 0.6
	local bk = math.min(speed / 16, 1)
	local bob = CFrame.new(math.sin(bobT) * 0.05 * bk, -math.abs(math.cos(bobT)) * 0.05 * bk, 0)

	local base = camCF * sway * bob

	-- right arm animation (swing / throw) around the shoulder
	local anim = CFrame.new()
	local st = (now - swingStart) / Config.SwingAnimTime
	local tt = (now - throwStart) / Config.ThrowAnimTime
	-- a new swing started (yours, a replay's or a watched player's): the other one of the combo
	if swingStart ~= seenSwing and st >= 0 and st < 1 then
		seenSwing = swingStart
		swingVariant = swingVariant == 1 and 2 or 1
	end
	if st >= 0 and st < 1 then
		anim = lerpKeys(swingVariant == 1 and SWING_A or SWING_B, st)
	elseif tt >= 0 and tt < 1 then
		anim = lerpKeys(THROW_KEYS, tt)
	elseif inspecting(now) then
		anim = lerpKeys(INSPECT_KEYS, (now - inspectStart) / INSPECT_TIME)
	end
	-- mobile: pulled back while the throw button is held (blends out into the throw)
	local holding = player:GetAttribute("ThrowHolding") == true and balloonReady
	holdK += ((holding and 1 or 0) - holdK) * math.min(1, dt * ((Config.ThrowHold and Config.ThrowHold.PoseSpeed) or 14))
	if holdK > 0.001 then anim = CFrame.new():Lerp(holdPose(), holdK) * anim end

	-- SPRINT ARM SWAY (edit the numbers in Config: ArmSwingAmount / UpDown / Forward / Tilt / Speed)
	-- Natural up-and-down sway, arms in opposite rhythm, only while sprinting.
	-- (someone else's "Sprinting" attribute doesn't reach this screen, so when spectating it's worked out from speed)
	local sprintingNow = char ~= nil and speed > 1 and (char:GetAttribute("Sprinting") == true or (spectateMode and speed > 18))
	armSwingK += ((sprintingNow and 1 or 0) - armSwingK) * math.min(1, dt * 8)
	armT += dt * speed * 0.6 * (Config.ArmSwingSpeed or 1)
	local amt = armSwingK * (Config.ArmSwingAmount or 1)
	local swingBusy = ((st >= 0 and st < 1) or (tt >= 0 and tt < 1)) and 0.15 or 1 -- right arm calms down while attacking
	local upDown = Config.ArmSwingUpDown or 0.22
	local fwd = Config.ArmSwingForward or 0.1
	local tilt = math.rad(Config.ArmSwingTilt or 9)
	local function sway(phase, k)
		local y = math.sin(phase)            -- up / down
		local z = math.cos(phase)            -- slight forward / back, a quarter-step behind
		return CFrame.new(0, upDown * y * k, -fwd * z * k) * CFrame.Angles(tilt * y * k * 0.5, 0, tilt * z * k * 0.3)
	end
	local rPumpCam = sway(armT, amt * 0.85 * swingBusy)
	local lPumpCam = sway(armT + math.pi, amt)
	local rPump, lPump = CFrame.new(), CFrame.new()
	-- left arm pulls back for balance during a melee swing
	local lSwing = CFrame.new()
	if st >= 0 and st < 1 then
		local a = math.sin(st * math.pi)
		lSwing = CFrame.new(-0.15 * a, -0.15 * a, 0.35 * a) * CFrame.Angles(math.rad(-15) * a, math.rad(-20) * a, 0)
	end

	local rShoulder = base * rPumpCam * R_POSE * rPump * anim
	rSleeve.CFrame = rShoulder * CFrame.new(0, 0, -(R_LEN - ARM_EXTRA) / 2) * ARM_ROT
	rHand.CFrame = rShoulder * CFrame.new(0, 0, -R_LEN + 0.04)
	-- balloon stays upright on screen, sitting on the right hand
	local grip = Config.BalloonGripOffset or Vector3.new(0, 0.12, 0.12)
	local handRot = base.Rotation
	local swingK = (st >= 0 and st < 1) and math.sin(st * math.pi) or 0 -- 0 -> 1 -> 0 over the swing
	if swingK > 0 then
		-- the balloon turns with the arm (partly) and trails / leans the way it's being swung
		local follow = Config.BalloonSwingFollow or 0.55
		local tilt = math.rad(Config.BalloonSwingTilt or 35)
		handRot = base.Rotation:Lerp(rShoulder.Rotation, follow * swingK)
			* CFrame.Angles(-tilt * 0.5 * swingK, 0, (swingVariant == 1 and 1 or -1) * tilt * swingK)
	end
	local rHandCF = CFrame.new((rShoulder * CFrame.new(0, 0, -R_LEN)).Position) * handRot * CFrame.new(grip)

	local lShoulder = base * lPumpCam * L_POSE * lPump * lSwing
	lSleeve.CFrame = lShoulder * CFrame.new(0, 0, -(L_LEN - ARM_EXTRA) / 2) * ARM_ROT
	lHand.CFrame = lShoulder * CFrame.new(0, 0, -L_LEN + 0.04)

	-- balloon sits on top of the right hand, held by its knot
	if balloonReady then
		local g = math.clamp((now - regrowStart) / INFLATE_TIME, 0, 1)
		local s = 1
		if g < 1 then
			-- inflate: grows from a tiny balloon, overshoots a touch, settles
			local c1 = 1.70158
			local e = 1 + (c1 + 1) * (g - 1) ^ 3 + c1 * (g - 1) ^ 2 -- easeOutBack
			s = 0.12 + 0.88 * e
		end
		vmBalloon.Size = balloonBaseSize * s
		vmBalloon.Transparency = 0
		-- inspecting: the balloon does a full slow spin (plus a little wobble) on the hand
		local spin = CFrame.new()
		if inspecting(now) then
			local it = math.clamp(((now - inspectStart) / INSPECT_TIME - 0.15) / 0.7, 0, 1)
			local e = it * it * (3 - 2 * it)
			local held = math.sin(math.clamp((now - inspectStart) / INSPECT_TIME, 0, 1) * math.pi) -- 0 -> 1 -> 0
			-- tilted toward you and leaning outward, turning slowly round so you see every side
			spin = CFrame.Angles(-0.35 * held, e * math.pi * 2, -0.3 * held + math.sin(it * math.pi * 2) * 0.12)
		end
		vmBalloon.CFrame = rHandCF * spin * CFrame.new(-knotOffset * s)
		showVMFX(g >= 0.6)
	else
		vmBalloon.Transparency = 1
		showVMFX(false)
	end
end)
