-- AIM TRAINING (client)
--   * the lobby door question: StarterGui > Main > PracticeChoice (AimButton / ArenaButton / CancelButton).
--     Walking further than its AutoCancelDistance attribute (studs) from the white wall cancels it.
--   * the Aim Training menu: StarterGui > AimTrainingUI > AimTrainingFrame (a copy of the Settings menu design -
--     restyle it freely; it runs the same script as the Settings menu). Open: M / D-pad right / the SETTINGS button.
--   * HUD (hits, accuracy, headshots, kills) + Challenge banner: StarterGui > AimTrainingUI > HUD / Challenge
--   * the board in your room: ReplicatedStorage > AimTraining > Board (SurfaceGui, buttons found by name)
--   * SCENARIOS below: what each ready-made scenario sets in the Movement tab
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GamepadService = game:GetService("GamepadService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local GS = require(RS:WaitForChild("GameSettings"))
local SFX = require(RS:WaitForChild("SFX"))
local shared = RS:WaitForChild("AimTraining")
local Remote = shared:WaitForChild("Remote")
local Choice = shared:WaitForChild("PracticeChoice")
local LeaveArena = RS:WaitForChild("BalloonCombat"):WaitForChild("Remotes"):WaitForChild("LeaveArena")

local SCENARIOS = {
	Still = {AimMoving = false},
	Strafe = {AimMoving = true, AimSpeed = 16, AimLeftRight = true, AimForwardBack = false, AimStrafeAngle = 0, AimStrafeMin = 3, AimStrafeMax = 10, AimPause = 0.1, AimJump = false},
	["Wide Strafe"] = {AimMoving = true, AimSpeed = 20, AimLeftRight = true, AimForwardBack = false, AimStrafeAngle = 0, AimStrafeMin = 8, AimStrafeMax = 20, AimPause = 0, AimJump = false},
	["Slow Strafe"] = {AimMoving = true, AimSpeed = 8, AimLeftRight = true, AimForwardBack = false, AimStrafeAngle = 0, AimStrafeMin = 2, AimStrafeMax = 6, AimPause = 0.4, AimJump = false},
	Jumpy = {AimMoving = true, AimSpeed = 16, AimLeftRight = true, AimForwardBack = false, AimStrafeAngle = 0, AimStrafeMin = 3, AimStrafeMax = 10, AimPause = 0.1, AimJump = true, AimJumpChance = 45},
	["All Over"] = {AimMoving = true, AimSpeed = 18, AimLeftRight = true, AimForwardBack = true, AimStrafeAngle = 0, AimStrafeMin = 3, AimStrafeMax = 14, AimPause = 0.1, AimJump = true, AimJumpChance = 20},
}

local function inAim() return player:GetAttribute("AimTraining") == true end
local function popIn(f)
	local s = f:FindFirstChild("OpenPop") or Instance.new("UIScale")
	s.Name = "OpenPop"
	s.Parent = f
	s.Scale = 0.7
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

------------------------------------------------------------ THE DOOR QUESTION
local promptPad, promptFrom
local function prompt()
	local m = pg:FindFirstChild("Main")
	return m and m:FindFirstChild("PracticeChoice")
end
local function hidePrompt(tellServer)
	local p = prompt()
	if p and p.Visible then
		p.Visible = false
		if tellServer then Choice:FireServer("Cancel") SFX.Play("Close") end
	end
	promptPad, promptFrom = nil, nil
end
local function showPrompt(pad)
	local p = prompt()
	if not p then return end
	promptPad = typeof(pad) == "Instance" and pad or nil
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	promptFrom = root and root.Position
	p.Visible = true
	popIn(p)
	SFX.Play("Open")
end
Choice.OnClientEvent:Connect(function(kind, pad)
	if kind == "Show" then showPrompt(pad) elseif kind == "Hide" then hidePrompt(false) end
end)
local function hookPrompt(main)
	local p = main:WaitForChild("PracticeChoice", 10)
	if not p then return end
	p.Visible = false
	local function btn(name, fn)
		local b = p:FindFirstChild(name, true)
		if b and b:IsA("GuiButton") then b.Activated:Connect(fn) end
	end
	btn("AimButton", function() Choice:FireServer("AimTraining") hidePrompt(false) end)
	btn("ArenaButton", function() Choice:FireServer("Arena") hidePrompt(false) end)
	btn("CancelButton", function() hidePrompt(true) end)
	-- controller Circle / B = Cancel (fired by ControllerSupport)
	local back = p:FindFirstChild("PadBack") or Instance.new("BindableEvent")
	back.Name = "PadBack"
	back.Parent = p
	back.Event:Connect(function() hidePrompt(true) end)
end
-- walked away from the wall: cancelled
local function distToPad(pos)
	if promptPad and promptPad.Parent then
		local rel = promptPad.CFrame:PointToObjectSpace(pos)
		local half = promptPad.Size / 2
		return Vector3.new(math.max(math.abs(rel.X) - half.X, 0), math.max(math.abs(rel.Y) - half.Y, 0), math.max(math.abs(rel.Z) - half.Z, 0)).Magnitude
	end
	return promptFrom and (pos - promptFrom).Magnitude or 0
end
RunService.Heartbeat:Connect(function()
	local p = prompt()
	if not (p and p.Visible) then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if distToPad(root.Position) > (p:GetAttribute("AutoCancelDistance") or 18) or player:GetAttribute("InArena") then
		hidePrompt(not player:GetAttribute("InArena"))
	end
end)

------------------------------------------------------------ THE MENU
local ui = pg:WaitForChild("AimTrainingUI", 300)
local menu = ui:WaitForChild("AimTrainingFrame")
local hud = ui:WaitForChild("HUD")
local banner = ui:WaitForChild("Challenge")
-- the menu runs the Settings menu's own script (a copy, so both always work the same)
if not menu:FindFirstChild("SettingsClient") then
	local srcScript = game:GetService("StarterGui"):WaitForChild("Main"):WaitForChild("SettingsFrame"):WaitForChild("SettingsClient")
	local copy = srcScript:Clone()
	copy.Enabled = true
	copy.Parent = menu
end
menu.Visible = false

-- while the menu is open: blur behind (same as the lobby menus: Main > MenuManager) and the rest of the UI hides
local hiddenByMenu = {}
local menuOpenSent = false
local function focusMenu(on)
	-- (bots don't throw at you while the menu is open)
	if menuOpenSent ~= on then menuOpenSent = on Remote:FireServer("MenuOpen", on) end
	local main = pg:FindFirstChild("Main")
	local mm = main and main:FindFirstChild("MenuManager")
	local blur = mm and mm:FindFirstChild("Blur")
	if blur then blur:Fire(on, "AimTrainingMenu") end
	if on then
		local function hide(g, prop)
			if g and g[prop] then hiddenByMenu[g] = prop g[prop] = false end
		end
		hide(hud, "Visible")
		hide(banner, "Visible")
		hide(pg:FindFirstChild("BalloonCombatUI"), "Enabled")
		hide(main and main:FindFirstChild("PracticeArenaLeave"), "Visible")
		hide(pg:FindFirstChild("AimBoard"), "Enabled")
	else
		for g, prop in hiddenByMenu do
			if g.Parent then g[prop] = true end
		end
		table.clear(hiddenByMenu)
		if not inAim() then hud.Visible = false end
	end
end
local function setMenu(on)
	if on and not inAim() then on = false end
	if menu.Visible == on then return end
	menu.Visible = on
	SFX.Play(on and "Open" or "Close")
	focusMenu(on)
	if on then popIn(menu) end
	-- the mouse is free while it's open (first person locks it otherwise)
	UIS.MouseIconEnabled = on or not player:GetAttribute("InArena")
	if GS.UsingGamepad() then
		if on then pcall(function() GamepadService:EnableGamepadCursor(menu) end)
		else pcall(function() GamepadService:DisableGamepadCursor() end) end
	end
end
menu:GetPropertyChangedSignal("Visible"):Connect(function()
	if not menu.Visible then
		UIS.MouseIconEnabled = not player:GetAttribute("InArena")
		focusMenu(false)
	end
end)
local action = menu:WaitForChild("Action", 10)
if action then
	action.Event:Connect(function(what)
		if what == "StartChallenge" then Remote:FireServer("StartChallenge") setMenu(false)
		elseif what == "ResetStats" then Remote:FireServer("ResetStats")
		elseif what == "Leave" then setMenu(false) LeaveArena:FireServer() end
	end)
end
UIS.InputBegan:Connect(function(input, gpe)
	if not inAim() then return end
	if GS.Is("AimMenu", input) and (not gpe or input.UserInputType.Name:find("^Gamepad")) then
		setMenu(not menu.Visible)
	elseif menu.Visible and input.KeyCode == Enum.KeyCode.ButtonB then
		setMenu(false)
	end
end)
local settingsBtn = hud:FindFirstChild("SettingsButton")
if settingsBtn and settingsBtn:IsA("GuiButton") then settingsBtn.Activated:Connect(function() setMenu(not menu.Visible) end) end
local function paintKey()
	if not (settingsBtn and settingsBtn:IsA("TextButton")) then return end
	local keys = GS.Keys("AimMenu")
	local k = (keys[1] and keys[1] ~= "" and keys[1]) or (keys[2] and keys[2] ~= "" and keys[2]) or nil
	-- (on a controller the button picture shows instead: PadHints)
	settingsBtn.Text = (k and not GS.UsingGamepad()) and ("SETTINGS (" .. GS.KeyText(k) .. ")") or "SETTINGS"
end
GS.Changed:Connect(function(key)
	if type(key) == "string" and (key:find("AimMenu") or key == "Key_InputMode" or key == "PadButtonStyle") then paintKey() end
end)
paintKey()

------------------------------------------------------------ SCENARIOS
local applying = false
local function matches(name)
	local sc = SCENARIOS[name]
	if not sc then return true end
	for k, v in sc do if GS.Get(k) ~= v then return false end end
	return true
end
GS.Changed:Connect(function(key, value)
	if key == "AimScenario" then
		local sc = SCENARIOS[value]
		if sc and not matches(value) then
			applying = true
			for k, v in sc do GS.Set(k, v) end
			applying = false
		end
	elseif not applying and type(key) == "string" and key:sub(1, 3) == "Aim" then
		-- changing a movement setting by hand = Custom
		local cur = GS.Get("AimScenario")
		if cur ~= "Custom" and SCENARIOS[cur] and SCENARIOS[cur][key] ~= nil and not matches(cur) then
			GS.Set("AimScenario", "Custom")
		end
	end
end)

------------------------------------------------------------ HUD + CHALLENGE BANNER
local function setStat(name, text)
	local f = hud:FindFirstChild(name)
	local v = f and f:FindFirstChild("Value")
	if v and v:IsA("TextLabel") then v.Text = text end
end
local function accuracy()
	local shots = player:GetAttribute("AimShots") or 0
	local hits = player:GetAttribute("AimHits") or 0
	return shots > 0 and math.floor(hits / shots * 100 + 0.5) or 0
end
local board -- (the board's SurfaceGui, when your room is there)
local function fmtTime(t) return ("%.2fs"):format(t) end
local function paintStats()
	setStat("Hits", tostring(player:GetAttribute("AimHits") or 0))
	setStat("Accuracy", accuracy() .. "%")
	setStat("Headshots", tostring(player:GetAttribute("AimHeads") or 0))
	setStat("Kills", tostring(player:GetAttribute("AimKills") or 0))
	if board then
		local bg = board:FindFirstChild("Background") or board
		local st = bg:FindFirstChild("Stats")
		if st then
			st.Text = ("Hits %d   Accuracy %d%%   Headshots %d   Kills %d"):format(player:GetAttribute("AimHits") or 0, accuracy(),
				player:GetAttribute("AimHeads") or 0, player:GetAttribute("AimKills") or 0)
		end
		local best = bg:FindFirstChild("Best")
		if best then
			local b = player:GetAttribute("AimBest")
			best.Text = ("Best time for %d kills: %s"):format(GS.Get("AimChallengeKills"), b and fmtTime(b) or "-")
		end
	end
end
for _, a in {"AimShots", "AimHits", "AimHeads", "AimKills", "AimBest"} do player:GetAttributeChangedSignal(a):Connect(paintStats) end

local noticeUntil = 0
Remote.OnClientEvent:Connect(function(kind, data)
	if kind == "Notice" and type(data) == "string" then
		banner.Text = data
		banner.Visible = true
		noticeUntil = os.clock() + 3
		SFX.Play("Error")
	end
end)
local doneAt
RunService.RenderStepped:Connect(function()
	local st = player:GetAttribute("AimChState")
	if not inAim() or menu.Visible then banner.Visible = false return end
	local now = workspace:GetServerTimeNow()
	if st == "countdown" then
		local left = math.ceil((player:GetAttribute("AimChStart") or now) - now)
		banner.Text = left > 0 and tostring(left) or "GO!"
		banner.Visible = true
		doneAt = nil
	elseif st == "running" then
		local t = math.max(now - (player:GetAttribute("AimChStart") or now), 0)
		banner.Text = ("%s   %d / %d"):format(fmtTime(t), player:GetAttribute("AimChKills") or 0, player:GetAttribute("AimChGoal") or 0)
		banner.Visible = true
		doneAt = nil
	elseif st == "done" then
		doneAt = doneAt or os.clock()
		banner.Text = ("DONE  %s%s"):format(fmtTime(player:GetAttribute("AimChTime") or 0), player:GetAttribute("AimChNewBest") and "   NEW BEST!" or "")
		banner.Visible = os.clock() - doneAt < 5
	else
		banner.Visible = os.clock() < noticeUntil
	end
end)
-- countdown beeps
local lastBeep
RunService.Heartbeat:Connect(function()
	if player:GetAttribute("AimChState") ~= "countdown" then lastBeep = nil return end
	local left = math.ceil((player:GetAttribute("AimChStart") or 0) - workspace:GetServerTimeNow())
	if left ~= lastBeep and left > 0 then lastBeep = left pcall(function() SFX.Tick(left) end) end
end)

------------------------------------------------------------ THE BOARD IN YOUR ROOM
local boardTpl = shared:WaitForChild("Board")
local function removeBoard() if board then board:Destroy() board = nil end end
local function paintBoard()
	if not board then return end
	local bg = board:FindFirstChild("Background") or board
	local function set(name, text) local b = bg:FindFirstChild(name) if b and b:IsA("TextButton") then b.Text = text end end
	set("Type", "TARGET: " .. tostring(GS.Get("AimType")):upper())
	set("Scenario", "SCENARIO: " .. tostring(GS.Get("AimScenario")):upper())
	set("Moving", "MOVING: " .. (GS.Get("AimMoving") and "ON" or "OFF"))
	set("Count", "HOW MANY: " .. tostring(GS.Get("AimCount")))
	paintStats()
end
local function cycle(key)
	local d = GS.ByKey[key]
	local i = table.find(d.Options, GS.Get(key)) or 0
	GS.Set(key, d.Options[i % #d.Options + 1])
	SFX.Play("Toggle")
end
local function makeBoard()
	removeBoard()
	local rooms = workspace:WaitForChild("AimRooms", 10)
	local room = rooms and rooms:WaitForChild("Room_" .. player.UserId, 10)
	local part = room and room:WaitForChild("Board", 10)
	if not part or not inAim() then return end
	board = boardTpl:Clone()
	board.Name = "AimBoard"
	board.Adornee = part
	board.ResetOnSpawn = false
	local bg = board:FindFirstChild("Background") or board
	local function on(name, fn)
		local b = bg:FindFirstChild(name)
		if b and b:IsA("GuiButton") then b.Activated:Connect(fn) end
	end
	on("Type", function() cycle("AimType") end)
	on("Scenario", function() cycle("AimScenario") end)
	on("Moving", function() GS.Set("AimMoving", not GS.Get("AimMoving")) SFX.Play("Toggle") end)
	on("Count", function() GS.Set("AimCount", GS.Get("AimCount") % 6 + 1) SFX.Play("Toggle") end)
	on("Challenge", function() Remote:FireServer("StartChallenge") SFX.Play("ButtonPress") end)
	on("ResetStats", function() Remote:FireServer("ResetStats") SFX.Play("ButtonPress") end)
	on("Settings", function() setMenu(true) end)
	board.Parent = pg
	paintBoard()
end
GS.Changed:Connect(function(key)
	if type(key) == "string" and key:sub(1, 3) == "Aim" then paintBoard() end
end)

------------------------------------------------------------ IN / OUT
-- you arrive (and respawn) looking at the box
local function faceBox()
	local cf = player:GetAttribute("AimSpawn")
	if typeof(cf) ~= "CFrame" then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 and inAim() do
			local cam = workspace.CurrentCamera
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - cf.Position).Magnitude < 12 then
				cam.CFrame = CFrame.new(cam.CFrame.Position) * cf.Rotation
			end
			RunService.RenderStepped:Wait()
		end
	end)
end
-- dying closes the menu (and its blur); respawning does too, in case the death was missed
local function hookDeath(c)
	local hum = c:WaitForChild("Humanoid", 10)
	if hum then hum.Died:Connect(function() setMenu(false) end) end
end
if player.Character then task.spawn(hookDeath, player.Character) end
player.CharacterAdded:Connect(function(c)
	setMenu(false)
	task.spawn(hookDeath, c)
	task.delay(0.3, function() if inAim() then faceBox() end end)
end)
local function refresh()
	local on = inAim()
	hud.Visible = on
	if on then
		task.delay(0.2, faceBox)
		task.spawn(makeBoard)
		paintStats()
	else
		setMenu(false)
		removeBoard()
		banner.Visible = false
	end
end
player:GetAttributeChangedSignal("AimTraining"):Connect(refresh)
refresh()

local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hookPrompt, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hookPrompt, c) end end)
