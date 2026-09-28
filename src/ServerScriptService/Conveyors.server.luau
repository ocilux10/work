local DEFAULT_SPEED = 16

local function setup(part)
	if not (part:IsA("BasePart") and part.Name == "Conveyor") then return end
	if part:GetAttribute("ConveyorReady") then return end
	local beam = part:FindFirstChildWhichIsA("Beam")
	if not (beam and beam.Attachment0 and beam.Attachment1) then return end
	part:SetAttribute("ConveyorReady", true)
	local speedValue = part:FindFirstChild("Speed")

	local function apply()
		local speed = (speedValue and speedValue:IsA("NumberValue")) and speedValue.Value or DEFAULT_SPEED
		local dir = beam.Attachment0.WorldPosition - beam.Attachment1.WorldPosition
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 0.01 then return end
		dir = dir.Unit
		-- an anchored part with a velocity carries whatever touches it, without moving itself
		part.Anchored = true
		part.AssemblyLinearVelocity = dir * speed
		-- arrows scroll toward Attachment0 (negative speed), at the same speed things move
		-- (the arrows' look is handled on each player's screen by StarterPlayerScripts > ConveyorVisuals)
	end
	apply()
	if speedValue then speedValue.Changed:Connect(apply) end
	part:GetPropertyChangedSignal("CFrame"):Connect(apply)
end

for _, d in workspace:GetDescendants() do setup(d) end
workspace.DescendantAdded:Connect(function(d)
	if d.Name == "Conveyor" then task.defer(setup, d) end
end)
