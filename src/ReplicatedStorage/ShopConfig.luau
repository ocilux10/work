-- SHOP SETTINGS (Main > ShopFrame)
-- COIN PACKS: one line per pack, in the order they sit in the shop (top-left first, left to right, then down).
--   Coins     = coins the buyer gets
--   Robux     = the price shown on the button (keep it the SAME as the product's price on the website)
--   ProductId = the Developer Product's ID. Make them at: Creator Hub > your game > Monetization > Developer Products
--               (0 = not set up yet: the button says "SOON" and does nothing)
--   Name      = optional, only used in messages
--   Value     = the "+10% VALUE" badge on the pack (a number = the %, 0 or nil = badge hidden). Text: ValueText below
local ShopConfig = {}

ShopConfig.CoinPacks = {
	{Coins = 500,    Robux = 19,   ProductId = 3714772721, Value = 0},
	{Coins = 1499,   Robux = 49,   ProductId = 3714772753, Value = 15},
	{Coins = 4999,   Robux = 149,  ProductId = 3714772779, Value = 30},
	{Coins = 14999,  Robux = 399,  ProductId = 3714772803, Value = 45},
	{Coins = 41999,  Robux = 999,  ProductId = 3714772846, Value = 60},
	{Coins = 119999, Robux = 2499, ProductId = 3714772877, Value = 75},
}

-- GIFTING: the Gift button lets you buy a pack for someone else in the server (if their Accept Gifts setting is on)
ShopConfig.GiftingEnabled = true
ShopConfig.GiftWindow = 120 -- seconds a started gift waits for the purchase to finish

ShopConfig.NotSetUpText = "SOON" -- button text for packs without a ProductId
ShopConfig.ValueText = "+{value}% VALUE" -- the value badge on each pack ({value} = the pack's Value)

-- BUYING (any dev product / game pass bought through ReplicatedStorage > Purchase)
ShopConfig.Purchase = {
	-- (the sound when you click to buy = "Purchase" in ReplicatedStorage > SoundConfig)
	-- the loading screen after Roblox's buy window
	ProcessingMaxTime = 1, -- longest "Processing..." shows while the coins arrive (game passes skip it)
	CompleteShowTime = 1,  -- how long "Purchase complete!" stays up
	ShowComplete = true,     -- false = close straight away instead of showing "Purchase complete!"
}

-- GAME PASSES: Name = what admins type in "Gift Gamepass" (and what scripts check), Id = the game pass id on Roblox
-- (0 = not made yet). A player owns a pass if they bought it on Roblox OR an admin gifted it. Scripts check with the
-- player attribute  player:GetAttribute("Pass_" .. Name) == true  (set by ServerScriptService > AdminServer).
ShopConfig.Passes = {
	-- {Name = "VIP", Id = 0},
	-- {Name = "2x Coins", Id = 0},
}

return ShopConfig
