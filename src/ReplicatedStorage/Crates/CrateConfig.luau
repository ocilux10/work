-- CRATES / CHESTS - everything about the chests in the shop (Main > ShopFrame > CRATES). Edit freely.
--   3D models: ReplicatedStorage > Crates > Models (Basic / Premium / Exclusive - recolour or make your own, one Model each)
--   Balloons (names, rarities, colours): ReplicatedStorage > BalloonSkins > SkinConfig
--   Look of the shop card:  Main > ShopFrame > ScrollingFrame > CratesSection1 > Crate (the first one is the template)
--   Look of the contents page: Main > ShopFrame > CrateView       Look of the spin: StarterGui > CrateOpening
--
-- ONE CHEST:
--   Id          unique name, never change it once the game is live
--   Name        shown on the card / contents page
--   Model       which model in Crates > Models to show
--   Tag         the little badge on the card ("CHEST", "NEW", "LIMITED"...). "" = no badge
--   Color       colour of the badge + the line under the card
--   Order       position in the shop (1 = first)
--   ShowInShop  false = hidden from the shop and can't be opened
--   Start / End WHEN it's in the shop, UTC time "YYYY-MM-DD HH:MM" (nil = always). After End it leaves the shop by
--               itself (and can't be bought any more). Before Start it's hidden (or "COMING SOON", see ShowBeforeStart).
--   ShowBeforeStart  true = shows before Start with a "COMING IN ..." timer (can't be opened yet)
--   Price       {Coins = 500}                         -> paid with coins
--               {Robux = 249, ProductId = 123456789}  -> paid with Robux (a Developer Product, like the coin packs;
--                                                        ProductId 0 = not made yet: the button says SOON)
--   Contents    what can come out: {Id = balloon id, Chance = number}. Chances are shares of the total, so they
--               don't HAVE to add up to 100 (the shop shows the real %). Keep them adding to 100 to keep it simple.
local M = {}

M.Crates = {
	{
		Id = "Basic", Name = "Basic Chest", Model = "Basic", Tag = "CHEST", Color = Color3.fromRGB(190, 200, 210), Order = 1,
		ShowInShop = true, Start = nil, End = nil,
		Price = {Coins = 500},
		Contents = {
			{Id = "Honeycomb",  Chance = 55},
			{Id = "CandySwirl", Chance = 20},
			{Id = "Heartbreak", Chance = 20},
			{Id = "Frostbite",  Chance = 3},
			{Id = "Toxic",      Chance = 2},
		},
	},
	{
		Id = "Premium", Name = "Premium Chest", Model = "Premium", Tag = "PREMIUM", Color = Color3.fromRGB(60, 140, 255), Order = 2,
		ShowInShop = true, Start = nil, End = nil,
		Price = {Coins = 1500},
		Contents = {
			{Id = "CandySwirl", Chance = 25},
			{Id = "Heartbreak", Chance = 25},
			{Id = "Frostbite",  Chance = 15},
			{Id = "Toxic",      Chance = 15},
			{Id = "Glitch",     Chance = 12},
			{Id = "Inferno",    Chance = 4},
			{Id = "Thunder",    Chance = 3},
			{Id = "ShadowVoid", Chance = 1},
		},
	},
	{
		Id = "Exclusive", Name = "Exclusive Chest", Model = "Exclusive", Tag = "LIMITED", Color = Color3.fromRGB(255, 180, 40), Order = 3,
		ShowInShop = true, Start = nil, End = "2026-10-31 23:59", -- leaves the shop at the end of October
		Price = {Coins = 5000}, -- Robux instead:  Price = {Robux = 249, ProductId = 0},
		Contents = {
			{Id = "Glitch",     Chance = 30},
			{Id = "Toxic",      Chance = 25},
			{Id = "Inferno",    Chance = 15},
			{Id = "Thunder",    Chance = 13},
			{Id = "ShadowVoid", Chance = 12},
			{Id = "Cosmic",     Chance = 3},
			{Id = "Royal",      Chance = 2},
		},
	},
}

-- TEXTS ({time} = "2d 5h", "3h 12m", "45s"...)
M.LeavingText = "LEAVES IN {time}"   -- on chests that have an End
M.ComingText = "COMING IN {time}"    -- on chests shown before their Start
M.ShowLeavingTimer = true             -- false = no "LEAVES IN" timer on the cards
M.NotSetUpText = "SOON"               -- Robux chest without a ProductId
M.NotEnoughCoinsText = "Not enough coins!"
M.ChanceDecimals = 2                  -- how many decimals the % shows at most (0.25%, 12%, 3.5%)
M.CoinPriceText = "{price} Coins"     -- price on a coin chest's buttons
M.RobuxPriceText = "\u{E002} {price}" -- price on a Robux chest's buttons (\u{E002} = the Robux icon)
M.OpenText = "Open  {price}"          -- the Open button on the contents page
M.OddsText = "1 balloon per open"     -- under the chest on the contents page

-- THE SHOP CARD
M.Card = {
	ModelSpin = 20,       -- degrees per second the chest turns on its card (0 = still)
	HoverSpin = 90,       -- ...and while you hover it
	HoverOutline = true,  -- the white outline on hover (same as the coin packs)
	ClickOpensContents = true, -- clicking the card (not the Buy button) shows what's inside
	BuyOpensContents = false,  -- true = the Buy button also goes to the contents page first instead of opening straight away
}

-- THE SPIN (StarterGui > CrateOpening)
M.Spin = {
	Time = 6,           -- seconds the strip spins for
	Cells = 55,         -- how many balloons fly past (the winner is near the end)
	Skip = true,        -- show the Skip button
	TickSound = "Hover",          -- plays every time a balloon passes the line (a name from SoundConfig, "" = none)
	WinSound = "QuestComplete",   -- when it lands
	RevealTime = 1.2,   -- seconds the winner stays highlighted before the inspect screen
	InspectAfter = true, -- true = go straight into the inspect screen with what you got (Stop = back to the shop)
	CellGap = 8,        -- pixels between the balloons on the strip
	WinnerPop = 1.12,   -- how much the winner grows when it lands (1 = not at all)
	TitleText = "Opening {name}...",
	WonText = "You got {balloon}!",
	GiftedText = "{from} gifted you a {name}!",
}

------------------------------------------------------------ (no need to edit below)
M.ById = {}
for _, c in M.Crates do M.ById[c.Id] = c end

-- "2026-10-31 23:59" (UTC) -> unix time
function M.ParseTime(t)
	if type(t) == "number" then return t end
	if type(t) ~= "string" then return nil end
	local y, mo, d, h, mi = t:match("^(%d+)%-(%d+)%-(%d+)%s*(%d*):?(%d*)")
	if not y then return nil end
	return DateTime.fromUniversalTime(tonumber(y), tonumber(mo), tonumber(d), tonumber(h) or 0, tonumber(mi) or 0, 0).UnixTimestamp
end

local function now() return workspace:GetServerTimeNow() end

-- "open" (can be bought), "soon" (shown but not started), "hidden"
function M.State(crate, t)
	t = t or now()
	if not crate or crate.ShowInShop == false then return "hidden" end
	local s, e = M.ParseTime(crate.Start), M.ParseTime(crate.End)
	if e and t >= e then return "hidden" end
	if s and t < s then return crate.ShowBeforeStart and "soon" or "hidden" end
	return "open"
end

-- the chests to show, in shop order
function M.Visible(t)
	local list = {}
	for _, c in M.Crates do if M.State(c, t) ~= "hidden" then table.insert(list, c) end end
	table.sort(list, function(a, b) return (a.Order or 0) < (b.Order or 0) end)
	return list
end

-- {{Id, Chance, Percent}, ...} highest chance first (only balloons that exist in SkinConfig)
function M.Odds(crate)
	local Skins = require(game:GetService("ReplicatedStorage"):WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
	local total, list = 0, {}
	for _, e in crate.Contents or {} do
		if Skins.ById[e.Id] and (tonumber(e.Chance) or 0) > 0 then total += e.Chance table.insert(list, e) end
	end
	local out = {}
	for _, e in list do table.insert(out, {Id = e.Id, Chance = e.Chance, Percent = e.Chance / total * 100}) end
	table.sort(out, function(a, b) return a.Chance > b.Chance end)
	return out, total
end

function M.PercentText(p)
	local d = M.ChanceDecimals or 2
	local s = ("%." .. d .. "f"):format(p)
	if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
	if s == "0" then s = "<" .. ("%." .. d .. "f"):format(10 ^ -d) end
	return s .. "%"
end

function M.TimeText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d, h, m, s = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60, seconds % 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm %ds"):format(m, s) end
	return s .. "s"
end

function M.ByProduct(productId)
	for _, c in M.Crates do
		if c.Price and (c.Price.ProductId or 0) ~= 0 and c.Price.ProductId == productId then return c end
	end
end

return M
