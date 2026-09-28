-- CRATES (server): owning + opening chests. Settings: ReplicatedStorage > Crates > CrateConfig
-- Chests are OWNED first, then opened: PlayerData.Crates = {[crateId] = how many}, also on the player as the attribute
-- "CrateInv" (JSON) for the UI ("Owned (3)").
-- Crates > Remote:
--   ("Buy", crateId)                 pay the coin price -> +1 owned            -> true, owned now
--   ("Open", crateId)                open 1 owned -> balloon rolled + given     -> true, balloonId
--   ("OpenAll", crateId)             open every owned one (up to MaxOpenAll)    -> true, {balloonId, ...}
--   ("GiftCoins", crateId, player)   pay the coin price -> +1 owned for them   -> true, message
-- Robux purchases, gifts, daily / leaderboard rewards: script.Give(player, crateId, gifter?) -> +1 owned
-- (Crates > Opened tells their screen: {Stored = true, Crate, From}).
-- A balloon is given BEFORE its spin plays (the spin is only for show), so leaving mid-spin loses nothing.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local folder = RS:WaitForChild("Crates")
local Config = require(folder:WaitForChild("CrateConfig"))
local Remote = folder:WaitForChild("Remote")
local Opened = folder:WaitForChild("Opened") -- server -> client: a chest arrived in your inventory
local Grant = SSS:WaitForChild("SkinServer"):WaitForChild("Grant")

local rng = Random.new()
local function roll(crate)
	local odds, total = Config.Odds(crate)
	if #odds == 0 then return nil end
	local r = rng:NextNumber() * total
	for _, e in odds do
		r -= e.Chance
		if r <= 0 then return e.Id end
	end
	return odds[#odds].Id
end

------------------------------------------------------------ OWNED CHESTS
local function inv(d)
	d.Crates = type(d.Crates) == "table" and d.Crates or {}
	return d.Crates
end
local function publish(p)
	local d = PlayerData.Get(p)
	if d then p:SetAttribute("CrateInv", HttpService:JSONEncode(inv(d))) end
end
local function addOwned(p, crateId, n)
	local d = PlayerData.Get(p)
	if not d then return false end
	local c = inv(d)
	c[crateId] = math.max(0, (c[crateId] or 0) + n)
	if c[crateId] == 0 then c[crateId] = nil end
	publish(p)
	return true
end
local function owned(p, crateId)
	local d = PlayerData.Get(p)
	return d and inv(d)[crateId] or 0
end

------------------------------------------------------------ ACTIONS
local function buy(p, crateId)
	local crate = type(crateId) == "string" and Config.ById[crateId]
	if not crate or Config.State(crate) ~= "open" then return false, "This chest isn't in the shop" end
	local price = crate.Price and crate.Price.Coins
	if not price then return false, "This chest is bought with Robux" end
	local d = PlayerData.Get(p)
	if not d then return false, "Still loading" end
	if (d.Coins or 0) < price then return false, Config.NotEnoughCoinsText or "Not enough coins!" end
	PlayerData.AddCoins(p, -price)
	addOwned(p, crate.Id, 1)
	return true, owned(p, crate.Id)
end

-- open `n` owned chests -> list of balloon ids
local function open(p, crateId, n)
	local crate = type(crateId) == "string" and Config.ById[crateId]
	if not crate then return false, "Unknown chest" end
	if p:GetAttribute("InArena") or p:GetAttribute("MatchId") ~= nil then return false, "You can't open chests in a match" end
	local have = owned(p, crate.Id)
	if have < 1 then return false, "You don't have one - buy it first" end
	n = math.min(n, have)
	-- (taken first, then rolled: never more balloons than chests)
	addOwned(p, crate.Id, -n)
	local got = {}
	for _ = 1, n do
		local id = roll(crate)
		if id and Grant:Invoke(p, id, 1) then
			table.insert(got, id)
		else
			addOwned(p, crate.Id, 1) -- (put back if it couldn't be given)
		end
	end
	if #got == 0 then return false, "Something went wrong" end
	return true, got
end

local function giftCoins(p, crateId, target)
	local crate = type(crateId) == "string" and Config.ById[crateId]
	if not crate or Config.State(crate) ~= "open" then return false, "This chest isn't in the shop" end
	local price = crate.Price and crate.Price.Coins
	if not price then return false, "This chest can only be gifted with Robux" end
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players or target == p then return false, "Pick someone else" end
	if target:GetAttribute("Pref_AcceptGifts") == false then return false, target.DisplayName .. " isn't accepting gifts" end
	local d = PlayerData.Get(p)
	if not d or not PlayerData.Get(target) then return false, "Still loading" end
	if (d.Coins or 0) < price then return false, Config.NotEnoughCoinsText or "Not enough coins!" end
	PlayerData.AddCoins(p, -price)
	addOwned(target, crate.Id, 1)
	Opened:FireClient(target, {Stored = true, Crate = crate.Id, From = p.DisplayName})
	return true, ("You gifted a %s to %s!"):format(crate.Name, target.DisplayName)
end

local busy = {}
Remote.OnServerInvoke = function(p, action, crateId, target)
	if busy[p] then return false, "Slow down" end
	busy[p] = true
	local ok, res, why = pcall(function()
		if action == "Buy" then return buy(p, crateId) end
		if action == "Open" then
			local okOpen, got = open(p, crateId, 1)
			if not okOpen then return false, got end
			return true, got[1]
		end
		if action == "OpenAll" then return open(p, crateId, Config.MaxOpenAll or 100) end
		if action == "GiftCoins" then return giftCoins(p, crateId, target) end
		return false, "Unknown action"
	end)
	task.delay(0.35, function() busy[p] = nil end)
	if not ok then warn("[CrateServer] " .. tostring(res)) return false, "Something went wrong" end
	return res, why
end

-- ShopServer (Robux purchase / gift) + GiveReward (daily / leaderboard): +1 owned. -> crateId, or nil if it failed
local bf = script:FindFirstChild("Give") or Instance.new("BindableFunction")
bf.Name = "Give"
bf.OnInvoke = function(p, crateId, gifter)
	local crate = Config.ById[crateId]
	if not crate or not addOwned(p, crate.Id, 1) then return nil end
	Opened:FireClient(p, {Stored = true, Crate = crate.Id, From = gifter and gifter.DisplayName or nil})
	return crate.Id
end
bf.Parent = script

local function onPlayer(p)
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 60 do task.wait(0.5) end
	publish(p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, pl in Players:GetPlayers() do task.spawn(onPlayer, pl) end
Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
