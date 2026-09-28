-- CONVEYOR DUMMIES (practice arena)
-- Config.ConveyorDummyCount dummies (default 6) ride round the practice conveyor loop
-- (every part named "Conveyor" inside a model whose name starts with "PracConveyor").
-- They don't walk: they travel along the belts' middle line at the belts' own speed (their "Speed" value),
-- round the corners, evenly spaced, facing the middle of the loop.
-- Killed -> ragdoll, then back on the belt after Config.ConveyorDummyRespawnTime seconds (default 3).
-- The dummy is a copy of the "Noob" in the practice arena, same as the trampoline dummies.

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))

local arena = workspace:FindFirstChild("PracticeArena") or workspace
local source = arena:WaitForChild("Noob", 10)
if not source then warn("[ConveyorDummies] no Noob to copy") return end
local template = source:Clone()
template.Name = "Dummy"
template:SetAttribute("CombatRegistered", nil)
for _, d in template:GetDescendants() do
	if d:IsA("BasePart") then d.Anchored = false end
end

------------------------------------------------------------ THE LOOP
local belts = {}
for _, m in workspace:GetDescendants() do
	if m:IsA("Model") and m.Name:match("^PracConveyor") then
		local b = m:FindFirstChild("Conveyor")
		local beam = b and b:FindFirstChildWhichIsA("Beam")
		if b and b:IsA("BasePart") and beam and beam.Attachment0 and beam.Attachment1 then
			-- same direction the Conveyors script pushes: towards the beam's Attachment0
			local dir = beam.Attachment0.WorldPosition - beam.Attachment1.WorldPosition
			dir = Vector3.new(dir.X, 0, dir.Z).Unit
			local top = b.Position.Y + b.Size.Y / 2
			local mid = Vector3.new(b.Position.X, top, b.Position.Z)
			table.insert(belts, {part = b, a = mid - dir * b.Size.Z / 2, b = mid + dir * b.Size.Z / 2})
		end
	end
end
if #belts == 0 then warn("[ConveyorDummies] no practice conveyor found") return end

-- put the belts in travel order: each next belt starts nearest to where the last one ends
local ordered = {table.remove(belts, 1)}
while #belts > 0 do
	local last = ordered[#ordered]
	local best, bestI
	for i, s in belts do
		local d = (s.a - last.b).Magnitude
		if not best or d < best then best, bestI = d, i end
	end
	table.insert(ordered, table.remove(belts, bestI))
end

-- path = belt, gap to next belt, belt, gap ... (closed loop)
local points = {}
for _, s in ordered do
	table.insert(points, {pos = s.a, belt = s.part})
	table.insert(points, {pos = s.b, belt = s.part})
end
local segs, total = {}, 0
for i = 1, #points do
	local p, q = points[i], points[i % #points + 1]
	local len = (q.pos - p.pos).Magnitude
	if len > 0.01 then
		table.insert(segs, {from = p.pos, to = q.pos, len = len, start = total, belt = p.belt})
		total += len
	end
end

local center = Vector3.zero
for _, s in ordered do center += s.part.Position end
center /= #ordered

local function pointAt(dist)
	dist %= total
	for _, s in segs do
		if dist <= s.start + s.len then
			return s.from:Lerp(s.to, (dist - s.start) / s.len), s.belt
		end
	end
	return segs[1].from, segs[1].belt
end

local function beltSpeed(part)
	local sv = part:FindFirstChild("Speed")
	return (sv and sv:IsA("NumberValue")) and sv.Value or 16
end

------------------------------------------------------------ DUMMIES
local count = Config.ConveyorDummyCount or 6
local phase = 0 -- how far the whole train has travelled
local dummies = {} -- [k] = {model, root}

local function cframeFor(k)
	local pos = pointAt(phase + (k - 0.5) * total / count) + Vector3.new(0, 3.05, 0)
	return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
end

local function spawnDummy(k)
	local dummy = template:Clone()
	dummy:SetAttribute("CustomRespawn", true) -- we respawn it, not the combat script
	local root = dummy:FindFirstChild("HumanoidRootPart")
	local hum = dummy:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end
	hum.AutoRotate = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	root.Anchored = true -- we move it along the belt ourselves
	dummy:PivotTo(cframeFor(k))
	dummy.Parent = arena
	dummies[k] = {model = dummy, root = root}
	hum.Died:Connect(function()
		if dummies[k] and dummies[k].model == dummy then dummies[k] = nil end
		root.Anchored = false -- fall over like normal
		task.wait(Config.ConveyorDummyRespawnTime or 3)
		if dummy.Parent then dummy:Destroy() end
		spawnDummy(k)
	end)
end

RunService.Heartbeat:Connect(function(dt)
	-- the train moves at the speed of the belt it's on (use the first dummy's belt, so they stay evenly spaced)
	local _, belt = pointAt(phase)
	local speed = beltSpeed(belt)
	phase = (phase + speed * dt) % total
	for k, d in dummies do
		if d.root.Parent then d.root.CFrame = cframeFor(k) end
	end
end)

for k = 1, count do task.spawn(spawnDummy, k) end
