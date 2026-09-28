-- DAILY QUESTS panel in the lobby (Main > Quests). Replaces Main > Quests > QuestsClient (switched off here), which
-- never updated the "[0/5]" (it sits inside the name label) and had the coins / bar out of view.
-- Data: player attributes "Quests" (JSON) + "QuestsResetAt" (ServerStorage > Quests). Settings: ReplicatedStorage > QuestConfig
-- Each Frame > Quest1..3 is laid out by LAYOUT below (edit the numbers to move things):
--   TextLabel = quest name, Completed = "[2/5]", Icon + CoinAmount = the coin reward, ProgressBar = the bar (on a track)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local QC = require(RS:WaitForChild("QuestConfig"))
local SFX = require(RS:WaitForChild("SFX"))
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- {AnchorPoint, Position, Size} as scales of the quest row
local LAYOUT = {
	Name     = {Vector2.new(0, 0),   UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.66, 0.42)},
	Count    = {Vector2.new(1, 0),   UDim2.fromScale(0.96, 0.08), UDim2.fromScale(0.28, 0.42)},
	Icon     = {Vector2.new(0, 0.5), UDim2.fromScale(0.04, 0.66), UDim2.fromScale(0.1, 0.3)},
	Coins    = {Vector2.new(0, 0.5), UDim2.fromScale(0.13, 0.66), UDim2.fromScale(0.4, 0.3)},
	Track    = {Vector2.new(0, 1),   UDim2.fromScale(0.04, 0.94), UDim2.fromScale(0.92, 0.1)},
}
local TRACK_COLOR = Color3.fromRGB(25, 25, 30)

local function place(o, key)
	if not o then return end
	local l = LAYOUT[key]
	o.AnchorPoint, o.Position, o.Size = l[1], l[2], l[3]
	-- (the design's aspect constraints would squash them in their new spots; the icon keeps its own)
	if key ~= "Icon" then for _, c in o:GetChildren() do if c:IsA("UIAspectRatioConstraint") then c:Destroy() end end end
end

local slots, timeLabel, first, lastDone = {}, nil, true, {}

local function hook(main)
	local panel = main:WaitForChild("Quests", 10)
	if not panel then return end
	local old = panel:FindFirstChild("QuestsClient")
	if old and old:IsA("LocalScript") then old.Enabled = false end
	local list = panel:WaitForChild("Frame")
	timeLabel = panel:FindFirstChild("Time")
	table.clear(slots)
	first = true
	for i = 1, 3 do
		local f = list:FindFirstChild("Quest" .. i)
		if f then
			f.ClipsDescendants = false
			local name = f:FindFirstChild("TextLabel")
			local count = f:FindFirstChild("Completed", true)
			if count then count.Parent = f count.TextXAlignment = Enum.TextXAlignment.Right count.TextScaled = true end
			if name then name.TextXAlignment = Enum.TextXAlignment.Left name.TextScaled = true end
			local coins, icon = f:FindFirstChild("CoinAmount"), f:FindFirstChild("Icon")
			if coins then coins.TextXAlignment = Enum.TextXAlignment.Left coins.TextScaled = true end
			place(name, "Name") place(count, "Count") place(icon, "Icon") place(coins, "Coins")
			-- the bar sits on a dark track so the quest shows even at 0
			local bar = f:FindFirstChild("ProgressBar", true)
			local track = f:FindFirstChild("Track")
			if bar and not track then
				track = Instance.new("Frame")
				track.Name = "Track"
				track.BackgroundColor3 = TRACK_COLOR
				track.BackgroundTransparency = 0.15
				track.BorderSizePixel = 0
				track.ZIndex = bar.ZIndex
				local c = bar:FindFirstChildOfClass("UICorner")
				if c then c:Clone().Parent = track else local nc = Instance.new("UICorner") nc.CornerRadius = UDim.new(1, 0) nc.Parent = track end
				track.Parent = f
				place(track, "Track")
				bar.Parent = track
				bar.AnchorPoint = Vector2.zero
				bar.Position = UDim2.fromScale(0, 0)
				bar.Size = UDim2.fromScale(0, 1)
				bar.ZIndex = track.ZIndex + 1
			end
			slots[i] = {frame = f, name = name, count = count, coins = coins, icon = icon, bar = bar,
				countColor = count and count.TextColor3, barColor = bar and bar.BackgroundColor3}
		end
	end
end

local function refresh()
	local ok, quests = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Quests") or "[]")
	if not ok or type(quests) ~= "table" then return end
	for i, s in slots do
		local q = quests[i]
		s.frame.Visible = q ~= nil
		if q then
			if s.name then s.name.Text = q.Name end
			if s.count then
				s.count.Text = ("[%d/%d]"):format(q.Progress or 0, q.Goal or 0)
				s.count.TextColor3 = q.Done and QC.DoneColor or s.countColor
			end
			if s.coins then s.coins.Text = q.Done and "CLAIMED" or tostring(q.Coins or 0) s.coins.TextColor3 = q.Done and QC.DoneColor or Color3.new(1, 1, 1) end
			if s.icon then s.icon.Visible = not q.Done end
			if s.bar then
				local pct = math.clamp((q.Progress or 0) / math.max(q.Goal or 1, 1), 0, 1)
				s.bar.Visible = true
				s.bar.BackgroundColor3 = q.Done and QC.DoneColor or s.barColor
				TweenService:Create(s.bar, TweenInfo.new(first and 0 or 0.4, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(pct, 1)}):Play()
			end
			if q.Done and lastDone[q.Id] == false and not player:GetAttribute("MatchId") then SFX.Play("QuestComplete") end
			lastDone[q.Id] = q.Done == true
		end
	end
	first = false
end

local function hookAndFill(main) hook(main) refresh() end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hookAndFill, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hookAndFill, c) end end)
player:GetAttributeChangedSignal("Quests"):Connect(refresh)

-- countdown to the next reset
while true do
	local resetAt = player:GetAttribute("QuestsResetAt")
	if timeLabel and timeLabel.Parent and resetAt then
		local left = math.max(0, math.floor(resetAt - workspace:GetServerTimeNow()))
		timeLabel.Text = ("[%02d:%02d:%02d]"):format(left // 3600, (left % 3600) // 60, left % 60)
	end
	task.wait(0.25)
end
