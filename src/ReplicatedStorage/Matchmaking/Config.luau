-- MATCHMAKING CONFIG
-- Everything you'd want to tweak for queues, voting, matches and XP lives here.

local Config = {}

------------------------------------------------------------ QUEUE PADS
Config.ReadyTime = 3          -- seconds both sides must stay full before the match starts
Config.PadRadius = 6.5        -- how far from a circle's centre you can stand and still count (studs)
Config.PadHeight = 8          -- how high above the circle you can be (jumping still counts)
Config.PadMargin = 3          -- extra studs around each circle that still count as standing on it

-- SOLO TEST: true = a match starts with just ONE person on a pad, so you can test the whole flow alone.
-- Only works in Roblox Studio playtests – real servers always need both sides full, even if you forget to turn it off.
-- (In solo, every round is won instantly since there's no enemy team.)
Config.SoloTest = true

-- PLAY MENU MATCHMAKING (ServerScriptService > GlobalMatchmaking): players from every server in the same
-- region search together, then get teleported into a private match server.
Config.Global = {
	Modes = {"1v1", "2v2", "3v3", "4v4"}, -- modes you can search for (FFA isn't in yet)
	JoinTimeout = 30,        -- match server: seconds to wait for everyone to arrive before cancelling
	CheckEvery = 2,          -- seconds between matchmaking checks
	EntryLife = 60,          -- a search that stops being refreshed disappears after this long (e.g. server crashed)
}
Config.StreakAnnounceMin = 10   -- breaking a win streak this big or bigger = [SERVER] announcement
Config.StreakAnnounceGlobal = 50 -- this big or bigger = [GLOBAL] announcement (every server)

------------------------------------------------------------ MATCH FLOW
Config.FadeTime = 0.6         -- black screen fade in / out
Config.LogoHoldTime = 1.5     -- how long the logo stays up before the vote
Config.LogoText = "Balloon Duels"  -- shown if LogoImage is empty
Config.LogoImage = "rbxassetid://93123859640937"         -- e.g. "rbxassetid://123456" once you have a logo
Config.VoteTime = 10          -- seconds to vote (always runs to the end)
Config.VoteResultTime = 3.5   -- how long the "map picked" animation plays before the match loads
Config.PointsToWin = 6        -- first team to this many round wins takes the match
Config.RoundCountdown = 3     -- freeze countdown at the start of every round
Config.RoundTime = 90         -- seconds per round (timer above the score). Nobody wins by then = DRAW, no point. nil = no limit

-- ROUND RESULT TEXT (the big banner + the line underneath it)
-- Placeholders you can use in the lines:
--   {killer} {victim}  player names (1v1)
--   {winner} {loser}   team names from MyTeamName / EnemyTeamName (team games; your team is always MyTeamName)
--   {seconds}          how long the round took      {s} = "second" or "seconds"
Config.ResultText = {
	Won = "ROUND WON",
	Lost = "ROUND LOST",
	Draw = "DRAW",

	Kill1v1 = "{killer} killed {victim} in {seconds} {s}",
	TeamKill = "{winner} killed {loser} in {seconds} {s}",
	TimeUp = "Time's up no points awarded",
	EveryoneDown = "Everyone went down no points awarded",

	MyTeamName = "Team 1",
	EnemyTeamName = "Team 2",
}
Config.ShootDelay = 0.5       -- after the countdown ends, balloon shots stay locked this long (moving + melee are allowed)
Config.KillReplay = true      -- replay the match-winning kill (killer's eyes) before the victory / defeat screen
Config.KillReplayTime = 3     -- seconds of replay
Config.RoundResultDelay = 1   -- after the round-winning kill, the kill popup stays this long before the round result appears
Config.RoundEndDelay = 4.5    -- total pause after a round is won before the next one (result is up for the rest)
Config.HoldingSpot = Vector3.new(0, 900, -6000) -- where players wait (out of sight) between getting a match and the first round
Config.EndScreenTime = 10      -- victory / defeat screen before going back to the lobby

------------------------------------------------------------ 1v1 REQUESTS
-- Mute tick on the 1v1 popup: the first mute of someone lasts this many minutes,
-- muting the same person again later lasts until the server shuts down.
Config.DuelMuteMinutes = 5

------------------------------------------------------------ XP (saved with ProfileStore)
-- Match XP = Win / Loss bonus  +  everything your kill popups showed during the match
-- (KILL, HEADSHOT, LONGSHOT, JUMPSHOT, MELEE – amounts in BalloonCombat > Config > XP).
-- Practice-arena / dummy kills give no XP.
Config.XP = {
	Win = 100,
	Loss = 25,
}

-- LEVEL CURVE: XP needed to go from `level` to `level + 1`
--   = Base + PerLevel * (level - 1) + Curve * (level - 1) ^ Power      (rounded to the nearest 10)
-- Each level takes a bit more than the last, but it never explodes:
--   Lv1→2: 300   Lv5→6: 480   Lv10→11: 730   Lv20→21: 1270   Lv30→31: 1850   Lv39→40: 2410   Lv50→51: 3120
-- A typical match is roughly 150–500 XP (loss with a couple of kills → win with headshots).
Config.XPCurve = {
	Base = 300,      -- cost of level 1 → 2
	PerLevel = 40,   -- every level costs this much more than the last
	Curve = 2.5,     -- small extra that grows faster at high levels
	Power = 1.5,     -- how quickly that extra grows (keep it around 1.3–1.6)
}

function Config.XPToNext(level)
	local c = Config.XPCurve
	local n = math.max(level or 1, 1) - 1
	local raw = c.Base + c.PerLevel * n + c.Curve * n ^ c.Power
	return math.floor(raw / 10 + 0.5) * 10
end

-- total XP -> level, XP into this level, XP needed for the next level
function Config.LevelInfo(totalXP)
	local left = math.max(0, math.floor(totalXP or 0))
	local level = 1
	while level < 10000 do
		local need = Config.XPToNext(level)
		if left < need then return level, left, need end
		left -= need
		level += 1
	end
	return level, 0, Config.XPToNext(level)
end

function Config.LevelFromXP(xp)
	return (Config.LevelInfo(xp))
end

-- LEVEL-UP REWARDS: a random amount of coins for every level gained,
-- between Min and Max in steps of Step (300, 310, 320 ... 500).
Config.LevelUpCoins = {
	Min = 50,
	Max = 100,
	Step = 5,
}

function Config.CoinsForLevel(level)
	local c = Config.LevelUpCoins
	local steps = math.floor((c.Max - c.Min) / c.Step)
	return c.Min + math.random(0, steps) * c.Step
end

------------------------------------------------------------ MAPS
-- Model = name of the map model inside ServerStorage > Maps
-- Image = picture for the vote card ("rbxassetid://..."), leave "" to just show the colour + name
-- Every map model needs:  Spawns > Team1 (parts 1-4) and Spawns > Team2 (parts 1-4), plus a "Spectate" part
Config.Maps = {
	{Name = "Warehouse", Model = "Warehouse", Image = "rbxassetid://81420071727504", Color = Color3.fromRGB(70, 80, 100)},
	{Name = "Arena", Model = "Arena", Image = "rbxassetid://80252872391694", Color = Color3.fromRGB(70, 80, 100)},
	{Name = "Map 3", Model = "Map3", Image = "", Color = Color3.fromRGB(60, 110, 70)},
	{Name = "Map 4", Model = "Map4", Image = "", Color = Color3.fromRGB(60, 80, 130)},
	{Name = "Map 5", Model = "Map5", Image = "", Color = Color3.fromRGB(130, 110, 50)},
	{Name = "Map 6", Model = "Map6", Image = "", Color = Color3.fromRGB(100, 60, 120)},
	{Name = "Map 7", Model = "Map7", Image = "", Color = Color3.fromRGB(50, 110, 120)},
	{Name = "Map 8", Model = "Map8", Image = "", Color = Color3.fromRGB(130, 80, 50)},
	{Name = "Map 9", Model = "Map9", Image = "", Color = Color3.fromRGB(80, 80, 80)},
}

-- MAP VOTE BACKGROUND: instead of a black screen, the camera hovers over random maps (blurred) while you vote.
-- The server keeps a look-only copy of every map far away (workspace > MapPreviews) for this.
Config.VotePreview = {
	Enabled = true,
	ShotTime = 4,        -- seconds on each map before cutting to the next
	Blur = 14,           -- blur strength behind the vote UI (0 = none)
	Height = 0.9,        -- how high above the map the camera floats (x the map's height, + 12 studs)
	Distance = 0.75,     -- how far out from the middle (x the map's width)
	Origin = Vector3.new(0, 600, -3000), -- where the preview copies are placed
	Spacing = 1200,
}

-- where running matches get built (each running match gets its own slot so several can run at once)
Config.ArenaOrigin = Vector3.new(0, 600, 3000)
Config.ArenaSpacing = 1200

-- MVP (team modes): the best player of the match, by points below. Shown on the end screen, crowned above their head,
-- and stood in the MIDDLE of their team's line-up (teammates either side). Counts for the "Get MVP" quest.
Config.MVP = {
	Enabled = true,
	MinTeamSize = 2,      -- 2 = only 2v2 and bigger (1v1 has no MVP)
	KillPoints = 100,
	AssistPoints = 50,
	DeathPoints = -40,    -- each death takes this off
	WinBonus = 25,        -- small tie-breaker for the winning team
	LineupSpacing = 4.5,  -- studs between players in the end line-up
	Tag = "\u{1F451} MVP", -- text above the MVP's head
	Color = Color3.fromRGB(255, 205, 60),
	EndText = "MVP: {name}", -- EndScreen > MVP label ({name}, {kills}, {deaths}, {assists})
}

-- PARTIES (Main > Top > PartyInvite "+" button, or the Invite button on someone's profile)
-- The leader searches in the Play menu and the whole party is put on the same team.
-- A party can only search modes with at least as many players per team as the party has (2 people -> 2v2, 3v3, 4v4).
Config.Party = {
	MaxSize = 4,        -- biggest party (4 = the biggest mode, 4v4)
	InviteTimeout = 20, -- seconds to accept an invite
	InviteCooldown = 20, -- seconds before you can invite the same person again (the Invite button counts it down)
}

return Config
