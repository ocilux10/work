-- TRADING SETTINGS (ServerScriptService > TradeServer, StarterPlayerScripts > TradeClient)
-- UI: StarterGui > Main > TradeListFrame (players list: eye = look at their balloons, Trade = send a request),
--     TradePrompt (incoming request), TradeFrame (the trade itself), TradeViewFrame (someone's balloons).
local C = {}
C.MaxItems = 12            -- most balloons each side can put in one trade
C.AllowCoins = true        -- coins can be offered
C.MaxCoins = 1000000       -- most coins one side can offer
C.RequestTimeout = 20      -- seconds a request waits for an answer
C.RequestCooldown = 10     -- seconds before you can ask the same player again
C.ConfirmTime = 3          -- both accepted -> this many seconds, then it happens (any change cancels the accepts)
C.MinLevel = 0             -- level needed to trade (0 = anyone)
-- texts ({name} = the other player's name, {n} = seconds / numbers)
C.Text = {
	Request = "{name} wants to trade!",
	Sent = "Sent",
	Accept = "Accept",
	Accepted = "Accepted",
	Countdown = "Trading in {n}...",
	TheyAccepted = "READY",
	Done = "Trade complete!",
	Declined = "{name} declined your trade",
	Cancelled = "{name} cancelled the trade",
	Busy = "{name} is already trading",
	NotAllowed = "{name} isn't accepting trades",
	Count = "{n}/{max} • {items} balloons", -- (n = slots used, items = balloons counting copies)
	Empty = "No one else is in this server",
	TheirEmpty = "No balloons yet",
}
return C
