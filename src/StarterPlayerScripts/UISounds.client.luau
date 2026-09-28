-- AUTOMATIC BUTTON SOUNDS + ANIMATIONS (every button in every ScreenGui)
--   hover      -> grows a little with a bounce + tilts slightly        sound: Hover
--   leave      -> back to normal                                       sound: HoverLeave
--   press down -> squashes in                                          sound: ButtonPress
--   release    -> springs back (+ a quick pop when it was a click)     sound: Click  (ButtonRelease if you let go off it)
-- Per button (or on anything above it):
--   "NoClickSound" = true   -> no sounds          "ClickSound" / "HoverSound" = a SoundConfig name to use instead
--   "ClickSound" = ""       -> hover sounds only (the button plays its own click, e.g. buy buttons -> "Purchase")
--   "NoButtonFX" = true     -> no animation (on the button itself)   "HoverScale" / "PressScale" = numbers (default 1.035 / 0.95)
-- Whole ScreenGuis can be skipped for sounds: SoundConfig.NoButtonSoundsIn
-- Invisible click-catchers (see-through buttons with no text / image) laid over a small frame (like the party faces)
-- animate that frame instead, so every clickable thing tweens the same way.
-- All sounds: ReplicatedStorage > SoundConfig
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SFX = require(RS:WaitForChild("SFX"))
local Config = SFX.Config

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local skipGuis = {}
for _, n in Config.NoButtonSoundsIn or {} do skipGuis[n] = true end

local function flagged(button, attr)
	local o = button
	while o and o ~= pg do
		if o:GetAttribute(attr) then return true end
		o = o.Parent
	end
	return false
end
local function silent(button)
	if flagged(button, "NoClickSound") then return true end
	local g = button:FindFirstAncestorWhichIsA("LayerCollector")
	return g ~= nil and skipGuis[g.Name] == true
end
local function isHoverDevice() return UIS.MouseEnabled and not (UIS.TouchEnabled and not UIS.KeyboardEnabled) end

-- a see-through button with no text / image is just a click area laid over something: don't animate it
local function isOverlay(b)
	if b.BackgroundTransparency < 0.99 then return false end
	if b:IsA("TextButton") and b.Text ~= "" and b.TextTransparency < 1 then return false end
	if b:IsA("ImageButton") and b.Image ~= "" and b.ImageTransparency < 1 then return false end
	-- has visible stuff of its own inside (icon / label) -> it IS the button
	for _, c in b:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then return false end
	end
	return true
end

local hooked = setmetatable({}, {__mode = "k"})
local function hook(b)
	if hooked[b] or not b:IsA("GuiButton") then return end
	hooked[b] = true

	-- the animation uses its own UIScale ("ButtonFX"); a button that already has a UIScale keeps just the sounds
	local animate = not b:GetAttribute("NoButtonFX")
	local target = b -- what grows / tilts
	if animate and isOverlay(b) then
		-- a see-through click area covering a small frame: that frame is the "button" you see
		local p = b.Parent
		local covers = b.Size.X.Scale >= 0.95 and b.Size.Y.Scale >= 0.95
		if covers and p and p:IsA("GuiObject") and not p:IsA("GuiButton") and not p:IsA("ScrollingFrame") and not p:GetAttribute("NoButtonFX") then
			target = p
		else
			animate = false
		end
	end
	local scale
	if animate then
		local existing = target:FindFirstChildOfClass("UIScale")
		if existing and existing.Name ~= "ButtonFX" then
			animate = false
		else
			scale = existing or Instance.new("UIScale")
			scale.Name = "ButtonFX"
			scale.Parent = target
		end
	end
	local tb = b -- (below, "b" = the thing that animates; events still come from the real button)
	b = target
	-- grow from the MIDDLE (on all sides): a free-standing button is re-anchored to its centre (same spot on screen).
	-- Buttons inside a list/grid layout can't be re-anchored (the layout places them) - centre their layout instead.
	-- Buttons with their own script inside (they move themselves) are left alone.
	if animate then
		local inLayout = b.Parent and b.Parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
		local scripted = b:FindFirstChildWhichIsA("LuaSourceContainer") ~= nil
		local parent = b.Parent
		if not inLayout and not scripted and not b:GetAttribute("KeepAnchor") and parent and parent:IsA("GuiBase2d")
			and (b.AnchorPoint.X ~= 0.5 or b.AnchorPoint.Y ~= 0.5) and parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.Y > 0 then
			local ax, ay = b.AnchorPoint.X, b.AnchorPoint.Y
			local dx = (0.5 - ax) * b.AbsoluteSize.X / parent.AbsoluteSize.X
			local dy = (0.5 - ay) * b.AbsoluteSize.Y / parent.AbsoluteSize.Y
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = b.Position + UDim2.fromScale(dx, dy)
		end
	end
	local baseRot = b.Rotation
	-- the little hover tilt: only on exit / close buttons (or any button with the attribute Tilt = true)
	local TILT_NAMES = {Exit = true, Off = true, Close = true, X = true, CloseButton = true, ExitButton = true}
	local tilt = b:GetAttribute("Tilt")
	if tilt == nil then tilt = TILT_NAMES[b.Name] == true end
	local tiltRot = tilt and baseRot + 1.5 or baseRot
	local hovering, pressed = false, false
	local function hoverScale() return b:GetAttribute("HoverScale") or 1.035 end
	local function pressScale() return b:GetAttribute("PressScale") or 0.95 end
	local function to(s, rot, t, style, dir)
		if not animate or not scale.Parent then return end
		TweenService:Create(scale, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), {Scale = s}):Play()
		if rot then TweenService:Create(b, TweenInfo.new(t, Enum.EasingStyle.Quad), {Rotation = rot}):Play() end
	end

	tb.MouseEnter:Connect(function()
		if not isHoverDevice() or not b.Visible then return end
		hovering = true
		to(hoverScale(), tiltRot, 0.22)
		if not silent(tb) then SFX.Play(tb:GetAttribute("HoverSound") or "Hover") end
	end)
	tb.MouseLeave:Connect(function()
		if not hovering and not pressed then return end
		hovering, pressed = false, false
		to(1, baseRot, 0.2, Enum.EasingStyle.Quad)
		if isHoverDevice() and b.Visible and not silent(tb) then SFX.Play("HoverLeave") end
	end)
	tb.MouseButton1Down:Connect(function()
		pressed = true
		to(pressScale(), baseRot, 0.08, Enum.EasingStyle.Quad)
		if not silent(tb) then SFX.Play("ButtonPress") end
	end)
	tb.MouseButton1Up:Connect(function()
		if not pressed then return end
		pressed = false
		to(hovering and hoverScale() or 1, hovering and tiltRot or baseRot, 0.25)
	end)
	tb.Activated:Connect(function()
		-- click: a quick pop, then settle
		if animate then
			to(hoverScale() + 0.025, nil, 0.08, Enum.EasingStyle.Quad)
			task.delay(0.09, function() to(hovering and hoverScale() or 1, nil, 0.25) end)
		end
		local cs = tb:GetAttribute("ClickSound")
		if not silent(tb) and cs ~= "" then SFX.Play(cs or "Click") end
	end)
	-- finger / mouse let go somewhere else (no click)
	UIS.InputEnded:Connect(function(input)
		if not pressed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			task.defer(function()
				if not pressed then return end -- it was a click (MouseButton1Up already ran)
				pressed = false
				to(hovering and hoverScale() or 1, hovering and tiltRot or baseRot, 0.25)
				if not silent(tb) then SFX.Play("ButtonRelease") end
			end)
		end
	end)
	-- hidden / closed while hovered: reset so it doesn't reopen big
	tb:GetPropertyChangedSignal("Visible"):Connect(function()
		if not b.Visible and animate then
			hovering, pressed = false, false
			scale.Scale = 1
			b.Rotation = baseRot
		end
	end)
end

for _, d in pg:GetDescendants() do task.spawn(hook, d) end
pg.DescendantAdded:Connect(function(d) task.defer(hook, d) end)
-- buttons on walls / boards (SurfaceGuis out in the world: leaderboards, spectate wall...) get the same tweens
local function hookWorld(d)
	if d:IsA("GuiButton") and d:FindFirstAncestorWhichIsA("SurfaceGui") then hook(d) end
end
for _, d in workspace:GetDescendants() do task.spawn(hookWorld, d) end
workspace.DescendantAdded:Connect(function(d) if d:IsA("GuiButton") then task.defer(hookWorld, d) end end)

------------------------------------------------------------ TRAMPOLINE DUMMIES
local function hookTrampoline(t)
	if not (t:IsA("Model") and t.Name == "Trampoline") or hooked[t] then return end
	hooked[t] = true
	t:GetAttributeChangedSignal("Bounced"):Connect(function()
		local bp = t:FindFirstChild("BouncePart", true)
		SFX.Play("Trampoline", bp or t:GetPivot().Position)
	end)
end
for _, d in workspace:GetDescendants() do hookTrampoline(d) end
workspace.DescendantAdded:Connect(hookTrampoline)
