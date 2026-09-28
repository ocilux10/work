-- LOADING SCREEN SETTINGS (ReplicatedFirst > LoadingScreen, run by ReplicatedFirst > LoadingScreenClient)
local C = {}

-- one of these is picked at random each time the game loads (the FunFacs label)
C.Tips = {
	"Headshots Kill Players Instantly",
	"Hold C or Ctrl while sprinting to slide - let go to stop",
	"Sprint and jump into a wall to climb up onto it",
	"Break someone's 10+ win streak and the whole server hears about it",
	"Stuck? Rounds end in a draw after 1:30 - go for the kill",
}

-- MODE:
--   "Timed"  = the loading screen lasts exactly Length seconds, no matter what (assets still load behind it)
--   "Assets" = the sweep takes Length seconds but never gets ahead of the real loading (game, character,
--              major assets, the map around you) - a slow device can take longer, up to MaxLoadTime
C.Mode = "Assets"

-- LENGTH: seconds the white takes to sweep across the logo. The screen closes right after ("Loaded!" + fade).
C.Length = 10
C.MaxLoadTime = 15         -- slow devices: after this many seconds it finishes anyway (the rest loads in the background)
-- which way the white sweeps across the logo:
--   "LeftToRight"  "RightToLeft"  "TopToBottom"  "BottomToTop"
C.FillDirection = "TopToBottom"
C.FillAngle = 20           -- tilts the edge by this many degrees (0 = perfectly straight edge)
C.FillSoftness = 0.18      -- how soft the edge between white and grey is (0 = sharp line)
C.LoadedHoldTime = 0.5     -- how long "Loaded!" shows before it fades
C.FadeTime = 0.4

C.LoadingText = "Loading... %d%%"
C.LoadedText = "Loaded!"

-- the logo fills from grey to white, sweeping left to right, as things load
C.EmptyColor = Color3.fromRGB(84, 84, 84)
C.FullColor = Color3.fromRGB(255, 255, 255)

return C
