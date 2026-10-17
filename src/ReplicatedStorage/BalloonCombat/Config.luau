--[[
	BALLOON COMBAT CONFIG
	Location: ReplicatedStorage > BalloonCombat > Config

	Used by:
	  • ServerScriptService > BalloonCombatServer   (damage, cooldowns, ranges, health, ragdoll, dummies, XP)
	  • StarterPlayer > StarterPlayerScripts > BalloonCombatClient   (viewmodel, input cooldowns, shot visuals, pop FX)
	  • StarterGui > BalloonCombatUI > UIController   (damage numbers, kill popup, kill feed)

	Change a number here, press Play, done. Both the server and the clients read this module.
]]

local Config = {}

---------------------------------------------------------------- HEALTH
Config.MaxHealth = 100          -- total player HP
Config.HealthRegen = false      -- false = removes Roblox's default health regen
Config.RegenDelay = 7.5          -- seconds without taking damage before health starts coming back
Config.RegenPerSecond = 10      -- HP healed per second once regen kicks in (0 = no regen)

---------------------------------------------------------------- SHOOT (Right click, hitscan)
Config.HeadshotDamage = 999
Config.BodyshotDamage = 75
Config.ShootRange = 1000         -- studs
Config.InflateTime = 0.2        -- seconds the new balloon takes to inflate after the cooldown; can't shoot/swing until it's full
Config.ShootCooldown = 0.8      -- seconds until the balloon regrows in your hand (you can't swing while it's gone)
-- HOW EASY SHOTS ARE TO LAND: a shot also hits anyone within this many studs of your crosshair line
-- (walls still block it). 0 = pixel-perfect. ~1 = a bit forgiving, 1.5 = Knife Duels-ish, 2.5+ = very easy.
Config.ShotAssistRadius = 0.15
Config.ShootKey = Enum.KeyCode.Q   -- keyboard key that also shoots (as well as right click)

-- The visible balloon that flies to the hit point (purely visual, damage is instant)
Config.ShotVisualSpeed = 3000   -- studs per second the thrown balloon flies (visual only – hits are instant hitscan)
Config.ShotMaxTravelTime = 0.05 -- the visual balloon never takes longer than this to arrive, however far the shot
Config.DamageWaitsForBalloon = false -- false = damage numbers / hit highlight / kill popup show the instant you hit

-- SHOT TRAIL (streak behind the thrown balloon)
Config.ShotTrail = true           -- false = no trail
Config.ShotTrailWidth = 0.5       -- studs wide at the balloon (tapers to a point)
Config.ShotTrailLifetime = 0.25   -- how long the streak takes to fade (seconds)
Config.ShotTrailTransparency = 0.3 -- 0 = solid, 1 = invisible
Config.ShotTrailGlow = 0.6        -- 0 = flat colour, 1 = full glow
Config.ShotTrailColor = Color3.fromRGB(255, 255, 255)      -- nil = same colour as the balloon, or e.g. Color3.fromRGB(255, 255, 255)
Config.ShotVisualScale = 0.6    -- size multiplier of the flying balloon
Config.ShotVisualTransparency = 0.35 -- 0 = solid, 1 = invisible ("slightly visible")

---------------------------------------------------------------- CHARACTER ANIMATIONS (what other players see)
-- Played on your own character while you're in a fight (arena / match / practice) - they replicate to everyone.
-- Id = "" turns one off. Priority: Idle < Movement < Action < Action2 < Action3 < Action4 (higher wins on the
-- joints both animate). Speed = playback speed, Fade = seconds to blend in / out.
-- The sprint animation is MovementConfig > Anims > Run.
Config.Animations = {
	FightIdle = {Id = "rbxassetid://116417245303962", Priority = Enum.AnimationPriority.Idle,    Speed = 1, Fade = 0.2}, -- standing still, ready to fight
	ItemHold  = {Id = "rbxassetid://105311739259242", Priority = Enum.AnimationPriority.Action,  Speed = 1, Fade = 0.2}, -- holding the balloon (loops)
	Swing     = {Id = "rbxassetid://132292872755038", Priority = Enum.AnimationPriority.Action2, Speed = 1, Fade = 0.05}, -- melee (left click)
	Throw     = {Id = "rbxassetid://91209099309991", Priority = Enum.AnimationPriority.Action2, Speed = 1, Fade = 0.05}, -- shoot (right click)
}

---------------------------------------------------------------- MOBILE THROW (the Shoot button on phones)
-- Hold the button = aim (drag to turn), let go = throw. "Instant Throw" in Settings throws on touch instead.
-- While held, your arm goes into the HOLD pose below (first person), and HoldAnimationId plays on your
-- character (what other players see). Leave HoldAnimationId "" for no character animation.
Config.ThrowHold = {
	AnimationId = "",                    -- e.g. "rbxassetid://1234567890" (made in the Animation Editor, set to Action priority)
	AnimationSpeed = 1,
	FadeTime = 0.1,                      -- seconds to blend the animation in / out
	-- first-person pull-back pose (X right, Y up, Z back toward you; angles in degrees)
	PoseOffset = Vector3.new(0.25, 0.3, 0.45),
	PoseAngles = Vector3.new(30, -10, -15),
	PoseSpeed = 14,                      -- how fast the arm moves into / out of the pose (higher = snappier)
}

-- AIM ASSIST (phones, Settings > Controls > Aim Assist): while holding the throw button the camera gently
-- pulls toward the enemy closest to your crosshair.
Config.MobileAimAssist = {
	Strength = 0.35,    -- (= the Settings 'Aim Assist Strength' slider at 50; the slider goes x0.02 to x2) 0 = off, 0.2 = subtle, 0.35 = normal, 0.6 = strong, 1 = almost snaps on
	MaxAngle = 12,      -- degrees from the crosshair an enemy must be within to get pulled toward
	Range = 150,        -- studs
	AimAt = {"Torso", "UpperTorso"}, -- body parts it can pull to (Torso = R6, UpperTorso = R15 - characters here are R15). Add "Head" = headshot assist
	WallCheck = true,   -- true = no pull toward enemies behind walls
	Dummies = true,     -- true = also pull toward the practice arena dummies
}

---------------------------------------------------------------- MELEE (Left click, hitbox – no raycast)
Config.MeleeDamage = 75        -- same damage everywhere on the body
Config.MeleeCooldown = 0.75
Config.MeleeRange = 6           -- how far in front of you the hitbox reaches (studs)
Config.MeleeHitboxWidth = 5     -- width/height of the hitbox (studs)

---------------------------------------------------------------- PHYSICS
Config.RagdollOnDeath = true
Config.RagdollFling = 45        -- how hard the body gets launched by the killing hit
Config.RagdollUpwardFling = 18  -- extra upward pop on death

---------------------------------------------------------------- VIEWMODEL / CAMERA
Config.ForceFirstPerson = true
Config.ViewmodelBalloonScale = 0.45   -- balloon size in your first-person hands
Config.BalloonGripOffset = Vector3.new(0, 0, -0.25) -- where the knot sits on your hand (X right, Y up, Z back toward you)
Config.HoldArmRaise = 0               -- degrees the right arm is raised forward while holding the balloon (0 = arm hangs naturally)
                                      -- (only works where Roblox lets scripts move the shoulder joint - often it doesn't)
Config.HoldArmSway = 1                -- how much walking/running still moves the holding arm (0 = frozen, 1 = full swing)
Config.HeldBalloonScale = 0.7         -- balloon size other players see in your hand
-- HOW OTHER PLAYERS SEE YOUR BALLOON: gripped in your hand like an equipped item (no string).
-- Want the old look back (floating on a string above the hand)? HeldStringLength = 2.2, HeldBalloonSide = 0.9.
Config.HeldStringLength = 0           -- studs of string between the hand and the bottom of the balloon (0 = held in the hand, no string)
Config.HeldBalloonSide = 0            -- studs the balloon sits out to the side of the hand
Config.HeldInHandOffset = Vector3.new(0.1, 0.05, 0) -- held in hand: where the balloon's bottom sits from the fist (X right, Y up, Z back - as the character faces). It stays upright whatever the hold animation does
Config.HeldInHandTilt = 10            -- held in hand: degrees the balloon leans forward (away from you)
Config.HeldInHandLean = 12            -- held in hand: degrees the balloon leans out to the side, clear of the arm
Config.HeldStringColor = Color3.fromRGB(235, 235, 235)
Config.HeldStringWidth = 0.05
Config.ArmColor = Color3.fromRGB(20, 20, 20)   -- sleeve colour (Knife Duels style black)
Config.HandColor = nil                -- nil = use the player's skin colour
Config.ShirtOnArms = true            -- true = put the player's shirt texture on the first-person arms (looks blurry up close)
Config.CameraFOV = 90                   -- camera field of view (nil = leave default)
Config.SwingAnimTime = 0.50
Config.SwingCombo = false  -- true = every other swing is a backhand to the right; false = always the slash to the left
Config.ThrowAnimTime = 0.20
-- SPRINT ARM SWAY (first-person arms, only while sprinting)
Config.ArmSwingAmount = 1            -- overall strength (0 = off)
Config.ArmSwingUpDown = 0.30       -- how far the arms bob up and down (studs)
Config.ArmSwingForward = 0.3         -- small forward/back drift that goes with it
Config.ArmSwingTilt = 30              -- degrees the arms tip with each step
Config.ArmSwingSpeed = 1             -- rhythm multiplier (higher = faster steps)
Config.Sway = 1                        -- 0 = no weapon sway
-- FIRST-PERSON ARM LAYOUT (camera space: X right, Y up, Z back toward you - more negative Z = further forward)
Config.RightArmHandPos = Vector3.new(0.85, -0.55, -2.5)  -- where the right hand (balloon) sits
Config.LeftArmHandPos = Vector3.new(-0.85, -1.15, -2.2)  -- where the left hand sits (lower = points more down, Knife Duels style)
-- ARMS DIP WHILE SLIDING / CROUCHING (first person): both arms drop and tip down
Config.SlideArmDrop = {
	Offset = Vector3.new(0, -0.4, 0.25),  -- how far the arms move (down / back)
	Pitch = -16,                          -- degrees they tip down
	Roll = 6,                             -- degrees they lean in
	CrouchAmount = 0.6,                   -- crouching = this much of the slide pose (0 = no dip when crouching)
	Speed = 10,                           -- how fast it blends in / out
}

---------------------------------------------------------------- FX
-- SOUNDS moved: every sound in the game is now in ReplicatedStorage > SoundConfig
-- Red highlight on the player you hit (only YOU see it)
Config.HitHighlight = true
Config.HitHighlightTime = 0.5           -- seconds
Config.HitHighlightColor = Color3.fromRGB(255, 40, 40)          -- fill (inside) colour on the hit that KILLS
Config.HitHighlightSurviveColor = Color3.fromRGB(255, 255, 255) -- fill colour on a hit they survive
Config.HitHighlightOutlineColor = Color3.fromRGB(255, 255, 255)   -- outline colour
Config.HitHighlightFillTransparency = 0.45                      -- 0 = solid, 1 = no fill (outline only)
Config.HitHighlightOutlineTransparency = 1                      -- 0 = solid outline, 1 = no outline
Config.HitHighlightOnHeadshots = true -- false = body shots only
Config.DamageNumberLifetime = 0.9
Config.BodyDamageColor = Color3.fromRGB(255, 243, 197)   -- chest/body shots (white)
Config.HeadDamageColor = Color3.fromRGB(255, 60, 60)     -- headshots (red)
Config.MeleeDamageColor = Color3.fromRGB(255, 255, 255)

---------------------------------------------------------------- KILL FEED / XP
-- XP values are only DISPLAYED in the kill popup. Hook your own XP saving to the
-- "PlayerKilled" BindableEvent inside ServerScriptService > BalloonCombatServer.
Config.XP = {
	Kill = 50,
	Headshot = 25,
	Jumpshot = 25,
	Melee = 25,
	LongShot = 25,              -- bonus XP for a LONG SHOT kill
}
Config.LongShotDistance = 75    -- studs; balloon-shot kills from this far or further = LONG SHOT (melee never)
Config.KillPopupTime = 2.5
Config.KillFeedMaxLines = 5
Config.KillFeedLineTime = 6

---------------------------------------------------------------- MISC
Config.TeamCheck = true        -- true = can't damage teammates
Config.TrampolineBounceHeight = 75  -- studs the trampoline dummies bounce up
Config.TrampolineRespawnTime = 3    -- seconds before a killed trampoline dummy comes back
Config.ConveyorDummyCount = 6       -- dummies standing (still) on the practice conveyor
Config.ConveyorDummyRespawnTime = 3 -- seconds before a killed conveyor dummy comes back
Config.DummyRespawnTime = 3     -- NPC dummies in Workspace respawn after this many seconds (0 = never)
Config.BalloonName = "Balloon"  -- name of the balloon MeshPart in ServerStorage

-- Anti-exploit leniency for hitscan (higher = more forgiving on laggy players)
Config.HitTolerance = 8

return Config
