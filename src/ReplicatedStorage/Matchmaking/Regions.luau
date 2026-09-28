-- REGIONS: country code (from Roblox) -> matchmaking region.
-- Players only get matched with people in the SAME region (GlobalMatchmaking). Move a country to another
-- region here if you want it grouped differently.
local Regions = {}

Regions.List = {
	["Europe"] = "AD AL AT BA BE BG BY CH CY CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK SM UA VA XK TR GE AM AZ",
	["North America"] = "US CA MX GT BZ SV HN NI CR PA CU DO HT JM PR BS BB TT AG DM GD KN LC VC BM GL KY TC VG VI AW CW",
	["South America"] = "BR AR CL CO PE VE EC BO PY UY GY SR GF FK",
	["Middle East"] = "AE SA QA BH KW OM IL PS JO LB SY IQ IR YE EG",
	["Asia"] = "JP KR KP CN TW HK MO MN SG MY ID TH VN PH KH LA MM BN TL IN PK BD LK NP BT MV AF KZ UZ TM KG TJ",
	["Oceania"] = "AU NZ FJ PG SB VU NC PF WS TO KI FM MH PW NR TV GU",
	["Africa"] = "ZA NG KE MA DZ TN LY SD ET GH CI SN CM UG TZ AO MZ ZM ZW BW NA MG MU RW BJ BF ML NE TD CF CG CD GA GQ GN GW LR SL TG GM MR ER DJ SO SS BI MW LS SZ KM SC CV ST RE YT",
}
Regions.Fallback = "North America" -- unknown countries

local byCountry = {}
for region, codes in Regions.List do
	for code in codes:gmatch("%u%u") do byCountry[code] = region end
end

function Regions.ForCountry(code)
	return (code and byCountry[string.upper(code)]) or Regions.Fallback
end

-- server only: the region of a player (cached on the player as the "Region" attribute)
function Regions.ForPlayer(player)
	local cached = player:GetAttribute("Region")
	if cached then return cached end
	local ok, code = pcall(function()
		return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(player)
	end)
	local region = Regions.ForCountry(ok and code or nil)
	player:SetAttribute("Region", region)
	return region
end

return Regions
