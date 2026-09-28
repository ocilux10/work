-- LIVE SPECTATE (server) - the SPECTATE wall in the lobby (Workspace > Lobby > Main > Edges)
-- Anyone in the lobby can watch any match running in THIS server: first person through a player's eyes, Q / E to
-- switch player, V freecam, M leave. The list of matches comes from MatchmakingServer (Matchmaking > LiveMatches).
-- Client: StarterPlayerScripts > LiveSpectateClient
-- While watching: your character stays frozen where you were in the lobby, and the map streams in around the
-- player you're watching (or your freecam).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local MM = RS:WaitForChild("Matchmaking")
local Remotes = MM:WaitForChild("Remotes")
local LiveFolder = MM:WaitForChild("LiveMatches", 30)

local Remote = Remotes:FindFirstChild("LiveSpectate") or Instance.new("RemoteFunction")
Remote.Name = "LiveSpectate"
Remote.Parent = Remotes
-- the freecam position is sent a few times a second (unreliable = fine if one is lost)
local CamRemote = Remotes:FindFirstChild("LiveSpectateCam") or Instance.new("UnreliableRemoteEvent")
CamRemote.Name = "LiveSpectateCam"
CamRemote.Parent = Remotes

local focusFolder = Instance.new("Folder")
focusFolder.Name = "SpectateFocus"
focusFolder.Parent = workspace

local watchers = {} -- [player] = {match = id, focus = Part, target = player?, anchored = {parts}}

local function inMatch(p, id)
	return p:GetAttribute("MatchId") == id
end

local function stop(p)
	local w = watchers[p]
	if not w then return end
	watchers[p] = nil
	if w.focus then w.focus:Destroy() end
	if p.Parent == Players then
		p.ReplicationFocus = nil
		p:SetAttribute("WatchingMatch", nil)
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and w.anchoredRoot == root then root.Anchored = false end
	end
end

local function start(p, id)
	if type(id) ~= "string" then return false, "?" end
	local f = LiveFolder and LiveFolder:FindFirstChild(id)
	if not f then return false, "That match just ended" end
	if p:GetAttribute("MatchId") ~= nil then return false, "You're in a match" end
	if p:GetAttribute("InArena") then return false, "Leave the practice arena first" end
	if p:GetAttribute("Searching") then return false, "Stop searching first" end
	stop(p)
	local focus = Instance.new("Part")
	focus.Name = p.Name
	focus.Anchored, focus.CanCollide, focus.CanQuery, focus.CanTouch = true, false, false, false
	focus.Transparency = 1
	focus.Size = Vector3.one
	focus.Parent = focusFolder
	local w = {match = id, focus = focus}
	watchers[p] = w
	-- freeze your own character in the lobby
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	-- (held in place: the lobby floor isn't loaded on the watcher's screen. Their client keeps it in its idle
	-- pose for everyone else - StarterCharacterScripts > Movement)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		w.anchoredRoot = root
	end
	p:SetAttribute("WatchingMatch", id)
	-- start the map streaming in around the first player straight away
	for _, other in Players:GetPlayers() do
		if inMatch(other, id) and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
			focus.Position = other.Character.HumanoidRootPart.Position
			break
		end
	end
	p.ReplicationFocus = focus
	pcall(function() p:RequestStreamAroundAsync(focus.Position, 5) end)
	return true
end

Remote.OnServerInvoke = function(p, action, arg)
	if action == "Watch" then
		return start(p, arg)
	elseif action == "Target" then
		-- who the spectator is looking through (the map streams in around them)
		local w = watchers[p]
		local t = typeof(arg) == "number" and Players:GetPlayerByUserId(arg)
		if w and t and inMatch(t, w.match) then w.target = t w.free = false end
		return true
	elseif action == "Stop" then
		stop(p)
		return true
	end
	return false
end

CamRemote.OnServerEvent:Connect(function(p, pos)
	local w = watchers[p]
	if w and typeof(pos) == "Vector3" and pos.Magnitude < 1e6 then
		w.free = true
		w.freePos = pos
	end
end)

-- how many people are watching each player (player attribute "Spectators": the eye + number on their screen)
local function countViewers()
	local counts = {}
	for p, w in watchers do
		if p.Parent == Players and w.target and not w.free then counts[w.target] = (counts[w.target] or 0) + 1 end
	end
	for _, p in Players:GetPlayers() do
		local n = counts[p]
		if p:GetAttribute("Spectators") ~= n then p:SetAttribute("Spectators", n) end
	end
end

-- keep the stream focus on whoever they're watching; send them home if the match ended
task.spawn(function()
	while true do
		task.wait(0.25)
		countViewers()
		for p, w in watchers do
			if p.Parent ~= Players then watchers[p] = nil if w.focus then w.focus:Destroy() end continue end
			if not (LiveFolder and LiveFolder:FindFirstChild(w.match)) or p:GetAttribute("MatchId") ~= nil then
				stop(p) -- match over (or they got pulled into a match themselves)
				continue
			end
			if w.free and w.freePos then
				w.focus.Position = w.freePos
			elseif w.target and w.target.Character and w.target.Character:FindFirstChild("HumanoidRootPart") then
				w.focus.Position = w.target.Character.HumanoidRootPart.Position
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	local w = watchers[p]
	watchers[p] = nil
	if w and w.focus then w.focus:Destroy() end
end)
-- respawning while watching (shouldn't happen, but) = stop watching
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function() if watchers[p] then stop(p) end end)
end)
for _, p in Players:GetPlayers() do
	p.CharacterAdded:Connect(function() if watchers[p] then stop(p) end end)
end
