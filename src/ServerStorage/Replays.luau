-- REPLAYS (storage) - every match is recorded by MatchmakingServer and saved here.
-- Each player keeps their LAST 20 matches (MaxPerPlayer). A replay is saved once and shared by everyone who was in
-- it; when nobody keeps it any more it's deleted, so storage stays small (~30-60 KB per 1v1).
-- Watching them: ServerScriptService > ReplayServer + StarterPlayerScripts > ReplayClient.
-- Studio can't use DataStores (unless API access is on), so there replays only last until you stop playing.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Replays = {}
Replays.MaxPerPlayer = 20
Replays.Rate = 20 -- samples per second
Replays.BYTES = 14 -- per player per sample (position 6, aim 4, state 1, hp 1, eye height 2)

local ok, store = pcall(function() return DataStoreService:GetDataStore("Replays_v1") end)
if not ok then store = nil end
local memory = setmetatable({}, {}) -- replays kept in this server (also the Studio fallback), max 40
local memOrder = {}
local function remember(id, json)
	if not memory[id] then table.insert(memOrder, id) end
	memory[id] = json
	while #memOrder > 40 do memory[table.remove(memOrder, 1)] = nil end
end
local memLists = {}

------------------------------------------------------------ PACKING
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local enc = {}
for i = 1, 64 do enc[i - 1] = B64:sub(i, i) end
local function toBase64(buf)
	local len = buffer.len(buf)
	local out = table.create(math.ceil(len / 3) * 4)
	local n = 0
	for i = 0, len - 1, 3 do
		local a = buffer.readu8(buf, i)
		local b = i + 1 < len and buffer.readu8(buf, i + 1) or 0
		local c = i + 2 < len and buffer.readu8(buf, i + 2) or 0
		local v = a * 65536 + b * 256 + c
		out[n + 1] = enc[(v // 262144) % 64]
		out[n + 2] = enc[(v // 4096) % 64]
		out[n + 3] = i + 1 < len and enc[(v // 64) % 64] or "="
		out[n + 4] = i + 2 < len and enc[v % 64] or "="
		n += 4
	end
	return table.concat(out)
end

-- samples[i] = false/nil (not there) or {Vector3 position (relative to the map), yaw, pitch, flags, hp}
function Replays.PackSamples(samples, frames)
	local buf = buffer.create(frames * Replays.BYTES)
	for i = 1, frames do
		local s = samples[i]
		local o = (i - 1) * Replays.BYTES
		if s then
			local p = s[1]
			buffer.writei16(buf, o, math.clamp(math.floor(p.X * 16 + 0.5), -32767, 32767))
			buffer.writei16(buf, o + 2, math.clamp(math.floor(p.Y * 16 + 0.5), -32767, 32767))
			buffer.writei16(buf, o + 4, math.clamp(math.floor(p.Z * 16 + 0.5), -32767, 32767))
			buffer.writeu16(buf, o + 6, math.floor(((s[2] % (2 * math.pi)) / (2 * math.pi)) * 65536 + 0.5) % 65536)
			buffer.writei16(buf, o + 8, math.clamp(math.floor(s[3] / (math.pi / 2) * 32767 + 0.5), -32767, 32767))
			buffer.writeu8(buf, o + 10, s[4] % 255)
			buffer.writeu8(buf, o + 11, s[5])
			-- camera height above the body (crouch / slide / jump), so the replay view is exactly theirs
			buffer.writei16(buf, o + 12, s[6] and math.clamp(math.floor(s[6] * 256 + 0.5), -32767, 32767) or -32768)
		else
			buffer.writeu8(buf, o + 10, 255) -- not in the match at this moment
		end
	end
	return toBase64(buf)
end

------------------------------------------------------------ SAVING
local function retry(fn)
	for attempt = 1, 3 do
		local okk, res = pcall(fn)
		if okk then return true, res end
		task.wait(2 * attempt)
	end
	return false
end
local function useStore()
	return store ~= nil and not (RunService:IsStudio() and not pcall(function() store:GetAsync("_probe") end))
end
local storeUsable -- checked once
local function canStore()
	if storeUsable == nil then storeUsable = useStore() end
	return storeUsable
end

-- what a player's list shows for one replay (small)
local function summary(rep)
	local teams = {{}, {}}
	for _, p in rep.People do
		table.insert(teams[p.Team] or teams[1], {UserId = p.UserId, Name = p.Name, Verified = p.Verified})
	end
	return {Id = rep.Id, Date = rep.Date, Map = rep.Map, Image = rep.Image, Mode = rep.Mode,
		Score1 = rep.Score1, Score2 = rep.Score2, Winner = rep.Winner, Team1 = teams[1], Team2 = teams[2],
		Length = rep.Frames / (rep.Rate or 10)}
end

local function dropReplay(id)
	memory[id] = nil
	if not canStore() then return end
	local left
	retry(function()
		store:UpdateAsync("RC_" .. id, function(n)
			left = (tonumber(n) or 1) - 1
			return left
		end)
	end)
	if left and left <= 0 then
		retry(function() store:RemoveAsync("R_" .. id) end)
		retry(function() store:RemoveAsync("RC_" .. id) end)
	end
end

local listeners = {}
function Replays.OnListChanged(fn) table.insert(listeners, fn) end

function Replays.Save(rep)
	local json = HttpService:JSONEncode(rep)
	remember(rep.Id, json)
	local sum = summary(rep)
	local users = {}
	for _, p in rep.People do table.insert(users, p.UserId) end
	if canStore() then
		retry(function() store:SetAsync("R_" .. rep.Id, json) end)
		retry(function() store:SetAsync("RC_" .. rep.Id, #users) end)
	end
	for _, uid in users do
		local removed = {}
		local function update(list)
			list = type(list) == "table" and list or {}
			table.insert(list, 1, sum)
			while #list > Replays.MaxPerPlayer do table.insert(removed, table.remove(list)) end
			return list
		end
		if canStore() then
			local newList
			retry(function() store:UpdateAsync("RL_" .. uid, function(old) table.clear(removed) newList = update(old) return newList end) end)
			memLists[uid] = newList or update(memLists[uid])
		else
			memLists[uid] = update(memLists[uid])
		end
		for _, r in removed do task.spawn(dropReplay, r.Id) end
		for _, fn in listeners do task.spawn(fn, uid) end
	end
end

------------------------------------------------------------ DELETING
-- takes one replay off this player's list (the bin button). The replay itself is only removed from storage once
-- nobody who played in it keeps it any more.
function Replays.Delete(userId, id)
	if type(id) ~= "string" or #id > 80 then return false end
	local found = false
	local function update(list)
		list = type(list) == "table" and list or {}
		for i = #list, 1, -1 do
			if type(list[i]) == "table" and list[i].Id == id then table.remove(list, i) found = true end
		end
		return list
	end
	if canStore() then
		local newList
		local okk = retry(function()
			store:UpdateAsync("RL_" .. userId, function(old) found = false newList = update(old) return newList end)
		end)
		if not okk then return false end
		memLists[userId] = newList
	else
		memLists[userId] = update(memLists[userId])
	end
	if not found then return false end
	if canStore() then
		task.spawn(dropReplay, id)
	else
		-- (no data stores: keep it in memory while someone else in this server still has it)
		local used = false
		for _, l in memLists do for _, e in l do if e.Id == id then used = true end end end
		if not used then memory[id] = nil end
	end
	for _, fn in listeners do task.spawn(fn, userId) end
	return true
end

------------------------------------------------------------ READING
function Replays.List(userId)
	if memLists[userId] then return memLists[userId] end
	if canStore() then
		local okk, list = retry(function() return store:GetAsync("RL_" .. userId) end)
		if okk then memLists[userId] = type(list) == "table" and list or {} return memLists[userId] end
	end
	return {}
end

function Replays.Get(id)
	if type(id) ~= "string" or #id > 80 then return nil end
	local json = memory[id]
	if not json and canStore() then
		local okk, res = retry(function() return store:GetAsync("R_" .. id) end)
		if okk and type(res) == "string" then json = res remember(id, res) end
	end
	if not json then return nil end
	local okk, rep = pcall(HttpService.JSONDecode, HttpService, json)
	return okk and rep or nil, json
end

-- forget cached lists of people who left (memory)
game:GetService("Players").PlayerRemoving:Connect(function(p) if canStore() then memLists[p.UserId] = nil end end)

return Replays
