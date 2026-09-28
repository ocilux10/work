-- DAILY REWARDS - edit freely. UI: StarterGui > Main > DailyRewardsFrame (Rewards > Frame = one day's card, the first
-- one is the template). Opened by the gift button in the top bar. Server: ServerScriptService > DailyRewardsServer.
-- A reward is written like this (any mix - see ReplicatedStorage > RewardInfo):
--   {Coins = 250}   {Crate = "Basic"}   {Crate = "Premium", CrateCount = 2}   {Balloon = "Toxic"}   {Coins = 500, Crate = "Basic"}
--   + optional Image = "rbxassetid://..." (picture on the card) / Name = "..." (text on the card instead)
local M = {}

-- one line per day (day 1 first). Add or remove lines to make the cycle longer / shorter.
M.Days = {
	{Coins = 100},
	{Coins = 150},
	{Coins = 200},
	{Crate = "Basic"},
	{Coins = 300},
	{Coins = 400},
	{Coins = 500, Crate = "Premium"},
}

M.CooldownHours = 24      -- hours after claiming until the next reward
M.StreakHours = 48        -- claim again within this many hours of your last claim to keep your streak
M.MissedDay = "Reset"     -- "Reset" = miss the StreakHours window and you're back to day 1,  "Keep" = carry on from where you were
M.AfterLastDay = "Loop"   -- after the last day: "Loop" = back to day 1,  "Stay" = keep getting the last day's reward
M.OpenOnJoin = true       -- open the menu by itself when a reward is waiting (once per join)

-- TEXTS ({time} = "5h 12m")
M.ClaimText = "CLAIM"
M.WaitText = "NEXT IN {time}"
M.ClaimedText = "You got {reward}!"
M.DayText = "{day}"        -- the day number on each card ("Day {day}" = "Day 1" ...)

-- LOOK
M.CoinImage = ""          -- picture for coin rewards ("" = the one on the template card)
M.TodayOutline = Color3.fromRGB(255, 255, 255) -- the outline on the card you can claim today
M.FutureTransparency = 0.35 -- how faded the days you haven't reached yet are (0 = not at all)

-- THE TOP BAR BUTTON (TopbarPlus)
M.Topbar = {
	Image = "",                       -- your gift picture, e.g. "rbxassetid://123456" ("" = the Label below instead)
	ImageScale = 0.6,
	Label = "🎁",
	Badge = true,                     -- the red "1" when a reward is waiting
	Color = Color3.fromRGB(18, 18, 21),
	LobbyOnly = true,                 -- hidden in matches / the practice arena
}

return M
