-- MATCHMAKING SERVER
-- Queue pads -> 3s ready check -> black fade + logo -> map vote -> rounds (first to 6) -> XP -> back to lobby.
-- Settings: ReplicatedStorage > Matchmaking > Config
-- Maps:     ServerStorage > Maps (each needs Spawns > Team1 / Team2 and a "Spectate" part)
--
-- HOW THE QUEUE AREAS ARE FOUND (works wherever they live in Workspace, e.g. inside Lobby):
--   * every Model named "Match<N>v<N>" with a Ui > Main1 / Main2 / ModeLabel is a sign
--   * the closest "MatchmakingPad" to a sign is its pad; the pad's two circle Models are the two sides
--   * each circle belongs to whichever board (Main1 = Team 1, Main2 = Team 2) is closest to it

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MM = RS:WaitForChild("Matchmaking")
local Config = require(MM:WaitForChild("Config"))
local PlayerCard = require(MM:WaitForChild("PlayerCard"))
local Remotes = MM:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent")
local VoteRemote = Remotes:WaitForChild("Vote")
local DeviceRemote = Remotes:WaitForChild("Device")
local LeaveEndScreen = Remotes:WaitForChild("LeaveEndScreen")

local PlayerData = require(SS:WaitForChild("PlayerData"))
local Quests = require(SS:WaitForChild("Quests")) -- daily quests (settings: ReplicatedStorage > QuestConfig)
local MapsFolder = SS:WaitForChild("Maps")
local PlayerKilled = script.Parent:WaitForChild("BalloonCombatServer"):WaitForChild("PlayerKilled")
local PlayerDamaged = script.Parent.BalloonCombatServer:WaitForChild("PlayerDamaged")
local TextChatService = game:GetService("TextChatService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local GREEN = Color3.fromRGB(40, 255, 120)

-- HOOKS for ServerScriptService > GlobalMatchmaking (the Play-menu cross-server queue)
--   StartMatch (BindableFunction): start a match here with these teams      -> Invoke({players}, {players})
--   SendToLobby (BindableEvent): in a match server, a player is done -> teleport them to a lobby
--   StreakEnded (BindableEvent): someone's 10+ win streak was just broken (for the announcements)
local Hooks = script:FindFirstChild("Hooks") or Instance.new("Folder")
Hooks.Name = "Hooks"
Hooks.Parent = script
local function hook(class, name)
	local h = Hooks:FindFirstChild(name) or Instance.new(class)
	h.Name = name
	h.Parent = Hooks
	return h
end
local StartMatchHook = hook("BindableFunction", "StartMatch")
local SendToLobbyHook = hook("BindableEvent", "SendToLobby")
local StreakEndedHook = hook("BindableEvent", "StreakEnded")
-- a private server made by the matchmaker = a match server (players go back to a lobby after)
local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

local ActiveFolder = workspace:FindFirstChild("ActiveMatches") or Instance.new("Folder")
ActiveFolder.Name = "ActiveMatches"
ActiveFolder.Parent = workspace

------------------------------------------------------------ HELPERS
local function now() return workspace:GetServerTimeNow() end

local function infoOf(p)
	return {
		UserId = p.UserId,
		Name = NameBadge.Of(p),
		Level = p:GetAttribute("Level") or 1,
		Device = p:GetAttribute("Device") or "PC",
		Streak = p:GetAttribute("WinStreak") or 0,
	}
end

local function aliveChar(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return char, hum, root end
end

local function freeze(p, on)
	-- frozen players also can't swing / shoot (BalloonCombat checks "CombatLocked")
	p:SetAttribute("CombatLocked", on or nil)
	p:SetAttribute("Frozen", on or nil) -- Movement script: no walking / jumping / sliding / crouching at all
	local _, hum, root = aliveChar(p)
	if root then root.Anchored = on end
	if hum and not on then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
end

local function teleport(p, cf)
	local char = p.Character
	if not char then return end
	pcall(function() p:RequestStreamAroundAsync(cf.Position, 5) end)
	char:PivotTo(cf)
end

------------------------------------------------------------ DEVICES
DeviceRemote.OnServerEvent:Connect(function(p, device)
	if device == "PC" or device == "Mobile" or device == "Console" then
		p:SetAttribute("Device", device)
	end
end)

------------------------------------------------------------ QUEUE AREAS
local areas = {}

local function boardGui(part)
	return part and part:FindFirstChildOfClass("SurfaceGui")
end

-- how much to spin the avatar tiles so they stand upright, whatever way the board part is rotated
local function uprightRotation(part, gui)
	local cf = part.CFrame
	local right, up
	local face = gui.Face
	if face == Enum.NormalId.Back then right, up = cf.RightVector, cf.UpVector
	elseif face == Enum.NormalId.Front then right, up = -cf.RightVector, cf.UpVector
	elseif face == Enum.NormalId.Right then right, up = cf.LookVector, cf.UpVector
	elseif face == Enum.NormalId.Left then right, up = -cf.LookVector, cf.UpVector
	else return 0 end
	return math.deg(math.atan2(Vector3.yAxis:Dot(right), Vector3.yAxis:Dot(up)))
end

local function flatDist(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function setupAreas()
	local signs, pads = {}, {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d.Name:match("^Match%dv%d$") and d:FindFirstChild("Ui") then
			table.insert(signs, d)
		elseif d:IsA("Model") and d.Name == "MatchmakingPad" then
			table.insert(pads, d)
		end
	end
	for _, sign in signs do
		local ui = sign.Ui
		local main1, main2 = ui:FindFirstChild("Main1"), ui:FindFirstChild("Main2")
		if not (main1 and main2) then continue end
		local teamSize = tonumber(sign.Name:match("^Match(%d)v"))
		local signPos = (main1.Position + main2.Position) / 2
		-- closest pad
		local pad, best
		for _, p in pads do
			local d = flatDist(p:GetBoundingBox().Position, signPos)
			if not best or d < best then pad, best = p, d end
		end
		if not pad then continue end
		-- the two circles = child Models with several parts
		local circles = {}
		for _, c in pad:GetChildren() do
			if c:IsA("Model") then
				local n = 0
				for _, bp in c:GetDescendants() do if bp:IsA("BasePart") then n += 1 end end
				if n >= 3 then table.insert(circles, c) end
			end
		end
		if #circles < 2 then
			warn("[Matchmaking] pad for " .. sign:GetFullName() .. " doesn't have 2 circle models")
			continue
		end
		local area = {sign = sign, teamSize = teamSize, sides = {}, members = {{}, {}}, fullSince = nil, starting = false}
		area.modeLabel = ui:FindFirstChild("ModeLabel")
		local modeText = area.modeLabel and boardGui(area.modeLabel) and boardGui(area.modeLabel):FindFirstChildOfClass("TextLabel")
		area.modeText = modeText
		area.modeOriginal = modeText and modeText.Text or ""
		local countPart = ui:FindFirstChild("CountLabel")
		area.countText = countPart and boardGui(countPart) and boardGui(countPart):FindFirstChildOfClass("TextLabel")
		for i = 1, 2 do
			local circle = circles[i]
			local cf, size = circle:GetBoundingBox()
			-- the box can be rotated (circle models are often built lying on their side), so work out
			-- how big it really is along the world X / Y / Z axes
			local half = size / 2
			local function worldHalf(axis)
				return math.abs(cf.RightVector:Dot(axis)) * half.X + math.abs(cf.UpVector:Dot(axis)) * half.Y + math.abs(cf.LookVector:Dot(axis)) * half.Z
			end
			local hx, hy, hz = worldHalf(Vector3.xAxis), worldHalf(Vector3.yAxis), worldHalf(Vector3.zAxis)
			local team = flatDist(cf.Position, main1.Position) <= flatDist(cf.Position, main2.Position) and 1 or 2
			local neon = {}
			for _, bp in circle:GetDescendants() do
				if bp:IsA("BasePart") and bp.Material == Enum.Material.Neon then
					table.insert(neon, {part = bp, color = bp.Color})
				end
			end
			-- the client (QueuePadColors) paints the circles green/red from these
			circle:SetAttribute("QueueArea", #areas + 1)
			circle:SetAttribute("QueueTeam", team)
			circle:SetAttribute("QueueMembers", "")
			circle:SetAttribute("QueueSize", teamSize) -- players per side (1v1 = 1 ... 4v4 = 4)
			circle:SetAttribute("QueueMode", sign.Name:match("^Match(%dv%d)$"))
			CollectionService:AddTag(circle, "QueueCircle")
			area.sides[team] = {
				circle = circle,
				center = cf.Position,
				-- footprint of the circle, generous so it's easy to step on (Config.PadMargin studs extra)
				halfX = hx + (Config.PadMargin or 3), halfZ = hz + (Config.PadMargin or 3),
				topY = cf.Position.Y + hy,
				board = boardGui(team == 1 and main1 or main2),
				rotation = boardGui(team == 1 and main1 or main2) and uprightRotation(team == 1 and main1 or main2, boardGui(team == 1 and main1 or main2)) or 0,
				neon = neon,
			}
		end
		if area.sides[1] and area.sides[2] then
			table.insert(areas, area)
		else
			warn("[Matchmaking] both circles of " .. sign:GetFullName() .. " matched the same board")
		end
	end
	print(("[Matchmaking] %d queue areas ready"):format(#areas))
end

local function onSide(side, pos)
	local rx, rz = math.abs(pos.X - side.center.X), math.abs(pos.Z - side.center.Z)
	-- ellipse test inside the circle's footprint
	local inside = (rx / side.halfX) ^ 2 + (rz / side.halfZ) ^ 2 <= 1
	local dy = pos.Y - side.topY
	return inside and dy > -4 and dy < Config.PadHeight
end

local function canQueue(p)
	-- (not while searching from the Play menu either)
	return p:GetAttribute("MatchId") == nil and not p:GetAttribute("InArena") and not p:GetAttribute("Searching") and aliveChar(p) ~= nil
end

local function renderArea(area)
	local total = 0
	for team = 1, 2 do
		local side = area.sides[team]
		local list = area.members[team]
		total += #list
		if side.board then
			for i = 1, area.teamSize do
				local slot = side.board:FindFirstChild("Slot" .. i)
				if slot then
					local p = list[i]
					local key = p and (p.UserId .. ":" .. tostring(p:GetAttribute("Level")) .. ":" .. tostring(p:GetAttribute("Device")) .. ":" .. tostring(p:GetAttribute("WinStreak"))) or ""
					if slot:GetAttribute("Shown") ~= key then
						slot:SetAttribute("Shown", key)
						PlayerCard.Fill(slot, p and infoOf(p) or nil, {Rotation = side.rotation})
					end
				end
			end
		end
		local ids = {}
		for _, p in list do table.insert(ids, tostring(p.UserId)) end
		local members = #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or ""
		if side.circle:GetAttribute("QueueMembers") ~= members then
			side.circle:SetAttribute("QueueMembers", members)
		end
	end
	if area.countText then area.countText.Text = total .. "/" .. (area.teamSize * 2) end
end

local startMatch -- defined below

local function queueTick()
	local claimed = {}
	for _, area in areas do
		if area.starting then continue end
		for team = 1, 2 do
			local side = area.sides[team]
			local list = area.members[team]
			-- drop players who stepped off / died / left
			for i = #list, 1, -1 do
				local p = list[i]
				local _, _, root = aliveChar(p)
				if p.Parent ~= Players or not canQueue(p) or not root or not onSide(side, root.Position) then
					table.remove(list, i)
				end
			end
			for _, p in list do claimed[p] = true end
		end
	end
	-- add new players (first come, first served; extra players on a full side just wait)
	for _, p in Players:GetPlayers() do
		if claimed[p] or not canQueue(p) then continue end
		local _, _, root = aliveChar(p)
		for _, area in areas do
			if area.starting then continue end
			local placed = false
			for team = 1, 2 do
				if onSide(area.sides[team], root.Position) and #area.members[team] < area.teamSize then
					table.insert(area.members[team], p)
					placed = true
					break
				end
			end
			if placed then break end
		end
	end
	-- ready check
	for _, area in areas do
		if area.starting then continue end
		renderArea(area)
		local full = #area.members[1] == area.teamSize and #area.members[2] == area.teamSize
		-- Config.SoloTest: one person is enough (Studio playtests only)
		if Config.SoloTest and RunService:IsStudio() and (#area.members[1] + #area.members[2]) > 0 then
			full = true
		end
		if full then
			area.fullSince = area.fullSince or os.clock()
			local left = Config.ReadyTime - (os.clock() - area.fullSince)
			if area.modeText then area.modeText.Text = tostring(math.max(1, math.ceil(left))) end
			if left <= 0 then
				area.fullSince = nil
				if area.modeText then area.modeText.Text = area.modeOriginal end
				local t1, t2 = table.clone(area.members[1]), table.clone(area.members[2])
				area.members = {{}, {}}
				renderArea(area)
				startMatch(t1, t2, area)
			end
		else
			if area.fullSince and area.modeText then area.modeText.Text = area.modeOriginal end
			area.fullSince = nil
		end
	end
end

------------------------------------------------------------ MATCHES
local matchByPlayer = {} -- [player] = match
local mvpScore, pickMVP, lineUp, crownMVP -- MVP helpers (defined near startMatch)
-- coins from level ups during a match (shown on the end screen's LevelUpFrame)
PlayerData.OnLevelUp(function(p, fromLevel, toLevel, coins)
	local m = matchByPlayer[p]
	local li = m and m.levelInfo and m.levelInfo[p]
	if li then li.Coins += coins or 0 end
end)
local usedSlots = {}

-- MATCH STATS on the player (read by the Tab scoreboard): MatchKills / MatchDeaths / MatchAssists
local function setStat(match, p, key, value)
	local st = match.stats[p]
	if not st then return end
	st[key] = value
	if p.Parent == Players then p:SetAttribute("Match" .. key, value) end
end
local function addStat(match, p, key, n)
	local st = match.stats[p]
	if st then setStat(match, p, key, (st[key] or 0) + (n or 1)) end
end

------------------------------------------------------------ MATCH CHAT
-- In a match you only chat with the people in it (TextChatService channel "Match_<id>").
-- Back in the lobby you're put back into the normal chat.
local function channelsFolder()
	return TextChatService:FindFirstChild("TextChannels")
end
local function removeFromChannel(channel, p)
	if not channel then return end
	for _, src in channel:GetChildren() do
		if src:IsA("TextSource") and src.UserId == p.UserId then src:Destroy() end
	end
end
local function chatJoinMatch(match, p)
	local folder = channelsFolder()
	if not folder then return end
	if not match.chat then
		local ch = Instance.new("TextChannel")
		ch.Name = "Match_" .. match.id
		ch.Parent = folder
		match.chat = ch
	end
	local function inChannel(ch)
		if not ch then return false end
		for _, src in ch:GetChildren() do
			if src:IsA("TextSource") and src.UserId == p.UserId then return true end
		end
		return false
	end
	-- someone who JUST joined the server (match servers) isn't fully set up for chat yet, and Roblox adds them to
	-- the normal chat a moment later - so keep making sure for a while: in the match channel, out of the lobby one
	local t0 = os.clock()
	repeat
		if not inChannel(match.chat) then pcall(function() match.chat:AddUserAsync(p.UserId) end) end
		if inChannel(match.chat) then
			removeFromChannel(folder:FindFirstChild("RBXGeneral"), p)
			if p:GetAttribute("MatchChannel") ~= match.chat.Name then p:SetAttribute("MatchChannel", match.chat.Name) end
		end
		task.wait(0.5)
	until os.clock() - t0 > 12 or p.Parent ~= Players or matchByPlayer[p] ~= match or not match.chat
end
local function chatLeaveMatch(match, p)
	if match and match.chat then removeFromChannel(match.chat, p) end
	if p.Parent ~= Players then return end
	p:SetAttribute("MatchChannel", nil)
	local folder = channelsFolder()
	local general = folder and folder:FindFirstChild("RBXGeneral")
	if general then
		local already = false
		for _, src in general:GetChildren() do
			if src:IsA("TextSource") and src.UserId == p.UserId then already = true end
		end
		if not already then pcall(function() general:AddUserAsync(p.UserId) end) end
	end
end

------------------------------------------------------------ KILL REPLAY RECORDING
-- Every match keeps the last few seconds of where everyone's body parts were + where they were aiming,
-- plus the shots fired, so the match-winning kill can be replayed from the killer's eyes.
local allPlayers -- defined below (used by the recorder)
local REPLAY_TIME = Config.KillReplayTime or 3
local RECORD_RATE = 1 / 20
local AimRemote = Remotes:FindFirstChild("Aim")
if not AimRemote then
	AimRemote = Instance.new("UnreliableRemoteEvent")
	AimRemote.Name = "Aim"
	AimRemote.Parent = Remotes
end
local aimOf = {} -- [player] = latest camera look vector
local eyeOf = {} -- [player] = camera height above their HumanoidRootPart (for replays)
local aimSent = {} -- [player] = last time AimLook was published
AimRemote.OnServerEvent:Connect(function(p, look, eye)
	if typeof(look) == "Vector3" and look.Magnitude > 0.5 and look.Magnitude == look.Magnitude then
		aimOf[p] = look.Unit
		if typeof(eye) == "number" and eye == eye then eyeOf[p] = math.clamp(eye, -6, 12) end
		-- LIVE SPECTATE: everyone can see where match players look (so spectators get their exact first-person view)
		if os.clock() - (aimSent[p] or 0) >= 0.1 then
			aimSent[p] = os.clock()
			p:SetAttribute("AimLook", look.Unit)
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) aimSent[p] = nil eyeOf[p] = nil end)
local BODY = {
	Head = true, HumanoidRootPart = true, Torso = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true,
	RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true,
	RightLowerLeg = true, RightFoot = true,
}
local function recordFrame(match, t)
	match.rec = match.rec or {}
	for _, p in allPlayers(match) do
		local char = p.Character
		if char then
			local parts = {}
			for _, bp in char:GetChildren() do
				if bp:IsA("BasePart") and BODY[bp.Name] then parts[bp.Name] = bp.CFrame end
			end
			local list = match.rec[p]
			if not list then list = {} match.rec[p] = list end
			table.insert(list, {t = t, look = aimOf[p], parts = parts})
			while #list > 0 and t - list[1].t > REPLAY_TIME + 3 do table.remove(list, 1) end
		end
	end
	if match.shots then
		while #match.shots > 0 and t - match.shots[1].t > REPLAY_TIME + 3 do table.remove(match.shots, 1) end
	end
	if match.hits then
		while #match.hits > 0 and t - match.hits[1].t > REPLAY_TIME + 3 do table.remove(match.hits, 1) end
	end
end
-- REPLAY_TIME seconds before the kill + a little after it (so the hit, damage number and pop are seen),
-- times made relative (0 = start of the replay)
local REPLAY_AFTER = Config.KillReplayAfter or 1
local function snapshotReplay(match, killer, victim, killT, tags)
	local t1 = killT + REPLAY_AFTER
	local t0 = killT - REPLAY_TIME
	local people = {}
	for p, list in match.rec or {} do
		if p.Parent == Players then
			local frames = {}
			for _, f in list do
						if f.t >= t0 and f.t <= t1 then table.insert(frames, {t = f.t - t0, look = f.look, parts = f.parts}) end
			end
			if #frames > 1 then table.insert(people, {UserId = p.UserId, Frames = frames}) end
		end
	end
	local shots = {}
	for _, s in match.shots or {} do
		if s.t >= t0 and s.t <= t1 then table.insert(shots, {t = s.t - t0, from = s.from, to = s.to, pop = s.pop, UserId = s.UserId, kind = s.kind}) end
	end
	-- hits that did damage (damage numbers + red flash on whoever got hit)
	local hits = {}
	for _, h in match.hits or {} do
		if h.t >= t0 and h.t <= t1 then
			table.insert(hits, {t = h.t - t0, Attacker = h.Attacker, Victim = h.Victim, pos = h.pos, amount = h.amount, head = h.head, melee = h.melee})
		end
	end
	return {Length = t1 - t0, Killer = killer.UserId, KillerName = NameBadge.Of(killer), Victim = victim.UserId, VictimName = NameBadge.Of(victim),
		KillAt = killT - t0, Tags = tags, People = people, Shots = shots, Hits = hits}
end

local function send(match, event, data)
	for _, team in match.teams do
		for _, p in team do
			if p.Parent == Players then MatchEvent:FireClient(p, event, data) end
		end
	end
end

allPlayers = function(match)
	local list = {}
	for _, team in match.teams do
		for _, p in team do table.insert(list, p) end
	end
	return list
end

local function teamInfos(match)
	local out = {}
	for t, team in match.original do
		out[t] = {}
		for _, p in team do table.insert(out[t], infoOf(p)) end
	end
	return out
end

local function checkForfeit(match)
	if #match.teams[1] == 0 and #match.teams[2] == 0 then
		match.cancelled = true
	elseif #match.teams[1] == 0 then
		match.forfeitWinner = 2
	elseif #match.teams[2] == 0 then
		match.forfeitWinner = 1
	end
end

local function spectate(match, p)
	local char = p.Character
	if not char or not match.map then return end
	char:WaitForChild("HumanoidRootPart", 5)
	if match.placing[p] or matchByPlayer[p] ~= match then return end
	local spot = match.map:FindFirstChild("Spectate", true)
	p:SetAttribute("InArena", false)
	p:SetAttribute("Spectating", true)
	if spot then
		teleport(p, spot.CFrame * CFrame.new(math.random(-4, 4), 3, math.random(-4, 4)))
	end
end

local function returnToLobby(p)
	local match = matchByPlayer[p]
	matchByPlayer[p] = nil
	task.spawn(chatLeaveMatch, match, p)
	if p.Parent ~= Players then return end
	for _, k in {"MatchKills", "MatchDeaths", "MatchAssists"} do p:SetAttribute(k, nil) end
	p:SetAttribute("MatchId", nil)
	p:SetAttribute("MatchTeam", nil)
	p:SetAttribute("Spectating", nil)
	p:SetAttribute("CombatLocked", nil)
	p:SetAttribute("ShootLocked", nil)
	p:SetAttribute("InArena", false)
	p:SetAttribute("MatchDead", nil)
	p:SetAttribute("MatchTeamSize", nil)
	p:SetAttribute("MatchEnded", nil)
	-- the end screen froze them: unfreeze, or they can't move back in the lobby
	p:SetAttribute("Frozen", nil)
	p:SetAttribute("CombatLocked", nil)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = false end
	if IS_MATCH_SERVER then
		-- match servers have no lobby: send them back to a real lobby server
		SendToLobbyHook:Fire(p)
		return
	end
	p:LoadCharacter() -- fresh character at the lobby SpawnLocation
end

-- spectateAfter: respawned while the round result is showing -> stand at your own spawn (hidden away from
-- the sky spectator spot) but keep watching the other players until the next round starts
local function placeForRound(match, p, team, index, spectateAfter)
	match.placing[p] = true
	-- dead? let Roblox's normal respawn happen first (calling LoadCharacter on top of it can spawn twice)
	local t0 = os.clock()
	while not aliveChar(p) and os.clock() - t0 < Players.RespawnTime + 1 and p.Parent == Players do task.wait() end
	if not aliveChar(p) and p.Parent == Players then p:LoadCharacter() end
	t0 = os.clock()
	while not aliveChar(p) and os.clock() - t0 < 5 and p.Parent == Players do task.wait() end
	local char, hum = aliveChar(p)
	if not char then match.placing[p] = nil return end
	hum.Health = hum.MaxHealth
	-- SIDES: teams swap ends every round (Config.SwapSides) - odd rounds normal, even rounds swapped
	local side = team
	if match.swapped then side = team == 1 and 2 or 1 end
	local spawns = match.map.Spawns["Team" .. side]:GetChildren()
	table.sort(spawns, function(a, b) return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0) end)
	local spawnPart = spawns[((index - 1) % #spawns) + 1]
	-- face the enemy team's spawns (i.e. towards the middle of the map / the other players)
	local enemy = match.map.Spawns["Team" .. (side == 1 and 2 or 1)]:GetChildren()
	local target = Vector3.zero
	for _, e in enemy do target += e.Position end
	target = #enemy > 0 and target / #enemy or (spawnPart.Position + spawnPart.CFrame.LookVector)
	local pos = spawnPart.Position + Vector3.new(0, 3, 0)
	local facing = CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
	if spectateAfter then
		p:SetAttribute("InArena", false)
		p:SetAttribute("Spectating", true)
	else
		p:SetAttribute("Spectating", nil)
		p:SetAttribute("InArena", true)
		p:SetAttribute("MatchDead", nil)
	end
	-- anchor FIRST, then move: an unanchored character is simulated by the player's own computer, which can
	-- send back where it was last round and undo the teleport (the "start where I was last round" glitch)
	freeze(p, true)
	teleport(p, facing)
	-- first-person camera keeps its old direction unless we turn it too (the client also snaps itself into place)
	if not spectateAfter then MatchEvent:FireClient(p, "Face", {Look = facing.LookVector, CFrame = facing}) end
	-- double-check a moment later and put them back if anything moved them
	for _, delay in {0.3, 0.9} do
		task.delay(delay, function()
			local c2, _, root = aliveChar(p)
			if c2 == char and root and match.phase == "rounds" and not match.roundActive
				and (root.Position - facing.Position).Magnitude > 4 then
				root.Anchored = true
				teleport(p, facing)
			end
		end)
	end
	match.alive[p] = true
	if match.diedConn[p] then match.diedConn[p]:Disconnect() end
	match.diedConn[p] = hum.Died:Connect(function()
		if match.alive[p] then
			match.alive[p] = false
			p:SetAttribute("MatchDead", true) -- [DEAD] in match chat (MatchChat)
			addStat(match, p, "Deaths", 1)
			Quests.OnDeath(p)
			send(match, "PlayerDied", {UserId = p.UserId})
		end
	end)
	match.placing[p] = nil
end

local function countAlive(match, team)
	local n = 0
	for _, p in match.teams[team] do
		if match.alive[p] and aliveChar(p) then n += 1 end
	end
	return n
end

------------------------------------------------------------ LIVE MATCHES (the SPECTATE wall in the lobby reads these)
-- ReplicatedStorage > Matchmaking > LiveMatches > <match id> (Folder) with attributes:
--   Map, Image, Mode, Score1, Score2, Team1 / Team2 (JSON list of {UserId, Name}), EndsAt (round timer), Round
-- Spectating itself: ServerScriptService > LiveSpectateServer
local LiveFolder = MM:FindFirstChild("LiveMatches") or Instance.new("Folder")
LiveFolder.Name = "LiveMatches"
LiveFolder.Parent = MM
local function publishLive(match, scores, extra)
	if IS_MATCH_SERVER or not match.map then return end
	local f = LiveFolder:FindFirstChild(match.id)
	if not f then
		f = Instance.new("Folder")
		f.Name = match.id
		f:SetAttribute("StartedAt", workspace:GetServerTimeNow())
	end
	local info = match.mapInfo or {}
	f:SetAttribute("Map", info.Name or "")
	f:SetAttribute("Image", info.Image or "")
	f:SetAttribute("Mode", match.mode)
	f:SetAttribute("Score1", scores and scores[1] or 0)
	f:SetAttribute("Score2", scores and scores[2] or 0)
	for t = 1, 2 do
		local list = {}
		for _, p in match.teams[t] do
			if p.Parent == Players then table.insert(list, {UserId = p.UserId, Name = NameBadge.Of(p)}) end
		end
		f:SetAttribute("Team" .. t, HttpService:JSONEncode(list))
	end
	for k, v in extra or {} do f:SetAttribute(k, v) end
	f.Parent = LiveFolder
end
------------------------------------------------------------ FULL MATCH RECORDING (Replays: ServerStorage > Replays)
-- 10 times a second: every player's position, facing, aim, state and HP (about 10 bytes each), plus every
-- shot / swing / hit / kill / round. Saved when the match ends; each player keeps their last 20 (Replays.MaxPerPlayer).
local Replays = require(SS:WaitForChild("Replays"))
local FULL_RATE = Replays.Rate or 10
local function fullStart(match, map, mapInfo)
	local origin = map:GetPivot()
	match.full = {
		t0 = os.clock(), origin = origin, frames = 0, people = {}, events = {},
		mapInfo = mapInfo, model = map.Name,
	}
	for t, team in match.teams do
		for _, p in team do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			match.full.people[p] = {UserId = p.UserId, Name = p.DisplayName, Verified = NameBadge.Verified(p), Team = t, samples = {}, Rig = hum and hum.RigType.Name or "R15"}
		end
	end
end
local function fullRel(match, v)
	local r = match.full.origin:PointToObjectSpace(v)
	return {math.floor(r.X * 10 + 0.5) / 10, math.floor(r.Y * 10 + 0.5) / 10, math.floor(r.Z * 10 + 0.5) / 10}
end
local function fullEvent(match, e)
	local f = match.full
	if not f then return end
	e.t = math.floor((os.clock() - f.t0) * 100 + 0.5) / 100
	table.insert(f.events, e)
end
local function fullSample(match)
	local f = match.full
	if not f then return end
	local idx = math.floor((os.clock() - f.t0) * FULL_RATE + 0.5)
	if idx < f.frames then return end
	f.frames = idx + 1
	for p, person in f.people do
		local char = p.Parent == Players and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local s = false
		if root and hum then
			local rel = f.origin:ToObjectSpace(root.CFrame)
			local look = aimOf[p] and f.origin:VectorToObjectSpace(aimOf[p]) or rel.LookVector
			local _, yaw = rel:ToEulerAnglesYXZ()
			local pitch = math.asin(math.clamp(look.Y, -1, 1))
			local lookYaw = math.atan2(-look.X, -look.Z)
			local flags = 0
			local alive = hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead and not p:GetAttribute("MatchDead") and not p:GetAttribute("Spectating")
			if alive then flags += 1 end
			if char:GetAttribute("Crouching") then flags += 2 end
			if hum.FloorMaterial == Enum.Material.Air then flags += 4 end
			if char:GetAttribute("Sprinting") then flags += 8 end
			if char:GetAttribute("Sliding") then flags += 16 end
			s = {rel.Position, alive and lookYaw or yaw, pitch, flags, math.clamp(math.floor(hum.Health + 0.5), 0, 255), eyeOf[p]}
		end
		person.samples[idx + 1] = s
	end
end
local function fullFinish(match, scores, winner)
	local f = match.full
	if not f or f.saved then return end
	f.saved = true
	local people = {}
	for p, person in f.people do
		table.insert(people, {UserId = person.UserId, Name = person.Name, Team = person.Team, Rig = person.Rig,
			Data = Replays.PackSamples(person.samples, f.frames)})
	end
	local info = f.mapInfo or {}
	task.spawn(Replays.Save, {
		Id = match.id .. "_" .. os.time(),
		Date = os.time(),
		Map = info.Name or "", Model = f.model, Image = info.Image or "",
		Mode = match.mode, Rate = FULL_RATE, Frames = f.frames, Bytes = Replays.BYTES, V = 3,
		Score1 = scores[1], Score2 = scores[2], Winner = winner,
		People = people, Events = f.events,
		Origin = {f.origin:GetComponents()},
	})
	match.full = nil
end

local function unpublishLive(match)
	local f = LiveFolder:FindFirstChild(match.id)
	if f then f:Destroy() end
end

local function runMatch(match)
	-- 1) black fade + logo
	match.phase = "intro"
	send(match, "Intro", {})
	-- only move them to the holding spot once their screen is fully black,
	-- so nobody sees themselves up in the sky / falling for a split second
	task.wait(Config.FadeTime + 0.2)
	for t, team in match.teams do
		for i, p in team do
			if p.Parent == Players and matchByPlayer[p] == match then
				local hold = (Config.HoldingSpot or Vector3.new(0, 900, -6000)) + Vector3.new(t * 30, 0, i * 6 + math.random(0, 400))
				teleport(p, CFrame.new(hold))
				freeze(p, true)
			end
		end
	end
	task.wait(math.max(0, Config.LogoHoldTime - 0.2))
	if match.cancelled or match.forfeitWinner then match.phase = "cancel" end

	-- 2) map vote
	local chosen
	if match.phase == "intro" then
		match.phase = "vote"
		match.votes = {}
		match.voteEndsAt = now() + Config.VoteTime
		send(match, "VoteStart", {EndsAt = match.voteEndsAt, Teams = teamInfos(match)})
		while now() < match.voteEndsAt and not match.cancelled and not match.forfeitWinner do
			task.wait(0.1)
		end
		local counts = {}
		for _, idx in match.votes do counts[idx] = (counts[idx] or 0) + 1 end
		local best, tied = 0, {}
		for idx, c in counts do
			if c > best then best, tied = c, {idx} elseif c == best then table.insert(tied, idx) end
		end
		if #tied == 0 then for i = 1, #Config.Maps do table.insert(tied, i) end end
		chosen = tied[math.random(1, #tied)] -- tie -> random between the tied maps
		if match.cancelled or match.forfeitWinner then
			match.phase = "cancel"
		else
			match.phase = "voted"
			send(match, "VoteResult", {Map = chosen, Tied = #tied > 1 and best > 0})
			task.wait(Config.VoteResultTime or 3.5) -- "map picked" animation
		end
	end

	-- someone left before the fight started -> no match, everybody back to the lobby
	if match.phase == "cancel" or match.cancelled or match.forfeitWinner then
		send(match, "Cancelled", {})
		task.wait(Config.FadeTime)
		for _, p in allPlayers(match) do returnToLobby(p) end
		send(match, "Return", {})
		return
	end

	-- 3) build the map in a free slot
	local mapInfo = Config.Maps[chosen]
	local template = MapsFolder:FindFirstChild(mapInfo.Model) or MapsFolder:GetChildren()[1]
	local slot = 1
	while usedSlots[slot] do slot += 1 end
	usedSlots[slot] = true
	local map = template:Clone()
	map.Name = "Match_" .. match.id
	map:PivotTo(CFrame.new(Config.ArenaOrigin + Vector3.new((slot - 1) * Config.ArenaSpacing, 0, 0)))
	map.Parent = ActiveFolder
	match.map = map
	match.mapInfo = mapInfo
	match.phase = "rounds"
	pcall(fullStart, match, template, mapInfo)
	if match.full then match.full.origin = map:GetPivot() match.full.model = template.Name end

	local scores = {0, 0}
	local round = 0
	local winner
	local firstRound = true
	while true do
		round += 1
		match.swapped = Config.SwapSides ~= false and round % 2 == 0
		match.roundActive = false
		match.lastKill = nil
		for t = 1, 2 do
			for i, p in match.teams[t] do
				task.spawn(placeForRound, match, p, t, i)
			end
		end
		-- wait until everyone is placed
		local t0 = os.clock()
		repeat task.wait(0.1) until next(match.placing) == nil or os.clock() - t0 > 10
		if firstRound then
			send(match, "MatchStart", {Teams = teamInfos(match), MapName = mapInfo.Name, PointsToWin = Config.PointsToWin})
			firstRound = false
			task.wait(Config.FadeTime)
		end
		send(match, "RoundStart", {Round = round, Scores = scores, Countdown = Config.RoundCountdown, PointsToWin = Config.PointsToWin,
			RoundTime = Config.RoundTime})
		publishLive(match, scores, {Round = round, EndsAt = 0})
		fullEvent(match, {k = "round", round = round, s1 = scores[1], s2 = scores[2]})
		task.wait(Config.RoundCountdown)
		local shootToken = {}
		match.shootToken = shootToken
		for _, p in allPlayers(match) do
			freeze(p, false)
			-- shots stay locked for a moment after the countdown
			p:SetAttribute("ShootLocked", true)
			task.delay(Config.ShootDelay or 1, function()
				if match.shootToken == shootToken then p:SetAttribute("ShootLocked", nil) end
			end)
		end
		match.roundActive = true
		match.roundStartedAt = os.clock()
		match.damagers = {} -- [victim player] = {[attacker] = true}, for assists (this round only)
		-- ROUND TIMER: nobody wins within Config.RoundTime = draw (no point)
		local roundEndsAt = Config.RoundTime and (workspace:GetServerTimeNow() + Config.RoundTime) or nil
		send(match, "Fight", {EndsAt = roundEndsAt})
		publishLive(match, scores, {EndsAt = roundEndsAt or 0})
		fullEvent(match, {k = "fight", len = Config.RoundTime or 0})

		local roundWinner
		while true do
			task.wait(0.1)
			if match.forfeitWinner then break end
			if roundEndsAt and workspace:GetServerTimeNow() >= roundEndsAt then
				roundWinner = 0
				match.lastKill = nil -- no replay for a timed-out round
				break
			end
			local a1, a2 = countAlive(match, 1), countAlive(match, 2)
			if a1 == 0 or a2 == 0 then
				roundWinner = (a1 > 0 and 1) or (a2 > 0 and 2) or 0
				break
			end
		end
		match.roundActive = false
		if match.forfeitWinner then winner = match.forfeitWinner break end
		if roundWinner > 0 then scores[roundWinner] += 1 end
		publishLive(match, scores, {EndsAt = 0})
		fullEvent(match, {k = "roundEnd", w = roundWinner, s1 = scores[1], s2 = scores[2]})
		local lk = match.lastKill
		send(match, "RoundEnd", {
			Winner = roundWinner, Scores = scores,
			Killer = lk and lk.killer, Victim = lk and lk.victim,
			KillerInfo = lk and lk.killerInfo, VictimInfo = lk and lk.victimInfo, -- player cards on the round result
			Seconds = math.floor(os.clock() - match.roundStartedAt + 0.5),
		})
		if scores[1] >= Config.PointsToWin or scores[2] >= Config.PointsToWin then
			winner = scores[1] >= Config.PointsToWin and 1 or 2
			task.wait(Config.RoundEndDelay) -- let the last round result play
			-- FINAL KILL REPLAY: everyone watches the match-winning kill through the killer's eyes
			if lk and lk.replay and Config.KillReplay ~= false then
				for _, p in allPlayers(match) do freeze(p, true) end
				send(match, "KillReplay", lk.replay)
				task.wait(lk.replay.Length + (Config.FadeTime or 0.6) * 2 + 1)
			end
			break
		end
		task.wait(Config.RoundEndDelay)
		if match.forfeitWinner then winner = match.forfeitWinner break end
	end

	-- 4) results + XP
	-- everyone (alive or dead) back at their own spawn, so the end-screen camera has a character to look at
	match.phase = "ending"
	unpublishLive(match) -- off the spectate wall (spectators are sent back to the lobby)
	pcall(fullFinish, match, scores, winner)
	match.roundActive = false
	for t = 1, 2 do
		for i, p in match.teams[t] do
			task.spawn(placeForRound, match, p, t, i)
		end
	end
	local tEnd = os.clock()
	repeat task.wait(0.1) until next(match.placing) == nil or os.clock() - tEnd > 8
	match.phase = "ended"
	-- MVP (team modes): best score from kills / assists / deaths. Stands in the middle of their team's line-up.
	local mvp, mvpInfo = pickMVP(match, winner)
	if mvp then
		for t = 1, 2 do
			local ordered = {}
			for _, p in match.teams[t] do if p.Parent == Players then table.insert(ordered, p) end end
			table.sort(ordered, function(a, b) return mvpScore(match, a, winner) > mvpScore(match, b, winner) end)
			local i = table.find(ordered, mvp)
			if i then table.remove(ordered, i) table.insert(ordered, 1, mvp) end
			lineUp(match, t, ordered)
		end
		crownMVP(mvp)
		Quests.Add(mvp, "MVP", 1)
	end
	local brokenStreaks = {} -- {{player, oldStreak}}
	for _, p in allPlayers(match) do
		if p.Parent ~= Players then continue end
		local team = p:GetAttribute("MatchTeam")
		local won = team == winner
		local st = match.stats[p]
		local xp = (won and Config.XP.Win or Config.XP.Loss) + st.KillXP
		PlayerData.AddXP(p, xp)
		if won then
			PlayerData.Increment(p, "WinStreak", 1)
			PlayerData.Increment(p, "Wins", 1)
		else
			local old = p:GetAttribute("WinStreak") or 0
			if old >= (Config.StreakAnnounceMin or 10) then table.insert(brokenStreaks, {p, old}) end
			PlayerData.Set(p, "WinStreak", 0)
			PlayerData.Increment(p, "Losses", 1)
		end
		PlayerData.Increment(p, "Kills", st.Kills)
		PlayerData.Increment(p, "Deaths", st.Deaths)
		PlayerData.Increment(p, "Matches", 1)
		-- daily quests
		if won then Quests.Add(p, "Wins", 1) end
		if match.mode == "1v1" then Quests.Add(p, "Matches1v1", 1) end
		local li = match.levelInfo[p] or {From = p:GetAttribute("Level") or 1, Coins = 0}
		freeze(p, true)
		p:SetAttribute("MatchEnded", true) -- end screen: Queue Again is allowed now (GlobalMatchmaking)
		-- combat off for the victory screen: third person, no balloon / viewmodel, so the camera can circle the player
		p:SetAttribute("Spectating", nil)
		p:SetAttribute("InArena", false)
		MatchEvent:FireClient(p, "MatchEnd", {
			Won = won, Scores = scores, Kills = st.Kills, Deaths = st.Deaths, XPGained = xp, EndTime = Config.EndScreenTime,
			XP = p:GetAttribute("XP"), Level = p:GetAttribute("Level"), Forfeit = match.forfeitWinner ~= nil,
			WinStreak = p:GetAttribute("WinStreak"),
			Quests = Quests.Summary(p, match.questSnap[p]),
			LevelFrom = li.From, LevelTo = PlayerData.GetLevel(p), LevelCoins = li.Coins,
			MVP = mvpInfo,
		})
	end
	-- WIN STREAK ANNOUNCEMENTS (GlobalMatchmaking posts them): who broke it = the winning team
	if #brokenStreaks > 0 then
		local winners = {}
		for _, p in match.teams[winner] or {} do
			if p.Parent == Players then table.insert(winners, {Name = p.Name, Streak = p:GetAttribute("WinStreak") or 0}) end
		end
		for _, b in brokenStreaks do
			StreakEndedHook:Fire({Name = b[1].Name, Streak = b[2]}, winners, match.mode)
		end
	end
	task.wait(Config.EndScreenTime)
	send(match, "FadeOut", {})
	task.wait(Config.FadeTime)

	-- 5) back to the lobby
	for _, p in allPlayers(match) do returnToLobby(p) end
	for _, c in match.diedConn do c:Disconnect() end
	for _, c in match.charConn do c:Disconnect() end
	task.wait(0.5)
	send(match, "Return", {})
	map:Destroy()
	usedSlots[slot] = nil
end

------------------------------------------------------------ MVP (settings: Matchmaking > Config > MVP)
function mvpScore(match, p, winner)
	local c = Config.MVP or {}
	local st = match.stats[p]
	if not st then return -math.huge end
	local s = st.Kills * (c.KillPoints or 100) + (st.Assists or 0) * (c.AssistPoints or 50) + st.Deaths * (c.DeathPoints or -40)
	if p:GetAttribute("MatchTeam") == winner then s += c.WinBonus or 0 end
	return s
end

function pickMVP(match, winner)
	local c = Config.MVP or {}
	if c.Enabled == false then return nil end
	local size = math.max(#match.original[1], #match.original[2])
	if size < (c.MinTeamSize or 2) then return nil end
	local best, bestScore
	for t = 1, 2 do
		for _, p in match.teams[t] do
			local st = match.stats[p]
			if p.Parent == Players and st and (st.Kills > 0 or (st.Assists or 0) > 0) then
				local s = mvpScore(match, p, winner)
				-- ties: more kills, then fewer deaths
				if not best or s > bestScore
					or (s == bestScore and (st.Kills > match.stats[best].Kills
						or (st.Kills == match.stats[best].Kills and st.Deaths < match.stats[best].Deaths))) then
					best, bestScore = p, s
				end
			end
		end
	end
	if not best then return nil end
	local st = match.stats[best]
	return best, {UserId = best.UserId, Name = best.Name, DisplayName = best.DisplayName, Verified = NameBadge.Verified(best), Team = best:GetAttribute("MatchTeam"),
		Kills = st.Kills, Deaths = st.Deaths, Assists = st.Assists or 0}
end

-- stands a team in a line at their spawns: ordered[1] in the middle, then right, left, right ...
function lineUp(match, t, ordered)
	local spawnsFolder = match.map and match.map:FindFirstChild("Spawns")
	local mine = spawnsFolder and spawnsFolder:FindFirstChild("Team" .. t)
	local enemyF = spawnsFolder and spawnsFolder:FindFirstChild("Team" .. (t == 1 and 2 or 1))
	if not (mine and enemyF) then return end
	local spawns, enemy = mine:GetChildren(), enemyF:GetChildren()
	if #spawns == 0 then return end
	local center = Vector3.zero
	for _, s in spawns do center += s.Position end
	center /= #spawns
	local target = Vector3.zero
	for _, e in enemy do target += e.Position end
	target = #enemy > 0 and target / #enemy or center + Vector3.new(0, 0, -10)
	local pos = center + Vector3.new(0, 3, 0)
	local facing = CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
	local gap = (Config.MVP and Config.MVP.LineupSpacing) or 4.5
	for i, p in ordered do
		local k = i == 1 and 0 or math.floor(i / 2) * (i % 2 == 0 and 1 or -1)
		local _, _, root = aliveChar(p)
		if root then
			root.Anchored = true
			teleport(p, facing * CFrame.new(k * gap, 0, 0))
		end
	end
end

-- crown + gold outline on the MVP (everyone sees it), removed when the end screen is over
function crownMVP(p)
	local c = Config.MVP or {}
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MVPTag"
	bb.Size = UDim2.fromOffset(160, 44)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Text = c.Tag or "MVP"
	lbl.TextScaled = true
	lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	lbl.TextColor3 = c.Color or Color3.fromRGB(255, 205, 60)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = lbl
	lbl.Parent = bb
	bb.Parent = head
	local hl = Instance.new("Highlight")
	hl.Name = "MVPHighlight"
	hl.FillTransparency = 1
	hl.OutlineColor = c.Color or Color3.fromRGB(255, 205, 60)
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = char
	local life = (Config.EndScreenTime or 8) + (Config.FadeTime or 1) + 1
	game:GetService("Debris"):AddItem(bb, life)
	game:GetService("Debris"):AddItem(hl, life)
end

startMatch = function(team1, team2, area, source)
	local match = {
		id = HttpService:GenerateGUID(false):sub(1, 8),
		teams = {team1, team2},
		original = {table.clone(team1), table.clone(team2)},
		area = area,
		stats = {}, alive = {}, placing = {}, diedConn = {}, charConn = {},
		questSnap = {}, levelInfo = {}, -- for the end screen (quest progress / levels gained this match)
		phase = "starting",
	}
	local size = math.max(#team1, #team2, 1)
	match.mode = size .. "v" .. size
	for t, team in match.teams do
		for _, p in team do
			matchByPlayer[p] = match
			p:SetAttribute("LastMode", match.mode) -- the end screen's Queue Again button searches this mode
			-- "Search" = came from the Play menu (Queue Again searches again), "Pad" = came from a queue pad / duel
			-- (Queue Again puts you back on a pad of the same mode)
			p:SetAttribute("LastSource", source or "Pad")
			p:SetAttribute("MatchTeamSize", size)
			p:SetAttribute("MatchDead", nil)
			match.stats[p] = {Kills = 0, Deaths = 0, Assists = 0, KillXP = 0}
			for _, k in {"Kills", "Deaths", "Assists"} do p:SetAttribute("Match" .. k, 0) end
			Quests.MatchStart(p)
			match.questSnap[p] = Quests.Snapshot(p)
			match.levelInfo[p] = {From = PlayerData.GetLevel(p), Coins = 0}
			p:SetAttribute("MatchId", match.id)
			task.spawn(chatJoinMatch, match, p)
			p:SetAttribute("MatchTeam", t)
			freeze(p, true) -- they stay put on the pad while the screen fades to black (runMatch moves them after)
			-- any respawn during the fight puts you in the spectator box until the next round
			match.charConn[p] = p.CharacterAdded:Connect(function()
				if match.phase == "rounds" and not match.placing[p] then
					if match.roundActive then
						spectate(match, p)
					else
						-- respawned between rounds (round result / replay): straight back to your own spawn,
						-- not the spectator spot up in the air (that's the "camera in the sky" glitch)
						for t, team in match.teams do
							local i = table.find(team, p)
							if i then
								-- spectate straight away so the camera never shows your new body / the lobby
								p:SetAttribute("Spectating", true)
								task.spawn(placeForRound, match, p, t, i, true)
								break
							end
						end
					end
				end
			end)
		end
	end
	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn("[Matchmaking] match crashed: " .. tostring(err))
			unpublishLive(match)
			for _, p in allPlayers(match) do pcall(returnToLobby, p) end
			send(match, "Return", {})
			if match.map then match.map:Destroy() end
		end
		match.over = true
		if match.chat then match.chat:Destroy() end
	end)
end

------------------------------------------------------------ VOTING
VoteRemote.OnServerEvent:Connect(function(p, idx, x, y)
	local match = matchByPlayer[p]
	if not match or match.phase ~= "vote" then return end
	if typeof(idx) ~= "number" or not Config.Maps[idx] then return end
	-- x, y = where on the card they clicked (0-1), so their face shows at that spot for everyone
	local function clamp01(n) return typeof(n) == "number" and n == n and math.clamp(n, 0, 1) or nil end
	match.votes[p] = idx
	match.votePos = match.votePos or {}
	match.votePos[p] = {clamp01(x), clamp01(y)}
	local list = {}
	for voter, v in match.votes do
		local pos = match.votePos[voter] or {}
		table.insert(list, {UserId = voter.UserId, Map = v, X = pos[1], Y = pos[2]})
	end
	-- voting always runs until the timer ends (players can change their vote until then)
	send(match, "VoteUpdate", {Votes = list})
end)

------------------------------------------------------------ RETURN TO LOBBY BUTTON (end screen)
local function leaveEndScreen(p)
	local match = matchByPlayer[p]
	if not match or match.phase ~= "ended" then return end
	-- take them out of the match so the automatic return later skips them
	for _, team in match.teams do
		local i = table.find(team, p)
		if i then table.remove(team, i) end
	end
	if match.charConn[p] then match.charConn[p]:Disconnect() match.charConn[p] = nil end
	MatchEvent:FireClient(p, "FadeOut", {})
	task.wait(Config.FadeTime)
	returnToLobby(p)
	task.wait(0.5)
	MatchEvent:FireClient(p, "Return", {})
end
LeaveEndScreen.OnServerEvent:Connect(leaveEndScreen)

------------------------------------------------------------ KILLS
PlayerKilled.Event:Connect(function(killer, victimModel, victimPlayer, tags)
	local match = killer and matchByPlayer[killer]
	if not match or not victimPlayer or matchByPlayer[victimPlayer] ~= match or not match.roundActive then return end
	addStat(match, killer, "Kills", 1)
	Quests.OnKill(killer, tags) -- daily quests
	-- ASSISTS: everyone else who damaged the victim this round
	local hitters = match.damagers and match.damagers[victimPlayer]
	if hitters then
		for attacker in hitters do
			if attacker ~= killer and matchByPlayer[attacker] == match then addStat(match, attacker, "Assists", 1) end
		end
		match.damagers[victimPlayer] = nil
	end
	-- the XP the kill popup showed (KILL + HEADSHOT / LONGSHOT / JUMPSHOT / MELEE) is really given at the end
	for _, t in (tags or {}) do
		match.stats[killer].KillXP += t.xp or 0
	end
	local ki, vi = infoOf(killer), infoOf(victimPlayer)
	ki.Team, vi.Team = killer:GetAttribute("MatchTeam"), victimPlayer:GetAttribute("MatchTeam")
	match.lastKill = {killer = NameBadge.Of(killer), victim = NameBadge.Of(victimPlayer), killerInfo = ki, victimInfo = vi}
	pcall(fullEvent, match, {k = "kill", a = killer.UserId, v = victimPlayer.UserId, tags = tags})
	-- keep the last few seconds in case this turns out to be the match-winning kill
	-- (taken a moment AFTER the kill so the hit + pop + fall are in it too)
	local lk, killT = match.lastKill, os.clock()
	task.delay(REPLAY_AFTER, function()
		local ok, rep = pcall(snapshotReplay, match, killer, victimPlayer, killT, tags)
		if ok then lk.replay = rep else warn("[Matchmaking] replay: " .. tostring(rep)) end
	end)
end)

-- who hurt who (for assists)
PlayerDamaged.Event:Connect(function(attacker, victimModel, victimPlayer, damage, hitPos, isHead, isMelee)
	-- every hit is remembered for the kill replay
	local m = attacker and matchByPlayer[attacker]
	if m and victimPlayer and m.phase == "rounds" and typeof(hitPos) == "Vector3" then
		m.hits = m.hits or {}
		table.insert(m.hits, {t = os.clock(), Attacker = attacker.UserId, Victim = victimPlayer.UserId, pos = hitPos, amount = damage, head = isHead, melee = isMelee})
		if m.full then pcall(fullEvent, m, {k = "hit", a = attacker.UserId, v = victimPlayer.UserId, pos = fullRel(m, hitPos), n = damage, head = isHead or nil, melee = isMelee or nil}) end
	end
	local match = attacker and matchByPlayer[attacker]
	if not match or not victimPlayer or matchByPlayer[victimPlayer] ~= match or not match.roundActive or not match.damagers then return end
	match.damagers[victimPlayer] = match.damagers[victimPlayer] or {}
	match.damagers[victimPlayer][attacker] = true
	if victimPlayer ~= attacker and type(damage) == "number" and damage > 0 then Quests.Add(attacker, "Damage", damage) end
end)

-- shots fired (for the kill replay)
local PlayerShot = script.Parent.BalloonCombatServer:WaitForChild("PlayerShot")
PlayerShot.Event:Connect(function(p, from, to, pop)
	local match = matchByPlayer[p]
	if not match or match.phase ~= "rounds" then return end
	match.shots = match.shots or {}
	table.insert(match.shots, {t = os.clock(), from = from, to = to, pop = pop, UserId = p.UserId})
	if match.full and typeof(from) == "Vector3" and typeof(to) == "Vector3" then
		pcall(fullEvent, match, {k = "shot", u = p.UserId, from = fullRel(match, from), to = fullRel(match, to), pop = pop or nil})
	end
end)
-- melee swings too (so the replay shows the killer's swing)
local PlayerSwung = script.Parent.BalloonCombatServer:WaitForChild("PlayerSwung", 10)
if PlayerSwung then
	PlayerSwung.Event:Connect(function(p)
		local match = matchByPlayer[p]
		if not match or match.phase ~= "rounds" then return end
		match.shots = match.shots or {}
		table.insert(match.shots, {t = os.clock(), kind = "swing", UserId = p.UserId})
		pcall(fullEvent, match, {k = "swing", u = p.UserId})
	end)
end

-- record every match that's fighting, 20 times a second
local recAcc = 0
RunService.Heartbeat:Connect(function(dt)
	recAcc += dt
	if recAcc < RECORD_RATE then return end
	recAcc = 0
	local t = os.clock()
	local seen = {}
	for _, match in matchByPlayer do
		if not seen[match] and match.phase == "rounds" then
			seen[match] = true
			recordFrame(match, t)
			pcall(fullSample, match)
		end
	end
end)

-- PING for the Tab scoreboard (same number as the ms in the corner)
task.spawn(function()
	while true do
		for _, p in Players:GetPlayers() do
			local ok, ping = pcall(function() return p:GetNetworkPing() end)
			if ok then p:SetAttribute("Ping", math.floor(ping * 1000 + 0.5)) end
		end
		task.wait(1)
	end
end)

------------------------------------------------------------ LEAVING
-- QUITTING MID-GAME: leaving any time after the match was found (vote, rounds, kill replay) resets your win streak.
-- Leaving on the victory / defeat screen is fine (the result is already decided).
local function quitMidGame(p)
	local match = matchByPlayer[p]
	if not match or match.phase == "ended" or match.phase == "ending" then return end
	if not p:GetAttribute("StreakReset") then
		p:SetAttribute("StreakReset", true)
		PlayerData.Set(p, "WinStreak", 0)
		-- and it counts as a loss (win rate = Wins / Matches)
		PlayerData.Increment(p, "Losses", 1)
		PlayerData.Increment(p, "Matches", 1)
	end
end
-- runs inside PlayerData's own leave handler, before the save (whichever script's PlayerRemoving fires first)
PlayerData.BeforeLeave(quitMidGame)

Players.PlayerRemoving:Connect(function(p)
	quitMidGame(p)
	local match = matchByPlayer[p]
	if not match then return end
	matchByPlayer[p] = nil
	for _, team in match.teams do
		local i = table.find(team, p)
		if i then table.remove(team, i) end
	end
	match.alive[p] = nil
	match.placing[p] = nil
	if match.rec then match.rec[p] = nil end
	aimOf[p] = nil
	if match.phase ~= "ended" then checkForfeit(match) end
end)

------------------------------------------------------------ 1v1 DUEL REQUESTS (profile > 1v1 button)
-- client -> server:  Duel:FireServer({Action = "Request", Target = player})
--                    Duel:FireServer({Action = "Respond", Id = id, Accept = true/false})
-- server -> client:  {Kind = "Incoming", Id, FromUserId, FromName, Expires}   (show Accept / Decline)
--                    {Kind = "Notice", Text}                                   ("Sent!", "x declined", ...)
local DuelRemote = Remotes:WaitForChild("Duel")
local DUEL_TIMEOUT = 15
local DUEL_COOLDOWN = 5
local duels = {}        -- [id] = {from, to, expires}
local lastDuelAsk = {}  -- [player] = os.clock()
local duelCounter = 0
-- MUTES (DuelPrompt > MuteToggle tick): first mute of someone = MUTE_MINUTES, the next one = rest of this server
local MUTE_MINUTES = Config.DuelMuteMinutes or 5
local mutes = {}        -- [player] = {[fromUserId] = expires (os.clock) or math.huge}
local mutedBefore = {}  -- [player] = {[fromUserId] = true} -> next mute is for the whole server
local function isMuted(p, fromUserId)
	local t = mutes[p] and mutes[p][fromUserId]
	return t ~= nil and os.clock() < t
end

-- (the practice arena / aim training count as free: only a real match makes you busy)
local function idle(p)
	return p and p.Parent == Players and p:GetAttribute("MatchId") == nil and not p:GetAttribute("Searching")
end
local function notice(p, text)
	if p and p.Parent == Players then DuelRemote:FireClient(p, {Kind = "Notice", Text = text}) end
end

DuelRemote.OnServerEvent:Connect(function(p, msg)
	if typeof(msg) ~= "table" then return end
	if msg.Action == "Request" then
		local target = msg.Target
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target == p then return end
		if lastDuelAsk[p] and os.clock() - lastDuelAsk[p] < DUEL_COOLDOWN then
			notice(p, "Wait a moment before challenging again")
			return
		end
		if not idle(p) then notice(p, "You can't challenge during a match") return end
		if not idle(target) then notice(p, target.DisplayName .. " is busy right now") return end
		if not require(SS:WaitForChild("Privacy")).Allows(target, p, "DuelRequests") then
			lastDuelAsk[p] = os.clock()
			notice(p, target.DisplayName .. " isn't accepting 1v1 requests")
			return
		end
		if isMuted(target, p.UserId) then
			lastDuelAsk[p] = os.clock()
			notice(p, target.DisplayName .. " isn't accepting requests right now")
			return
		end
		lastDuelAsk[p] = os.clock()
		duelCounter += 1
		local id = duelCounter
		duels[id] = {from = p, to = target, expires = os.clock() + DUEL_TIMEOUT}
		DuelRemote:FireClient(target, {Kind = "Incoming", Id = id, FromUserId = p.UserId, FromName = p.DisplayName, FromVerified = NameBadge.Verified(p), FromUsername = p.Name, Timeout = DUEL_TIMEOUT,
			MuteForever = mutedBefore[target] ~= nil and mutedBefore[target][p.UserId] ~= nil, MuteMinutes = MUTE_MINUTES})
		notice(p, "1v1 request sent to " .. target.DisplayName)
		task.delay(DUEL_TIMEOUT, function()
			if duels[id] then
				duels[id] = nil
				notice(p, target.DisplayName .. " didn't answer")
			end
		end)
	elseif msg.Action == "Respond" then
		local d = duels[msg.Id]
		if not d or d.to ~= p then return end
		duels[msg.Id] = nil
		if not msg.Accept then
			notice(d.from, p.DisplayName .. " declined your 1v1")
			return
		end
		if not (idle(d.from) and idle(d.to)) then
			notice(d.from, "1v1 cancelled – someone is busy")
			notice(d.to, "1v1 cancelled – someone is busy")
			return
		end
		-- anyone in the practice arena / aim training comes out of it first
		local arena = script.Parent:FindFirstChild("ArenaServer") and script.Parent.ArenaServer:FindFirstChild("SetInArena")
		local moved = false
		for _, q in {d.from, d.to} do
			if q:GetAttribute("InArena") and arena then pcall(function() arena:Invoke(q, false) end) moved = true end
		end
		if moved then task.wait(0.3) end
		if not (idle(d.from) and idle(d.to)) then return end
		startMatch({d.from}, {d.to}, nil)
	elseif msg.Action == "Mute" then
		-- tick on the prompt: {Action = "Mute", UserId = fromUserId, Muted = true/false}
		local uid = msg.UserId
		if typeof(uid) ~= "number" then return end
		mutes[p] = mutes[p] or {}
		mutedBefore[p] = mutedBefore[p] or {}
		if msg.Muted then
			if isMuted(p, uid) then return end
			if mutedBefore[p][uid] then
				mutes[p][uid] = math.huge -- muted before: rest of the server
			else
				mutes[p][uid] = os.clock() + MUTE_MINUTES * 60
				mutedBefore[p][uid] = "pending" -- becomes true when the prompt closes still ticked
			end
		else
			-- unticked before the prompt closed: undo
			mutes[p][uid] = nil
			if mutedBefore[p][uid] == "pending" then mutedBefore[p][uid] = nil end
		end
	elseif msg.Action == "MuteClosed" then
		local uid = msg.UserId
		if typeof(uid) ~= "number" or not mutedBefore[p] then return end
		if mutedBefore[p][uid] == "pending" then mutedBefore[p][uid] = true end
	end
end)
Players.PlayerRemoving:Connect(function(p)
	lastDuelAsk[p] = nil
	mutes[p] = nil
	mutedBefore[p] = nil
	for id, d in duels do
		if d.from == p or d.to == p then duels[id] = nil end
	end
end)

------------------------------------------------------------ MAP PREVIEWS (camera background while voting)
-- look-only copies of every vote map, far away, always streamed to every player
local function buildPreviews()
	local vp = Config.VotePreview
	if not (vp and vp.Enabled) then return end
	local old = workspace:FindFirstChild("MapPreviews")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "MapPreviews"
	for i, info in Config.Maps do
		local src = MapsFolder:FindFirstChild(info.Model)
		if not (src and src:IsA("Model")) then continue end
		local m = src:Clone()
		m.Name = tostring(i) -- index in Config.Maps
		-- look-only copy: no spectator box / spawn markers (the see-through box would sit over the map in the shot)
		for _, n in {"SpectatorBox", "Spectate", "Spawns"} do
			local c = m:FindFirstChild(n)
			if c then c:Destroy() end
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("SpawnLocation") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			end
		end
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		m:PivotTo(CFrame.new(vp.Origin + Vector3.new((i - 1) * vp.Spacing, 0, 0)))
		m.Parent = folder
	end
	folder.Parent = workspace
end

------------------------------------------------------------ JOIN FROM THE LOBBY LIST (QueueUI > Lobbies > Join)
-- client: JoinQueue:FireServer(areaIndex)  ->  teleported onto the side of that pad with the fewest players
local JoinQueue = Remotes:FindFirstChild("JoinQueue")
if not JoinQueue then
	JoinQueue = Instance.new("RemoteEvent")
	JoinQueue.Name = "JoinQueue"
	JoinQueue.Parent = Remotes
end
local lastJoin = {}
-- puts a player on the side of an area with the fewest players (false if it's full)
local function placeOnArea(p, area)
	for team = 1, 2 do
		if table.find(area.members[team], p) then return true end
	end
	local best
	for team = 1, 2 do
		local n = #area.members[team]
		if n < area.teamSize and (not best or n < #area.members[best]) then best = team end
	end
	if not best then return end -- full
	local side = area.sides[best]
	local a = math.random() * math.pi * 2
	local r = math.min(side.halfX, side.halfZ) * 0.3 * math.random()
	local pos = Vector3.new(side.center.X + math.cos(a) * r, side.topY + 3.5, side.center.Z + math.sin(a) * r)
	-- face the other circle
	local other = area.sides[best == 1 and 2 or 1].center
	teleport(p, CFrame.lookAt(pos, Vector3.new(other.X, pos.Y, other.Z)))
	return true
end

-- QUEUE AGAIN after a pad match: the pad of that mode people are already waiting on (most people first),
-- otherwise an empty one
local function padRequeue(p, mode)
	if not canQueue(p) then return false end
	local waitingArea, waitingCount, emptyArea
	for _, area in areas do
		if area.starting or area.sides[1].circle:GetAttribute("QueueMode") ~= mode then continue end
		local n1, n2 = #area.members[1], #area.members[2]
		if n1 >= area.teamSize and n2 >= area.teamSize then continue end -- full
		if n1 + n2 == 0 then
			emptyArea = emptyArea or area
		elseif not waitingArea or n1 + n2 > waitingCount then
			waitingArea, waitingCount = area, n1 + n2
		end
	end
	local area = waitingArea or emptyArea
	return area ~= nil and placeOnArea(p, area)
end

JoinQueue.OnServerEvent:Connect(function(p, index)
	if lastJoin[p] and os.clock() - lastJoin[p] < 1 then return end
	-- end screen Queue Again (pad matches): leave now, then go onto a pad of the same mode
	if index == "Requeue" then
		local match = matchByPlayer[p]
		local mode = p:GetAttribute("LastMode")
		if not match or match.phase ~= "ended" or type(mode) ~= "string" then return end
		lastJoin[p] = os.clock()
		p:SetAttribute("PadRequeue", mode)
		leaveEndScreen(p)
		return
	end
	if typeof(index) ~= "number" then return end
	local area = areas[index]
	if not area or area.starting or not canQueue(p) then return end
	lastJoin[p] = os.clock()
	placeOnArea(p, area)
end)

-- after the trip back to the lobby, drop Queue Again players onto a pad
local function hookRequeue(p)
	p.CharacterAdded:Connect(function(char)
		local mode = p:GetAttribute("PadRequeue")
		if not mode then return end
		task.wait(0.5) -- let the lobby spawn finish first
		if p:GetAttribute("PadRequeue") ~= mode or p.Character ~= char then return end
		p:SetAttribute("PadRequeue", nil)
		padRequeue(p, mode)
	end)
end
for _, p in Players:GetPlayers() do hookRequeue(p) end
Players.PlayerAdded:Connect(hookRequeue)
Players.PlayerRemoving:Connect(function(p) lastJoin[p] = nil end)

------------------------------------------------------------ START A MATCH FOR GlobalMatchmaking
StartMatchHook.OnInvoke = function(team1, team2)
	for _, team in {team1, team2} do
		for _, p in team do
			if matchByPlayer[p] then return false end
		end
	end
	startMatch(team1, team2, nil, "Search")
	return true
end

------------------------------------------------------------ START
buildPreviews()
setupAreas()
task.spawn(function()
	while true do
		task.wait(0.15)
		local ok, err = pcall(queueTick)
		if not ok then warn("[Matchmaking] queue error: " .. tostring(err)) end
	end
end)
