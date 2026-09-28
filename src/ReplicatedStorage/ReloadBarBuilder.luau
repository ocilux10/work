-- RELOAD BAR SHAPES (the balloon coming back after a throw). Used by the combat HUD (BalloonCombatClient) and the
-- preview in Settings > Crosshair. Settings: Reload Shape / Color / Background / Size / Distance.
--   Bar       under the crosshair (its look = StarterGui > BalloonCombatUI > ReloadBar, restyle freely)
--   Vertical  standing up on the right of the crosshair (same look as the bar, turned upright)
--   Ring      a ring of segments around the crosshair that light up
--   Dot       a small circle on the right of the crosshair that fills up
local M = {}

function M.Options(GS, scale)
	return {
		Style = GS.Get("ReloadStyle") or "Bar",
		Fill = GS.ToColor(GS.Get("ReloadColor")),
		Back = GS.ToColor(GS.Get("ReloadBackColor")),
		Size = GS.Get("ReloadSize") or 1,
		Distance = GS.Get("ReloadDistance") or 14,
		Scale = scale or 1,
	}
end

local function corner(p)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = p
end

-- a bar from the designed ReloadBar (or a plain one)
local function barFrom(template)
	local b
	if template then
		b = template:Clone()
		b.Visible = true
		for _, d in b:GetDescendants() do if d:IsA("LuaSourceContainer") then d:Destroy() end end
	else
		b = Instance.new("Frame")
		b.BorderSizePixel = 0
		corner(b)
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.BorderSizePixel = 0
		corner(f)
		f.Parent = b
	end
	b.Name = "Bar"
	return b, b:FindFirstChild("Fill")
end

-- builds the shape in `holder` (a 0 x 0 frame sitting on the crosshair). Returns set(fraction 0..1)
function M.Build(holder, o, template)
	local old = holder:FindFirstChild("Shape")
	if old then old:Destroy() end
	local shape = Instance.new("Frame")
	shape.Name = "Shape"
	shape.BackgroundTransparency = 1
	shape.Size = UDim2.fromOffset(0, 0)
	shape.ZIndex = holder.ZIndex
	shape.Parent = holder
	local k = o.Scale * o.Size
	local dist = o.Distance * o.Scale
	if o.Style == "Ring" then
		local n = 28
		local r = math.max(dist, 6 * o.Scale) + 4 * k
		local segs = {}
		for i = 1, n do
			local a = (i - 1) / n * math.pi * 2
			local seg = Instance.new("Frame")
			seg.Name = "Seg" .. i
			seg.BorderSizePixel = 0
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Size = UDim2.fromOffset(math.max(2.2 * k, 1), math.max(5 * k, 2))
			seg.Position = UDim2.fromOffset(math.sin(a) * r, -math.cos(a) * r)
			seg.Rotation = math.deg(a)
			corner(seg)
			seg.Parent = shape
			segs[i] = seg
		end
		return function(frac)
			local lit = math.floor(math.clamp(frac, 0, 1) * n + 0.5)
			for i, seg in segs do
				local on = i <= lit
				seg.BackgroundColor3 = on and o.Fill or o.Back
				seg.BackgroundTransparency = on and 0 or 0.3
			end
		end
	elseif o.Style == "Dot" then
		local d = math.max(12 * k, 4)
		local g = Instance.new("CanvasGroup") -- (clips the fill to the circle)
		g.Name = "Dot"
		g.BorderSizePixel = 0
		g.AnchorPoint = Vector2.new(0, 0.5)
		g.Position = UDim2.fromOffset(dist, 0)
		g.Size = UDim2.fromOffset(d, d)
		g.BackgroundColor3 = o.Back
		corner(g)
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.fromScale(0, 1)
		f.BackgroundColor3 = o.Fill
		f.Parent = g
		local ring = Instance.new("Frame")
		ring.Name = "Outline"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0, 0.5)
		ring.Position = g.Position
		ring.Size = g.Size
		corner(ring)
		local st = Instance.new("UIStroke") st.Color = Color3.new(0, 0, 0) st.Thickness = 1 st.Transparency = 0.3 st.Parent = ring
		g.Parent = shape
		ring.Parent = shape
		return function(frac) f.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1)) end
	elseif o.Style == "Vertical" then
		local b, f = barFrom(template)
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.fromOffset(dist, 0)
		b.Size = UDim2.fromOffset(math.max(5 * k, 2), math.max(40 * k, 8))
		b.BackgroundColor3 = o.Back
		b.Parent = shape
		if f then
			f.AnchorPoint = Vector2.new(0, 1)
			f.Position = UDim2.fromScale(0, 1)
			f.BackgroundColor3 = o.Fill
		end
		return function(frac) if f then f.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1)) end end
	end
	-- Bar
	local b, f = barFrom(template)
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.fromOffset(0, dist)
	b.Size = UDim2.fromOffset(math.max(44 * k, 8), math.max(5 * k, 2))
	b.BackgroundColor3 = o.Back
	b.Parent = shape
	if f then
		f.AnchorPoint = Vector2.new(0, 0)
		f.Position = UDim2.fromScale(0, 0)
		f.BackgroundColor3 = o.Fill
	end
	return function(frac) if f then f.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) end end
end

M.Keys = {"ReloadStyle", "ReloadColor", "ReloadBackColor", "ReloadSize", "ReloadDistance"}
return M
