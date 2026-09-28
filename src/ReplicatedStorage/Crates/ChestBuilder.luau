-- CHEST MODEL, built from parts (no model file needed). Colours per chest: CrateConfig > each chest's Look.
--   ChestBuilder.Build(look) -> Model:  Decor > Bottom (body + base trim), Decor > Top (lid + ridges), Guards (corners),
--   Lock (plate + keyhole + light), Item (where a reward appears, above the chest), Anchor (bottom centre = PrimaryPart),
--   Shine (sparkles, when look.Sparkle). The lock faces +Z (the camera side in the shop / spin).
--   look = {Body, Lid, Trim, Seam, Lock = Color3s, Material = "SmoothPlastic", LockMaterial = "Neon", Sparkle = true,
--           SparkleColor = Color3, Scale = 1}
local M = {}

local function part(parent, name, cf, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- a box with rounded edges: 3 inset boxes + 12 edge cylinders + 8 corner balls
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local function roundedBox(parent, name, cf, size, r, color, material)
	local m = Instance.new("Model")
	m.Name = name
	local sx, sy, sz = size.X, size.Y, size.Z
	r = math.min(r, sx / 2, sy / 2, sz / 2)
	local d = r * 2
	part(m, "Core", cf, Vector3.new(sx, sy - d, sz - d), color, material)
	part(m, "Core", cf, Vector3.new(sx - d, sy, sz - d), color, material)
	part(m, "Core", cf, Vector3.new(sx - d, sy - d, sz), color, material)
	local hx, hy, hz = sx / 2 - r, sy / 2 - r, sz / 2 - r
	for _, a in {-1, 1} do
		for _, b in {-1, 1} do
			part(m, "Edge", cf * CFrame.new(0, a * hy, b * hz), Vector3.new(sx - d, d, d), color, material, CYL)
			part(m, "Edge", cf * CFrame.new(a * hx, 0, b * hz) * ALONG_Y, Vector3.new(sy - d, d, d), color, material, CYL)
			part(m, "Edge", cf * CFrame.new(a * hx, b * hy, 0) * ALONG_Z, Vector3.new(sz - d, d, d), color, material, CYL)
			for _, c in {-1, 1} do
				part(m, "Corner", cf * CFrame.new(a * hx, b * hy, c * hz), Vector3.one * d, color, material, BALL)
			end
		end
	end
	m.Parent = parent
	return m
end

local function mat(name, default)
	local ok, v = pcall(function() return Enum.Material[name] end)
	return ok and v or default
end

function M.Build(look)
	look = look or {}
	local k = look.Scale or 1
	local body = look.Body or Color3.fromRGB(190, 200, 215)
	local lid = look.Lid or body
	local trim = look.Trim or Color3.fromRGB(110, 118, 130)
	local seam = look.Seam or Color3.fromRGB(20, 20, 24)
	local lockC = look.Lock or Color3.fromRGB(80, 200, 255)
	local material = mat(look.Material or "SmoothPlastic", Enum.Material.SmoothPlastic)
	local lockMat = mat(look.LockMaterial or "Neon", Enum.Material.Neon)
	local V = function(x, y, z) return Vector3.new(x, y, z) * k end
	local at = function(x, y, z) return CFrame.new(x * k, y * k, z * k) end

	local model = Instance.new("Model")
	model.Name = "Chest"
	local anchor = part(model, "Anchor", at(0, 0.05, 0), V(1, 0.1, 1), body, material)
	anchor.Transparency = 1
	model.PrimaryPart = anchor

	local decor = Instance.new("Model") decor.Name = "Decor" decor.Parent = model
	-- BOTTOM: body + a darker base band
	local bottom = Instance.new("Model") bottom.Name = "Bottom" bottom.Parent = decor
	roundedBox(bottom, "Body", at(0, 1.05, 0), V(4, 1.7, 3), 0.28 * k, body, material)
	roundedBox(bottom, "Base", at(0, 0.22, 0), V(4.12, 0.44, 3.12), 0.16 * k, trim, material)
	-- the dark gap between body and lid
	part(decor, "Seam", at(0, 1.93, 0), V(3.86, 0.16, 2.86), seam, Enum.Material.SmoothPlastic)
	-- TOP: the lid + 3 ridges across it
	local top = Instance.new("Model") top.Name = "Top" top.Parent = decor
	roundedBox(top, "Lid", at(0, 2.45, 0), V(4.1, 0.9, 3.1), 0.3 * k, lid, material)
	for i, z in {-0.95, 0, 0.95} do
		roundedBox(top, "Ridge" .. i, at(0, 2.93, z), V(4.16, 0.28, 0.5), 0.13 * k, i == 2 and trim or lid, material)
	end
	-- corner guards (both halves)
	local guards = Instance.new("Model") guards.Name = "Guards" guards.Parent = decor
	for _, x in {-1, 1} do
		for _, z in {-1, 1} do
			roundedBox(guards, "Guard", at(x * 1.92, 1.5, z * 1.42), V(0.5, 2.85, 0.5), 0.2 * k, trim, material)
		end
	end
	-- LOCK on the front (+Z)
	local lock = Instance.new("Model") lock.Name = "Lock" lock.Parent = model
	roundedBox(lock, "Frame", at(0, 1.95, 1.58), V(0.95, 0.95, 0.22), 0.1 * k, trim, material)
	local plate = part(lock, "Plate", at(0, 1.95, 1.68), V(0.7, 0.7, 0.08), lockC, lockMat)
	part(lock, "Keyhole", at(0, 1.9, 1.73), V(0.12, 0.28, 0.04), seam, Enum.Material.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Color = lockC
	light.Brightness = 1.2
	light.Range = 6 * k
	light.Parent = plate
	-- where a reward pops out (inside, under the lid - kept inside so it doesn't change how the chest is framed)
	local item = part(model, "Item", at(0, 2.2, 0), V(1, 1, 1), body, material)
	item.Transparency = 1
	-- SHINE: sparkles around the chest
	local shine = part(model, "Shine", at(0, 1.6, 0), V(4.4, 3.2, 3.4), body, material)
	shine.Transparency = 1
	if look.Sparkle then
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(look.SparkleColor or lockC)
		pe.LightEmission = 1
		pe.Rate = 8
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35 * k), NumberSequenceKeypoint.new(1, 0)})
		pe.Speed = NumberRange.new(0.3, 1)
		pe.Rotation = NumberRange.new(0, 360)
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		pe.Parent = shine
	end
	return model
end

return M
