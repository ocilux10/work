-- BALLOON LOOKS: builds a balloon's look + VFX from its Look / ExtraFX in SkinConfig (no model needed for new ones).
--   Look = {
--     Shape = "Inferno",               -- which balloon's 3D shape to use (a model in BalloonSkins > Models)
--     Color = Color3.fromRGB(...),     -- its colour (the shape's own painted texture is removed)
--     Material = "Neon",               -- SmoothPlastic, Neon, Glass, ForceField, Foil, Metal, Marble, Ice, CrackedLava, Slate...
--     Reflectance = 0.3, Transparency = 0.2,
--     KeepTexture = true,              -- keep the shape's painted texture (just tinted) instead of a plain colour
--     Glow = Color3 (or {Color = , Brightness = , Range = }),   -- a light inside it
--     FX = {"Sparkles", "Aura", ...},  -- effects (list below), coloured with FXColor (and FXColor2 = fades to)
--     FXColor = Color3 or "Rainbow", FXColor2 = Color3,
--   }
--   ExtraFX = {FX = {...}, FXColor = ..., Glow = ...}   -- effects ADDED on top of a balloon that has its own model
-- EFFECTS: Sparkles, Stars, Embers, Fire, Smoke, Aura, Vortex, Implode, Snow, Bubbles, Drip, Ring, DoubleRing, Halo
local M = {}

local TEX = {
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	implode = "rbxasset://textures/particles/explosion01_implosion_main.dds",
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 110)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 200)),
})
local function colors(c1, c2)
	if c1 == "Rainbow" then return RAINBOW end
	c1 = typeof(c1) == "Color3" and c1 or Color3.new(1, 1, 1)
	return ColorSequence.new(c1, typeof(c2) == "Color3" and c2 or c1)
end
local function firstColor(c) return typeof(c) == "Color3" and c or Color3.new(1, 1, 1) end
local function ns(...) return NumberSequence.new(...) end

local function attach(part, name, pos)
	local a = part:FindFirstChild(name)
	if a and a:IsA("Attachment") then return a end
	a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos or Vector3.zero
	a.Parent = part
	return a
end
local function emitter(parent, name, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	pe.LightEmission = 1
	pe.LockedToPart = false
	for k, v in props do pe[k] = v end
	pe.Parent = parent
	return pe
end

-- a flat ring round the balloon out of two curved beams (like Cosmic's)
local function ring(part, name, radius, tilt, cs, width)
	local l = Instance.new("Attachment") l.Name = "FX_" .. name .. "L"
	local r = Instance.new("Attachment") r.Name = "FX_" .. name .. "R"
	-- attachment X axis points "forward" (+Z) so the beams curve out front / back into a circle
	l.CFrame = CFrame.Angles(tilt, 0, 0) * CFrame.new(-radius, 0, 0) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	r.CFrame = CFrame.Angles(tilt, 0, 0) * CFrame.new(radius, 0, 0) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	l.Parent, r.Parent = part, part
	local k = radius * 4 / 3
	for i, side in {1, -1} do
		local b = Instance.new("Beam")
		b.Name = "FX_" .. name .. (i == 1 and "Front" or "Back")
		b.Attachment0, b.Attachment1 = l, r
		b.CurveSize0, b.CurveSize1 = k * side, -k * side
		b.Width0, b.Width1 = width, width
		b.Color = cs
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Transparency = ns(0.15)
		b.FaceCamera = true
		b.Segments = 24
		b.Parent = part
	end
end

local PRESETS = {}
PRESETS.Sparkles = function(part, core, cs, s)
	emitter(part, "FX_Sparkles", {Texture = TEX.sparkles, Color = cs, Rate = 7, Lifetime = NumberRange.new(0.6, 1.1),
		Size = ns({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35 * s), NumberSequenceKeypoint.new(1, 0)}),
		Speed = NumberRange.new(0.5 * s, 1.5 * s), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90), Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface})
end
PRESETS.Stars = function(part, core, cs, s)
	emitter(part, "FX_Stars", {Texture = TEX.sparkles, Color = cs, Rate = 12, Lifetime = NumberRange.new(1, 1.6),
		Size = ns({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.18 * s), NumberSequenceKeypoint.new(1, 0)}),
		Speed = NumberRange.new(0), Transparency = ns(0.1), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface})
end
PRESETS.Embers = function(part, core, cs, s)
	emitter(core, "FX_Embers", {Texture = TEX.sparks, Color = cs, Rate = 10, Lifetime = NumberRange.new(0.8, 1.4),
		Size = ns(0.25 * s, 0), Speed = NumberRange.new(1.5 * s, 3 * s), SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 2 * s, 0), EmissionDirection = Enum.NormalId.Top})
end
PRESETS.Fire = function(part, core, cs, s)
	emitter(core, "FX_Fire", {Texture = TEX.fire, Color = cs, Rate = 16, Lifetime = NumberRange.new(0.4, 0.7),
		Size = ns({NumberSequenceKeypoint.new(0, 0.7 * s), NumberSequenceKeypoint.new(1, 0)}), Speed = NumberRange.new(1 * s, 2.5 * s),
		SpreadAngle = Vector2.new(20, 20), Transparency = ns(0.3, 1), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60)})
end
PRESETS.Smoke = function(part, core, cs, s)
	emitter(core, "FX_Smoke", {Texture = TEX.smoke, Color = cs, Rate = 5, Lifetime = NumberRange.new(1.2, 2), LightEmission = 0,
		Size = ns(0.6 * s, 1.4 * s), Speed = NumberRange.new(0.4 * s, 1 * s), Transparency = ns(0.55, 1),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30)})
end
PRESETS.Aura = function(part, core, cs, s)
	emitter(core, "FX_Aura", {Texture = TEX.glow, Color = cs, Rate = 3, Lifetime = NumberRange.new(1, 1.4),
		Size = ns(1.3 * s, 1.8 * s), Speed = NumberRange.new(0), Transparency = ns({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.75), NumberSequenceKeypoint.new(1, 1)}),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40)})
end
PRESETS.Vortex = function(part, core, cs, s)
	emitter(core, "FX_Vortex", {Texture = TEX.vortex, Color = cs, Rate = 4, Lifetime = NumberRange.new(0.8, 1.1),
		Size = ns(1.2 * s, 0.4 * s), Speed = NumberRange.new(0), Transparency = ns(0.5, 1),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(180, 260)})
end
PRESETS.Implode = function(part, core, cs, s)
	emitter(core, "FX_Implode", {Texture = TEX.implode, Color = cs, Rate = 3, Lifetime = NumberRange.new(0.6, 0.9),
		Size = ns(1.6 * s, 0.2 * s), Speed = NumberRange.new(0), Transparency = ns(0.4, 1), Rotation = NumberRange.new(0, 360)})
end
PRESETS.Snow = function(part, core, cs, s)
	emitter(part, "FX_Snow", {Texture = TEX.sparkles, Color = cs, Rate = 9, Lifetime = NumberRange.new(1.2, 1.8),
		Size = ns(0.14 * s, 0.05 * s), Speed = NumberRange.new(0.3 * s, 0.8 * s), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1.2 * s, 0), Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface})
end
PRESETS.Bubbles = function(part, core, cs, s)
	emitter(part, "FX_Bubbles", {Texture = TEX.glow, Color = cs, Rate = 6, Lifetime = NumberRange.new(1, 1.6),
		Size = ns(0.12 * s, 0.3 * s), Speed = NumberRange.new(0.6 * s, 1.2 * s), SpreadAngle = Vector2.new(40, 40),
		Transparency = ns(0.2, 1), EmissionDirection = Enum.NormalId.Top, Shape = Enum.ParticleEmitterShape.Sphere})
end
PRESETS.Drip = function(part, core, cs, s)
	local drip = attach(part, "FX_Drip", Vector3.new(0, -part.Size.Y * 0.45, 0))
	emitter(drip, "FX_Drops", {Texture = TEX.glow, Color = cs, Rate = 3, Lifetime = NumberRange.new(0.6, 0.9), LightEmission = 0.4,
		Size = ns(0.18 * s, 0.05 * s), Speed = NumberRange.new(0), Acceleration = Vector3.new(0, -8 * s, 0), EmissionDirection = Enum.NormalId.Bottom})
end
PRESETS.Ring = function(part, core, cs, s)
	ring(part, "Ring", part.Size.X * 0.75, math.rad(18), cs, 0.08 * s)
end
PRESETS.DoubleRing = function(part, core, cs, s)
	ring(part, "Ring", part.Size.X * 0.75, math.rad(18), cs, 0.07 * s)
	ring(part, "Ring2", part.Size.X * 0.9, math.rad(-28), cs, 0.05 * s)
end
PRESETS.Halo = function(part, core, cs, s)
	-- a small ring floating over the top
	local top = Instance.new("Attachment") top.Name = "FX_HaloCenter" top.Position = Vector3.new(0, part.Size.Y * 0.62, 0) top.Parent = part
	local rad = part.Size.X * 0.3
	local l = Instance.new("Attachment") l.Name = "FX_HaloL"
	local r = Instance.new("Attachment") r.Name = "FX_HaloR"
	local axis = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	l.CFrame = CFrame.new(-rad, part.Size.Y * 0.62, 0) * axis
	r.CFrame = CFrame.new(rad, part.Size.Y * 0.62, 0) * axis
	l.Parent, r.Parent = part, part
	for i, side in {1, -1} do
		local b = Instance.new("Beam")
		b.Name = "FX_Halo" .. i
		b.Attachment0, b.Attachment1 = l, r
		b.CurveSize0, b.CurveSize1 = rad * 4 / 3 * side, -rad * 4 / 3 * side
		b.Width0, b.Width1 = 0.07 * s, 0.07 * s
		b.Color = cs
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Segments = 16
		b.Parent = part
	end
end

local function addFX(part, spec)
	if type(spec) ~= "table" then return end
	local s = part.Size.Y / 2.4 -- (sizes above are for a ~2.4 stud tall balloon)
	local core = attach(part, "FX_Core")
	local cs = colors(spec.FXColor or spec.Color, spec.FXColor2)
	for _, name in spec.FX or {} do
		local fn = PRESETS[name]
		if fn then fn(part, core, cs, s) else warn("[BalloonLook] unknown effect " .. tostring(name)) end
	end
	local g = spec.Glow
	if g then
		local light = core:FindFirstChild("Glow") or Instance.new("PointLight")
		light.Name = "Glow"
		if typeof(g) == "Color3" then light.Color = g light.Brightness = 1.5 light.Range = 8 * s
		elseif type(g) == "table" then light.Color = firstColor(g.Color) light.Brightness = g.Brightness or 1.5 light.Range = (g.Range or 8) * s end
		light.Parent = core
	end
end

-- a new balloon from a Look (base = a copy of the Shape's MeshPart)
function M.Build(base, look)
	local part = base
	-- the shape's own effects go
	for _, c in part:GetChildren() do
		if c:IsA("Attachment") or c:IsA("Beam") or c:IsA("Light") or c:IsA("ParticleEmitter") or c:IsA("SurfaceAppearance") then c:Destroy() end
	end
	if look.KeepTexture ~= true and part:IsA("MeshPart") then pcall(function() part.TextureID = "" end) end
	if typeof(look.Color) == "Color3" then part.Color = look.Color end
	if look.Material then
		local ok, mat = pcall(function() return Enum.Material[look.Material] end)
		if ok and mat then part.Material = mat end
	end
	part.Reflectance = look.Reflectance or 0
	part.Transparency = look.Transparency or 0
	addFX(part, look)
	return part
end

-- extra effects on a balloon that has its own model
function M.Extra(part, extra) addFX(part, extra) return part end

return M
