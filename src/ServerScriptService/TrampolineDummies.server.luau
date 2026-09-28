-- TRAMPOLINE DUMMIES
-- One dummy per model named "Trampoline" in the PracticeArena. It bounces straight up and down on the
-- trampoline's BouncePart. Killed dummies ragdoll (BalloonCombatServer) and respawn on their trampoline.
-- Settings (ReplicatedStorage > BalloonCombat > Config): TrampolineBounceHeight, TrampolineRespawnTime
-- The dummy is a copy of the first "Noob" in PracticeArena (taken when the server starts).
-- BOT TICK BOX: each Trampoline model has a "Bot" attribute. Ticked = a dummy bounces on it, unticked = empty.
-- (Works live too: untick it while playing and the dummy disappears, tick it and one appears.)

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))

-- the practice arena used to be a PracticeArena folder; if it isn't grouped any more, use Workspace
local arena = workspace:WaitForChild("PracticeArena", 3) or workspace
local source = arena:WaitForChild("Noob", 10)
if not source then warn("[TrampolineDummies] no Noob in PracticeArena to copy") return end
local template = source:Clone()
template.Name = "Dummy"
template:SetAttribute("CombatRegistered", nil)
for _, d in template:GetDescendants() do
	if d:IsA("BasePart") then d.Anchored = false end
end

-- the springy surface of a trampoline
local function surfaceOf(tramp)
	local bp = tramp:FindFirstChild("BouncePart", true)
	if not bp then
		local cf, size = tramp:GetBoundingBox()
		return Vector3.new(cf.Position.X, cf.Position.Y + size.Y / 2, cf.Position.Z)
	end
	local thin = math.min(bp.Size.X, bp.Size.Y, bp.Size.Z)
	return bp.Position + Vector3.new(0, thin / 2, 0)
end

local current = {} -- [trampoline] = its dummy
local function wantsBot(tramp)
	return tramp:GetAttribute("Bot") ~= false -- missing attribute = yes
end

local function spawnOn(tramp)
	if not wantsBot(tramp) or (current[tramp] and current[tramp].Parent) then return end
	local surface = surfaceOf(tramp)
	local dummy = template:Clone()
	dummy:SetAttribute("CustomRespawn", true) -- we handle respawning, not the combat script
	local root = dummy:FindFirstChild("HumanoidRootPart")
	local hum = dummy:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end
	-- face into the arena (toward ArenaSpawn, where players come from), not at the wall next to it
	local lookTarget = arena:FindFirstChild("ArenaSpawn", true)
	local targetPos = lookTarget and lookTarget.Position or arena:GetBoundingBox().Position
	local facing = CFrame.lookAt(surface, Vector3.new(targetPos.X, surface.Y, targetPos.Z)).Rotation
	dummy:PivotTo(CFrame.new(surface + Vector3.new(0, 3.1, 0)) * facing)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum.AutoRotate = false
	dummy.Parent = arena
	current[tramp] = dummy
	for _, p in dummy:GetDescendants() do
		if p:IsA("BasePart") then pcall(function() p:SetNetworkOwner(nil) end) end
	end

	local g = workspace.Gravity
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not root.Parent or hum.Health <= 0 then conn:Disconnect() return end
		local v = root.AssemblyLinearVelocity
		local pos = root.Position
		-- keep it centred over the trampoline and upright
		local toCenter = Vector3.new(surface.X - pos.X, 0, surface.Z - pos.Z)
		local vx, vz = toCenter.X * 6, toCenter.Z * 6
		local feetY = pos.Y - 3
		local vy = v.Y
		-- a standing humanoid hovers ~0.45 studs above the floor, so allow for that (or just check it's standing)
		local landed = feetY <= surface.Y + 0.75 or hum.FloorMaterial ~= Enum.Material.Air
		if vy <= 0.5 and landed then
			-- hit the trampoline: launch to exactly TrampolineBounceHeight
			vy = math.sqrt(2 * g * (Config.TrampolineBounceHeight or 12))
			-- clients play the boing (StarterPlayerScripts > UISounds, SoundConfig > Trampoline)
			tramp:SetAttribute("Bounced", os.clock())
		end
		root.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(root.Position) * facing
	end)

	hum.Died:Connect(function()
		task.wait(Config.TrampolineRespawnTime or 3)
		if dummy.Parent then dummy:Destroy() end
		if current[tramp] == dummy then current[tramp] = nil end
		if tramp.Parent then spawnOn(tramp) end
	end)
end

for _, d in arena:GetDescendants() do
	if d:IsA("Model") and d.Name == "Trampoline" then
		task.spawn(spawnOn, d)
		-- tick / untick Bot while playing
		d:GetAttributeChangedSignal("Bot"):Connect(function()
			if wantsBot(d) then
				spawnOn(d)
			else
				local dummy = current[d]
				current[d] = nil
				if dummy and dummy.Parent then dummy:Destroy() end
			end
		end)
	end
end
