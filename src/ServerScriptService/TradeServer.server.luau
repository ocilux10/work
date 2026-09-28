-- TRADING (server). Settings + texts: ReplicatedStorage > Trade > TradeConfig. Balloons move with SkinServer.Transfer,
-- coins with PlayerData. Who can send you requests: Settings > Other > Trade Requests (ServerStorage > Privacy).
-- Messages to clients (Trade.Remote): {Kind = "Incoming" / "Open" / "State" / "Closed" / "Notice" / "Done", ...}
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local Config = require(RS:WaitForChild("Trade"):WaitForChild("TradeConfig"))
local Remote = RS.Trade:WaitForChild("Remote")
local PlayerData = require(SS:WaitForChild("PlayerData"))
local Privacy = require(SS:WaitForChild("Privacy"))
local SkinServer = script.Parent:WaitForChild("SkinServer")
local Has, Transfer = SkinServer:WaitForChild("Has"), SkinServer:WaitForChild("Transfer")

local T = Config.Text or {}
local function fmt(t, name, n) return ((t or ""):gsub("{name}", name or ""):gsub("{n}", tostring(n or ""))) end
local function notice(p, text) Remote:FireClient(p, {Kind = "Notice", Text = text}) end

local requests = {} -- [id] = {from, to, at}
local lastAsked = {} -- ["from_to"] = os.clock()
local sessions = {} -- [player] = session  (both players point at the same one)

-- (the lobby, practice arena and aim training are all fine - only a real match / watching one blocks trading)
local function inLobby(p)
	return p.Parent == Players and p:GetAttribute("MatchId") == nil
		and not p:GetAttribute("WatchingReplay") and not p:GetAttribute("WatchingMatch")
end
local function canTrade(p)
	if not PlayerData.Get(p) then return false end
	if (Config.MinLevel or 0) > 0 and PlayerData.GetLevel(p) < Config.MinLevel then return false end
	return true
end

------------------------------------------------------------ SESSION
local function side(s, p) return s.a == p and s.A or s.B end
local function other(s, p) return s.a == p and s.b or s.a end
local function stateFor(s, p)
	local me, them = side(s, p), side(s, other(s, p))
	return {Kind = "State", Id = s.id, Mine = {Items = me.items, Coins = me.coins, Accepted = me.accepted},
		Theirs = {Items = them.items, Coins = them.coins, Accepted = them.accepted},
		EndsAt = s.endsAt, Partner = other(s, p)}
end
local function push(s)
	for _, p in {s.a, s.b} do if p.Parent then Remote:FireClient(p, stateFor(s, p)) end end
end
local function close(s, reason, by)
	if s.closed then return end
	s.closed = true
	sessions[s.a], sessions[s.b] = nil, nil
	for _, p in {s.a, s.b} do
		if p.Parent then
			local who = other(s, p)
			local text = reason == "Done" and T.Done or (by and by ~= p and fmt(T.Cancelled, who.DisplayName)) or nil
			Remote:FireClient(p, {Kind = reason == "Done" and "Done" or "Closed", Id = s.id, Text = text})
		end
	end
end
local function slots(items) local n = 0 for _ in items do n += 1 end return n end
local function unaccept(s)
	s.A.accepted, s.B.accepted = false, false
	s.endsAt = nil
	s.token += 1
end

local function finish(s)
	if s.closed then return end
	local a, b = s.a, s.b
	if not (inLobby(a) and inLobby(b)) then close(s, "Cancelled") return end
	local da, db = PlayerData.Get(a), PlayerData.Get(b)
	if not (da and db) then close(s, "Cancelled") return end
	-- check EVERYTHING again right before swapping
	if (da.Coins or 0) < s.A.coins or (db.Coins or 0) < s.B.coins then
		unaccept(s) push(s) notice(a, "Not enough coins") notice(b, "Not enough coins") return
	end
	local ok = Transfer:Invoke(a, s.A.items, b, s.B.items)
	if not ok then unaccept(s) push(s) notice(a, "Those balloons aren't there anymore") notice(b, "Those balloons aren't there anymore") return end
	if s.A.coins > 0 then PlayerData.AddCoins(a, -s.A.coins) PlayerData.AddCoins(b, s.A.coins) end
	if s.B.coins > 0 then PlayerData.AddCoins(b, -s.B.coins) PlayerData.AddCoins(a, s.B.coins) end
	close(s, "Done")
end

local function open(a, b)
	local s = {id = HttpService:GenerateGUID(false), a = a, b = b, token = 0,
		A = {items = {}, coins = 0, accepted = false}, B = {items = {}, coins = 0, accepted = false}}
	sessions[a], sessions[b] = s, s
	for _, p in {a, b} do
		local o = other(s, p)
		Remote:FireClient(p, {Kind = "Open", Id = s.id, Partner = o})
	end
	push(s)
end

------------------------------------------------------------ REQUESTS FROM CLIENTS
local handlers = {}
function handlers.Request(p, msg)
	local target = msg.Target
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == p or target.Parent ~= Players then return end
	if not (inLobby(p) and canTrade(p)) or sessions[p] then return end
	if not inLobby(target) or not canTrade(target) or sessions[target] then notice(p, fmt(T.Busy, target.DisplayName)) return end
	if not Privacy.Allows(target, p, "TradeRequests") then notice(p, fmt(T.NotAllowed, target.DisplayName)) return end
	local key = p.UserId .. "_" .. target.UserId
	if lastAsked[key] and os.clock() - lastAsked[key] < (Config.RequestCooldown or 10) then return end
	lastAsked[key] = os.clock()
	-- they already asked you: that's a yes
	for id, r in requests do
		if r.from == target and r.to == p then requests[id] = nil open(target, p) return end
	end
	local id = HttpService:GenerateGUID(false)
	requests[id] = {from = p, to = target, at = os.clock()}
	Remote:FireClient(target, {Kind = "Incoming", Id = id, From = p, FromUserId = p.UserId, FromName = p.DisplayName,
		FromVerified = p.HasVerifiedBadge, Timeout = Config.RequestTimeout or 20, Text = fmt(T.Request, p.DisplayName)})
	task.delay(Config.RequestTimeout or 20, function() requests[id] = nil end)
end
function handlers.Respond(p, msg)
	local r = requests[msg.Id]
	if not r or r.to ~= p then return end
	requests[msg.Id] = nil
	local from = r.from
	if msg.Accept ~= true then
		if from.Parent then notice(from, fmt(T.Declined, p.DisplayName)) end
		return
	end
	if from.Parent ~= Players or sessions[from] or sessions[p] or not (inLobby(from) and inLobby(p)) then
		notice(p, fmt(T.Busy, from.DisplayName)) return
	end
	open(from, p)
end
function handlers.Offer(p, msg)
	local s = sessions[p]
	if not s or s.id ~= msg.Id then return end
	local items = type(msg.Items) == "table" and msg.Items or {}
	local clean = {}
	for id, n in items do
		if type(id) == "string" and type(n) == "number" and n >= 1 and n % 1 == 0 then clean[id] = n end
	end
	if slots(clean) > (Config.MaxItems or 12) then return end
	if next(clean) and not Has:Invoke(p, clean) then return end
	local coins = 0
	if Config.AllowCoins ~= false then
		coins = tonumber(msg.Coins) or 0
		coins = math.clamp(math.floor(coins), 0, math.min(Config.MaxCoins or math.huge, (PlayerData.Get(p) or {}).Coins or 0))
	end
	local me = side(s, p)
	me.items, me.coins = clean, coins
	unaccept(s) -- anything changed: both have to accept again
	push(s)
end
function handlers.Accept(p, msg)
	local s = sessions[p]
	if not s or s.id ~= msg.Id then return end
	local me = side(s, p)
	me.accepted = msg.On == true
	if not me.accepted then unaccept(s) push(s) return end
	if s.A.accepted and s.B.accepted then
		-- both ready: countdown (any change calls unaccept, which stops this)
		s.token += 1
		local token = s.token
		s.endsAt = workspace:GetServerTimeNow() + (Config.ConfirmTime or 3)
		task.delay(Config.ConfirmTime or 3, function()
			if s.token == token and not s.closed and s.A.accepted and s.B.accepted then finish(s) end
		end)
	end
	push(s)
end
function handlers.Cancel(p, msg)
	local s = sessions[p]
	if s then close(s, "Cancelled", p) end
end

Remote.OnServerEvent:Connect(function(p, msg)
	if type(msg) ~= "table" then return end
	local h = handlers[msg.Action]
	if h then
		local ok, err = pcall(h, p, msg)
		if not ok then warn("[TradeServer] " .. tostring(err)) end
	end
end)

-- leaving / going into a fight ends the trade
local function watch(p)
	for _, a in {"MatchId", "WatchingReplay", "WatchingMatch"} do
		p:GetAttributeChangedSignal(a):Connect(function()
			local s = sessions[p]
			if s and not inLobby(p) then close(s, "Cancelled", p) end
		end)
	end
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do watch(p) end
Players.PlayerRemoving:Connect(function(p)
	local s = sessions[p]
	if s then close(s, "Cancelled", p) end
	for id, r in requests do if r.from == p or r.to == p then requests[id] = nil end end
end)
