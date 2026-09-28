-- GLOBAL MATCHMAKING (the Play menu)
-- Players pick 1v1 / 2v2 / 3v3 / 4v4 and search. Everyone searching the same mode in the same REGION, on ANY server,
-- is in one queue (MemoryStoreService). When enough are found, one server reserves a private match server and
-- tells every server (MessagingService) to teleport its players there. The match server waits for everyone, runs
-- the normal match (MatchmakingServer), then sends people back to a lobby.
--   * "Queue Again" on the end screen starts a new search straight away (you keep searching through the teleport).
--   * Not everyone arrives in time -> "Match Cancelled" and everyone who did arrive goes back to searching.
--   * Win streaks of 10+ being broken -> [SERVER] announcement, 50+ -> [GLOBAL] announcement (every server).
-- Settings: ReplicatedStorage > Matchmaking > Config > Global / StreakAnnounceMin / StreakAnnounceGlobal
-- Regions:  ReplicatedStorage > Matchmaking > Regions
-- STUDIO: teleports don't work in Studio, so a match found in Studio starts right here instead (and uses its own
-- queue, so Studio testers never get matched with real players).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")

local MM = RS:WaitForChild("Matchmaking")
local Config = require(MM:WaitForChild("Config"))
local Regions = require(MM:WaitForChild("Regions"))
local Remotes = MM:WaitForChild("Remotes")
local SearchRemote = Remotes:WaitForChild("Search")
local AnnounceRemote = Remotes:WaitForChild("Announce")
-- PARTIES: the leader searches for the whole party; they always end up on the same team (ServerStorage > Parties)
local Parties = require(game:GetService("ServerStorage"):WaitForChild("Parties"))
-- fired by MatchUI > MatchClient once a player's match UI has loaded
local ClientReady = Remotes:FindFirstChild("ClientReady") or Instance.new("RemoteEvent")
ClientReady.Name = "ClientReady"
ClientReady.Parent = Remotes
local Hooks = script.Parent:WaitForChild("MatchmakingServer"):WaitForChild("Hooks")
local StartMatchHook = Hooks:WaitForChild("StartMatch")

local G = Config.Global or {}
local MODES = {}
for _, m in G.Modes or {"1v1", "2v2", "3v3", "4v4"} do MODES[m] = tonumber(m:match("^(%d)v")) end
local CHECK_EVERY = G.CheckEvery or 3
local ENTRY_LIFE = G.EntryLife or 60
local JOIN_TIMEOUT = G.JoinTimeout or 30

local IS_STUDIO = RunService:IsStudio()
local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local PREFIX = IS_STUDIO and "Studio_" or ""
local TOPIC_FOUND = PREFIX .. "MM_MatchFound"
local TOPIC_ANNOUNCE = "MM_Announce"

local function now() return workspace:GetServerTimeNow() end
local function queueName(mode, region) return PREFIX .. "Q_" .. mode .. "_" .. region end
local queues = {}
local function queue(mode, region)
	local n = queueName(mode, region)
	queues[n] = queues[n] or MemoryStoreService:GetSortedMap(n)
	return queues[n]
end
local Locks = MemoryStoreService:GetSortedMap(PREFIX .. "MM_Locks")

------------------------------------------------------------ STATUS -> CLIENT (StarterGui > SearchUI)
-- State: Searching / Found / Teleporting / Waiting / Idle / Cancelled (popup) / Notice (popup)
local function status(p, state, extra)
	if p.Parent ~= Players then return end
	local msg = extra or {}
	msg.State = state
	SearchRemote:FireClient(p, msg)
end

------------------------------------------------------------ SEARCHING
local searching = {} -- [player who started it (solo player / party leader)] = {mode, region, since, members}
local searchOwner = {} -- [every member of a running search] = the player who started it

local function writeEntry(p, s)
	local ok, err = pcall(function()
		local ids = {}
		for _, m in s.members or {p} do table.insert(ids, m.UserId) end
		queue(s.mode, s.region):SetAsync(tostring(p.UserId), {job = game.JobId, t = s.since, ids = ids, party = s.party}, ENTRY_LIFE, s.since)
	end)
	if not ok then warn("[GlobalMatchmaking] queue write: " .. tostring(err)) end
	return ok
end

-- stops the search p is part of (a party member cancelling stops the whole party's search)
local function stopSearch(p, silent)
	local owner = searchOwner[p] or p
	local s = searching[owner]
	if not s then return end
	searching[owner] = nil
	for _, m in s.members or {owner} do
		searchOwner[m] = nil
		if m.Parent == Players then
			m:SetAttribute("Searching", nil)
			if not silent then status(m, "Idle") end
		end
	end
	task.spawn(function()
		pcall(function() queue(s.mode, s.region):RemoveAsync(tostring(owner.UserId)) end)
	end)
end
-- found a match: forget the search without touching the queue (the matchmaker already took the entry out)
local function clearSearch(p)
	local owner = searchOwner[p] or p
	local s = searching[owner]
	if s then
		searching[owner] = nil
		for _, m in s.members or {owner} do searchOwner[m] = nil if m.Parent == Players then m:SetAttribute("Searching", nil) end end
	end
	searchOwner[p] = nil
	if p.Parent == Players then p:SetAttribute("Searching", nil) end
end
local function sinceOfSearch(p)
	local s = searching[searchOwner[p] or p]
	return s and s.since
end

local function canSearch(p)
	if p:GetAttribute("MatchId") ~= nil and not p:GetAttribute("MatchEnded") then return false end
	return true
end

local function startSearch(p, mode, since)
	if not MODES[mode] or not canSearch(p) then return end
	local members = Parties.Members(p)
	if #members > 1 then
		if not Parties.IsLeader(p) then
			status(p, "Notice", {Title = "Party", Text = "Only the party leader can search for a match."})
			return
		end
		if #members > MODES[mode] then
			status(p, "Notice", {Title = "Party", Text = ("Your party has %d players - pick %dv%d or bigger."):format(#members, #members, #members)})
			return
		end
		for _, m in members do
			if not canSearch(m) then
				status(p, "Notice", {Title = "Party", Text = m.DisplayName .. " is still in a match."})
				return
			end
		end
	end
	for _, m in members do stopSearch(m, true) end
	local s = {mode = mode, region = Regions.ForPlayer(p), since = since or now(), members = members, party = Parties.Info(p)}
	searching[p] = s
	for _, m in members do
		searchOwner[m] = p
		m:SetAttribute("Searching", mode)
		status(m, "Searching", {Mode = mode, Since = s.since, Region = s.region})
	end
	task.spawn(function()
		if not writeEntry(p, s) and searching[p] == s then
			stopSearch(p, true)
			status(p, "Notice", {Title = "Matchmaking", Text = "Couldn't start searching, try again in a moment."})
		end
	end)
end

SearchRemote.OnServerEvent:Connect(function(p, msg)
	if typeof(msg) ~= "table" then return end
	if msg.Action == "Start" and typeof(msg.Mode) == "string" then
		startSearch(p, msg.Mode)
	elseif msg.Action == "Cancel" then
		stopSearch(p)
	end
end)

-- someone joined / left / got kicked from a party that was searching -> that search stops
Parties.Changed:Connect(function(party, reason, who)
	if reason == "restored" then return end
	local list = table.clone(party.Members)
	if who then table.insert(list, who) end
	for _, m in list do
		if searchOwner[m] then
			stopSearch(m)
			status(m, "Notice", {Title = "Party", Text = "The party changed, so the search was stopped."})
		end
	end
end)

-- keep our searches alive in the queue (entries expire if a server dies)
task.spawn(function()
	while true do
		task.wait(math.max(5, ENTRY_LIFE / 3))
		for p, s in searching do
			if p.Parent == Players then task.spawn(writeEntry, p, s) end
		end
	end
end)

------------------------------------------------------------ MATCH FOUND -> TELEPORT
local function playerById(id) return Players:GetPlayerByUserId(tonumber(id) or 0) end

local pendingTeleport = {} -- [player] = mode (to put them back in the queue if the teleport fails)

local function onMatchFound(data)
	if type(data) ~= "table" or type(data.Teams) ~= "table" then return end
	local mine = {}
	for _, team in data.Teams do
		for _, id in team do
			local p = playerById(id)
			if p then table.insert(mine, p) end
		end
	end
	if #mine == 0 then return end
	for _, p in mine do
		clearSearch(p)
		pendingTeleport[p] = data.Mode
		status(p, "Found", {Mode = data.Mode})
	end
	task.wait(1.2)
	for _, p in mine do status(p, "Teleporting", {Mode = data.Mode}) end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = data.Code
	options:SetTeleportData({Match = {Id = data.Id, Mode = data.Mode, Teams = data.Teams, Parties = data.Parties}})
	local list = {}
	for _, p in mine do if p.Parent == Players then table.insert(list, p) end end
	local ok, err = pcall(function() TeleportService:TeleportAsync(game.PlaceId, list, options) end)
	if not ok then
		warn("[GlobalMatchmaking] teleport failed: " .. tostring(err))
		for _, p in list do
			pendingTeleport[p] = nil
			status(p, "Cancelled", {Text = "Couldn't join the match. Rejoining matchmaking..."})
			if Parties.IsLeader(p) then startSearch(p, data.Mode) end
		end
	end
end

TeleportService.TeleportInitFailed:Connect(function(p, result, err)
	local mode = pendingTeleport[p]
	if not mode then return end
	pendingTeleport[p] = nil
	status(p, "Cancelled", {Text = "Couldn't join the match. Rejoining matchmaking..."})
	if Parties.IsLeader(p) then startSearch(p, mode) end
end)

if not IS_STUDIO then
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC_FOUND, function(message) onMatchFound(message.Data) end)
		end)
		if not ok then warn("[GlobalMatchmaking] subscribe: " .. tostring(err)) end
	end)
end

------------------------------------------------------------ THE MATCHMAKER
-- Each check, a server that has players searching tries to become the matchmaker for that queue (a short lock),
-- so only ONE server ever pulls players out of a queue at a time.
local function takeLock(name)
	local got = false
	pcall(function()
		Locks:UpdateAsync("lock_" .. name, function(old)
			if old and old.job ~= game.JobId and (old.untilT or 0) > now() then return nil end
			got = true
			return {job = game.JobId, untilT = now() + CHECK_EVERY * 2}
		end, CHECK_EVERY * 4)
	end)
	return got
end

local function tryMatch(mode, region)
	local size = MODES[mode]
	local need = size * 2
	local solo = IS_STUDIO and Config.SoloTest
	if solo then need = 1 end
	local name = queueName(mode, region)
	if not takeLock(name) then return end
	local map = queue(mode, region)
	local ok, items = pcall(function() return map:GetRangeAsync(Enum.SortDirection.Ascending, 100) end)
	if not ok or #items == 0 then return end
	-- oldest first; a party (several ids in one entry) always goes onto ONE team, filling the emptier team first
	local teams, picked, parties = {{}, {}}, {}, {}
	local room = {size, solo and 0 or size}
	for _, it in items do
		local v = it.value
		local ids = (type(v) == "table" and type(v.ids) == "table" and #v.ids > 0) and v.ids or {it.key}
		local t = room[1] >= room[2] and 1 or 2
		if room[t] < #ids then t = (t == 1) and 2 or 1 end
		if room[t] >= #ids then
			for _, id in ids do table.insert(teams[t], tostring(id)) end
			room[t] -= #ids
			table.insert(picked, it)
			if type(v) == "table" and type(v.party) == "table" then table.insert(parties, v.party) end
		end
		if room[1] == 0 and room[2] == 0 then break end
		if solo and #picked >= 1 then break end
	end
	if not solo and (room[1] > 0 or room[2] > 0) then return end -- not enough players yet
	if #picked == 0 then return end
	for _, it in picked do pcall(function() map:RemoveAsync(it.key) end) end
	local id = HttpService:GenerateGUID(false):sub(1, 8)

	if IS_STUDIO then
		-- no teleports in Studio: start the match right here
		local t = {{}, {}}
		local sinceOf = {}
		for i, team in teams do
			for _, key in team do
				local p = playerById(key)
				if p then
					sinceOf[p] = sinceOfSearch(p)
					clearSearch(p)
					table.insert(t[i], p)
				end
			end
		end
		local busy = false
		for _, team in t do for _, p in team do if p:GetAttribute("MatchId") ~= nil then busy = true end end end
		if busy then
			for _, team in t do for _, p in team do if Parties.IsLeader(p) then startSearch(p, mode, sinceOf[p]) end end end
			return
		end
		for _, team in t do for _, p in team do status(p, "Found", {Mode = mode}) end end
		task.wait(1.2)
		for _, team in t do for _, p in team do status(p, "Idle") end end
		local ok2, started = pcall(function() return StartMatchHook:Invoke(t[1], t[2]) end)
		if not (ok2 and started) then
			-- someone's still busy (e.g. on the end screen): keep them searching and try again next check
			for _, team in t do for _, p in team do if Parties.IsLeader(p) then startSearch(p, mode, sinceOf[p]) end end end
		end
		return
	end

	local okR, code = pcall(function() return TeleportService:ReserveServer(game.PlaceId) end)
	if not okR then
		warn("[GlobalMatchmaking] reserve server: " .. tostring(code))
		-- put them back so nobody loses their place
		for _, it in picked do pcall(function() map:SetAsync(it.key, it.value, ENTRY_LIFE, it.sortKey or (type(it.value) == "table" and it.value.t) or now()) end) end
		return
	end
	local data = {Code = code, Mode = mode, Teams = teams, Id = id, Parties = parties}
	local okP, err = pcall(function() MessagingService:PublishAsync(TOPIC_FOUND, data) end)
	if not okP then
		warn("[GlobalMatchmaking] publish: " .. tostring(err))
		task.spawn(onMatchFound, data) -- at least move the players on this server
	end
end

task.spawn(function()
	while true do
		task.wait(CHECK_EVERY)
		local todo = {}
		for p, s in searching do
			if p.Parent == Players then todo[s.mode .. "|" .. s.region] = {s.mode, s.region} end
		end
		for _, q in todo do
			local ok, err = pcall(tryMatch, q[1], q[2])
			if not ok then warn("[GlobalMatchmaking] " .. tostring(err)) end
		end
	end
end)

------------------------------------------------------------ PLAYERS JOINING / LEAVING
local expected -- match servers: {Id, Mode, Teams}
local arrived = {} -- [userId string] = player
local matchStarted, matchCancelled = false, false

local sentToLobby = {} -- [player] = true once their teleport started (a party goes in one teleport)
local function sendToLobby(p, requeue)
	if p.Parent ~= Players or sentToLobby[p] then return end
	-- the whole party goes back together, to the same lobby server
	local list = {}
	for _, m in Parties.Members(p) do
		if m.Parent == Players and not sentToLobby[m] then table.insert(list, m) end
	end
	local leader = Parties.Leader(p)
	local s = searching[searchOwner[leader] or leader]
	local data = {FromMatch = true, Party = #list > 1 and Parties.Info(p) or nil}
	if s then
		data.Requeue = {Mode = s.mode, Since = s.since}
	elseif requeue then
		data.Requeue = {Mode = requeue}
	end
	-- a party's search is restarted by the leader only, once everyone's back
	if data.Requeue and #list > 1 then data.Requeue.Leader = leader.UserId end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(data)
	for _, m in list do
		sentToLobby[m] = true
		status(m, "Teleporting", {Mode = s and s.mode or requeue or "Lobby", ToLobby = true})
	end
	local ok, err = pcall(function() TeleportService:TeleportAsync(game.PlaceId, list, options) end)
	if not ok then
		warn("[GlobalMatchmaking] back to lobby: " .. tostring(err))
		for _, m in list do sentToLobby[m] = nil end
	end
end
Hooks:WaitForChild("SendToLobby").Event:Connect(function(p) sendToLobby(p) end)

-- a player counts as ready once their match UI has loaded and they have a character
-- (or after READY_TIMEOUT seconds on the server, so one slow loader can't hold the match forever)
local READY_TIMEOUT = 15
local ready, arrivedAt = {}, {}
ClientReady.OnServerEvent:Connect(function(p) ready[p] = true end)
local function isReady(p)
	if ready[p] and p.Character and p.Character:FindFirstChildOfClass("Humanoid") then return true end
	return arrivedAt[p] ~= nil and os.clock() - arrivedAt[p] > READY_TIMEOUT
end

local starting = false
local function checkStart()
	if matchStarted or matchCancelled or not expected or starting then return end
	local t = {{}, {}}
	for i, team in expected.Teams do
		for _, id in team do
			local p = arrived[tostring(id)]
			if not p or p.Parent ~= Players then return end -- still waiting
			table.insert(t[i], p)
		end
	end
	-- everyone's here: wait until they've all loaded in, then go
	starting = true
	task.spawn(function()
		while true do
			local allReady = true
			for _, team in t do for _, p in team do if p.Parent == Players and not isReady(p) then allReady = false end end end
			if allReady then break end
			task.wait(0.25)
		end
		task.wait(1) -- a moment for the screen to settle
		if matchStarted or matchCancelled then return end
		matchStarted = true
		local t2 = {{}, {}}
		for i, team in t do for _, p in team do if p.Parent == Players then table.insert(t2[i], p) end end end
		for _, team in t2 do for _, p in team do status(p, "Idle") end end
		StartMatchHook:Invoke(t2[1], t2[2])
	end)
end

local function onPlayerAdded(p)
	Regions.ForPlayer(p)
	local join = p:GetJoinData()
	local td = join and join.TeleportData
	if IS_MATCH_SERVER then
		-- an admin reloaded their lobby (AdminServer > ReloadServer): this is just a stop on the way to a fresh lobby
		if type(td) == "table" and td.Reload == true then
			status(p, "Teleporting", {Mode = "Lobby", ToLobby = true})
			task.delay(6, sendToLobby, p) -- (the old server has closed by then, so they land in a new one)
			return
		end
		if type(td) == "table" and type(td.Match) == "table" and not expected then
			expected = td.Match
			-- not everyone made it in time -> cancel, everyone who's here goes back to searching
			task.delay(JOIN_TIMEOUT, function()
				if matchStarted or starting then return end -- (starting = everyone's here, just loading in)
				matchCancelled = true
				for _, pl in Players:GetPlayers() do
					status(pl, "Cancelled", {Text = "Not enough players joined in time. Rejoining matchmaking..."})
				end
				task.wait(3)
				for _, pl in Players:GetPlayers() do task.spawn(sendToLobby, pl, expected.Mode) end
			end)
		end
		arrived[tostring(p.UserId)] = p
		arrivedAt[p] = os.clock()
		for _, info in (expected and expected.Parties) or {} do
			if type(info) == "table" and type(info.Members) == "table" and table.find(info.Members, p.UserId) then Parties.Restore(p, info) end
		end
		if matchCancelled then
			task.spawn(sendToLobby, p, expected and expected.Mode)
		elseif not matchStarted then
			status(p, "Waiting", {Mode = expected and expected.Mode or ""})
			checkStart()
		else
			-- joined after it started (e.g. rejoined): nothing to do here, back to a lobby
			task.spawn(sendToLobby, p)
		end
		return
	end
	-- lobby: back from a match together with your party
	if type(td) == "table" and type(td.Party) == "table" then Parties.Restore(p, td.Party) end
	-- lobby: came back from a match still searching (Queue Again), or a cancelled match -> keep searching
	if type(td) == "table" and type(td.Requeue) == "table" and MODES[td.Requeue.Mode] then
		local lead = td.Requeue.Leader
		if lead and lead ~= p.UserId then return end -- the party leader restarts it for everyone
		if lead and type(td.Party) == "table" and type(td.Party.Members) == "table" then
			-- wait (a little) for the rest of the party to arrive
			local t0 = os.clock()
			while os.clock() - t0 < 10 do
				local all = true
				for _, id in td.Party.Members do if not Players:GetPlayerByUserId(id) then all = false end end
				if all then break end
				task.wait(0.5)
			end
		end
		task.wait(2) -- let their UI load
		if p.Parent == Players then startSearch(p, td.Requeue.Mode, td.Requeue.Since) end
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

Players.PlayerRemoving:Connect(function(p)
	pendingTeleport[p] = nil
	sentToLobby[p] = nil
	searchOwner[p] = nil
	-- teleporting away with a search running: the entry stays (the next server refreshes it); otherwise remove it
	local s = searching[p]
	searching[p] = nil
	if s and not IS_MATCH_SERVER then
		pcall(function() queue(s.mode, s.region):RemoveAsync(tostring(p.UserId)) end)
	end
end)

------------------------------------------------------------ WIN STREAK ANNOUNCEMENTS
local GREEN, PURPLE = "#46E66E", "#B964FF"
local function streakText(kind, victim, winners, mode)
	local c = kind == "GLOBAL" and PURPLE or GREEN
	local by = {}
	for _, w in winners do table.insert(by, ("@%s (%d winstreak)"):format(w.Name, w.Streak)) end
	local list = #by > 1 and (table.concat(by, ", ", 1, #by - 1) .. " and " .. by[#by]) or (by[1] or "someone")
	return ('[%s]: <font color="%s">@%s</font> just had their <font color="%s">%d winstreak</font> ended by %s in a %s')
		:format(kind, c, victim.Name, c, victim.Streak, list, mode or "match")
end

local function announceHere(kind, text)
	AnnounceRemote:FireAllClients({Kind = kind, Text = text})
end

if not IS_STUDIO then
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_ANNOUNCE, function(message)
				local d = message.Data
				if type(d) == "table" and type(d.Text) == "string" then announceHere(d.Kind or "GLOBAL", d.Text) end
			end)
		end)
	end)
end

Hooks:WaitForChild("StreakEnded").Event:Connect(function(victim, winners, mode)
	if victim.Streak >= (Config.StreakAnnounceGlobal or 50) then
		local text = streakText("GLOBAL", victim, winners, mode)
		local ok = not IS_STUDIO and pcall(function() MessagingService:PublishAsync(TOPIC_ANNOUNCE, {Kind = "GLOBAL", Text = text}) end)
		if not ok then announceHere("GLOBAL", text) end
	else
		announceHere("SERVER", streakText("SERVER", victim, winners, mode))
	end
end)
