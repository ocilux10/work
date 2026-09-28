-- CONTROLLER SUPPORT (Xbox / PlayStation / any gamepad)
-- Buttons for every action: Settings > Controls > Controller (rebindable; defaults in ReplicatedStorage > GameSettings >
-- GS.PadDefaults, or SettingsDefaults). Movement = left stick, camera = right stick (speed: Controller Sensitivity).
-- This script adds:
--   * MENUS: Share / View (Select) = Roblox's controller cursor on / off (left stick moves it, Cross / A clicks).
--            It also comes up by itself when a menu / popup opens. Circle / B = close the menu or say No to a popup.
--            L1 / R1 = switch Settings tabs.
--   * AIM ASSIST (Settings > Controls > Aim Assist, same strength settings as phones: BalloonCombat > Config >
--            MobileAimAssist): a gentle pull toward the enemy nearest your crosshair while you're aiming with the
--            right stick or holding throw.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local GS = require(RS:WaitForChild("GameSettings"))
local Config = require(RS:WaitForChild("BalloonCombat"):WaitForChild("Config"))

-- we pick what gets highlighted (otherwise Roblox's own Select-button selection jumps to random buttons)
pcall(function() GuiService.AutoSelectGuiEnabled = false end)

local MENUS = {"MatchmakingFrame", "SettingsFrame", "SkinsFrame", "ShopFrame", "PlayerProfile", "PartyInviteFrame", "GiftFrame", "SearchFrame", "WatchFrame", "TradeListFrame", "TradeFrame", "TradeViewFrame", "AdminFrame"}
local PROMPTS = {"DuelPrompt", "PartyPrompt", "DeleteReplayPrompt", "PracticeChoice", "DeleteBalloonPrompt", "TradePrompt"}
local BAR = "Buttons" -- Main > Buttons = the 5 bottom buttons

local function isPad(input) return input.UserInputType.Name:find("^Gamepad") ~= nil end
local function main() return pg:FindFirstChild("Main") end
local function inLobby()
	return player:GetAttribute("MatchId") == nil and not player:GetAttribute("InArena")
		and not player:GetAttribute("WatchingMatch") and not player:GetAttribute("WatchingReplay")
end
local function openMenu()
	local m = main()
	if not m then return nil end
	for _, n in MENUS do
		local f = m:FindFirstChild(n)
		if f and f.Visible then return f end
	end
	return nil
end
local function openPrompt()
	local m = main()
	if not m then return nil end
	for _, n in PROMPTS do
		local f = m:FindFirstChild(n)
		if f and f.Visible then return f end
	end
	local su = pg:FindFirstChild("SearchUI")
	local pop = su and su:FindFirstChild("Popup")
	if pop and pop.Visible then return pop end
	return nil
end
-- highlight the first button inside a frame
local function selectIn(gui)
	if not gui then return end
	task.defer(function()
		if not gui.Visible then return end
		pcall(function() GuiService:Select(gui) end)
	end)
end
local function selectBar()
	local m = main()
	selectIn(m and m:FindFirstChild(BAR))
end
local function clearSelection() GuiService.SelectedObject = nil end

------------------------------------------------------------ CURSOR (Roblox's black circle controller cursor)
-- Share / View (the small button in the middle) = cursor on / off. Left stick moves it, Cross / A clicks.
-- It also pops up by itself when a menu or a popup opens on a controller, and goes away when they close.
local GamepadService = game:GetService("GamepadService")
local cursorByMenu = false -- the cursor was turned on by a menu opening (not by the player)
local function cursorOn()
	local ok, on = pcall(function() return GamepadService.GamepadCursorEnabled end)
	return ok and on
end
local function canCursor() -- not while fighting (Share / View = Scoreboard there)
	return not player:GetAttribute("InArena") and player:GetAttribute("MatchId") == nil
end
local function showCursor(at)
	clearSelection()
	pcall(function() GamepadService:EnableGamepadCursor(at) end)
end
local function hideCursor()
	cursorByMenu = false
	if cursorOn() then pcall(function() GamepadService:DisableGamepadCursor() end) end
end
local function startAt(f)
	-- popups: the cursor starts on Accept / Yes
	local yes = f and (f:FindFirstChild("AcceptButton", true) or f:FindFirstChild("YesButton", true) or f:FindFirstChild("AimButton", true))
	if yes and yes:IsA("GuiButton") and yes.Visible then return yes end
	return f
end

local selectWasOn -- (was the cursor on when Share / View went down?)
------------------------------------------------------------ BUTTONS
UIS.InputBegan:Connect(function(input)
	if not isPad(input) then return end
	local k = input.KeyCode
	local menu = openMenu()
	if k == Enum.KeyCode.ButtonB then
		-- Circle / B: close the popup / menu
		local prompt = openPrompt()
		if prompt then
			-- (each popup's own script listens to its PadBack event = the same as clicking No / Decline / Close)
			local back = prompt:FindFirstChild("PadBack")
			if back and back:IsA("BindableEvent") then back:Fire() else prompt.Visible = false end
			return
		end
		if menu then
			menu.Visible = false
			return
		end
		if cursorOn() and canCursor() then hideCursor() end
	elseif k == Enum.KeyCode.ButtonSelect and canCursor() then
		-- (the toggle happens when you LET GO of the button: Roblox's own cursor also reacts to the press itself,
		-- and turning it on during the press made it switch straight back off)
		selectWasOn = cursorOn()
	elseif (k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.ButtonR1) and menu and menu.Name == "SettingsFrame" then
		local ev = menu:FindFirstChild("SwitchTab")
		if ev then ev:Fire(k == Enum.KeyCode.ButtonR1 and 1 or -1) end
	end
end)

UIS.InputEnded:Connect(function(input)
	if not isPad(input) or input.KeyCode ~= Enum.KeyCode.ButtonSelect then return end
	local was = selectWasOn
	selectWasOn = nil
	if was == nil or not canCursor() then return end
	task.defer(function()
		if was then
			hideCursor()
		elseif not cursorOn() then
			cursorByMenu = false
			local m = main()
			local at = startAt(openPrompt() or openMenu()) or (m and m:FindFirstChild(BAR))
			showCursor(at)
			-- (if Roblox switched it straight back off, turn it on once more)
			task.delay(0.15, function() if not cursorOn() and GS.UsingGamepad() then showCursor(at) end end)
		end
	end)
end)

-- a menu / popup opening on a controller brings the cursor up; when the last one closes it goes away again
local hooked = setmetatable({}, {__mode = "k"})
local function watchFrame(f)
	if hooked[f] then return end
	hooked[f] = true
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		if f.Visible then
			if GS.UsingGamepad() and canCursor() and not cursorOn() then
				task.delay(0.1, function()
					if f.Visible and not cursorOn() then
						cursorByMenu = true
						showCursor(startAt(f))
					end
				end)
			end
		else
			task.delay(0.05, function()
				if cursorByMenu and not openMenu() and not openPrompt() then hideCursor() end
			end)
		end
	end)
end
local function hookMain(m)
	for _, n in MENUS do task.spawn(function() local f = m:WaitForChild(n, 10) if f then watchFrame(f) end end) end
	for _, n in PROMPTS do task.spawn(function() local f = m:WaitForChild(n, 10) if f then watchFrame(f) end end) end
end
local m0 = pg:WaitForChild("Main", 30)
if m0 then hookMain(m0) end
pg.ChildAdded:Connect(function(c)
	if c.Name == "Main" then hookMain(c) end
	if c.Name == "SearchUI" then local p = c:WaitForChild("Popup", 10) if p then watchFrame(p) end end
end)
task.spawn(function()
	local su = pg:WaitForChild("SearchUI", 30)
	local p = su and su:WaitForChild("Popup", 10)
	if p then watchFrame(p) end
end)
-- into a fight: no cursor left on screen
for _, at in {"InArena", "MatchId"} do
	player:GetAttributeChangedSignal(at):Connect(function() if not canCursor() then hideCursor() clearSelection() end end)
end
-- switching back to mouse / touch: cursor off
UIS.LastInputTypeChanged:Connect(function()
	if not GS.UsingGamepad() then
		if cursorOn() then hideCursor() end
		if GuiService.SelectedObject then clearSelection() end
	end
end)

------------------------------------------------------------ AIM ASSIST
local stick2 = Vector2.zero
UIS.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick2 = Vector2.new(input.Position.X, input.Position.Y) end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick2 = Vector2.zero end
end)

local function isEnemyModel(model)
	if model == player.Character then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local other = Players:GetPlayerFromCharacter(model)
	local myMatch = player:GetAttribute("MatchId")
	if other then
		if myMatch ~= nil then
			if other:GetAttribute("MatchId") ~= myMatch then return false end
			local mine, theirs = player:GetAttribute("MatchTeam"), other:GetAttribute("MatchTeam")
			return not (mine ~= nil and mine == theirs)
		end
		return other:GetAttribute("InArena") == true and other:GetAttribute("MatchId") == nil
	end
	return myMatch == nil and (Config.MobileAimAssist and Config.MobileAimAssist.Dummies) == true
end
local candidates, lastScan = {}, 0
local function scan()
	table.clear(candidates)
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then table.insert(candidates, p.Character) end
	end
	local AA = Config.MobileAimAssist
	if AA and AA.Dummies and player:GetAttribute("MatchId") == nil then
		for _, d in workspace:GetDescendants() do
			if d:IsA("Humanoid") and d.Parent:IsA("Model") and not Players:GetPlayerFromCharacter(d.Parent) then table.insert(candidates, d.Parent) end
		end
	end
end
local function target(cam)
	local AA = Config.MobileAimAssist
	if not AA or (AA.Strength or 0) <= 0 then return nil end
	if os.clock() - lastScan > 1 then lastScan = os.clock() scan() end
	local camPos, look = cam.CFrame.Position, cam.CFrame.LookVector
	local best, bestAng = nil, math.rad(AA.MaxAngle or 12)
	local params
	for _, m in candidates do
		if m.Parent and isEnemyModel(m) then
			local names = type(AA.AimAt) == "table" and AA.AimAt or {AA.AimAt or "UpperTorso"}
			for _, pn in names do
				local part = m:FindFirstChild(pn)
				if part and part:IsA("BasePart") then
					local to = part.Position - camPos
					local dist = to.Magnitude
					if dist > 1 and dist <= (AA.Range or 150) then
						local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
						if ang < bestAng then
							local visible = true
							if AA.WallCheck ~= false then
								if not params then
									params = RaycastParams.new()
									params.FilterType = Enum.RaycastFilterType.Exclude
									params.FilterDescendantsInstances = {player.Character, cam}
								end
								local hit = workspace:Raycast(camPos, to, params)
								visible = hit == nil or hit.Instance:IsDescendantOf(m)
							end
							if visible then best, bestAng = part, ang end
						end
					end
				end
			end
		end
	end
	return best
end

RunService:BindToRenderStep("ControllerAimAssist", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not GS.UsingGamepad() or not GS.Get("AimAssist") then return end
	if not player:GetAttribute("InArena") or player:GetAttribute("TabHeld") then return end
	-- only while you're actually aiming: moving the right stick, or holding throw
	local aiming = stick2.Magnitude > 0.15 or GS.IsDown("Shoot") or player:GetAttribute("ThrowHolding") == true
	if not aiming then return end
	local cam = workspace.CurrentCamera
	local t = target(cam)
	if not t then return end
	local AA = Config.MobileAimAssist
	local alpha = math.clamp((AA.Strength or 0.35) * dt * 12, 0, 1)
	local want = CFrame.lookAt(cam.CFrame.Position, t.Position)
	local wp, wy = want:ToEulerAnglesYXZ()
	local cp, cy = cam.CFrame:ToEulerAnglesYXZ()
	local dy = (wy - cy + math.pi) % (2 * math.pi) - math.pi
	cam.CFrame = CFrame.new(cam.CFrame.Position) * CFrame.fromEulerAnglesYXZ(cp + (wp - cp) * alpha, cy + dy * alpha, 0)
end)

------------------------------------------------------------ BUTTON HINTS ON THE COMBAT HUD
-- BalloonCombatUI > LMB / RMB boxes show the button you actually use (M1 / RT / R2 ...), and follow rebinding
local function firstKey(action)
	local keys = GS.Keys(action)
	local k = (keys[1] and keys[1] ~= "" and keys[1]) or (keys[2] and keys[2] ~= "" and keys[2]) or nil
	local HUD = {MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB"}
	return k and (HUD[k] or GS.KeyText(k)) or "-"
end
local function paintHints()
	local ui = pg:FindFirstChild("BalloonCombatUI")
	if not ui then return end
	local l = ui:FindFirstChild("LMB") and ui.LMB:FindFirstChild("LMB")
	local r = ui:FindFirstChild("RMB") and ui.RMB:FindFirstChild("Rmb")
	if l and l:IsA("TextLabel") then l.Text = firstKey("Swing") end
	if r and r:IsA("TextLabel") then r.Text = firstKey("Shoot") end
end
GS.Changed:Connect(function(key)
	if type(key) == "string" and (key:find("Swing") or key:find("Shoot") or key == "Key_InputMode" or key == "PadButtonStyle") then paintHints() end
end)
pg.ChildAdded:Connect(function(c) if c.Name == "BalloonCombatUI" then task.wait(0.2) paintHints() end end)
paintHints()
