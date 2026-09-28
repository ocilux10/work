-- LEADERBOARD CHAT TAGS
-- Players in the top MaxRank of any leaderboard (All Time or Monthly) get a tag in front of their name in chat,
-- e.g.  [#1 KILLS] lux: gg
-- If they're on several boards, only their BEST one shows (lowest number; ties go by the Priority order below).

local C = {}

C.Enabled = true
C.MaxRank = 100 -- top 100 of a board gets a tag

-- what the tag says. {rank} = their place, {board} = the board's text below
C.Format = "[#{rank} {board}]"

-- the text for each board / period (leave one out = no tags from that board)
C.BoardText = {
	Kills     = {AllTime = "KILLS",     Monthly = "MONTHLY KILLS"},
	Wins      = {AllTime = "WINS",      Monthly = "MONTHLY WINS"},
	Level     = {AllTime = "LEVEL"},
	Winstreak = {AllTime = "WINSTREAK"},
}

-- tie-breaker when someone has the same place on two boards (first = shown)
C.Priority = {"Kills_AllTime", "Wins_AllTime", "Level_AllTime", "Winstreak_AllTime", "Kills_Monthly", "Wins_Monthly"}

-- tag colour by place: the first line whose UpTo is >= their place is used
C.Colors = {
	{UpTo = 1,   Color = Color3.fromRGB(255, 200, 40)},  -- #1 gold
	{UpTo = 2,   Color = Color3.fromRGB(200, 205, 215)}, -- #2 silver
	{UpTo = 3,   Color = Color3.fromRGB(205, 127, 50)},  -- #3 bronze
	{UpTo = 10,  Color = Color3.fromRGB(185, 100, 255)}, -- #4 - #10 purple
	{UpTo = 100, Color = Color3.fromRGB(90, 190, 255)},  -- #11 - #100 blue
}

-- OPTIONAL: fully custom tags for exact places, e.g. the #1 killer:
--   C.Custom = { Kills_AllTime = { [1] = {Text = "[TOP KILLER]", Color = Color3.fromRGB(255, 60, 60)} } }
C.Custom = {}

return C
