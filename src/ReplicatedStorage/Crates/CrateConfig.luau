-- CRATES / CHESTS - everything about the chests in the shop (Main > ShopFrame > CRATES). Edit freely.
--   3D model: built by ReplicatedStorage > Crates > ChestBuilder from each chest's Look (colours below). Want your own
--             model instead? Put it in Crates > Models and set Model = "<its name>" (and remove Look).
--   Balloons (names, rarities, looks): ReplicatedStorage > BalloonSkins > SkinConfig
--   Look of the shop card:  Main > ShopFrame > ScrollingFrame > CratesSection1 > Crate (the first one is the template)
--   Look of the contents page: Main > ShopFrame > CrateView       Look of the spin: StarterGui > CrateOpening
--
-- ONE CHEST:
--   Id          unique name, never change it once the game is live
--   Name        shown on the card / contents page
--   Look        the chest's colours: Body / Lid / Trim (base, ridge, corners, lock frame) / Seam / Lock (the plate + its
--               light), Material / LockMaterial ("SmoothPlastic", "Neon", "Metal", "Foil"...), Sparkle = true (sparkles
--               around it, SparkleColor)
--   Model       (instead of Look) a model in Crates > Models
--   Tag         the little badge on the card ("CHEST", "NEW", "LIMITED"...). "" = no badge
--   Color       colour of the badge + the line under the card
--   Order       position in the shop (1 = first)
--   ShowInShop  false = hidden from the shop and can't be opened
--   Start / End WHEN it's in the shop, UTC time "YYYY-MM-DD HH:MM" (nil = always). After End it leaves the shop by
--               itself (and can't be bought any more). Before Start it's hidden (or "COMING SOON", see ShowBeforeStart).
--   ShowBeforeStart  true = shows before Start with a "COMING IN ..." timer (can't be opened yet)
--   Price       Coins = 500                   -> can be opened with coins (leave it out = Robux only)
--               Robux = 49, ProductId = 123   -> can ALSO be bought with Robux: make a Developer Product for it (Creator
--                                                Hub > your game > Monetization > Developer Products) and put its id here.
--                                                ProductId 0 = not made yet (the Robux button says SOON).
--               Robux chests can be gifted too.
--   Contents    what can come out: {Id = balloon id, Chance = number}. Chances are shares of the total, so they
--               don't HAVE to add up to 100 (the shop shows the real %). Keep them adding to 100 to keep it simple.
local M = {}
local C = Color3.fromRGB

M.Crates = {
	{
		Id = "Basic", Name = "Basic Chest", Tag = "CHEST", Color = C(190, 200, 210), Order = 1,
		Look = {Body = C(205, 212, 222), Lid = C(220, 226, 235), Trim = C(120, 128, 140), Lock = C(70, 170, 255), LockMaterial = "Neon"},
		ShowInShop = true, Start = nil, End = nil,
		Price = {Coins = 500, Robux = 49, ProductId = 0},
		Contents = {
			-- common 85
			{Id = "Honeycomb",  Chance = 15},
			{Id = "Bubblegum",  Chance = 12},
			{Id = "Mint",       Chance = 12},
			{Id = "Sky",        Chance = 12},
			{Id = "Lemon",      Chance = 10},
			{Id = "Coal",       Chance = 8},
			{Id = "Beehive",    Chance = 8},
			{Id = "Peppermint", Chance = 8},
			-- rare 12
			{Id = "CandySwirl", Chance = 3},
			{Id = "Heartbreak", Chance = 3},
			{Id = "Chrome",     Chance = 2},
			{Id = "NeonLime",   Chance = 2},
			{Id = "Marble",     Chance = 2},
			-- epic 3
			{Id = "Frostbite",  Chance = 1.5},
			{Id = "Toxic",      Chance = 1},
			{Id = "GoldRush",   Chance = 0.5},
		},
	},
	{
		Id = "Premium", Name = "Premium Chest", Tag = "PREMIUM", Color = C(60, 140, 255), Order = 2,
		Look = {Body = C(40, 105, 225), Lid = C(55, 125, 240), Trim = C(25, 45, 100), Lock = C(255, 200, 60), LockMaterial = "Neon"},
		ShowInShop = true, Start = nil, End = nil,
		Price = {Coins = 1500, Robux = 149, ProductId = 0},
		Contents = {
			-- rare 50
			{Id = "CandySwirl",   Chance = 7},
			{Id = "Heartbreak",   Chance = 7},
			{Id = "Chrome",       Chance = 6},
			{Id = "GlassBalloon", Chance = 6},
			{Id = "NeonLime",     Chance = 6},
			{Id = "Marble",       Chance = 6},
			{Id = "CottonCandy",  Chance = 4},
			{Id = "Lovestruck",   Chance = 4},
			{Id = "Glacier",      Chance = 2},
			{Id = "StormCloud",   Chance = 2},
			-- epic 38
			{Id = "Frostbite",     Chance = 6},
			{Id = "Toxic",         Chance = 6},
			{Id = "Glitch",        Chance = 6},
			{Id = "GoldRush",      Chance = 5},
			{Id = "Hologram",      Chance = 5},
			{Id = "RoyalJelly",    Chance = 4},
			{Id = "BrokenHearted", Chance = 3},
			{Id = "AcidRain",      Chance = 1.5},
			{Id = "Corrupted",     Chance = 1.5},
			-- legendary 11
			{Id = "Inferno",     Chance = 2},
			{Id = "Thunder",     Chance = 2},
			{Id = "ShadowVoid",  Chance = 1.5},
			{Id = "Blizzard",    Chance = 1.5},
			{Id = "Radioactive", Chance = 1},
			{Id = "Error404",    Chance = 1},
			{Id = "BlueFlame",   Chance = 1},
			{Id = "Voltage",     Chance = 0.5},
			{Id = "Eclipse",     Chance = 0.5},
			-- mythic 1
			{Id = "Cosmic",  Chance = 0.3},
			{Id = "Royal",   Chance = 0.3},
			{Id = "Diamond", Chance = 0.2},
			{Id = "Galaxy",  Chance = 0.2},
		},
	},
	{
		Id = "Exclusive", Name = "Exclusive Chest", Tag = "LIMITED", Color = C(255, 180, 40), Order = 3,
		Look = {Body = C(28, 28, 34), Lid = C(38, 38, 46), Trim = C(215, 165, 45), Lock = C(255, 45, 45), LockMaterial = "Neon",
			Sparkle = true, SparkleColor = C(255, 200, 80)},
		ShowInShop = true, Start = nil, End = "2026-10-31 23:59", -- leaves the shop at the end of October
		Price = {Coins = 5000, Robux = 399, ProductId = 0},
		Contents = {
			-- epic 45
			{Id = "Glitch",        Chance = 8},
			{Id = "Magma",         Chance = 8},
			{Id = "AcidRain",      Chance = 8},
			{Id = "Toxic",         Chance = 7},
			{Id = "Corrupted",     Chance = 7},
			{Id = "BrokenHearted", Chance = 7},
			-- legendary 40
			{Id = "Inferno",    Chance = 5},
			{Id = "Thunder",    Chance = 5},
			{Id = "ShadowVoid", Chance = 5},
			{Id = "BlueFlame",  Chance = 5},
			{Id = "Voltage",    Chance = 5},
			{Id = "Eclipse",    Chance = 5},
			{Id = "Nebula",     Chance = 5},
			{Id = "Emperor",    Chance = 5},
			-- mythic 12
			{Id = "Cosmic",   Chance = 2.5},
			{Id = "Royal",    Chance = 2.5},
			{Id = "Hellfire", Chance = 2},
			{Id = "Plasma",   Chance = 2},
			{Id = "Abyss",    Chance = 1.5},
			{Id = "Galaxy",   Chance = 1},
			{Id = "Diamond",  Chance = 0.5},
			-- exclusive 3
			{Id = "RainbowPrism", Chance = 1.2},
			{Id = "Celestial",    Chance = 1},
			{Id = "VoidKing",     Chance = 0.8},
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
	ShowRobuxButton = true,    -- chests with a coin AND a Robux price: a second (Robux) button above Buy on the card
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

-- a fresh 3D model of a chest (built from its Look, or its Model from Crates > Models), or nil
function M.ModelFor(crate)
	if not crate then return nil end
	local folder = game:GetService("ReplicatedStorage"):WaitForChild("Crates")
	if crate.Model then
		local src = folder:WaitForChild("Models"):FindFirstChild(crate.Model)
		if src then return src:Clone() end
	end
	return require(folder:WaitForChild("ChestBuilder")).Build(crate.Look)
end

-- which ways a chest can be bought
function M.HasCoins(crate) return crate and crate.Price and tonumber(crate.Price.Coins) ~= nil end
function M.HasRobux(crate) return crate and crate.Price and (crate.Price.Robux ~= nil or crate.Price.ProductId ~= nil) end
function M.RobuxReady(crate) return M.HasRobux(crate) and (crate.Price.ProductId or 0) ~= 0 end

function M.ByProduct(productId)
	for _, c in M.Crates do
		if c.Price and (c.Price.ProductId or 0) ~= 0 and c.Price.ProductId == productId then return c end
	end
end

return M
