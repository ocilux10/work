-- PLAYER CARD
-- Builds the little avatar tile used on the queue boards, the match scoreboard and the vote cards:
--   headshot + level (top left) + device icon (top right) + optional name underneath.
-- Device icons are drawn with Frames so no image uploads are needed.

local PlayerCard = {}

local WHITE = Color3.new(1, 1, 1)

local function box(parent, size, pos, filled)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = WHITE
	f.BackgroundTransparency = filled and 0 or 1
	f.BorderSizePixel = 0
	if not filled then
		local s = Instance.new("UIStroke")
		s.Color = WHITE
		s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	f.Parent = parent
	return f
end

-- device = "PC" | "Mobile" | "Console"
-- CUSTOM ICONS: put an ImageLabel (or any GuiObject) named PC / Mobile / Console inside
-- ReplicatedStorage > Matchmaking > DeviceIcons and it's used instead of the drawn icon.
function PlayerCard.DeviceIcon(device, parent)
	local custom = script.Parent:FindFirstChild("DeviceIcons")
	custom = custom and custom:FindFirstChild(device or "PC")
	if custom and custom:IsA("GuiObject") then
		local c = custom:Clone()
		c.Name = "Device"
		c.Visible = true
		c.Parent = parent
		return c
	end
	local holder = Instance.new("Frame")
	holder.Name = "Device"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent
	if device == "Mobile" then
		local body = box(holder, UDim2.fromScale(0.45, 0.85), UDim2.fromScale(0.5, 0.5), false)
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0.2, 0) c.Parent = body
		box(holder, UDim2.fromScale(0.15, 0.06), UDim2.fromScale(0.5, 0.8), true)
	elseif device == "Console" then
		local body = box(holder, UDim2.fromScale(0.9, 0.55), UDim2.fromScale(0.5, 0.55), false)
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0.45, 0) c.Parent = body
		box(holder, UDim2.fromScale(0.22, 0.07), UDim2.fromScale(0.3, 0.55), true)
		box(holder, UDim2.fromScale(0.07, 0.22), UDim2.fromScale(0.3, 0.55), true)
		box(holder, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.7, 0.5), true)
	else -- PC monitor
		box(holder, UDim2.fromScale(0.9, 0.6), UDim2.fromScale(0.5, 0.38), false)
		box(holder, UDim2.fromScale(0.1, 0.18), UDim2.fromScale(0.5, 0.78), true)
		box(holder, UDim2.fromScale(0.45, 0.08), UDim2.fromScale(0.5, 0.9), true)
	end
	return holder
end

-- WIN STREAK (bottom right): "\u{1F525}N", hidden when the streak is 0
local function streakLabel(parent, streak)
	local s = Instance.new("TextLabel")
	s.Name = "Streak"
	s.BackgroundTransparency = 1
	s.AnchorPoint = Vector2.new(1, 1)
	s.Position = UDim2.fromScale(0.97, 0.98)
	s.Size = UDim2.fromScale(0.62, 0.3)
	s.Font = Enum.Font.GothamBlack
	s.TextScaled = true
	s.TextXAlignment = Enum.TextXAlignment.Right
	s.TextColor3 = WHITE
	s.TextStrokeTransparency = 0.4
	s.Text = "\u{1F525}" .. tostring(streak or 0)
	s.Visible = (streak or 0) > 0
	s.ZIndex = 3
	s.Parent = parent
	return s
end

-- info = {UserId, Name, Level, Device, Streak}
-- opts = {ShowName = bool, TextScale = number}
-- CUSTOM TILE: if ReplicatedStorage > Matchmaking > PlayerCardTemplate exists (a Frame), it's cloned instead of
-- the built-in look. Any of these children get filled in if they exist:
--   Headshot (ImageLabel), Level (TextLabel), DeviceSlot (Frame), PlayerName (TextLabel)
local function fillTemplate(tile, info, opts, template)
	local card = template:Clone()
	card.Name = "Card"
	card.Visible = true
	card.Rotation = opts.Rotation or 0
	local head = card:FindFirstChild("Headshot", true)
	if head and head:IsA("ImageLabel") then
		head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(info.UserId or 1, 1))
	end
	local lvl = card:FindFirstChild("Level", true)
	if lvl and lvl:IsA("TextLabel") then lvl.Text = tostring(info.Level or 1) end
	local name = card:FindFirstChild("PlayerName", true)
	if name and name:IsA("TextLabel") then name.Text = info.Name or "" end
	local slot = card:FindFirstChild("DeviceSlot", true)
	if slot then PlayerCard.DeviceIcon(info.Device or "PC", slot) end
	local streak = card:FindFirstChild("Streak", true)
	if streak and streak:IsA("TextLabel") then
		streak.Text = "\u{1F525}" .. tostring(info.Streak or 0)
		streak.Visible = (info.Streak or 0) > 0
	elseif not streak then
		streakLabel(card, info.Streak)
	end
	card.Parent = tile
	return card
end

function PlayerCard.Fill(tile, info, opts)
	opts = opts or {}
	local old = tile:FindFirstChild("Card")
	if old then old:Destroy() end
	if not info then return end
	local template = script.Parent:FindFirstChild("PlayerCardTemplate")
	if template and template:IsA("GuiObject") then return fillTemplate(tile, info, opts, template) end

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 2
	card.Rotation = opts.Rotation or 0 -- for SurfaceGuis on rotated parts
	card.Parent = tile

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 1)
	head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(info.UserId or 1, 1))
	head.ZIndex = 2
	head.Parent = card
	local hc = Instance.new("UICorner") hc.CornerRadius = UDim.new(0.12, 0) hc.Parent = head

	local lvl = Instance.new("TextLabel")
	lvl.Name = "Level"
	lvl.BackgroundTransparency = 1
	lvl.Position = UDim2.fromScale(0.05, 0.02)
	lvl.Size = UDim2.fromScale(0.45, 0.28)
	lvl.Font = Enum.Font.GothamBlack
	lvl.TextScaled = true
	lvl.TextXAlignment = Enum.TextXAlignment.Left
	lvl.TextColor3 = WHITE
	lvl.TextStrokeTransparency = 0.4
	lvl.Text = tostring(info.Level or 1)
	lvl.ZIndex = 3
	lvl.Parent = card

	local dev = Instance.new("Frame")
	dev.Name = "DeviceSlot"
	dev.BackgroundTransparency = 1
	dev.AnchorPoint = Vector2.new(1, 0)
	dev.Position = UDim2.fromScale(0.96, 0.04)
	dev.Size = UDim2.fromScale(0.26, 0.26)
	dev.ZIndex = 3
	dev.Parent = card
	local icon = PlayerCard.DeviceIcon(info.Device or "PC", dev)
	for _, d in icon:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = 3 end end
	streakLabel(card, info.Streak)

	if opts.ShowName then
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.fromScale(0.5, 1.03)
		name.Size = UDim2.fromScale(1.4, opts.NameHeight or 0.25)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = WHITE
		name.TextStrokeTransparency = 0.5
		name.Text = info.Name or ""
		name.ZIndex = 3
		name.Parent = card
	end
	return card
end

return PlayerCard
