-- CARD FX (client): balloon effects on the menu pictures + the pictures turning round and round.
-- ViewportFrames can't show particles / beams, so the effects are drawn in 2D over the picture instead, from the
-- balloon's effects in SkinConfig (Look.FX / ExtraFX, FXColor):
--   glow (Aura, Fire, Implode, Glow...)   spinning ring (Ring, DoubleRing, Halo, Vortex)   sparkles (Sparkles, Stars,
--   Snow, Embers, Bubbles, Drip)
-- Settings > Other > Balloon Effects (MenuBalloonFX) turns them off (the turning stays).
--   CardFX.Attach(viewportFrame, balloonId)   -- call after the balloon is in the ViewportFrame
--   CardFX.Spin(viewportFrame)                -- only the turning (no effects)
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Skins = require(script.Parent:WaitForChild("SkinConfig"))
local M = {}

M.SpinSpeed = 45 -- degrees per second the pictures turn
M.SettingKey = "MenuBalloonFX"

local GS
local function fxOn()
	GS = GS or require(RS:WaitForChild("GameSettings"))
	local ok, v = pcall(GS.Get, M.SettingKey)
	return not ok or v ~= false
end

local RING = {Ring = true, DoubleRing = true, Halo = true, Vortex = true}
local GLOW = {Aura = true, Fire = true, Implode = true, Smoke = true}
local SPARK = {Sparkles = true, Stars = true, Snow = true, Embers = true, Bubbles = true, Drip = true}

local entries = setmetatable({}, {__mode = "k"}) -- [viewport] = {overlay, parts..., colors}

local function specOf(id)
	local s = Skins.ById[id or ""]
	if not s then return nil end
	local spec = s.Look or s.ExtraFX
	if not spec then return nil end
	local fx = {}
	for _, n in spec.FX or {} do fx[n] = true end
	local rar = Skins.Rarities[s.Rarity] or Skins.Rarities.Common
	local c1 = spec.FXColor
	if c1 == nil and spec.Glow then c1 = typeof(spec.Glow) == "Color3" and spec.Glow or spec.Glow.Color end
	c1 = c1 or rar.Color
	local c2 = typeof(spec.FXColor2) == "Color3" and spec.FXColor2 or (typeof(c1) == "Color3" and c1 or nil)
	local ring, glow, spark = false, spec.Glow ~= nil or (rar.Order or 0) >= 4, false
	for n in fx do
		if RING[n] then ring = true end
		if GLOW[n] then glow = true end
		if SPARK[n] then spark = true end
	end
	if not (ring or glow or spark) then return nil end
	return {Ring = ring, Glow = glow, Spark = spark, C1 = c1, C2 = c2, RainbowBody = spec.RainbowBody == true}
end

local function circle(parent, name, scale, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(scale, scale)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	local ar = Instance.new("UIAspectRatioConstraint") ar.Parent = f
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(1, 0) c.Parent = f
	f.Parent = parent
	return f
end

local function model(vp)
	for _, c in vp:GetChildren() do
		if c:IsA("BasePart") or c:IsA("Model") then return c end
		if c:IsA("WorldModel") then
			for _, d in c:GetChildren() do if d:IsA("BasePart") or d:IsA("Model") then return d end end
		end
	end
end

function M.Spin(vp)
	if not vp then return end
	local e = entries[vp] or {}
	e.spinOnly = e.overlay == nil
	entries[vp] = e
end

function M.Attach(vp, id)
	if not vp then return end
	local old = entries[vp]
	if old and old.overlay then old.overlay:Destroy() end
	local e = {id = id}
	entries[vp] = e
	local spec = specOf(id)
	e.spec = spec
	if not spec then return end
	-- the overlay sits exactly on the picture (a sibling, so it isn't cut off by the ViewportFrame)
	local o = Instance.new("Frame")
	o.Name = vp.Name .. "_FX"
	o.BackgroundTransparency = 1
	o.AnchorPoint, o.Position, o.Size = vp.AnchorPoint, vp.Position, vp.Size
	o.ZIndex = vp.ZIndex
	o.Active = false
	o.LayoutOrder = vp.LayoutOrder
	e.overlay = o
	if spec.Glow then
		local g = circle(o, "Glow", 0.85, vp.ZIndex)
		g.BackgroundTransparency = 0.72
		local gr = Instance.new("UIGradient")
		gr.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1)})
		gr.Parent = g
		e.glow, e.glowGrad = g, gr
	end
	if spec.Ring then
		local r = circle(o, "Ring", 0.95, vp.ZIndex + 1)
		local st = Instance.new("UIStroke") st.Thickness = 2 st.Transparency = 0.1 st.Parent = r
		local gr = Instance.new("UIGradient")
		gr.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0)})
		gr.Parent = st
		e.ring, e.ringStroke, e.ringGrad = r, st, gr
	end
	if spec.Spark then
		e.sparks = {}
		for i = 1, 5 do
			local sp = Instance.new("Frame")
			sp.Name = "Spark"
			sp.AnchorPoint = Vector2.new(0.5, 0.5)
			sp.BorderSizePixel = 0
			sp.Rotation = 45
			sp.ZIndex = vp.ZIndex + 2
			sp.Size = UDim2.fromOffset(0, 0)
			sp.Parent = o
			e.sparks[i] = {f = sp, t = math.random() * 1.2, pos = Vector2.new(math.random(), math.random())}
		end
	end
	o.Parent = vp.Parent
	-- follows the picture if it's moved / hidden
	vp:GetPropertyChangedSignal("Visible"):Connect(function() o.Visible = vp.Visible and fxOn() end)
	vp.Destroying:Connect(function() o:Destroy() end)
end

local function colorAt(spec, t, which)
	if spec.C1 == "Rainbow" then return Color3.fromHSV((t * 0.25 + (which or 0) * 0.33) % 1, 0.75, 1) end
	if which == 1 and spec.C2 then return spec.C1:Lerp(spec.C2, (math.sin(t * 2) + 1) / 2) end
	return spec.C1
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local on = fxOn()
	for vp, e in entries do
		if not vp.Parent then entries[vp] = nil continue end
		-- (only what's actually on screen)
		if vp.AbsoluteSize.X < 2 then continue end
		local gui = vp:FindFirstAncestorWhichIsA("LayerCollector")
		if gui and gui:IsA("ScreenGui") and not gui.Enabled then continue end
		-- turn round
		local m = model(vp)
		if m then
			local rot = CFrame.Angles(0, math.rad(M.SpinSpeed) * dt, 0)
			if m:IsA("BasePart") then m.CFrame = rot * m.CFrame else m:PivotTo(rot * m:GetPivot()) end
			if e.spec and e.spec.RainbowBody and m:IsA("BasePart") then m.Color = Color3.fromHSV((t * 0.15) % 1, 0.45, 1) end
		end
		local o = e.overlay
		if o then
			if on ~= (o.Visible) and vp.Visible then o.Visible = on end
			if on then
				local spec = e.spec
				if e.glow then
					e.glow.BackgroundColor3 = colorAt(spec, t, 0)
					e.glowGrad.Rotation = (t * 40) % 360
					e.glow.BackgroundTransparency = 0.7 + math.sin(t * 2.2) * 0.06
				end
				if e.ring then
					e.ringStroke.Color = colorAt(spec, t, 1)
					e.ringGrad.Rotation = (t * 160) % 360
				end
				if e.sparks then
					for _, s in e.sparks do
						s.t += dt
						local life = 1.1
						if s.t > life then
							s.t -= life
							local a = math.random() * math.pi * 2
							local r = 0.28 + math.random() * 0.2
							s.pos = Vector2.new(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r)
							s.f.BackgroundColor3 = colorAt(spec, t + math.random(), 2)
						end
						local k = s.t / life
						local size = math.sin(k * math.pi) * 7
						s.f.Position = UDim2.fromScale(s.pos.X, s.pos.Y - k * 0.06)
						s.f.Size = UDim2.fromOffset(size, size)
						s.f.BackgroundTransparency = 0.1 + k * 0.5
					end
				end
			end
		end
	end
end)

return M
