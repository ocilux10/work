-- HIDE ROBLOX NAMETAGS
-- Removes Roblox's default name + health bar above EVERY humanoid (players and NPCs),
-- including ones that spawn later (respawning dummies, trampoline NPCs, new characters).

local function hide(h)
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.NameDisplayDistance = 0
	h.HealthDisplayDistance = 0
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Humanoid") then hide(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then hide(d) end
end)
