-- LOBBY / PRACTICE ARENA
-- Players spawn in the lobby (the SpawnLocation) as a normal third-person character: no balloon, no combat,
-- but sprint / crouch / slide / climb still work.
-- Entering the arena turns on first person + balloon combat. Dying in the arena respawns you in the arena.
--
-- ENTER:  touch any part named "PracticeArenaEnter" (or tagged "PracticeArenaEnter" with CollectionService).
--         You're asked "Aim Training or Practice Arena?" (StarterGui > Main > PracticeChoice). Walking away from the
--         wall cancels it (its AutoCancelDistance attribute). Aim Training = ServerScriptService > AimTrainingServer.
--         (set up: the big white panel in Workspace > Door is named PracticeArenaEnter)
--         Make that part whenever you're ready – it's picked up automatically, even if added later.
-- SPAWN:  Workspace > PracticeArena > ArenaSpawn (invisible part – move it where you want players to appear)
-- EXIT:   touch any part named "ExitPanel" (or tagged "ExitPanel") – found anywhere in Workspace, so it keeps
--         working if the arena gets moved / regrouped (currently Workspace > Door > ExitPanel)
-- LEAVE:  press G or the LEAVE button (StarterGui > Main > PracticeArenaLeave) – sends you back to the SpawnLocation.
--
-- From other server scripts you can also do:  script.SetInArena:Invoke(player, true/false)

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local LeaveArena = RS:WaitForChild("BalloonCombat"):WaitForChild("Remotes"):WaitForChild("LeaveArena")
local ENTER_NAME = "PracticeArenaEnter"

local AimServer = script.Parent:WaitForChild("AimTrainingServer")
local ChoiceRemote = RS:WaitForChild("AimTraining"):FindFirstChild("PracticeChoice") or Instance.new("RemoteEvent")
ChoiceRemote.Name = "PracticeChoice"
ChoiceRemote.Parent = RS.AimTraining

local function arenaSpawnCF(player)
	-- in aim training you come back in your own room
	if player and player:GetAttribute("AimTraining") and typeof(player:GetAttribute("AimSpawn")) == "CFrame" then
		return player:GetAttribute("AimSpawn")
	end
	local p = workspace:FindFirstChild("ArenaSpawn", true)
	if p then
		local offset = Vector3.new(math.random(-20, 20) / 10, 3.5, math.random(-20, 20) / 10)
		return CFrame.new(p.Position + offset) * p.CFrame.Rotation
	end
end
local function lobbyCF()
	-- the lobby SpawnLocation can be anywhere in Workspace (e.g. inside a "Lobby" model)
	local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if sp then return CFrame.new(sp.Position + Vector3.new(0, 3.5, 0)) * sp.CFrame.Rotation end
end

-- QUICK LOADING SCREEN going in / out: ReplicatedStorage > LoadingTransition (attributes Enabled / FadeIn / Hold /
-- FadeOut, seconds). Its look: StarterGui > LoadingScreen.
local Transition = RS:FindFirstChild("LoadingTransition") or Instance.new("RemoteEvent")
Transition.Name = "LoadingTransition"
Transition.Parent = RS
local moving = {}
local function setInArena(player, inArena, spawnCF, noFade)
	if moving[player] then return end
	if not noFade and Transition:GetAttribute("Enabled") ~= false and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		moving[player] = true
		Transition:FireClient(player, "In")
		task.wait((Transition:GetAttribute("FadeIn") or 0.15) + 0.03)
		moving[player] = nil
		if player.Parent ~= Players then return end
		task.delay(Transition:GetAttribute("Hold") or 0.1, function() if player.Parent then Transition:FireClient(player, "Out") end end)
	end
	player:SetAttribute("InArena", inArena == true)
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local cf = inArena and (spawnCF or arenaSpawnCF(player)) or lobbyCF()
		if cf then char:PivotTo(cf) end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = hum.MaxHealth end
	end
end

local fn = Instance.new("BindableFunction")
fn.Name = "SetInArena"
-- (matches use this: they have their own fade, so no loading screen here)
fn.OnInvoke = function(player, inArena, spawnCF) return setInArena(player, inArena, spawnCF, true) end
fn.Parent = script

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("InArena", false)
	player.CharacterAdded:Connect(function(char)
		-- died in the arena -> come back in the arena (matches handle their own respawns)
		if player:GetAttribute("InArena") and player:GetAttribute("MatchId") == nil then
			char:WaitForChild("HumanoidRootPart")
			task.wait()
			local cf = arenaSpawnCF(player)
			if cf then char:PivotTo(cf) else player:SetAttribute("InArena", false) end
		end
	end)
end)
for _, p in Players:GetPlayers() do
	if p:GetAttribute("InArena") == nil then p:SetAttribute("InArena", false) end
end

-- enter pads: they ask "Aim Training or Practice Arena?" (once, until you walk away from the wall)
local debounce = {}
local asked = {} -- [player] = the pad they were asked at
local function ask(player, pad)
	if asked[player] or player:GetAttribute("InArena") or player:GetAttribute("MatchId") ~= nil then return end
	if player:GetAttribute("WatchingReplay") or player:GetAttribute("WatchingMatch") then return end
	asked[player] = pad
	ChoiceRemote:FireClient(player, "Show", pad)
end
local function nearPad(player, dist)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pad = asked[player]
	if not root or not pad or not pad.Parent then return false end
	local rel = pad.CFrame:PointToObjectSpace(root.Position)
	local half = pad.Size / 2
	local dx, dy, dz = math.max(math.abs(rel.X) - half.X, 0), math.max(math.abs(rel.Y) - half.Y, 0), math.max(math.abs(rel.Z) - half.Z, 0)
	return Vector3.new(dx, dy, dz).Magnitude <= dist
end
ChoiceRemote.OnServerEvent:Connect(function(player, choice)
	if not asked[player] then return end
	if choice == "Cancel" then
		-- (asked again only after walking away and coming back)
		return
	end
	if player:GetAttribute("InArena") or player:GetAttribute("MatchId") ~= nil or not nearPad(player, 30) then return end
	debounce[player] = os.clock()
	if choice == "Arena" then
		setInArena(player, true)
	elseif choice == "AimTraining" then
		local ok, cf = pcall(function() return AimServer.Enter:Invoke(player) end)
		if ok and cf then setInArena(player, true, cf) end
	end
end)
task.spawn(function()
	-- walked away from the wall: they can be asked again next time
	while true do
		task.wait(0.3)
		for player in asked do
			if player.Parent ~= Players or player:GetAttribute("InArena") or not nearPad(player, 20) then
				if player.Parent == Players and not player:GetAttribute("InArena") then ChoiceRemote:FireClient(player, "Hide") end
				asked[player] = nil
			end
		end
	end
end)
local hooked = {}
local function hookPad(part)
	if hooked[part] or not part:IsA("BasePart") then return end
	hooked[part] = true
	part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player or player:GetAttribute("InArena") then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if debounce[player] and os.clock() - debounce[player] < 1 then return end
		ask(player, part)
	end)
end
for _, d in workspace:GetDescendants() do
	if d.Name == ENTER_NAME then hookPad(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d.Name == ENTER_NAME then hookPad(d) end
end)
for _, p in CollectionService:GetTagged(ENTER_NAME) do hookPad(p) end
CollectionService:GetInstanceAddedSignal(ENTER_NAME):Connect(hookPad)

-- exit: only the big white panel Workspace > PracticeArena > Door > ExitPanel sends you back to the lobby
local function hookExit(part)
	if not part:IsA("BasePart") then return end
	part.CanTouch = true
	part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player or not player:GetAttribute("InArena") then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if debounce[player] and os.clock() - debounce[player] < 1 then return end
		debounce[player] = os.clock()
		setInArena(player, false)
	end)
end
local EXIT_NAME = "ExitPanel"
local exitPanels = {} -- every exit panel in the game (found by name or tag, wherever it lives)
local hookedExit = {}
local function addExit(part)
	if hookedExit[part] or not part:IsA("BasePart") then return end
	hookedExit[part] = true
	table.insert(exitPanels, part)
	hookExit(part)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			local i = table.find(exitPanels, part)
			if i then table.remove(exitPanels, i) end
			hookedExit[part] = nil
		end
	end)
end
for _, d in workspace:GetDescendants() do
	if d.Name == EXIT_NAME then addExit(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d.Name == EXIT_NAME then addExit(d) end
end)
for _, p in CollectionService:GetTagged(EXIT_NAME) do addExit(p) end
CollectionService:GetInstanceAddedSignal(EXIT_NAME):Connect(addExit)
if #exitPanels == 0 then
	warn("[ArenaServer] no part named ExitPanel found – name the practice arena's leave door ExitPanel")
end

-- ZONE CHECK: touching can be blocked by decoration (e.g. the VFX parts in front of the doors),
-- so we also check if a player is standing right in front of / inside a door panel.
local ZONE_DEPTH = 6 -- studs of "reach" through the panel's thickness
local function inZone(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	-- the thinnest axis of the panel is the one you walk through
	local sx, sy, sz = half.X, half.Y, half.Z
	local thin = math.min(sx, sy, sz)
	if sx == thin then sx += ZONE_DEPTH / 2 elseif sy == thin then sy += ZONE_DEPTH / 2 else sz += ZONE_DEPTH / 2 end
	return math.abs(rel.X) <= sx and math.abs(rel.Y) <= sy + 3 and math.abs(rel.Z) <= sz
end
task.spawn(function()
	while true do
		task.wait(0.15)
		local enters = {}
		for _, d in workspace:GetDescendants() do
			if d.Name == ENTER_NAME and d:IsA("BasePart") then table.insert(enters, d) end
		end

		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 and player:GetAttribute("MatchId") == nil and not (debounce[player] and os.clock() - debounce[player] < 1) then
				if player:GetAttribute("InArena") then
					for _, exitPanel in exitPanels do
						if exitPanel.Parent and inZone(exitPanel, root.Position) then
							debounce[player] = os.clock()
							task.spawn(setInArena, player, false)
							break
						end
					end
				else
					for _, pad in enters do
						if inZone(pad, root.Position) then
							ask(player, pad)
							break
						end
					end
				end
			end
		end
	end
end)

LeaveArena.OnServerEvent:Connect(function(player)
	if player:GetAttribute("MatchId") ~= nil then return end -- can't leave a real match this way
	if player:GetAttribute("InArena") then setInArena(player, false) end
end)
Players.PlayerRemoving:Connect(function(p) debounce[p] = nil asked[p] = nil moving[p] = nil end)

------------------------------------------------------------ PRACTICE BOARD
-- Shows the headshots of everyone in the practice arena on the lobby door's white panel.
-- Look / layout: Workspace > Lobby > Door > PracticeArenaEnter > PracticePlayers (edit "Template" to restyle tiles)
local function refreshBoard()
	for _, panel in workspace:GetDescendants() do
		if panel.Name == ENTER_NAME and panel:IsA("BasePart") then
			local sg = panel:FindFirstChild("PracticePlayers")
			local grid = sg and sg:FindFirstChild("Grid")
			local template = sg and sg:FindFirstChild("Template")
			if grid and template then
				template.Visible = false -- the Template is just the design; copies of it go in the Grid
				local inArena = {}
				for _, p in Players:GetPlayers() do
					if p:GetAttribute("InArena") and p:GetAttribute("MatchId") == nil then table.insert(inArena, p) end
				end
				-- remove tiles for players who left
				for _, t in grid:GetChildren() do
					if t:IsA("Frame") then
						local keep = false
						for _, p in inArena do if t.Name == tostring(p.UserId) then keep = true end end
						if not keep then t:Destroy() end
					end
				end
				-- add tiles for new ones
				for i, p in inArena do
					local t = grid:FindFirstChild(tostring(p.UserId))
					if not t then
						t = template:Clone()
						t.Name = tostring(p.UserId)
						t:FindFirstChild("Head", true).Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(p.UserId, 1))
						local nameLabel = t:FindFirstChild("PlayerName", true)
						if nameLabel then nameLabel.Text = NameBadge.Of(p) end
						t.Visible = true
						t.Parent = grid
					end
					t.LayoutOrder = i
				end
				local empty = sg:FindFirstChild("Empty")
				if empty then empty.Visible = #inArena == 0 end
			end
		end
	end
end
local function watch(p)
	p:GetAttributeChangedSignal("InArena"):Connect(refreshBoard)
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do watch(p) end
Players.PlayerRemoving:Connect(function() task.defer(refreshBoard) end)
refreshBoard()
