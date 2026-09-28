-- SHOP LAYOUT (Main > ShopFrame > ScrollingFrame)
-- 1) The sections filled by scripts (chests, exclusives, passes) are made exactly as tall as what's in them, and
--    everything under them moves up / down to match - no gap when there are fewer passes than cards in Studio, and
--    the chests go onto a second row when there are more than fit on one.
-- 2) The top bar tabs (ShopFrame > TopBar > Tabs) scroll to their section: a tab goes to the heading with the same text
--    ("Crates" -> CRATES). A tab's SectionName attribute can point it at any heading / section by name instead.
-- Sizes in Studio are kept as the starting point every time (edit them there as usual).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local FIT = {"CratesSection1", "ExclusiveSection1", "PassesSection1"} -- sections made to fit their content
local WRAP = {CratesSection1 = true}                                   -- sections that go onto more rows when full
local GAP = 8                                                          -- pixels above a heading when a tab scrolls to it

local scroll, shop
local orig = {}       -- [GuiObject] = {Position, Size} as designed
local origCanvas
local busy, again = false, false

local function remember(o)
	if not orig[o] then orig[o] = {Position = o.Position, Size = o.Size} end
end

-- everything is worked out from the DESIGN sizes (scales) and the scrolling frame's own size - never from sizes read
-- back after changing something (Roblox only updates those on the next frame, so they'd be stale)
local function reflow()
	if not scroll or not scroll.Parent or not origCanvas then return end
	if busy then again = true return end
	busy = true
	local winW = scroll.AbsoluteWindowSize.X
	local canvasPx = origCanvas.Y.Scale * scroll.AbsoluteSize.Y + origCanvas.Y.Offset
	if winW < 2 or canvasPx < 2 then busy = false return end
	local moves = {} -- {top = designed Y scale, delta = px}
	for _, name in FIT do
		local sec = scroll:FindFirstChild(name)
		local lay = sec and sec:FindFirstChildWhichIsA("UIListLayout")
		local o = sec and orig[sec]
		if sec and lay and o then
			local secH = o.Size.Y.Scale * canvasPx + o.Size.Y.Offset
			local secW = o.Size.X.Scale * winW + o.Size.X.Offset
			-- the layout's design padding (saved once)
			if lay:GetAttribute("DesignPad") == nil then lay:SetAttribute("DesignPad", lay.Padding.Scale) lay:SetAttribute("DesignPadOff", lay.Padding.Offset) end
			local pad = sec:FindFirstChildOfClass("UIPadding")
			if pad and pad:GetAttribute("DesignTop") == nil then
				pad:SetAttribute("DesignTop", pad.PaddingTop.Scale) pad:SetAttribute("DesignTopOff", pad.PaddingTop.Offset)
				pad:SetAttribute("DesignBottom", pad.PaddingBottom.Scale) pad:SetAttribute("DesignBottomOff", pad.PaddingBottom.Offset)
			end
			local top = pad and (pad:GetAttribute("DesignTop") * secH + pad:GetAttribute("DesignTopOff")) or 0
			local bottom = pad and (pad:GetAttribute("DesignBottom") * secH + pad:GetAttribute("DesignBottomOff")) or 0
			local vertical = lay.FillDirection == Enum.FillDirection.Vertical
			local gap = lay:GetAttribute("DesignPad") * (vertical and secH or secW) + lay:GetAttribute("DesignPadOff")
			-- the shown cards, in pixels from their design size
			local count, sumH, cardW, cardH = 0, 0, 0, 0
			for _, c in sec:GetChildren() do
				if c:IsA("GuiObject") then
					if c:GetAttribute("DesignSizeY") == nil then c:SetAttribute("DesignSizeY", c.Size.Y.Scale) c:SetAttribute("DesignSizeYOff", c.Size.Y.Offset) end
					local w = c.Size.X.Scale * secW + c.Size.X.Offset
					local h = c:GetAttribute("DesignSizeY") * secH + c:GetAttribute("DesignSizeYOff")
					-- a UIAspectRatioConstraint decides the real size (it keeps the card inside w x h at its ratio)
					local ar = c:FindFirstChildOfClass("UIAspectRatioConstraint")
					if ar and ar.AspectRatio > 0 then
						if w / h > ar.AspectRatio then w = h * ar.AspectRatio else h = w / ar.AspectRatio end
					end
					c.Size = UDim2.new(c.Size.X.Scale, c.Size.X.Offset, 0, c:GetAttribute("DesignSizeY") * secH + c:GetAttribute("DesignSizeYOff"))
					if c.Visible then
						count += 1
						sumH += h
						cardH = math.max(cardH, h)
						cardW = math.max(cardW, w)
					end
				end
			end
			local content
			if vertical then
				content = sumH + gap * math.max(count - 1, 0)
				lay.Padding = UDim.new(0, gap)
			else
				-- (a little tolerance: designs are often a hair wider than the row and still sit on one line)
				local perRow = math.max(1, math.floor((secW + gap) / math.max(cardW + gap, 1) + 0.06))
				-- wrap only when there really are more than fit (turning it on otherwise could drop a card to a new row)
				lay.Wraps = WRAP[name] == true and count > perRow
				local rows = lay.Wraps and math.max(1, math.ceil(count / perRow)) or 1
				content = rows * cardH
			end
			if pad then pad.PaddingTop = UDim.new(0, top) pad.PaddingBottom = UDim.new(0, bottom) end
			local need = math.ceil(top + content + bottom + 2)
			-- (safety: never squash a section that has cards to almost nothing)
			if count > 0 and need < secH * 0.25 then need = secH end
			sec.Size = UDim2.new(o.Size.X.Scale, o.Size.X.Offset, 0, need)
			table.insert(moves, {top = o.Position.Y.Scale, delta = need - secH})
		end
	end
	-- everything below a section that changed moves by that much
	local total = 0
	for _, mv in moves do total += mv.delta end
	for obj, v in orig do
		if obj.Parent == scroll then
			local shift = 0
			for _, mv in moves do if v.Position.Y.Scale > mv.top + 1e-4 then shift += mv.delta end end
			obj.Position = v.Position + UDim2.fromOffset(0, shift)
		end
	end
	scroll.CanvasSize = origCanvas + UDim2.fromOffset(0, total)
	busy = false
	if again then again = false task.defer(reflow) end
end

------------------------------------------------------------ TABS
local function headingFor(b)
	local want = b:GetAttribute("SectionName")
	if want and scroll:FindFirstChild(want) then return scroll[want] end
	local txt = (b:IsA("TextButton") and b.Text ~= "" and b.Text) or (b:FindFirstChildWhichIsA("TextLabel", true) and b:FindFirstChildWhichIsA("TextLabel", true).Text) or b.Name
	for _, c in scroll:GetChildren() do
		if c:IsA("TextLabel") and c.Text:lower() == txt:lower() then return c end
	end
end
local function scrollTo(target)
	task.wait() -- (after the crate view closes and the list is back)
	local y = target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y - GAP
	y = math.clamp(y, 0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y))
	TweenService:Create(scroll, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {CanvasPosition = Vector2.new(0, y)}):Play()
end

------------------------------------------------------------ HOOK (again after every respawn)
local function hook(main)
	shop = main:WaitForChild("ShopFrame", 10)
	if not shop then return end
	scroll = shop:WaitForChild("ScrollingFrame")
	table.clear(orig)
	origCanvas = scroll.CanvasSize
	for _, c in scroll:GetChildren() do if c:IsA("GuiObject") then remember(c) end end
	local tabs = shop:FindFirstChild("TopBar") and shop.TopBar:FindFirstChild("Tabs")
	if tabs then
		for _, b in tabs:GetChildren() do
			if b:IsA("GuiButton") then
				b.Activated:Connect(function()
					local h = headingFor(b)
					if h then task.spawn(scrollTo, h) end
				end)
			end
		end
	end
	-- fit the sections whenever the shop opens / the screen changes size (chest / pass cards are made by other scripts)
	shop:GetPropertyChangedSignal("Visible"):Connect(function() if shop.Visible then task.delay(0.05, reflow) end end)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if shop.Visible then task.defer(reflow) end end)
	task.delay(1, reflow)
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
