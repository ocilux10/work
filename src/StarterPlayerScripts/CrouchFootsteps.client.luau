-- CROUCH FOOTSTEPS: crouch-walking is much quieter - for you AND for everyone else's characters.
-- Works on Roblox's default footstep sound ("Running" in HumanoidRootPart). A character counts as crouching
-- while its Crouch / CrouchWalk animation is playing (animations replicate, so this works for other players too).
-- Volume: ReplicatedStorage > MovementConfig > CrouchFootstepVolume (1 = normal, 0 = silent)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local M = require(RS:WaitForChild("MovementConfig"))

local crouchIds = {}
for _, name in {"Crouch", "CrouchWalk"} do
	local id = M.Anims and M.Anims[name]
	if id then crouchIds[id:match("%d+") or id] = true end
end

local function isCrouching(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return false end
	for _, t in animator:GetPlayingAnimationTracks() do
		local id = t.Animation and t.Animation.AnimationId
		if id and crouchIds[id:match("%d+") or id] then return true end
	end
	return false
end

while true do
	task.wait(0.1)
	local mult = M.CrouchFootstepVolume or 0.15
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local step = root and root:FindFirstChild("Running")
		if step and step:IsA("Sound") then
			local base = step:GetAttribute("BaseVolume")
			if base == nil then base = step.Volume step:SetAttribute("BaseVolume", base) end
			local want = isCrouching(char) and base * mult or base
			if step.Volume ~= want then step.Volume = want end
		end
	end
end
