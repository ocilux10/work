-- BALLOON SKINS (server): what you own, equipping, locking, deleting, how many exist.
-- Balloons + rarities + testers: ReplicatedStorage > BalloonSkins > SkinConfig.
-- The player gets attributes: EquippedSkin (Id), BalloonInv (JSON {Id = count}),
-- BalloonGot (JSON {Id = os.time first got}).
-- "X exist" counts: ReplicatedStorage > BalloonSkins attributes Exist_<Id> (the whole game, refreshed every minute).
-- Other scripts (admin commands later):  script.Grant:Invoke(player, id, count)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local folder = RS:WaitForChild("BalloonSkins")
local Skins = require(folder:WaitForChild("SkinConfig"))

local Remote = folder:FindFirstChild("Remote") or Instance.new("RemoteFunction")
Remote.Name = "Remote"
Remote.Parent = folder

------------------------------------------------------------ HOW MANY EXIST (whole game)
local existStore
pcall(function() existStore = DataStoreService:GetDataStore("BalloonExist_v1") end)
local pending = {} -- [id] = change not written yet
local localCount = {} -- (Studio without API access: counted in this server only)
local function changeExist(id, n)
	pending[id] = (pending[id] or 0) + n
	localCount[id] = (localCount[id] or 0) + n
	folder:SetAttribute("Exist_" .. id, math.max((folder:GetAttribute("Exist_" .. id) or 0) + n, 0))
end
task.spawn(function()
	while true do
		for _, s in Skins.Skins do
			local id = s.Id
			local n = pending[id]
			pending[id] = nil
			if existStore then
				local ok, value = pcall(function()
					if n and n ~= 0 then
						return existStore:IncrementAsync(id, n)
					end
					return existStore:GetAsync(id)
				end)
				if ok and type(value) == "number" then folder:SetAttribute("Exist_" .. id, math.max(value, 0)) end
			end
			task.wait(0.2)
		end
		task.wait(60)
	end
end)

------------------------------------------------------------ INVENTORY
local function data(p) return PlayerData.Get(p) end
local function publish(p)
	local d = data(p)
	if not d then return end
	local inv, got = {}, {}
	for id, e in d.Balloons or {} do
		if Skins.ById[id] and (e.Count or 0) > 0 then inv[id] = e.Count got[id] = e.Got or 0 end
	end
	inv[Skins.DefaultId] = math.max(inv[Skins.DefaultId] or 0, 1)
	p:SetAttribute("BalloonInv", HttpService:JSONEncode(inv))
	p:SetAttribute("BalloonGot", HttpService:JSONEncode(got))
	d.LockedBalloons = nil
	local eq = d.EquippedSkin
	if not Skins.ById[eq] or (eq ~= Skins.DefaultId and not inv[eq]) then eq = Skins.DefaultId d.EquippedSkin = eq end
	p:SetAttribute("EquippedSkin", eq)
end
local function count(p, id)
	if id == Skins.DefaultId then return 1 end
	local d = data(p)
	local e = d and d.Balloons and d.Balloons[id]
	return e and e.Count or 0
end

local SkinServer = {}
function SkinServer.Grant(p, id, n)
	local d = data(p)
	if not d or not Skins.ById[id] or id == Skins.DefaultId then return false end
	n = math.max(math.floor(n or 1), 1)
	d.Balloons = d.Balloons or {}
	local e = d.Balloons[id] or {Count = 0, Got = os.time()}
	e.Count += n
	d.Balloons[id] = e
	changeExist(id, n)
	publish(p)
	return true
end
local function removeOne(p, id)
	local d = data(p)
	if not d or id == Skins.DefaultId then return false end
	local e = d.Balloons and d.Balloons[id]
	if not e or e.Count <= 0 then return false end
	e.Count -= 1
	if e.Count <= 0 then d.Balloons[id] = nil end
	changeExist(id, -1)
	return true
end

-- testers get every balloon once
local function giveTester(p)
	local isTester = false
	for _, n in Skins.Testers do if n:lower() == p.Name:lower() then isTester = true end end
	if not isTester then return end
	local d = data(p)
	d.TesterGranted = d.TesterGranted or {}
	for _, s in Skins.Skins do
		if s.Id ~= Skins.DefaultId and not d.TesterGranted[s.Id] then
			d.TesterGranted[s.Id] = true
			SkinServer.Grant(p, s.Id, table.find(Skins.TesterDoubles, s.Id) and 2 or 1)
		end
	end
end

local function onPlayer(p)
	-- wait for the data to load
	local t0 = os.clock()
	while p.Parent == Players and not data(p) and os.clock() - t0 < 30 do task.wait(0.25) end
	if not data(p) then return end
	giveTester(p)
	publish(p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end

------------------------------------------------------------ REQUESTS FROM THE BALLOONS MENU
local busy = {}
Remote.OnServerInvoke = function(p, action, arg, arg2)
	if busy[p] then return false, "Slow down" end
	busy[p] = true
	local ok, res, why = pcall(function()
		local d = data(p)
		if not d then return false, "Still loading" end
		if action == "Equip" then
			if type(arg) ~= "string" or not Skins.ById[arg] or count(p, arg) <= 0 then return false, "You don't have that balloon" end
			d.EquippedSkin = arg
			publish(p)
			return true
		elseif action == "Delete" then
			-- arg = {Id, Id, ...}: one of each is deleted
			if type(arg) ~= "table" then return false end
			local n = 0
			for _, id in arg do
				if type(id) == "string" and removeOne(p, id) then n += 1 end
			end
			publish(p)
			return n > 0, n
		end
		return false
	end)
	busy[p] = nil
	if not ok then warn("[SkinServer] " .. tostring(res)) return false, "Something went wrong" end
	return res, why
end

------------------------------------------------------------ TRADING (ServerScriptService > TradeServer)
-- items = {[Id] = count}. Has(p, items) -> can they give these?  Transfer(a, itemsA, b, itemsB) -> swaps both at once.
-- (the Default balloon can't be traded; trading away your equipped one switches you to Default)
local function validItems(items)
	if type(items) ~= "table" then return false end
	for id, n in items do
		if type(id) ~= "string" or not Skins.ById[id] or id == Skins.DefaultId then return false end
		if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
	end
	return true
end
function SkinServer.Has(p, items)
	if not data(p) or not validItems(items) then return false end
	for id, n in items do if count(p, id) < n then return false end end
	return true
end
local function move(from, to, items)
	local df, dt = data(from), data(to)
	for id, n in items do
		local e = df.Balloons[id]
		e.Count -= n
		if e.Count <= 0 then df.Balloons[id] = nil end
		dt.Balloons = dt.Balloons or {}
		local r = dt.Balloons[id] or {Count = 0, Got = os.time()}
		r.Count += n
		dt.Balloons[id] = r
	end
end
function SkinServer.Transfer(a, itemsA, b, itemsB)
	-- everything is checked first, so it either all happens or nothing does
	if a == b or not SkinServer.Has(a, itemsA) or not SkinServer.Has(b, itemsB) then return false end
	move(a, b, itemsA)
	move(b, a, itemsB)
	publish(a)
	publish(b)
	return true
end
-- admin tools (ServerScriptService > AdminServer): Refresh = re-send a player's balloons after their data was changed
function SkinServer.Refresh(p) publish(p) return true end
for name, fn in {Has = SkinServer.Has, Transfer = SkinServer.Transfer, Refresh = SkinServer.Refresh} do
	local bf = script:FindFirstChild(name) or Instance.new("BindableFunction")
	bf.Name = name
	bf.OnInvoke = fn
	bf.Parent = script
end

local grant = script:FindFirstChild("Grant") or Instance.new("BindableFunction")
grant.Name = "Grant"
grant.OnInvoke = SkinServer.Grant
grant.Parent = script
