-- GAME SETTINGS (client): every setting in the Settings menu, its default, and saving.
--   local GS = require(game.ReplicatedStorage.GameSettings)
--   GS.Get("FOV")  GS.Set("FOV", 90)  GS.Reset("FOV")  GS.ResetTab("Video")  GS.Changed:Connect(function(key, value) end)
-- KEYBINDS: GS.Is("Shoot", input) -> this input is bound to Shoot?   GS.IsDown("Sprint") -> held right now?
--   Keys are saved as names ("W", "LeftShift", "MouseButton1"). Two slots per action.
-- Everything is saved in the player's data as one "Prefs" value (ServerScriptService > SettingsServer).
-- ADD A SETTING: add a line to DEFS (it shows up in the menu by itself) and read it with GS.Get where it's used.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local GS = {}

-- Type: Toggle / Slider (Min, Max, Step) / Cycle (Options) / Color (Options) / Keybind (Default = {slot1, slot2})
-- PCOnly = hidden on phones / tablets
-- HideWhen = {"OtherKey", value}: the row hides while that other setting has that value
-- LiveLabel / LiveSub: text that follows the current crosshair shape ({Style} = "Cross", {style} = "cross"),
--   and GS.LiveSections renames a section heading the same way
-- DEFAULTS: the easy place to change what new players start with is ReplicatedStorage > SettingsDefaults
local combatFOV = 85
pcall(function() combatFOV = require(game:GetService("ReplicatedStorage"):WaitForChild("BalloonCombat"):WaitForChild("Config")).CameraFOV or 85 end)

GS.Tabs = {"Controls", "Crosshair", "Video", "Audio", "Other"}
GS.LiveSections = {["Center Dot"] = "Center {Style}"}
-- {Style} = the crosshair shape you're using right now (DotStyle; "None" still reads "Dot")
function GS.LiveText(t)
	if type(t) ~= "string" then return t end
	local s = GS.Get and GS.Get("DotStyle") or "Dot"
	if s == nil or s == "None" or s == "Image" then s = "Dot" end
	return (t:gsub("{Style}", s):gsub("{style}", s:lower()))
end
-- phones / tablets (no keyboard): Auto Sprint starts ON for them, and MobileOnly settings only show there
local IS_PHONE = (function() local ok, uis = pcall(game.GetService, game, "UserInputService") return ok and uis.TouchEnabled and not uis.KeyboardEnabled or false end)()
GS.Defs = {
	-- CONTROLS
	{Tab = "Controls", Section = "Controls", Key = "Sensitivity", Type = "Slider", Default = 1, Min = 0.1, Max = 3, Step = 0.1, Label = "Sensitivity", Sub = "Camera look speed"},
	{Tab = "Controls", Section = "Controls", Key = "AimAssist", Type = "Toggle", Default = true, Label = "Aim Assist", Sub = "Pulls your aim toward enemies (phones and controllers)", MobileOnly = true, PadToo = true},
	{Tab = "Controls", Section = "Controls", Key = "AutoSprint", Type = "Toggle", Default = IS_PHONE, Label = "Auto Sprint", Sub = IS_PHONE and "Sprint while moving, or toggle it with the sprint button" or "Always sprint while moving"},
	{Tab = "Controls", Section = "Controls", Key = "InstantThrow", Type = "Toggle", Default = not IS_PHONE, Label = "Instant Throw", Sub = IS_PHONE and "Throw the moment you touch the button instead of on release" or "Throw on press instead of hold-and-release"},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_MoveForward", Type = "Keybind", Default = {"W", "Up"}, Label = "Move Forward", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_MoveBackward", Type = "Keybind", Default = {"S", "Down"}, Label = "Move Backward", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_StrafeLeft", Type = "Keybind", Default = {"A", ""}, Label = "Strafe Left", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_StrafeRight", Type = "Keybind", Default = {"D", ""}, Label = "Strafe Right", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Sprint", Type = "Keybind", Default = {"LeftShift", ""}, Label = "Sprint", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Jump", Type = "Keybind", Default = {"Space", ""}, Label = "Jump / Vault", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Crouch", Type = "Keybind", Default = {"C", "LeftControl"}, Label = "Crouch / Slide", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Swing", Type = "Keybind", Default = {"MouseButton1", ""}, Label = "Melee", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Shoot", Type = "Keybind", Default = {"MouseButton2", "Q"}, Label = "Throw Balloon", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Inspect", Type = "Keybind", Default = {"F", ""}, Label = "Inspect Balloon", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_Scoreboard", Type = "Keybind", Default = {"Tab", ""}, Label = "Scoreboard", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_LeaveArena", Type = "Keybind", Default = {"G", ""}, Label = "Leave Practice Arena", PCOnly = true},
	{Tab = "Controls", Section = "Keybinds", Key = "Key_AimMenu", Type = "Keybind", Default = {"M", ""}, Label = "Aim Training Menu", PCOnly = true, Shared = true},
	-- SPECTATE + REPLAYS (leaving uses the Leave Practice Arena key above)
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_SpectatePrev", Type = "Keybind", Default = {"Q", ""}, Label = "Previous Player", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_SpectateNext", Type = "Keybind", Default = {"E", ""}, Label = "Next Player", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_Freecam", Type = "Keybind", Default = {"V", ""}, Label = "Freecam", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_FreecamUp", Type = "Keybind", Default = {"E", ""}, Label = "Freecam Up", PCOnly = true, Shared = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_FreecamDown", Type = "Keybind", Default = {"Q", ""}, Label = "Freecam Down", PCOnly = true, Shared = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplayPause", Type = "Keybind", Default = {"Space", ""}, Label = "Replay Pause", PCOnly = true, Shared = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplayBack", Type = "Keybind", Default = {"Left", ""}, Label = "Replay Back 5s", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplayForward", Type = "Keybind", Default = {"Right", ""}, Label = "Replay Forward 5s", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplayPrevRound", Type = "Keybind", Default = {"Z", ""}, Label = "Replay Previous Round", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplayNextRound", Type = "Keybind", Default = {"X", ""}, Label = "Replay Next Round", PCOnly = true},
	{Tab = "Controls", Section = "Spectate & Replays", Key = "Key_ReplaySpeed", Type = "Keybind", Default = {"T", ""}, Label = "Replay Speed", PCOnly = true},
	-- CROSSHAIR
	{Tab = "Crosshair", Section = "Lines", Key = "CrossLines", Type = "Toggle", Default = false, Label = "Lines", Sub = "Show lines around the center dot"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "DotStyle", Type = "Cycle", Default = "Dot", Options = {"Dot", "Circle", "Cross", "Image", "None"}, Label = "Dot Style", Sub = "Shape of the center dot", LiveLabel = "{Style} Style", LiveSub = "Shape of the center {style}"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "DotSize", Type = "Slider", Default = 5, Min = 1, Max = 12, Step = 1, Label = "Dot Size", Sub = "Size of the center dot", LiveLabel = "{Style} Size", LiveSub = "Size of the center {style}"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "DotColor", Type = "Color", Default = "#FFFFFF", Label = "Dot Color", Sub = "Color of the crosshair (click to pick)", LiveLabel = "{Style} Color"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "CrosshairImage", Type = "Text", Default = "", ShowWhen = {"DotStyle", "Image"}, Label = "Crosshair ID", Sub = "Paste an image / decal ID + Enter"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "CrosshairImageSize", Type = "Slider", Default = 32, Min = 8, Max = 128, Step = 1, ShowWhen = {"DotStyle", "Image"}, Label = "Image Size", Sub = "How big your crosshair image is"},
	{Tab = "Crosshair", Section = "Center Dot", Key = "CrosshairImageTint", Type = "Toggle", Default = false, ShowWhen = {"DotStyle", "Image"}, Label = "Color The Image", Sub = "Tint it with the Dot Color (for white images)"},
	{Tab = "Crosshair", Section = "Outline", Key = "CrossOutline", Type = "Toggle", Default = true, Label = "Outline", Sub = "Dark outline around the crosshair"},
	{Tab = "Crosshair", Section = "Outline", Key = "OutlineThickness", Type = "Slider", Default = 1, Min = 1, Max = 4, Step = 0.5, Label = "Outline Thickness", Sub = "How thick the outline is"},
	{Tab = "Crosshair", Section = "Reload Bar", Key = "ReloadStyle", Type = "Cycle", Default = "Bar", Options = {"Bar", "Vertical", "Ring", "Dot"}, Label = "Reload Shape", Sub = "Bar, upright bar, ring or dot"},
	{Tab = "Crosshair", Section = "Reload Bar", Key = "ReloadColor", Type = "Color", Default = "#FFC828", Label = "Reload Color", Sub = "The part that fills up (click to pick)"},
	{Tab = "Crosshair", Section = "Reload Bar", Key = "ReloadBackColor", Type = "Color", Default = "#141414", Label = "Background Color", Sub = "The empty part behind it (click to pick)"},
	{Tab = "Crosshair", Section = "Reload Bar", Key = "ReloadSize", Type = "Slider", Default = 1, Min = 0.5, Max = 3, Step = 0.1, Label = "Reload Size", Sub = "How big it is"},
	{Tab = "Crosshair", Section = "Reload Bar", Key = "ReloadDistance", Type = "Slider", Default = 14, Min = 0, Max = 60, Step = 1, Label = "Reload Distance", Sub = "How far from the crosshair"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "Hitmarker", Type = "Toggle", Default = true, Label = "Hitmarker", Sub = "An X flashes on your crosshair when you hit someone"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerStyle", Type = "Cycle", Default = "X", Options = {"X", "Plus", "Ring", "Dot"}, Label = "Hitmarker Type", Sub = "Shape of the hitmarker"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerMatchCrosshair", Type = "Toggle", Default = true, Label = "Match Crosshair Color", Sub = "Use your crosshair's color for every hit"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerColor", Type = "Color", Default = "#FFFFFF", HideWhen = {"HitmarkerMatchCrosshair", true}, Label = "Hit Color", Sub = "Color for body hits and melee (click to pick)"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerHeadColor", Type = "Color", Default = "#FF3B3B", HideWhen = {"HitmarkerMatchCrosshair", true}, Label = "Headshot Color", Sub = "Color for headshots (click to pick)"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerSize", Type = "Slider", Default = 9, Min = 4, Max = 24, Step = 1, Label = "Hitmarker Size", Sub = "How long the lines are"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerThickness", Type = "Slider", Default = 2, Min = 1, Max = 6, Step = 0.5, Label = "Hitmarker Thickness", Sub = "How thick the lines are"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerDuration", Type = "Slider", Default = 0.3, Min = 0.1, Max = 1, Step = 0.05, Label = "Hitmarker Duration", Sub = "How long it stays on screen (seconds)"},
	{Tab = "Crosshair", Section = "Hitmarker", Key = "HitmarkerSound", Type = "Toggle", Default = true, Label = "Hitmarker Sound", Sub = "A tick sound with every hit"},
	-- VIDEO
	{Tab = "Video", Section = "Camera", Key = "FOV", Type = "Slider", Default = combatFOV, Min = 70, Max = 110, Step = 1, Label = "FOV", Sub = "Field of view in the arena and matches"},
	{Tab = "Video", Section = "Camera", Key = "CameraShake", Type = "Toggle", Default = true, Label = "Camera Motion", Sub = "Tilt, landing dip and movement feedback"},
	{Tab = "Video", Section = "Performance", Key = "DisableShadows", Type = "Toggle", Default = false, Label = "Disable Ingame Shadows", Sub = "Turns off world shadows"},
	{Tab = "Video", Section = "Performance", Key = "DisableMaterials", Type = "Toggle", Default = false, Label = "Disable Materials", Sub = "Simplifies part materials"},
	{Tab = "Video", Section = "Performance", Key = "PerfStats", Type = "Toggle", Default = true, Label = "Performance Stats", Sub = "Show FPS and ping in the corner"},
	{Tab = "Video", Section = "Player Visibility", Key = "DummyEnemies", Type = "Toggle", Default = false, Label = "Dummy Enemies", Sub = "Show enemies as plain dummies in matches"},
	{Tab = "Video", Section = "Player Visibility", Key = "DummyTeammates", Type = "Toggle", Default = false, Label = "Dummy Teammates", Sub = "Show teammates as plain dummies in matches"},
	-- AUDIO
	{Tab = "Audio", Section = "Volume", Key = "SoundVolume", Type = "Slider", Default = 100, Min = 0, Max = 100, Step = 5, Label = "Sound", Sub = "Master volume"},
	{Tab = "Audio", Section = "Volume", Key = "MusicVolume", Type = "Slider", Default = 50, Min = 0, Max = 100, Step = 5, Label = "Music", Sub = "Background music"},
	-- OTHER
	{Tab = "Other", Section = "Privacy", Key = "PartyRequests", Type = "Cycle", Default = "Everyone", Options = {"Everyone", "Friends", "No one"}, Label = "Party Requests", Sub = "Who can invite you to a party"},
	{Tab = "Other", Section = "Privacy", Key = "DuelRequests", Type = "Cycle", Default = "Everyone", Options = {"Everyone", "Friends", "No one"}, Label = "Duel Requests", Sub = "Who can ask to 1v1"},
	{Tab = "Other", Section = "Privacy", Key = "TradeRequests", Type = "Cycle", Default = "Everyone", Options = {"Everyone", "Friends", "No one"}, Label = "Trade Requests", Sub = "Who can ask to trade"},
	{Tab = "Other", Section = "Privacy", Key = "AcceptGifts", Type = "Toggle", Default = true, Label = "Accept Gifts", Sub = "Let other players gift you coins"},
	{Tab = "Other", Section = "Privacy", Key = "JoinRequests", Type = "Cycle", Default = "Everyone", Options = {"Everyone", "Friends", "No one"}, Label = "Joins", Sub = "Who can join your server from search"},
	{Tab = "Other", Section = "Menus", Key = "MenuBalloonFX", Type = "Toggle", Default = true, Label = "Balloon Effects", Sub = "Glow, rings and sparkles on balloon pictures in menus"},
	-- AIM TRAINING (its own menu: StarterGui > AimTrainingUI > AimTrainingFrame, tabs Target / Movement / Box / Challenge)
	-- Text = a text box, Button = a button row (Action is sent to the menu's "Action" event)
	{Tab = "Target", Section = "Target", Key = "AimType", Type = "Cycle", Default = "Bot", Options = {"Bot", "Disc", "Orbs"}, Label = "Target Type", Sub = "Bots, a bullseye disc or floating orbs"},
	{Tab = "Target", Section = "Target", Key = "AimScenario", Type = "Cycle", Default = "Strafe", Options = {"Custom", "Still", "Strafe", "Wide Strafe", "Slow Strafe", "Jumpy", "All Over"}, Label = "Scenario", Sub = "Ready-made setups (fills in the Movement tab)"},
	{Tab = "Target", Section = "Target", Key = "AimCount", Type = "Slider", Default = 1, Min = 1, Max = 6, Step = 1, Label = "How Many", Sub = "Targets at the same time"},
	{Tab = "Target", Section = "Target", Key = "AimDistance", Type = "Slider", Default = 45, Min = 10, Max = 150, Step = 1, Label = "Distance", Sub = "How far the box is from you (studs)"},
	{Tab = "Target", Section = "Target", Key = "AimOrbSize", Type = "Slider", Default = 2, Min = 0.5, Max = 5, Step = 0.5, Label = "Orb Size", Sub = "Size of the floating orbs"},
	{Tab = "Target", Section = "You", Key = "AimReload", Type = "Toggle", Default = true, Label = "Reload Cooldown", Sub = "Off = your balloon comes back straight away"},
	{Tab = "Target", Section = "Bot", Key = "AimAvatar", Type = "Text", Default = "", Label = "Bot Avatar", Sub = "Type a username + Enter (empty = Noob)"},
	{Tab = "Target", Section = "Bot", Key = "AimShootBack", Type = "Toggle", Default = false, Label = "Bots Throw Back", Sub = "Bots throw balloons at you (dodge practice)"},
	{Tab = "Target", Section = "Bot", Key = "AimShootRate", Type = "Slider", Default = 2, Min = 0.5, Max = 6, Step = 0.5, Label = "Throw Every", Sub = "Seconds between their throws"},
	{Tab = "Target", Section = "Bot", Key = "AimShootAccuracy", Type = "Slider", Default = 50, Min = 0, Max = 100, Step = 5, Label = "Their Accuracy", Sub = "How often their throws hit you (%)"},
	{Tab = "Target", Section = "Bot", Key = "AimShootHeadshot", Type = "Slider", Default = 25, Min = 0, Max = 100, Step = 5, Label = "Their Headshots", Sub = "How many of their hits are headshots (%) - 100 + 100 accuracy = every throw kills"},
	{Tab = "Movement", Section = "Movement", Key = "AimMoving", Type = "Toggle", Default = true, Label = "Moving", Sub = "Off = they stand still"},
	{Tab = "Movement", Section = "Movement", Key = "AimSpeed", Type = "Slider", Default = 16, Min = 2, Max = 32, Step = 1, Label = "Walk Speed", Sub = "How fast they move"},
	{Tab = "Movement", Section = "Movement", Key = "AimLeftRight", Type = "Toggle", Default = true, Label = "Left / Right", Sub = "Strafe side to side"},
	{Tab = "Movement", Section = "Movement", Key = "AimForwardBack", Type = "Toggle", Default = false, Label = "Forward / Back", Sub = "Move toward you and away"},
	{Tab = "Movement", Section = "Movement", Key = "AimStrafeAngle", Type = "Slider", Default = 0, Min = -80, Max = 80, Step = 5, Label = "Strafe Angle", Sub = "Tilts their strafe line (0 = straight across)"},
	{Tab = "Movement", Section = "Movement", Key = "AimStrafeMin", Type = "Slider", Default = 3, Min = 1, Max = 30, Step = 1, Label = "Shortest Strafe", Sub = "Shortest distance before changing direction"},
	{Tab = "Movement", Section = "Movement", Key = "AimStrafeMax", Type = "Slider", Default = 10, Min = 1, Max = 40, Step = 1, Label = "Longest Strafe", Sub = "Longest distance before changing direction"},
	{Tab = "Movement", Section = "Movement", Key = "AimPause", Type = "Slider", Default = 0.1, Min = 0, Max = 2, Step = 0.05, Label = "Pause", Sub = "Stop time between strafes (seconds)"},
	{Tab = "Movement", Section = "Movement", Key = "AimJump", Type = "Toggle", Default = false, Label = "Jumping", Sub = "They jump sometimes"},
	{Tab = "Movement", Section = "Movement", Key = "AimJumpChance", Type = "Slider", Default = 30, Min = 5, Max = 100, Step = 5, Label = "Jump Chance", Sub = "Chance to jump on each strafe (%)"},
	{Tab = "Box", Section = "Box", Key = "AimBoxShow", Type = "Toggle", Default = true, Label = "Show Box", Sub = "They can never leave it, even when it's hidden"},
	{Tab = "Box", Section = "Box", Key = "AimBoxWidth", Type = "Slider", Default = 30, Min = 6, Max = 90, Step = 1, Label = "Width", Sub = "Side to side (studs)"},
	{Tab = "Box", Section = "Box", Key = "AimBoxDepth", Type = "Slider", Default = 12, Min = 4, Max = 60, Step = 1, Label = "Depth", Sub = "Toward you and away (studs)"},
	{Tab = "Box", Section = "Box", Key = "AimBoxHeight", Type = "Slider", Default = 10, Min = 4, Max = 40, Step = 1, Label = "Height", Sub = "How tall (orbs float inside it)"},
	{Tab = "Box", Section = "Box", Key = "AimBoxColor", Type = "Color", Default = "#4FC3FF", Label = "Box Color", Sub = "Click to pick"},
	{Tab = "Box", Section = "Box", Key = "AimBoxTransparency", Type = "Slider", Default = 0.85, Min = 0, Max = 1, Step = 0.05, Label = "Box See-Through", Sub = "1 = only the outline"},
	{Tab = "Box", Section = "Box", Key = "AimBoxOutline", Type = "Toggle", Default = true, Label = "Outline", Sub = "Lines around the edges"},
	{Tab = "Challenge", Section = "Timed Challenge", Key = "AimChallengeKills", Type = "Slider", Default = 20, Min = 5, Max = 100, Step = 5, Label = "Kills To Finish", Sub = "Kill this many as fast as you can"},
	{Tab = "Challenge", Section = "Timed Challenge", Key = "AimStartChallenge", Type = "Button", Action = "StartChallenge", Label = "Start Challenge", Sub = "3, 2, 1 then the timer runs", ButtonText = "Start"},
	{Tab = "Challenge", Section = "Stats", Key = "AimResetStats", Type = "Button", Action = "ResetStats", Label = "Reset Stats", Sub = "Hits, accuracy and kills back to 0", ButtonText = "Reset"},
	{Tab = "Challenge", Section = "Room", Key = "AimLeave", Type = "Button", Action = "Leave", Label = "Leave Aim Training", Sub = "Back to the lobby", ButtonText = "Leave"},
}
GS.AimTabs = {"Target", "Movement", "Box", "Challenge"}
GS.ColorValues = {
	White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(255, 70, 70), Green = Color3.fromRGB(80, 255, 120),
	Cyan = Color3.fromRGB(70, 230, 255), Yellow = Color3.fromRGB(255, 230, 60), Pink = Color3.fromRGB(255, 110, 220),
	Orange = Color3.fromRGB(255, 160, 50),
}
-- colour settings are saved as "#RRGGBB" (old saves may still hold a name above)
function GS.ToColor(v)
	if type(v) == "string" then
		if GS.ColorValues[v] then return GS.ColorValues[v] end
		local ok, c = pcall(Color3.fromHex, v)
		if ok then return c end
	end
	return Color3.new(1, 1, 1)
end
-- CONTROLLER: every keyboard action also gets a controller button (Settings > Controls > Controller, rebindable).
-- Defaults here (PlayStation names in the comments). Movement / camera stay on the sticks.
GS.PadDefaults = {
	Sprint = "ButtonL3",       -- L3
	Jump = "ButtonA",          -- X / A
	Crouch = "ButtonB",        -- Circle / B  (slide while sprinting)
	Swing = "ButtonR2",        -- R2 melee
	Shoot = "ButtonL2",        -- L2 throw
	Inspect = "ButtonY",       -- Triangle / Y
	Scoreboard = "ButtonSelect", -- Share / View (hold)
	AimMenu = "DPadRight",     -- aim training menu (only in aim training)
	LeaveArena = "DPadDown",
	SpectatePrev = "ButtonL1", SpectateNext = "ButtonR1", Freecam = "DPadUp",
	FreecamUp = "ButtonR1", FreecamDown = "ButtonL1",
	ReplayPause = "ButtonX",   -- Square / X
	ReplayBack = "DPadLeft", ReplayForward = "DPadRight",
	ReplayPrevRound = "ButtonL2", ReplayNextRound = "ButtonR2", ReplaySpeed = "ButtonY",
}
-- (spectate / replay buttons only work while watching, so they may share buttons with the fight controls)
local PAD_SHARED = {AimMenu = true, SpectatePrev = true, SpectateNext = true, Freecam = true, FreecamUp = true, FreecamDown = true, ReplayPause = true,
	ReplayBack = true, ReplayForward = true, ReplayPrevRound = true, ReplayNextRound = true, ReplaySpeed = true}
do
	local extra = {
		{Tab = "Controls", Section = "Controller", Key = "PadSensitivity", Type = "Slider", Default = 1, Min = 0.2, Max = 3, Step = 0.1, Label = "Controller Sensitivity", Sub = "How fast the right stick turns the camera", PadOnly = true},
		{Tab = "Controls", Section = "Controller", Key = "PadButtonStyle", Type = "Cycle", Default = "Auto", Options = {"Auto", "PlayStation", "Xbox"}, Label = "Button Names", Sub = "Show PlayStation or Xbox button names", PadOnly = true},
	}
	for _, d in GS.Defs do
		local action = d.Key:match("^Key_(.+)$")
		if action and GS.PadDefaults[action] then
			table.insert(extra, {Tab = "Controls", Section = "Controller", Key = "Pad_" .. action, Type = "Keybind", Pad = true, PadOnly = true,
				Default = {GS.PadDefaults[action], ""}, Label = d.Label, Shared = PAD_SHARED[action] or d.Shared})
		end
	end
	for _, e in extra do table.insert(GS.Defs, e) end
end

-- ReplicatedStorage > SettingsDefaults: one simple line per setting ("Key = value") overrides the Default above
pcall(function()
	local overrides = require(game:GetService("ReplicatedStorage"):WaitForChild("SettingsDefaults", 5))
	if type(overrides) ~= "table" then return end
	for _, d in GS.Defs do
		local short = d.Key:gsub("^Key_", "")
		local v = overrides[d.Key]
		if v == nil and d.Type == "Keybind" then v = overrides[short] end
		if v ~= nil then
			if d.Type == "Keybind" and type(v) == "string" then v = {v, ""} end
			if d.Type == "Keybind" and type(v) == "table" then v = {v[1] or "", v[2] or ""} end
			if d.Type == "Color" and typeof(v) == "Color3" then v = "#" .. v:ToHex() end
			d.Default = v
		end
	end
end)
GS.ByKey = {}
for _, d in GS.Defs do GS.ByKey[d.Key] = d end

local changed = Instance.new("BindableEvent")
GS.Changed = changed.Event
local values = {}

local function copy(v) if type(v) == "table" then return table.clone(v) end return v end
local function same(a, b)
	if type(a) == "table" and type(b) == "table" then
		for i = 1, math.max(#a, #b) do if (a[i] or "") ~= (b[i] or "") then return false end end
		return true
	end
	return a == b
end

function GS.Get(key)
	local v = values[key]
	if v == nil then local d = GS.ByKey[key] return d and copy(d.Default) end
	return copy(v)
end
function GS.IsDefault(key)
	local d = GS.ByKey[key]
	return d == nil or same(GS.Get(key), d.Default)
end

-- saving: one Prefs string, a moment after the last change
local player = Players.LocalPlayer
local saveToken = 0
local function save()
	if not player then return end
	saveToken += 1
	local my = saveToken
	task.delay(0.6, function()
		if my ~= saveToken then return end
		local remote = game:GetService("ReplicatedStorage"):WaitForChild("Matchmaking"):WaitForChild("Remotes"):WaitForChild("SaveSetting")
		local ok, json = pcall(HttpService.JSONEncode, HttpService, values)
		if ok then
			GS._lastSaved = json
			remote:FireServer("Prefs", json)
		end
	end)
end

function GS.Set(key, v)
	local d = GS.ByKey[key]
	if not d then return end
	if d.Type == "Slider" then
		v = math.clamp(math.floor(v / d.Step + 0.5) * d.Step, d.Min, d.Max)
		v = tonumber(string.format("%.2f", v))
	end
	if same(GS.Get(key), v) then return end
	if same(v, d.Default) then values[key] = nil else values[key] = copy(v) end
	changed:Fire(key, GS.Get(key))
	save()
end
function GS.Reset(key)
	local d = GS.ByKey[key]
	if d then GS.Set(key, copy(d.Default)) end
end
function GS.ResetTab(tab)
	for _, d in GS.Defs do if d.Tab == tab then GS.Reset(d.Key) end end
end

------------------------------------------------------------ KEYBINDS
local function inputName(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then return input.KeyCode.Name end
	if input.UserInputType == Enum.UserInputType.Gamepad1 then return input.KeyCode.Name end
	return input.UserInputType.Name -- MouseButton1 / MouseButton2 / MouseButton3
end
GS.InputName = inputName
-- CONTROLLER: is the player using a controller right now? (last thing they touched was a gamepad)
local PAD_TYPES = {[Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true, [Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true}
function GS.UsingGamepad()
	-- (Studio testing without a controller: set the player's ForcePad attribute to true)
	if player and player:GetAttribute("ForcePad") and RunService:IsStudio() then return true end
	local ok, t = pcall(function() return UIS:GetLastInputType() end)
	return ok and PAD_TYPES[t] == true
end
-- when the player switches between keyboard and controller, key hints everywhere refresh (they listen for "Key_...")
if RunService:IsClient() then
	local wasPad = GS.UsingGamepad()
	UIS.LastInputTypeChanged:Connect(function()
		local now = GS.UsingGamepad()
		if now ~= wasPad then
			wasPad = now
			changed:Fire("Key_InputMode", now)
		end
	end)
	if player then
		player:GetAttributeChangedSignal("ForcePad"):Connect(function()
			wasPad = GS.UsingGamepad()
			changed:Fire("Key_InputMode", wasPad)
		end)
	end
end

-- the buttons SHOWN for an action (keyboard keys, or controller buttons while using a controller)
function GS.Keys(action)
	if GS.UsingGamepad() and GS.ByKey["Pad_" .. action] then return GS.Get("Pad_" .. action) or {} end
	return GS.Get("Key_" .. action) or {}
end
-- does this input trigger the action? (keyboard / mouse binds AND controller binds both work)
function GS.Is(action, input)
	local n = inputName(input)
	for _, k in GS.Get("Key_" .. action) or {} do if k ~= "" and k == n then return true end end
	if PAD_TYPES[input.UserInputType] then
		for _, k in GS.Get("Pad_" .. action) or {} do if k ~= "" and k == n then return true end end
	end
	return false
end
function GS.IsDown(action)
	for _, k in GS.Get("Key_" .. action) or {} do
		if k ~= "" then
			if k:find("^MouseButton") then
				if UIS:IsMouseButtonPressed(Enum.UserInputType[k]) then return true end
			else
				local ok, code = pcall(function() return Enum.KeyCode[k] end)
				if ok and code and UIS:IsKeyDown(code) then return true end
			end
		end
	end
	for _, k in GS.Get("Pad_" .. action) or {} do
		if k ~= "" then
			local ok, code = pcall(function() return Enum.KeyCode[k] end)
			if ok and code then
				for pad in PAD_TYPES do
					local ok2, down = pcall(function() return UIS:IsGamepadButtonDown(pad, code) end)
					if ok2 and down then return true end
				end
			end
		end
	end
	return false
end
-- short text for a key box ("LSHIFT", "M1" ...)
local SHORT = {LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL", LeftAlt = "LALT",
	RightAlt = "RALT", MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3", Return = "ENTER", Backspace = "BKSP",
	Space = "SPACE", Up = "UP", Down = "DOWN", Left = "LEFT", Right = "RIGHT", CapsLock = "CAPS"}
local PAD_XBOX = {ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT",
	ButtonR2 = "RT", ButtonL3 = "LS", ButtonR3 = "RS", ButtonStart = "MENU", ButtonSelect = "VIEW",
	DPadUp = "D-UP", DPadDown = "D-DOWN", DPadLeft = "D-LEFT", DPadRight = "D-RIGHT"}
local PAD_PS = {ButtonA = "CROSS", ButtonB = "CIRCLE", ButtonX = "SQUARE", ButtonY = "TRIANGLE", ButtonL1 = "L1", ButtonR1 = "R1",
	ButtonL2 = "L2", ButtonR2 = "R2", ButtonL3 = "L3", ButtonR3 = "R3", ButtonStart = "OPTIONS", ButtonSelect = "SHARE",
	DPadUp = "D-UP", DPadDown = "D-DOWN", DPadLeft = "D-LEFT", DPadRight = "D-RIGHT"}
local function padStyle()
	local s = GS.Get and GS.Get("PadButtonStyle") or "Auto"
	if s == "PlayStation" or s == "Xbox" then return s end
	-- Auto: Roblox names the buttons after the controller that's plugged in
	local ok, str = pcall(function() return UIS:GetStringForKeyCode(Enum.KeyCode.ButtonA) end)
	if ok and type(str) == "string" and (str:find("Cross") or str:find("✕")) then return "PlayStation" end
	return "Xbox"
end
function GS.KeyText(name)
	if not name or name == "" then return "" end
	if PAD_XBOX[name] then return (padStyle() == "PlayStation" and PAD_PS or PAD_XBOX)[name] end
	return SHORT[name] or string.upper(name)
end
function GS.IsPadKey(name) return PAD_XBOX[name] ~= nil end
-- the real button picture (Circle / B ...) for a controller key, following Settings > Button Names. nil = not a pad key
local CTRL = "rbxasset://textures/ui/Controls/"
local IMG_PS = {ButtonA = "ButtonCross", ButtonB = "ButtonCircle", ButtonX = "ButtonSquare", ButtonY = "ButtonTriangle",
	ButtonL1 = "ButtonL1", ButtonR1 = "ButtonR1", ButtonL2 = "ButtonL2", ButtonR2 = "ButtonR2", ButtonL3 = "ButtonL3", ButtonR3 = "ButtonR3",
	ButtonStart = "PS5/ButtonOptions", ButtonSelect = "PS5/ButtonShare", DPadUp = "DPadUp", DPadDown = "DPadDown", DPadLeft = "DPadLeft", DPadRight = "DPadRight"}
local IMG_XBOX = {ButtonA = "ButtonA", ButtonB = "ButtonB", ButtonX = "ButtonX", ButtonY = "ButtonY", ButtonL1 = "ButtonLB", ButtonR1 = "ButtonRB",
	ButtonL2 = "ButtonLT", ButtonR2 = "ButtonRT", ButtonL3 = "ButtonLS", ButtonR3 = "ButtonRS", ButtonStart = "ButtonStart", ButtonSelect = "ButtonSelect",
	DPadUp = "DPadUp", DPadDown = "DPadDown", DPadLeft = "DPadLeft", DPadRight = "DPadRight"}
function GS.KeyImage(name)
	if not name or not IMG_PS[name] then return nil end
	-- (D-pad: the PlayStation pictures don't show which direction, so both use the ones with the arrow)
	if name:sub(1, 4) == "DPad" then return CTRL .. "XboxController/" .. IMG_XBOX[name] .. "@2x.png" end
	if padStyle() == "PlayStation" then return CTRL .. "PlayStationController/" .. IMG_PS[name] .. "@2x.png" end
	return CTRL .. "XboxController/" .. IMG_XBOX[name] .. "@2x.png"
end
-- the first controller button bound to an action ("" = none)
function GS.PadKey(action)
	for _, k in GS.Get("Pad_" .. action) or {} do if k ~= "" then return k end end
	return ""
end

------------------------------------------------------------ LOAD
local function load()
	if not player then return end
	local raw = player:GetAttribute("Setting_Prefs")
	if type(raw) ~= "string" or raw == GS._lastSaved then return end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(t) ~= "table" then return end
	local old = values
	values = {}
	for k, v in t do if GS.ByKey[k] then values[k] = v end end
	for _, d in GS.Defs do
		local a, b = old[d.Key], values[d.Key]
		if not same(a == nil and d.Default or a, b == nil and d.Default or b) then changed:Fire(d.Key, GS.Get(d.Key)) end
	end
end
if RunService:IsClient() and player then
	load()
	player:GetAttributeChangedSignal("Setting_Prefs"):Connect(load)
end

return GS
