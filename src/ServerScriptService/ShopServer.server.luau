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
-- EXCLUSIVES (Robux balloons) and pass GIFTS (a dev product that gives a game pass) - ShopConfig
-- -> the Exclusive, its index, how many copies that product gives
local function exclusiveFor(productId)
	for i, e in ShopConfig.Exclusives or {} do
		for _, a in ShopConfig.ExclusiveAmounts(e) do
			if (a.ProductId or 0) ~= 0 and a.ProductId == productId then return e, i, a.Amount or 1 end
		end
	end
end
local function passGiftFor(productId)
	for _, ps in ShopConfig.Passes or {} do
		if (ps.GiftProductId or 0) ~= 0 and ps.GiftProductId == productId then return ps end
	end
end
local function givePass(p, ps)
	local d = PlayerData.Get(p)
	if not d then return false end
	d.Passes = d.Passes or {}
	d.Passes[ps.Name] = true
	p:SetAttribute("Pass_" .. ps.Name, true)
	return true
end
-- bought on Roblox while in the game: owned straight away
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, passId, bought)
	if not bought then return end
	for _, ps in ShopConfig.Passes or {} do
		if (ps.Id or 0) ~= 0 and ps.Id == passId then p:SetAttribute("Pass_" .. ps.Name, true) end
	end
end)
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
		elseif type(data) == "table" and type(data.Crate) == "string" then
			-- (the same gift list is used for "Exclusive:<n>" balloons and "Pass:<name>" passes)
			local n, amountIndex = data.Crate:match("^Exclusive:(%d+):?(%d*)$")
			n, amountIndex = tonumber(n or ""), tonumber(amountIndex or "") or 1
			local passName = data.Crate:match("^Pass:(.+)$")
			if n then
				local e = (ShopConfig.Exclusives or {})[n]
				local a = e and ShopConfig.ExclusiveAmounts(e)[amountIndex]
				if not e or not a or not ShopConfig.ExclusiveActive(e) or (a.ProductId or 0) == 0 then return false, "That balloon isn't available" end
				pack = {ProductId = a.ProductId}
			elseif passName then
				for _, ps in ShopConfig.Passes or {} do
					if ps.Name == passName and (ps.GiftProductId or 0) ~= 0 then pack = {ProductId = ps.GiftProductId} end
				end
				if not pack then return false, "That pass can't be gifted" end
				if typeof(target) == "Instance" and target:IsA("Player") and target:GetAttribute("Pass_" .. passName) then
					return false, target.DisplayName .. " already has " .. passName
				end
			end
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
	local exclusive, _, exAmount = nil, nil, 1
	if not pack and not crate then exclusive, _, exAmount = exclusiveFor(info.ProductId) end
	local passGift = not pack and not crate and not exclusive and passGiftFor(info.ProductId)
	if not pack and not crate and not exclusive and not passGift then
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

	if exclusive or passGift then
		-- an Exclusive balloon / a gifted game pass
		local what
		if exclusive then
			local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
			local grant = game:GetService("ServerScriptService"):WaitForChild("SkinServer"):WaitForChild("Grant")
			if not grant:Invoke(receiver, exclusive.Balloon, exAmount) then return Enum.ProductPurchaseDecision.NotProcessedYet end
			what = (exAmount > 1 and (exAmount .. "x ") or "") .. Skins.Get(exclusive.Balloon).Name
		else
			if not givePass(receiver, passGift) then return Enum.ProductPurchaseDecision.NotProcessedYet end
			what = "the " .. passGift.Name .. " pass"
		end
		table.insert(data.Receipts, info.PurchaseId)
		while #data.Receipts > 50 do table.remove(data.Receipts, 1) end
		if receiver == buyer then
			notice(buyer, ("You got %s! Thanks for your support"):format(what))
		else
			notice(buyer, ("You gifted %s to %s!"):format(what, receiver.DisplayName))
			notice(receiver, ("%s gifted you %s!"):format(buyer.DisplayName, what))
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

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
