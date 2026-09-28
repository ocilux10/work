-- DAILY QUESTS panel in the lobby (Main > Quests). Replaces Main > Quests > QuestsClient (switched off here), which
-- never updated the "[0/5]" (it sits inside the name label, where that script didn't look).
-- The look is exactly the one in StarterGui - this only fills in the texts:
--   TextLabel = quest name, TextLabel > Completed = "[2/5]" (turns QuestConfig.DoneColor when done), CoinAmount = coins
-- Data: player attributes "Quests" (JSON) + "QuestsResetAt" (ServerStorage > Quests).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local QC = require(RS:WaitForChild("QuestConfig"))
local SFX = require(RS:WaitForChild("SFX"))
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local slots, timeLabel, lastDone = {}, nil, {}

local function hook(main)
	local panel = main:WaitForChild("Quests", 10)
	if not panel then return end
	local old = panel:FindFirstChild("QuestsClient")
	if old and old:IsA("LocalScript") then old.Enabled = false end
	local list = panel:WaitForChild("Frame")
	timeLabel = panel:FindFirstChild("Time")
	table.clear(slots)
	for i = 1, 3 do
		local f = list:FindFirstChild("Quest" .. i)
		if f then
			local count = f:FindFirstChild("Completed", true)
			slots[i] = {frame = f, name = f:FindFirstChild("TextLabel"), count = count, coins = f:FindFirstChild("CoinAmount"),
				countColor = count and count:GetAttribute("DesignColor") or (count and count.TextColor3)}
			if count and count:GetAttribute("DesignColor") == nil then count:SetAttribute("DesignColor", count.TextColor3) end
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
			if s.coins then s.coins.Text = tostring(q.Coins or 0) end
			if q.Done and lastDone[q.Id] == false and not player:GetAttribute("MatchId") then SFX.Play("QuestComplete") end
			lastDone[q.Id] = q.Done == true
		end
	end
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
