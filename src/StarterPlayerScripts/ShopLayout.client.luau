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

local function reflow()
	if not scroll or not scroll.Parent then return end
	if busy then again = true return end
	busy = true
	-- back to the design
	for o, v in orig do if o.Parent then o.Position, o.Size = v.Position, v.Size end end
	if origCanvas then scroll.CanvasSize = origCanvas end
	for _, name in FIT do
		local sec = scroll:FindFirstChild(name)
		if sec then
			for _, c in sec:GetChildren() do
				if c:IsA("GuiObject") and c:GetAttribute("DesignSizeY") then
					c.Size = UDim2.new(c.Size.X.Scale, c.Size.X.Offset, c:GetAttribute("DesignSizeY"), c:GetAttribute("DesignSizeYOff") or 0)
				end
			end
			local lay = sec:FindFirstChildWhichIsA("UIListLayout")
			if lay and lay:GetAttribute("DesignPad") then lay.Padding = UDim.new(lay:GetAttribute("DesignPad"), lay:GetAttribute("DesignPadOff") or 0) end
		end
	end
	task.wait()
	-- fix what depends on the section's height in pixels, then let the section fit its content
	local moves = {} -- {top = designed Y, delta = px}
	for _, name in FIT do
		local sec = scroll:FindFirstChild(name)
		local lay = sec and sec:FindFirstChildWhichIsA("UIListLayout")
		if sec and lay and sec.AbsoluteSize.Y > 0 then
			for _, c in sec:GetChildren() do
				if c:IsA("GuiObject") then
					if c:GetAttribute("DesignSizeY") == nil then c:SetAttribute("DesignSizeY", c.Size.Y.Scale) c:SetAttribute("DesignSizeYOff", c.Size.Y.Offset) end
					c.Size = UDim2.new(c.Size.X.Scale, c.Size.X.Offset, 0, c.AbsoluteSize.Y)
				end
			end
			if lay:GetAttribute("DesignPad") == nil then lay:SetAttribute("DesignPad", lay.Padding.Scale) lay:SetAttribute("DesignPadOff", lay.Padding.Offset) end
			if lay.FillDirection == Enum.FillDirection.Vertical then
				lay.Padding = UDim.new(0, lay.Padding.Scale * sec.AbsoluteSize.Y + lay.Padding.Offset)
			end
			if WRAP[name] then lay.Wraps = true end
			local pad = sec:FindFirstChildOfClass("UIPadding")
			local top = pad and (pad.PaddingTop.Scale * sec.AbsoluteSize.Y + pad.PaddingTop.Offset) or 0
			local bottom = pad and (pad.PaddingBottom.Scale * sec.AbsoluteSize.Y + pad.PaddingBottom.Offset) or 0
			if pad then pad.PaddingTop = UDim.new(0, top) pad.PaddingBottom = UDim.new(0, bottom) end
			task.wait()
			local need = lay.AbsoluteContentSize.Y + top + bottom + 4
			local delta = need - sec.AbsoluteSize.Y
			sec.Size = UDim2.new(sec.Size.X.Scale, sec.Size.X.Offset, 0, need)
			table.insert(moves, {top = orig[sec].Position.Y.Scale, delta = delta})
		end
	end
	-- everything below a section that changed moves by that much
	local total = 0
	for _, mv in moves do total += mv.delta end
	for o, v in orig do
		if o.Parent == scroll then
			local shift = 0
			for _, mv in moves do if v.Position.Y.Scale > mv.top + 1e-4 then shift += mv.delta end end
			o.Position = v.Position + UDim2.fromOffset(0, shift)
		end
	end
	if origCanvas then scroll.CanvasSize = origCanvas + UDim2.fromOffset(0, total) end
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
