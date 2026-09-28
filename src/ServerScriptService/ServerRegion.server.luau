-- SERVER REGION  ->  workspace:GetAttribute("ServerRegion")  (shown under the fps / ms)
-- Shows the big region the server is in: Europe, North America, South America, Asia, Oceania, Africa, Middle East.
--
-- HOW: Roblox sends a game's web requests through its own (US) servers, so asking a website "where am I?" always says
-- North America. Instead this looks at the players: whoever has the LOWEST ping is basically sitting next to the
-- server, so the server is in their region (their country comes from Roblox's LocalizationService).
-- Re-checked every few seconds, so it corrects itself as players join / leave. No HTTP needed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")

local CHECK_EVERY = 5      -- seconds
local CLOSE_PING_MS = 90   -- a player this close (or closer) decides the region straight away

local REGIONS = {
	["Europe"] = "AD AL AT BA BE BG BY CH CY CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK SM UA VA XK TR GE AM AZ",
	["North America"] = "US CA MX GT BZ SV HN NI CR PA CU DO HT JM PR BS BB TT AG DM GD KN LC VC BM GL KY TC VG VI AW CW",
	["South America"] = "BR AR CL CO PE VE EC BO PY UY GY SR GF FK",
	["Middle East"] = "AE SA QA BH KW OM IL PS JO LB SY IQ IR YE EG",
	["Asia"] = "JP KR KP CN TW HK MO MN SG MY ID TH VN PH KH LA MM BN TL IN PK BD LK NP BT MV AF KZ UZ TM KG TJ",
	["Oceania"] = "AU NZ FJ PG SB VU NC PF WS TO KI FM MH PW NR TV GU",
	["Africa"] = "ZA NG KE MA DZ TN LY SD ET GH CI SN CM UG TZ AO MZ ZM ZW BW NA MG MU RW BJ BF ML NE TD CF CG CD GA GQ GN GW LR SL TG GM MR ER DJ SO SS BI MW LS SZ KM SC CV ST RE YT",
}
local BY_COUNTRY = {}
for region, codes in REGIONS do
	for code in codes:gmatch("%u%u") do BY_COUNTRY[code] = region end
end

local countryOf = {} -- [player] = "GB"
local function lookup(p)
	local ok, code = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(p) end)
	if ok and type(code) == "string" then countryOf[p] = string.upper(code) end
end
Players.PlayerAdded:Connect(lookup)
Players.PlayerRemoving:Connect(function(p) countryOf[p] = nil end)
for _, p in Players:GetPlayers() do task.spawn(lookup, p) end

workspace:SetAttribute("ServerRegion", RunService:IsStudio() and "Studio" or "...")
if RunService:IsStudio() then return end

while true do
	local best, bestPing
	for _, p in Players:GetPlayers() do
		local region = countryOf[p] and BY_COUNTRY[countryOf[p]]
		local ok, ping = pcall(function() return p:GetNetworkPing() * 1000 end)
		if region and ok and ping > 0 and (not bestPing or ping < bestPing) then best, bestPing = region, ping end
	end
	-- the closest player decides; if nobody's close yet, still use the closest as the best guess
	if best and (bestPing <= CLOSE_PING_MS or workspace:GetAttribute("ServerRegion") == "...") then
		workspace:SetAttribute("ServerRegion", best)
	elseif best then
		workspace:SetAttribute("ServerRegion", best)
	end
	task.wait(CHECK_EVERY)
end
