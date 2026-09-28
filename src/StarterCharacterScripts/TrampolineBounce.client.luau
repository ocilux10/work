-- Players bounce on any model named "Trampoline" (its BouncePart), like the trampoline dummies.
-- Height: ReplicatedStorage > BalloonCombat > Config > PlayerTrampolineBounceHeight
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))
local SFX = require(RS:WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig

local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {char}

local lastBounce = 0
RunService.Heartbeat:Connect(function()
	if hum.Health <= 0 then return end
	local v = root.AssemblyLinearVelocity
	if v.Y > 2 then return end -- still going up
	-- what's right under our feet?
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -3.6, 0), params)
	if not hit then return end
	local tramp = hit.Instance:FindFirstAncestor("Trampoline")
	if not tramp or os.clock() - lastBounce < 0.15 then return end
	lastBounce = os.clock()
	local h = Config.PlayerTrampolineBounceHeight or Config.TrampolineBounceHeight or 20
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = Vector3.new(v.X, math.sqrt(2 * workspace.Gravity * h), v.Z)
	SFX.Play("Trampoline", root)
end)
