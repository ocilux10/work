-- PLAYER DATA (ProfileStore)
-- Loads / saves every player's data. Require this from any server script:
--   local PlayerData = require(game.ServerStorage.PlayerData)
--   PlayerData.AddXP(player, 100)
--   PlayerData.Increment(player, "WinStreak", 1)
--   PlayerData.Set(player, "WinStreak", 0)
--   PlayerData.Get(player)  -> the data table (or nil if not loaded yet)
--   PlayerData.AddCoins(player, 50)
-- The player's XP / Level / Coins are also mirrored to attributes (player:GetAttribute("XP") / "Level" / "Coins")
-- and Level / WinStreak to leaderstats so they show on the player list.
-- LEVEL-UP REWARDS: every level gained gives Config.CoinsForLevel(level) coins (Matchmaking > Config).
-- (A LevelUp remote event is also fired to the client, in case you want an effect for it later.)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local Config = require(RS:WaitForChild("Matchmaking"):WaitForChild("Config"))

local TEMPLATE = {
	XP = 0,
	Coins = 0,
	RewardedLevel = 0, -- highest level we've already paid the level-up coins for
	NextLevelCoins = 0, -- the (pre-rolled) coins you'll get for your next level up – shown on the XP bar
	WinStreak = 0,
	Kills = 0,
	Deaths = 0,
	Matches = 0,
	Wins = 0,           -- shown on player profiles (the player list only shows Level + WinStreak)
	Losses = 0,
	Playtime = 0,        -- seconds spent in the game
	EquippedSkin = "Default", -- the balloon you use (ReplicatedStorage > BalloonSkins)
	Balloons = {},       -- balloons you own: {[Id] = {Count = n, Got = os.time()}} (ServerScriptService > SkinServer)
	LockedBalloons = {}, -- {[Id] = true}: locked balloons can't be deleted
	TesterGranted = {},  -- {[Id] = true}: tester balloons already given (SkinConfig.Testers)
	Passes = {},         -- {[PassName] = true}: game passes gifted by admins (ShopConfig.Passes; ServerScriptService > AdminServer)
	-- MONTHLY leaderboards: kills / wins this calendar month (UTC). Reset automatically when the month changes.
	MonthKey = "",
	MonthKills = 0,
	MonthWins = 0,
	-- DAILY QUESTS (ServerStorage > Quests)
	QuestCycleStart = 0, -- os.time the current 24h quest cycle started (first ever join, then every 24h)
	Quests = {},         -- {{Id, Progress, Done}, ...}
	Receipts = {},       -- ids of Robux purchases already given (ServerScriptService > ShopServer)
	Crates = {},         -- chests you own and haven't opened: {[crateId] = count} (ServerScriptService > CrateServer)
	Daily = {Day = 0, Last = -1}, -- DAILY REWARDS: the last day claimed (1 = day 1) + which calendar day (ServerScriptService > DailyRewardsServer)
	LeaderboardClaimed = {}, -- {["2026-09 MonthKills"] = true}: monthly leaderboard rewards already given (LeaderboardRewardsServer)
	Settings = {},       -- small UI choices (e.g. LobbiesOpen), saved by ServerScriptService > SettingsServer
}

local function monthKey() return os.date("!%Y-%m") end
-- the monthly counters, reset if we're in a new month
local function freshMonth(d)
	local mk = monthKey()
	if d.MonthKey ~= mk then
		d.MonthKey = mk
		d.MonthKills = 0
		d.MonthWins = 0
	end
end

local Store = ProfileStore.New("PlayerData_v1", TEMPLATE)
local Profiles = {} -- [player] = profile
local sessionStart = {} -- [player] = os.clock() when playtime was last banked

local PlayerData = {}

local function mirror(player)
	local profile = Profiles[player]
	if not profile then return end
	local xp = profile.Data.XP
	local level, into, need = Config.LevelInfo(xp)
	player:SetAttribute("XP", xp)
	player:SetAttribute("XPInto", into)   -- XP earned inside the current level (for the XP bar)
	player:SetAttribute("XPNeeded", need)  -- XP this level needs to reach the next one
	player:SetAttribute("Level", level)
	player:SetAttribute("WinStreak", profile.Data.WinStreak)
	player:SetAttribute("Coins", profile.Data.Coins)
	player:SetAttribute("NextLevelCoins", profile.Data.NextLevelCoins)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local lv = ls:FindFirstChild("Level") or Instance.new("IntValue")
	lv.Name = "Level"
	lv.Value = level
	lv.Parent = ls
	local w = ls:FindFirstChild("Win Streak") or Instance.new("IntValue")
	w.Name = "Win Streak"
	w.Value = profile.Data.WinStreak
	w.Parent = ls
end

local function onPlayerAdded(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Couldn't load your data, please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	-- existing players: don't pay out for levels they already had before rewards existed
	if (profile.Data.RewardedLevel or 0) < 1 then
		profile.Data.RewardedLevel = Config.LevelFromXP(profile.Data.XP)
	end
	-- roll the next level-up reward now, so the XP bar can show exactly what you'll get
	if (profile.Data.NextLevelCoins or 0) <= 0 then
		profile.Data.NextLevelCoins = Config.CoinsForLevel((profile.Data.RewardedLevel or 1) + 1)
	end
	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Your data was loaded on another server, please rejoin.")
	end)
	if player.Parent == Players then
		Profiles[player] = profile
		sessionStart[player] = os.clock()
		mirror(player)
	else
		profile:EndSession()
	end
end

function PlayerData.Get(player)
	local p = Profiles[player]
	return p and p.Data
end

function PlayerData.Increment(player, key, amount)
	local p = Profiles[player]
	if not p then return end
	p.Data[key] = (p.Data[key] or 0) + (amount or 1)
	if key == "Kills" or key == "Wins" then
		freshMonth(p.Data)
		p.Data["Month" .. key] = (p.Data["Month" .. key] or 0) + (amount or 1)
	end
	mirror(player)
	return p.Data[key]
end

-- this month's kills / wins (0 if the month has changed since they were counted)
function PlayerData.GetMonthly(player, key)
	local d = PlayerData.Get(player)
	if not d then return 0 end
	freshMonth(d)
	return d["Month" .. key] or 0
end

function PlayerData.Set(player, key, value)
	local p = Profiles[player]
	if not p then return end
	p.Data[key] = value
	mirror(player)
	return value
end

local LevelUpRemote -- ReplicatedStorage > Matchmaking > Remotes > LevelUp
local function levelUpRemote()
	if LevelUpRemote then return LevelUpRemote end
	local remotes = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes")
	LevelUpRemote = remotes:FindFirstChild("LevelUp")
	if not LevelUpRemote then
		LevelUpRemote = Instance.new("RemoteEvent")
		LevelUpRemote.Name = "LevelUp"
		LevelUpRemote.Parent = remotes
	end
	return LevelUpRemote
end

function PlayerData.AddCoins(player, amount)
	return PlayerData.Increment(player, "Coins", amount)
end

-- other scripts can react to level ups:  PlayerData.OnLevelUp(function(player, fromLevel, toLevel, coins) end)
local levelHooks = {}
function PlayerData.OnLevelUp(fn) table.insert(levelHooks, fn) end

function PlayerData.AddXP(player, amount)
	local p = Profiles[player]
	if not p then return end
	p.Data.XP = (p.Data.XP or 0) + (amount or 0)
	-- pay coins for every new level reached
	local level = Config.LevelFromXP(p.Data.XP)
	local from = p.Data.RewardedLevel or 1
	if level > from then
		-- pay the reward that was shown on the XP bar, then roll the one for the next level
		local coins = 0
		for l = from + 1, level do
			local reward = p.Data.NextLevelCoins or 0
			if reward <= 0 then reward = Config.CoinsForLevel(l) end
			coins += reward
			p.Data.NextLevelCoins = Config.CoinsForLevel(l + 1)
		end
		p.Data.Coins = (p.Data.Coins or 0) + coins
		p.Data.RewardedLevel = level
		levelUpRemote():FireClient(player, {Level = level, Coins = coins, LevelsGained = level - from})
		for _, fn in levelHooks do task.spawn(fn, player, from, level, coins) end
	end
	mirror(player)
	return p.Data.XP
end

-- everything another player may see on your profile (Main > PlayerProfile)
function PlayerData.GetPublicProfile(player)
	local d = PlayerData.Get(player)
	if not d then return nil end
	local level = Config.LevelFromXP(d.XP)
	return {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		Verified = player.HasVerifiedBadge == true,
		Level = level,
		WinStreak = d.WinStreak or 0,
		Kills = d.Kills or 0,
		Deaths = d.Deaths or 0,
		Wins = d.Wins or 0,
		Losses = d.Losses or 0,
		Matches = d.Matches or 0,
		Playtime = (d.Playtime or 0) + (sessionStart[player] and (os.clock() - sessionStart[player]) or 0),
		EquippedSkin = d.EquippedSkin or "Default",
		Device = player:GetAttribute("Device") or "PC",
	}
end

-- a player who ISN'T in this server: read their saved data (read-only). Returns the same table as GetPublicProfile, or nil.
function PlayerData.GetOfflineProfile(userId, name, displayName, verified)
	local ok, view = pcall(function() return Store:GetAsync("Player_" .. userId) end)
	if not ok or not view or type(view.Data) ~= "table" then return nil end
	local d = view.Data
	return {
		UserId = userId,
		Name = name or "?",
		DisplayName = displayName or name or "?",
		Verified = verified == true,
		Level = Config.LevelFromXP(d.XP or 0),
		WinStreak = d.WinStreak or 0,
		Kills = d.Kills or 0,
		Deaths = d.Deaths or 0,
		Wins = d.Wins or 0,
		Losses = d.Losses or 0,
		Matches = d.Matches or 0,
		Playtime = d.Playtime or 0,
		EquippedSkin = d.EquippedSkin or "Default",
		Device = "PC",
		Offline = true,
	}
end

-- a player who ISN'T in this server: their whole saved data table (read-only copy), or nil. (Admin > Stat Lookup)
function PlayerData.GetOfflineData(userId)
	local ok, view = pcall(function() return Store:GetAsync("Player_" .. userId) end)
	if not ok or not view or type(view.Data) ~= "table" then return nil end
	return view.Data
end

-- live playtime (banked + this session) of someone in this server
function PlayerData.GetPlaytime(player)
	local d = PlayerData.Get(player)
	if not d then return 0 end
	return (d.Playtime or 0) + (sessionStart[player] and (os.clock() - sessionStart[player]) or 0)
end

function PlayerData.GetLevel(player)
	local d = PlayerData.Get(player)
	return Config.LevelFromXP(d and d.XP or 0)
end

for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end
Players.PlayerAdded:Connect(onPlayerAdded)
-- PLAYTIME: bank the time played into the profile (every minute + when leaving)
local function bankPlaytime(player)
	local p, start = Profiles[player], sessionStart[player]
	if not (p and start) then return end
	local now = os.clock()
	p.Data.Playtime = (p.Data.Playtime or 0) + (now - start)
	sessionStart[player] = now
end
task.spawn(function()
	while true do
		task.wait(60)
		for player in Profiles do bankPlaytime(player) end
	end
end)

-- other scripts can change a leaving player's data before it's saved:  PlayerData.BeforeLeave(function(player) ... end)
local leaveHooks = {}
function PlayerData.BeforeLeave(fn) table.insert(leaveHooks, fn) end

Players.PlayerRemoving:Connect(function(player)
	for _, fn in leaveHooks do
		local ok, err = pcall(fn, player)
		if not ok then warn("[PlayerData] BeforeLeave: " .. tostring(err)) end
	end
	bankPlaytime(player)
	sessionStart[player] = nil
	local profile = Profiles[player]
	if profile then profile:EndSession() end
end)

return PlayerData
