-- BALLOONS MENU (Main > SkinsFrame, opened by the SKINS button) + the INSPECT screen (StarterGui > BalloonInspect)
-- Look: SkinsFrame > Templates > Card (the balloon cards), ActionMenu (Equip / Inspect / Delete - opens where you click), ToolBar
--       (Sort / Show / count / bin = pick several to delete / tick = delete them), Main > DeleteBalloonPrompt (its
--       OneText / LastText / ManyText attributes are the questions). Inspect room: ReplicatedStorage > BalloonSkins >
--       InspectRoom (move CameraSpot / BalloonSpot to reframe). Balloons, rarities: BalloonSkins > SkinConfig.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CAS = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("BalloonSkins")
local Skins = require(folder:WaitForChild("SkinConfig"))
local Remote = folder:WaitForChild("Remote")
local GS = require(RS:WaitForChild("GameSettings"))
local SFX = require(RS:WaitForChild("SFX"))
local ClientActions = RS:WaitForChild("BalloonCombat"):WaitForChild("ClientActions")
local CardFX = require(folder:WaitForChild("CardFX")) -- effects + turning on the pictures

local SORTS = {"Rarity", "Name", "Newest", "Amount"}
local FILTERS = {"All", table.unpack(Skins.RarityOrder or {"Common", "Rare", "Epic", "Legendary", "Mythic"})} -- (SkinConfig.RarityOrder)
local sortMode, filterMode, searchText = "Rarity", "All", ""
local massMode, selected = false, {}
local openId -- the card whose ActionMenu is open

local function decode(attr)
	local raw = player:GetAttribute(attr)
	if type(raw) ~= "string" then return {} end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(t) == "table" and t or {}
end
local function inventory() local inv = decode("BalloonInv") inv[Skins.DefaultId] = inv[Skins.DefaultId] or 1 return inv end
local function locked() return decode("BalloonLocked") end
local function equipped() return player:GetAttribute("EquippedSkin") or Skins.DefaultId end
local function shortNum(n)
	if n >= 1e6 then return (("%.1fM"):format(n / 1e6):gsub("%.0M", "M")) end
	if n >= 1e3 then return (("%.1fK"):format(n / 1e3):gsub("%.0K", "K")) end
	return tostring(n)
end
local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end
local function btnText(b, t) local l = b and b:FindFirstChild("Text") if l then l.Text = t elseif b then setText(b, t) end end

-- a balloon in a ViewportFrame
local function showInViewport(vp, id)
	for _, c in vp:GetChildren() do if not c:IsA("UIComponent") then c:Destroy() end end
	local m = Skins.ForViewport(Skins.Model(id))
	if not m then return end
	m.CFrame = CFrame.new()
	m.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local size = m.Size
	cam.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.05, size.Y * 2.45), Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	CardFX.Attach(vp, id)
end

------------------------------------------------------------ THE MENU
local frame, scroll, cardTpl, actionMenu, toolBar, prompt
local cards = {}
local function main() return pg:FindFirstChild("Main") end

local function closeActions()
	openId = nil
	if actionMenu then actionMenu.Visible = false end
end

local function sortedIds()
	local inv, list = inventory(), {}
	local got = decode("BalloonGot")
	for id, n in inv do
		local s = Skins.ById[id]
		if s and n > 0 then
			local r = Skins.Rarities[s.Rarity]
			local okFilter = filterMode == "All" or s.Rarity == filterMode
			local okSearch = searchText == "" or s.Name:lower():find(searchText, 1, true) or (r and r.Text:lower():find(searchText, 1, true))
			if okFilter and okSearch then table.insert(list, {id = id, s = s, n = n, r = r and r.Order or 0, got = got[id] or 0}) end
		end
	end
	table.sort(list, function(a, b)
		-- the equipped one is always first
		if (a.id == equipped()) ~= (b.id == equipped()) then return a.id == equipped() end
		if sortMode == "Name" then return a.s.Name < b.s.Name end
		if sortMode == "Newest" and a.got ~= b.got then return a.got > b.got end
		if sortMode == "Amount" and a.n ~= b.n then return a.n > b.n end
		if a.r ~= b.r then return a.r > b.r end
		return a.s.Index < b.s.Index
	end)
	return list
end

local refresh -- forward
local function paintCard(c, e)
	local lk = locked()
	local r = Skins.Rarities[e.s.Rarity] or Skins.Rarities.Common
	setText(c:FindFirstChild("SkinName"), e.n > 1 and ("%s <font color=\"#9aa0ad\">x%d</font>"):format(e.s.Name, e.n) or e.s.Name)
	local nl = c:FindFirstChild("SkinName") if nl and nl:IsA("TextLabel") then nl.RichText = true end
	local tl = c:FindFirstChild("SkinType")
	if tl and tl:IsA("TextLabel") then tl.Text = e.s.Rarity == "Default" and e.s.Type or (r.Text .. " " .. e.s.Type) end
	local bar = c:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = r.Color end
	local glow = c:FindFirstChild("RarityGlow") if glow then glow.BackgroundColor3 = r.Color end
	local dot = c:FindFirstChild("EquippedDot") if dot then dot.Visible = e.id == equipped() end
	local lock = c:FindFirstChild("LockIcon") if lock then lock:Destroy() end
	local sel = c:FindFirstChild("Selected") if sel then sel.Visible = massMode and selected[e.id] == true end
end

local GuiService = game:GetService("GuiService")
local function openActions(c, e)
	if not actionMenu then return end
	openId = e.id
	local isEq = e.id == equipped()
	local eqB, delB = actionMenu:FindFirstChild("EquipButton"), actionMenu:FindFirstChild("DeleteButton")
	btnText(eqB, isEq and "Equipped" or "Equip")
	if delB then delB.Visible = e.id ~= Skins.DefaultId end
	-- opens where you clicked (card centre on controller), kept inside the menu
	local fa, fs = frame.AbsolutePosition, frame.AbsoluteSize
	local ca, cs = c.AbsolutePosition, c.AbsoluteSize
	local at = ca + cs / 2
	if not GuiService.SelectedObject then
		-- the mouse is in whole-window pixels; the menu's ScreenGui may start lower (under the top bar) or be inset on
		-- phones. How much it's shifted = window size - ScreenGui size (top bar at the top, safe areas split both sides).
		local m = UIS:GetMouseLocation()
		local sg = frame:FindFirstAncestorOfClass("ScreenGui")
		local view = workspace.CurrentCamera.ViewportSize
		if sg then
			local diff = view - sg.AbsoluteSize
			m -= Vector2.new(diff.X / 2, diff.Y)
		end
		at = m
	end
	actionMenu.Visible = true
	local pop = actionMenu:FindFirstChild("Pop") or Instance.new("UIScale")
	pop.Name = "Pop" pop.Parent = actionMenu pop.Scale = 1
	actionMenu.AnchorPoint = Vector2.new(0, 0)
	-- measure how the parent really maps offsets to the screen (a UIScale on the menu / screen changes it), so the
	-- menu's top-left corner lands EXACTLY on the click
	-- the menu's top-left corner goes EXACTLY on the click. Offsets inside its parent are multiplied by every UIScale
	-- above it, so: position = (click - parent's corner) / those scales. (Reading AbsolutePosition right after moving
	-- something gives the OLD value until the next frame, so only values that don't change here are used.)
	local parent = actionMenu.Parent
	local k = 1
	local a = parent
	while a do
		local sc = a:FindFirstChildOfClass("UIScale")
		if sc then k *= sc.Scale end
		if a:IsA("LayerCollector") then break end
		a = a.Parent
	end
	local ms = actionMenu.AbsoluteSize
	-- (kept inside the menu: near the right / bottom edge it opens to the left / upwards instead)
	local tx, ty = at.X, at.Y
	if tx + ms.X > fa.X + fs.X - 4 then tx -= ms.X end
	if ty + ms.Y > fa.Y + fs.Y - 4 then ty -= ms.Y end
	local pp = parent:IsA("GuiObject") and parent.AbsolutePosition or Vector2.zero
	actionMenu.Position = UDim2.fromOffset((tx - pp.X) / k, (ty - pp.Y) / k)
	pop.Scale = 0.7
	TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

refresh = function()
	if not (frame and scroll and cardTpl) then return end
	local list = sortedIds()
	local keep = {}
	for i, e in list do
		keep[e.id] = true
		local c = cards[e.id]
		if not c or not c.Parent then
			c = cardTpl:Clone()
			c.Name = "Card_" .. e.id
			c.Visible = true
			cards[e.id] = c
			local vp = c:FindFirstChild("BalloonView")
			if vp then showInViewport(vp, e.id) end
			local b = c:FindFirstChild("Button")
			if b and b:IsA("GuiButton") then
				b.Activated:Connect(function()
					local cur
					for _, x in sortedIds() do if x.id == e.id then cur = x end end
					if not cur then return end
					if massMode then
						if cur.id == Skins.DefaultId then SFX.Play("Error") return end
						selected[cur.id] = not selected[cur.id] or nil
						SFX.Play("Toggle")
						paintCard(c, cur)
						refresh()
					elseif openId == cur.id and actionMenu and actionMenu.Visible then
						closeActions()
					else
						SFX.Play("ButtonPress")
						openActions(c, cur)
					end
				end)
			end
			c.Parent = scroll
		end
		c.LayoutOrder = i
		paintCard(c, e)
	end
	for id, c in cards do
		if not keep[id] then c:Destroy() cards[id] = nil selected[id] = nil end
	end
	-- counts / buttons
	local total, types = 0, 0
	for id, n in inventory() do if Skins.ById[id] and n > 0 then total += n types += 1 end end
	if toolBar then
		-- text: ToolBar attributes CountText / CountTextSame ({types} = different balloons, {total} = counting copies)
		local fmt = total ~= types and (toolBar:GetAttribute("CountText") or "{types} balloons ({total} total)")
			or (toolBar:GetAttribute("CountTextSame") or "{types} balloons")
		setText(toolBar:FindFirstChild("CountLabel"), (fmt:gsub("{types}", tostring(types)):gsub("{total}", tostring(total))))
		btnText(toolBar:FindFirstChild("SortButton"), "Sort: " .. sortMode)
		btnText(toolBar:FindFirstChild("FilterButton"), "Show: " .. filterMode)
		local n = 0 for _ in selected do n += 1 end
		local conf = toolBar:FindFirstChild("ConfirmButton")
		-- texts: ToolBar attributes ConfirmText / TrashText / TrashCloseText
		if conf then conf.Visible = massMode and n > 0 btnText(conf, toolBar:GetAttribute("ConfirmText") or "CONFIRM") end
		local trash = toolBar:FindFirstChild("TrashButton")
		if trash then btnText(trash, massMode and (toolBar:GetAttribute("TrashCloseText") or "X") or (toolBar:GetAttribute("TrashText") or "TRASH")) end
	end
end

-- hovering another balloon closes the open Equip / Inspect / Delete menu (not while the mouse is on the menu)
RunService.Heartbeat:Connect(function()
	if not (openId and actionMenu and actionMenu.Visible) then return end
	if GuiService.SelectedObject then return end -- (controller)
	local m = UIS:GetMouseLocation()
	local sg = frame and frame:FindFirstAncestorOfClass("ScreenGui")
	if not (sg and sg.IgnoreGuiInset) then m -= GuiService:GetGuiInset() end
	local p, s = actionMenu.AbsolutePosition, actionMenu.AbsoluteSize
	if m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y then return end
	for id, c in cards do
		if id ~= openId and c.Visible then
			local cp, cs = c.AbsolutePosition, c.AbsoluteSize
			if m.X >= cp.X and m.X <= cp.X + cs.X and m.Y >= cp.Y and m.Y <= cp.Y + cs.Y then closeActions() return end
		end
	end
end)

------------------------------------------------------------ DELETING (are you sure?)
local pendingDelete
local function ask(ids)
	if not prompt then return end
	pendingDelete = ids
	local inv = inventory()
	local title = prompt:FindFirstChild("Title")
	local text
	if #ids == 1 then
		local s = Skins.Get(ids[1])
		local left = (inv[ids[1]] or 1) - 1
		text = (left > 0 and (prompt:GetAttribute("OneText") or "Delete 1 {name}? You'll have {left} left.")
			or (prompt:GetAttribute("LastText") or "Delete your {name}?")):gsub("{name}", s.Name):gsub("{left}", tostring(left))
	else
		text = (prompt:GetAttribute("ManyText") or "Delete {n} balloons?"):gsub("{n}", tostring(#ids))
	end
	setText(title, text)
	prompt.Visible = true
	local pop = prompt:FindFirstChild("OpenPop") or Instance.new("UIScale")
	pop.Name = "OpenPop" pop.Parent = prompt pop.Scale = 0.7
	TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	SFX.Play("Open")
end
local function closePrompt() pendingDelete = nil if prompt then prompt.Visible = false end end
local function doDelete()
	local ids = pendingDelete
	closePrompt()
	if not ids then return end
	local ok = Remote:InvokeServer("Delete", ids)
	SFX.Play(ok and "DuelDeclined" or "Error")
	massMode = false
	table.clear(selected)
	refresh()
end

------------------------------------------------------------ INSPECT SCREEN
local inspectGui, room, inspecting, mode, shown
local returnTo -- the menu to reopen after inspecting (nil = the Balloons menu)
-- the balloon's turn: any direction, all the way round (drag left/right = around, up/down = over the top)
local rot, rotVel, dragging, releasedAt, lastPos, lastMoveAt = CFrame.new(), Vector2.zero, false, 0, nil, 0
local hiddenGuis = {}
local ROOM_CF = CFrame.new(0, 4000, 30000) -- far away from everything (only on your screen)

-- UI that stays while inspecting (everything else is switched off). BalloonCombatUI = crosshair in Wielded.
local KEEP = {Chat = true, LoadingScreen = true, BalloonCombatUI = true, TopbarPlus = true}
local function setTab(which)
	mode = which
	local tabs = inspectGui:FindFirstChild("Tabs")
	local on = tabs and tabs:GetAttribute("ActiveColor") or Color3.fromRGB(40, 230, 90)
	local off = tabs and tabs:GetAttribute("IdleColor") or Color3.new(1, 1, 1)
	for _, n in {"InspectTab", "WieldedTab"} do
		local b = tabs and tabs:FindFirstChild(n)
		local line = b and b:FindFirstChild("Line")
		if line then line.BackgroundColor3 = ((n == "InspectTab") == (which == "Inspect")) and on or off end
	end
	local hint = inspectGui:FindFirstChild("Hint")
	local cam = workspace.CurrentCamera
	local camSpot = room and room:FindFirstChild("CameraSpot")
	if camSpot then cam.CFrame = camSpot.CFrame end
	dragging = false
	local combatUI = pg:FindFirstChild("BalloonCombatUI")
	if which == "Inspect" then
		ClientActions:Fire("PreviewEnd")
		if combatUI then combatUI.Enabled = false end
		if shown then shown.Parent = room end
		if hint then hint.Text = hint:GetAttribute("InspectText") or "Hold and drag to spin it" end
	else
		if shown then shown.Parent = nil end
		-- Wielded: your arms + the balloon - swing, throw and inspect like in a fight (only you see it; you can't walk)
		if combatUI then combatUI.Enabled = true end
		ClientActions:Fire("PreviewStart", inspecting)
		local keys = GS.Keys("Inspect")
		local k = (keys[1] and keys[1] ~= "" and keys[1]) or (keys[2] and keys[2] ~= "" and keys[2]) or "F"
		if hint then hint.Text = (hint:GetAttribute("WieldedText") or "Press {key} to inspect"):gsub("{key}", GS.KeyText(k)) end
	end
	SFX.Play("ButtonPress")
end

-- the practice-arena loading screen (StarterPlayerScripts > LoadingTransitionClient; timings = ReplicatedStorage >
-- LoadingTransition attributes FadeIn / Hold / FadeOut): fades in, `fn` runs behind it, fades out
local function withLoading(fn)
	local lt = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("LoadingTransitionClient")
	local play = lt and lt:FindFirstChild("Play")
	local cfg = RS:FindFirstChild("LoadingTransition")
	if not play or (cfg and cfg:GetAttribute("Enabled") == false) then fn() return end
	play:Fire("In")
	task.wait((cfg and cfg:GetAttribute("FadeIn") or 0.15) + (cfg and cfg:GetAttribute("Hold") or 0.12))
	fn()
	play:Fire("Out")
end

local stopInspectNow -- forward
local stopping = false
local function stopInspect()
	if not inspecting or stopping then return end
	stopping = true
	withLoading(function() stopInspectNow() end)
	stopping = false
end
stopInspectNow = function()
	if not inspecting then return end
	inspecting = nil
	player:SetAttribute("InspectingBalloon", nil)
	ClientActions:Fire("PreviewEnd")
	CAS:UnbindAction("BalloonInspectBlock")
	if room then room:Destroy() room = nil end
	shown = nil
	inspectGui.Enabled = false
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	for g, prop in hiddenGuis do if g.Parent then g[prop] = true end end
	table.clear(hiddenGuis)
	local main = pg:FindFirstChild("Main") if main then main.Enabled = true end
	-- back to where you came from (the Balloons menu, or someone's balloons / profile)
	local back = returnTo
	returnTo = nil
	if back and back.Parent then back.Visible = true elseif frame then frame.Visible = true end
	SFX.Play("Close")
end

local startInspectNow -- forward
local function startInspect(id, from)
	if inspecting or not inspectGui or not Skins.ById[id] then return end
	if player:GetAttribute("InArena") or player:GetAttribute("MatchId") ~= nil then return end
	withLoading(function() startInspectNow(id, from) end)
end
startInspectNow = function(id, from)
	if inspecting or not inspectGui or not Skins.ById[id] then return end
	if player:GetAttribute("InArena") or player:GetAttribute("MatchId") ~= nil then return end
	inspecting = id
	returnTo = from
	player:SetAttribute("InspectingBalloon", true)
	closeActions()
	if frame then frame.Visible = false end
	if from then from.Visible = false end
	-- everything else hides while you look at it (kept hidden: see keepHidden below)
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g ~= inspectGui and g.Enabled and not KEEP[g.Name] then
			hiddenGuis[g] = "Enabled"
			g.Enabled = false
		end
	end
	room = folder:WaitForChild("InspectRoom"):Clone()
	room:PivotTo(ROOM_CF)
	room.Parent = workspace
	local spot = room:FindFirstChild("BalloonSpot")
	shown = Skins.Model(id)
	shown.Anchored = true
	shown.CFrame = spot and spot.CFrame or ROOM_CF
	shown.Parent = room
	rot, rotVel = CFrame.new(), Vector2.zero
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	-- name card / how many exist
	local s = Skins.Get(id)
	local r = Skins.Rarities[s.Rarity] or Skins.Rarities.Common
	local card = inspectGui:FindFirstChild("NameCard")
	if card then
		setText(card:FindFirstChild("SkinName"), s.Name)
		setText(card:FindFirstChild("SkinType"), s.Rarity == "Default" and s.Type or (r.Text .. " " .. s.Type))
		local bar = card:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = r.Color end
		local glow = card:FindFirstChild("RarityGlow") if glow then glow.BackgroundColor3 = r.Color end
		-- the description (SkinConfig Desc) under the name card: BalloonInspect > Desc (made from SkinType if missing)
		local desc = inspectGui:FindFirstChild("Desc")
		local typeLbl = card:FindFirstChild("SkinType")
		if not desc and typeLbl then
			desc = typeLbl:Clone()
			desc.Name = "Desc"
			desc.AnchorPoint = card.AnchorPoint
			desc.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, typeLbl.Size.Y.Scale * card.Size.Y.Scale, typeLbl.Size.Y.Offset)
			desc.Position = card.Position + UDim2.new(0, 0, card.Size.Y.Scale * (1 - card.AnchorPoint.Y), card.Size.Y.Offset * (1 - card.AnchorPoint.Y) + 6)
			desc.TextColor3 = Color3.fromRGB(200, 200, 210)
			desc.Parent = inspectGui
		end
		if desc then
			desc.Visible = (s.Desc or "") ~= ""
			setText(desc, s.Desc or "")
		end
	end
	local exist = inspectGui:FindFirstChild("Exist")
	if exist then
		local n = folder:GetAttribute("Exist_" .. id)
		exist.Visible = id ~= Skins.DefaultId and n ~= nil
		exist.Text = ('<font color="#46E65A">%s</font> exist'):format(shortNum(n or 0))
	end
	-- no walking around while you look
	CAS:BindActionAtPriority("BalloonInspectBlock", function() return Enum.ContextActionResult.Sink end, false, 3000,
		Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump)
	inspectGui.Enabled = true
	setTab("Inspect")
	SFX.Play("Open")
end

-- drag to spin (keeps going for a moment after you let go)
UIS.InputBegan:Connect(function(input, gpe)
	if not inspecting then return end
	if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then stopInspect() return end
	if mode ~= "Inspect" then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- (not when pressing one of the screen's buttons)
		local p = input.Position
		for _, o in pg:GetGuiObjectsAtPosition(p.X, p.Y) do
			if o:IsA("GuiButton") and o.Visible and o:IsDescendantOf(inspectGui) then return end
		end
		dragging = true
		rotVel = Vector2.zero
		lastPos = Vector2.new(p.X, p.Y)
		lastMoveAt = os.clock()
	end
end)
-- turn it by a screen movement (radians across / down)
local function turnBy(d)
	local cam = workspace.CurrentCamera.CFrame
	rot = CFrame.fromAxisAngle(cam.UpVector, d.X) * CFrame.fromAxisAngle(cam.RightVector, d.Y) * rot
end
UIS.InputChanged:Connect(function(input)
	if not inspecting or mode ~= "Inspect" then return end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		-- controller: the right stick spins it
		local v = Vector2.new(input.Position.X, -input.Position.Y)
		if v.Magnitude > 0.15 then rotVel = v * 3 releasedAt = os.clock() + 1e6 else releasedAt = os.clock() end
		return
	end
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		local d = (p - (lastPos or p)) * (inspectGui:GetAttribute("SpinSpeed") or 0.012)
		lastPos = p
		if d.Magnitude == 0 then return end
		local dt = math.clamp(os.clock() - lastMoveAt, 1 / 240, 0.1)
		lastMoveAt = os.clock()
		turnBy(d)
		-- speed for the fling (per second)
		rotVel = rotVel:Lerp(d / dt, 0.5)
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			dragging = false
			releasedAt = os.clock()
			lastPos = nil
			-- held still before letting go = no fling
			if os.clock() - lastMoveAt > 0.08 then rotVel = Vector2.zero end
		end
	end
end)
RunService.RenderStepped:Connect(function(dt)
	if not inspecting then return end
	-- other scripts may switch UI back on: keep it off while inspecting
	for g in hiddenGuis do if g.Parent and g.Enabled then g.Enabled = false end end
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g ~= inspectGui and g.Enabled and not KEEP[g.Name] and not hiddenGuis[g] then
			hiddenGuis[g] = "Enabled" g.Enabled = false
		end
	end
	if mode == "Wielded" then
		local camSpot = room and room:FindFirstChild("CameraSpot")
		if camSpot then workspace.CurrentCamera.CFrame = camSpot.CFrame end
		return
	end
	if not (shown and shown.Parent and room) then return end
	local keep = inspectGui:GetAttribute("SpinKeepTime") or 0.5
	if not dragging then
		local since = os.clock() - releasedAt
		if since < 0 then
			turnBy(rotVel * dt) -- (controller stick held)
		elseif since < keep then
			turnBy(rotVel * dt * (1 - since / keep)) -- keeps spinning that way, slowing to a stop
		else
			turnBy(Vector2.new((inspectGui:GetAttribute("IdleSpin") or 0) * dt, 0))
		end
	end
	local spot = room:FindFirstChild("BalloonSpot")
	local base = spot and spot.CFrame or ROOM_CF
	shown.CFrame = CFrame.new(base.Position) * rot * base.Rotation
	local camSpot = room:FindFirstChild("CameraSpot")
	if camSpot then workspace.CurrentCamera.CFrame = camSpot.CFrame end
end)

local function hookInspectGui()
	inspectGui = pg:WaitForChild("BalloonInspect", 300)
	if not inspectGui then return end
	local tabs = inspectGui:WaitForChild("Tabs")
	tabs:WaitForChild("InspectTab").Activated:Connect(function() if inspecting and mode ~= "Inspect" then setTab("Inspect") end end)
	tabs:WaitForChild("WieldedTab").Activated:Connect(function() if inspecting and mode ~= "Wielded" then setTab("Wielded") end end)
	inspectGui:WaitForChild("StopButton").Activated:Connect(stopInspect)
end
task.spawn(hookInspectGui)
-- other scripts (someone's balloons, a profile's balloon card): BalloonsClient.Inspect:Fire(balloonId, menuToReturnTo)
local inspectEvent = script:FindFirstChild("Inspect") or Instance.new("BindableEvent")
inspectEvent.Name = "Inspect"
inspectEvent.Parent = script
inspectEvent.Event:Connect(function(id, from) startInspect(id, typeof(from) == "Instance" and from or nil) end)
player.CharacterAdded:Connect(function() if inspecting then stopInspectNow() end end)

------------------------------------------------------------ HOOK THE MENU (again after every respawn)
local function hook(m)
	frame = m:WaitForChild("SkinsFrame", 10)
	if not frame then return end
	table.clear(cards)
	scroll = frame:WaitForChild("ScrollingFrame")
	cardTpl = frame:WaitForChild("Templates"):WaitForChild("Card")
	actionMenu = frame:FindFirstChild("ActionMenu")
	toolBar = frame:FindFirstChild("ToolBar")
	prompt = m:FindFirstChild("DeleteBalloonPrompt")
	frame.Visible = false
	if actionMenu then actionMenu.Visible = false end
	if prompt then prompt.Visible = false end
	-- open / close
	local open = m:FindFirstChild("Buttons") and m.Buttons:FindFirstChild("Skins", true)
	if open and open:IsA("GuiButton") then
		open.Activated:Connect(function()
			frame.Visible = not frame.Visible
			SFX.Play(frame.Visible and "Open" or "Close")
		end)
	end
	local exit = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Exit")
	if exit and exit:IsA("GuiButton") then exit.Activated:Connect(function() frame.Visible = false SFX.Play("Close") end) end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then refresh() else closeActions() massMode = false table.clear(selected) end
	end)
	-- search
	local search = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Search")
	if search and search:IsA("TextBox") then
		search:GetPropertyChangedSignal("Text"):Connect(function() searchText = search.Text:lower():gsub("^%s+", ""):gsub("%s+$", "") refresh() end)
	end
	-- action menu
	if actionMenu then
		local function on(name, fn) local b = actionMenu:FindFirstChild(name) if b and b:IsA("GuiButton") then b.Activated:Connect(fn) end end
		on("EquipButton", function()
			local id = openId
			closeActions()
			if not id or id == equipped() then return end
			local ok = Remote:InvokeServer("Equip", id)
			SFX.Play(ok and "Toggle" or "Error")
			refresh()
		end)
		on("InspectButton", function() local id = openId if id then startInspect(id) end end)
		local lb = actionMenu:FindFirstChild("LockButton") if lb then lb:Destroy() end
		on("DeleteButton", function() local id = openId closeActions() if id then ask({id}) end end)
	end
	-- tool bar
	if toolBar then
		local function on(name, fn) local b = toolBar:FindFirstChild(name) if b and b:IsA("GuiButton") then b.Activated:Connect(fn) end end
		on("SortButton", function() sortMode = SORTS[(table.find(SORTS, sortMode) or 0) % #SORTS + 1] SFX.Play("Toggle") refresh() end)
		on("FilterButton", function() filterMode = FILTERS[(table.find(FILTERS, filterMode) or 0) % #FILTERS + 1] SFX.Play("Toggle") refresh() end)
		on("TrashButton", function() massMode = not massMode table.clear(selected) closeActions() SFX.Play("Toggle") refresh() end)
		on("ConfirmButton", function()
			local ids = {}
			for id in selected do table.insert(ids, id) end
			if #ids > 0 then ask(ids) end
		end)
	end
	-- delete prompt
	if prompt then
		local yes, no = prompt:FindFirstChild("YesButton", true), prompt:FindFirstChild("NoButton", true)
		if yes and yes:IsA("GuiButton") then yes:SetAttribute("NoClickSound", true) yes.Activated:Connect(doDelete) end
		if no and no:IsA("GuiButton") then no.Activated:Connect(closePrompt) end
		local back = Instance.new("BindableEvent") back.Name = "PadBack" back.Parent = prompt back.Event:Connect(closePrompt)
	end
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
for _, a in {"BalloonInv", "BalloonLocked", "EquippedSkin"} do
	player:GetAttributeChangedSignal(a):Connect(function() if frame and frame.Visible then refresh() end end)
end
