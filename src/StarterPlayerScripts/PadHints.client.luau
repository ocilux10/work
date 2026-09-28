-- CONTROLLER BUTTON ICONS on the UI (only while playing on a controller)
-- Put a "PadHint" attribute (text) on any button / label and the real controller button picture shows on it:
--   an action name ("Swing", "LeaveArena", "ReplayPause" ...) = the button bound to it (follows rebinding), or
--   a button name ("ButtonA", "ButtonB", "ButtonL1", "ButtonSelect", "DPadDown" ...).
-- PlayStation or Xbox pictures: Settings > Controls > Button Names (Auto = whatever controller is plugged in).
-- Optional, on the same object:
--   PadHintSide  "Corner" (default: top-right corner) / "Left" / "Right" / "Top" / "Bottom" (just outside that edge)
--                "InLeft" / "InRight" (just inside) / "TopLeft" / "TopRight" (above, at that end) / "Center" / "Replace" (hides its text, the icon goes in its place)
--   PadHintSize  icon size as a fraction of the object's height (default: the template's Size attribute)
--   PadHint2 / PadHintSide2 / PadHintSize2 = a second icon on the same object
-- (not on a frame that has a UIListLayout / UIGridLayout inside - the layout would move the icon; use one of its buttons)
-- Icon look: ReplicatedStorage > PadHintTemplate (ImageLabel + SizeLimit min / max pixels). Changes show live.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local GS = require(RS:WaitForChild("GameSettings"))
local template = RS:WaitForChild("PadHintTemplate")

local SIDES = {
	Corner = {Vector2.new(0.5, 0.5), UDim2.new(1, -2, 0, 2)},
	Left = {Vector2.new(1, 0.5), UDim2.new(0, -6, 0.5, 0)},
	Right = {Vector2.new(0, 0.5), UDim2.new(1, 6, 0.5, 0)},
	Top = {Vector2.new(0.5, 1), UDim2.new(0.5, 0, 0, -4)},
	Bottom = {Vector2.new(0.5, 0), UDim2.new(0.5, 0, 1, 4)},
	InLeft = {Vector2.new(0, 0.5), UDim2.new(0, 6, 0.5, 0)},
	InRight = {Vector2.new(1, 0.5), UDim2.new(1, -6, 0.5, 0)},
	TopLeft = {Vector2.new(0, 1), UDim2.new(0, 4, 0, -4)},
	TopRight = {Vector2.new(1, 1), UDim2.new(1, -4, 0, -4)},
	Center = {Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)},
	Replace = {Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)},
}
local SLOTS = {"", "2"}
local watched = {} -- [gui] = {[slot] = icon}

local function keyFor(v)
	if type(v) ~= "string" or v == "" then return "" end
	if GS.IsPadKey(v) then return v end
	return GS.PadKey(v)
end
local function isText(o) return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") end
local function hideText(gui, on)
	if not isText(gui) then return end
	local saved = gui:GetAttribute("PadHintTextT")
	if on then
		if saved == nil then gui:SetAttribute("PadHintTextT", gui.TextTransparency) end
		gui.TextTransparency = 1
	elseif saved ~= nil then
		gui.TextTransparency = saved
		gui:SetAttribute("PadHintTextT", nil)
	end
end

local function paint(gui)
	local icons = watched[gui]
	if not icons then return end
	local replacing, padded = false, false
	for _, slot in SLOTS do
		local icon = icons[slot]
		local img = GS.UsingGamepad() and GS.KeyImage(keyFor(gui:GetAttribute("PadHint" .. slot))) or nil
		if not img then
			if icon then icon.Visible = false end
		else
			if not icon or icon.Parent ~= gui then
				if icon then icon:Destroy() end
				icon = template:Clone()
				icon.Name = "PadHint" .. slot
				icon.Parent = gui
				icons[slot] = icon
			end
			local side = gui:GetAttribute("PadHintSide" .. slot) or "Corner"
			local s = SIDES[side] or SIDES.Corner
			local frac = gui:GetAttribute("PadHintSize" .. slot) or template:GetAttribute("Size") or 0.6
			icon.AnchorPoint, icon.Position = s[1], s[2]
			-- a text button with the icon inside its edge: the text moves over to make room
			if (side == "InLeft" or side == "InRight") and isText(gui) then
				local lim = template:FindFirstChildOfClass("UISizeConstraint")
				local px = gui.AbsoluteSize.Y * frac
				if lim then px = math.clamp(px, lim.MinSize.Y, lim.MaxSize.Y) end
				local own = gui:FindFirstChild("PadHintPad")
				local other = false
				for _, c in gui:GetChildren() do if c:IsA("UIPadding") and c ~= own then other = true end end
				if not other then
					own = own or Instance.new("UIPadding")
					own.Name = "PadHintPad"
					own.PaddingLeft = UDim.new(0, side == "InLeft" and px + 6 or 0)
					own.PaddingRight = UDim.new(0, side == "InRight" and px + 6 or 0)
					own.Parent = gui
					icon.Position = side == "InLeft" and UDim2.new(0, -px, 0.5, 0) or UDim2.new(1, px, 0.5, 0)
				end
				padded = true
			end
			icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
			icon.Size = UDim2.fromScale(frac, frac)
			icon.ZIndex = gui.ZIndex + (template:GetAttribute("ZOffset") or 5)
			icon.Image = img
			icon.Visible = true
			if side == "Replace" then replacing = true end
		end
	end
	hideText(gui, replacing)
	if not padded then
		local own = gui:FindFirstChild("PadHintPad")
		if own then own:Destroy() end
	end
end

local function watch(gui)
	if watched[gui] or not gui:IsA("GuiObject") then return end
	if gui:GetAttribute("PadHint") == nil and gui:GetAttribute("PadHint2") == nil then return end
	watched[gui] = {}
	gui.AttributeChanged:Connect(function(a)
		if a:sub(1, 7) == "PadHint" and a ~= "PadHintTextT" then paint(gui) end
	end)
	gui.Destroying:Connect(function() watched[gui] = nil end)
	local sizing = false
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if sizing or not gui:FindFirstChild("PadHintPad") then return end
		sizing = true
		task.delay(0.1, function() sizing = false paint(gui) end)
	end)
	paint(gui)
end
for _, d in pg:GetDescendants() do watch(d) end
-- (a PadHint attribute added while playing is picked up within a couple of seconds)
task.spawn(function()
	while true do
		task.wait(2)
		for _, d in pg:GetDescendants() do
			if not watched[d] and d:IsA("GuiObject") then watch(d) end
		end
	end
end)
pg.DescendantAdded:Connect(function(d)
	if d.Name:sub(1, 7) == "PadHint" then return end -- (our own icons / padding)
	task.defer(watch, d)
end)

local function paintAll()
	for gui in watched do
		if gui.Parent then paint(gui) else watched[gui] = nil end
	end
end
GS.Changed:Connect(function(key)
	if type(key) == "string" and (key:sub(1, 4) == "Pad_" or key == "Key_InputMode" or key == "PadButtonStyle") then paintAll() end
end)
-- template edited (Studio / live): every icon is rebuilt from it
local pending = false
local function rebuild()
	if pending then return end
	pending = true
	task.delay(0.2, function()
		pending = false
		for gui, icons in watched do
			for slot, icon in icons do icon:Destroy() icons[slot] = nil end
		end
		paintAll()
	end)
end
template.Changed:Connect(rebuild)
template.AttributeChanged:Connect(rebuild)
template.DescendantAdded:Connect(rebuild)
template.DescendantRemoving:Connect(rebuild)
for _, d in template:GetDescendants() do d.Changed:Connect(rebuild) end
