-- SFX: plays the sounds listed in ReplicatedStorage > SoundConfig (edit sounds THERE, not here).
--   SFX.Play("Click")                 -- 2D (just you hear it)
--   SFX.Play("Pop", somePart)         -- 3D, from a part / attachment
--   SFX.Play("Pop", Vector3.new(...)) -- 3D, at a position
-- Returns the Sound (or nil if that sound is turned off). Client only.
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(script.Parent:WaitForChild("SoundConfig"))
local SFX = {}
SFX.Config = Config
-- a countdown tick: normal tick, or the harder one in the last few seconds
function SFX.Tick(secondsLeft)
	return SFX.Play(secondsLeft <= (Config.UrgentTickSeconds or 5) and "TimerTickUrgent" or "TimerTick")
end
local lastPlayed = {}

local function entry(name)
	local e = Config.Sounds[name]
	if not e or e.Off or not e.Id or e.Id == "" then return nil end
	return e
end

function SFX.Enabled(name) return entry(name) ~= nil end

-- Settings > SFX turns every sound effect off / on (this player only)
SFX.Muted = false
SFX.VolumeScale = 1 -- Settings > Audio > Sound (0 - 1)
function SFX.SetMuted(on) SFX.Muted = on == true end

function SFX.Play(name, where, opts)
	if RunService:IsServer() then return nil end
	if SFX.Muted then return nil end
	local e = entry(name)
	if not e then return nil end
	opts = opts or {}
	local now = os.clock()
	if e.MinGap and lastPlayed[name] and now - lastPlayed[name] < e.MinGap then return nil end
	lastPlayed[name] = now
	local s = Instance.new("Sound")
	s.Name = "SFX_" .. name
	s.SoundId = e.Id
	s.Volume = (e.Volume or 0.5) * (opts.Volume or 1) * (Config.MasterVolume or 1) * (SFX.VolumeScale or 1) * ((Config.CategoryVolume or {})[e.Category or ""] or 1)
	local pr = e.PitchRandom or 0
	s.PlaybackSpeed = ((e.Pitch or 1) + pr * (math.random() * 2 - 1)) * (opts.Pitch or 1)
	s.Looped = e.Looped == true
	if e.Start then s.TimePosition = e.Start end
	local holder
	if typeof(where) == "Instance" and (where:IsA("BasePart") or where:IsA("Attachment")) then
		s.RollOffMaxDistance = e.MaxDistance or 150
		s.RollOffMinDistance = e.MinDistance or 8
		s.Parent = where
	elseif typeof(where) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.WorldPosition = where
		holder.Parent = workspace.Terrain
		s.RollOffMaxDistance = e.MaxDistance or 150
		s.RollOffMinDistance = e.MinDistance or 8
		s.Parent = holder
	else
		s.Parent = SoundService
	end
	s:Play()
	if not s.Looped then
		s.Ended:Connect(function() s:Destroy() if holder then holder:Destroy() end end)
		Debris:AddItem(holder or s, e.MaxLength or 12)
	end
	return s
end

-- load every sound up front so the first play isn't silent / late
if not RunService:IsServer() then
	task.spawn(function()
		local list = {}
		for _, e in Config.Sounds do
			if e.Id and e.Id ~= "" then
				local s = Instance.new("Sound")
				s.SoundId = e.Id
				table.insert(list, s)
			end
		end
		pcall(function() ContentProvider:PreloadAsync(list) end)
	end)
end

return SFX
