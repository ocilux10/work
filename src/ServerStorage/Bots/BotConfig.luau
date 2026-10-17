-- BOT SETTINGS  (ServerStorage > Bots > BotService runs them)
-- Bots fight like players: sprint, slide, jump, climb, throw and swing - using the same damage as players.
local M = {}

-- ON / OFF: false = no bots anywhere (queues never get filled, the admin test button does nothing)
M.Enabled = true

-- FILLING QUEUES (casual only - never ranked): after this many seconds waiting without a full match, bots fill the
-- empty places and the match starts. A real player who turns up first takes the place instead.
M.FillAfter = 10
M.FillPads = true          -- the queue pads in the lobby
M.FillMatchmaking = true   -- the Play menu (1v1 - 4v4): your side is filled up with bots too

-- WHICH DIFFICULTY bots use (one of the names below)
M.Difficulty = "Medium"

-- DIFFICULTIES - every number here changes how a bot plays:
--   ReactionTime   seconds after it first sees you before it can throw
--   Accuracy       % of throws that hit (a body hit = 75 damage, two kill)
--   Headshots      % of its HITS that are headshots (a headshot kills outright)
--   ThrowDelay     extra seconds between throws on top of the normal reload
--   MeleeAccuracy  % of swings that connect when close
--   AimTurnSpeed   how fast it turns to face you (higher = snappier)
--   PreferMin/Max  the distance it likes to fight from (studs)
--   StrafeChange   seconds between changing which way it strafes (lower = harder to hit)
--   SprintChance   0-1: how often it sprints instead of walking
--   SlideChance    chance per second to slide while running
--   JumpChance     chance per second to jump to dodge
--   Climb          true = climbs walls / boxes in the way (up to ClimbMax studs high)
M.Difficulties = {
	Easy = {
		ReactionTime = 0.9, Accuracy = 18, Headshots = 0, ThrowDelay = 0.9, MeleeAccuracy = 45,
		AimTurnSpeed = 5, PreferMin = 22, PreferMax = 45, StrafeChange = 1.6,
		SprintChance = 0.4, SlideChance = 0.05, JumpChance = 0.05, Climb = true, ClimbMax = 12,
	},
	Medium = {
		ReactionTime = 0.55, Accuracy = 32, Headshots = 4, ThrowDelay = 0.45, MeleeAccuracy = 60,
		AimTurnSpeed = 8, PreferMin = 18, PreferMax = 40, StrafeChange = 1.1,
		SprintChance = 0.75, SlideChance = 0.12, JumpChance = 0.1, Climb = true, ClimbMax = 16,
	},
	Hard = {
		ReactionTime = 0.3, Accuracy = 48, Headshots = 10, ThrowDelay = 0.15, MeleeAccuracy = 75,
		AimTurnSpeed = 12, PreferMin = 14, PreferMax = 34, StrafeChange = 0.7,
		SprintChance = 0.95, SlideChance = 0.22, JumpChance = 0.18, Climb = true, ClimbMax = 18,
	},
}

-- LOOKS: each bot wears the avatar of one of these Roblox accounts (picked at random; a standard body, like players
-- get in fights). Add / remove any user ids.
M.AvatarUserIds = {
	1, 156, 261, 2207291, 7733466, 18339063, 28969907, 48103520, 63691473, 99178012,
	116855413, 155291620, 205301230, 261946594, 349211812, 1206543842, 1510245318,
}
-- NAMES: made-up player names (picked at random, never two the same in one match)
-- LEVELS shown on their cards / the Tab scoreboard (random between these)
M.LevelMin = 3
M.LevelMax = 40
M.Names = {
	"xXSnipeKingXx", "balloonpro22", "N1ghtShade", "popmaster_7", "Zyrex", "lilfrost09", "Kairo_YT", "vexxed",
	"Mochi_Bear", "TrickyNova", "skyhopper44", "JayJayPlays", "aimlessxd", "Rivuu", "Blitzkrieg_88", "quietstorm",
	"FrostByte", "pixelbandit", "HollowHalo", "eeeevan", "Tofu_Ninja", "Mxlti", "cloudy_dayz", "Reaper_Rin",
}

return M
