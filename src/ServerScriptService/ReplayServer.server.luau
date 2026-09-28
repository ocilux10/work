-- REPLAYS (server) - watching your last 20 matches (recorded by MatchmakingServer, stored by ServerStorage > Replays)
-- "Watch": the match's map is copied far away just for you, with a stand-in character for everyone who played;
-- your screen (StarterPlayerScripts > ReplayClient) moves them through the recording. Your own character waits,
-- frozen, in the lobby. Settings: MAX_SESSIONS below, and ReplayOffset in Matchmaking > Config.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local MM = RS:WaitForChild("Matchmaking")
local Config = require(MM:WaitForChild("Config"))
local Remotes = MM:WaitForChild("Remotes")
local Replays = require(SS:WaitForChild("Replays"))
local MapsFolder = SS:WaitForChild("Maps")
local BalloonTemplate = RS:WaitForChild("BalloonCombat"):WaitForChild("BalloonTemplate")

local MAX_SESSIONS = 8 -- replays being watched at once in one server (each has its own copy of a map)
local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

local Remote = Remotes:FindFirstChild("Replays") or Instance.new("RemoteFunction")
Remote.Name = "Replays"
Remote.Parent = Remotes
local Changed = Remotes:FindFirstChild("ReplaysChanged") or Instance.new("RemoteEvent")
Changed.Name = "ReplaysChanged"
Changed.Parent = Remotes
local CamRemote = Remotes:FindFirstChild("ReplayCam") or Instance.new("UnreliableRemoteEvent")
CamRemote.Name = "ReplayCam"
CamRemote.Parent = Remotes

local root = Instance.new("Folder")
root.Name = "ReplaySessions"
root.Parent = workspace

local sessions = {} -- [player] = {folder, slot, focus, anchoredRoot}
local usedSlots = {}
local descCache = {}

Replays.OnListChanged(function(userId)
	local p = Players:GetPlayerByUserId(userId)
	if p then Changed:FireClient(p) end
end)

local function ghostFor(userId, rig)
	local desc = descCache[userId]
	if not desc then
		local ok, d = pcall(function() return Players:GetHumanoidDescriptionFromUserId(math.max(userId, 1)) end)
		desc = ok and d or Instance.new("HumanoidDescription")
		descCache[userId] = desc
	end
	-- same body type as in the match (the movement animations only fit that rig)
	local rigType = rig == "R6" and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, rigType) end)
	if not ok or not model then return nil end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Anchored = d.Name == "HumanoidRootPart"
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
		if not hum:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = hum end
	end
	-- a balloon in their hand, like in the match
	local arm = model:FindFirstChild("Right Arm") or model:FindFirstChild("RightHand")
	if arm then
		local b = BalloonTemplate:Clone()
		b.Name = "HeldBalloon"
		for _, d in b:GetDescendants() do if d:IsA("Beam") or d:IsA("Script") then d:Destroy() end end
		if b:IsA("BasePart") then
			b.Size *= 0.6
			b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.Massless = false, false, false, false, true
			b.CFrame = arm.CFrame * CFrame.new(0.9, arm.Name == "RightHand" and 2 or 2.6, 0)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = arm, b
			w.Parent = b
			b.Parent = model
		else
			b:Destroy()
		end
	end
	return model
end

local function stop(p)
	local s = sessions[p]
	if not s then return end
	sessions[p] = nil
	usedSlots[s.slot] = nil
	if s.folder then s.folder:Destroy() end
	if p.Parent == Players then
		p.ReplicationFocus = nil
		p:SetAttribute("WatchingReplay", nil)
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and s.anchoredRoot == r then r.Anchored = false end
	end
end

local function watch(p, id)
	if p:GetAttribute("MatchId") ~= nil then return nil, "You're in a match" end
	if p:GetAttribute("InArena") then return nil, "Leave the practice arena first" end
	if p:GetAttribute("WatchingMatch") then return nil, "Stop spectating first" end
	-- only replays in your own list
	local mine = false
	for _, r in Replays.List(p.UserId) do if r.Id == id then mine = true break end end
	if not mine then return nil, "That replay isn't in your list any more" end
	stop(p)
	local count = 0
	for _ in sessions do count += 1 end
	if count >= MAX_SESSIONS then return nil, "Too many replays playing right now, try again soon" end
	local rep, json = Replays.Get(id)
	if not rep then return nil, "Couldn't load that replay" end
	local template = MapsFolder:FindFirstChild(rep.Model or "") or MapsFolder:FindFirstChild(rep.Map or "")
	if not template then return nil, "That map doesn't exist any more" end

	local slot = 1
	while usedSlots[slot] do slot += 1 end
	usedSlots[slot] = true
	local origin = CFrame.new((Config.ArenaOrigin or Vector3.new(0, 500, 5000)) + (Config.ReplayOffset or Vector3.new(0, 0, 3000))
		+ Vector3.new((slot - 1) * (Config.ArenaSpacing or 1000), 0, 0))
	local folder = Instance.new("Model")
	folder.Name = "Replay_" .. p.UserId
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Default
	local map = template:Clone()
	map.Name = "Map"
	map:PivotTo(origin)
	for _, d in map:GetDescendants() do if d:IsA("BaseScript") then d:Destroy() end end
	map.Parent = folder
	local ghosts = Instance.new("Folder")
	ghosts.Name = "Ghosts"
	ghosts.Parent = folder
	local s = {folder = folder, slot = slot}
	sessions[p] = s
	for _, person in rep.People or {} do
		local g = ghostFor(person.UserId, person.Rig)
		if g then
			g.Name = tostring(person.UserId)
			g:PivotTo(origin * CFrame.new(0, -500, 0)) -- hidden until the client places it
			g.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
			g.Parent = ghosts
			pcall(function() g:AddPersistentPlayer(p) end) -- always sent to the viewer, wherever the camera is
		end
	end
	if sessions[p] ~= s then folder:Destroy() return nil, "Cancelled" end
	-- focus: the map streams in around it (moved by the client's camera)
	local focus = Instance.new("Part")
	focus.Name = "Focus"
	focus.Anchored, focus.CanCollide, focus.CanQuery, focus.CanTouch, focus.Transparency = true, false, false, false, 1
	focus.Size = Vector3.one
	focus.CFrame = origin
	focus.Parent = folder
	s.focus = focus
	folder.Parent = root
	-- freeze your own character in the lobby
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	-- (held in place: the lobby floor isn't loaded on the watcher's screen. Their client keeps it in its idle
	-- pose for everyone else - StarterCharacterScripts > Movement)
	if r then r.AssemblyLinearVelocity = Vector3.zero r.Anchored = true s.anchoredRoot = r end
	p.ReplicationFocus = focus
	pcall(function() p:RequestStreamAroundAsync(origin.Position, 5) end)
	p:SetAttribute("WatchingReplay", id)
	return {Session = folder.Name, Origin = {origin:GetComponents()}, Json = json}
end

Remote.OnServerInvoke = function(p, action, arg)
	if action == "List" then
		return Replays.List(p.UserId)
	elseif action == "Watch" then
		if IS_MATCH_SERVER then return nil, "Replays can be watched in the lobby" end
		return watch(p, arg)
	elseif action == "Stop" then
		stop(p)
		return true
	elseif action == "Delete" then
		-- the bin on a row (after "Are you sure?"): off your list for good
		if p:GetAttribute("WatchingReplay") == arg then stop(p) end
		local okk = Replays.Delete(p.UserId, arg)
		if not okk then return nil, "Couldn't delete that replay" end
		return true
	end
	return nil
end

CamRemote.OnServerEvent:Connect(function(p, pos)
	local s = sessions[p]
	if s and s.focus and typeof(pos) == "Vector3" and (pos - s.focus.Position).Magnitude < 3000 then s.focus.Position = pos end
end)

Players.PlayerRemoving:Connect(stop)
local function hookChar(p) p.CharacterAdded:Connect(function() if sessions[p] then stop(p) end end) end
Players.PlayerAdded:Connect(hookChar)
for _, p in Players:GetPlayers() do hookChar(p) end
-- pulled into a match while watching -> stop
task.spawn(function()
	while true do
		task.wait(1)
		for p in sessions do if p:GetAttribute("MatchId") ~= nil or p:GetAttribute("InArena") then stop(p) end end
	end
end)

