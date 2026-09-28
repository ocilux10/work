--[[
	MOVEMENT CONFIG
	Location: ReplicatedStorage > MovementConfig
	Used by:  StarterPlayer > StarterCharacterScripts > Movement
]]
local M = {}

---------------------------------------------------------------- KEYS
M.SprintKey = Enum.KeyCode.LeftShift   -- hold
M.CrouchKey = Enum.KeyCode.LeftControl -- works exactly like the slide key below
M.CrouchToggle = false        -- true = tap to crouch / tap again to stand (handy in Studio, where Ctrl+W/A/S/D are Studio shortcuts)
M.SlideKey = Enum.KeyCode.C             -- hold while SPRINTING = slide (as long as held), otherwise = crouch

---------------------------------------------------------------- SPEEDS
M.WalkSpeed = 16
M.SprintSpeed = 26
M.CrouchSpeed = 8
M.Acceleration = 70           -- how fast you speed up (studs/s per second). Higher = snappier
M.Deceleration = 90           -- how fast you slow down
M.SprintAnyDirection = true   -- true = sprint in any direction (W/A/S/D); false = forwards only

---------------------------------------------------------------- JUMPING / AIR
M.CarryMomentum = true        -- keep your speed in the air (slide-jumps and sprint-jumps stay fast)
M.MobileAutoSprint = true     -- phones / tablets always sprint, everywhere (there's no sprint key)
M.AirMomentumDecay = 6        -- how quickly that carried speed fades while airborne
M.CoyoteTime = 0.12           -- you can still jump this long after running off a ledge
M.JumpBuffer = 0.12           -- pressing jump slightly before landing still jumps

---------------------------------------------------------------- CROUCH / SLIDE
M.CrouchCameraDrop = 1.4
M.CrouchFootstepVolume = 0.15 -- footstep volume while crouch-walking (1 = normal, 0 = silent). Applies to everyone's footsteps
M.SlideCameraDrop = 2
M.SlideSpeed = 42             -- minimum starting slide speed (faster if you were already fast)
M.SlideFriction = 28          -- speed lost per second on flat ground (lower = a long held slide keeps more speed)
M.SlopeBoost = 90             -- extra speed gained sliding down slopes (lost going up)
M.SlideSteer = 2              -- how much you can steer a slide with A/D
M.SlideMaxTime = 1            -- slide lasts as long as you HOLD C / Ctrl, up to this many seconds (flat ground)
M.SlideMinTime = 0.15         -- a quick tap still slides at least this long
M.SlideDownhillMaxTime = 3    -- max hold time when sliding down a slope
M.SlideCooldown = 0.6
M.SlideMinSpeed = 10          -- must be moving at least this fast to slide (10 = works from a walk)
M.SlideJumpBoost = 8          -- extra forward speed when you jump out of a slide
M.LandingSlide = true         -- holding crouch when you land at speed goes straight into a slide
M.SlideAnimTime = 0.3         -- seconds the slide animation takes to play once (nil = its normal speed)
M.SlideAnimLoop = false

---------------------------------------------------------------- CLIMB + VAULT
M.ClimbRequiresSprint = true
M.ClimbReach = 2.5            -- how far above your waist a ledge can be while in the air
M.ClimbCheckDistance = 2.6
M.ClimbTime = 0.65
M.ClimbCooldown = 0.4
M.VaultEnabled = true         -- sprint into a waist/chest-high obstacle to hop onto it without jumping
M.VaultMinHeight = 1.6        -- studs above your feet
M.VaultMaxHeight = 4.5
M.VaultTime = 0.32

---------------------------------------------------------------- CAMERA FEEL
M.SprintFOVBoost = 12
M.SlideFOVBoost = 12
M.StrafeTilt = 2              -- degrees the camera leans when strafing (0 = off)
M.SlideTilt = 2              -- degrees the camera leans while sliding
M.LandingDip = 0.5            -- how much the camera dips on a hard landing (0 = off)
M.ClimbCameraPitch = 8        -- camera nods down as you pull yourself up

---------------------------------------------------------------- ANIMATIONS
M.Anims = {
	Run = "rbxassetid://120027936031994",
	Crouch = "rbxassetid://139646403065983",
	CrouchWalk = "rbxassetid://108680143346372",
	Slide = "rbxassetid://89615311779494",
	Climb = "rbxassetid://125095111836724",

	-- normal movement (these replace Roblox's default animations; leave "" to keep the Roblox default)
	Walk = "rbxassetid://75271648194142",
	Idle = "rbxassetid://77041112425450",
	Jump = "rbxassetid://118995119848870",
	Fall = "rbxassetid://71305990489517",
}

return M
