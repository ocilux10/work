-- SOUND CONFIG  -  every sound in the game lives here.
--
-- Change a sound: paste a new id into Id ("rbxassetid://123456").
-- Turn one off: Off = true   (back on: Off = false). The id stays there either way.
--   Volume      0 - 10 (0.5 is normal)
--   Pitch       1 = normal, 1.2 = higher/faster, 0.8 = lower/slower
--   PitchRandom a little random pitch each time so repeats don't sound robotic (0 = none)
--   Category    which volume slider it's under (CategoryVolume below)
--   MinGap      (optional) seconds before the same sound can play again (stops spam)
--   Start       (optional) skip this many seconds into the audio
--   Off         true = sound is off, false = sound is on
--
-- Sounds from the Creator Store can be taken down / made private by their uploader. If one goes silent,
-- the Output window says "failed to load" - just swap in another id.

local SoundConfig = {}

SoundConfig.MasterVolume = 1

SoundConfig.CategoryVolume = {
	UI = 1,        -- buttons, menus, popups
	Combat = 1,    -- swings, shots, pops, hits, kills
	Match = 1,     -- countdown, round won / lost, victory, map vote ...
	Lobby = 1,     -- queue pads, lobby list, coins, xp
	Movement = 1,  -- slide, crouch, trampolines
	Ambient = 1,   -- conveyor hum etc.
}

-- timers tick every second; in the last this-many seconds they switch to the harder "urgent" tick
SoundConfig.UrgentTickSeconds = 5

-- ScreenGuis whose buttons DON'T get the automatic click / hover sound
SoundConfig.NoButtonSoundsIn = {"MobileControls"}

local R = "rbxassetid://"
SoundConfig.Sounds = {
	------------------------------------------------------------ UI (every button in the game gets Click + Hover automatically)
	-- (a single button can use a different sound: give it a ClickSound attribute with a name from this list,
	--  or NoClickSound = true to keep it silent)
	Click          = {Off = false, Id = R .. "113397864512278", Volume = 0.6, Pitch = 1, PitchRandom = 0.03, Category = "UI"},
	ButtonPress    = {Off = false, Id = R .. "", Volume = 0.35, Pitch = 0.8, Category = "UI", MinGap = 0.03},  -- mouse / finger goes DOWN on a button
	ButtonRelease  = {Off = false, Id = R .. "", Volume = 0.3, Pitch = 1.25, Category = "UI", MinGap = 0.03}, -- let go OFF the button (no click)
	HoverLeave     = {Off = false, Id = R .. "133216848606395", Volume = 0.25, Pitch = 1.15, Category = "UI", MinGap = 0.05}, -- mouse leaves a button
	Hover          = {Off = false, Id = R .. "133216848606395", Volume = 0.6, Pitch = 1.45, Category = "UI", MinGap = 0.05},
	Open           = {Off = false, Id = R .. "127183292018512", Volume = 0.5, Pitch = 1.1, Category = "UI"},   -- a menu / profile opens
	Close          = {Off = true, Id = R .. "15675037413", Volume = 0.5, Pitch = 1, Category = "UI"},     -- a menu / profile closes
	PanelSlide     = {Off = false, Id = R .. "127183292018512", Volume = 0.35, Pitch = 1.2, Category = "UI"},  -- daily quests / lobby list slide open-closed
	Notify         = {Off = false, Id = R .. "117653664939966", Volume = 0.5, Pitch = 1, Category = "UI"},     -- small notice text ("request sent", ...)
	Error          = {Off = false, Id = R .. "87519554692663", Volume = 0.5, Pitch = 1, Category = "UI"},     -- something you can't do
	Toggle         = {Off = false, Id = R .. "9120094547", Volume = 0.45, Pitch = 1.1, Category = "UI"},  -- tick boxes (mute tick)
	TabOpen        = {Off = true, Id = R .. "15675032796", Volume = 0.35, Pitch = 0.9, Category = "UI"},  -- holding Tab (scoreboard / free mouse)
	DuelRequest    = {Off = false, Id = R .. "15675016548", Volume = 0.6, Pitch = 1, Category = "UI"},     -- someone challenged you to a 1v1
	DuelAccepted   = {Off = false, Id = R .. "15675043410", Volume = 0.6, Pitch = 1.1, Category = "UI"},
	DuelDeclined   = {Off = false, Id = R .. "15675081158", Volume = 0.5, Pitch = 1, Category = "UI"},
	Invite         = {Off = true, Id = R .. "15675046931", Volume = 0.5, Pitch = 1.3, Category = "UI"},
	ChatMessage    = {Off = true, Id = R .. "15675085146", Volume = 0.3, Pitch = 1.3, Category = "UI", MinGap = 0.2}, -- someone typed in match chat

	------------------------------------------------------------ COMBAT
	Hitmarker      = {Off = false, Id = R .. "121351852050830", Volume = 0.5, Pitch = 1, PitchRandom = 0.03, Category = "Combat", MinGap = 0.03}, -- hitmarker tick (players can turn it off: Settings > Crosshair)
	Swing          = {Off = false, Id = R .. "132176641904643", Volume = 0.5, Pitch = 1, PitchRandom = 0.08, Category = "Combat"},   -- melee swing (you + others)
	Shoot          = {Off = false, Id = R .. "113000389487934", Volume = 0.3, Pitch = 1.1, PitchRandom = 0.08, Category = "Combat"}, -- balloon thrown
	Pop            = {Off = false, Id = R .. "9113263444", Volume = 0.6, Pitch = 1, PitchRandom = 0.1, Category = "Combat"},    -- balloon hits something & pops
	BalloonInflate = {Off = true, Id = R .. "134057288", Volume = 0.3, Pitch = 1.6, Category = "Combat", Start = 0},       -- your balloon regrows
	Inspect        = {Off = false, Id = R .. "82062733616238", Volume = 0.3, Pitch = 1, Category = "Combat"},             -- F inspect
	Hit            = {Off = false, Id = R .. "121351852050830", Volume = 0.2, Pitch = 1, PitchRandom = 0.05, Category = "Combat"}, -- you damaged someone
	Headshot       = {Off = false, Id = R .. "108290646184559", Volume = 0.5, Pitch = 1, Category = "Combat"},              -- you hit a head
	MeleeHit       = {Off = false, Id = R .. "139520673393967", Volume = 0.3, Pitch = 0.8, Category = "Combat"},           -- your swing connected
	Kill           = {Off = false, Id = R .. "128062463831151", Volume = 0.3, Pitch = 1, Category = "Combat"},             -- you eliminated someone
	Hurt           = {Off = false, Id = R .. "1471213022", Volume = 0.45, Pitch = 0.7, PitchRandom = 0.05, Category = "Combat", MinGap = 0.1}, -- you got hit
	Death          = {Off = false, Id = R .. "135454814111440", Volume = 0.6, Pitch = 0.9, Category = "Combat"},               -- you died
	KillFeed       = {Off = false, Id = "", Volume = 0.3, Pitch = 1, Category = "Combat"},                                 -- a line in the kill feed (off)

	------------------------------------------------------------ MATCH
	MatchFound     = {Off = false, Id = R .. "123582256549202", Volume = 0.6, Pitch = 0.9, Category = "Match"},  -- screen goes black, logo
	VoteOpen       = {Off = false, Id = R .. "15675046931", Volume = 0.5, Pitch = 0.9, Category = "Match"},  -- map vote appears
	Vote           = {Off = false, Id = R .. "139804904213958", Volume = 0.7, Pitch = 1, PitchRandom = 0.04, Category = "Match"}, -- you (or anyone) voted
	MapPicked      = {Off = false, Id = R .. "15675043410", Volume = 0.7, Pitch = 1, Category = "Match"},    -- the "map picked" animation
	MatchStart     = {Off = false, Id = R .. "140419294351439", Volume = 0.5, Pitch = 0.8, Category = "Match"},  -- fade into the map
	CountdownTick  = {Off = false, Id = R .. "134410911353980", Volume = 0.5, Pitch = 1, Category = "Match"},     -- 3, 2, 1
	Heartbeat      = {Off = true, Id = R .. "135454814111440", Volume = 0.35, Pitch = 1, Category = "Match", MinGap = 0.3}, -- countdown heartbeat pulse
	Fight          = {Off = false, Id = R .. "7743999789", Volume = 0.7, Pitch = 1.5, Category = "Match"},   -- FIGHT!
	RoundWon       = {Off = false, Id = R .. "74216560469867", Volume = 0.6, Pitch = 1, Category = "Match"},
	RoundLost      = {Off = false, Id = R .. "124409408802700", Volume = 0.5, Pitch = 1, Category = "Match"},
	RoundDraw      = {Off = false, Id = R .. "124409408802700", Volume = 0.5, Pitch = 1.3, Category = "Match"},
	ScoreTick      = {Off = false, Id = R .. "134410911353980", Volume = 0.6, Pitch = 1.2, Category = "Match"},  -- the score number rolling up
	PlayerDied     = {Off = false, Id = "", Volume = 0.4, Pitch = 1, Category = "Match"},                    -- any player in your match died (off)
	ReplayStart    = {Off = true, Id = R .. "15675028888", Volume = 0.6, Pitch = 0.6, Category = "Match"},  -- FINAL KILL replay begins
	Victory        = {Off = false, Id = R .. "74216560469867", Volume = 0.6, Pitch = 1, Category = "Match"},
	Defeat         = {Off = false, Id = R .. "124409408802700", Volume = 0.5, Pitch = 1, Category = "Match"},
	XPGain         = {Off = false, Id = R .. "128418218662188", Volume = 0.3, Pitch = 1.6, Category = "Match", MinGap = 0.04}, -- XP bar filling
	LevelUp        = {Off = false, Id = R .. "112485797063762", Volume = 0.7, Pitch = 1, Category = "Match"},
	QuestComplete  = {Off = false, Id = R .. "15675043410", Volume = 0.65, Pitch = 1.25, Category = "Match"},  -- a daily quest finished (end screen / lobby)
	MatchCancelled = {Off = false, Id = R .. "7153932260", Volume = 0.6, Pitch = 0.9, Category = "Match"},
	ReturnToLobby  = {Off = true, Id = R .. "15675024286", Volume = 0.5, Pitch = 1, Category = "Match"},
	EnemyHighlight = {Off = false, Id = "", Volume = 0.4, Pitch = 1, Category = "Match"},                    -- enemies glow red (off)
	-- TIMERS: anything that counts down ticks like a clock
	TimerTick      = {Off = false, Id = R .. "134410911353980", Volume = 0.35, Pitch = 1, Category = "Match"},     -- map vote timer, duel request timer, pad ready countdown
	TimerTickUrgent= {Off = false, Id = R .. "134410911353980", Volume = 0.6, Pitch = 1.25, Category = "Match"},   -- the last UrgentTickSeconds seconds

	------------------------------------------------------------ PLAY MENU MATCHMAKING
	SearchStart    = {Off = false, Id = R .. "15675046931", Volume = 0.55, Pitch = 1, Category = "Lobby"},       -- started searching
	SearchCancel   = {Off = false, Id = R .. "15675037413", Volume = 0.5, Pitch = 0.85, Category = "Lobby"},      -- stopped searching
	QueueMatchFound= {Off = false, Id = R .. "15675043410", Volume = 0.75, Pitch = 1.15, Category = "Lobby"},     -- a match was found
	Teleporting    = {Off = false, Id = R .. "15674975792", Volume = 0.5, Pitch = 0.9, Category = "Lobby"},       -- teleporting to the match / lobby
	QueueCancelled = {Off = false, Id = R .. "15675075163", Volume = 0.6, Pitch = 0.9, Category = "Lobby"},       -- "Match Cancelled" popup
	OpenPlayMenu   = {Off = false, Id = R .. "15675046931", Volume = 0.45, Pitch = 1.2, Category = "UI"},        -- the Play menu opens
	Announcement   = {Off = false, Id = R .. "15675085146", Volume = 0.5, Pitch = 1, Category = "UI"},           -- [SERVER] / [GLOBAL] win streak message

	------------------------------------------------------------ LOBBY
	PadJoin        = {Off = false, Id = R .. "15675055424", Volume = 0.6, Pitch = 1, Category = "Lobby"},    -- you stepped on a queue pad
	PadLeave       = {Off = true, Id = R .. "15675032796", Volume = 0.4, Pitch = 0.75, Category = "Lobby"}, -- you stepped off
	PadPlayerJoined= {Off = true, Id = R .. "15675055424", Volume = 0.4, Pitch = 1.25, Category = "Lobby"}, -- someone joined your pad
	PadReady       = {Off = false, Id = R .. "15675085146", Volume = 0.6, Pitch = 1.2, Category = "Lobby"},  -- both sides full, match about to start
	LobbyJoin      = {Off = false, Id = R .. "15675024286", Volume = 0.5, Pitch = 1.2, Category = "Lobby"},  -- Join button teleport
	ArenaEnter     = {Off = true, Id = R .. "15675012262", Volume = 0.5, Pitch = 1.1, Category = "Lobby"},  -- into the practice arena
	ArenaLeave     = {Off = true, Id = R .. "15675024286", Volume = 0.5, Pitch = 0.9, Category = "Lobby"},
	Purchase       = {Off = false, Id = R .. "134810204798705", Volume = 0.6, Pitch = 1, Category = "UI", MinGap = 0.3}, -- clicked to buy a game pass / dev product (plays instead of Click)
	Coins          = {Off = false, Id = R .. "133570405319995", Volume = 0.5, Pitch = 1, Category = "Lobby", MinGap = 0.1}, -- coins went up

	------------------------------------------------------------ MOVEMENT
	Slide          = {Off = false, Id = R .. "134781979035978", Volume = 0.45, Pitch = 1, PitchRandom = 0.05, Category = "Movement"},
	SlideJump      = {Off = false, Id = R .. "127183292018512", Volume = 0.4, Pitch = 1.3, Category = "Movement"},
	Crouch         = {Off = true, Id = R .. "15675037413", Volume = 0.25, Pitch = 0.8, Category = "Movement"},   -- crouching AND standing back up
	Climb          = {Off = true, Id = R .. "15675028888", Volume = 0.4, Pitch = 0.9, Category = "Movement"},   -- ledge climb
	Vault          = {Off = false, Id = R .. "15675024286", Volume = 0.4, Pitch = 1.2, Category = "Movement"},   -- hop over a low wall
	HardLand       = {Off = true, Id = R .. "125235091454234", Volume = 0.5, Pitch = 0.5, Category = "Movement", MinGap = 0.3}, -- big fall
	Trampoline     = {Off = true, Id = R .. "127183292018512", Volume = 0.5, Pitch = 1.1, PitchRandom = 0.08, Category = "Movement", MinGap = 0.2, MaxDistance = 80}, -- you + the trampoline dummies

	------------------------------------------------------------ AMBIENT (looping, heard near the thing)
	Conveyor       = {Off = true, Id = R .. "75177473015129", Volume = 0.15, Pitch = 1, Category = "Ambient", Looped = true, MaxDistance = 45},
}

return SoundConfig
