-- DAILY REWARDS (server). Settings: ReplicatedStorage > DailyRewards > DailyConfig. Client: StarterPlayerScripts > DailyRewardsClient
-- Saved in PlayerData: Daily = {Day = last day claimed, At = os.time() it was claimed}.
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

-- a reward every Cooldown seconds after the last claim (24h); miss it by more than MissWindow and (MissedDay = "Reset") the
-- streak starts again at day 1
local function cooldown() return Config.CooldownHours and Config.CooldownHours * 3600 or 86400 end
local function missWindow() return Config.StreakHours and Config.StreakHours * 3600 or 2 * 86400 end
local function lastAt(daily) return tonumber(daily.At) or -1e12 end
local function resetAtOf(daily) return lastAt(daily) + cooldown() end

-- (can claim, day) - the day you'd get now, or the one you got last
local function state(d)
	local daily = type(d.Daily) == "table" and d.Daily or {Day = 0}
	local now = os.time()
	if now < resetAtOf(daily) then return false, math.max(daily.Day or 1, 1) end
	local nextDay = 1
	if now <= lastAt(daily) + missWindow() or Config.MissedDay == "Keep" then nextDay = (daily.Day or 0) + 1 end
	if nextDay > #Config.Days then nextDay = Config.AfterLastDay == "Stay" and #Config.Days or 1 end
	return true, nextDay
end
local function resetAt(d) return resetAtOf(type(d.Daily) == "table" and d.Daily or {}) end

local function publish(p)
	local d = PlayerData.Get(p)
	if not d then return end
	local can, day = state(d)
	p:SetAttribute("DailyDay", day)
	p:SetAttribute("DailyCanClaim", can)
	p:SetAttribute("DailyResetAt", resetAt(d))
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
	d.Daily = {Day = day, At = os.time()} -- (saved first: it can never be claimed twice)
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
