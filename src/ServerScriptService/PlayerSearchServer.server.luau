-- PLAYER SEARCH (Main > Top > Search button -> Main > SearchFrame)
--   PlayerSearch:InvokeServer("Lookup", "username") -> profile data of ANY player by exact username (online or offline)
--   PlayerSearch:InvokeServer("Profile", player)    -> profile data of someone in this server
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local Remote = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes"):WaitForChild("PlayerSearch")

local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

------------------------------------------------------------ WHO'S ONLINE (every server keeps its players listed here)
-- MemoryStore map "Presence": userId -> {Job = server id, Match = true on a match server}; entries expire if a server dies.
local Presence = MemoryStoreService:GetHashMap((RunService:IsStudio() and "Studio_" or "") .. "Presence_v1")
local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local PRESENCE_LIFE = 150
local function announce(p)
	pcall(function() Presence:SetAsync(tostring(p.UserId), {Job = game.JobId, Match = IS_MATCH_SERVER}, PRESENCE_LIFE) end)
end
local function presenceOf(userId)
	local ok, v = pcall(function() return Presence:GetAsync(tostring(userId)) end)
	if ok and type(v) == "table" then return v end
	return nil
end
Players.PlayerAdded:Connect(announce)
for _, p in Players:GetPlayers() do task.spawn(announce, p) end
Players.PlayerRemoving:Connect(function(p)
	-- only clear it if they're still listed as HERE (teleporting players get re-listed by the next server)
	local v = presenceOf(p.UserId)
	if v and v.Job == game.JobId then pcall(function() Presence:RemoveAsync(tostring(p.UserId)) end) end
end)
task.spawn(function()
	while true do
		task.wait(60)
		for _, p in Players:GetPlayers() do task.spawn(announce, p) end
	end
end)

local lastAsk = {} -- [player] = os.clock() (one lookup per second each)
local cache = {} -- [lowercase name] = {userId, name, time}

Remote.OnServerInvoke = function(p, action, arg)
	if action == "Profile" then
		if typeof(arg) ~= "Instance" or not arg:IsA("Player") or arg.Parent ~= Players then return nil end
		return PlayerData.GetPublicProfile(arg)
	elseif action == "Lookup" then
		if type(arg) ~= "string" then return nil, "Type a username" end
		local name = arg:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
		if #name < 3 or #name > 20 or name:find("[^%w_]") then return nil, "That isn't a valid username" end
		if lastAsk[p] and os.clock() - lastAsk[p] < 1 then return nil, "Slow down a little" end
		lastAsk[p] = os.clock()
		-- in this server? then it's live data
		for _, pl in Players:GetPlayers() do
			if pl.Name:lower() == name:lower() then return PlayerData.GetPublicProfile(pl) end
		end
		local key = name:lower()
		local c = cache[key]
		local userId, realName
		if c and os.clock() - c[3] < 300 then
			userId, realName = c[1], c[2]
		else
			local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
			if not ok or not id then return nil, "No player called " .. name end
			userId = id
			local ok2, realN = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
			realName = ok2 and realN or name
			cache[key] = {userId, realName, os.clock()}
		end
		local display, verified = realName, false
		pcall(function()
			local info = UserService:GetUserInfosByUserIdsAsync({userId})
			if info and info[1] then display = info[1].DisplayName verified = info[1].HasVerifiedBadge == true end
		end)
		local data = PlayerData.GetOfflineProfile(userId, realName, display, verified)
		if not data then return nil, realName .. " hasn't played Balloon Duels yet" end
		-- online in another server?
		local pres = presenceOf(userId)
		if pres and pres.Job ~= game.JobId then
			data.Offline = false
			data.OnlineElsewhere = true
			data.CanJoin = not pres.Match -- (a match server is private: no joining)
			data.InMatch = pres.Match == true
		end
		return data
	end
	if action == "Join" then
		-- follow someone to their server (lobbies only)
		local userId = tonumber(arg)
		if not userId then return nil, "Can't join" end
		if p:GetAttribute("MatchId") ~= nil then return nil, "Finish your match first" end
		local pres = presenceOf(userId)
		if not pres then return nil, "They aren't online any more" end
		if pres.Job == game.JobId then return nil, "They're already in this server" end
		if pres.Match then return nil, "They're in a match right now" end
		if RunService:IsStudio() then return nil, "Joining other servers doesn't work in Studio" end
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = pres.Job
		local ok, err = pcall(function() TeleportService:TeleportAsync(game.PlaceId, {p}, options) end)
		if not ok then return nil, "Couldn't join: " .. tostring(err) end
		return true
	end
	return nil
end

Players.PlayerRemoving:Connect(function(p) lastAsk[p] = nil end)
