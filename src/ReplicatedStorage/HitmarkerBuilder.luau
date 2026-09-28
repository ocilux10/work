-- HITMARKER DRAWING (used by the real hitmarker in BalloonCombatUI > UIController and the preview in Settings)
-- The look lives in StarterGui > BalloonCombatUI > Hitmarker: one frame per TYPE (X, Plus, Ring, Dot). Restyle any of
-- them freely. Each type has a Kind attribute that says how Settings' size / thickness / colour are put on it:
--   Kind = "Lines"  -> its Line frames (any number, any Rotation) = arms sticking out from the middle
--   Kind = "Ring"   -> its "Circle" frame: a ring (the circle's UIStroke = the ring line)
--   Kind = "Dot"    -> its "Circle" frame: a filled dot
-- NEW TYPE: duplicate one of them, rename it, then add that name to HitmarkerStyle's Options in ReplicatedStorage >
-- GameSettings (and it shows up in Settings).
local TweenService = game:GetService("TweenService")
local H = {}

local function base(o, prop)
	local key = "Base" .. prop
	local v = o:GetAttribute(key)
	if v == nil then v = o[prop] o:SetAttribute(key, v) end
	return v
end

-- opts: style, size, thick, color, scale (preview zoom)
function H.Apply(hm, opts)
	local k = opts.scale or 1
	local style = hm:FindFirstChild(opts.style or "X") or hm:FindFirstChild("X")
	for _, s in hm:GetChildren() do
		if s:IsA("GuiObject") then s.Visible = s == style end
	end
	if not style then return end
	local size, thick, color = (opts.size or 9) * k, (opts.thick or 2) * k, opts.color or Color3.new(1, 1, 1)
	local kind = style:GetAttribute("Kind") or "Lines"
	local gap = size * 0.55 + 3 * k -- (arms start a bit out from the middle so the crosshair stays clear)
	for _, o in style:GetDescendants() do
		if o:IsA("GuiObject") then o.BackgroundTransparency = base(o, "BackgroundTransparency") end
		if o:IsA("UIStroke") then o.Transparency = base(o, "Transparency") end
	end
	if kind == "Lines" then
		for _, l in style:GetChildren() do
			if l:IsA("GuiObject") then
				local a = math.rad(l.Rotation)
				local r = gap + size / 2
				l.Size = UDim2.fromOffset(size, thick)
				l.Position = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r)
				l.BackgroundColor3 = color
			end
		end
	else
		local c = style:FindFirstChild("Circle") or style:FindFirstChildWhichIsA("GuiObject")
		if c then
			if kind == "Ring" then
				local d = (gap + size * 0.35) * 2
				c.Size = UDim2.fromOffset(d, d)
				local ring = c:FindFirstChild("Ring") or c:FindFirstChildOfClass("UIStroke")
				if ring then ring.Thickness = thick ring.Color = color end
			else
				local d = size * 0.7 + thick
				c.Size = UDim2.fromOffset(d, d)
				c.BackgroundColor3 = color
			end
		end
	end
	return style
end

-- quick pop in, hold, fade out (duration = the whole thing)
function H.Flash(hm, style, duration, token, isCurrent)
	local pop = hm:FindFirstChildOfClass("UIScale")
	if pop then
		pop.Scale = hm:GetAttribute("PopScale") or 1.35
		TweenService:Create(pop, TweenInfo.new(math.min(0.12, duration * 0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end
	hm.Visible = true
	task.delay(duration * 0.4, function()
		if isCurrent and not isCurrent(token) then return end
		local ti = TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, o in style:GetDescendants() do
			if o:IsA("GuiObject") then TweenService:Create(o, ti, {BackgroundTransparency = 1}):Play() end
			if o:IsA("UIStroke") then TweenService:Create(o, ti, {Transparency = 1}):Play() end
		end
	end)
	task.delay(duration + 0.05, function()
		if isCurrent and not isCurrent(token) then return end
		hm.Visible = false
	end)
end

-- the colour to use for this hit, from the player's settings
function H.ColorFor(GS, head)
	if GS.Get("HitmarkerMatchCrosshair") then return GS.ToColor(GS.Get("DotColor")) end
	return GS.ToColor(head and GS.Get("HitmarkerHeadColor") or GS.Get("HitmarkerColor"))
end

function H.Options(GS, head, scale)
	return {style = GS.Get("HitmarkerStyle") or "X", size = GS.Get("HitmarkerSize"), thick = GS.Get("HitmarkerThickness"),
		color = H.ColorFor(GS, head), scale = scale}
end

return H
