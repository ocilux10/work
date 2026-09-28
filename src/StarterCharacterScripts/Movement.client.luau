-- MOVEMENT v2
-- Sprint (LeftShift) · C or LeftControl: slide while SPRINTING (lasts as long as you hold it), otherwise crouch · Ledge climb (sprint-jump into a wall) · Vault (sprint into a low obstacle)
-- Momentum, slope slides, slide-jumps, coyote time, jump buffering, camera tilt / landing dip.
-- Settings: ReplicatedStorage > MovementConfig
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local M = require(RS:WaitForChild("MovementConfig"))
local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local animator = hum:WaitForChild("Animator")
local camera = workspace.CurrentCamera
local localPlayer = game:GetService("Players").LocalPlayer
local CombatConfig = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))
local SFX = require(RS:WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig
local GS = require(RS:WaitForChild("GameSettings")) -- keybinds, auto sprint, FOV, camera motion (Settings menu)
local function firstPerson()
	return localPlayer:GetAttribute("InArena") == true
end

------------------------------------------------------------ HELPERS
local function flat(v)
	v = Vector3.new(v.X, 0, v.Z)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.zero
end
local function hSpeed()
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end
local function approach(a, b, step)
	if a < b then return math.min(a + step, b) end
	return math.max(a - step, b)
end
local function lerp(a, b, t) return a + (b - a) * t end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilter()
	rayParams.FilterDescendantsInstances = {char, camera}
end
refreshFilter()

local function groundRay()
	return workspace:Raycast(root.Position, Vector3.new(0, -4.2, 0), rayParams)
end
local function facing()
	local v = firstPerson() and camera.CFrame.LookVector or root.CFrame.LookVector
	return flat(v)
end
local function onGround()
	return hum.FloorMaterial ~= Enum.Material.Air
end

------------------------------------------------------------ ANIMATIONS
-- WALK / IDLE / JUMP / FALL go into Roblox's own Animate script (it already switches between those states);
-- an empty "" keeps the Roblox default
local DEFAULT_ANIMS = {
	Walk = {"walk"},
	Idle = {"idle"},
	Jump = {"jump"},
	Fall = {"fall"},
}
task.spawn(function()
	local animate = char:WaitForChild("Animate", 10)
	if not animate then return end
	for name, folders in DEFAULT_ANIMS do
		local id = M.Anims[name]
		if type(id) == "string" and id ~= "" then
			for _, folderName in folders do
				local folder = animate:WaitForChild(folderName, 5)
				if folder then
					for _, a in folder:GetChildren() do
						if a:IsA("Animation") then a.AnimationId = id end
					end
				end
			end
			-- the walk animation is also used for running in Roblox's Animate
			if name == "Walk" then
				local run = animate:FindFirstChild("run")
				if run then for _, a in run:GetChildren() do if a:IsA("Animation") then a.AnimationId = id end end end
			end
		end
	end
end)

local tracks = {}
for name, id in M.Anims do
	if DEFAULT_ANIMS[name] or id == "" then continue end -- (those are handled by Animate above)
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, t = pcall(function() return animator:LoadAnimation(a) end)
	if ok and t then
		t.Priority = (name == "Slide" or name == "Climb") and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement
		tracks[name] = t
	else
		warn("[Movement] couldn't load animation", name, id)
	end
end
-- WATCHING A REPLAY / SPECTATING: your parked character just stands there with its idle animation for everyone
-- else. (The lobby floor under you isn't loaded on your screen while your camera is far away, so Roblox's Animate
-- would otherwise play the falling pose.)
local watchIdle
local function setWatchPose(on)
	local animate = char:FindFirstChild("Animate")
	if on then
		if watchIdle then return end
		if animate and animate:IsA("LocalScript") then animate.Disabled = true end
		for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0.1) end
		local idleFolder = animate and animate:FindFirstChild("idle")
		local anim = idleFolder and idleFolder:FindFirstChildWhichIsA("Animation")
		if not anim then
			anim = Instance.new("Animation")
			local custom = M.Anims and M.Anims.Idle
			anim.AnimationId = (type(custom) == "string" and custom ~= "") and custom or "rbxassetid://180435571"
		end
		local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and t then
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Core
			t:Play(0.1)
			watchIdle = t
		else
			watchIdle = true
		end
	elseif watchIdle then
		if typeof(watchIdle) == "Instance" then watchIdle:Stop(0.1) end
		watchIdle = nil
		if animate and animate:IsA("LocalScript") then animate.Disabled = false end
	end
end

local current
local function playOnly(name, speed)
	if current ~= name then
		for n, t in tracks do
			if n ~= name and t.IsPlaying then t:Stop(0.15) end
		end
		current = name
		local t = name and tracks[name]
		if t then
			-- loop is set at play time (the animation asset's own setting overrides it at load)
			if name == "Slide" then t.Looped = M.SlideAnimLoop == true
			elseif name == "Climb" then t.Looped = false
			else t.Looped = true end
			t:Play(0.15)
			if name == "Slide" and M.SlideAnimTime and t.Length > 0 then
				t:AdjustSpeed(t.Length / M.SlideAnimTime)
			end
		end
	end
	if speed and name and tracks[name] and name ~= "Slide" then
		tracks[name]:AdjustSpeed(speed)
	end
end

------------------------------------------------------------ STATE
local sprintHeld, crouchHeld = false, false
-- Settings > Controls > Auto Sprint (ON by default on phones). With it OFF, phones get a Sprint button
-- (StarterGui > MobileControls > SprintButton) that toggles sprinting on / off.
-- The toggle is remembered on the player (attribute MobileSprint) so it survives respawning.
-- CONTROLLER: hold the sprint button (L3 by default) to sprint, same as holding Shift
local function isPad(input) return input.UserInputType.Name:find("^Gamepad") ~= nil end
local function sprintOn()
	if sprintHeld then return true end
	if GS.Get("AutoSprint") then return true end -- Settings > Controls > Auto Sprint
	return localPlayer:GetAttribute("MobileSprint") == true
end
local sliding, climbing = false, false
local slideHeld = false -- slide lasts as long as C / Ctrl (or the mobile Slide button) is held, up to M.SlideMaxTime
local lastSlide, lastClimb = -100, -100
local slideDir, slideSpeed, slideStart, slideAirTime = Vector3.zero, 0, 0, 0
local curSpeed = M.WalkSpeed
local momentum = 0
local sprintJumped = false
local wasGrounded = true
local leftGroundAt, jumpedSinceGround = -100, false
local lastJumpPress = -100
local peakFall = 0
local wasCrouchHeld = false

-- camera fx
local baseFOV = camera.FieldOfView
local fov = baseFOV
local roll, pitch, pitchTarget = 0, 0, 0
local dip, dipVel = 0, 0
local camDrop, camDropTarget = 0, 0

------------------------------------------------------------ SLIDE
local function canSlide()
	return not sliding and not climbing and onGround()
		and hSpeed() >= M.SlideMinSpeed
		and os.clock() - lastSlide >= M.SlideCooldown
end

local function startSlide()
	-- slide the way you're pressing (W/A/S/D), otherwise the way you're already moving
	local input = flat(hum.MoveDirection)
	local v = flat(root.AssemblyLinearVelocity)
	slideDir = input ~= Vector3.zero and input or (v ~= Vector3.zero and v or flat(camera.CFrame.LookVector))
	slideSpeed = math.max(M.SlideSpeed, hSpeed() * 1.15)
	slideStart = os.clock()
	slideAirTime = 0
	sliding = true
	slideHeld = true
	lastSlide = os.clock()
	SFX.Play("Slide", root)
end

local function endSlide()
	if not sliding then return end
	sliding = false
	curSpeed = math.clamp(slideSpeed, M.CrouchSpeed, M.SprintSpeed)
end

------------------------------------------------------------ CLIMB / VAULT
local function tryClimb(grounded)
	if climbing or sliding or os.clock() - lastClimb < M.ClimbCooldown then return end
	local look = facing()
	if hum.MoveDirection:Dot(look) < 0.4 then return end -- must be pushing toward it
	if grounded then
		if not M.VaultEnabled or not sprintOn() or hSpeed() < M.SprintSpeed * 0.7 then return end
	elseif M.ClimbRequiresSprint and not (sprintJumped or sprintOn()) then
		return
	end

	-- 1) wall in front of us
	local wall
	for _, h in {-1, 0.5, 1.5} do
		wall = workspace:Raycast(root.Position + Vector3.new(0, h, 0), look * M.ClimbCheckDistance, rayParams)
		if wall then break end
	end
	if not wall or math.abs(wall.Normal.Y) > 0.35 or not wall.Instance.CanCollide then return end
	local normal = flat(wall.Normal)
	if normal == Vector3.zero then return end

	-- 2) top edge
	local feetY = root.Position.Y - 3
	local maxTop = grounded and (feetY + M.VaultMaxHeight) or (root.Position.Y + M.ClimbReach)
	local probe = wall.Position - normal * 0.9
	local down = workspace:Raycast(Vector3.new(probe.X, maxTop + 0.6, probe.Z), Vector3.new(0, -(maxTop - feetY + 1), 0), rayParams)
	if not down or down.Normal.Y < 0.7 then return end
	local ledgeY = down.Position.Y
	if ledgeY > maxTop then return end
	if grounded and ledgeY - feetY < M.VaultMinHeight then return end
	if not grounded and ledgeY < root.Position.Y - 1.5 then return end

	-- nothing blocking the space above our head on the way up
	local headroom = workspace:Raycast(root.Position, Vector3.new(0, ledgeY + 3.4 - root.Position.Y, 0), rayParams)
	if headroom then return end

	-- 3) room to stand on top
	local standPos = Vector3.new(probe.X, ledgeY + 3.05, probe.Z) - normal * 0.6
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = {char, camera}
	op.RespectCanCollide = true
	if #workspace:GetPartBoundsInBox(CFrame.new(standPos + Vector3.new(0, 0.25, 0)), Vector3.new(1.8, 4.6, 1.2), op) > 0 then return end

	-- 4) pull up / hop over
	climbing = true
	lastClimb = os.clock()
	SFX.Play(grounded and "Vault" or "Climb", root)
	local duration = grounded and M.VaultTime or M.ClimbTime
	local carry = math.max(hSpeed(), curSpeed)
	playOnly("Climb")
	if tracks.Climb and tracks.Climb.Length > 0 then tracks.Climb:AdjustSpeed(tracks.Climb.Length / duration) end
	pitchTarget = -M.ClimbCameraPitch
	hum.AutoRotate = false
	local facing = CFrame.lookAt(Vector3.zero, -normal)
	local startPos = root.Position
	local upPos = Vector3.new(startPos.X, ledgeY + 3.35, startPos.Z)
	local t0 = os.clock()
	local conn
	local lastSet = root.Position
	conn = RunService.RenderStepped:Connect(function()
		if not root.Parent or hum.Health <= 0 then conn:Disconnect() climbing = false return end
		-- the server teleported / froze us mid-climb (round ended, new round placed us): stop right here,
		-- otherwise the climb drags us back to the ledge and we start the round there
		if root.Anchored or (root.Position - lastSet).Magnitude > 6 then
			conn:Disconnect()
			climbing = false
			sprintJumped = false
			hum.AutoRotate = true
			pitchTarget = 0
			current = nil
			return
		end
		local t = math.clamp((os.clock() - t0) / duration, 0, 1)
		local pos
		local split = grounded and 0.45 or 0.6
		if t < split then
			local a = t / split
			pos = startPos:Lerp(upPos, 1 - (1 - a) ^ 2)
		else
			local a = (t - split) / (1 - split)
			pos = upPos:Lerp(standPos, a * a * (3 - 2 * a))
		end
		root.CFrame = CFrame.new(pos) * facing
		lastSet = pos
		root.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 then
			conn:Disconnect()
			climbing = false
			sprintJumped = false
			hum.AutoRotate = true
			pitchTarget = 0
			current = nil
			hum:ChangeState(Enum.HumanoidStateType.Running)
			-- come out of it moving, not dead-stopped
			curSpeed = grounded and carry or math.max(curSpeed, M.WalkSpeed)
			root.AssemblyLinearVelocity = -normal * curSpeed * 0.8
		end
	end)
end

------------------------------------------------------------ INPUT
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if localPlayer:GetAttribute("Loading") then return end -- loading screen: nothing
	-- match countdown (Frozen): you can't move, but you CAN crouch (spam it), and holding sprint / crouch is
	-- remembered so the moment the countdown ends you're already sprinting / sliding
	if localPlayer:GetAttribute("Frozen") then
		if GS.Is("Sprint", input) then
			sprintHeld = true
		elseif GS.Is("Crouch", input) then
			if M.CrouchToggle then crouchHeld = not crouchHeld else crouchHeld = true end
		end
		return
	end
	local key = input.KeyCode
	if GS.Is("Sprint", input) then
		sprintHeld = true
		if M.CrouchToggle then crouchHeld = false end -- sprinting stands you back up
	elseif GS.Is("Crouch", input) then
		-- C and Left Ctrl do exactly the same thing: SPRINTING = slide (for as long as it's held), otherwise crouch
		-- (walking with just W/A/S/D and pressing it crouches)
		if sprintOn() and hum.MoveDirection.Magnitude > 0.1 and canSlide() then
			startSlide()
		elseif M.CrouchToggle then
			crouchHeld = not crouchHeld
		else
			crouchHeld = true
		end
	elseif GS.Is("Jump", input) then
		lastJumpPress = os.clock()
		-- coyote time: just ran off a ledge, still allowed to jump
		if not onGround() and not jumpedSinceGround and not climbing and os.clock() - leftGroundAt <= M.CoyoteTime then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	if GS.Is("Sprint", input) then
		sprintHeld = GS.IsDown("Sprint")
	elseif GS.Is("Crouch", input) then
		local eitherDown = GS.IsDown("Crouch")
		-- letting go ends the slide
		if not eitherDown then slideHeld = false end
		-- letting go of either crouch key stands you back up (unless the other one is still held)
		if not M.CrouchToggle and not eitherDown then
			crouchHeld = false
		end
	end
end)

-- MOBILE BUTTONS (StarterGui > MobileControls): "Slide" = C key (slide if moving, else crouch toggle), "Jump"
local clientActions = RS:WaitForChild("BalloonCombat"):WaitForChild("ClientActions")
local actionConn = clientActions.Event:Connect(function(action)
	if hum.Health <= 0 then return end
	if localPlayer:GetAttribute("Loading") then return end -- loading screen: nothing
	if localPlayer:GetAttribute("Frozen") then
		-- countdown: the mobile Slide button still crouches; the sprint toggle still works
		if action == "Slide" then crouchHeld = not crouchHeld
		elseif action == "SprintToggle" then localPlayer:SetAttribute("MobileSprint", not localPlayer:GetAttribute("MobileSprint")) end
		return
	end
	if action == "Slide" then
		-- phones always sprint, so moving + Slide button = slide; standing still = crouch
		if sprintOn() and canSlide() and hum.MoveDirection.Magnitude > 0.1 then
			startSlide()
		else
			crouchHeld = not crouchHeld -- standing still: the button toggles crouch
		end
	elseif action == "SprintToggle" then
		localPlayer:SetAttribute("MobileSprint", not localPlayer:GetAttribute("MobileSprint"))
	elseif action == "SlideEnd" then
		slideHeld = false -- let go of the mobile Slide button
	elseif action == "Jump" then
		lastJumpPress = os.clock()
		if crouchHeld and not sliding then crouchHeld = false end -- jumping stands you up
		if onGround() or (not jumpedSinceGround and not climbing and os.clock() - leftGroundAt <= M.CoyoteTime) then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)
script.Destroying:Connect(function() actionConn:Disconnect() end)
hum.Died:Connect(function() actionConn:Disconnect() end)

hum.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Jumping then
		jumpedSinceGround = true
		local speed = hSpeed()
		sprintJumped = sprintOn() and speed > M.WalkSpeed
		if sliding then
			-- slide-jump: keep the slide speed plus a boost
			local boost = slideDir * M.SlideJumpBoost
			root.AssemblyLinearVelocity += boost
			SFX.Play("SlideJump", root)
			speed = slideSpeed + M.SlideJumpBoost
			endSlide()
		end
		if M.CarryMomentum then momentum = speed end
	elseif new == Enum.HumanoidStateType.Landed then
		jumpedSinceGround = false
		sprintJumped = false
		-- landing camera dip, scaled by how hard you hit the ground
		if M.LandingDip > 0 then
			local k = math.clamp((peakFall - 20) / 60, 0, 1)
			dipVel -= k * M.LandingDip * 25
		end
		-- thud on a big fall
		if peakFall > 45 then SFX.Play("HardLand", root, {Volume = math.clamp(peakFall / 90, 0.5, 1.3)}) end
		peakFall = 0
		-- keep some of your air speed when you land
		curSpeed = math.max(curSpeed, math.min(hSpeed(), M.SprintSpeed + 6))
		-- land into a slide
		if M.LandingSlide and crouchHeld and sprintOn() and os.clock() - lastSlide >= M.SlideCooldown and hSpeed() >= M.SlideMinSpeed then
			task.defer(startSlide)
		elseif os.clock() - lastJumpPress <= M.JumpBuffer then
			task.defer(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
		end
		momentum = 0
	end
end)

------------------------------------------------------------ MAIN LOOP
local wasFrozen = false
local fwdLatch = false
local function movingKeysDown()
	if hum.MoveDirection.Magnitude > 0.1 then return true end
	for _, k in {"MoveForward", "MoveBackward", "StrafeLeft", "StrafeRight"} do
		local ok, down = pcall(GS.IsDown, k)
		if ok and down then return true end
	end
	return false
end
-- the countdown just ended: do exactly what the held keys say (sprint, slide, crouch) straight away
local function onUnfrozen()
	sprintHeld = GS.IsDown("Sprint")
	local crouchDown = GS.IsDown("Crouch")
	if not M.CrouchToggle then crouchHeld = crouchDown end
	if crouchDown and sprintOn() and movingKeysDown() and not sliding then
		crouchHeld = M.CrouchToggle and crouchHeld or false
		curSpeed = M.SprintSpeed
		startSlide()
		slideSpeed = math.max(M.SlideSpeed, M.SprintSpeed * 1.15)
	elseif sprintOn() and movingKeysDown() then
		curSpeed = math.max(curSpeed, M.SprintSpeed * 0.85) -- off the line at (nearly) full sprint
	end
end
RunService.Heartbeat:Connect(function(dt)
	if hum.Health <= 0 then playOnly(nil) return end
	if climbing then return end
	-- watching a replay / spectating: your own (parked) character does nothing, so holding W / Shift doesn't make
	-- the replay camera lean, zoom or run
	if localPlayer:GetAttribute("WatchingReplay") or localPlayer:GetAttribute("WatchingMatch") then
		hum.WalkSpeed = 0
		if sliding then endSlide() end
		curSpeed = M.WalkSpeed
		playOnly(nil)
		camDropTarget = 0
		for _, a in {"Sprinting", "Sliding", "Crouching"} do if char:GetAttribute(a) then char:SetAttribute(a, false) end end
		-- standing still in the lobby (no walking / jumping from the keys you use to watch)
		hum:Move(Vector3.zero)
		setWatchPose(true)
		if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			hum:SetAttribute("WatchNoJump", true)
		end
		return
	end
	if hum:GetAttribute("WatchNoJump") then
		hum:SetAttribute("WatchNoJump", nil)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	setWatchPose(false)
	-- loading screen is up (ReplicatedFirst > LoadingScreenClient): stand still
	local frozen = localPlayer:GetAttribute("Frozen") == true
	if wasFrozen and not frozen and not localPlayer:GetAttribute("Loading") then task.defer(onUnfrozen) end
	wasFrozen = frozen
	if localPlayer:GetAttribute("Loading") or frozen then
		hum.WalkSpeed = 0
		curSpeed = M.WalkSpeed
		if sliding then endSlide() curSpeed = M.WalkSpeed end
		-- countdown crouching (look + sound + camera height), no sprinting arms while standing still
		local crouching = frozen and crouchHeld
		if crouchHeld ~= wasCrouchHeld then
			wasCrouchHeld = crouchHeld
			SFX.Play("Crouch", root, crouchHeld and nil or {Pitch = 1.35, Volume = 0.8})
		end
		playOnly(crouching and "Crouch" or nil)
		camDropTarget = crouching and M.CrouchCameraDrop or 0
		if char:GetAttribute("Sprinting") then char:SetAttribute("Sprinting", false) end
		if char:GetAttribute("Sliding") then char:SetAttribute("Sliding", false) end
		if char:GetAttribute("Crouching") ~= crouching then char:SetAttribute("Crouching", crouching) end
		-- no jumping either (turned back on once you're free)
		if localPlayer:GetAttribute("Frozen") and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			hum:SetAttribute("FrozenNoJump", true)
		end
		return
	end
	if hum:GetAttribute("FrozenNoJump") then
		hum:SetAttribute("FrozenNoJump", nil)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	local grounded = onGround()
	local now = os.clock()
	local moveDir = hum.MoveDirection
	local moving = moveDir.Magnitude > 0.1
	local look = facing()
	-- sprint needs you to be going roughly forward. A thumbstick wobbles around that line, which used to flick
	-- between sprint and walk speed (jerky on phones), so: on touch any direction sprints, and everyone gets a
	-- little "stickiness" (starts at 0.3, only stops below -0.1)
	local touch = UIS:GetLastInputType() == Enum.UserInputType.Touch
	local dot = moving and moveDir.Unit:Dot(look) or -1
	if not moving then fwdLatch = false
	elseif dot > 0.3 then fwdLatch = true
	elseif dot < -0.1 then fwdLatch = false end
	local forwardish = moving and (M.SprintAnyDirection or touch or fwdLatch)

	-- coyote tracking
	if wasGrounded and not grounded and not jumpedSinceGround then leftGroundAt = now end
	wasGrounded = grounded
	if not grounded then peakFall = math.max(peakFall, -root.AssemblyLinearVelocity.Y) end

	local crouching = crouchHeld and not sliding
	local sprinting = sprintOn() and not crouchHeld and not sliding and forwardish
	if crouchHeld ~= wasCrouchHeld then
		wasCrouchHeld = crouchHeld
		-- one "Crouch" sound for both (standing up = same sound, higher + quieter), so Off = true mutes both
		if not sliding then SFX.Play("Crouch", root, crouchHeld and nil or {Pitch = 1.35, Volume = 0.8}) end
	end

	-------- SLIDE PHYSICS
	if sliding then
		local g = groundRay()
		local slopeGain = 0
		if g then
			local downhill = Vector3.new(g.Normal.X, 0, g.Normal.Z) -- points downhill, length = steepness
			slopeGain = downhill:Dot(slideDir)
		end
		slideSpeed += (M.SlopeBoost * slopeGain - M.SlideFriction) * dt
		-- light steering
		if moving and M.SlideSteer > 0 then
			slideDir = flat(slideDir:Lerp(flat(moveDir), math.min(1, M.SlideSteer * dt)))
		end
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = slideDir * math.max(slideSpeed, 0) + Vector3.new(0, v.Y, 0)
		hum.WalkSpeed = math.max(slideSpeed, M.CrouchSpeed)

		if grounded then slideAirTime = 0 else slideAirTime += dt end
		local downhillSlide = slopeGain > 0.08
		local slideTime = now - slideStart
		local maxTime = downhillSlide and math.max(M.SlideMaxTime, M.SlideDownhillMaxTime or 3) or M.SlideMaxTime
		-- slide for as long as the key is held (a quick tap still gives a short M.SlideMinTime slide)
		local letGo = not slideHeld and slideTime >= (M.SlideMinTime or 0.15)
		if slideSpeed <= M.CrouchSpeed + 1 or slideTime > maxTime or letGo or slideAirTime > 0.2 then
			endSlide()
		end
		-- a non-looping slide animation holds its last pose for the rest of the slide
		local st = tracks.Slide
		if sliding and st and st.IsPlaying and not st.Looped and st.Length > 0 and st.TimePosition >= st.Length * 0.9 then
			st:AdjustSpeed(0)
		end
	end

	-------- SPEED (acceleration + carried momentum)
	if not sliding then
		local target = crouching and M.CrouchSpeed or (sprinting and M.SprintSpeed or M.WalkSpeed)
		if not moving then target = math.min(target, M.WalkSpeed) end
		local rate = target > curSpeed and M.Acceleration or M.Deceleration
		curSpeed = approach(curSpeed, target, rate * dt)
		if not grounded and M.CarryMomentum then
			momentum = math.max(momentum - M.AirMomentumDecay * dt, 0)
			hum.WalkSpeed = math.max(curSpeed, momentum)
		else
			hum.WalkSpeed = curSpeed
		end
	end

	-------- CLIMB / VAULT
	if not sliding then
		if not grounded then tryClimb(false)
		elseif sprinting then tryClimb(true) end
		if climbing then return end
	end

	-------- ANIMATION
	local speed = hSpeed()
	if sliding then
		playOnly("Slide")
	elseif crouching and grounded then
		if moving then playOnly("CrouchWalk", math.clamp(speed / M.CrouchSpeed, 0.6, 1.6)) else playOnly("Crouch") end
	elseif sprinting and grounded and speed > M.WalkSpeed + 1 then
		playOnly("Run", math.clamp(speed / M.SprintSpeed, 0.7, 1.4))
	else
		playOnly(nil)
	end

	-------- let other scripts (first-person arms) know
	local isSprinting = sprinting and grounded and speed > M.WalkSpeed + 1
	if char:GetAttribute("Sprinting") ~= isSprinting then char:SetAttribute("Sprinting", isSprinting) end
	if char:GetAttribute("Sliding") ~= sliding then char:SetAttribute("Sliding", sliding) end
	if char:GetAttribute("Crouching") ~= crouching then char:SetAttribute("Crouching", crouching) end

	-------- camera targets
	camDropTarget = sliding and M.SlideCameraDrop or (crouching and M.CrouchCameraDrop or 0)
end)

------------------------------------------------------------ CAMERA FEEL (runs after the default camera, before the viewmodel)
local BIND = "MovementCameraFX"
local UNDO = "MovementCameraFXUndo"
local applied = CFrame.new()
pcall(function() RunService:UnbindFromRenderStep(BIND) end)
pcall(function() RunService:UnbindFromRenderStep(UNDO) end)
-- remove last frame's tilt before Roblox's camera reads it (otherwise it would build up)
RunService:BindToRenderStep(UNDO, Enum.RenderPriority.Camera.Value - 1, function()
	camera.CFrame = camera.CFrame * applied:Inverse()
	applied = CFrame.new()
end)
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not root.Parent then return end
	dt = math.min(dt, 1 / 20)
	if localPlayer:GetAttribute("WatchingReplay") or localPlayer:GetAttribute("WatchingMatch") then
		-- (the replay / spectate camera is in charge: no lean, dip or FOV change from your own character)
		camDrop, roll, pitch, dip, dipVel = 0, 0, 0, 0, 0
		hum.CameraOffset = Vector3.zero
		applied = CFrame.new()
		return
	end

	-- crouch / slide height
	camDrop = lerp(camDrop, camDropTarget, math.min(1, dt * 12))
	hum.CameraOffset = Vector3.new(0, -camDrop, 0)

	-- FOV
	local boost = sliding and M.SlideFOVBoost or ((sprintOn() and hSpeed() > M.WalkSpeed + 2) and M.SprintFOVBoost or 0)
	baseFOV = (firstPerson() and (GS.Get("FOV") or CombatConfig.CameraFOV)) or 70 -- Settings > Video > FOV
	fov = lerp(fov, baseFOV + boost, math.min(1, dt * 8))
	camera.FieldOfView = fov

	-- lean when strafing / sliding
	local right = flat(camera.CFrame.RightVector)
	local strafe = hum.MoveDirection:Dot(right)
	local targetRoll = -strafe * M.StrafeTilt
	if sliding then targetRoll += M.SlideTilt end
	roll = lerp(roll, targetRoll, math.min(1, dt * 8))

	-- climb nod
	pitch = lerp(pitch, pitchTarget, math.min(1, dt * 10))

	-- landing dip (spring)
	dipVel += (-dip * 170 - dipVel * 16) * dt
	dip += dipVel * dt

	applied = CFrame.new(0, dip, 0) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
	if not GS.Get("CameraShake") then applied = CFrame.new() end -- Settings > Video > Camera Motion off
	camera.CFrame = camera.CFrame * applied
end)

local function cleanup()
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
	pcall(function() RunService:UnbindFromRenderStep(UNDO) end)
	camera.FieldOfView = baseFOV
	hum.CameraOffset = Vector3.zero
end
hum.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)
