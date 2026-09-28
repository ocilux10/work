-- CONVEYOR ARROWS (look only). Each Conveyor part's arrows scroll the way things get pushed (towards the Beam's Attachment0).
-- How fast they LOOK = "ArrowSpeed" attribute on the Conveyor part (studs/sec, 0 = same as its Speed value).
-- Updates live, even if you change ArrowSpeed / Speed while playtesting.

local DEFAULT_SPEED = 16
local hooked = {}
local SFX = require(game:GetService("ReplicatedStorage"):WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig

local function setup(part)
	if hooked[part] or not (part:IsA("BasePart") and part.Name == "Conveyor") then return end
	local beam = part:FindFirstChildWhichIsA("Beam")
	if not beam then return end
	hooked[part] = true
	-- quiet looping hum you hear when you're near the belt (SoundConfig > Conveyor)
	if not part:FindFirstChild("SFX_Conveyor") then SFX.Play("Conveyor", part) end
	local function apply()
		local sv = part:FindFirstChild("Speed")
		local arrow = part:GetAttribute("ArrowSpeed")
		if typeof(arrow) ~= "number" or arrow <= 0 then
			arrow = (sv and sv:IsA("NumberValue")) and sv.Value or DEFAULT_SPEED
		end
		local len = beam.TextureLength > 0 and beam.TextureLength or 1
		beam.TextureSpeed = -arrow / len
	end
	apply()
	part:GetAttributeChangedSignal("ArrowSpeed"):Connect(apply)
	local sv = part:FindFirstChild("Speed")
	if sv then sv.Changed:Connect(apply) end
	beam:GetPropertyChangedSignal("TextureLength"):Connect(apply)
	-- if something else (e.g. the server) changes the beam speed, put ours back
	beam:GetPropertyChangedSignal("TextureSpeed"):Connect(function()
		local len = beam.TextureLength > 0 and beam.TextureLength or 1
		local want = part:GetAttribute("ArrowSpeed")
		if typeof(want) ~= "number" or want <= 0 then want = (sv and sv.Value) or DEFAULT_SPEED end
		if math.abs(beam.TextureSpeed + want / len) > 0.001 then apply() end
	end)
end

for _, d in workspace:GetDescendants() do setup(d) end
-- conveyors that stream in later
workspace.DescendantAdded:Connect(function(d)
	if d.Name == "Conveyor" then task.defer(setup, d)
	elseif d:IsA("Beam") and d.Parent and d.Parent.Name == "Conveyor" then task.defer(setup, d.Parent) end
end)
