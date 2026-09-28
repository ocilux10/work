-- LIVE SPECTATE (client) - watch any match running in this server.
-- Lists: the SPECTATE wall in the lobby (Workspace > Lobby > Main > Edges > SpectateGui) and the Spectate tab of the
-- camera menu (top bar > Main > WatchFrame). Rows: leading side green, other red. Click the eye to watch.
-- Watching: first person through a player's eyes (their arms + balloon). Keys (Settings > Controls > Spectate & Replays):
-- Q / E previous / next player, V freecam (WASD, E / Q up / down, Shift faster, hold right mouse to look),
-- leave = your Leave Practice Arena key (G). Phones: tap the buttons; freecam = thumbstick + drag to look.
-- HUD look: StarterGui > SpectateHUD (restyle freely - keep the names). Server: ServerScriptService > LiveSpectateServer.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local MM = RS:WaitForChild("Matchmaking")
local Remotes = MM:WaitForChild("Remotes")
local LiveFolder = MM:WaitForChild("LiveMatches")
local Remote = Remotes:WaitForChild("LiveSpectate")
local CamRemote = Remotes:WaitForChild("LiveSpectateCam")
local GS = require(RS:WaitForChild("GameSettings"))
local SFX = require(RS:WaitForChild("SFX"))
local CombatConfig = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))
local ClientActions = RS:WaitForChild("BalloonCombat"):WaitForChild("ClientActions")

local GREEN = Color3.fromRGB(60, 235, 110)
local RED = Color3.fromRGB(255, 70, 70)
local DARK = Color3.fromRGB(28, 28, 34)
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FREECAM_SPEED, FREECAM_FAST = 28, 70
local DEATH_CAM_TIME = 2.5 -- seconds the camera rides the ragdoll before moving to someone still alive

local isPhone = UIS.TouchEnabled and not UIS.KeyboardEnabled
-- controller: right stick position (freecam looks around with it)
local function padStick()
	local ok, states = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
	if not ok then return Vector2.zero end
	for _, s in states do
		if s.KeyCode == Enum.KeyCode.Thumbstick2 then return Vector2.new(s.Position.X, s.Position.Y) end
	end
	return Vector2.zero
end
local function headshot(id) return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(id, 1)) end
local function decode(s)
	local ok, t = pcall(HttpService.JSONDecode, HttpService, s or "[]")
	return ok and type(t) == "table" and t or {}
end
local function notice(text)
	local main = pg:FindFirstChild("Main")
	local n = main and main:FindFirstChild("DuelNotice")
	if not (n and n:IsA("TextLabel")) then return end
	n.Text = text
	n.Visible = true
	local token = (n:GetAttribute("Token") or 0) + 1
	n:SetAttribute("Token", token)
	task.delay(2.5, function() if n:GetAttribute("Token") == token then n.Visible = false end end)
end
-- leading team green, the other red (a draw: team 1 green, team 2 red)
local function sideColors(s1, s2)
	if s2 > s1 then return RED, GREEN end
	return GREEN, RED
end

local watch -- forward declared: watch(matchId)

------------------------------------------------------------ THE LISTS (wall + camera menu)
local function faces(row, slotName, team, color, rightAlign)
	-- the slot keeps exactly the position / size it has in the design; with more players on a team, their faces
	-- share that same space side by side (team 1 packs toward VS from the left, team 2 from the right)
	local slot = row:FindFirstChild(slotName)
	if not slot then return end
	for _, c in row:GetChildren() do if c.Name == slotName .. "_Extra" then c:Destroy() end end
	local basePos = slot:GetAttribute("BasePos") or slot.Position
	local baseSize = slot:GetAttribute("BaseSize") or slot.Size
	slot:SetAttribute("BasePos", basePos)
	slot:SetAttribute("BaseSize", baseSize)
	local n = math.max(#team, 1)
	for i = 1, n do
		local f = i == 1 and slot or slot:Clone()
		if i > 1 then f.Name = slotName .. "_Extra" f.Parent = row end
		local m = team[i]
		if f:IsA("ImageLabel") or f:IsA("ImageButton") then f.Image = m and headshot(m.UserId) or "" end
		f.BackgroundColor3 = color
		local stroke = f:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = color end
		if n == 1 then
			f.Position, f.Size = basePos, baseSize
		else
			local w = UDim.new(baseSize.X.Scale / n, baseSize.X.Offset / n)
			local k = rightAlign and (n - i) or (i - 1)
			f.Size = UDim2.new(w, baseSize.Y)
			f.Position = UDim2.new(basePos.X.Scale + w.Scale * k, basePos.X.Offset + w.Offset * k, basePos.Y.Scale, basePos.Y.Offset)
		end
	end
end

local function paintRow(row, f)
	local s1, s2 = f:GetAttribute("Score1") or 0, f:GetAttribute("Score2") or 0
	local c1, c2 = sideColors(s1, s2)
	local sc1, sc2 = row:FindFirstChild("Score1"), row:FindFirstChild("Score2")
	if sc1 then sc1.Text = tostring(s1) sc1.TextColor3 = c1 end
	if sc2 then sc2.Text = tostring(s2) sc2.TextColor3 = c2 end
	faces(row, "Player1", decode(f:GetAttribute("Team1")), c1, true)
	faces(row, "Player2", decode(f:GetAttribute("Team2")), c2, false)
	local map = row:FindFirstChild("MapLabel")
	local img = f:GetAttribute("Image") or ""
	if map and map:IsA("ImageLabel") and img ~= "" then map.Image = img end
	-- the drawn eye on the watch button hides if the button has its own picture
	local btn = row:FindFirstChild("SpectateImage")
	local drawn = btn and btn:FindFirstChild("Drawn")
	if drawn then drawn.Visible = btn.Image == "" end
end

local lists = {} -- {scroll, tpl, rows = {[matchId] = row}, empty}
local function makeEmpty(scroll)
	-- the designed "EmptyText" label in the list (restyle it freely); made here only if it's missing
	local designed = scroll:FindFirstChild("EmptyText")
	if designed then designed.LayoutOrder = -1 return designed end
	local l = Instance.new("TextLabel")
	l.Name = "NoMatches"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 0.08)
	l.FontFace = FONT
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(220, 225, 235)
	l.TextTransparency = 0.2
	l.Text = "No matches right now"
	l.LayoutOrder = -1
	l.Parent = scroll
	return l
end
local function refreshList(list)
	if not list.scroll.Parent then return end
	local all = LiveFolder:GetChildren()
	table.sort(all, function(x, y) return (x:GetAttribute("StartedAt") or 0) < (y:GetAttribute("StartedAt") or 0) end)
	local keepIds = {}
	for i, f in all do
		keepIds[f.Name] = true
		local row = list.rows[f.Name]
		if not row then
			row = list.tpl:Clone()
			row.Name = "Live_" .. f.Name
			row.Visible = true
			local btn = row:FindFirstChild("SpectateImage")
			if btn and btn:IsA("GuiButton") then
				local id = f.Name
				btn.Activated:Connect(function() watch(id) end)
			end
			row.Parent = list.scroll
			list.rows[f.Name] = row
			f.AttributeChanged:Connect(function() if list.rows[f.Name] == row then paintRow(row, f) end end)
		end
		row.LayoutOrder = i
		paintRow(row, f)
	end
	for id, row in list.rows do
		if not keepIds[id] then row:Destroy() list.rows[id] = nil end
	end
	if list.empty then list.empty.Visible = next(list.rows) == nil end
end
local function refreshAll() for _, l in lists do refreshList(l) end end
local function addList(scroll, tpl, fit)
	local list = {scroll = scroll, tpl = tpl, rows = {}}
	list.empty = makeEmpty(scroll)
	if fit then
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
		local lay = scroll:FindFirstChildOfClass("UIListLayout")
		if lay then lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() scroll.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 10) end) end
	end
	table.insert(lists, list)
	refreshList(list)
	return list
end

local wallTemplate
-- LIVE DESIGN: change a row template while playing (Studio play test / a live session) and the rows rebuild with it
local function watchTemplate(inst, onChange)
	local pending = false
	local function changed()
		if pending then return end
		pending = true
		task.delay(0.25, function() pending = false onChange() end)
	end
	local function hook(d) d.Changed:Connect(changed) end
	hook(inst)
	for _, d in inst:GetDescendants() do hook(d) end
	inst.DescendantAdded:Connect(function(d) hook(d) changed() end)
	inst.DescendantRemoving:Connect(changed)
end
local function rebuildList(list, newTpl)
	list.tpl = newTpl
	for _, r in list.rows do r:Destroy() end
	table.clear(list.rows)
	refreshList(list)
end

local menuHooked = setmetatable({}, {__mode = "k"})
local function hookMenu(main)
	if menuHooked[main] then return end
	local wf = main:WaitForChild("WatchFrame", 10)
	local scroll = wf and wf:WaitForChild("SpectateList", 10)
	local hasOwn = wf and wf:FindFirstChild("Templates") and wf.Templates:FindFirstChild("SpectateRow")
	if not (scroll and (hasOwn or wallTemplate)) then return end
	menuHooked[main] = true
	for i = #lists, 1, -1 do if not lists[i].scroll.Parent then table.remove(lists, i) end end
	-- the menu's own row design: WatchFrame > Templates > SpectateRow (falls back to the wall's row if it's deleted)
	local own = wf:FindFirstChild("Templates") and wf.Templates:FindFirstChild("SpectateRow")
	local tpl
	if own then
		tpl = own:Clone()
		tpl.Visible = true
	else
		tpl = wallTemplate:Clone()
		tpl.Size = UDim2.new(0.97, 0, 0, 0)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectType = Enum.AspectType.ScaleWithParentSize
		ar.DominantAxis = Enum.DominantAxis.Width
		ar.AspectRatio = 7
		ar.Parent = tpl
	end
	local lay = scroll:FindFirstChildOfClass("UIListLayout")
	if not lay then
		lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.Parent = scroll
	end
	lay.SortOrder = Enum.SortOrder.LayoutOrder -- (rows go in order; padding / alignment are yours to set)
	local list = addList(scroll, tpl, true)
	if own then
		watchTemplate(own, function()
			local fresh = own:Clone()
			fresh.Visible = true
			rebuildList(list, fresh)
		end)
	end
end

-- the menu list works on its own (it doesn't need the wall)
LiveFolder.ChildAdded:Connect(function() task.defer(refreshAll) end)
LiveFolder.ChildRemoved:Connect(function() task.defer(refreshAll) end)
do
	local m = pg:FindFirstChild("Main")
	if m then task.spawn(hookMenu, m) end
	pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hookMenu, c) end end)
end

-- the wall: a SurfaceGui called "SpectateGui" ANYWHERE in the world (move it wherever you like). The real one stays as
-- the design; this screen shows its own copy (clicks on walls only work from PlayerGui). The original is switched off
-- every time it (re)appears - streaming can bring it back.
task.spawn(function()
	local original
	local function isWall(d) return d:IsA("SurfaceGui") and d.Name == "SpectateGui" end
	while not original do
		for _, d in workspace:GetDescendants() do
			if isWall(d) then original = d break end
		end
		if not original then task.wait(2) end
	end
	local edges = workspace
	local wall = original:Clone()
	wall.Name = "SpectateWall"
	wall.Adornee = original.Parent
	wall.ResetOnSpawn = false
	wall.Parent = pg
	original.Enabled = false
	edges.DescendantAdded:Connect(function(d)
		if isWall(d) then
			d.Enabled = false
			if d.Parent then wall.Adornee = d.Parent end
		end
	end)
	local scroll = wall:FindFirstChild("SpectateScrolling", true)
	local tpl = scroll and scroll:FindFirstChild("Game1")
	-- (the list always shows on the wall, even if it was hidden while designing)
	if scroll then scroll.Visible = true end
	if not tpl then warn("[LiveSpectate] SpectateGui has no SpectateScrolling > Game1 row") return end
	tpl.Parent = nil -- (kept only as the row design, never shown)
	wallTemplate = tpl:Clone()
	wallTemplate.Visible = true
	local wallList = addList(scroll, wallTemplate, false)
	local designRow = original:FindFirstChild("Game1", true)
	if designRow then
		watchTemplate(designRow, function()
			wallTemplate = designRow:Clone()
			wallTemplate.Visible = true
			rebuildList(wallList, wallTemplate:Clone())
		end)
	end
	-- (menu hooked above; if it had no template of its own it can use the wall's row now)
	local m = pg:FindFirstChild("Main")
	if m then task.spawn(hookMenu, m) end
end)

------------------------------------------------------------ HUD (StarterGui > SpectateHUD)
local hud = pg:WaitForChild("SpectateHUD", 300) -- (a timeout = no "infinite yield" warning while the loading screen is up)
hud.Enabled = false
local top = hud:WaitForChild("Top")
local team1Holder, team2Holder, mid = top:WaitForChild("Team1"), top:WaitForChild("Team2"), top:WaitForChild("Middle")
local timerLabel, score1, score2 = mid:WaitForChild("Timer"), mid:WaitForChild("Score1"), mid:WaitForChild("Score2")
local faceTpl = hud:WaitForChild("FaceTemplate")
local mapLabel = hud:WaitForChild("Watching")
local viewers = hud:WaitForChild("Viewers")
local viewersCount = viewers:WaitForChild("Count")
local bottom = hud:WaitForChild("Bottom")
local prevBtn, nextBtn, nameBar = bottom:WaitForChild("Prev"), bottom:WaitForChild("Next"), bottom:WaitForChild("NameBar")
local prevKey, nextKey = prevBtn:FindFirstChild("Key"), nextBtn:FindFirstChild("Key")
local nameLabel, nameLine, nameGrad = nameBar:WaitForChild("Name"), nameBar:FindFirstChild("Line") -- (Line is optional: delete it and the colour goes on the gradient only), nameBar:FindFirstChildOfClass("UIGradient")
local hpLabel, hpBack = hud:WaitForChild("HP"), hud:WaitForChild("HPBar")
local hpFill = hpBack:WaitForChild("Fill")
local freeBtn, leaveBtn = hud:WaitForChild("Freecam"), hud:WaitForChild("Leave")
local freeKey = freeBtn:FindFirstChild("Key", true)
local leaveKey = leaveBtn:FindFirstChild("Key", true)
local freeColor = freeBtn.BackgroundColor3
local eyeImg = viewers:FindFirstChild("Eye")
if eyeImg and eyeImg:FindFirstChild("Drawn") then eyeImg.Drawn.Visible = eyeImg.Image == "" end

-- phones: no key letters
for _, k in {prevKey, nextKey} do if k then k.Visible = not isPhone end end
for _, b in {freeBtn, leaveBtn} do
	local kb = b:FindFirstChild("KeyBox")
	if kb then kb.Visible = not isPhone end
end

local function scaleHud()
	-- (attribute AutoScale on the HUD: false = keep the sizes exactly as designed)
	if hud:GetAttribute("AutoScale") == false then return end
	local vp = workspace.CurrentCamera.ViewportSize
	local s = math.clamp(vp.X / 1500, 0.5, 1.1)
	for _, g in {top, bottom, freeBtn, leaveBtn, hpBack, hpLabel, mapLabel, viewers} do
		local u = g:FindFirstChild("HudScale") or Instance.new("UIScale")
		u.Name = "HudScale"
		u.Scale = s
		u.Parent = g
	end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(scaleHud)
scaleHud()

local function keyText(action)
	local t = GS.Keys(action)
	local k = (t[1] and t[1] ~= "" and t[1]) or t[2] or ""
	return GS.KeyText(k) or ""
end
local function showKeys()
	if prevKey then prevKey.Text = keyText("SpectatePrev") end
	if nextKey then nextKey.Text = keyText("SpectateNext") end
	if freeKey then freeKey.Text = keyText("Freecam") end
	if leaveKey then leaveKey.Text = keyText("LeaveArena") end
end
GS.Changed:Connect(function(key) if type(key) == "string" and (key:sub(1, 4) == "Key_" or key:sub(1, 4) == "Pad_" or key == "PadButtonStyle") then showKeys() end end)
showKeys()

------------------------------------------------------------ WATCHING
local watching -- match id
local folder -- its LiveMatches folder
local target -- the Player being watched
local look = Vector3.new(0, 0, -1)
local free = false
local freeCF = CFrame.new()
local oldFOV
local diedAt -- when the watched player died (death camera)
local lastEye, lastLook -- where the watched player was looking from the last moment they were alive
local deathFloor -- how low the death camera may drop (the ground under where they died)
local connections = {}

local function members()
	local list = {}
	if not folder then return list end
	for t = 1, 2 do
		for _, m in decode(folder:GetAttribute("Team" .. t)) do
			local p = Players:GetPlayerByUserId(m.UserId)
			if p then table.insert(list, {player = p, team = t}) end
		end
	end
	return list
end
local function alive(p)
	local c = p and p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and not p:GetAttribute("MatchDead") and not p:GetAttribute("Spectating")
end

local function paintTop()
	if not folder then return end
	local s1, s2 = folder:GetAttribute("Score1") or 0, folder:GetAttribute("Score2") or 0
	local c1, c2 = sideColors(s1, s2)
	score1.Text, score2.Text = tostring(s1), tostring(s2)
	score1.TextColor3, score2.TextColor3 = c1, c2
	for t, holder in {team1Holder, team2Holder} do
		for _, c in holder:GetChildren() do if c:IsA("ImageLabel") then c:Destroy() end end
		for i, m in decode(folder:GetAttribute("Team" .. t)) do
			local img = faceTpl:Clone()
			img.Name = tostring(m.UserId)
			img.Visible = true
			img.LayoutOrder = t == 1 and -i or i
			img.BackgroundColor3 = t == 1 and c1 or c2
			img.Image = headshot(m.UserId)
			local p = Players:GetPlayerByUserId(m.UserId)
			if p and not alive(p) then img.ImageTransparency = 0.6 end
			img.Parent = holder
		end
	end
	mapLabel.Text = ("SPECTATING  •  %s  •  %s"):format((folder:GetAttribute("Map") or ""):upper(), folder:GetAttribute("Mode") or "")
end

local function paintName()
	if not target then nameLabel.Text = "" return end
	nameLabel.Text = NameBadge.Of(target)
	local s1, s2 = folder and folder:GetAttribute("Score1") or 0, folder and folder:GetAttribute("Score2") or 0
	local c1, c2 = sideColors(s1, s2)
	local c = (target:GetAttribute("MatchTeam") or 1) == 2 and c2 or c1
	if nameLine then nameLine.BackgroundColor3 = c end
	if nameGrad then nameGrad.Color = ColorSequence.new(DARK, DARK:Lerp(c, 0.45)) end
end

local function tellTarget()
	if not target then return end
	local id = target.UserId
	task.spawn(function() pcall(function() Remote:InvokeServer("Target", id) end) end)
end
local function setTarget(p)
	if not p then return end
	target = p
	diedAt = nil
	lastEye, lastLook = nil, nil
	local head = p.Character and p.Character:FindFirstChild("Head")
	local l = p:GetAttribute("AimLook")
	look = typeof(l) == "Vector3" and l or (head and head.CFrame.LookVector) or look
	ClientActions:Fire("SpectateTarget", p.UserId)
	tellTarget()
	paintName()
end

local function cycle(dir)
	local list = members()
	if #list == 0 then return end
	local cur = 0
	for i, m in list do if m.player == target then cur = i end end
	for step = 1, #list do
		local i = ((cur - 1 + dir * step) % #list) + 1
		if alive(list[i].player) or step == #list then
			setTarget(list[i].player)
			break
		end
	end
	SFX.Play("ButtonPress")
end

local function crosshair(on)
	local ui = pg:FindFirstChild("BalloonCombatUI")
	local ch = ui and ui:FindFirstChild("Crosshair")
	if ch and ch:IsA("GuiObject") and ch.Visible ~= on then ch.Visible = on end
end

local function setFree(on)
	free = on
	if on then
		freeCF = workspace.CurrentCamera.CFrame
	else
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		tellTarget() -- counted as watching them again
	end
	ClientActions:Fire("SpectateFreecam", on)
	freeBtn.BackgroundColor3 = on and freeColor:Lerp(Color3.new(1, 1, 1), 0.25) or freeColor
end

-- back in the lobby: make sure the lobby UI is really back (bottom buttons, XP bar, top bar...), whatever hid it
local function restoreLobbyUI()
	task.spawn(function()
		-- (wait for the server to clear WatchingMatch, up to 5s, instead of giving up - that left the lobby UI hidden)
		local t0 = os.clock()
		repeat task.wait(0.1) until not (player:GetAttribute("WatchingReplay") or player:GetAttribute("WatchingMatch")) or os.clock() - t0 > 5 or watching
		if watching then return end
		local main = pg:FindFirstChild("Main")
		if not main or player:GetAttribute("MatchId") ~= nil or player:GetAttribute("InArena") then return end
		main.Enabled = true
		for _, c in main:GetChildren() do
			if c:IsA("GuiObject") and c:GetAttribute("LobbyVisible") == true and not c.Visible then c.Visible = true end
		end
		-- the lobby HUD always comes back (its LobbyVisible can have been saved while a menu had hidden it)
		for _, n in {"Buttons", "XpBar", "Bottom", "Top", "Quests"} do
			local c = main:FindFirstChild(n)
			if c and c:IsA("GuiObject") then c:SetAttribute("LobbyVisible", true) c.Visible = true end
		end
		local mm = main:FindFirstChild("MenuManager")
		local ev = mm and mm:FindFirstChild("Refocus")
		if ev then ev:Fire() end
	end)
end
local function stopWatching(tellServer)
	if not watching then return end
	watching, folder, target = nil, nil, nil
	for _, c in connections do c:Disconnect() end
	table.clear(connections)
	RunService:UnbindFromRenderStep("LiveSpectateCamera")
	free = false
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	hud.Enabled = false
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	if oldFOV then cam.FieldOfView = oldFOV end
	ClientActions:Fire("SpectateEnd")
	crosshair(false)
	local main = pg:FindFirstChild("Main")
	if main then main.Enabled = true end
	local w = pg:FindFirstChild("SpectateWall") if w then w.Enabled = true end
	if tellServer ~= false then task.spawn(function() pcall(function() Remote:InvokeServer("Stop") end) end) end
	restoreLobbyUI()
end

watch = function(id)
	if watching or player:GetAttribute("WatchingReplay") then return end
	local ok, res, why = pcall(function() return Remote:InvokeServer("Watch", id) end)
	if not (ok and res) then
		SFX.Play("Error")
		notice((ok and why) or "Couldn't spectate right now")
		return
	end
	folder = LiveFolder:FindFirstChild(id)
	if not folder then pcall(function() Remote:InvokeServer("Stop") end) return end
	watching = id
	SFX.Play("Open")
	local menu = pg:FindFirstChild("Main") and pg.Main:FindFirstChild("WatchFrame")
	if menu then menu.Visible = false end
	local cam = workspace.CurrentCamera
	oldFOV = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = GS.Get("FOV") or CombatConfig.CameraFOV or 70
	hud.Enabled = true
	free = false
	freeBtn.BackgroundColor3 = freeColor
	paintTop()
	ClientActions:Fire("SpectateStart")
	local list = members()
	local first = list[1] and list[1].player
	for _, m in list do if alive(m.player) then first = m.player break end end
	setTarget(first)
	table.insert(connections, folder.AttributeChanged:Connect(function() paintTop() paintName() end))
	table.insert(connections, folder.AncestryChanged:Connect(function()
		if folder and not folder.Parent then
			notice("The match ended")
			stopWatching()
		end
	end))

	local camPosSent = 0
	RunService:BindToRenderStep("LiveSpectateCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not watching then return end
		local main = pg:FindFirstChild("Main")
		if main and main.Enabled then main.Enabled = false end
		local wall = pg:FindFirstChild("SpectateWall") if wall and wall.Enabled then wall.Enabled = false end
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
		-- timer
		local endsAt = folder and folder:GetAttribute("EndsAt") or 0
		if endsAt > 0 then
			local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
			timerLabel.Text = ("%d:%02d"):format(left // 60, left % 60)
			timerLabel.TextColor3 = left <= 10 and RED or Color3.new(1, 1, 1)
		else
			timerLabel.Text = "ROUND " .. tostring(folder and folder:GetAttribute("Round") or 1)
			timerLabel.TextColor3 = Color3.new(1, 1, 1)
		end
		-- the eye: how many people watch this player
		local n = target and target:GetAttribute("Spectators") or 0
		viewers.Visible = n > 0 and not free
		viewersCount.Text = tostring(n)

		if free then
			crosshair(false)
			local move = Vector3.zero
			if isPhone or UIS:GetLastInputType() == Enum.UserInputType.Touch or GS.UsingGamepad() then
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				move = hum and hum.MoveDirection or Vector3.zero
			elseif not UIS:GetFocusedTextBox() then
				local lv, rv = freeCF.LookVector, freeCF.RightVector
				if GS.IsDown("MoveForward") then move += lv end
				if GS.IsDown("MoveBackward") then move -= lv end
				if GS.IsDown("StrafeRight") then move += rv end
				if GS.IsDown("StrafeLeft") then move -= rv end
				if GS.IsDown("FreecamUp") then move += Vector3.yAxis end
				if GS.IsDown("FreecamDown") then move -= Vector3.yAxis end
			end
			local speed = GS.IsDown("Sprint") and FREECAM_FAST or FREECAM_SPEED
			if move.Magnitude > 0 then freeCF += move.Unit * speed * dt end
			local pst = padStick()
			if pst.Magnitude > 0.15 then
				local pp, py = freeCF:ToEulerAnglesYXZ()
				pp = math.clamp(pp + pst.Y * dt * 2.2, math.rad(-85), math.rad(85))
				py -= pst.X * dt * 3
				freeCF = CFrame.new(freeCF.Position) * CFrame.fromEulerAnglesYXZ(pp, py, 0)
			end
			if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				local d = UIS:GetMouseDelta()
				local pitch, yaw = freeCF:ToEulerAnglesYXZ()
				pitch = math.clamp(pitch - d.Y * 0.004, math.rad(-85), math.rad(85))
				yaw -= d.X * 0.004
				freeCF = CFrame.new(freeCF.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
			elseif UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
				UIS.MouseBehavior = Enum.MouseBehavior.Default
			end
			cam.CFrame = freeCF
			if os.clock() - camPosSent > 0.3 then
				camPosSent = os.clock()
				CamRemote:FireServer(freeCF.Position)
			end
			hpLabel.Visible, hpBack.Visible = false, false
			return
		end

		if not target or target.Parent ~= Players then
			local list = members()
			if #list > 0 then setTarget(list[1].player) end
		end
		local char = target and target.Character
		local head = char and char:FindFirstChild("Head")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		hpLabel.Visible, hpBack.Visible = true, true

		if target and not alive(target) then
			-- DEATH CAMERA: drops and tips over from where they died (not glued to the body: dead players get moved away /
			-- the ragdoll can slip through the floor), never below the ground there. Then moves on to someone still fighting.
			if not diedAt then
				diedAt = os.clock()
				lastEye = lastEye or (head and head.Position) or cam.CFrame.Position
				lastLook = lastLook or cam.CFrame.LookVector
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local ignore = {cam}
				for _, pl in Players:GetPlayers() do if pl.Character then table.insert(ignore, pl.Character) end end
				params.FilterDescendantsInstances = ignore
				local hit = workspace:Raycast(lastEye, Vector3.new(0, -12, 0), params)
				deathFloor = hit and hit.Position.Y + 0.6 or (lastEye.Y - 1.8)
			end
			crosshair(false)
			local fall = math.clamp((os.clock() - diedAt) / 0.45, 0, 1)
			local flat = Vector3.new(lastLook.X, 0, lastLook.Z)
			if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end
			local eye = Vector3.new(lastEye.X, math.max(lastEye.Y - 1.8 * fall, deathFloor), lastEye.Z)
			local base = CFrame.lookAt(eye, eye + lastLook:Lerp(flat.Unit, fall).Unit)
			cam.CFrame = base * CFrame.Angles(math.rad(-25) * fall, 0, math.rad(70) * fall)
			hpLabel.Text = "0 HP"
			hpFill.Size = UDim2.fromScale(0, 1)
			if os.clock() - diedAt > DEATH_CAM_TIME then
				for _, m in members() do if alive(m.player) and m.player ~= target then setTarget(m.player) break end end
			end
			return
		end
		diedAt = nil
		crosshair(true)
		if head then
			local want = target:GetAttribute("AimLook")
			if typeof(want) ~= "Vector3" then want = head.CFrame.LookVector end
			look = look:Lerp(want, math.min(1, dt * 18))
			if look.Magnitude < 0.1 then look = want end
			local eye = head.Position + Vector3.new(0, 0.1, 0)
			cam.CFrame = CFrame.lookAt(eye, eye + look.Unit)
			lastEye, lastLook = eye, look.Unit
		end
		if hum then
			hpLabel.Text = math.max(0, math.floor(hum.Health + 0.5)) .. " HP"
			local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			hpFill.Size = UDim2.fromScale(frac, 1)
			hpFill.BackgroundColor3 = frac > 0.5 and GREEN or (frac > 0.25 and Color3.fromRGB(255, 170, 60) or RED)
		end
	end)
end

------------------------------------------------------------ INPUT
prevBtn.Activated:Connect(function() if watching then if free then setFree(false) end cycle(-1) end end)
nextBtn.Activated:Connect(function() if watching then if free then setFree(false) end cycle(1) end end)
freeBtn.Activated:Connect(function() if watching then setFree(not free) SFX.Play("ButtonPress") end end)
leaveBtn.Activated:Connect(function() stopWatching() end)
UIS.InputBegan:Connect(function(input, gpe)
	if not watching or gpe then return end
	if GS.Is("LeaveArena", input) then
		stopWatching()
	elseif GS.Is("Freecam", input) then
		setFree(not free)
	elseif free then
		return -- in freecam E / Q fly up / down (the switch keys only work in first person)
	elseif GS.Is("SpectatePrev", input) then
		cycle(-1)
	elseif GS.Is("SpectateNext", input) then
		cycle(1)
	end
end)
UIS.TouchMoved:Connect(function(touch, gpe)
	if not (watching and free) or gpe then return end
	local d = touch.Delta
	local pitch, yaw = freeCF:ToEulerAnglesYXZ()
	pitch = math.clamp(pitch - d.Y * 0.006, math.rad(-85), math.rad(85))
	yaw -= d.X * 0.006
	freeCF = CFrame.new(freeCF.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end)

-- the server stopped it (match over / you got pulled into a match) -> tidy up here too
player:GetAttributeChangedSignal("WatchingMatch"):Connect(function()
	if watching and player:GetAttribute("WatchingMatch") == nil then stopWatching(false) end
end)
player.CharacterAdded:Connect(function() if watching then stopWatching() end end)
