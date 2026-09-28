-- LEADERBOARDS (server)
-- Every UpdateEvery seconds: saves everyone's stats to Roblox's ordered data stores, reads the top players
-- and works out every online player's rank. The boards themselves are drawn by StarterPlayerScripts > LeaderboardClient.
-- Settings: ReplicatedStorage > LeaderboardConfig
-- Data for the clients: ReplicatedStorage > LeaderboardData > "<Board>_AllTime" / "<Board>_Monthly" (JSON lists)
-- and on each player the attribute "LB_<Board>_<Period>" = "rank|value" (rank "" = not ranked, "+1000" = below place 1000).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DSS = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local UserService = game:GetService("UserService")
local RunService = game:GetService("RunService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local C = require(RS:WaitForChild("LeaderboardConfig"))
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))

local folder = RS:FindFirstChild("LeaderboardData") or Instance.new("Folder")
folder.Name = "LeaderboardData"
folder.Parent = RS

local function monthKey() return os.date("!%Y-%m") end
local function periods(board) return board.Monthly and {"AllTime", "Monthly"} or {"AllTime"} end
local function storeName(board, period)
	-- board.Store (if set) keeps the saved data's name the same when a board is renamed
	return "LB_" .. (board.Store or board.Name) .. "_" .. (period == "AllTime" and "AllTime" or monthKey())
end

local function valueFor(p, board, period)
	local d = PlayerData.Get(p)
	if not d then return nil end
	if period == "Monthly" then return math.floor(PlayerData.GetMonthly(p, board.Stat)) end
	return math.floor(d[board.Stat] or 0)
end

------------------------------------------------------------ STUDIO FAKE DATA
local fake = false -- switches on when Studio can't reach the data stores
local fakeLists = {}
local function fakeList(key)
	if fakeLists[key] then return fakeLists[key] end
	local rng = Random.new(#key * 7919)
	local list, v = {}, rng:NextInteger(20000, 30000)
	for i = 1, C.RankLimit do
		table.insert(list, {id = -i, v = v})
		v = math.max(1, v - rng:NextInteger(1, i < 20 and 900 or 40))
	end
	fakeLists[key] = list
	return list
end

------------------------------------------------------------ STATE
local cache = {}       -- ["Kills_AllTime"] = {values = {v...} (sorted, up to RankLimit), complete = bool}
local written = {}     -- [userId .. key] = last value we saved
local nameCache = {}   -- [userId] = {n = username, d = display name}

local function names(ids)
	local need = {}
	for _, id in ids do if id > 0 and not nameCache[id] then table.insert(need, id) end end
	for i = 1, #need, 100 do
		local chunk = table.move(need, i, math.min(i + 99, #need), 1, {})
		local ok, infos = pcall(function() return UserService:GetUserInfosByUserIdsAsync(chunk) end)
		if ok then
			for _, info in infos do nameCache[info.Id] = {n = info.Username, d = NameBadge.Format(info.DisplayName, info.HasVerifiedBadge)} end
		end
		for _, id in chunk do
			if not nameCache[id] then
				local ok2, n = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
				nameCache[id] = {n = ok2 and n or "?", d = ok2 and n or "?"}
			end
		end
	end
end

local function budget()
	local ok, b = pcall(function() return DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync) end)
	return ok and b or 0
end

------------------------------------------------------------ RANK (from the cached sorted values, no data store calls)
-- returns "" (nothing), "123" (exact), or "+N" (below the N places we fetched, e.g. "+1000")
local function rankOf(key, v)
	if not v or v <= 0 then return "" end
	local c = cache[key]
	if not c then return "" end
	for i, other in c.values do
		if v >= other then return tostring(i) end
	end
	if c.complete then return tostring(#c.values + 1) end
	return "+" .. #c.values
end

local function updatePlayerAttrs(p)
	for _, board in C.Boards do
		for _, period in periods(board) do
			local key = board.Name .. "_" .. period
			local v = valueFor(p, board, period)
			if v then p:SetAttribute("LB_" .. key, rankOf(key, v) .. "|" .. v) end
		end
	end
end

------------------------------------------------------------ ONE REFRESH
local function refreshBoard(board, period)
	local key = board.Name .. "_" .. period
	local store = DSS:GetOrderedDataStore(storeName(board, period))
	-- 1) save everyone who's online
	if not fake then
		for _, p in Players:GetPlayers() do
			local v = valueFor(p, board, period)
			local wk = p.UserId .. key .. storeName(board, period)
			if v and written[wk] ~= v and (v > 0 or (written[wk] or 0) > 0) then
				local ok, err = pcall(function() store:SetAsync("u" .. p.UserId, v) end)
				if ok then written[wk] = v
				elseif RunService:IsStudio() and C.StudioFakeData then fake = true
				else warn("[Leaderboards] save " .. key .. ": " .. tostring(err)) end
			end
		end
	end
	-- 2) read the top (and further down, while there's budget, so ranks can be exact up to RankLimit)
	local rows, values, complete = {}, {}, false
	if fake then
		local list = table.clone(fakeList(key))
		-- slot the real online players in by their real value
		for _, p in Players:GetPlayers() do
			local v = valueFor(p, board, period)
			if v and v > 0 then table.insert(list, {id = p.UserId, v = v}) end
		end
		table.sort(list, function(a, b) return a.v > b.v end)
		for i, e in list do
			if i <= C.TopCount then table.insert(rows, e) end
			if i <= C.RankLimit then table.insert(values, e.v) end
		end
		complete = #list <= C.RankLimit
	else
		local ok, pages = pcall(function() return store:GetSortedAsync(false, 100, 1) end)
		if not ok then
			if RunService:IsStudio() and C.StudioFakeData then fake = true return refreshBoard(board, period) end
			warn("[Leaderboards] read " .. key .. ": " .. tostring(pages))
			return
		end
		-- lowest value among online players who aren't in the top yet: only page further if someone needs it
		local lowestNeeded = math.huge
		for _, p in Players:GetPlayers() do
			local v = valueFor(p, board, period)
			if v and v > 0 then lowestNeeded = math.min(lowestNeeded, v) end
		end
		while true do
			for _, e in pages:GetCurrentPage() do
				local id = tonumber(tostring(e.key):match("%d+"))
				if id then
					if #rows < C.TopCount then table.insert(rows, {id = id, v = e.value}) end
					table.insert(values, e.value)
				end
			end
			if pages.IsFinished then complete = true break end
			if #values >= C.RankLimit then break end
			if #rows >= C.TopCount and values[#values] < lowestNeeded then break end -- nobody online is further down
			if budget() < 3 then break end -- save budget for the other boards; exact ranks catch up next time
			local okNext = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not okNext then break end
		end
		if #values < C.RankLimit and not complete and values[#values] and values[#values] < lowestNeeded then
			complete = false -- we stopped early on purpose; online players are all above this point
		end
	end
	cache[key] = {values = values, complete = complete}
	-- 3) names for the rows
	local ids = {}
	for _, r in rows do table.insert(ids, r.id) end
	names(ids)
	local out = {}
	for _, r in rows do
		local nm = nameCache[r.id]
		local fakeName = r.id < 0 and ("Player" .. (-r.id)) or nil
		table.insert(out, {u = r.id, n = fakeName or (nm and nm.n) or "?", d = fakeName or (nm and nm.d) or "?", v = r.v})
	end
	local sv = folder:FindFirstChild(key) or Instance.new("StringValue")
	sv.Name = key
	sv.Value = HttpService:JSONEncode(out)
	sv:SetAttribute("Month", monthKey())
	sv.Parent = folder
end

local function refreshAll()
	for _, board in C.Boards do
		for _, period in periods(board) do
			local ok, err = pcall(refreshBoard, board, period)
			if not ok then warn("[Leaderboards] " .. board.Name .. " " .. period .. ": " .. tostring(err)) end
		end
	end
	for _, p in Players:GetPlayers() do updatePlayerAttrs(p) end
end

------------------------------------------------------------ LOOP
task.spawn(function()
	task.wait(8) -- let everyone's data load first
	while true do
		folder:SetAttribute("NextUpdate", workspace:GetServerTimeNow() + C.UpdateEvery)
		refreshAll()
		task.wait(C.UpdateEvery)
	end
end)

-- your "You" row only changes when the boards refresh, so it always matches the list above it.
-- (Joining players get theirs filled in once, as soon as their data has loaded.)
Players.PlayerAdded:Connect(function(p)
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 30 do task.wait(0.5) end
	if p.Parent == Players and p:GetAttribute("LB_Kills_AllTime") == nil then pcall(updatePlayerAttrs, p) end
end)

-- save a leaving player's final numbers
PlayerData.BeforeLeave(function(p)
	if fake then return end
	for _, board in C.Boards do
		for _, period in periods(board) do
			local key = board.Name .. "_" .. period
			local v = valueFor(p, board, period)
			local wk = p.UserId .. key .. storeName(board, period)
			if v and written[wk] ~= v and (v > 0 or (written[wk] or 0) > 0) then
				task.spawn(function()
					pcall(function() DSS:GetOrderedDataStore(storeName(board, period)):SetAsync("u" .. p.UserId, v) end)
				end)
			end
			written[wk] = nil
		end
	end
end)
