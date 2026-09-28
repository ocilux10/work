-- DAILY QUESTS (server). Settings: ReplicatedStorage > QuestConfig
-- Other server scripts report progress:
--   Quests.Add(player, "Wins", 1)       Quests.OnKill(killer, tags)      Quests.OnDeath(player)
-- The client reads the player attributes "Quests" (JSON list) and "QuestsResetAt" (os.time of the next reset).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local QC = require(RS:WaitForChild("QuestConfig"))

local Quests = {}
local byId = {}
for _, q in QC.Quests do byId[q.Id] = q end
local BEST = {KillStreak = true, QuickKills = true} -- these keep your best, the others add up
-- "Streak3" = done once: 3 kills in ONE match without dying in between (dying or a new match starts the count over)
local STREAK_NEEDED = 3
local live = {} -- [player] = {streak, killTimes}

local function cycleLen() return (QC.CycleHours or 24) * 3600 end

local function roll(d)
	local pool = {}
	for _, q in QC.Quests do if q.Enabled ~= false then table.insert(pool, q.Id) end end
	-- try not to give yesterday's quests again
	local last = {}
	for _, e in d.Quests or {} do last[e.Id] = true end
	local fresh = {}
	for _, id in pool do if not last[id] then table.insert(fresh, id) end end
	if #fresh >= (QC.QuestsPerDay or 3) then pool = fresh end
	local list = {}
	for _ = 1, math.min(QC.QuestsPerDay or 3, #pool) do
		local k = math.random(#pool)
		table.insert(list, {Id = pool[k], Progress = 0, Done = false})
		table.remove(pool, k)
	end
	d.Quests = list
end

local function publish(player)
	local d = PlayerData.Get(player)
	if not d then return end
	local out = {}
	for _, e in d.Quests or {} do
		local q = byId[e.Id]
		if q then
			table.insert(out, {Id = e.Id, Name = q.Name, Goal = q.Goal, Progress = math.min(math.floor(e.Progress + 1e-6), q.Goal),
				Done = e.Done, XP = q.XP, Coins = q.Coins})
		end
	end
	player:SetAttribute("Quests", HttpService:JSONEncode(out))
	player:SetAttribute("QuestsResetAt", (d.QuestCycleStart or os.time()) + cycleLen())
end

-- new day? (the cycle keeps lining up with the time of your very first join)
local function checkCycle(player)
	local d = PlayerData.Get(player)
	if not d then return nil end
	local now = os.time()
	local changed = false
	if (d.QuestCycleStart or 0) <= 0 then
		d.QuestCycleStart = now
		roll(d)
		changed = true
	elseif now >= d.QuestCycleStart + cycleLen() then
		d.QuestCycleStart += math.floor((now - d.QuestCycleStart) / cycleLen()) * cycleLen()
		roll(d)
		changed = true
	elseif type(d.Quests) ~= "table" or #d.Quests == 0 then
		roll(d)
		changed = true
	end
	-- (the kills-without-dying quest used to count 0-3 across games: old unfinished progress starts over at 0/1)
	for _, e in d.Quests or {} do
		if e.Id == "Streak3" and not e.StreakV2 then
			e.StreakV2 = true
			if not e.Done then e.Progress = 0 end
			changed = true
		end
	end
	if changed then publish(player) end
	return d
end

local function reward(player, q)
	if (q.XP or 0) > 0 then PlayerData.AddXP(player, q.XP) end
	if (q.Coins or 0) > 0 then PlayerData.AddCoins(player, q.Coins) end
end

local function apply(player, stat, fn)
	local d = checkCycle(player)
	if not d then return end
	local changed = false
	for _, e in d.Quests do
		local q = byId[e.Id]
		if q and q.Stat == stat and not e.Done then
			local new = math.min(fn(e.Progress or 0), q.Goal)
			if new ~= e.Progress then
				e.Progress = new
				changed = true
				if new >= q.Goal then
					e.Done = true
					reward(player, q)
				end
			end
		end
	end
	if changed then publish(player) end
end

function Quests.Add(player, stat, amount)
	apply(player, stat, function(p) return p + (amount or 1) end)
end
function Quests.Best(player, stat, value)
	apply(player, stat, function(p) return math.max(p, value) end)
end

local function state(player)
	live[player] = live[player] or {streak = 0, killTimes = {}}
	return live[player]
end

-- a match starts: kill streak / quick kills start fresh
function Quests.MatchStart(player)
	live[player] = {streak = 0, killTimes = {}}
end

function Quests.OnKill(killer, tags)
	Quests.Add(killer, "Kills", 1)
	for _, t in tags or {} do
		if t.name == "HEADSHOT" then Quests.Add(killer, "HeadshotKills", 1)
		elseif t.name == "JUMPSHOT" then Quests.Add(killer, "JumpshotKills", 1)
		elseif t.name == "LONGSHOT" then Quests.Add(killer, "LongKills", 1) end
	end
	local s = state(killer)
	s.streak += 1
	Quests.Best(killer, "KillStreak", s.streak)
	if s.streak == STREAK_NEEDED then Quests.Add(killer, "Streak3", 1) end
	local now = os.clock()
	table.insert(s.killTimes, now)
	local window = QC.QuickKillWindow or 20
	while s.killTimes[1] and now - s.killTimes[1] > window do table.remove(s.killTimes, 1) end
	Quests.Best(killer, "QuickKills", #s.killTimes)
end

function Quests.OnDeath(player)
	state(player).streak = 0
end

-- progress right now, to compare at the end of a match
function Quests.Snapshot(player)
	local d = checkCycle(player)
	if not d then return nil end
	local snap = {Cycle = d.QuestCycleStart, Progress = {}}
	for _, e in d.Quests do snap.Progress[e.Id] = e.Progress end
	return snap
end

-- the quests this match moved forward (for the end screen)
function Quests.Summary(player, snap)
	local d = checkCycle(player)
	if not (d and snap) then return {} end
	local out = {}
	for _, e in d.Quests do
		local q = byId[e.Id]
		if q then
			local from = (snap.Cycle == d.QuestCycleStart and snap.Progress[e.Id]) or 0
			local to = math.min(e.Progress or 0, q.Goal)
			local justDone = e.Done and from < q.Goal
			if math.floor(to + 1e-6) > math.floor(from + 1e-6) or justDone then
				table.insert(out, {Name = q.Name, Goal = q.Goal, From = math.floor(from + 1e-6), To = math.floor(to + 1e-6),
					Done = e.Done, JustDone = justDone, XP = q.XP, Coins = q.Coins})
			end
		end
	end
	return out
end

-- players: roll / publish on join, play time every 5 seconds (counts everywhere)
local function onJoin(player)
	local t0 = os.clock()
	while player.Parent == Players and not PlayerData.Get(player) and os.clock() - t0 < 60 do task.wait(0.5) end
	if checkCycle(player) then publish(player) end
end
for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end
Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(function(p) live[p] = nil end)

task.spawn(function()
	local STEP = 5
	while true do
		task.wait(STEP)
		for _, p in Players:GetPlayers() do
			if PlayerData.Get(p) then
				task.spawn(Quests.Add, p, "Minutes", STEP / 60)
			end
		end
	end
end)

return Quests
