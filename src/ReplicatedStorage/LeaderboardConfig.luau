-- LEADERBOARD SETTINGS
-- Boards: a model named <Name> anywhere in Workspace > UiPart > <Name>Gui > <Name>Frame (the names must match).
-- Inside each: <Name>Scrolling > Template (one row), AllTime / Monthly buttons, Updates label,
-- and <Name>Gui > Template2 = the "You" row at the bottom.
-- Row parts: PlaceLabel, PlayerImage, PlayerName, PlayerUser, Amount.
local C = {}

C.TopCount = 100        -- how many players each board lists
C.UpdateEvery = 300     -- seconds between refreshes ("Leaderboard Updates In 4:59")
C.RankLimit = 1000      -- your exact rank is worked out down to here; below that the You row shows "1,000+"
C.NoneText = "N/A"      -- shown as your place when you have 0 of that stat

-- Stat = what's ranked. Monthly = also has a this-month board (needs a Monthly button on the board).
-- Display "Level" = stored as XP (so ties break properly) but shown as the level number.
C.Boards = {
	{Name = "Kills", Stat = "Kills", Monthly = true},
	{Name = "Wins", Stat = "Wins", Monthly = true},
	{Name = "Level", Stat = "XP", Display = "Level"},
	-- (Store = the saved data's name - kept as "WinStreak" so existing scores aren't lost after the rename)
	{Name = "Winstreak", Stat = "WinStreak", Store = "WinStreak"}, -- current streak
}

-- colours of the place numbers (#1, #2, #3), everyone else gets OtherPlaceColor
C.PlaceColors = {
	Color3.fromRGB(255, 200, 40),  -- #1 gold
	Color3.fromRGB(200, 205, 215), -- #2 silver
	Color3.fromRGB(205, 127, 50),  -- #3 bronze
}
C.OtherPlaceColor = Color3.fromRGB(255, 255, 255) -- #4 and below (and N/A) = plain white

-- Studio can't use real leaderboard data unless "Enable Studio Access to API Services" is on,
-- so Studio shows made-up players instead (only in Studio, never in the real game).
C.StudioFakeData = true

return C
