-- Draws the crosshair from the Crosshair settings (ReplicatedStorage > GameSettings) inside a container frame.
-- Used for the real crosshair (BalloonCombatUI > Crosshair) and the preview in Settings > Crosshair.
local GS = require(script.Parent:WaitForChild("GameSettings"))
local B = {}

local function part(container, name, size, pos, color, outline, round)
	local thick = (GS.Get("OutlineThickness") or 1)
	local f = Instance.new("Frame")
	f.Name = "CH_" .. name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, pos.X, 0.5, pos.Y)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if round then local c = Instance.new("UICorner") c.CornerRadius = UDim.new(1, 0) c.Parent = f end
	if outline then local s = Instance.new("UIStroke") s.Color = Color3.new(0, 0, 0) s.Thickness = thick * (B.scale or 1) s.Transparency = 0.2 s.Parent = f end
	f.Parent = container
	return f
end

-- an ID can be an image ID or a decal ID: an image ID is used as it is; if it doesn't load (a decal ID), the
-- decal's picture is used instead (remembered per ID)
local resolved = {} -- [id] = content string
local checking = {}
local ContentProvider = game:GetService("ContentProvider")
B.Changed = Instance.new("BindableEvent") -- fires when an ID turned out to be a decal (so crosshairs redraw)
function B.ImageFor(id)
	if resolved[id] then return resolved[id] end
	local asImage = "rbxassetid://" .. id
	if not checking[id] then
		checking[id] = true
		task.spawn(function()
			local status
			pcall(function() ContentProvider:PreloadAsync({asImage}, function(_, s) status = s end) end)
			if status ~= Enum.AssetFetchStatus.Success then
				resolved[id] = ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(id)
				B.Changed:Fire()
			else
				resolved[id] = asImage
			end
		end)
	end
	return asImage
end

-- scale: 1 = real size (preview can draw bigger)
function B.Draw(container, scale)
	scale = scale or 1
	B.scale = scale
	for _, c in container:GetChildren() do if c.Name:sub(1, 3) == "CH_" then c:Destroy() end end
	local color = GS.ToColor(GS.Get("DotColor"))
	local outline = GS.Get("CrossOutline")
	local size = GS.Get("DotSize") * scale
	local style = GS.Get("DotStyle")
	if style == "Dot" then
		part(container, "Dot", Vector2.new(size, size), Vector2.zero, color, outline, true)
	elseif style == "Circle" then
		local ring = part(container, "Ring", Vector2.new(size * 2 + 4, size * 2 + 4), Vector2.zero, color, false, true)
		ring.BackgroundTransparency = 1
		local s = Instance.new("UIStroke") s.Color = color s.Thickness = math.max(1, math.floor(size / 3 + 0.5)) s.Parent = ring
	elseif style == "Image" then
		-- your own crosshair: an image or decal ID (Settings > Crosshair > Crosshair ID)
		local id = tostring(GS.Get("CrosshairImage") or ""):match("%d+")
		if id then
			local px = (GS.Get("CrosshairImageSize") or 32) * scale
			local img = Instance.new("ImageLabel")
			img.Name = "CH_Image"
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromOffset(px, px)
			img.ScaleType = Enum.ScaleType.Fit
			img.ImageColor3 = GS.Get("CrosshairImageTint") and color or Color3.new(1, 1, 1)
			img.Image = B.ImageFor(id)
			img.Parent = container
		end
	elseif style == "Cross" then
		local t = math.max(1, math.floor(size / 3 + 0.5))
		part(container, "CrossH", Vector2.new(size * 2, t), Vector2.zero, color, outline, false)
		part(container, "CrossV", Vector2.new(t, size * 2), Vector2.zero, color, outline, false)
	end
	if GS.Get("CrossLines") then
		local len, gap, thick = 7 * scale, size / 2 + 4 * scale, math.max(2, math.floor(2 * scale))
		part(container, "LineL", Vector2.new(len, thick), Vector2.new(-(gap + len / 2), 0), color, outline)
		part(container, "LineR", Vector2.new(len, thick), Vector2.new(gap + len / 2, 0), color, outline)
		part(container, "LineU", Vector2.new(thick, len), Vector2.new(0, -(gap + len / 2)), color, outline)
		part(container, "LineD", Vector2.new(thick, len), Vector2.new(0, gap + len / 2), color, outline)
	end
end

return B
