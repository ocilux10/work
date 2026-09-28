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

-- GAME PASSES (shop: Main > ShopFrame > PASSES - one card per line, in order; unused cards are hidden)
--   Name   what admins type in "Gift Gamepass" (and what scripts check) + the big text on the card
--   Id     the game pass id on Roblox (0 = not made yet: the button says SOON). Make them at: Creator Hub > your game >
--          Monetization > Passes
--   Robux  the price shown on the button (keep it the SAME as on Roblox)
--   Perks  the perks text on the card        Image = the picture ("" = keep the one in Studio)
--   Badge  the little badge text ("20% OFF", "BEST VALUE"...; "" = hidden)      Tag = the tag at the top ("PASSES")
--   GiftProductId  Roblox can't gift game passes, so gifting uses a Developer Product with the same price: make one and
--          put its id here (0 = no Gift button). The receiver then owns the pass in this game.
-- A player owns a pass if they bought it on Roblox OR it was gifted OR an admin gave it. Scripts check with
--   player:GetAttribute("Pass_" .. Name) == true
ShopConfig.Passes = {
	{Name = "VIP", Id = 0, Robux = 249, GiftProductId = 0, Tag = "PASSES", Badge = "20% OFF", Image = "",
		Perks = "Perks: VIP Head Tag • VIP Chat Tag • Exclusive VIP Balloon"},
	-- {Name = "2x Coins", Id = 0, Robux = 199, GiftProductId = 0, Tag = "PASSES", Badge = "", Image = "", Perks = "Perks: Double coins from matches"},
}
ShopConfig.OwnedText = "OWNED" -- the Buy button on a pass you have

-- EXCLUSIVES (shop: Main > ShopFrame > EXCLUSIVES - one card per line, in order; unused cards are hidden)
-- A limited balloon sold for Robux. It leaves the shop at End by itself.
--   Balloon    the balloon's Id (BalloonSkins > SkinConfig)       Robux = the price shown
--   ProductId  a Developer Product for it (0 = not made yet: SOON). Gifting uses the same product.
--   Start / End  UTC "YYYY-MM-DD HH:MM" (nil = always). The card shows the time left until End.
--   Tag        the tag at the top of the card
ShopConfig.Exclusives = {
	{Balloon = "RainbowPrism", Robux = 399, ProductId = 0, Start = nil, End = "2026-10-31 23:59", Tag = "EXCLUSIVE"},
	{Balloon = "Celestial",    Robux = 599, ProductId = 0, Start = nil, End = "2026-10-31 23:59", Tag = "EXCLUSIVE"},
}
ShopConfig.ExclusiveTypeText = "{rarity} {type}" -- the small line under the balloon's name ("Exclusive Balloon")
ShopConfig.OwnedExclusiveText = nil                -- e.g. "OWNED" to stop people buying one they have (nil = can buy more)

-- is an Exclusive in the shop right now? (Start / End)
function ShopConfig.ExclusiveActive(e, now)
	local Crates = require(script.Parent:WaitForChild("Crates"):WaitForChild("CrateConfig"))
	now = now or os.time()
	local s, en = Crates.ParseTime(e.Start), Crates.ParseTime(e.End)
	if s and now < s then return false end
	if en and now >= en then return false end
	return true
end

return ShopConfig
