-- ADMIN PANEL (server). Who's an admin + settings: ReplicatedStorage > Admin > AdminConfig. Panel: StarterGui > Main > AdminFrame.
-- Every command is checked here (the client can't give itself anything). Players who aren't in this server:
--   coins / balloons / passes / everything / reset are saved and applied the moment they're in a server
--   (straight away if they're in another server right now), bans work from anywhere, kick reaches any server.
-- Logs: every action by every admin, all servers (DataStore "AdminLogs_v1", newest first).
-- Both people get a chat message + a notice: the admin who did it and the player it was done to.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local DSS = game:GetService("DataStoreService")
local MS = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local MPS = game:GetService("MarketplaceService")

local folder = RS:WaitForChild("Admin")
local Config = require(folder:WaitForChild("AdminConfig"))
local Remote = folder:WaitForChild("Command")
local Notify = folder:WaitForChild("Notify")
local PlayerData = require(SS:WaitForChild("PlayerData"))
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local ShopConfig = require(RS:WaitForChild("ShopConfig"))
local SkinServer = script.Parent:WaitForChild("SkinServer")
local Grant, Refresh = SkinServer:WaitForChild("Grant"), SkinServer:WaitForChild("Refresh")

------------------------------------------------------------ WHO'S AN ADMIN
local adminCache = {}
local function isAdmin(p)
	if adminCache[p] ~= nil then return adminCache[p] end
	local ok = table.find(Config.UserIds or {}, p.UserId) ~= nil
	if not ok and Config.GroupId then
		local s, rank = pcall(function() return p:GetRankInGroup(Config.GroupId) end)
		ok = s and rank >= (Config.MinGroupRank or 255)
	end
	adminCache[p] = ok
	return ok
end
local function onPlayer(p)
	if isAdmin(p) then p:SetAttribute("IsAdmin", true) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end
Players.PlayerRemoving:Connect(function(p) adminCache[p] = nil end)

------------------------------------------------------------ NOTIFICATIONS (chat + notice on their screen)
local function notify(p, text)
	if p and p.Parent == Players then Notify:FireClient(p, {Text = text, Prefix = Config.ChatPrefix, Color = Config.ChatColor}) end
end

------------------------------------------------------------ LOGS
local logStore
pcall(function() logStore = DSS:GetDataStore("AdminLogs_v1") end)
local memLogs = {} -- (Studio without API access: this server only)
local function addLog(admin, line)
	local e = {t = os.time(), by = admin.Name, line = line}
	table.insert(memLogs, 1, e)
	while #memLogs > (Config.LogKeep or 200) do table.remove(memLogs) end
	if logStore then
		task.spawn(function()
			pcall(function()
				logStore:UpdateAsync("Log", function(old)
					old = type(old) == "table" and old or {}
					table.insert(old, 1, e)
					while #old > (Config.LogKeep or 200) do table.remove(old) end
					return old
				end)
			end)
		end)
	end
end
local function getLogs()
	if logStore then
		local ok, list = pcall(function() return logStore:GetAsync("Log") end)
		if ok and type(list) == "table" then return list end
	end
	return memLogs
end

------------------------------------------------------------ PASSES (ShopConfig.Passes)
local function findPass(name)
	name = (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	for _, ps in ShopConfig.Passes or {} do
		if ps.Name:lower() == name then return ps end
	end
end
local function refreshPasses(p)
	local d = PlayerData.Get(p)
	for _, ps in ShopConfig.Passes or {} do
		local owned = d and d.Passes and d.Passes[ps.Name] == true
		if not owned and (ps.Id or 0) ~= 0 then
			local ok, has = pcall(function() return MPS:UserOwnsGamePassAsync(p.UserId, ps.Id) end)
			owned = ok and has
		end
		p:SetAttribute("Pass_" .. ps.Name, owned == true)
	end
end

------------------------------------------------------------ DOING THINGS TO A PLAYER (here, now)
local function waitData(p)
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 30 do task.wait(0.25) end
	return PlayerData.Get(p)
end
-- returns what happened, for the messages ("500 coins")
local function apply(p, a)
	local d = waitData(p)
	if not d then return nil end
	if a.Kind == "Coins" then
		PlayerData.AddCoins(p, a.Amount)
		return a.Amount .. " coins"
	elseif a.Kind == "SetCoins" then
		PlayerData.Set(p, "Coins", a.Amount)
		return "coins set to " .. a.Amount
	elseif a.Kind == "Balloon" then
		Grant:Invoke(p, a.Id, a.Amount or 1)
		return (a.Amount or 1) .. "x " .. Skins.Get(a.Id).Name
	elseif a.Kind == "Pass" then
		d.Passes = d.Passes or {}
		d.Passes[a.Pass] = true
		refreshPasses(p)
		return "the " .. a.Pass .. " pass"
	elseif a.Kind == "Everything" then
		local n = 0
		for _, s in Skins.Skins do
			local owned = d.Balloons and d.Balloons[s.Id] and d.Balloons[s.Id].Count or 0
			if s.Id ~= Skins.DefaultId and owned <= 0 then Grant:Invoke(p, s.Id, 1) n += 1 end
		end
		d.Passes = d.Passes or {}
		for _, ps in ShopConfig.Passes or {} do d.Passes[ps.Name] = true end
		refreshPasses(p)
		return "every balloon (" .. n .. " new) and every pass"
	elseif a.Kind == "Reset" then
		for _, k in {"Kills", "Deaths", "Wins", "Losses", "Matches", "WinStreak", "MonthKills", "MonthWins", "XP", "Coins"} do d[k] = 0 end
		d.RewardedLevel = 1
		d.NextLevelCoins = 0
		d.Balloons = {}
		d.EquippedSkin = Skins.DefaultId
		PlayerData.Set(p, "Coins", 0) -- (re-sends level / coins / streak)
		Refresh:Invoke(p)
		return "a stats reset"
	end
end

------------------------------------------------------------ PLAYERS WHO AREN'T HERE (saved, applied when they're in a server)
local pendStore
pcall(function() pendStore = DSS:GetDataStore("AdminPending_v1") end)
local function addPending(userId, a)
	if not pendStore then return false end
	local ok = pcall(function()
		pendStore:UpdateAsync(tostring(userId), function(old)
			old = type(old) == "table" and old or {}
			table.insert(old, a)
			return old
		end)
	end)
	if ok then pcall(function() MS:PublishAsync("AdminApply", userId) end) end -- (in another server right now: now)
	return ok
end
local applying = {}
local function applyPending(p)
	if not pendStore or applying[p] then return end
	applying[p] = true
	if waitData(p) then
		local list
		pcall(function()
			pendStore:UpdateAsync(tostring(p.UserId), function(old)
				list = old
				return {} -- taken: never applied twice
			end)
		end)
		for _, a in type(list) == "table" and list or {} do
			local what = apply(p, a)
			if what then notify(p, ("%s %s"):format(a.By or "An admin", a.Kind == "Reset" and "reset your stats" or (a.Kind == "SetCoins" and ("set your " .. what) or ("gave you " .. what)))) end
		end
	end
	applying[p] = nil
end
Players.PlayerAdded:Connect(function(p) task.spawn(applyPending, p) task.spawn(function() if waitData(p) then refreshPasses(p) end end) end)
for _, p in Players:GetPlayers() do task.spawn(applyPending, p) task.spawn(function() if waitData(p) then refreshPasses(p) end end) end
pcall(function()
	MS:SubscribeAsync("AdminApply", function(msg)
		local p = Players:GetPlayerByUserId(tonumber(msg.Data) or 0)
		if p then applyPending(p) end
	end)
	MS:SubscribeAsync("AdminKick", function(msg)
		local data = type(msg.Data) == "table" and msg.Data or {}
		local p = Players:GetPlayerByUserId(tonumber(data.UserId) or 0)
		if p then p:Kick(data.Reason or "Kicked by an admin") end
	end)
end)

------------------------------------------------------------ FINDING THE PLAYER
-- in this server: exact username / display name first, then the start of one. Otherwise any Roblox username.
local function resolve(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
	if name == "" then return nil, "Type a player name" end
	local low = name:lower()
	for _, p in Players:GetPlayers() do
		if p.Name:lower() == low or p.DisplayName:lower() == low then return {player = p, userId = p.UserId, name = p.Name} end
	end
	for _, p in Players:GetPlayers() do
		if p.Name:lower():sub(1, #low) == low or p.DisplayName:lower():sub(1, #low) == low then return {player = p, userId = p.UserId, name = p.Name} end
	end
	local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
	if not ok or not id then return nil, "No player called " .. name end
	local ok2, real = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
	return {player = nil, userId = id, name = ok2 and real or name}
end
local function parseDuration(s)
	s = (s or ""):lower():gsub("%s", "")
	local n, unit = s:match("^(%d+%.?%d*)([mhd]?)$")
	n = tonumber(n)
	if not n or n <= 0 then return nil end
	local mult = ({m = 60, h = 3600, d = 86400})[unit] or 3600 -- a plain number = hours
	return math.floor(n * mult)
end
local function niceTime(sec)
	if sec >= 86400 then return ("%gd"):format(math.floor(sec / 8640 + 0.5) / 10) end
	if sec >= 3600 then return ("%gh"):format(math.floor(sec / 360 + 0.5) / 10) end
	return math.ceil(sec / 60) .. "m"
end

------------------------------------------------------------ COMMANDS
-- a "give" to a player: here = now, anywhere else = saved and applied when they're in a server
local function give(admin, t, a, verb)
	a.By = admin.Name
	if t.player and t.player.Parent == Players then
		local what = apply(t.player, a)
		if not what then return false, "Their data isn't loaded yet - try again" end
		if t.player ~= admin then notify(t.player, ("%s %s"):format(admin.Name, verb(what, true))) end
		addLog(admin, ("%s %s"):format(admin.Name, verb(what, false, t.name)))
		return true, ("Done: %s"):format(verb(what, false, t.name))
	end
	if not addPending(t.userId, a) then return false, "Couldn't save that (DataStores off?)" end
	addLog(admin, ("%s %s (offline)"):format(admin.Name, verb(a.Desc or "it", false, t.name)))
	return true, t.name .. " isn't here - they'll get it as soon as they're in a server"
end

local commands = {}
function commands.GiveCoins(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local n = math.floor(tonumber(args.Amount) or 0)
	if n < 1 or n > (Config.MaxCoins or 1e8) then return false, "Type an amount (1 - " .. (Config.MaxCoins or 1e8) .. ")" end
	return give(admin, t, {Kind = "Coins", Amount = n, Desc = n .. " coins"}, function(what, you, name) return you and ("gave you " .. what) or ("gave " .. name .. " " .. what) end)
end
function commands.SetCoins(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local n = math.floor(tonumber(args.Amount) or -1)
	if n < 0 or n > (Config.MaxCoins or 1e8) then return false, "Type an amount (0 - " .. (Config.MaxCoins or 1e8) .. ")" end
	return give(admin, t, {Kind = "SetCoins", Amount = n, Desc = "coins set to " .. n}, function(what, you, name) return you and ("set your " .. what) or ("set " .. name .. "'s " .. what) end)
end
function commands.GiftPass(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	if #(ShopConfig.Passes or {}) == 0 then return false, "No passes set up yet (ShopConfig > Passes)" end
	local ps = findPass(args.Pass)
	if not ps then return false, "No pass called \"" .. tostring(args.Pass or "") .. "\" (ShopConfig > Passes)" end
	return give(admin, t, {Kind = "Pass", Pass = ps.Name, Desc = "the " .. ps.Name .. " pass"}, function(what, you, name) return you and ("gifted you " .. what) or ("gifted " .. name .. " " .. what) end)
end
function commands.GiveBalloon(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local id = args.Id
	if type(id) ~= "string" or not Skins.ById[id] or id == Skins.DefaultId then return false, "Select a balloon first" end
	local n = math.clamp(math.floor(tonumber(args.Amount) or 1), 1, 100)
	return give(admin, t, {Kind = "Balloon", Id = id, Amount = n, Desc = n .. "x " .. Skins.Get(id).Name}, function(what, you, name) return you and ("gave you " .. what) or ("gave " .. name .. " " .. what) end)
end
function commands.GiveEverything(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	return give(admin, t, {Kind = "Everything", Desc = "every balloon and pass"}, function(what, you, name) return you and ("gave you " .. what) or ("gave " .. name .. " " .. what) end)
end
function commands.ResetStats(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	return give(admin, t, {Kind = "Reset", Desc = "a stats reset"}, function(_, you, name) return you and "reset your stats" or ("reset " .. name .. "'s stats") end)
end
function commands.Kick(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	if t.userId == admin.UserId then return false, "You can't kick yourself" end
	local reason = (args.Reason or "") ~= "" and args.Reason or "Kicked by an admin"
	if t.player and t.player.Parent == Players then
		t.player:Kick(reason)
	else
		pcall(function() MS:PublishAsync("AdminKick", {UserId = t.userId, Reason = reason}) end)
	end
	addLog(admin, ("%s kicked %s (%s)"):format(admin.Name, t.name, reason))
	return true, "Kicked " .. t.name
end
local function ban(admin, t, seconds, reason)
	if t.userId == admin.UserId then return false, "You can't ban yourself" end
	local ok, e = pcall(function()
		Players:BanAsync({UserIds = {t.userId}, ApplyToUniverse = true, Duration = seconds or -1,
			DisplayReason = reason, PrivateReason = ("by %s: %s"):format(admin.Name, reason)})
	end)
	if not ok then return false, "Ban failed: " .. tostring(e) end
	return true
end
function commands.Ban(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local reason = (args.Reason or "") ~= "" and args.Reason or "Banned"
	local ok, e = ban(admin, t, -1, reason)
	if not ok then return false, e end
	addLog(admin, ("%s banned %s forever (%s)"):format(admin.Name, t.name, reason))
	return true, "Banned " .. t.name
end
function commands.TempBan(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local sec = parseDuration(args.Duration)
	if not sec then return false, "Type a time: 30m / 12h / 7d" end
	local ok, e = ban(admin, t, sec, "Banned for " .. niceTime(sec))
	if not ok then return false, e end
	addLog(admin, ("%s banned %s for %s"):format(admin.Name, t.name, niceTime(sec)))
	return true, ("Banned %s for %s"):format(t.name, niceTime(sec))
end
function commands.Unban(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	local ok, e = pcall(function() Players:UnbanAsync({UserIds = {t.userId}, ApplyToUniverse = true}) end)
	if not ok then return false, "Unban failed: " .. tostring(e) end
	addLog(admin, ("%s unbanned %s"):format(admin.Name, t.name))
	return true, "Unbanned " .. t.name
end
function commands.Join(admin, args)
	local t, err = resolve(args.Target) if not t then return false, err end
	if t.userId == admin.UserId then return false, "That's you" end
	if t.player and t.player.Parent == Players then
		local mine = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
		local theirs = t.player.Character and t.player.Character:FindFirstChild("HumanoidRootPart")
		if not (mine and theirs) then return false, "No character to go to" end
		admin.Character:PivotTo(theirs.CFrame * CFrame.new(0, 0, 4))
		addLog(admin, ("%s went to %s"):format(admin.Name, t.name))
		return true, "Teleported to " .. t.name
	end
	local ok, _, e, placeId, jobId = pcall(function() return TeleportService:GetPlayerPlaceInstanceAsync(t.userId) end)
	if not ok or not jobId or jobId == "" then return false, t.name .. " isn't in a server of this game right now" end
	local opts = Instance.new("TeleportOptions")
	opts.ServerInstanceId = jobId
	local ok2, e2 = pcall(function() TeleportService:TeleportAsync(placeId, {admin}, opts) end)
	if not ok2 then return false, "Teleport failed: " .. tostring(e2) end
	addLog(admin, ("%s joined %s's server"):format(admin.Name, t.name))
	return true, "Joining " .. t.name .. "..."
end

local last = {}
Remote.OnServerInvoke = function(p, cmd, args)
	if not isAdmin(p) then return false, "Not an admin" end
	if cmd == "Logs" then return true, getLogs() end
	local fn = type(cmd) == "string" and commands[cmd]
	if not fn then return false, "Unknown command" end
	if last[p] and os.clock() - last[p] < 0.5 then return false, "Slow down" end
	last[p] = os.clock()
	local ok, res, msg = pcall(fn, p, type(args) == "table" and args or {})
	if not ok then warn("[AdminServer] " .. tostring(res)) return false, "Something went wrong" end
	if res then notify(p, msg) end
	return res, msg
end
Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
