-- REPLAYS (client) - your last 20 matches, in the Replays tab of the camera menu (top bar > Main > WatchFrame).
-- Rows: WatchFrame > Templates > ReplayRow (restyle freely - keep the names): SpectateImage = watch it,
-- BinImage = delete it (asks first: Main > DeleteReplayPrompt - MapImage / Title / YesButton / NoButton, the question
-- is its Text attribute), Player1 / Player2 faces, Score1 / Score2, MapLabel, Date. Template changes show live.
-- Watching: first person through any player (Q / E), V = freecam, leave = your Leave Practice Arena key (G).
-- Bottom: previous / next round, pause, speed, timeline (click or drag). Keys: Settings > Controls > Spectate & Replays
-- (Space pause, Left / Right 5 seconds, Z / X rounds, T speed; in freecam E / Q = up / down). HUD look: StarterGui > ReplayHUD.
-- Recording + saving: ServerScriptService > MatchmakingServer / ReplayServer, ServerStorage > Replays.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local MM = RS:WaitForChild("Matchmaking")
local Remotes = MM:WaitForChild("Remotes")
local Remote = Remotes:WaitForChild("Replays")
local Changed = Remotes:WaitForChild("ReplaysChanged")
local CamRemote = Remotes:WaitForChild("ReplayCam")
local GS = require(RS:WaitForChild("GameSettings"))
local SFX = require(RS:WaitForChild("SFX"))
local Balloon = RS:WaitForChild("BalloonCombat")
local CombatConfig = require(Balloon:WaitForChild("Config"))
local ClientActions = Balloon:WaitForChild("ClientActions")
local ReplayFX = Balloon:FindFirstChild("ReplayFX")
local MoveConfig = require(RS:WaitForChild("MovementConfig"))
local NameBadge = require(RS:WaitForChild("NameBadge"))

local GREEN = Color3.fromRGB(60, 235, 110)
local RED = Color3.fromRGB(255, 70, 70)
local DARK = Color3.fromRGB(28, 28, 34)
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local FREECAM_SPEED, FREECAM_FAST = 28, 70
local SPEEDS = {0.5, 1, 2, 4}

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
local function sideColors(s1, s2)
	if s2 > s1 then return RED, GREEN end
	return GREEN, RED
end
local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

local play -- forward declared: play(replayId)

------------------------------------------------------------ THE LIST (camera menu > Replays tab)
local lists = {} -- {scroll, tpl, rows = {}, empty}
local entries = {} -- your replays (newest first), from the server

local function faces(row, slotName, team, color, rightAlign)
	-- the slot keeps exactly the position / size it has in the design; with more players on a team, their faces
	-- share that same space side by side (team 1 packs toward the middle from the left, team 2 from the right)
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

local function paintRow(row, e)
	local s1, s2 = e.Score1 or 0, e.Score2 or 0
	local c1, c2 = sideColors(s1, s2)
	local sc1, sc2 = row:FindFirstChild("Score1"), row:FindFirstChild("Score2")
	if sc1 and sc1:IsA("TextLabel") then sc1.Text = tostring(s1) sc1.TextColor3 = c1 end
	if sc2 and sc2:IsA("TextLabel") then sc2.Text = tostring(s2) sc2.TextColor3 = c2 end
	faces(row, "Player1", e.Team1 or {}, c1, true)
	faces(row, "Player2", e.Team2 or {}, c2, false)
	local map = row:FindFirstChild("MapLabel")
	if map and (map:IsA("ImageLabel") or map:IsA("ImageButton")) and (e.Image or "") ~= "" then map.Image = e.Image end
	local date = row:FindFirstChild("Date")
	if date and date:IsA("TextLabel") and e.Date then
		local ok, txt = pcall(function() return DateTime.fromUnixTimestamp(e.Date):FormatLocalTime("DD/MM/YYYY HH:mm", "en-gb") end)
		date.Text = ok and txt or ""
	end
end

local function makeEmpty(scroll)
	-- the designed "EmptyText" label in the list (restyle it freely); made here only if it's missing
	local designed = scroll:FindFirstChild("EmptyText")
	if designed then designed.LayoutOrder = -1 return designed end
	local l = Instance.new("TextLabel")
	l.Name = "NoReplays"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 0.08)
	l.FontFace = FONT
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(220, 225, 235)
	l.TextTransparency = 0.2
	l.Text = "No replays yet - play a match!"
	l.LayoutOrder = -1
	l.Parent = scroll
	return l
end

local askDelete -- forward declared: askDelete(entry)
local function refreshList(list)
	if not list.scroll.Parent then return end
	for _, r in list.rows do r:Destroy() end
	table.clear(list.rows)
	for i, e in entries do
		local row = list.tpl:Clone()
		row.Name = "Replay_" .. i
		row.Visible = true
		row.LayoutOrder = i
		local btn = row:FindFirstChild("SpectateImage")
		if btn and btn:IsA("GuiButton") then
			local id = e.Id
			btn.Activated:Connect(function() play(id) end)
		end
		local bin = row:FindFirstChild("BinImage")
		if bin and bin:IsA("GuiButton") then
			bin.Activated:Connect(function() askDelete(e) end)
		end
		paintRow(row, e)
		row.Parent = list.scroll
		table.insert(list.rows, row)
	end
	if list.empty then list.empty.Visible = #entries == 0 end
end
local function refreshAll() for _, l in lists do refreshList(l) end end

local fetching = false
local function fetch()
	if fetching then return end
	fetching = true
	local ok, list = pcall(function() return Remote:InvokeServer("List") end)
	fetching = false
	if ok and type(list) == "table" then
		entries = list
		refreshAll()
	end
end
Changed.OnClientEvent:Connect(fetch)

-- LIVE DESIGN: change the row template while playing (Studio play test / a live session) and the rows rebuild with it
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

------------------------------------------------------------ DELETE (bin button -> "Are you sure?")
local deleting -- the replay the open prompt is about
local deletePrompt
local hiddenBehind -- the menu hidden while the prompt is open (Main > WatchFrame): back when it closes
local function closeDelete()
	deleting = nil
	if deletePrompt then deletePrompt.Visible = false end
	if hiddenBehind and hiddenBehind.Parent then hiddenBehind.Visible = true end
	hiddenBehind = nil
end
local function doDelete(e)
	-- gone from the list straight away; the server takes it off your saved list
	for i = #entries, 1, -1 do if entries[i].Id == e.Id then table.remove(entries, i) end end
	refreshAll()
	SFX.Play("DuelDeclined")
	task.spawn(function()
		local ok, res, why = pcall(function() return Remote:InvokeServer("Delete", e.Id) end)
		if not (ok and res) then
			notice((ok and why) or "Couldn't delete that replay")
			fetch()
		end
	end)
end
askDelete = function(e)
	if not deletePrompt or not deletePrompt.Parent then doDelete(e) return end -- (no prompt designed: just delete)
	deleting = e
	local title = deletePrompt:FindFirstChild("Title", true)
	if title and title:IsA("TextLabel") then title.Text = deletePrompt:GetAttribute("Text") or "Are you sure you want to delete this replay?" end
	local img = deletePrompt:FindFirstChild("MapImage", true)
	if img and img:IsA("ImageLabel") and (e.Image or "") ~= "" then img.Image = e.Image end
	-- the replays menu steps aside while you answer (comes back on Delete / Cancel)
	local wf = deletePrompt.Parent:FindFirstChild("WatchFrame")
	if wf and wf.Visible then
		hiddenBehind = wf
		wf.Visible = false
	end
	deletePrompt.Visible = true
	local pop = deletePrompt:FindFirstChild("OpenPop") or Instance.new("UIScale")
	pop.Name = "OpenPop"
	pop.Parent = deletePrompt
	pop.Scale = 0.7
	TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	SFX.Play("Open")
end
local function hookDeletePrompt(main)
	local p = main:WaitForChild("DeleteReplayPrompt", 10)
	if not p then return end
	deletePrompt = p
	p.Visible = false
	local yes, no = p:FindFirstChild("YesButton", true), p:FindFirstChild("NoButton", true)
	if yes and yes:IsA("GuiButton") then
		yes:SetAttribute("NoClickSound", true)
		yes.Activated:Connect(function()
			local e = deleting
			closeDelete()
			if e then doDelete(e) end
		end)
	end
	if no and no:IsA("GuiButton") then no.Activated:Connect(closeDelete) end
	-- controller Circle / B = No (fired by ControllerSupport)
	local back = p:FindFirstChild("PadBack") or Instance.new("BindableEvent")
	back.Name = "PadBack"
	back.Parent = p
	back.Event:Connect(closeDelete)
end

local function hookMenu(main)
	task.spawn(hookDeletePrompt, main)
	local wf = main:WaitForChild("WatchFrame", 10)
	local scroll = wf and wf:WaitForChild("ReplaysList", 10)
	local own = wf and wf:WaitForChild("Templates", 10)
	own = own and own:WaitForChild("ReplayRow", 10)
	if not (scroll and own) then warn("[Replays] WatchFrame needs ReplaysList + Templates > ReplayRow") return end
	for i = #lists, 1, -1 do if not lists[i].scroll.Parent then table.remove(lists, i) end end
	local tpl = own:Clone()
	tpl.Visible = true
	local lay = scroll:FindFirstChildOfClass("UIListLayout")
	if not lay then
		lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 6)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.Parent = scroll
	end
	lay.SortOrder = Enum.SortOrder.LayoutOrder -- (rows go in order; padding / alignment are yours to set)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() scroll.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 10) end)
	local list = {scroll = scroll, tpl = tpl, rows = {}}
	list.empty = makeEmpty(scroll)
	table.insert(lists, list)
	refreshList(list)
	watchTemplate(own, function()
		local fresh = own:Clone()
		fresh.Visible = true
		list.tpl = fresh
		refreshList(list)
	end)
	-- fresh list every time the Replays tab is opened; closing the menu closes the delete question too
	wf:GetAttributeChangedSignal("Tab"):Connect(function() if wf:GetAttribute("Tab") == "Replays" and wf.Visible then task.spawn(fetch) end end)
	wf:GetPropertyChangedSignal("Visible"):Connect(function()
		if wf.Visible and wf:GetAttribute("Tab") == "Replays" then task.spawn(fetch) end
		if not wf.Visible then closeDelete() end
	end)
end
do
	local m = pg:FindFirstChild("Main")
	if m then task.spawn(hookMenu, m) end
	pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hookMenu, c) end end)
	task.spawn(fetch)
end

------------------------------------------------------------ HUD (StarterGui > ReplayHUD)
local hud = pg:WaitForChild("ReplayHUD", 300) -- (a timeout = no "infinite yield" warning while the loading screen is up)
hud.Enabled = false
local top = hud:WaitForChild("Top")
local team1Holder, team2Holder, mid = top:WaitForChild("Team1"), top:WaitForChild("Team2"), top:WaitForChild("Middle")
local timerLabel, score1, score2 = mid:WaitForChild("Timer"), mid:WaitForChild("Score1"), mid:WaitForChild("Score2")
local faceTpl = hud:WaitForChild("FaceTemplate")
local titleLabel = hud:WaitForChild("Watching")
local viewers = hud:FindFirstChild("Viewers")
if viewers then viewers.Visible = false end
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
local controls = hud:WaitForChild("Controls")
local roundBackBtn, pauseBtn, roundNextBtn, speedBtn = controls:WaitForChild("RoundBack"), controls:WaitForChild("Pause"), controls:WaitForChild("RoundNext"), controls:WaitForChild("Speed")
local pauseLabel, speedLabel = pauseBtn:FindFirstChild("Label"), speedBtn:FindFirstChild("Label")
local timeline = hud:WaitForChild("Timeline")
local timeFill, knob = timeline:WaitForChild("Fill"), timeline:WaitForChild("Knob")
local timeText = hud:WaitForChild("Time")

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
	for _, g in {top, bottom, freeBtn, leaveBtn, hpBack, hpLabel, titleLabel, controls, timeText} do
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

------------------------------------------------------------ DECODING
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local dec = {}
for i = 1, 64 do dec[string.byte(B64, i)] = i - 1 end
local function fromBase64(s)
	local len = #s
	local pad = (s:sub(-2) == "==" and 2) or (s:sub(-1) == "=" and 1) or 0
	local out = buffer.create(math.max(0, len // 4 * 3 - pad))
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = (dec[a] or 0) * 262144 + (dec[b] or 0) * 4096 + (dec[c] or 0) * 64 + (dec[d] or 0)
		if o < buffer.len(out) then buffer.writeu8(out, o, (v // 65536) % 256) end
		if o + 1 < buffer.len(out) then buffer.writeu8(out, o + 1, (v // 256) % 256) end
		if o + 2 < buffer.len(out) then buffer.writeu8(out, o + 2, v % 256) end
		o += 3
	end
	return out
end
-- one sample: position (map space), yaw, pitch, flags, hp - or nil if they weren't there
-- (12 bytes = current format; 10 bytes = the first replays, with rougher aim)
local function sample(buf, i, frames, bytes)
	if i < 0 or i >= frames or (i + 1) * bytes > buffer.len(buf) then return nil end
	local o = i * bytes
	local pos = Vector3.new(buffer.readi16(buf, o) / 16, buffer.readi16(buf, o + 2) / 16, buffer.readi16(buf, o + 4) / 16)
	if bytes >= 12 then
		local flags = buffer.readu8(buf, o + 10)
		if flags == 255 then return nil end
		-- (14 bytes = + their real camera height above the body)
		local eye
		if bytes >= 14 then
			local e = buffer.readi16(buf, o + 12)
			if e ~= -32768 then eye = e / 256 end
		end
		return pos, buffer.readu16(buf, o + 6) / 65536 * 2 * math.pi, buffer.readi16(buf, o + 8) / 32767 * (math.pi / 2), flags, buffer.readu8(buf, o + 11), eye
	end
	local flags = buffer.readu8(buf, o + 8)
	if flags == 255 then return nil end
	return pos, buffer.readu8(buf, o + 6) / 256 * 2 * math.pi, buffer.readi8(buf, o + 7) / 127 * (math.pi / 2), flags, buffer.readu8(buf, o + 9)
end
local function lerpAngle(a, b, t)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

------------------------------------------------------------ PLAYBACK
local R -- the replay being watched (nil = none)
local DEATH_CAM_TIME = 2.2 -- seconds the camera rides the fall before moving to someone still alive
local SHOT_SNAP = 0.15 -- seconds around each throw the aim locks onto where the throw went

local function state(person, t)
	local f = t * R.rate
	local i = math.floor(f)
	local a = f - i
	local p1, y1, pi1, fl1, hp1, e1 = sample(person.buf, i, R.frames, R.bytes)
	if not p1 then return nil end
	local p2, y2, pi2, _, _, e2 = sample(person.buf, i + 1, R.frames, R.bytes)
	if not p2 then p2, y2, pi2, e2 = p1, y1, pi1, e1 end
	-- (a teleport between two samples - respawn / new round - jumps instead of sliding across the map)
	if (p2 - p1).Magnitude > 30 then p2, y2, pi2, e2 = p1, y1, pi1, e1 end
	local eye = e1 and (e2 and e1 + (e2 - e1) * a or e1)
	return p1:Lerp(p2, a), lerpAngle(y1, y2, a), pi1 + (pi2 - pi1) * a, fl1, hp1, (p2 - p1) * R.rate, eye
end
-- alive = the alive flag AND some health left (a body at 0 HP can still be flagged alive for a moment while it
-- ragdolls / falls away - that's what used to drag the camera through the map)
local function isAlive(flags, hp) return flags % 2 == 1 and (hp == nil or hp > 0) end
local function aliveAt(person, t)
	local p, _, _, flags, hp = state(person, t)
	return p ~= nil and isAlive(flags, hp)
end
-- when they died, if it was in the last few seconds (nil = alive, or dead for a while), plus where they were standing
-- and looking at that moment. (After dying the recording follows the body / the spectator spot, which can be under
-- the map - so the death fall always starts from the last spot they were alive.)
local function deathTime(person, t)
	local i = math.floor(t * R.rate)
	for k = i, math.max(0, i - math.floor(4 * R.rate)), -1 do
		local p, yaw, pitch, flags, hp = sample(person.buf, k, R.frames, R.bytes)
		-- (a gap right as they die - the respawn / ragdoll swap - is skipped, not treated as "not in the match")
		if p and isAlive(flags, hp) then return (k + 1) / R.rate, p, yaw, pitch, (flags // 2) % 2 == 1 or (flags // 16) % 2 == 1 end
	end
	return nil
end

local ANIM_NAMES = {"Idle", "Walk", "Run", "Crouch", "CrouchWalk", "Slide", "Jump", "Fall"}
local function setupGhost(person)
	local g = person.ghost
	local hum = g:FindFirstChildOfClass("Humanoid")
	local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 2))
	person.tracks = {}
	if not animator then return end
	for _, n in ANIM_NAMES do
		local id = MoveConfig.Anims and MoveConfig.Anims[n]
		if id then
			local a = Instance.new("Animation")
			a.AnimationId = id
			local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
			if ok then
				tr.Looped = n ~= "Jump"
				person.tracks[n] = tr
			end
		end
	end
end
local function playAnim(person, name, speed)
	if person.anim ~= name then
		if person.anim and person.tracks[person.anim] then person.tracks[person.anim]:Stop(0.15) end
		person.anim = name
		local tr = name and person.tracks[name]
		if tr then tr:Play(0.15) end
	end
	local tr = name and person.tracks[name]
	-- (paused = frozen mid-step; 2x playback = legs move 2x)
	if tr then tr:AdjustSpeed((R and R.paused) and 0 or (speed or 1) * (R and R.speed or 1)) end
end

local function worldPoint(v)
	if type(v) ~= "table" then return nil end
	return R.origin * Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0)
end

local function flyShot(from, to, pop)
	local tpl = Balloon:FindFirstChild("BalloonTemplate")
	local b = tpl and tpl:Clone() or Instance.new("Part")
	b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
	if b:IsA("BasePart") then b.Size *= 0.6 end
	for _, d in b:GetDescendants() do if d:IsA("Beam") then d.Enabled = false end end
	b.CFrame = CFrame.new(from)
	b.Parent = workspace
	local tw = TweenService:Create(b, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {CFrame = CFrame.new(to)})
	tw:Play()
	tw.Completed:Connect(function()
		if pop then
			local flash = Instance.new("Part")
			flash.Shape = Enum.PartType.Ball
			flash.Material = Enum.Material.Neon
			flash.Color = b.Color
			flash.Anchored, flash.CanCollide, flash.CanQuery = true, false, false
			flash.Size = Vector3.one * 0.6
			flash.CFrame = CFrame.new(to)
			flash.Parent = workspace
			TweenService:Create(flash, TweenInfo.new(0.15), {Size = Vector3.one * 3.5, Transparency = 1}):Play()
			task.delay(0.3, function() flash:Destroy() end)
		end
		b:Destroy()
	end)
end

-- scores / round / fight timer at time t (from the round events)
local function matchState(t)
	local s1, s2, round, fightT, fightLen = 0, 0, 1, nil, 0
	for _, e in R.events do
		if e.t > t then break end
		if e.k == "round" then s1, s2, round, fightT = e.s1 or s1, e.s2 or s2, e.round or round, nil
		elseif e.k == "fight" then fightT, fightLen = e.t, e.len or 0
		elseif e.k == "roundEnd" then s1, s2, fightT = e.s1 or s1, e.s2 or s2, nil end
	end
	return s1, s2, round, fightT, fightLen
end

local function paintTop(s1, s2)
	local c1, c2 = sideColors(s1, s2)
	score1.Text, score2.Text = tostring(s1), tostring(s2)
	score1.TextColor3, score2.TextColor3 = c1, c2
	for t, holder in {team1Holder, team2Holder} do
		for _, img in holder:GetChildren() do
			if img:IsA("ImageLabel") then
				img.BackgroundColor3 = t == 1 and c1 or c2
				local person = R.byId[tonumber(img.Name)]
				img.ImageTransparency = (person and aliveAt(person, R.t)) and 0 or 0.6
			end
		end
	end
end

local function buildTop()
	for t, holder in {team1Holder, team2Holder} do
		for _, c in holder:GetChildren() do if c:IsA("ImageLabel") then c:Destroy() end end
		local i = 0
		for _, person in R.people do
			if person.Team == t then
				i += 1
				local img = faceTpl:Clone()
				img.Name = tostring(person.UserId)
				img.Visible = true
				img.LayoutOrder = t == 1 and -i or i
				img.Image = headshot(person.UserId)
				img.Parent = holder
			end
		end
	end
end

local function paintName()
	local p = R and R.pov
	if not p then nameLabel.Text = "" return end
	nameLabel.Text = NameBadge.Format(p.Name or "?", p.Verified)
	local s1, s2 = matchState(R.t)
	local c1, c2 = sideColors(s1, s2)
	local c = p.Team == 2 and c2 or c1
	if nameLine then nameLine.BackgroundColor3 = c end
	if nameGrad then nameGrad.Color = ColorSequence.new(DARK, DARK:Lerp(c, 0.45)) end
end

local function setPov(person)
	if not person then return end
	if R.pov and R.pov.ghost then R.pov.ghost:SetAttribute("SpecDead", nil) end
	R.pov = person
	if person.ghost then ClientActions:Fire("SpectateTarget", person.ghost) end
	paintName()
end

local function cycle(dir)
	local list = R.people
	if #list == 0 then return end
	local cur = table.find(list, R.pov) or 0
	for step = 1, #list do
		local i = ((cur - 1 + dir * step) % #list) + 1
		if aliveAt(list[i], R.t) or step == #list then setPov(list[i]) break end
	end
	SFX.Play("ButtonPress")
end

local function setFree(on)
	R.free = on
	if on then R.freeCF = workspace.CurrentCamera.CFrame else UIS.MouseBehavior = Enum.MouseBehavior.Default end
	ClientActions:Fire("SpectateFreecam", on)
	freeBtn.BackgroundColor3 = on and freeColor:Lerp(Color3.new(1, 1, 1), 0.25) or freeColor
end

local function setPaused(on)
	R.paused = on
	if pauseLabel then pauseLabel.Text = on and "▶" or "II" end
end

-- jump to time t: events before it are skipped (not replayed)
local function seek(t)
	R.t = math.clamp(t, 0, R.length)
	R.nextEvent = 1
	while R.events[R.nextEvent] and R.events[R.nextEvent].t <= R.t do R.nextEvent += 1 end
	if R.pov and R.pov.ghost then ClientActions:Fire("SpectateTarget", R.pov.ghost) end -- balloon back in hand
	if R.t >= R.length then setPaused(true) end
end

local function roundStarts()
	local list = {0}
	for _, e in R.events do if e.k == "round" and e.t > 0.5 then table.insert(list, e.t) end end
	return list
end
local function roundBack()
	local target = 0
	for _, s in roundStarts() do if s < R.t - 2 then target = s end end
	seek(target)
end
local function roundNext()
	for _, s in roundStarts() do if s > R.t + 0.1 then seek(s) return end end
	seek(R.length)
end
local function togglePause()
	if R.t >= R.length then seek(0) end
	setPaused(not R.paused)
end
local function nextSpeed()
	local i = table.find(SPEEDS, R.speed) or 2
	R.speed = SPEEDS[i % #SPEEDS + 1]
	if speedLabel then speedLabel.Text = (R.speed == 0.5 and "0.5" or tostring(R.speed)) .. "x" end
end

-- back in the lobby: make sure the lobby UI is really back (bottom buttons, XP bar, top bar...), whatever hid it
local function restoreLobbyUI()
	task.spawn(function()
		-- (the server clears WatchingReplay a moment after we stop: wait for it, up to 5s, instead of giving up -
		-- giving up early is what left the bottom buttons hidden after a replay)
		local t0 = os.clock()
		repeat task.wait(0.1) until not (player:GetAttribute("WatchingReplay") or player:GetAttribute("WatchingMatch")) or os.clock() - t0 > 5 or R
		if R then return end -- (started watching another one)
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
local function stopReplay(tellServer)
	if not R then return end
	local r = R
	R = nil
	RunService:UnbindFromRenderStep("ReplayCamera")
	for _, person in r.people do
		for _, tr in person.tracks or {} do pcall(function() tr:Stop(0) end) end
	end
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	hud.Enabled = false
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	if r.oldFOV then cam.FieldOfView = r.oldFOV end
	ClientActions:Fire("SpectateEnd")
	local ui = pg:FindFirstChild("BalloonCombatUI")
	local ch = ui and ui:FindFirstChild("Crosshair")
	if ch and ch:IsA("GuiObject") then ch.Visible = false end
	local kp = ui and ui:FindFirstChild("KillPopup")
	if kp and kp:IsA("GuiObject") then kp.Visible = false end
	local main = pg:FindFirstChild("Main")
	if main then main.Enabled = true end
	for _, n in {"SpectateWall"} do local w = pg:FindFirstChild(n) if w then w.Enabled = true end end
	if tellServer ~= false then task.spawn(function() pcall(function() Remote:InvokeServer("Stop") end) end) end
	restoreLobbyUI()
end

play = function(id)
	if R or player:GetAttribute("WatchingMatch") then return end
	local ok, res, why = pcall(function() return Remote:InvokeServer("Watch", id) end)
	if not (ok and type(res) == "table") then
		SFX.Play("Error")
		notice((ok and why) or "Couldn't load that replay")
		return
	end
	local okj, rep = pcall(HttpService.JSONDecode, HttpService, res.Json)
	if not okj then pcall(function() Remote:InvokeServer("Stop") end) notice("That replay is broken") return end
	local session = workspace:WaitForChild("ReplaySessions"):WaitForChild(res.Session, 15)
	local ghosts = session and session:WaitForChild("Ghosts", 10)
	if not ghosts then pcall(function() Remote:InvokeServer("Stop") end) notice("Couldn't load that replay") return end
	local menu = pg:FindFirstChild("Main") and pg.Main:FindFirstChild("WatchFrame")
	if menu then menu.Visible = false end

	R = {
		rep = rep, rate = rep.Rate or 10, frames = rep.Frames or 0, bytes = rep.Bytes or 10, events = rep.Events or {},
		origin = CFrame.new(table.unpack(res.Origin)), people = {}, byId = {},
		t = 0, speed = 1, paused = false, nextEvent = 1, free = false, freeCF = CFrame.new(),
	}
	R.length = R.frames / R.rate
	table.sort(R.events, function(a, b) return (a.t or 0) < (b.t or 0) end)
	for t = 1, 2 do
		for _, p in rep.People or {} do
			if (p.Team or 1) == t then
				local person = {UserId = p.UserId, Name = p.Name, Verified = p.Verified, Team = p.Team or 1, buf = fromBase64(p.Data or ""), tracks = {}, shots = {}}
				person.ghost = ghosts:WaitForChild(tostring(p.UserId), 10)
				if person.ghost then setupGhost(person) end
				table.insert(R.people, person)
				R.byId[p.UserId] = person
			end
		end
	end
	-- each person's throws (their aim snaps onto these, so the replay crosshair is exactly where they threw)
	for _, e in R.events do
		if e.k == "shot" and R.byId[e.u] then table.insert(R.byId[e.u].shots, e) end
	end
	local cam = workspace.CurrentCamera
	R.oldFOV = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = GS.Get("FOV") or CombatConfig.CameraFOV or 70
	titleLabel.Text = ("REPLAY  •  %s  •  %s"):format((rep.Map or ""):upper(), rep.Mode or "")
	buildTop()
	setPaused(false)
	if speedLabel then speedLabel.Text = "1x" end
	freeBtn.BackgroundColor3 = freeColor
	hud.Enabled = true
	SFX.Play("Open")
	ClientActions:Fire("SpectateStart")
	setPov(R.byId[player.UserId] or R.people[1])
	seek(0)

	local focusSent = 0
	RunService:BindToRenderStep("ReplayCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not R then return end
		local main = pg:FindFirstChild("Main")
		if main and main.Enabled then main.Enabled = false end
		for _, n in {"SpectateWall"} do local w = pg:FindFirstChild(n) if w and w.Enabled then w.Enabled = false end end
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end

		-- time
		if not R.paused and not R.dragging then
			R.t = math.min(R.t + dt * R.speed, R.length)
			if R.t >= R.length then setPaused(true) end
		end
		local t = R.t
		-- events since the last frame
		while R.events[R.nextEvent] and R.events[R.nextEvent].t <= t do
			local e = R.events[R.nextEvent]
			R.nextEvent += 1
			if t - e.t < 0.5 then -- (no effects when jumping far ahead)
				local pov = R.pov and R.pov.UserId
				if e.k == "shot" then
					local from, to = worldPoint(e.from), worldPoint(e.to)
					if e.u == pov and not R.free then
						ClientActions:Fire("SpectateShot", to, e.pop == true)
					elseif from and to then
						flyShot(from, to, e.pop)
						SFX.Play("Shoot", from)
					end
				elseif e.k == "swing" then
					if e.u == pov and not R.free then ClientActions:Fire("SpectateSwing")
					else
						local person = R.byId[e.u]
						local head = person and person.ghost and person.ghost:FindFirstChild("Head")
						if head then SFX.Play("Swing", head) end
					end
				elseif e.k == "hit" and e.a == pov and ReplayFX then
					local pos = worldPoint(e.pos)
					local victim = R.byId[e.v]
					if pos then ReplayFX:Fire("Damage", {pos = pos, amount = e.n or 0, head = e.head, melee = e.melee, target = victim and victim.ghost}) end
				elseif e.k == "kill" and e.a == pov and ReplayFX then
					local victim = R.byId[e.v]
					ReplayFX:Fire("Kill", {victim = victim and victim.Name or "?", tags = e.tags or {}, distance = 0, victimUserId = e.v})
				end
			end
		end

		-- the stand-ins
		for _, person in R.people do
			local g = person.ghost
			local root = g and g.Parent and g:FindFirstChild("HumanoidRootPart")
			if root then
				local pos, yaw, _, flags, ghp, vel = state(person, t)
				-- paused: the first-person arms freeze too (BalloonCombatClient reads SpecPaused)
				g:SetAttribute("SpecPaused", R.paused or nil)
				if pos and isAlive(flags, ghp) then
					root.CFrame = R.origin * CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
					g:SetAttribute("SpecVel", vel)
					local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
					local crouch, air, sprint, slide = (flags // 2) % 2 == 1, (flags // 4) % 2 == 1, (flags // 8) % 2 == 1, (flags // 16) % 2 == 1
					if slide then playAnim(person, "Slide")
					elseif air then playAnim(person, vel.Y > 1 and "Jump" or "Fall")
					elseif crouch then playAnim(person, speed > 1 and "CrouchWalk" or "Crouch", speed > 1 and math.clamp(speed / 8, 0.5, 2) or 1)
					elseif speed > 1 then
						if sprint or speed > 20 then playAnim(person, "Run", math.clamp(speed / 26, 0.6, 1.6))
						else playAnim(person, "Walk", math.clamp(speed / 16, 0.5, 1.6)) end
					else playAnim(person, "Idle") end
				else
					-- just died: they fall over where their body went; after that they're tucked away under the map
					local died, lastPos, lastYaw = deathTime(person, t)
					if died and t - died < 3 then
						local fall = math.clamp((t - died) / 0.45, 0, 1)
						root.CFrame = R.origin * CFrame.new(lastPos) * CFrame.Angles(0, lastYaw, 0) * CFrame.new(0, -1.6 * fall, 0) * CFrame.Angles(-math.rad(88) * fall, 0, 0)
					else
						root.CFrame = R.origin * CFrame.new(0, -400, 0)
					end
					playAnim(person, nil)
				end
			end
		end

		-- UI: scores, timer, timeline
		local s1, s2, round, fightT, fightLen = matchState(t)
		paintTop(s1, s2)
		if R.paused and t >= R.length then
			timerLabel.Text = "END"
		elseif fightT and fightLen > 0 then
			timerLabel.Text = clock(math.ceil(fightLen - (t - fightT)))
		else
			timerLabel.Text = "ROUND " .. round
		end
		local frac = R.length > 0 and t / R.length or 0
		timeFill.Size = UDim2.fromScale(frac, 1)
		knob.Position = UDim2.fromScale(frac, 0.5)
		timeText.Text = clock(t) .. " / " .. clock(R.length)

		local focusPos
		local ui = pg:FindFirstChild("BalloonCombatUI")
		local ch = ui and ui:FindFirstChild("Crosshair")
		if R.free then
			local move = Vector3.zero
			if isPhone or UIS:GetLastInputType() == Enum.UserInputType.Touch or GS.UsingGamepad() then
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				move = hum and hum.MoveDirection or Vector3.zero
			elseif not UIS:GetFocusedTextBox() then
				local lv, rv = R.freeCF.LookVector, R.freeCF.RightVector
				if GS.IsDown("MoveForward") then move += lv end
				if GS.IsDown("MoveBackward") then move -= lv end
				if GS.IsDown("StrafeRight") then move += rv end
				if GS.IsDown("StrafeLeft") then move -= rv end
				if GS.IsDown("FreecamUp") then move += Vector3.yAxis end
				if GS.IsDown("FreecamDown") then move -= Vector3.yAxis end
			end
			local speed = GS.IsDown("Sprint") and FREECAM_FAST or FREECAM_SPEED
			if move.Magnitude > 0 then R.freeCF += move.Unit * speed * dt end
			local pst = padStick()
			if pst.Magnitude > 0.15 then
				local pp, py = R.freeCF:ToEulerAnglesYXZ()
				pp = math.clamp(pp + pst.Y * dt * 2.2, math.rad(-85), math.rad(85))
				py -= pst.X * dt * 3
				R.freeCF = CFrame.new(R.freeCF.Position) * CFrame.fromEulerAnglesYXZ(pp, py, 0)
			end
			if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				local d = UIS:GetMouseDelta()
				local pitch, yaw = R.freeCF:ToEulerAnglesYXZ()
				pitch = math.clamp(pitch - d.Y * 0.004, math.rad(-85), math.rad(85))
				yaw -= d.X * 0.004
				R.freeCF = CFrame.new(R.freeCF.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
			elseif UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
				UIS.MouseBehavior = Enum.MouseBehavior.Default
			end
			cam.CFrame = R.freeCF
			focusPos = R.freeCF.Position
			hpLabel.Visible, hpBack.Visible = false, false
			if ch and ch:IsA("GuiObject") and ch.Visible then ch.Visible = false end
		else
			-- FIRST PERSON through the chosen player
			local pov = R.pov
			local pos, yaw, pitch, flags, hp, eyeH
			if pov then pos, yaw, pitch, flags, hp, _, eyeH = state(pov, t) end
			hpLabel.Visible, hpBack.Visible = true, true
			if pos then
				local alive = isAlive(flags, hp)
				local crouch = (flags // 2) % 2 == 1 or (flags // 16) % 2 == 1
				-- their real camera height when recorded (newer replays), else a standing / crouching guess
				local eye = R.origin * (pos + Vector3.new(0, eyeH or (crouch and 0.6 or 1.5), 0))
				local look = (R.origin.Rotation * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)).LookVector
				-- exact aim on every throw: the look eases onto where the throw actually went
				for _, s in pov.shots do
					local d = math.abs(s.t - t)
					if d < SHOT_SNAP then
						-- (from their eye to where it landed = exactly where their crosshair was)
						local to = worldPoint(s.to)
						if to and (to - eye).Magnitude > 0.5 then
							look = look:Lerp((to - eye).Unit, 1 - d / SHOT_SNAP).Unit
						end
					elseif s.t > t then
						break
					end
				end
				if alive then
					if pov.ghost then pov.ghost:SetAttribute("SpecDead", nil) end
					cam.CFrame = CFrame.lookAt(eye, eye + look)
					if ch and ch:IsA("GuiObject") and not ch.Visible then ch.Visible = true end
				else
					-- DEATH CAMERA: drops and tips over with their fall, then moves on to someone still fighting
					if pov.ghost then pov.ghost:SetAttribute("SpecDead", true) end
					if ch and ch:IsA("GuiObject") and ch.Visible then ch.Visible = false end
					local died, lastPos, lastYaw, lastPitch, lastCrouch = deathTime(pov, t)
					if died then
						-- fall from where they died, looking where they last looked
						eye = R.origin * (lastPos + Vector3.new(0, lastCrouch and 0.6 or 1.5, 0))
						look = (R.origin.Rotation * CFrame.fromEulerAnglesYXZ(lastPitch, lastYaw, 0)).LookVector
					end
					died = died or t
					local fall = math.clamp((t - died) / 0.45, 0, 1)
					local base = CFrame.lookAt(eye, eye + look)
					cam.CFrame = base * CFrame.new(0, -1.8 * fall, 0.4 * fall) * CFrame.Angles(math.rad(-35) * fall, 0, math.rad(70) * fall)
					if t - died > DEATH_CAM_TIME then
						for _, person in R.people do if person ~= pov and aliveAt(person, t) then setPov(person) break end end
					end
				end
				focusPos = eye
				local shownHp = alive and hp or 0
				hpLabel.Text = shownHp .. " HP"
				local f = math.clamp(shownHp / 100, 0, 1)
				hpFill.Size = UDim2.fromScale(f, 1)
				hpFill.BackgroundColor3 = f > 0.5 and GREEN or (f > 0.25 and Color3.fromRGB(255, 170, 60) or RED)
			else
				-- not in the match at this moment (e.g. left early): pick someone who is
				for _, person in R.people do if person ~= pov and state(person, t) then setPov(person) break end end
			end
		end
		if focusPos and os.clock() - focusSent > 0.4 then
			focusSent = os.clock()
			CamRemote:FireServer(focusPos)
		end
	end)
end

------------------------------------------------------------ INPUT
prevBtn.Activated:Connect(function() if R then if R.free then setFree(false) end cycle(-1) end end)
nextBtn.Activated:Connect(function() if R then if R.free then setFree(false) end cycle(1) end end)
freeBtn.Activated:Connect(function() if R then setFree(not R.free) SFX.Play("ButtonPress") end end)
leaveBtn.Activated:Connect(function() stopReplay() end)
pauseBtn.Activated:Connect(function() if R then togglePause() end end)
speedBtn.Activated:Connect(function() if R then nextSpeed() end end)
roundBackBtn.Activated:Connect(function() if R then roundBack() end end)
roundNextBtn.Activated:Connect(function() if R then roundNext() end end)
-- timeline: click / drag to jump
local function seekTo(x)
	if not R then return end
	local a, s = timeline.AbsolutePosition.X, timeline.AbsoluteSize.X
	seek(math.clamp((x - a) / math.max(s, 1), 0, 1) * R.length)
end
timeline.InputBegan:Connect(function(input)
	if not R then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		R.dragging = true
		seekTo(input.Position.X)
	end
end)
UIS.InputChanged:Connect(function(input)
	if R and R.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		seekTo(input.Position.X)
	end
end)
UIS.InputEnded:Connect(function(input)
	if R and R.dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		R.dragging = false
	end
end)
-- keys: Settings > Controls > Spectate & Replays
UIS.InputBegan:Connect(function(input, gpe)
	if not R or gpe then return end
	if GS.Is("LeaveArena", input) then stopReplay()
	elseif GS.Is("ReplayPause", input) then togglePause()
	elseif GS.Is("Freecam", input) then setFree(not R.free)
	elseif GS.Is("ReplayBack", input) then seek(R.t - 5)
	elseif GS.Is("ReplayForward", input) then seek(R.t + 5)
	elseif GS.Is("ReplayPrevRound", input) then roundBack()
	elseif GS.Is("ReplayNextRound", input) then roundNext()
	elseif GS.Is("ReplaySpeed", input) then nextSpeed()
	elseif R.free then return -- in freecam E / Q fly up / down
	elseif GS.Is("SpectatePrev", input) then cycle(-1)
	elseif GS.Is("SpectateNext", input) then cycle(1)
	end
end)
UIS.TouchMoved:Connect(function(touch, gpe)
	if not (R and R.free) or gpe then return end
	local d = touch.Delta
	local pitch, yaw = R.freeCF:ToEulerAnglesYXZ()
	pitch = math.clamp(pitch - d.Y * 0.006, math.rad(-85), math.rad(85))
	yaw -= d.X * 0.006
	R.freeCF = CFrame.new(R.freeCF.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end)

player:GetAttributeChangedSignal("WatchingReplay"):Connect(function()
	if R and player:GetAttribute("WatchingReplay") == nil then stopReplay(false) end
end)
player.CharacterAdded:Connect(function() if R then stopReplay() end end)
