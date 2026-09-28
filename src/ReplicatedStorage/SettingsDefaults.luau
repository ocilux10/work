-- SETTINGS DEFAULTS - what every NEW player starts with (and what the red X / Reset buttons go back to).
-- Just change a value and save. Players who already changed a setting keep their own choice.
--   true / false          on / off
--   numbers               sliders (stay inside the slider's range)
--   "#RRGGBB"             colours (hex, e.g. "#FF3B3B" = red)
--   "text"                a choice from the list shown in the comment
--   {"Key1", "Key2"}      keybinds: 2 slots, "" = empty
-- A line that starts with -- is switched off (the setting uses its built-in default).
-- (All the other details - names, ranges, which tab - are in ReplicatedStorage > GameSettings.)
return {

	-------------------------------- CONTROLS
	-- Controls
	Sensitivity = 1, -- Sensitivity  (0.1 - 3)
	AimAssist = true, -- Aim Assist
	-- AutoSprint = ..., -- Auto Sprint  (built-in default depends on the device / game config: IS_PHONE)
	-- InstantThrow = ..., -- Instant Throw  (built-in default depends on the device / game config: not IS_PHONE)
	-- Keybinds
	Key_MoveForward = {"W", "Up"}, -- Move Forward
	Key_MoveBackward = {"S", "Down"}, -- Move Backward
	Key_StrafeLeft = {"A", ""}, -- Strafe Left
	Key_StrafeRight = {"D", ""}, -- Strafe Right
	Key_Sprint = {"LeftShift", ""}, -- Sprint
	Key_Jump = {"Space", ""}, -- Jump / Vault
	Key_Crouch = {"C", "LeftControl"}, -- Crouch / Slide
	Key_Swing = {"MouseButton1", ""}, -- Melee
	Key_Shoot = {"MouseButton2", "Q"}, -- Throw Balloon
	Key_Inspect = {"F", ""}, -- Inspect Balloon
	Key_Scoreboard = {"Tab", ""}, -- Scoreboard
	Key_LeaveArena = {"G", ""}, -- Leave Practice Arena
	-- Spectate & Replays
	Key_SpectatePrev = {"Q", ""}, -- Previous Player
	Key_SpectateNext = {"E", ""}, -- Next Player
	Key_Freecam = {"V", ""}, -- Freecam
	Key_FreecamUp = {"E", ""}, -- Freecam Up
	Key_FreecamDown = {"Q", ""}, -- Freecam Down
	Key_ReplayPause = {"Space", ""}, -- Replay Pause
	Key_ReplayBack = {"Left", ""}, -- Replay Back 5s
	Key_ReplayForward = {"Right", ""}, -- Replay Forward 5s
	Key_ReplayPrevRound = {"Z", ""}, -- Replay Previous Round
	Key_ReplayNextRound = {"X", ""}, -- Replay Next Round
	Key_ReplaySpeed = {"T", ""}, -- Replay Speed

	-------------------------------- CROSSHAIR
	-- Lines
	CrossLines = false, -- Lines
	-- Center Dot
	DotStyle = "Dot", -- Dot Style  {Dot, Circle, Cross, None}
	DotSize = 5, -- Dot Size  (1 - 12)
	DotColor = "#FFFFFF", -- Dot Color
	-- Outline
	CrossOutline = true, -- Outline
	OutlineThickness = 1, -- Outline Thickness  (1 - 4)
	-- Hitmarker
	Hitmarker = true, -- Hitmarker
	HitmarkerStyle = "X", -- Hitmarker Type  {X, Plus, Ring, Dot}
	HitmarkerMatchCrosshair = true, -- Match Crosshair Color
	HitmarkerColor = "#FFFFFF", -- Hit Color
	HitmarkerHeadColor = "#FF3B3B", -- Headshot Color
	HitmarkerSize = 9, -- Hitmarker Size  (4 - 24)
	HitmarkerThickness = 2, -- Hitmarker Thickness  (1 - 6)
	HitmarkerDuration = 0.3, -- Hitmarker Duration  (0.1 - 1)
	HitmarkerSound = true, -- Hitmarker Sound

	-------------------------------- VIDEO
	-- Camera
	-- FOV = ..., -- FOV  (70 - 110)  (built-in default depends on the device / game config: combatFOV)
	CameraShake = true, -- Camera Motion
	-- Performance
	DisableShadows = false, -- Disable Ingame Shadows
	DisableMaterials = false, -- Disable Materials
	PerfStats = true, -- Performance Stats
	-- Player Visibility
	DummyEnemies = false, -- Dummy Enemies
	DummyTeammates = false, -- Dummy Teammates

	-------------------------------- AUDIO
	-- Volume
	SoundVolume = 100, -- Sound  (0 - 100)
	MusicVolume = 50, -- Music  (0 - 100)

	-------------------------------- OTHER
	-- Privacy
	PartyRequests = "Everyone", -- Party Requests  {Everyone, Friends, No one}
	DuelRequests = "Everyone", -- Duel Requests  {Everyone, Friends, No one}
	TradeRequests = "Everyone", -- Trade Requests  {Everyone, Friends, No one}
	AcceptGifts = true, -- Accept Gifts
	AllowJoins = true, -- Allow Joins (people who search your name can join your server)

	-------------------------------- CONTROLLER (Settings > Controls > Controller)
	-- button names: ButtonA (Cross), ButtonB (Circle), ButtonX (Square), ButtonY (Triangle), ButtonL1 / ButtonR1,
	-- ButtonL2 / ButtonR2 (triggers), ButtonL3 / ButtonR3 (stick clicks), ButtonSelect (Share / View), DPadUp / Down / Left / Right
	PadSensitivity = 1, -- Controller Sensitivity  (0.2 - 3)
	PadButtonStyle = "Auto", -- Button Names  {Auto, PlayStation, Xbox}
	Pad_Swing = {"ButtonR2", ""}, -- Melee (R2)
	Pad_Shoot = {"ButtonL2", ""}, -- Throw Balloon (L2)
	Pad_Sprint = {"ButtonL3", ""}, -- Sprint (L3, hold it down to sprint)
	Pad_Jump = {"ButtonA", ""}, -- Jump / Vault (Cross)
	Pad_Crouch = {"ButtonB", ""}, -- Crouch / Slide (Circle)
	Pad_Inspect = {"ButtonY", ""}, -- Inspect Balloon (Triangle)
	Pad_Scoreboard = {"ButtonSelect", ""}, -- Scoreboard (Share, hold)
	Pad_LeaveArena = {"DPadDown", ""}, -- Leave Practice Arena / leave spectating & replays
	Pad_SpectatePrev = {"ButtonL1", ""}, -- Previous Player
	Pad_SpectateNext = {"ButtonR1", ""}, -- Next Player
	Pad_Freecam = {"DPadUp", ""}, -- Freecam
	Pad_FreecamUp = {"ButtonR1", ""}, -- Freecam Up
	Pad_FreecamDown = {"ButtonL1", ""}, -- Freecam Down
	Pad_ReplayPause = {"ButtonX", ""}, -- Replay Pause (Square)
	Pad_ReplayBack = {"DPadLeft", ""}, -- Replay Back 5s
	Pad_ReplayForward = {"DPadRight", ""}, -- Replay Forward 5s
	Pad_ReplayPrevRound = {"ButtonL2", ""}, -- Replay Previous Round
	Pad_ReplayNextRound = {"ButtonR2", ""}, -- Replay Next Round
	Pad_ReplaySpeed = {"ButtonY", ""}, -- Replay Speed
}
