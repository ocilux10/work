-- QUEUE PAD COLOURS + GLOW (per player)
-- The circle you're standing on glows GREEN. The opposite circle glows RED until that side has
-- enough players (full), then it lights up GREEN too.
-- Pads you're not on: a circle with people on it glows green, empty ones keep their normal colour.
-- Every lit circle gets a soft pulsing glow (a light on the floor + the neon breathing).
-- Tweak with attributes on this script: GlowRange, GlowBrightness, PulseSpeed, PulseAmount (0 = no pulse).
-- MatchmakingServer tags each circle "QueueCircle" with QueueArea / QueueTeam / QueueMembers / QueueSize.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local GREEN = Color3.fromRGB(0, 255, 0)
local RED = Color3.fromRGB(255, 0, 0)

local function attr(name, default)
	local v = script:GetAttribute(name)
	if v == nil then script:SetAttribute(name, default) return default end
	return v
end

local original = {}     -- [neon part] = {color, transparency}
local lit = {}          -- [circle] = colour it's lit with (nil = not lit)
local lights = {}       -- [circle] = PointLight holder part

local function neonParts(circle)
	local list = {}
	for _, d in circle:GetDescendants() do
		if d:IsA("BasePart") and (d.Material == Enum.Material.Neon or original[d]) then
			if not original[d] then original[d] = {d.Color, d.Transparency} end
			table.insert(list, d)
		end
	end
	return list
end

local function members(circle)
	local s = circle:GetAttribute("QueueMembers") or ""
	local n = 0
	for _ in s:gmatch("%d+") do n += 1 end
	return n, s
end
local function hasMe(circle)
	local _, s = members(circle)
	return string.find(s, "," .. player.UserId .. ",", 1, true) ~= nil
end
local function isFull(circle)
	local size = circle:GetAttribute("QueueSize") or 1
	return members(circle) >= size
end

local function lightFor(circle)
	local holder = lights[circle]
	if holder and holder.Parent then return holder end
	local cf = circle:GetBoundingBox()
	holder = Instance.new("Part")
	holder.Name = "PadGlow"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(cf.Position + Vector3.new(0, 2, 0))
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Parent = holder
	holder.Parent = workspace.CurrentCamera -- local only
	lights[circle] = holder
	return holder
end

local function paint()
	local byArea = {}
	for _, c in CollectionService:GetTagged("QueueCircle") do
		local a = c:GetAttribute("QueueArea")
		if a then
			byArea[a] = byArea[a] or {}
			table.insert(byArea[a], c)
		end
	end
	for _, circles in byArea do
		local mine
		for _, c in circles do if hasMe(c) then mine = c end end
		for _, c in circles do
			local color
			if mine then
				-- your side green; the other side red until it has enough players, then green
				color = (c == mine or isFull(c)) and GREEN or RED
			elseif members(c) > 0 then
				color = GREEN
			end
			lit[c] = color
			for _, part in neonParts(c) do
				part.Color = color or original[part][1]
				if not color then part.Transparency = original[part][2] end
			end
			local holder = lights[c]
			if color then
				holder = lightFor(c)
				holder.PointLight.Color = color
				holder.PointLight.Enabled = true
			elseif holder and holder.Parent then
				holder.PointLight.Enabled = false
			end
		end
	end
end

-- the pulse: light brightness + neon "breathing"
RunService.RenderStepped:Connect(function()
	local speed, amount = attr("PulseSpeed", 2.2), attr("PulseAmount", 0.35)
	local range, bright = attr("GlowRange", 14), attr("GlowBrightness", 2.5)
	local wave = (math.sin(os.clock() * speed * math.pi) + 1) / 2 -- 0..1
	for c, color in lit do
		if not c.Parent then lit[c] = nil continue end
		if color then
			local holder = lights[c]
			if holder and holder.Parent then
				holder.PointLight.Range = range
				holder.PointLight.Brightness = bright * (1 - amount + amount * wave)
			end
			for _, part in neonParts(c) do
				part.Transparency = original[part][2] + (1 - original[part][2]) * amount * 0.5 * (1 - wave)
			end
		end
	end
end)

local hooked = {}
local function hook(c)
	if hooked[c] then return end
	hooked[c] = true
	c:GetAttributeChangedSignal("QueueMembers"):Connect(paint)
	c.DescendantAdded:Connect(function() task.defer(paint) end) -- parts streaming in
	paint()
end
for _, c in CollectionService:GetTagged("QueueCircle") do hook(c) end
CollectionService:GetInstanceAddedSignal("QueueCircle"):Connect(hook)
