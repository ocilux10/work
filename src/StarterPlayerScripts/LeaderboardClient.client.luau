-- LEADERBOARDS (client): fills the boards in Workspace > Lobby > Kills / Wins / Level / WinStreak
-- from ReplicatedStorage > LeaderboardData (the server refreshes it every few minutes).
--   * rows: #place, headshot, display name, @username, amount (with commas: 13,861)
--   * the "You" row (Template2): your place (N/A when you have 0), your amount
--   * All Time / Monthly buttons switch that board for you only
--   * every text stays on ONE line and shrinks to fit (long names, big numbers)
-- Settings: ReplicatedStorage > LeaderboardConfig
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local player = Players.LocalPlayer
local C = require(RS:WaitForChild("LeaderboardConfig"))
local MMConfig = require(RS:WaitForChild("Matchmaking"):WaitForChild("Config"))
local dataFolder = RS:WaitForChild("LeaderboardData")

local view = {} -- [board name] = "AllTime" | "Monthly"
local drawn = {} -- [board name] = what's currently drawn (so we only rebuild when something changed)

------------------------------------------------------------ HELPERS
local function commas(n)
	local s = tostring(math.floor(n))
	local neg = s:sub(1, 1) == "-"
	if neg then s = s:sub(2) end
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then s = s:sub(2) end
	return (neg and "-" or "") .. s
end

local function shown(board, v)
	if board.Display == "Level" then return MMConfig.LevelFromXP(v or 0) end
	return v or 0
end

-- ONE LINE, SHRINK TO FIT: the biggest text size that fits the label's height AND width.
-- (Roblox's own TextScaled wraps long names onto two lines, or overflows once wrapping is off.)
-- MaxTextScale attribute on a label (default 0.85) = how much of the label's height the text may use.
local function fit(label)
	local w, h = label.AbsoluteSize.X, label.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	local key = label.Text .. "|" .. math.floor(w) .. "x" .. math.floor(h)
	if label:GetAttribute("FitKey") == key then return end
	label.TextScaled = false
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.None
	local size = math.clamp(math.floor(h * (label:GetAttribute("MaxTextScale") or 0.85)), 1, 100)
	label.TextSize = size
	for _ = 1, 3 do -- shrink by the overflow, then nudge down until it really fits
		local bw = label.TextBounds.X
		if bw <= w * 0.97 or size <= 1 then break end
		size = math.max(1, math.min(size - 1, math.floor(size * (w * 0.97) / bw)))
		label.TextSize = size
	end
	label:SetAttribute("FitKey", key)
end

local function oneLine(root)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then fit(d) end
	end
end

local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end

-- the board model can sit anywhere in Workspace (straight in it, or inside a Lobby model / folder)
local modelCache, lastScan = {}, {}
local function boardModel(name)
	local m = modelCache[name]
	if m and m.Parent and m:FindFirstChild("UiPart") then return m end
	m = nil
	local direct = workspace:FindFirstChild(name)
	if direct and direct:FindFirstChild("UiPart") then m = direct end
	-- full search at most every 5s (the board may just be streamed out while you're far away)
	if not m and os.clock() - (lastScan[name] or -10) > 5 then
		lastScan[name] = os.clock()
		-- (names are matched ignoring upper / lower case: "Winstreak" finds the WinStreak board)
		local lower = name:lower()
		for _, d in workspace:GetDescendants() do
			local up = d.Name:lower() == lower and d:FindFirstChild("UiPart")
			if up and up:FindFirstChildOfClass("SurfaceGui") then m = d break end
		end
	end
	modelCache[name] = m
	return m
end

local function find(board)
	local model = boardModel(board.Name)
	local part = model and model:FindFirstChild("UiPart")
	-- names can vary a little (e.g. Level board = LevelsGui / LevelsFrame / LevelsScrolling): fall back to
	-- "the SurfaceGui on UiPart" and "the Frame in it that has a ScrollingFrame"
	local gui = part and (part:FindFirstChild(board.Name .. "Gui") or part:FindFirstChildOfClass("SurfaceGui"))
	local frame = gui and gui:FindFirstChild(board.Name .. "Frame")
	if gui and not frame then
		for _, c in gui:GetChildren() do
			if c:IsA("Frame") and c:FindFirstChildWhichIsA("ScrollingFrame") then frame = c break end
		end
	end
	if not frame then return nil end
	local scroll = frame:FindFirstChild(board.Name .. "Scrolling") or frame:FindFirstChildWhichIsA("ScrollingFrame")
	local template = scroll and scroll:FindFirstChild("Template")
	local you = frame:FindFirstChild("Template2") or gui:FindFirstChild("Template2")
	-- (the list always shows, even if it was hidden while designing; the row design itself never shows)
	if scroll and not scroll.Visible then scroll.Visible = true end
	if template and template.Visible then template.Visible = false end
	return {gui = gui, frame = frame, scroll = scroll, template = template, you = you}
end

local function headshot(userId)
	if not userId or userId <= 0 then return "rbxasset://textures/ui/GuiImagePlaceholder.png" end
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

-- #1 / #2 / #3 use the UIGradients inside the PlaceLabel: FirstPlace / SecondPlace / ThirdPlace (text stays white
-- so the gradient shows its real colours). Everyone else: no gradient, plain white.
-- A PlaceLabel without those gradients falls back to LeaderboardConfig > PlaceColors / OtherPlaceColor.
local GRADIENTS = {"FirstPlace", "SecondPlace", "ThirdPlace"}
local function placeColor(label, place)
	if not label then return end
	local hasGradients = false
	for i, name in GRADIENTS do
		local g = label:FindFirstChild(name)
		if g and g:IsA("UIGradient") then
			hasGradients = true
			g.Enabled = place == i
		end
	end
	if hasGradients then
		label.TextColor3 = Color3.new(1, 1, 1)
	else
		label.TextColor3 = (place and C.PlaceColors[place]) or C.OtherPlaceColor or Color3.new(1, 1, 1)
	end
end

local function fillRow(row, place, entry, board)
	setText(row:FindFirstChild("PlaceLabel"), "#" .. place)
	placeColor(row:FindFirstChild("PlaceLabel"), place)
	local img = row:FindFirstChild("PlayerImage")
	if img and img:IsA("ImageLabel") then img.Image = headshot(entry.u) end
	setText(row:FindFirstChild("PlayerName"), entry.d or "?")
	setText(row:FindFirstChild("PlayerUser"), "@" .. (entry.n or "?"))
	setText(row:FindFirstChild("Amount"), commas(shown(board, entry.v)))
end

------------------------------------------------------------ BUTTONS (All Time / Monthly)
-- The SELECTED look = how AllTime is designed, the UNSELECTED look = how Monthly is designed
-- (background colour + its UIGradient + the UIStroke's UIGradient + text colour). The selected button gets the
-- selected look, the other one the unselected look - so restyle the two buttons in Studio and it just follows.
local function lookOf(btn)
	local grad = btn:FindFirstChildOfClass("UIGradient")
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	local sgrad = stroke and stroke:FindFirstChildOfClass("UIGradient")
	return {
		bg = btn.BackgroundColor3,
		grad = grad and grad.Color,
		sgrad = sgrad and sgrad.Color,
		strokeColor = stroke and stroke.Color,
		text = btn:IsA("TextButton") and btn.TextColor3 or nil,
	}
end
local function applyLook(btn, look)
	if not look then return end
	btn.BackgroundColor3 = look.bg
	local grad = btn:FindFirstChildOfClass("UIGradient")
	if grad and look.grad then grad.Color = look.grad end
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if stroke and look.strokeColor then stroke.Color = look.strokeColor end
	local sgrad = stroke and stroke:FindFirstChildOfClass("UIGradient")
	if sgrad and look.sgrad then sgrad.Color = look.sgrad end
	if look.text and btn:IsA("TextButton") then btn.TextColor3 = look.text end
end

-- [AllTime button] = {on = look, off = look}, read ONCE from the design (a normal table: a weak one could
-- forget it, and re-reading from an already-restyled button swapped the colours). Cleared when the button goes.
local looks = {}
local function styleButtons(b, board)
	local all, month = b.frame:FindFirstChild("AllTime"), b.frame:FindFirstChild("Monthly")
	if not all then return end
	-- read the designed looks once per button copy (a board streaming back in brings fresh, unstyled buttons)
	local L = looks[all]
	if not L then
		L = {on = lookOf(all), off = month and lookOf(month) or nil}
		looks[all] = L
		all.Destroying:Connect(function() looks[all] = nil end)
	end
	local v = view[board.Name] or "AllTime"
	if not board.Monthly then v = "AllTime" end
	applyLook(all, v == "AllTime" and L.on or L.off)
	if month then applyLook(month, v == "Monthly" and L.on or L.off) end
end

local function hookButtons(b, board, redraw)
	for _, name in {"AllTime", "Monthly"} do
		local btn = b.frame:FindFirstChild(name)
		if btn and btn:IsA("GuiButton") and not btn:GetAttribute("LBHooked") then
			btn:SetAttribute("LBHooked", true)
			btn.Activated:Connect(function()
				if name == "Monthly" and not board.Monthly then return end
				view[board.Name] = name
				redraw(true)
			end)
		end
	end
end

------------------------------------------------------------ DRAW
local function draw(board, force)
	local b = find(board)
	if not (b and b.scroll and b.template) then return end
	local period = view[board.Name] or "AllTime"
	if period == "Monthly" and not board.Monthly then period = "AllTime" end
	hookButtons(b, board, function(f) draw(board, f) end)
	styleButtons(b, board)
	local key = board.Name .. "_" .. period
	local sv = dataFolder:FindFirstChild(key)
	local json = sv and sv.Value or "[]"

	-- the design row is only a template: never show it (a board streaming back in brings it back visible)
	b.template.Visible = false
	-- the list (only rebuilt when the data / view changed, or rows went missing - e.g. the board streamed back in)
	local sig = key .. "#" .. #json .. "#" .. json:sub(1, 64) .. json:sub(-64)
	local expected = select(2, json:gsub("\"u\":", ""))
	local have = 0
	for _, c in b.scroll:GetChildren() do if c.Name:match("^LBRow_") then have += 1 end end
	if force or drawn[board.Name] ~= sig or have ~= expected then
		drawn[board.Name] = sig
		local ok, list = pcall(function() return HttpService:JSONDecode(json) end)
		if not ok then list = {} end
		for _, c in b.scroll:GetChildren() do if c.Name:match("^LBRow_") then c:Destroy() end end
		local tpl = b.template
		-- rows get a fixed pixel height (the Template's size), so any number of rows fits the scroll area
		local rowH = tpl:GetAttribute("RowHeight")
		if not rowH then
			rowH = math.max(10, math.floor(tpl.AbsoluteSize.Y + 0.5))
			if tpl.AbsoluteSize.Y > 0 then tpl:SetAttribute("RowHeight", rowH) end
		end
		tpl.Visible = false
		-- rows stack top to bottom (added if the board is missing its UIListLayout)
		local layout = b.scroll:FindFirstChildOfClass("UIListLayout")
		if not layout then
			layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = b.scroll
		end
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		local pad = layout.Padding.Offset
		for i, entry in list do
			local row = tpl:Clone()
			row.Name = "LBRow_" .. i
			row.LayoutOrder = i
			row.Size = UDim2.new(tpl.Size.X.Scale, tpl.Size.X.Offset, 0, rowH)
			row.Visible = true
			fillRow(row, i, entry, board)
			oneLine(row)
			row.Parent = b.scroll
		end
		b.scroll.CanvasSize = UDim2.new(0, 0, 0, #list * (rowH + pad))
	end

	-- YOU row
	if b.you then
		local raw = player:GetAttribute("LB_" .. key) or "|0"
		local rank, value = raw:match("^(.-)|(%-?%d+)$")
		value = tonumber(value) or 0
		local placeText
		if value <= 0 or rank == nil or rank == "" then
			placeText = C.NoneText or "N/A"
		elseif rank:sub(1, 1) == "+" then
			placeText = commas(tonumber(rank:sub(2)) or C.RankLimit) .. "+"
		else
			placeText = "#" .. commas(tonumber(rank) or 0)
		end
		setText(b.you:FindFirstChild("PlaceLabel"), placeText)
		placeColor(b.you:FindFirstChild("PlaceLabel"), tonumber(rank or ""))
		local img = b.you:FindFirstChild("PlayerImage")
		if img and img:IsA("ImageLabel") then img.Image = headshot(player.UserId) end
		setText(b.you:FindFirstChild("PlayerName"), NameBadge.Of(player))
		setText(b.you:FindFirstChild("PlayerUser"), "@" .. player.Name)
		setText(b.you:FindFirstChild("Amount"), commas(shown(board, value)))
		oneLine(b.you)
	end

	-- "Leaderboard Updates In 4:32"
	local upd = b.frame:FindFirstChild("Updates")
	if upd then
		if upd:GetAttribute("Prefix") == nil then upd:SetAttribute("Prefix", upd.Text) end
		local left = math.max(0, math.ceil((dataFolder:GetAttribute("NextUpdate") or 0) - workspace:GetServerTimeNow()))
		setText(upd, (upd:GetAttribute("Prefix") or "Leaderboard Updates In ") .. ("%d:%02d"):format(left // 60, left % 60))
	end
	oneLine(b.frame)
end

------------------------------------------------------------ LOOP
local function drawAll(force)
	for _, board in C.Boards do
		local ok, err = pcall(draw, board, force)
		if not ok then warn("[Leaderboards] " .. board.Name .. ": " .. tostring(err)) end
	end
end
dataFolder.ChildAdded:Connect(function(c)
	c:GetPropertyChangedSignal("Value"):Connect(function() drawAll() end)
	drawAll()
end)
for _, c in dataFolder:GetChildren() do c:GetPropertyChangedSignal("Value"):Connect(function() drawAll() end) end
while true do
	drawAll()
	task.wait(1)
end
