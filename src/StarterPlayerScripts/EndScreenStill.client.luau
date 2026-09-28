-- END SCREEN: stand still on the victory / defeat screen.
-- The server anchors everyone in place when a match ends (MatchmakingServer > freeze / lineUp), sometimes a little above
-- the floor. An anchored character in the air thinks it's falling and plays the fall / jump animation (looks like
-- flying). While "MatchEnded" is on, falling / jumping are switched off so it just stands (idle animation).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local STATES = {Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.Climbing}

local still = false
local conn
local function hum()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function setStill(on)
	if on == still then return end
	still = on
	local h = hum()
	if h then
		for _, s in STATES do h:SetStateEnabled(s, not on) end
		if on then h:ChangeState(Enum.HumanoidStateType.Running) end
	end
	if conn then conn:Disconnect() conn = nil end
	if on then
		conn = RunService.Heartbeat:Connect(function()
			local h2, root = hum()
			if not h2 then return end
			h2:Move(Vector3.zero)
			if root and not root.Anchored then root.AssemblyLinearVelocity = Vector3.zero end
			local st = h2:GetState()
			if st ~= Enum.HumanoidStateType.Running and st ~= Enum.HumanoidStateType.Dead then h2:ChangeState(Enum.HumanoidStateType.Running) end
		end)
	end
end

local function update() setStill(player:GetAttribute("MatchEnded") == true) end
player:GetAttributeChangedSignal("MatchEnded"):Connect(update)
player.CharacterAdded:Connect(function()
	still = false
	if conn then conn:Disconnect() conn = nil end
	task.defer(update)
end)
update()
