-- SHOP (server): Robux coin packs + gifting them. Settings: ReplicatedStorage > ShopConfig
-- Purchases go through MarketplaceService.ProcessReceipt (the ONLY place this game should set it).
-- A purchase is only ever given once (receipt ids are saved in the buyer's data).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local ShopConfig = require(RS:WaitForChild("ShopConfig"))
local CrateConfig = require(RS:WaitForChild("Crates"):WaitForChild("CrateConfig")) -- Robux chests (ServerScriptService > CrateServer)
local Remotes = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes")
local ShopRemote = Remotes:WaitForChild("Shop")
local DuelRemote = Remotes:WaitForChild("Duel") -- short messages (Main > DuelNotice)

local function notice(p, text)
	if p and p.Parent == Players then DuelRemote:FireClient(p, {Kind = "Notice", Text = text}) end
end
local function packFor(productId)
	for i, pack in ShopConfig.CoinPacks do
		if pack.ProductId ~= 0 and pack.ProductId == productId then return pack, i end
	end
end
local function fmt(n) return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end

local pendingGift = {} -- [buyer] = {target = player, productId, expires}

-- client asks before opening a gift purchase: is this person allowed to get it?
ShopRemote.OnServerInvoke = function(p, action, data)
	if action == "StartGift" then
		if not ShopConfig.GiftingEnabled then return false, "Gifting is turned off" end
		local target = type(data) == "table" and data.Target
		local pack = type(data) == "table" and ShopConfig.CoinPacks[data.Pack]
		-- (or a Robux chest: data.Crate = its Id)
		local crate = type(data) == "table" and type(data.Crate) == "string" and CrateConfig.ById[data.Crate]
		if crate then
			if CrateConfig.State(crate) ~= "open" or not crate.Price or (crate.Price.ProductId or 0) == 0 then return false, "That chest isn't available" end
			pack = {ProductId = crate.Price.ProductId}
		end
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players or target == p then return false, "Pick someone else" end
		if not pack or pack.ProductId == 0 then return false, "That pack isn't available yet" end
		if target:GetAttribute("Pref_AcceptGifts") == false then return false, target.DisplayName .. " isn't accepting gifts" end
		pendingGift[p] = {target = target, productId = pack.ProductId, expires = os.clock() + (ShopConfig.GiftWindow or 120)}
		return true
	elseif action == "CancelGift" then
		pendingGift[p] = nil
		return true
	end
	return false
end

MarketplaceService.ProcessReceipt = function(info)
	local buyer = Players:GetPlayerByUserId(info.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local data = PlayerData.Get(buyer)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end
	data.Receipts = data.Receipts or {}
	if table.find(data.Receipts, info.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end -- already given

	local pack = packFor(info.ProductId)
	local crate = not pack and CrateConfig.ByProduct(info.ProductId)
	if not pack and not crate then
		warn("[Shop] unknown product " .. tostring(info.ProductId) .. " - add it to ReplicatedStorage > ShopConfig (or Crates > CrateConfig)")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- a gift? (started from the Gift button, same product, not expired, receiver still here and loaded)
	local gift = pendingGift[buyer]
	local receiver = buyer
	if gift and gift.productId == info.ProductId and os.clock() < gift.expires
		and gift.target.Parent == Players and PlayerData.Get(gift.target) then
		receiver = gift.target
	end
	pendingGift[buyer] = nil

	if crate then
		-- a Robux chest: roll + give the balloon (the receiver's screen plays the spin)
		local give = game:GetService("ServerScriptService"):WaitForChild("CrateServer"):WaitForChild("Give")
		local id = give:Invoke(receiver, crate.Id, receiver ~= buyer and buyer or nil)
		if not id then return Enum.ProductPurchaseDecision.NotProcessedYet end
		table.insert(data.Receipts, info.PurchaseId)
		while #data.Receipts > 50 do table.remove(data.Receipts, 1) end
		if receiver ~= buyer then
			notice(buyer, ("You gifted a %s to %s!"):format(crate.Name, receiver.DisplayName))
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	PlayerData.AddCoins(receiver, pack.Coins)
	table.insert(data.Receipts, info.PurchaseId)
	while #data.Receipts > 50 do table.remove(data.Receipts, 1) end

	if receiver == buyer then
		notice(buyer, ("+%s coins! Thanks for your support"):format(fmt(pack.Coins)))
	else
		notice(buyer, ("You gifted %s coins to %s!"):format(fmt(pack.Coins), receiver.DisplayName))
		notice(receiver, ("%s gifted you %s coins!"):format(buyer.DisplayName, fmt(pack.Coins)))
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

Players.PlayerRemoving:Connect(function(p) pendingGift[p] = nil end)
