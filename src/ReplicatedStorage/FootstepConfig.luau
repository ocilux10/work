local C = {}

C.Enabled = false
C.Volume = 0.45                -- overall footstep volume
C.SprintVolume = 1.1           -- x volume while sprinting
C.CrouchVolume = 0.25          -- x volume while crouch-walking (sneaky)
C.PitchRandom = 0.03           -- +/- random pitch per step (small = consistent)
C.VolumeRandom = 0          -- +/- random volume per step (small = consistent)
C.StrideWalk = 13           -- studs between steps when walking
C.StrideSprint = 8         -- studs between steps when sprinting
C.LandVolume = 0.1               -- x volume of a step when you land from a jump / fall (0 = no landing thump)
C.HearDistance = 70            -- how far other players' steps can be heard (studs)

-- sound sets (Roblox audio ids). Add / remove ids freely.
-- TIP: keep every sound in a set from the SAME pack (same loudness + tone), or steps sound inconsistent.
C.Sets = {
	-- one soft, matching pack (4 takes of the same step) - used everywhere right now
	Main = {87061775498714},

	-- other floor types (not used unless you add them to Materials below)
	Hard = {87061775498714, 140594308250996, 139267724392327},
	Metal = {140728903346385, 139723537411614},
	Wood = {140525304232464},
	Grass = {110522236020035, 135037154891351, 140668467774841},
	Sand = {98912102275037},
	Snow = {135918121539048},
	Carpet = {91882016473062, 123224557798023, 131412978408311, 114768473003662}, -- fabric
}

-- which set each floor material uses (anything not listed uses Default).
-- Empty = the same consistent steps on every floor. Example to add later:  Grass = "Grass", Metal = "Metal",
C.Default = "Main"
C.Materials = {
}

return C
