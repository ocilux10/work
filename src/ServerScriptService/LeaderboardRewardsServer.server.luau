-- MONTHLY LEADERBOARD REWARDS (server). Settings: ReplicatedStorage > LeaderboardRewards > RewardsConfig.
-- Last month's top players of each monthly board (the same saved boards ServerScriptService > Leaderboards shows:
-- OrderedDataStore "LB_<board>_<YYYY-MM>") win their tier's reward. Remote:
--   "State" -> {EndsAt, Month, Boards = {{Board, Place, Claimed}, ...}}      "Claim" -> true, message
-- Claimed months are saved in PlayerData.LeaderboardClaimed ("2026-09 Kills" = true), so it can't be taken twice.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local DSS = game:GetService("DataStoreService")
local PlayerData = require(SS:WaitForChild("PlayerData"))
local GiveReward = require(SS:WaitForChild("GiveReward"))
local RewardInfo = require(RS:WaitForChild("RewardInfo"))
local LBConfig = require(RS:WaitForChild("LeaderboardConfig"))
local folder = RS:WaitForChild("LeaderboardRewards")
local Config = require(folder:WaitForChild("RewardsConfig"))
local Remote = folder:WaitForChild("Remote")
local Notify = RS:WaitForChild("Admin"):WaitForChild("Notify") -- (chat + notice on their screen)

------------------------------------------------------------ MONTHS (UTC)
local function lastMonthKey()
	local d = os.date("!*t")
	local y, m = d.year, d.month - 1
	if m == 0 then y, m = y - 1, 12 end
	return ("%04d-%02d"):format(y, m)
end
local function monthEndsAt()
	local d = os.date("!*t")
	local y, m = d.year, d.month + 1
	if m == 13 then y, m = y + 1, 1 end
	return DateTime.fromUniversalTime(y, m, 1, 0, 0, 0).UnixTimestamp
end

------------------------------------------------------------ LAST MONTH'S TOP 100 (read once per board per month, per server)
local function storeName(boardName, month)
	for _, b in LBConfig.Boards do
		if b.Name == boardName then return "LB_" .. (b.Store or b.Name) .. "_" .. month end
	end
	return "LB_" .. boardName .. "_" .. month
end
local maxTop = 0
for _, b in Config.Boards do for _, t in b.Tiers do maxTop = math.max(maxTop, t.Top) end end

local cache = {} -- ["Kills 2026-09"] = {[userId] = place} (or false while loading)
local function places(boardName, month)
	local key = boardName .. " " .. month
	while cache[key] == false do task.wait(0.2) end
	if cache[key] then return cache[key] end
	cache[key] = false
	local out = {}
	local ok, err = pcall(function()
		local pages = DSS:GetOrderedDataStore(storeName(boardName, month)):GetSortedAsync(false, math.clamp(maxTop, 1, 100))
		local place = 0
		while place < maxTop do
			for _, e in pages:GetCurrentPage() do
				place += 1
				if place > maxTop then break end
				local id = tonumber(tostring(e.key):match("%d+"))
				if id and (tonumber(e.value) or 0) >= (Config.MinScore or 1) then out[id] = place end
			end
			if pages.IsFinished or place >= maxTop then break end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn("[LeaderboardRewards] couldn't read " .. storeName(boardName, month) .. ": " .. tostring(err))
		cache[key] = nil
		return {}
	end
	cache[key] = out
	return out
end

local function tierFor(board, place)
	if not place then return nil end
	local list = table.clone(board.Tiers)
	table.sort(list, function(a, b) return a.Top < b.Top end)
	for _, t in list do if place <= t.Top then return t end end
	return nil
end

------------------------------------------------------------ STATE / CLAIM
local function state(p)
	local d = PlayerData.Get(p)
	local month = lastMonthKey()
	local out = {EndsAt = monthEndsAt(), Month = month, Boards = {}}
	for i, b in Config.Boards do
		local place = places(b.Board, month)[p.UserId]
		local claimed = d and type(d.LeaderboardClaimed) == "table" and d.LeaderboardClaimed[month .. " " .. b.Board] == true
		out.Boards[i] = {Board = b.Board, Place = tierFor(b, place) and place or nil, Claimed = claimed}
	end
	return out
end

local function claim(p)
	local d = PlayerData.Get(p)
	if not d then return false, "Still loading" end
	d.LeaderboardClaimed = type(d.LeaderboardClaimed) == "table" and d.LeaderboardClaimed or {}
	local month = lastMonthKey()
	local got = {}
	for _, b in Config.Boards do
		local key = month .. " " .. b.Board
		local place = places(b.Board, month)[p.UserId]
		local tier = tierFor(b, place)
		if tier and not d.LeaderboardClaimed[key] then
			d.LeaderboardClaimed[key] = true -- (saved first: never given twice)
			GiveReward(p, tier.Reward)
			table.insert(got, ((Config.WonText or "You placed {place} on {board} last month: {reward}!")
				:gsub("{place}", "#" .. place):gsub("{board}", b.Title or b.Board):gsub("{reward}", RewardInfo.Text(tier.Reward))))
		end
	end
	-- (old months: forget them so the saved list doesn't grow forever)
	for k in d.LeaderboardClaimed do
		if k:sub(1, 7) < month then d.LeaderboardClaimed[k] = nil end
	end
	if #got == 0 then return false, "Nothing to claim" end
	return true, table.concat(got, "\n")
end

local busy = {}
Remote.OnServerInvoke = function(p, action)
	if busy[p] then return false, "Slow down" end
	busy[p] = true
	local ok, a, b = pcall(function()
		if action == "State" then return true, state(p) end
		if action == "Claim" then
			if Config.Delivery == "Auto" then return false, "Rewards are given automatically" end
			return claim(p)
		end
		return false
	end)
	busy[p] = nil
	if not ok then warn("[LeaderboardRewards] " .. tostring(a)) return false, "Something went wrong" end
	return a, b
end

-- AUTO: given as soon as their data has loaded
Players.PlayerAdded:Connect(function(p)
	if Config.Delivery ~= "Auto" then return end
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 60 do task.wait(0.5) end
	if p.Parent ~= Players then return end
	local ok, msg = claim(p)
	if ok then Notify:FireClient(p, {Text = msg, Prefix = "[REWARDS]", Color = "#FFC828"}) end
end)
Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
