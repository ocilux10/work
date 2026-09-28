-- CRATES (server): opening chests. Settings: ReplicatedStorage > Crates > CrateConfig
-- Coin chests: the client asks Crates > Remote ("Open", crateId) -> coins taken, balloon rolled + given, result returned.
-- Robux chests: bought through ShopServer's ProcessReceipt, which calls script.Give (receiver, crateId, gifter).
-- The balloon is given BEFORE the spin plays (the spin is only for show), so leaving mid-spin loses nothing.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local folder = RS:WaitForChild("Crates")
local Config = require(folder:WaitForChild("CrateConfig"))
local Remote = folder:WaitForChild("Remote")
local Opened = folder:WaitForChild("Opened") -- server -> client: play the spin for a Robux / gifted chest
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

-- roll + give one balloon from this chest
local function give(p, crate)
	local id = roll(crate)
	if not id then warn("[CrateServer] " .. crate.Id .. " has no valid Contents") return nil end
	if not Grant:Invoke(p, id, 1) then return nil end
	return id
end

local busy = {}
-- GIFT WITH COINS: ("GiftCoins", crateId, targetPlayer) -> the buyer pays, the target gets the balloon + sees the spin
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
	local id = give(target, crate)
	if not id then PlayerData.AddCoins(p, price) return false, "Something went wrong, coins refunded" end
	Opened:FireClient(target, {Crate = crate.Id, Id = id, From = p.DisplayName})
	return true, ("You gifted a %s to %s!"):format(crate.Name, target.DisplayName)
end

Remote.OnServerInvoke = function(p, action, crateId, target)
	if action == "GiftCoins" then
		if busy[p] then return false, "Slow down" end
		busy[p] = true
		local ok, res, why = pcall(giftCoins, p, crateId, target)
		task.delay(0.5, function() busy[p] = nil end)
		if not ok then warn("[CrateServer] " .. tostring(res)) return false, "Something went wrong" end
		return res, why
	end
	if action ~= "Open" then return false end
	if busy[p] then return false, "Slow down" end
	busy[p] = true
	local ok, res, why = pcall(function()
		local crate = type(crateId) == "string" and Config.ById[crateId]
		if not crate or Config.State(crate) ~= "open" then return false, "This chest isn't in the shop" end
		if p:GetAttribute("InArena") or p:GetAttribute("MatchId") ~= nil then return false, "You can't open chests in a match" end
		local price = crate.Price and crate.Price.Coins
		if not price then return false, "This chest is bought with Robux" end
		local d = PlayerData.Get(p)
		if not d then return false, "Still loading" end
		if (d.Coins or 0) < price then return false, Config.NotEnoughCoinsText or "Not enough coins!" end
		PlayerData.AddCoins(p, -price)
		local id = give(p, crate)
		if not id then PlayerData.AddCoins(p, price) return false, "Something went wrong, coins refunded" end
		return true, id
	end)
	task.delay(0.5, function() busy[p] = nil end)
	if not ok then warn("[CrateServer] " .. tostring(res)) return false, "Something went wrong" end
	return res, why
end

-- ShopServer (Robux purchase / gift): give(receiver, crateId, gifter?) -> balloon id or nil
local bf = script:FindFirstChild("Give") or Instance.new("BindableFunction")
bf.Name = "Give"
bf.OnInvoke = function(p, crateId, gifter)
	local crate = Config.ById[crateId]
	if not crate then return nil end
	local id = give(p, crate)
	if id then Opened:FireClient(p, {Crate = crate.Id, Id = id, From = gifter and gifter.DisplayName or nil}) end
	return id
end
bf.Parent = script

Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
