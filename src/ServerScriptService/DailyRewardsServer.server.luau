-- DAILY REWARDS (server). Settings: ReplicatedStorage > DailyRewards > DailyConfig. Client: StarterPlayerScripts > DailyRewardsClient
-- Saved in PlayerData: Daily = {Day = last day claimed, Last = the calendar day it was claimed on}.
-- Put on the player: DailyDay (the day you can claim / claimed today), DailyCanClaim, DailyResetAt (unix time of the next day).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local PlayerData = require(SS:WaitForChild("PlayerData"))
local GiveReward = require(SS:WaitForChild("GiveReward"))
local RewardInfo = require(RS:WaitForChild("RewardInfo"))
local folder = RS:WaitForChild("DailyRewards")
local Config = require(folder:WaitForChild("DailyConfig"))
local Remote = folder:WaitForChild("Remote")

local function offset() return (Config.ResetHourUTC or 0) * 3600 end
local function today() return math.floor((os.time() - offset()) / 86400) end
local function resetAt() return (today() + 1) * 86400 + offset() end

-- (can claim, day) - the day you'd get now, or the one you already got today
local function state(d)
	local daily = type(d.Daily) == "table" and d.Daily or {Day = 0, Last = -1}
	local t = today()
	if daily.Last == t then return false, math.max(daily.Day or 1, 1) end
	local nextDay = 1
	if daily.Last == t - 1 or Config.MissedDay == "Keep" then nextDay = (daily.Day or 0) + 1 end
	if nextDay > #Config.Days then nextDay = Config.AfterLastDay == "Stay" and #Config.Days or 1 end
	return true, nextDay
end

local function publish(p)
	local d = PlayerData.Get(p)
	if not d then return end
	local can, day = state(d)
	p:SetAttribute("DailyDay", day)
	p:SetAttribute("DailyCanClaim", can)
	p:SetAttribute("DailyResetAt", resetAt())
end

local busy = {}
Remote.OnServerInvoke = function(p, action)
	if action ~= "Claim" then return false end
	if busy[p] then return false, "Slow down" end
	local d = PlayerData.Get(p)
	if not d then return false, "Still loading" end
	local can, day = state(d)
	if not can then return false, "Already claimed today" end
	local reward = Config.Days[day]
	if not reward then return false, "No reward set up for day " .. day end
	busy[p] = true
	d.Daily = {Day = day, Last = today()} -- (saved first: it can never be claimed twice)
	local ok = GiveReward(p, reward)
	publish(p)
	busy[p] = nil
	if not ok then return false, "Something went wrong" end
	return true, (Config.ClaimedText or "You got {reward}!"):gsub("{reward}", RewardInfo.Text(reward)), day
end

local function onPlayer(p)
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 60 do task.wait(0.5) end
	publish(p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end
Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)

-- a new day started while they're playing
task.spawn(function()
	while true do
		task.wait(20)
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("DailyResetAt") and os.time() >= p:GetAttribute("DailyResetAt") then publish(p) end
		end
	end
end)
