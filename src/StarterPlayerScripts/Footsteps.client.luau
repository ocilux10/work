-- FOOTSTEPS: realistic footsteps for every character (yours and other players'), instead of Roblox's own.
-- Sound picked by the floor material, steps timed by how fast you move, quieter when crouching, louder when
-- sprinting, none while sliding / in the air, plus a step when you land.
-- Settings + sound ids: ReplicatedStorage > FootstepConfig
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local C = require(RS:WaitForChild("FootstepConfig"))
local M = require(RS:WaitForChild("MovementConfig"))
if not C.Enabled then return end

-- animation ids that mean "crouching" / "sliding" (animations replicate, so this works for other players too)
local function idOf(s) return s and tostring(s):match("%d+") end
local crouchIds = {[idOf(M.Anims.Crouch) or "-"] = true, [idOf(M.Anims.CrouchWalk) or "-"] = true}
local slideId = idOf(M.Anims.Slide) or "-"

-- preload every footstep sound so the first steps aren't silent
task.spawn(function()
	local list = {}
	for _, set in C.Sets do for _, id in set do table.insert(list, "rbxassetid://" .. id) end end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

local rng = Random.new()
local lastPick = {} -- never the same take twice in a row (stops that "stuck" repeating sound)
local function soundFor(material)
	local setName = C.Materials[material.Name] or C.Default
	local set = C.Sets[setName] or C.Sets[C.Default]
	if not set or #set == 0 then return nil end
	local i = rng:NextInteger(1, #set)
	if #set > 1 and i == lastPick[setName] then i = i % #set + 1 end
	lastPick[setName] = i
	return set[i]
end

local function play(root, material, volume)
	local id = soundFor(material)
	if not id then return end
	local s = Instance.new("Sound")
	s.Name = "Footstep"
	s.SoundId = "rbxassetid://" .. id
	s.Volume = C.Volume * volume * (1 + rng:NextNumber(-C.VolumeRandom, C.VolumeRandom))
	s.PlaybackSpeed = 1 + rng:NextNumber(-C.PitchRandom, C.PitchRandom)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = C.HearDistance
	s.Parent = root
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end

local function animState(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	local crouch, slide = false, false
	if animator then
		for _, t in animator:GetPlayingAnimationTracks() do
			local id = idOf(t.Animation and t.Animation.AnimationId)
			if id then
				if crouchIds[id] then crouch = true end
				if id == slideId then slide = true end
			end
		end
	end
	return crouch, slide
end

local state = {} -- [character] = {acc, grounded, airTime}

RunService.Heartbeat:Connect(function(dt)
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (hum and root) or hum.Health <= 0 then continue end
		-- silence Roblox's own footstep sound
		local running = root:FindFirstChild("Running")
		if running and running:IsA("Sound") and running.Volume ~= 0 then running.Volume = 0 end

		local st = state[char]
		if not st then
			st = {acc = 0, grounded = true, airTime = 0}
			state[char] = st
			char.Destroying:Once(function() state[char] = nil end)
		end
		local grounded = hum.FloorMaterial ~= Enum.Material.Air
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude

		if not grounded then
			st.airTime += dt
		else
			-- landing step
			if not st.grounded and st.airTime > 0.3 and (C.LandVolume or 0) > 0 then
				play(root, hum.FloorMaterial, C.LandVolume)
				st.acc = 0
			end
			st.airTime = 0
			if speed > 1.5 then
				local crouch, slide = animState(hum)
				if slide then
					st.acc = 0 -- no steps while sliding
				else
					local sprinting = speed > (M.WalkSpeed or 16) + 2
					local stride = crouch and C.StrideWalk * 0.7 or (sprinting and C.StrideSprint or C.StrideWalk)
					st.acc += speed * dt
					if st.acc >= stride then
						st.acc -= stride
						local vol = crouch and C.CrouchVolume or (sprinting and C.SprintVolume or 1)
						play(root, hum.FloorMaterial, vol)
					end
				end
			else
				-- standing still: the first step comes quickly once you start moving
				st.acc = C.StrideWalk * 0.6
			end
		end
		st.grounded = grounded
	end
end)
