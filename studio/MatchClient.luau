-- MATCH CLIENT
-- Drives StarterGui > MatchUI. EVERYTHING in MatchUI is optional and restyleable:
-- the script only looks things up BY NAME, skips anything it can't find, never forces sizes,
-- and only sets colours from the attributes on MatchUI (WinColor, LoseColor, MyTeamColor ...).
-- See MatchUI > UI_GUIDE for the full list of names the script looks for.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local player = Players.LocalPlayer
local gui = script.Parent
local MM = RS:WaitForChild("Matchmaking")
local Config = require(MM:WaitForChild("Config"))
local PlayerCard = require(MM:WaitForChild("PlayerCard"))
local Remotes = MM:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent")
local VoteRemote = Remotes:WaitForChild("Vote")
local DeviceRemote = Remotes:WaitForChild("Device")
local SFX = require(RS:WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig

------------------------------------------------------------ SAFE HELPERS (missing UI never breaks anything)
local function get(parent, ...)
	local cur = parent
	for _, name in {...} do
		if not cur then return nil end
		cur = cur:FindFirstChild(name)
	end
	return cur
end
local function isText(o) return o and (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) end
local function setText(o, t) if isText(o) then o.Text = t end end
local function setTextColor(o, c) if isText(o) and c then o.TextColor3 = c end end
local function show(o, on) if o and o:IsA("GuiObject") then o.Visible = on end end
local function color(name) return gui:GetAttribute(name) end

local function tween(obj, t, props)
	if not obj then return end
	local ok, tw = pcall(function()
		return TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	end)
	if ok and tw then tw:Play() return tw end
end

-- "pop": starts a bit bigger and shrinks back to whatever size the designer gave it
local function pop(obj, scale)
	if not (obj and obj:IsA("GuiObject")) or gui:GetAttribute("PopAnimations") == false then return end
	local orig = obj:GetAttribute("DesignSize")
	if not orig then orig = obj.Size obj:SetAttribute("DesignSize", orig) end
	local k = scale or 1.25
	obj.Size = UDim2.new(orig.X.Scale * k, orig.X.Offset * k, orig.Y.Scale * k, orig.Y.Offset * k)
	tween(obj, 0.3, {Size = orig})
end

-- fade works on a Frame (BackgroundTransparency), ImageLabel (ImageTransparency) or CanvasGroup (GroupTransparency)
local function setFade(obj, alpha, t)
	if not obj then return end
	local prop = obj:IsA("CanvasGroup") and "GroupTransparency" or (obj:IsA("ImageLabel") and "ImageTransparency") or "BackgroundTransparency"
	if t and t > 0 then tween(obj, t, {[prop] = alpha}) else obj[prop] = alpha end
end
local function getFade(obj)
	if not obj then return 1 end
	if obj:IsA("CanvasGroup") then return obj.GroupTransparency end
	if obj:IsA("ImageLabel") then return obj.ImageTransparency end
	return obj.BackgroundTransparency
end

local function headshot(userId)
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(userId or 1, 1))
end

------------------------------------------------------------ DEVICE
-- the icon on your head tag / cards follows what you're PLAYING WITH right now: a controller on PC shows a controller,
-- keyboard + mouse on a console shows a PC. Controllers: "PlayStation" or "Xbox" (its own shape).
local function padType() return "Controller" end -- (one controller icon for every controller)
local function detectDevice()
	if GuiService:IsTenFootInterface() then return padType() end
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then return "Mobile" end
	if UIS.GamepadEnabled and not UIS.KeyboardEnabled and not UIS.MouseEnabled then return padType() end
	return "PC"
end
local sentDevice = detectDevice()
DeviceRemote:FireServer(sentDevice)
local function useDevice(d)
	if d == sentDevice then return end
	sentDevice = d
	DeviceRemote:FireServer(d)
end
local PAD_INPUT = {Gamepad1 = true, Gamepad2 = true, Gamepad3 = true, Gamepad4 = true}
UIS.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if PAD_INPUT[t.Name] then useDevice(padType())
	elseif t == Enum.UserInputType.Touch then useDevice("Mobile")
	elseif t == Enum.UserInputType.Keyboard or t.Name:find("^MouseButton") then useDevice("PC") end
end)

------------------------------------------------------------ UI LOOKUPS (re-looked up every time, so editing live is fine)
local function Fade() return gui:FindFirstChild("Fade") end
local function Vote() return gui:FindFirstChild("Vote") end
local function HUD() return gui:FindFirstChild("HUD") end
-- (the HUD's designed spot, saved before anything moves it - round results return it here)
do
	local h = HUD()
	if h and h:GetAttribute("DesignPos") == nil then
		h:SetAttribute("DesignPos", h.Position)
		h:SetAttribute("DesignAnchor", h.AnchorPoint)
	end
end
local function Center() return gui:FindFirstChild("Center") end
local function EndScreen() return gui:FindFirstChild("EndScreen") end

local function myTeam() return player:GetAttribute("MatchTeam") or 1 end
local function otherTeam() return myTeam() == 1 and 2 or 1 end

------------------------------------------------------------ FADE + LOGO
local function fadeToBlack()
	local f = Fade()
	if not f then return end
	show(f, true)
	setFade(f, 0, Config.FadeTime)
	task.wait(Config.FadeTime)
end
local function showLogo(on, textOverride)
	local f = Fade()
	local logo, logoImg = get(f, "Logo"), get(f, "LogoImage")
	local useImage = Config.LogoImage ~= "" and logoImg ~= nil
	if logoImg and logoImg:IsA("ImageLabel") then
		show(logoImg, useImage)
		if Config.LogoImage ~= "" then logoImg.Image = Config.LogoImage end
		tween(logoImg, 0.4, {ImageTransparency = (on and not textOverride) and 0 or 1})
	end
	if isText(logo) then
		show(logo, not useImage or textOverride ~= nil)
		logo.Text = textOverride or Config.LogoText
		tween(logo, 0.4, {TextTransparency = on and 0 or 1})
	end
end
local function fadeFromBlack()
	local f = Fade()
	if not f then return end
	setFade(f, 1, Config.FadeTime)
	showLogo(false)
	task.delay(Config.FadeTime, function()
		if getFade(f) > 0.99 then show(f, false) end
	end)
end

-- the combat health bar sits top-centre in the lobby/practice; during a match it moves to the bottom
-- so it doesn't cover the scoreboard (turn off with the MoveHealthBar attribute on MatchUI = false)
local savedHB
local function combatUI() return player.PlayerGui:FindFirstChild("BalloonCombatUI") end
local function matchLayout(on)
	if gui:GetAttribute("MoveHealthBar") == false then return end
	local hb = get(combatUI(), "HealthBar")
	if not hb then return end
	if on then
		if not savedHB then savedHB = {hb.Position, hb.AnchorPoint} end
		hb.AnchorPoint = Vector2.new(0.5, 1)
		hb.Position = UDim2.new(0.5, 0, 1, -24)
	elseif savedHB then
		hb.Position, hb.AnchorPoint = savedHB[1], savedHB[2]
		savedHB = nil
	end
end

-- When a screen opens, the script turns its pieces back on (designers often hide things while working).
-- Left alone: anything named ...Template, the pieces the script toggles itself (below),
-- and anything with the attribute AlwaysHidden = true (use that to hide something for real).
local MANAGED = {
	EloCard = true, RankChange = true, -- (ranked result: MatchUI > EloResultClient shows these itself)
	Dead = true, Selected = true, Dim = true, Spectating = true, Countdown = true,
	Banner = true, BannerSub = true, Subtitle = true, Logo = true, LogoImage = true,
}
local function reveal(root)
	if not root then return end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			if d:GetAttribute("AlwaysHidden") then
				d.Visible = false
			elseif not MANAGED[d.Name] and not d.Name:match("Template$") then
				d.Visible = true
			end
		end
	end
end

local function hideAll()
	show(Vote(), false)
	show(HUD(), false)
	show(EndScreen(), false)
	local c = Center()
	if c then for _, x in c:GetChildren() do show(x, false) end end
end

------------------------------------------------------------ END SCREEN CAMERA
-- slowly swings around in front of your character while the victory / defeat screen is up
local END_CAM = "MatchEndCamera"
local endCamOn = false
local function startEndCamera(duration, focusChar)
	-- focusChar = the MVP in team modes (they stand in the middle of their team's line-up)
	local char = focusChar or player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then char = player.Character root = char and char:FindFirstChild("HumanoidRootPart") focusChar = nil end
	if not root then return end
	endCamOn = true
	local cam = workspace.CurrentCamera
	-- face the way the character's HEAD looks (the root can point a different way after slides / animations)
	local head = char:FindFirstChild("Head")
	local look = (not focusChar and head) and head.CFrame.LookVector or root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then look = root.CFrame.LookVector * Vector3.new(1, 0, 1) end
	-- NEVER BEHIND A WALL: the camera swings round on the side with the most open space in front of them, and if
	-- something is still between it and them, it moves in front of that thing
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {cam}
	for _, pl in Players:GetPlayers() do if pl.Character then table.insert(ignore, pl.Character) end end
	params.FilterDescendantsInstances = ignore
	local far = (focusChar and 15 or 11) + 1
	local function clearance(dir)
		local worst = far
		for _, deg in {-28, 0, 28} do
			local d = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, math.rad(deg), 0)).LookVector * far + Vector3.new(0, 1.2, 0)
			local hit = workspace:Raycast(root.Position, d, params)
			if hit then worst = math.min(worst, (hit.Position - root.Position).Magnitude) end
		end
		return worst
	end
	local bestDir, bestClear = look.Unit, -1
	for _, turn in {0, 90, -90, 180} do
		local dir = (CFrame.lookAt(Vector3.zero, look.Unit) * CFrame.Angles(0, math.rad(turn), 0)).LookVector
		local c = clearance(dir)
		if c > bestClear + 0.5 then bestDir, bestClear = dir, c end
		if c >= far then break end
	end
	look = bestDir
	local base = CFrame.lookAt(root.Position, root.Position + look.Unit)
	local t0 = os.clock()
	pcall(function() RunService:UnbindFromRenderStep(END_CAM) end)
	RunService:BindToRenderStep(END_CAM, Enum.RenderPriority.Last.Value + 5, function()
		if not endCamOn then return end
		cam.CameraType = Enum.CameraType.Scriptable
		local a = math.clamp((os.clock() - t0) / math.max(duration, 1), 0, 1)
		local ease = 1 - (1 - a) ^ 2
		local angle = math.rad(-28 + 56 * ease) -- swing from one side to the other
		local dist = (focusChar and 15 or 11) - 3 * ease -- and push in a little (further back for a team line-up)
		local target = base.Position + Vector3.new(0, -0.6, 0)
		local offset = (base * CFrame.Angles(0, angle, 0)).LookVector * dist + Vector3.new(0, 1.2, 0)
		local hit = workspace:Raycast(base.Position, offset, params)
		if hit then offset = offset.Unit * math.max((hit.Position - base.Position).Magnitude - 0.6, 2.5) end
		cam.CFrame = CFrame.lookAt(base.Position + offset, target)
		local me = player.Character
		if me then
			for _, d in me:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end
			end
		end
	end)
end

------------------------------------------------------------ END SCREEN: DAILY QUESTS + LEVEL UP
-- EndScreen > ResultsThing > QuestsFrame > Quest1..3 (Text, Amount, Progress > Fill, CoinAmount), Label,
-- and LevelUpFrame (Result "10 < 12", CoinAmount). Only quests you moved forward this match are shown.
local QuestConfig = require(RS:WaitForChild("QuestConfig"))
local questToken = 0
local function fillSize(prog, fill, pct)
	-- Fill sits inside Progress with a small margin; full = Progress width minus that margin on both sides
	if fill.Size.X.Scale == 0 and prog.Size.X.Scale == 0 then
		local w = prog.Size.X.Offset
		local full = w - 2 * (fill.Position.X.Scale * w + fill.Position.X.Offset)
		return UDim2.new(0, math.max(0, full * pct), fill.Size.Y.Scale, fill.Size.Y.Offset)
	end
	local full = 1 - 2 * fill.Position.X.Scale
	return UDim2.new(full * pct, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
end
local function showEndQuests(e, data)
	questToken += 1
	local token = questToken
	local rt = get(e, "ResultsThing")
	local frame = get(rt, "QuestsFrame")
	local quests = data.Quests or {}
	show(frame, #quests > 0)
	show(get(rt, "Label"), #quests > 0)
	for i = 1, 3 do
		local slot = get(frame, "Quest" .. i)
		local q = quests[i]
		show(slot, q ~= nil)
		if slot and q then
			local amount, prog = get(slot, "Amount"), get(slot, "Progress")
			local fill = get(prog, "Fill")
			setText(get(slot, "Text"), q.Name)
			setText(get(slot, "CoinAmount"), tostring(q.Coins or 0))
			-- already finished before this match -> CLAIMED straight away; finished now -> after the bar fills
			local function claimed(on)
				for _, nm in {"CoinAmount", "Icon", "PassXP"} do show(get(slot, nm), not on) end
				local c = get(slot, "Claimed") -- (QuestsFrame > Quest<n> > Claimed in StarterGui)
				show(c, on)
			end
			claimed(q.From >= q.Goal)
			setText(amount, ("[%d/%d]"):format(q.From, q.Goal))
			if isText(amount) then
				if not amount:GetAttribute("DesignColor") then amount:SetAttribute("DesignColor", amount.TextColor3) end
				amount.TextColor3 = (q.From >= q.Goal) and QuestConfig.DoneColor or amount:GetAttribute("DesignColor")
			end
			if fill then
				if not fill:GetAttribute("DesignColor") then fill:SetAttribute("DesignColor", fill.BackgroundColor3) end
				fill.BackgroundColor3 = fill:GetAttribute("DesignColor")
				fill.Size = fillSize(prog, fill, q.From / math.max(q.Goal, 1))
				fill.Visible = true
			end
			-- one after the other: bar tweens from the old progress to the new one, the number counts up with it
			task.delay(0.8 + (i - 1) * 0.45, function()
				if token ~= questToken then return end
				local t = QuestConfig.BarTweenTime or 0.9
				if fill then
					TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Size = fillSize(prog, fill, q.To / math.max(q.Goal, 1))}):Play()
				end
				local t0 = os.clock()
				while os.clock() - t0 < t and token == questToken do
					local a = 1 - (1 - (os.clock() - t0) / t) ^ 2
					setText(amount, ("[%d/%d]"):format(math.floor(q.From + (q.To - q.From) * a + 0.5), q.Goal))
					task.wait()
				end
				if token ~= questToken then return end
				setText(amount, ("[%d/%d]"):format(q.To, q.Goal))
				if q.JustDone then
					SFX.Play("QuestComplete")
					setTextColor(amount, QuestConfig.DoneColor)
					claimed(true)
					pop(get(slot, "Claimed"), 1.3)
					if fill then tween(fill, 0.25, {BackgroundColor3 = QuestConfig.DoneColor}) end
					pop(amount, 1.4)
				end
			end)
		end
	end
	-- levels gained this match (match XP + quest XP) and the coins they paid
	local lv = get(rt, "LevelUpFrame")
	local from, to = data.LevelFrom or 0, data.LevelTo or 0
	show(lv, to > from)
	if lv and to > from then
		setText(get(lv, "Result"), ("%d < %d"):format(from, to))
		setText(get(lv, "CoinAmount"), tostring(data.LevelCoins or 0))
		-- a level that gives a CHEST (Matchmaking > Config > CrateForLevel): the chest's picture + name instead of coins
		local icon = get(lv, "Icon")
		if icon and icon:IsA("ImageLabel") and icon:GetAttribute("CoinImage") == nil then icon:SetAttribute("CoinImage", icon.Image) end
		local crate
		if Config.CrateForLevel then
			for l = from + 1, to do
				local c = Config.CrateForLevel(l)
				if c then crate = c end
			end
		end
		local CrateCfg = crate and require(RS:WaitForChild("Crates"):WaitForChild("CrateConfig"))
		local cc = CrateCfg and CrateCfg.ById[crate.Crate]
		if cc then
			if icon and icon:IsA("ImageLabel") then icon.Image = cc.RewardImage or icon.Image end
			setText(get(lv, "CoinAmount"), crate.Text or cc.Name)
		elseif icon and icon:IsA("ImageLabel") then
			icon.Image = icon:GetAttribute("CoinImage")
		end
	end
	show(rt, #quests > 0 or to > from)
	-- "Quests" always sits right on top of the highest quest, and "New Level!" right on top of that
	local function stack()
		if not (rt and rt.AbsoluteSize.Y > 0) then return end
		local label = get(rt, "Label")
		local top -- pixel Y of the top of the stack so far
		for i = 1, 3 do
			local slot = get(frame, "Quest" .. i)
			if slot and slot.Visible and (not top or slot.AbsolutePosition.Y < top) then top = slot.AbsolutePosition.Y end
		end
		if not top and frame then top = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y end
		if not top then return end
		local function placeAbove(obj, gap)
			if not (obj and obj:IsA("GuiObject") and obj.Visible) then return end
			local h = obj.AbsoluteSize.Y
			local y = top - gap - h -- pixel top of obj
			local rel = (y - rt.AbsolutePosition.Y + obj.AnchorPoint.Y * h) / rt.AbsoluteSize.Y
			obj.Position = UDim2.new(obj.Position.X.Scale, obj.Position.X.Offset, rel, 0)
			top = y
		end
		placeAbove(label, 2)
		placeAbove(lv, 6)
	end
	task.defer(function()
		RunService.Heartbeat:Wait() -- let the list layout place the quests first
		stack()
		if lv and to > from then pop(lv, 1.15) end
	end)
	if rt and not rt:GetAttribute("StackHooked") then
		rt:SetAttribute("StackHooked", true)
		rt:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if rt.Visible then stack() end end)
	end
end
local function stopEndCamera()
	if not endCamOn then return end
	endCamOn = false
	pcall(function() RunService:UnbindFromRenderStep(END_CAM) end)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

------------------------------------------------------------ VOTE BACKGROUND CAMERA
-- hovers over random maps (workspace > MapPreviews, built by the server) with a blur, instead of a black screen.
-- Settings: Matchmaking > Config > VotePreview
local PREVIEW_CAM = "VotePreviewCamera"
local Lighting = game:GetService("Lighting")
local previewOn = false
local previewToken = 0
local previewBlur

local function previewMaps()
	local folder = workspace:FindFirstChild("MapPreviews")
	local list = {}
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:FindFirstChildWhichIsA("BasePart", true) then table.insert(list, m) end
		end
	end
	return list
end

local function setPreviewBlur(on)
	local vp = Config.VotePreview or {}
	if not previewBlur or not previewBlur.Parent then
		previewBlur = Instance.new("BlurEffect")
		previewBlur.Name = "VoteBlur"
		previewBlur.Size = 0
		previewBlur.Parent = Lighting
	end
	tween(previewBlur, 0.4, {Size = on and (vp.Blur or 14) or 0})
end

-- one shot: slow drift around + over the map, looking at its middle
local function shotFor(model, duration, token)
	local vp = Config.VotePreview or {}
	local cf, size = model:GetBoundingBox()
	local center = cf.Position
	local radius = math.max(size.X, size.Z) * (vp.Distance or 0.75)
	local height = size.Y * (vp.Height or 0.9) + 12
	local a0 = math.random() * math.pi * 2
	local dir = math.random() < 0.5 and 1 or -1
	local sweep = math.rad(35) * dir
	local t0 = os.clock()
	local cam = workspace.CurrentCamera
	pcall(function() RunService:UnbindFromRenderStep(PREVIEW_CAM) end)
	RunService:BindToRenderStep(PREVIEW_CAM, Enum.RenderPriority.Last.Value + 4, function()
		if not previewOn or token ~= previewToken then return end
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local ang = a0 + sweep * a
		local r = radius * (1 - 0.12 * a) -- drifts in a little
		local pos = center + Vector3.new(math.cos(ang) * r, height, math.sin(ang) * r)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, size.Y * 0.1, 0))
	end)
end

local function stopPreview()
	if not previewOn then return end
	previewOn = false
	previewToken += 1
	pcall(function() RunService:UnbindFromRenderStep(PREVIEW_CAM) end)
	setPreviewBlur(false)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

-- quick dip to black between shots so the cut isn't harsh
local function dip(fn)
	local f = Fade()
	if f then show(f, true) setFade(f, 0, 0.2) task.wait(0.2) end
	fn()
	if f then setFade(f, 1, 0.25) end
end

-- starts cycling random maps (focusIndex = stay on that map, used for the vote result)
local function startPreview(focusIndex)
	local vp = Config.VotePreview
	if not (vp and vp.Enabled) then return false end
	local maps = previewMaps()
	if #maps == 0 then return false end
	previewOn = true
	previewToken += 1
	local token = previewToken
	setPreviewBlur(true)
	if focusIndex then
		local m
		for _, x in maps do if x.Name == tostring(focusIndex) then m = x end end
		if m then task.spawn(dip, function() shotFor(m, 3, token) end) end
		return true
	end
	task.spawn(function()
		local last
		local first = true
		while previewOn and token == previewToken do
			local pick = maps[math.random(1, #maps)]
			if #maps > 1 then
				local tries = 0
				while pick == last and tries < 10 do pick = maps[math.random(1, #maps)] tries += 1 end
			end
			last = pick
			if first then
				shotFor(pick, vp.ShotTime or 4, token)
				first = false
			else
				dip(function() if token == previewToken then shotFor(pick, vp.ShotTime or 4, token) end end)
			end
			task.wait((vp.ShotTime or 4) - 0.2)
		end
	end)
	return true
end

------------------------------------------------------------ NO RESETTING DURING A MATCH
local function setResetAllowed(allowed)
	for _ = 1, 20 do
		if pcall(function() StarterGui:SetCore("ResetButtonCallback", allowed) end) then return end
		task.wait(0.5)
	end
end
local function onMatchIdChanged()
	task.spawn(setResetAllowed, player:GetAttribute("MatchId") == nil)
end
player:GetAttributeChangedSignal("MatchId"):Connect(onMatchIdChanged)
onMatchIdChanged()

------------------------------------------------------------ BUTTONS (hooked whenever they exist)
local hookedReturn
local function hookButtons()
	local btn = get(EndScreen(), "ReturnButton")
	if btn and btn:IsA("GuiButton") and hookedReturn ~= btn then
		hookedReturn = btn
		btn.Activated:Connect(function()
			local r = Remotes:FindFirstChild("LeaveEndScreen")
			if r then r:FireServer() end
		end)
	end
end
hookButtons()

------------------------------------------------------------ VOTE
local cards = {}
local voterIcons = {} -- [userId] = the voter's face on a map card
local voteEndsAt = 0
local votePhase = false

local function buildVote()
	local v = Vote()
	local grid = get(v, "Grid")
	local template = v and v:FindFirstChild("CardTemplate", true) -- can live in Vote or inside Grid (for previewing)
	table.clear(cards)
	if not (grid and template) then return end
	template.Visible = false
	local voterTpl = v:FindFirstChild("VoterTemplate", true)
	if voterTpl then voterTpl.Visible = false end
	for _, icon in voterIcons do icon:Destroy() end
	table.clear(voterIcons)
	for _, c in grid:GetChildren() do if c:IsA("GuiObject") and c:GetAttribute("MapCard") then c:Destroy() end end
	for i, map in Config.Maps do
		local card = template:Clone()
		-- the preview voter face inside the design isn't a real vote
		for _, d in card:GetDescendants() do if d.Name == "VoterTemplate" then d:Destroy() end end
		card.Name = "Map" .. i
		card:SetAttribute("MapCard", true)
		card.LayoutOrder = i
		card.Visible = true
		local img = card:FindFirstChild("Image")
		if img and img:IsA("ImageLabel") then
			if map.Image and map.Image ~= "" then img.Image = map.Image end
			if map.Color and img:GetAttribute("UseMapColor") ~= false then img.BackgroundColor3 = map.Color end
		end
		setText(card:FindFirstChild("MapName"), string.upper(map.Name))
		setText(card:FindFirstChild("Count"), "")
		local hl = card:FindFirstChild("Highlight")
		if hl and hl:IsA("UIStroke") then hl.Transparency = 1 end
		local button = card:FindFirstChild("Button") or (card:IsA("GuiButton") and card)
		if button and button:IsA("GuiButton") then
			button:SetAttribute("NoClickSound", true) -- plays the Vote sound instead
			button.Activated:Connect(function(input)
				if not votePhase then return end
				-- where on the card you clicked (0-1) -> your face goes there
				-- (AbsolutePosition doesn't include the top bar; the mouse location does)
				local screen
				if input and input.UserInputType == Enum.UserInputType.Touch then
					screen = Vector2.new(input.Position.X, input.Position.Y)
				else
					screen = UIS:GetMouseLocation() - GuiService:GetGuiInset()
				end
				local rel = (screen - card.AbsolutePosition) / card.AbsoluteSize
				VoteRemote:FireServer(i, math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1))
				SFX.Play("Vote")
				for j, c in cards do
					local h = c:FindFirstChild("Highlight")
					if h and h:IsA("UIStroke") then
						h.Transparency = (j == i) and 0 or 1
						if j == i then h.Color = color("MyVoteColor") or h.Color end
					end
					show(c:FindFirstChild("Selected"), j == i)
				end
			end)
		end
		show(card:FindFirstChild("Selected"), false)
		card.Parent = grid
		cards[i] = card
	end
end

------------------------------------------------------------ MAP PICKED ANIMATION
-- losers shrink away one by one, the winner flies to the middle, grows, flashes, shines and sends out rings.
-- Tweak with attributes on MatchUI > Vote:  ResultScale (default 1.7), PickedColor (ring / outline colour)
local function clearResultCard()
	local v = Vote()
	if not v then return end
	for _, c in v:GetChildren() do if c:GetAttribute("ResultFX") then c:Destroy() end end
end

local function shrinkAway(card, delay)
	local s = card:FindFirstChild("PickScale") or Instance.new("UIScale")
	s.Name = "PickScale"
	s.Parent = card
	task.delay(delay, function()
		local tw = TweenService:Create(s, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
		tw:Play()
		tw.Completed:Connect(function() if card.Parent then card.Visible = false end end)
	end)
end

-- the pick effects' look: MatchUI > Templates > PickRing / PickFlash / PickShine (restyle there)
local function fxTemplate(name)
	local tf = gui:FindFirstChild("Templates")
	local t = tf and tf:FindFirstChild(name)
	if not t then return nil end
	local c = t:Clone()
	c.Visible = true
	return c
end
local function ring(parent, size, colr, z, delay)
	task.delay(delay, function()
		local r = fxTemplate("PickRing")
		local st
		if r then
			st = r:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			st.Color = colr
			st.Parent = r
		else
			r = Instance.new("Frame")
			r.AnchorPoint = Vector2.new(0.5, 0.5)
			r.Position = UDim2.fromScale(0.5, 0.5)
			r.BackgroundTransparency = 1
			local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 14) c.Parent = r
			st = Instance.new("UIStroke") st.Color = colr st.Thickness = 6 st.Parent = r
		end
		r.Name = "PickRing"
		r:SetAttribute("ResultFX", true)
		r.Size = UDim2.fromOffset(size.X, size.Y)
		r.ZIndex = z
		r.Parent = parent
		local ti = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(r, ti, {Size = UDim2.fromOffset(size.X * 1.6, size.Y * 1.9)}):Play()
		TweenService:Create(st, ti, {Transparency = 1, Thickness = 1}):Play()
		task.delay(0.75, function() r:Destroy() end)
	end)
end

local function playPickAnimation(mapIndex)
	local v = Vote()
	if not v then return end
	SFX.Play("MapPicked")
	clearResultCard()
	local winner = cards[mapIndex]
	local pickColor = v:GetAttribute("PickedColor") or color("ChosenMapColor") or Color3.fromRGB(60, 255, 130)
	-- 1) the other maps shrink away, one after another
	local n = 0
	for i, card in cards do
		if i ~= mapIndex then
			shrinkAway(card, n * 0.045)
			n += 1
		end
	end
	if not winner then return end
	-- 2) a floating copy of the winner (so the grid layout can't hold it in place)
	local absPos, absSize = winner.AbsolutePosition, winner.AbsoluteSize
	local vPos = v.AbsolutePosition
	local fly = winner:Clone()
	fly.Name = "PickedCard"
	fly:SetAttribute("ResultFX", true)
	fly:SetAttribute("MapCard", nil)
	fly.AnchorPoint = Vector2.new(0.5, 0.5)
	fly.Size = UDim2.fromOffset(absSize.X, absSize.Y)
	fly.Position = UDim2.fromOffset(absPos.X - vPos.X + absSize.X / 2, absPos.Y - vPos.Y + absSize.Y / 2)
	fly.ZIndex = 50
	fly.ClipsDescendants = true
	for _, d in fly:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = 50 + math.max(d.ZIndex, 1) end
		if d:IsA("UIAspectRatioConstraint") or d:IsA("UISizeConstraint") then d:Destroy() end
	end
	local hl = fly:FindFirstChild("Highlight")
	if hl and hl:IsA("UIStroke") then
		hl.Transparency = 0
		hl.Color = pickColor
		-- (a "Scaled" stroke's thickness is a fraction of the card, not pixels: 3 = three cards wide = the white screen)
		if hl.StrokeSizingMode ~= Enum.StrokeSizingMode.ScaledSize then hl.Thickness = math.max(hl.Thickness, 3) end
	end
	show(fly:FindFirstChild("Selected"), true)
	local scale = Instance.new("UIScale")
	scale.Parent = fly
	fly.Parent = v
	winner.Visible = false
	-- 3) fly to the middle and grow (with a bounce)
	local big = v:GetAttribute("ResultScale") or 1.7
	task.delay(0.3, function()
		if not fly.Parent then return end
		TweenService:Create(fly, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5, 0.52)}):Play()
		TweenService:Create(scale, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = big}):Play()
	end)
	-- 4) landing: flash + shine sweep + rings
	task.delay(0.9, function()
		if not fly.Parent then return end
		local flash = fxTemplate("PickFlash")
		if not flash then
			flash = Instance.new("Frame")
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
			flash.BackgroundTransparency = 0.1
		end
		flash.Name = "PickFlash"
		flash.ZIndex = 200
		local fc = fly:FindFirstChildOfClass("UICorner")
		if fc and not flash:FindFirstChildOfClass("UICorner") then fc:Clone().Parent = flash end
		flash.Parent = fly
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()

		-- a full-card overlay whose gradient slides across (stays inside the card's rounded shape)
		local shine = fxTemplate("PickShine")
		local g = shine and shine:FindFirstChildOfClass("UIGradient")
		if not (shine and g) then
			shine = Instance.new("Frame")
			shine.Size = UDim2.fromScale(1, 1)
			shine.BackgroundColor3 = Color3.new(1, 1, 1)
			shine.BackgroundTransparency = 0
			g = Instance.new("UIGradient")
			g.Rotation = 20
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.5, 0.4),
				NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = shine
		end
		shine.Name = "PickShine"
		shine.ZIndex = 201
		g.Offset = Vector2.new(-1, 0)
		if fc and not shine:FindFirstChildOfClass("UICorner") then fc:Clone().Parent = shine end
		shine.Parent = fly
		TweenService:Create(g, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Offset = Vector2.new(1, 0)}):Play()

		local ringSize = absSize * big
		local holder = Instance.new("Frame")
		holder.Name = "PickRings"
		holder:SetAttribute("ResultFX", true)
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.52)
		holder.Size = UDim2.fromOffset(ringSize.X, ringSize.Y)
		holder.ZIndex = 49
		holder.Parent = v
		ring(holder, ringSize, pickColor, 49, 0)
		ring(holder, ringSize, Color3.new(1, 1, 1), 49, 0.15)
		-- little settle pulse
		local t1 = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Scale = big * 1.06})
		t1:Play()
		t1.Completed:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Scale = big}):Play()
		end)
	end)
end

-- VOTER FACES: each voter's face sits where they clicked on the card and slides to the new spot when they click again.
-- Look = VoterTemplate. Its size on the card = ClickSize attribute on VoterTemplate (fraction of the card's height, default 0.24).
local function updateVotes(votes)
	local v = Vote()
	local template = v and v:FindFirstChild("VoterTemplate", true)
	local counts = {}
	local seen = {}
	for n, vote in votes do
		local card = cards[vote.Map]
		if card then
			counts[vote.Map] = (counts[vote.Map] or 0) + 1
			seen[vote.UserId] = true
			local free = vote.X ~= nil and vote.Y ~= nil -- placed where they clicked
			local parent = free and card or card:FindFirstChild("Voters")
			local icon = voterIcons[vote.UserId]
			if icon and not icon.Parent then icon = nil end
			if not icon and template and parent then
				icon = template:Clone()
				icon.Name = tostring(vote.UserId)
				icon:SetAttribute("Voter", true)
				local img = icon:IsA("ImageLabel") and icon or icon:FindFirstChildWhichIsA("ImageLabel", true)
				if img then img.Image = headshot(vote.UserId) end
				icon.Visible = true
				if vote.UserId == player.UserId then
					local s = icon:FindFirstChildOfClass("UIStroke")
					if s then s.Color = color("MyVoteColor") or s.Color end
				end
				voterIcons[vote.UserId] = icon
			end
			if icon and parent then
				icon.LayoutOrder = n
				if free then
					local target = UDim2.fromScale(vote.X, vote.Y)
					local k = template:GetAttribute("ClickSize") or 0.24
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Size = UDim2.fromScale(k, k)
					icon:SetAttribute("DesignSize", icon.Size)
					if not icon:FindFirstChild("ClickAspect") then
						local a = Instance.new("UIAspectRatioConstraint")
						a.Name = "ClickAspect"
						a.AspectRatio = 1
						a.DominantAxis = Enum.DominantAxis.Height
						a.Parent = icon
					end
					icon.ZIndex = math.max(icon.ZIndex, 26)
					if icon.Parent == card then
						-- same card: slide to the new spot
						if icon.Position ~= target then tween(icon, 0.2, {Position = target}) end
					else
						icon.Position = target
						icon.Parent = card
						pop(icon, 0.01)
					end
				elseif icon.Parent ~= parent then
					icon.Parent = parent
					pop(icon, 0.01)
				end
			end
		end
	end
	-- remove faces of voters that aren't in the list any more
	for uid, icon in voterIcons do
		if not seen[uid] then icon:Destroy() voterIcons[uid] = nil end
	end
	for i, card in cards do
		setText(card:FindFirstChild("Count"), counts[i] and tostring(counts[i]) or "")
	end
end

local lastVoteSecond
task.spawn(function()
	while true do
		task.wait(0.1)
		if votePhase then
			local secs = math.max(0, math.ceil(voteEndsAt - workspace:GetServerTimeNow()))
			setText(get(Vote(), "Timer"), tostring(secs))
			-- clock tick every second; the last few seconds tick harder
			if lastVoteSecond and secs ~= lastVoteSecond and secs > 0 then
				SFX.Tick(secs)
			end
			lastVoteSecond = secs
		else
			lastVoteSecond = nil
		end
	end
end)

------------------------------------------------------------ SCOREBOARD
local scoreCards = {} -- [userId] = card

-- CHAT BUBBLES UNDER THE SCORE CARDS: whatever a player types in chat pops up under their card for a few seconds.
-- Look: HUD > ScoreCardTemplate > ChatBubbles (BubbleTemplate = one message; attributes ShowTime (7), MaxBubbles (4),
-- TextSizeScale = text size as a part of the card's height, MaxChars).
do
	local TCS = game:GetService("TextChatService")
	TCS.MessageReceived:Connect(function(msg)
		local src = msg.TextSource
		if not src or player:GetAttribute("MatchId") == nil then return end
		local card = scoreCards[src.UserId]
		local holder = card and card.Parent and card:FindFirstChild("ChatBubbles")
		local tpl = holder and holder:FindFirstChild("BubbleTemplate")
		if not tpl then return end
		local text = tostring(msg.Text or "")
		text = text:gsub("<[^>]->", "") -- (no rich-text tags)
		if text == "" then return end
		local maxC = holder:GetAttribute("MaxChars") or 40
		if utf8.len(text) and utf8.len(text) > maxC then text = text:sub(1, utf8.offset(text, maxC + 1) - 1) .. "..." end
		local b = tpl:Clone()
		b.Name = "Bubble"
		b.Text = text
		b.TextSize = math.max(8, math.floor(card.AbsoluteSize.Y * (holder:GetAttribute("TextSizeScale") or 0.16)))
		b.Visible = true
		local n = (holder:GetAttribute("Count") or 0) + 1
		holder:SetAttribute("Count", n)
		b.LayoutOrder = n
		b.Parent = holder
		local sc = Instance.new("UIScale") sc.Scale = 0.3 sc.Parent = b
		TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		-- too many: the oldest goes
		local bubbles = {}
		for _, c in holder:GetChildren() do if c.Name == "Bubble" then table.insert(bubbles, c) end end
		table.sort(bubbles, function(a, c2) return a.LayoutOrder < c2.LayoutOrder end)
		for i = 1, #bubbles - (holder:GetAttribute("MaxBubbles") or 4) do bubbles[i]:Destroy() end
		task.delay(holder:GetAttribute("ShowTime") or 7, function()
			if not b.Parent then return end
			local tw = TweenService:Create(b, TweenInfo.new(0.3), {BackgroundTransparency = 1, TextTransparency = 1})
			tw:Play()
			tw.Completed:Wait()
			b:Destroy()
		end)
	end)
end

local function buildHUD(teams)
	table.clear(scoreCards)
	local hud = HUD()
	local template = get(hud, "ScoreCardTemplate")
	if not template then return end
	for side, team in {teams[myTeam()], teams[otherTeam()]} do
		local holder = get(hud, side == 1 and "Team1" or "Team2")
		if holder then
			for _, c in holder:GetChildren() do if c:GetAttribute("ScoreCard") then c:Destroy() end end
			for i, info in team do
				local c = template:Clone()
				c.Name = tostring(info.UserId)
				c:SetAttribute("ScoreCard", true)
				c.Visible = true
				c.LayoutOrder = side == 1 and -i or i
				local teamColor = color(side == 1 and "MyTeamColor" or "EnemyTeamColor")
				local bar = c:FindFirstChild("Bar")
				if bar and bar:IsA("GuiObject") and teamColor then bar.BackgroundColor3 = teamColor end
				local stroke = c:FindFirstChild("TeamStroke")
				if stroke and stroke:IsA("UIStroke") and teamColor then stroke.Color = teamColor end
				local tile = c:FindFirstChild("Tile")
				if tile then PlayerCard.Fill(tile, info) end
				local img = c:FindFirstChild("Headshot")
				if img and img:IsA("ImageLabel") then img.Image = headshot(info.UserId) end
				setText(c:FindFirstChild("PlayerName"), info.Name)
				setText(c:FindFirstChild("Level"), tostring(info.Level or 1))
				show(c:FindFirstChild("Dead"), false)
				-- LEFT THE MATCH (ScoreCardTemplate > Left: dark overlay + disconnect icon, like the skull)
				-- (bots are never "in the server" as players - they don't leave)
				local gone = not info.Bot and Players:GetPlayerByUserId(info.UserId) == nil
				show(c:FindFirstChild("Left"), gone)
				if gone then show(c:FindFirstChild("Dead"), false) end
				c.Parent = holder
				scoreCards[info.UserId] = c
			end
		end
	end
end

local function setScores(scores)
	local s = get(HUD(), "Score")
	-- clear leftovers of an interrupted score roll (a stray old digit could show a wrong score)
	if s then
		for _, d in s:GetDescendants() do
			if d:GetAttribute("RollNext") then d:Destroy() end
		end
		for _, n in {"Score1", "Score2"} do
			local l = get(s, n)
			local home = l and l:GetAttribute("DesignPosition")
			if home then l.Position = home end
		end
	end
	setText(get(s, "Score1"), tostring(scores[myTeam()] or 0))
	setText(get(s, "Score2"), tostring(scores[otherTeam()] or 0))
end

------------------------------------------------------------ SPECTATING
local specToken = 0
local currentSpec -- the player being watched
-- true from the moment you die mid-round (while a teammate is still alive) until the server puts you in
-- the spectator box - so the camera goes straight to your teammate instead of following your new
-- character around for a second
local earlySpectate = false
local deathPos -- where you died (no teammate left: the camera goes to the enemy nearest to it = usually your killer)
local function isFFA() return player:GetAttribute("FFA") == true or workspace:GetAttribute("FFA") == true end
local function spectatingNow()
	-- (death camera on = never cut to another player: you stay looking round your own body)
	if Config.DeathCam ~= false and player:GetAttribute("DeathCam") then return false end
	return player:GetAttribute("Spectating") == true or earlySpectate
end
-- FIRST PERSON through the watched player's eyes (like the lobby spectate): their view (AimLook, sent 30x a second),
-- their arms + balloon + crosshair (BalloonCombatClient via ClientActions)
local SpecActions = RS:WaitForChild("BalloonCombat"):WaitForChild("ClientActions")
local fpWho, fpLook
local deathFrozen = false -- (the camera held still where you died: YOU DIED below)
-- (the server sends the watched player's damage numbers to you - Remotes > SpectatingWho)
local SpectatingWho = Remotes:WaitForChild("SpectatingWho", 10)
-- SEEN THROUGH THEIR EYES: everyone else drawn where the WATCHED player saw them (their ping + ~0.1s earlier), like
-- the lobby spectate / replays - otherwise their crosshair looks off what they're aiming at
local seenHist, seenSet = {}, {}
local function seenClear()
	for p, h in seenHist do
		local c = p.Character
		if c and c.Parent and h[#h] and seenSet[p] then pcall(function() c:PivotTo(h[#h].cf) end) end
	end
	table.clear(seenHist) table.clear(seenSet)
end
local function seenStep(who)
	local now = os.clock()
	local delay = math.clamp((tonumber(who:GetAttribute("Ping")) or 0) / 1000 + 0.1, 0, 0.6)
	for _, p in Players:GetPlayers() do
		local c = p ~= who and p ~= player and p:GetAttribute("MatchId") == player:GetAttribute("MatchId") and p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if c and c.Parent and hum and hum.Health > 0 then
			local cur = c:GetPivot()
			local h = seenHist[p] if not h then h = {} seenHist[p] = h end
			if not seenSet[p] or cur ~= seenSet[p] then
				table.insert(h, {t = now, cf = cur})
				while #h > 2 and now - h[2].t > 1 do table.remove(h, 1) end
			end
			local at, cf = now - delay, h[1].cf
			for i = #h, 1, -1 do
				if h[i].t <= at then
					local a, b = h[i], h[i + 1]
					cf = b and a.cf:Lerp(b.cf, math.clamp((at - a.t) / math.max(b.t - a.t, 1e-3), 0, 1)) or a.cf
					break
				end
			end
			if (cf.Position - cur.Position).Magnitude > 40 then cf = cur table.clear(h) table.insert(h, {t = now, cf = cur}) end
			c:PivotTo(cf)
			seenSet[p] = c:GetPivot()
		else
			seenHist[p], seenSet[p] = nil, nil
		end
	end
end
-- BOTS (ServerStorage > Bots) can be watched too: they're the bot's body Model (in workspace > Bots), not a Player
local function charOf(x) if x:IsA("Player") then return x.Character end return x end
local function whoName(x) if x:IsA("Player") then return NameBadge.Of(x) end return x:GetAttribute("BotName") or x.Name end
local function matchPeople()
	local list = Players:GetPlayers()
	local bf = workspace:FindFirstChild("Bots")
	for _, m in bf and bf:GetChildren() or {} do
		if m:GetAttribute("MatchId") ~= nil and m:GetAttribute("MatchId") == player:GetAttribute("MatchId") then table.insert(list, m) end
	end
	return list
end
local function fpWatch(p)
	if fpWho == p then return end
	if not fpWho then SpecActions:Fire("SpectateStart") end
	fpWho = p
	if SpectatingWho then SpectatingWho:FireServer(p:IsA("Player") and p.UserId or nil) end
	seenClear()
	local l = p:GetAttribute("AimLook")
	local head = charOf(p) and charOf(p):FindFirstChild("Head")
	fpLook = typeof(l) == "Vector3" and l or (head and head.CFrame.LookVector) or Vector3.new(0, 0, -1)
	SpecActions:Fire("SpectateTarget", p:IsA("Player") and p.UserId or p)
	RunService:UnbindFromRenderStep("MatchSpectateCam")
	RunService:BindToRenderStep("MatchSpectateCam", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local who = fpWho
		local h = who and charOf(who) and charOf(who):FindFirstChild("Head")
		if not h then return end
		local cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
		local want = who:GetAttribute("AimLook")
		if typeof(want) ~= "Vector3" then want = h.CFrame.LookVector end
		fpLook = fpLook:Lerp(want, math.min(1, dt * 26))
		if fpLook.Magnitude < 0.1 then fpLook = want end
		local eye = h.Position + Vector3.new(0, 0.1, 0)
		cam.CFrame = CFrame.lookAt(eye, eye + fpLook.Unit)
		-- their crosshair on screen (like the lobby spectate)
		local ui = player.PlayerGui:FindFirstChild("BalloonCombatUI")
		local ch = ui and ui:FindFirstChild("Crosshair")
		if ch and ch:IsA("GuiObject") and not ch.Visible then ch.Visible = true end
		if ui and ui:IsA("ScreenGui") and not ui.Enabled then ui.Enabled = true end
		-- (off unless MatchUI attribute SeenDelay = true: players who stop updating were left drawn at an old spot)
		if gui:GetAttribute("SeenDelay") == true then pcall(seenStep, who) end
	end)
end
local function fpStop()
	if not fpWho then return end
	deathFrozen = false
	fpWho = nil
	RunService:UnbindFromRenderStep("MatchSpectateCam")
	seenClear()
	if SpectatingWho then SpectatingWho:FireServer(nil) end
	SpecActions:Fire("SpectateEnd")
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end
local function updateSpectate()
	specToken += 1
	local token = specToken
	local cam = workspace.CurrentCamera
	local label = get(Center(), "Spectating")
	if not spectatingNow() then
		show(label, false)
		-- (death camera: leave the camera on your body)
		if player:GetAttribute("DeathCam") then return end
		fpStop()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		return
	end
	task.spawn(function()
		while token == specToken do
			-- WHO TO WATCH: a teammate who's still alive first; none left (1v1, last of your team, FFA) = the enemy
			-- nearest to where you died (your killer, most of the time)
			local target, mate, enemy, enemyDist
			local ffa = isFFA()
			for _, p in matchPeople() do
				if p ~= player and p:GetAttribute("MatchId") == player:GetAttribute("MatchId") and not p:GetAttribute("Spectating") and not p:GetAttribute("MatchDead") then
					local h = charOf(p) and charOf(p):FindFirstChildOfClass("Humanoid")
					local r = charOf(p) and charOf(p):FindFirstChild("HumanoidRootPart")
					if h and h.Health > 0 then
						if not ffa and p:GetAttribute("MatchTeam") == myTeam() then
							if not mate then mate = {p = p, h = h} end
						else
							local d = (deathPos and r) and (r.Position - deathPos).Magnitude or 0
							if not enemy or d < enemyDist then enemy, enemyDist = {p = p, h = h}, d end
						end
					end
				end
			end
			-- (keep watching the same person while they're alive, so it doesn't flick between enemies)
			local cur = currentSpec
			local curH = cur and cur.Parent and charOf(cur) and charOf(cur):FindFirstChildOfClass("Humanoid")
			if cur and curH and curH.Health > 0 and not cur:GetAttribute("MatchDead") and (not mate or (not ffa and cur:GetAttribute("MatchTeam") == myTeam())) then
				target = {p = cur, h = curH}
			else
				target = mate or enemy
			end
			currentSpec = target and target.p
			if target then
				fpWatch(target.p)
				label = get(Center(), "Spectating")
				setText(label, "SPECTATING " .. string.upper(whoName(target.p)))
				show(label, true)
			end
			-- re-pick the target every 0.25s (someone who dies is swapped straight away)
			local t0 = os.clock()
			while token == specToken and os.clock() - t0 < 0.25 do
				if target and (not target.h.Parent or target.h.Health <= 0) then break end
				RunService.RenderStepped:Wait()
			end
		end
	end)
end
player:GetAttributeChangedSignal("Spectating"):Connect(function()
	if not player:GetAttribute("Spectating") then earlySpectate = false end
	updateSpectate()
end)
player:GetAttributeChangedSignal("MatchId"):Connect(function()
	if player:GetAttribute("MatchId") == nil and earlySpectate then earlySpectate = false updateSpectate() end
end)
-- YOU DIED: the camera cuts to someone still fighting - a teammate if one's alive, else the enemy (your killer).
-- In FFA you watch your killer until you respawn. (Matchmaking > Config > SpectateAfterDeath = how long first)
local function stopEarlySpectate()
	if not earlySpectate then return end
	earlySpectate = false
	currentSpec = nil
	updateSpectate()
end
-- HOLD THE CAMERA BETWEEN ROUNDS: after a round ends the server moves your (new) character away from the map, and the
-- camera used to follow it up into the sky for a few seconds before the round result. Now it stays put from the end of
-- the round until the next one starts.
local camHeld, betweenRounds = false, false
local function holdCam()
	if camHeld then return end
	camHeld = true
	local cam = workspace.CurrentCamera
	local cf = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	RunService:UnbindFromRenderStep("MatchHoldCam")
	RunService:BindToRenderStep("MatchHoldCam", Enum.RenderPriority.Last.Value + 3, function()
		-- (something else hands the camera back mid-hold - e.g. the kill replay ending: back to where it was held)
		if camHeld and cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable cam.CFrame = cf end
	end)
end
local function releaseCam()
	betweenRounds = false
	if not camHeld then return end
	camHeld = false
	RunService:UnbindFromRenderStep("MatchHoldCam")
	local cam = workspace.CurrentCamera
	if fpWho then return end
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

-- DEATH CAMERA (Matchmaking > Config > DeathCam, default on): when you die the camera drops to third person round your
-- body lying on the ground and you can turn it round / zoom (instead of cutting straight to spectating). Your respawn
-- takes it back. DeathCam = false = the old way (held still where your eyes were, then spectating).
local function freezeDeathCam()
	local cam = workspace.CurrentCamera
	if fpWho or camHeld or cam.CameraType == Enum.CameraType.Scriptable then return end
	deathFrozen = true
	local char = player.Character
	local focus = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if Config.DeathCam ~= false and focus then
		-- (BalloonCombatClient sees DeathCam: third person, no first-person arms, mouse free to turn the camera)
		player:SetAttribute("DeathCam", true)
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = math.max(player.CameraMaxZoomDistance, 20)
		player.CameraMinZoomDistance = Config.DeathCamZoom or 8
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = focus
		task.delay(0.2, function() if player:GetAttribute("DeathCam") then player.CameraMinZoomDistance = 2 end end)
		return
	end
	local cf = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
end
local function unfreezeDeathCam()
	if player:GetAttribute("DeathCam") then player:SetAttribute("DeathCam", nil) end
	if not deathFrozen then return end
	deathFrozen = false
	if fpWho or camHeld then return end
	local cam = workspace.CurrentCamera
	if cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Custom end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end
local function watchDeath(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end
	hum.Died:Connect(function()
		if char ~= player.Character then return end
		if player:GetAttribute("MatchId") ~= nil or player:GetAttribute("InArena") or isFFA() then freezeDeathCam() end
	end)
	-- (several triggers - Died alone was missed sometimes after a few rounds; each life only counts once)
	local handled = false
	local function onDeath()
		if handled or char ~= player.Character then return end
		if player:GetAttribute("MatchId") == nil or player:GetAttribute("WatchingReplay") then return end
		handled = true
		-- start clean (a leftover watch from an earlier round never blocks this one)
		if earlySpectate then earlySpectate = false end
		fpStop()
		local r = char:FindFirstChild("HumanoidRootPart")
		deathPos = r and r.Position or nil
		currentSpec = nil
		-- (death camera on: you stay round your body - no cutting to spectating. Started from here too: Died alone
		--  doesn't always reach this screen when the server does the kill)
		if Config.DeathCam ~= false then freezeDeathCam() return end
		for _, p in matchPeople() do
			if p ~= player and p:GetAttribute("MatchId") == player:GetAttribute("MatchId") and not p:GetAttribute("MatchDead") then
				local h = charOf(p) and charOf(p):FindFirstChildOfClass("Humanoid")
				if h and h.Health > 0 then
					task.delay(Config.SpectateAfterDeath or 0.1, function()
						if player:GetAttribute("MatchId") ~= nil and not player:GetAttribute("MatchEnded") and hum.Health <= 0 then
							earlySpectate = true
							updateSpectate()
						end
					end)
					return
				end
			end
		end
	end
	hum.Died:Connect(onDeath)
	hum.HealthChanged:Connect(function(h) if h <= 0 then onDeath() end end)
	local c = player:GetAttributeChangedSignal("MatchDead"):Connect(function()
		if player:GetAttribute("MatchDead") and hum.Health <= 0 then onDeath() end
	end)
	char.AncestryChanged:Connect(function() if not char.Parent then c:Disconnect() end end)
end
if player.Character then task.spawn(watchDeath, player.Character) end
player.CharacterAdded:Connect(function(char)
	-- FFA: respawned = back in the fight, stop watching your killer
	if isFFA() then task.delay(0.1, stopEarlySpectate) end
	task.spawn(watchDeath, char)
	-- between rounds: the server just moved you off the map - the camera stays where it was (no trip to the sky)
	if betweenRounds then holdCam() end
	-- (the death camera hands back to you - unless you're spectating someone)
	task.defer(function() if not spectatingNow() then unfreezeDeathCam() else deathFrozen = false if player:GetAttribute("DeathCam") then player:SetAttribute("DeathCam", nil) end end end)
	task.wait(0.1)
	if not spectatingNow() then updateSpectate() end
end)

------------------------------------------------------------ EVENTS
local handlers = {}
local startRoundResult, endRoundResult -- defined further down (ROUND RESULT)
local highlightEnemies -- defined further down (COUNTDOWN ENEMY HIGHLIGHT)
local roundToken = 0
local matchTeams -- {[team] = {info, ...}} from MatchStart

function handlers.Intro()
	SFX.Play("MatchFound")
	hideAll()
	hookButtons()
	local f = Fade()
	if f then setFade(f, 1) end
	showLogo(false)
	fadeToBlack()
	showLogo(true)
end

function handlers.VoteStart(data)
	SFX.Play("VoteOpen")
	player:SetAttribute("InVote", true) -- (MusicClient plays SoundService > VoteMusic while this is on)
	clearResultCard()
	reveal(Vote())
	buildVote()
	voteEndsAt = data.EndsAt
	votePhase = true
	local v = Vote()
	setText(get(v, "Title"), "VOTE FOR A MAP")
	showLogo(false)
	local f = Fade()
	if startPreview() then
		-- maps in the background: lift the black screen
		if f then show(f, true) setFade(f, 1, 0.4) end
	else
		if f then show(f, true) setFade(f, 0) end
	end
	show(v, true)
end

function handlers.VoteUpdate(data)
	updateVotes(data.Votes)
	if data.AllVoted then
		votePhase = false -- freeze the timer
		setText(get(Vote(), "Timer"), "ALL VOTED")
	end
end

function handlers.VoteResult(data)
	votePhase = false
	-- the vote music fades out with the screen
	task.delay(math.max((Config.VoteResultTime or 3.5) - Config.FadeTime, 0), function() if not votePhase then player:SetAttribute("InVote", nil) end end)
	-- camera goes to the winning map, then fades to black before the match loads
	if previewOn then
		previewToken += 1
		startPreview(data.Map)
	end
	-- always fade to black at the end of the pick (with or without the preview camera), and only THEN let the
	-- camera go back to the character - otherwise the empty sky at the holding spot flashes white
	task.delay((Config.VoteResultTime or 3.5) - Config.FadeTime - 0.1, function()
		if votePhase then return end -- a new vote started meanwhile
		fadeToBlack()
		stopPreview()
	end)
	local map = Config.Maps[data.Map]
	local v = Vote()
	setText(get(v, "Title"), string.upper(map and map.Name or "?"))
	setText(get(v, "Timer"), data.Tied and "TIE - PICKED AT RANDOM" or "")
	playPickAnimation(data.Map)
end

function handlers.MatchStart(data)
	SFX.Play("MatchStart")
	matchTeams = data.Teams
	stopPreview()
	show(Vote(), false)
	reveal(HUD())
	local ok, err = pcall(buildHUD, data.Teams)
	if not ok then warn("[MatchUI] scoreboard: " .. tostring(err)) end
	setScores({0, 0})
	show(HUD(), true)
	matchLayout(true)
	setText(get(Center(), "Subtitle"), (data.PointsToWin == 1 and "FIRST TO 1 POINT" or ("FIRST TO %d POINTS"):format(data.PointsToWin)))
	fadeFromBlack()
end

function handlers.Face(data)
	-- placed for a new round: stop the early spectate camera
	if earlySpectate then earlySpectate = false updateSpectate() end
	-- spawned facing the enemy: turn the first-person camera to match (a few frames so camera scripts don't undo it)
	-- also snap our own character onto the spawn (in case our computer still thinks we're where we were last round)
	if typeof(data.CFrame) == "CFrame" then
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		-- (only while the body is still ours to move - once the server holds it in place, moving it here would just
		-- jump our own view back and forth against the server's spot)
		if c and root and not root.Anchored and (c:GetPivot().Position - data.CFrame.Position).Magnitude > 4 then pcall(function() c:PivotTo(data.CFrame) end) end
	end
	local look = data.Look
	if typeof(look) ~= "Vector3" then return end
	for _ = 1, 6 do
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head then
			local cam = workspace.CurrentCamera
			cam.CFrame = CFrame.lookAt(head.Position, head.Position + look)
		end
		task.wait()
	end
end

-- COUNTDOWN BLUR: the world blurs during the 3-2-1 before each round (strength = CountdownBlur attribute on MatchUI > Center, 0 = off)
local countdownBlur
local function setCountdownBlur(on)
	if not countdownBlur or not countdownBlur.Parent then
		countdownBlur = Instance.new("BlurEffect")
		countdownBlur.Name = "CountdownBlur"
		countdownBlur.Size = 0
		countdownBlur.Parent = Lighting
	end
	local c = Center()
	local size = c and c:GetAttribute("CountdownBlur")
	if size == nil then size = 16 end
	tween(countdownBlur, 0.25, {Size = on and size or 0})
	-- dark layer (MatchUI > CountdownDim, same look as the profile's): its BackgroundTransparency in Studio = how dark
	local dim = gui:FindFirstChild("CountdownDim")
	if dim and dim:IsA("GuiObject") then
		local target = dim:GetAttribute("DesignTransparency")
		if target == nil then target = dim.BackgroundTransparency dim:SetAttribute("DesignTransparency", target) end
		local t = dim:GetAttribute("FadeTime") or 0.25
		if on then
			if not dim.Visible then dim.BackgroundTransparency = 1 end
			dim.Visible = true
			tween(dim, t, {BackgroundTransparency = target})
		elseif dim.Visible then
			local tw = tween(dim, t, {BackgroundTransparency = 1})
			task.delay(t, function()
				if dim.BackgroundTransparency > 0.99 then dim.Visible = false end
			end)
		end
	end
end

-- HEARTBEAT: on every countdown number the dark layer + blur thump twice (lub-dub), subtle.
-- Strength = HeartbeatStrength attribute on MatchUI > CountdownDim (0 = off, default 0.12)
local function heartbeat(token)
	local dim = gui:FindFirstChild("CountdownDim")
	local base = dim and dim:GetAttribute("DesignTransparency")
	local k = dim and dim:GetAttribute("HeartbeatStrength")
	if k == nil then k = 0.12 end
	if not (dim and base) or k <= 0 then return end
	local c = Center()
	local blurBase = (c and c:GetAttribute("CountdownBlur")) or 16
	local function beat(amount)
		if token ~= roundToken then return end
		if amount == k then SFX.Play("Heartbeat") end -- one heartbeat sound per lub-dub
		TweenService:Create(dim, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = math.max(0, base - amount)}):Play()
		if countdownBlur then TweenService:Create(countdownBlur, TweenInfo.new(0.07), {Size = blurBase + amount * 40}):Play() end
		task.wait(0.08)
		if token ~= roundToken then return end
		TweenService:Create(dim, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = base}):Play()
		if countdownBlur then TweenService:Create(countdownBlur, TweenInfo.new(0.2), {Size = blurBase}):Play() end
	end
	task.spawn(function()
		beat(k)         -- lub
		task.wait(0.1)
		beat(k * 0.55)  -- dub (softer)
	end)
end

function handlers.RoundStart(data)
	stopEarlySpectate() -- (new round: back to your own eyes)
	releaseCam()
	roundToken += 1
	local token = roundToken
	setCountdownBlur(true)
	highlightEnemies(true)
	SFX.Play("EnemyHighlight")
	-- safety: never leave the black screen up once the fight is on
	local f = Fade()
	if f and f.Visible and getFade(f) < 1 then fadeFromBlack() end
	for _, c in scoreCards do show(c:FindFirstChild("Dead"), false) end
	setScores(data.Scores)
	local center = Center()
	endRoundResult(false)
	show(get(center, "Banner"), false)
	show(get(center, "BannerSub"), false)
	local sub = get(center, "Subtitle")
	setText(sub, (data.PointsToWin == 1 and "FIRST TO 1 POINT" or ("FIRST TO %d POINTS"):format(data.PointsToWin)))
	show(sub, true)
	local cd = get(center, "Countdown")
	for n = data.Countdown, 1, -1 do
		if token ~= roundToken then return end
		setText(cd, tostring(n))
		show(cd, true)
		pop(cd, 1.4)
		SFX.Play("CountdownTick")
		-- (first beat waits for the fade-in to finish)
		task.delay(n == data.Countdown and 0.3 or 0, heartbeat, token)
		task.wait(1)
	end
end

function handlers.Fight()
	setCountdownBlur(false)
	highlightEnemies(false)
	roundToken += 1
	local token = roundToken
	local center = Center()
	local cd = get(center, "Countdown")
	setText(cd, "FIGHT!")
	SFX.Play("Fight")
	show(cd, true)
	pop(cd, 1.2)
	task.delay(0.7, function()
		if token ~= roundToken then return end
		show(cd, false)
		show(get(center, "Subtitle"), false)
	end)
end

function handlers.PlayerDied(data)
	SFX.Play("PlayerDied")
	local c = scoreCards[data.UserId]
	-- (someone who left keeps the Left icon, not the skull)
	if c and not (c:FindFirstChild("Left") and c.Left.Visible) then show(c:FindFirstChild("Dead"), true) end
end
-- someone in your match left / disconnected: their card shows the Left icon for the rest of the match
Players.PlayerRemoving:Connect(function(p)
	local c = scoreCards[p.UserId]
	if not c then return end
	show(c:FindFirstChild("Dead"), false)
	show(c:FindFirstChild("Left"), true)
end)

-- ROUND RESULT (uses the old design): 1s after the round-winning kill the kill popup closes, everything else hides,
-- the world blurs, Banner / BannerSub show above the top scoreboard (HUD) which slides to the middle,
-- and the team that scored rolls its number up like a clock. All of it goes back when the next round starts.
-- Tweak with attributes on MatchUI > Center: ResultHudY, ResultHudScale, ResultBannerY, ResultSubY, ResultBlur
-- and Matchmaking > Config > RoundResultDelay.

-- the score label itself rolls: the old number slides up and out, the new one slides in from below
local function rollDigit(label, from, to, delay)
	if not isText(label) then return end
	local holder = label.Parent
	-- only clear THIS label's leftover roll (both scores share the same holder)
	for _, c in holder:GetChildren() do if c:GetAttribute("RollNext") == label.Name then c:Destroy() end end
	local home = label:GetAttribute("DesignPosition")
	if not home then home = label.Position label:SetAttribute("DesignPosition", home) end
	label.Position = home
	label.Text = tostring(from)
	if from == to then return end
	task.delay(delay or 0, function() SFX.Play("ScoreTick") end)
	if holder:IsA("GuiObject") then holder.ClipsDescendants = true end
	local nxt = label:Clone()
	nxt:SetAttribute("RollNext", label.Name)
	nxt.Text = tostring(to)
	nxt.Position = home + UDim2.fromScale(0, 1)
	nxt.Parent = holder
	task.delay((delay or 0) + 1, function()
		-- safety net: whatever happened to the tween, end on the right number, in the right place
		if nxt.Parent then nxt:Destroy() end
		if label.Parent then label.Text = tostring(to) label.Position = home end
	end)
	task.delay(delay or 0, function()
		if not nxt.Parent then return end
		local ti = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(label, ti, {Position = home - UDim2.fromScale(0, 1)}):Play()
		local t = TweenService:Create(nxt, ti, {Position = home})
		t:Play()
		t.Completed:Connect(function()
			label.Text = tostring(to)
			label.Position = home
			nxt:Destroy()
			pop(label, 1.3) -- little thump once the new number lands
		end)
	end)
end

local resultState -- what was hidden / moved, so it can all be put back
local resultBlur
local function setResultBlur(on)
	if not resultBlur or not resultBlur.Parent then
		resultBlur = Instance.new("BlurEffect")
		resultBlur.Name = "RoundResultBlur"
		resultBlur.Size = 0
		resultBlur.Parent = Lighting
	end
	local c = Center()
	tween(resultBlur, 0.3, {Size = on and ((c and c:GetAttribute("ResultBlur")) or 14) or 0})
end

local function cattr(name, default)
	local c = Center()
	local v = c and c:GetAttribute(name)
	if v == nil then return default end
	return v
end

endRoundResult = function(instant)
	player:SetAttribute("NoTabMenu", nil)
	local st = resultState
	if not st then return end
	resultState = nil
	st.alive = false
	setResultBlur(false)
	for g in st.guis do if g.Parent then g.Enabled = true end end
	for _, o in st.hiddenObjs do if o.Parent then o.Visible = true end end
	for core, was in st.core do pcall(function() StarterGui:SetCoreGuiEnabled(core, was) end) end
	for o, saved in st.moved do
		if o.Parent then o.AnchorPoint = saved[2] o.Position = saved[1] end
	end
	local center = Center()
	show(get(center, "Banner"), false)
	show(get(center, "BannerSub"), false)
	local hud = HUD()
	local scale = hud and hud:FindFirstChild("ResultScale")
	if hud and st.hud then
		if instant then
			hud.AnchorPoint, hud.Position = st.hud[2], st.hud[1]
			if scale then scale:Destroy() end
		else
			-- slide back up to the top, then restore the designer's exact position
			local ti = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(hud, ti, {Position = st.hudPixel}):Play()
			if scale then TweenService:Create(scale, ti, {Scale = 1}):Play() end
			task.delay(0.36, function()
				if resultState then return end -- a new result started meanwhile
				hud.AnchorPoint, hud.Position = st.hud[2], st.hud[1]
				if scale and scale.Parent then scale:Destroy() end
			end)
		end
	end
end

startRoundResult = function(data)
	endRoundResult(true)
	player:SetAttribute("NoTabMenu", true) -- no Tab scoreboard / free mouse during the round result (TabMenu)
	local st = {guis = {}, hiddenObjs = {}, core = {}, moved = {}, alive = true}
	resultState = st
	local pg = player.PlayerGui
	-- 1) close every other UI (other ScreenGuis, the rest of MatchUI, chat + player list)
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then st.guis[g] = true g.Enabled = false end
	end
	-- (chat stays open so players can still talk during the round result)
	for _, core in {Enum.CoreGuiType.PlayerList} do
		local ok, was = pcall(function() return StarterGui:GetCoreGuiEnabled(core) end)
		if ok and was then st.core[core] = was pcall(function() StarterGui:SetCoreGuiEnabled(core, false) end) end
	end
	local center = Center()
	for _, o in gui:GetChildren() do
		if o:IsA("GuiObject") and o ~= center and o ~= HUD() and o.Name ~= "Fade" and o.Visible then
			o.Visible = false table.insert(st.hiddenObjs, o)
		end
	end
	if center then
		for _, o in center:GetChildren() do
			if o:IsA("GuiObject") and o.Name ~= "Banner" and o.Name ~= "BannerSub" then o.Visible = false end
		end
	end
	-- keep them closed even if another script turns one back on
	task.spawn(function()
		while st.alive do
			for g in st.guis do if g.Parent and g.Enabled then g.Enabled = false end end
			task.wait(0.1)
		end
	end)
	setResultBlur(true)

	-- 2) old Banner / BannerSub text above the scoreboard
	local mine, theirs = myTeam(), otherTeam()
	local banner, sub = get(center, "Banner"), get(center, "BannerSub")
	-- Banner / BannerSub can be the text itself OR a box (Frame) with the text label inside it
	local function textOf(o)
		if not o or isText(o) then return o end
		local named = o:FindFirstChild(o.Name, true)
		if isText(named) then return named end
		return o:FindFirstChildWhichIsA("TextLabel", true)
	end
	local bannerText, subLabel = textOf(banner), textOf(sub)
	SFX.Play(data.Winner == 0 and "RoundDraw" or (data.Winner == mine and "RoundWon" or "RoundLost"))
	-- all the wording lives in ReplicatedStorage > Matchmaking > Config > ResultText
	local RT = Config.ResultText or {}
	if data.Winner == 0 then
		setText(bannerText, RT.Draw or "DRAW") setTextColor(bannerText, color("DrawColor"))
	elseif data.Winner == mine then
		setText(bannerText, RT.Won or "ROUND WON") setTextColor(bannerText, color("WinColor"))
	else
		setText(bannerText, RT.Lost or "ROUND LOST") setTextColor(bannerText, color("LoseColor"))
	end
	-- line under ROUND WON / ROUND LOST:
	--   1v1:        "lux killed require in 12 seconds"
	--   team modes: "Team 1 killed Team 2 in 12 seconds" (your own team is always Team 1 on your screen)
	--   time ran out: "Time's up - no one scored"
	local secs = data.Seconds or 0
	local myName, theirName = RT.MyTeamName or "Team 1", RT.EnemyTeamName or "Team 2"
	local fill = {
		killer = data.Killer or "?", victim = data.Victim or "?",
		winner = data.Winner == mine and myName or theirName,
		loser = data.Winner == mine and theirName or myName,
		seconds = tostring(secs), s = secs == 1 and "second" or "seconds",
	}
	local function format(line)
		return ((line or ""):gsub("{(%w+)}", function(k) return fill[k] or ("{" .. k .. "}") end))
	end
	local subText = ""
	local teamGame = (player:GetAttribute("MatchTeamSize") or 1) > 1
	if data.Winner == 0 then
		subText = format(data.Killer and (RT.EveryoneDown or "Everyone went down - no one scored")
			or (RT.TimeUp or "Time's up - no one scored"))
	elseif teamGame then
		subText = format(RT.TeamKill or "{winner} killed {loser} in {seconds} {s}")
	elseif data.Killer then
		subText = format(RT.Kill1v1 or "{killer} killed {victim} in {seconds} {s}")
	end
	setText(subLabel, subText)
	for o, y in {[banner or false] = cattr("ResultBannerY", 0.37), [sub or false] = cattr("ResultSubY", 0.415)} do
		if o then
			st.moved[o] = {o.Position, o.AnchorPoint}
			o.AnchorPoint = Vector2.new(0.5, 0.5)
			o.Position = UDim2.fromScale(0.5, y)
		end
	end
	show(banner, true)
	show(sub, subText ~= "")
	pop(banner, 1.25)

	-- 3) the top scoreboard slides to the middle and grows (the round timer stays hidden on the result)
	local hud = HUD()
	if hud then
		show(hud, true)
		local rt = hud:FindFirstChild("RoundTimer")
		if rt then rt.Visible = false end
		-- (the DESIGNED spot, remembered once - saving wherever it was at the time could catch it mid-slide when two
		--  results came close together, e.g. both dying in a trade, and it was then put back too high)
		if hud:GetAttribute("DesignPos") == nil then
			hud:SetAttribute("DesignPos", hud.Position)
			hud:SetAttribute("DesignAnchor", hud.AnchorPoint)
		end
		st.hud = {hud:GetAttribute("DesignPos"), hud:GetAttribute("DesignAnchor")}
		local parentPos = hud.Parent:IsA("GuiObject") and hud.Parent.AbsolutePosition or Vector2.zero
		local centerPx = hud.AbsolutePosition + hud.AbsoluteSize / 2 - parentPos
		st.hudPixel = UDim2.new(0, centerPx.X, 0, centerPx.Y)
		hud.AnchorPoint = Vector2.new(0.5, 0.5)
		hud.Position = st.hudPixel
		local scale = hud:FindFirstChild("ResultScale") or Instance.new("UIScale")
		scale.Name = "ResultScale"
		scale.Scale = 1
		scale.Parent = hud
		local ti = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(hud, ti, {Position = UDim2.fromScale(0.5, cattr("ResultHudY", 0.56))}):Play()
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = cattr("ResultHudScale", 1.6)}):Play()
	end

	-- 4) the tick: the side that scored rolls up from its old number
	local prev = {data.Scores[1] or 0, data.Scores[2] or 0}
	if data.Winner and data.Winner > 0 then prev[data.Winner] = math.max(0, prev[data.Winner] - 1) end
	local score = get(hud, "Score")
	-- starts once the scoreboard has landed in the middle (it takes ~0.5s to get there)
	local rollDelay = cattr("ResultRollDelay", 0.75)
	rollDigit(get(score, "Score1"), prev[mine], data.Scores[mine] or 0, rollDelay)
	rollDigit(get(score, "Score2"), prev[theirs], data.Scores[theirs] or 0, rollDelay)
end

function handlers.RoundEnd(data)
	if earlySpectate then earlySpectate = false updateSpectate() end
	-- the camera stays put from when the server MOVES you (your respawn between rounds - that was the trip to the
	-- sky) until the next round. Not before: the winner can still walk round during the result, and a held camera
	-- there made it look like you couldn't move.
	betweenRounds = true
	-- the kill popup gets RoundResultDelay seconds, then it closes and the round result takes over
	local token = roundToken
	task.delay(Config.RoundResultDelay or 1, function()
		if token ~= roundToken then return end -- next round already started
		local popup = get(combatUI(), "KillPopup")
		if popup and popup:IsA("GuiObject") then popup.Visible = false end
		startRoundResult(data)
	end)
end

-- END SCREEN: your character just stands there (idle), no running / falling animation while frozen.
-- (Your character is replaced when you go back to the lobby, so nothing needs turning back on.)
local function standStill()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then animate.Enabled = false end
	for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0.2) end
	local idle = animate and animate:FindFirstChild("idle")
	local a = idle and idle:FindFirstChildWhichIsA("Animation")
	if a then
		local track = animator:LoadAnimation(a)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.2)
	end
	hum:Move(Vector3.zero)
end

function handlers.MatchEnd(data)
	stopEarlySpectate()
	releaseCam()
	if player:GetAttribute("DeathCam") then player:SetAttribute("DeathCam", nil) end
	-- (standing still on the end screen: StarterCharacterScripts > Movement holds the idle pose while you're frozen)
	if earlySpectate then earlySpectate = false updateSpectate() end
	player:SetAttribute("NoTabMenu", nil)
	setCountdownBlur(false)
	highlightEnemies(false)
	roundToken += 1
	endRoundResult(true)
	hideAll()
	hookButtons()
	local cui = combatUI()
	if cui then cui.Enabled = false end
	local e = EndScreen()
	reveal(e)
	local result = get(e, "Result")
	setText(result, (data.Won and "VICTORY" or "DEFEAT") .. (data.Forfeit and " (FORFEIT)" or ""))
	setTextColor(result, color(data.Won and "VictoryTitleColor" or "DefeatTitleColor"))
	local score = get(e, "Score")
	setText(get(score, "Box1", "Value"), tostring(data.Scores[myTeam()]))
	setText(get(score, "Box2", "Value"), tostring(data.Scores[otherTeam()]))
	-- player card: headshot, level, device, streak, name, K/D, XP gained (each part optional)
	local card = get(e, "Card")
	if card then
		local img = card:FindFirstChild("Headshot")
		if img and img:IsA("ImageLabel") then img.Image = headshot(player.UserId) end
		setText(get(card, "LevelBox", "Value") or card:FindFirstChild("Level"), tostring(data.Level or 1))
		local slot = card:FindFirstChild("DeviceSlot")
		if slot then
			for _, c in slot:GetChildren() do if c:GetAttribute("DeviceIcon") then c:Destroy() end end
			local icon = PlayerCard.DeviceIcon(player:GetAttribute("Device") or "PC", slot)
			icon:SetAttribute("DeviceIcon", true)
			for _, d in icon:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = slot.ZIndex + 1 end end
			if icon:IsA("GuiObject") then icon.ZIndex = slot.ZIndex + 1 end
		end
		local streak = card:FindFirstChild("Streak")
		if isText(streak) then
			-- the design has its own fire icon (an ImageLabel inside Streak) -> just the number, no emoji
			-- (no fire picture in the design? the fire image is added in front of the number - PlayerCard.SetStreak)
			if streak:GetAttribute("Format") then streak.Text = streak:GetAttribute("Format"):format(data.WinStreak or 0)
			else PlayerCard.SetStreak(streak, data.WinStreak or 0) end
		end
		setText(card:FindFirstChild("PlayerName"), string.upper(NameBadge.Of(player)))
		setText(card:FindFirstChild("Username"), "@" .. string.upper(player.Name))
		local kd = card:FindFirstChild("KD")
		if isText(kd) then
			if kd.RichText then
				kd.Text = ('%d / <font color="#FF4A4A">%d</font>'):format(data.Kills, data.Deaths)
			else
				kd.Text = ("%d / %d"):format(data.Kills, data.Deaths)
			end
		end
		setText(card:FindFirstChild("Kills"), tostring(data.Kills))
		setText(card:FindFirstChild("Deaths"), tostring(data.Deaths))
		setText(card:FindFirstChild("XP"), ("+%d XP"):format(data.XPGained))
	end
	show(e, true)
	SFX.Play(data.Won and "Victory" or "Defeat")
	pop(result, 1.25)
	if card and gui:GetAttribute("PopAnimations") ~= false then
		local pos = card:GetAttribute("DesignPosition") or card.Position
		card:SetAttribute("DesignPosition", pos)
		card.Position = pos + UDim2.fromScale(0, 0.4)
		tween(card, 0.5, {Position = pos})
	end
	-- the end screen should show the world, not a black screen
	local f = Fade()
	if f and f.Visible then setFade(f, 1) show(f, false) end
	showEndQuests(e, data)
	-- MVP (team modes)
	local mvpLabel = get(e, "MVP")
	local mvpChar
	if data.MVP then
		local mc = Config.MVP or {}
		local txt = (mc.EndText or "MVP: {name}"):gsub("{(%w+)}", {
			name = string.upper(NameBadge.Format(data.MVP.DisplayName or data.MVP.Name or "?", data.MVP.Verified)),
			kills = tostring(data.MVP.Kills or 0), deaths = tostring(data.MVP.Deaths or 0), assists = tostring(data.MVP.Assists or 0)})
		-- ONE crown: the label's own Icon (crown picture) if it has one, else a crown emoji in front
		local hasIcon = mvpLabel and mvpLabel:FindFirstChildWhichIsA("ImageLabel") ~= nil
		setText(mvpLabel, (hasIcon and " " or "\u{1F451} ") .. txt)
		if mc.Color then setTextColor(mvpLabel, mc.Color) end
		show(mvpLabel, true)
		pop(mvpLabel, 1.3)
		local mp = Players:GetPlayerByUserId(data.MVP.UserId)
		mvpChar = mp and mp.Character
	else
		show(mvpLabel, false)
	end
	startEndCamera(data.EndTime or Config.EndScreenTime, mvpChar)
end

function handlers.FadeOut()
	fadeToBlack()
end

function handlers.Cancelled()
	releaseCam()
	if player:GetAttribute("DeathCam") then player:SetAttribute("DeathCam", nil) end
	setCountdownBlur(false)
	votePhase = false
	stopPreview()
	endRoundResult(true)
	hideAll()
	local f = Fade()
	if f then show(f, true) setFade(f, 0) end
	showLogo(true, "MATCH CANCELLED")
	SFX.Play("MatchCancelled")
end

function handlers.Return()
	releaseCam()
	if player:GetAttribute("DeathCam") then player:SetAttribute("DeathCam", nil) end
	stopEarlySpectate()
	SFX.Play("ReturnToLobby")
	-- back in the lobby: every cleanup step is protected, so one broken piece can never leave you on a black screen
	for _, step in {
		function() setCountdownBlur(false) end,
		function() highlightEnemies(false) end,
		function() votePhase = false stopPreview() end,
		function() endRoundResult(true) end,
		function() roundToken += 1 stopEndCamera() end,
		function() hideAll() matchLayout(false) end,
		function() player:SetAttribute("NoTabMenu", nil) end,
	} do
		local ok, err = pcall(step)
		if not ok then warn("[MatchUI] Return cleanup: " .. tostring(err)) end
	end
	local cui = combatUI()
	if cui then cui.Enabled = true end
	showLogo(false)
	local f = Fade()
	if f then show(f, true) setFade(f, 0) end
	task.wait(0.3)
	fadeFromBlack()
end

------------------------------------------------------------ AIM (for the kill replay)
-- in a match, tell the server where you're looking (+ how high your camera is above your body) ~30x a second,
-- so replays show your exact view
task.spawn(function()
	local AimRemote = Remotes:WaitForChild("Aim", 30)
	if not AimRemote then return end
	local last = 0
	RunService.RenderStepped:Connect(function()
		if os.clock() - last < 1 / 45 then return end -- (45x a second: smooth spectating / replays)
		if not (player:GetAttribute("MatchId") and player:GetAttribute("InArena")) then return end
		last = os.clock()
		local cam = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		-- (+ where your body is on your screen right now, so replays match your aim to your body exactly)
		AimRemote:FireServer(cam.CFrame.LookVector, root and (cam.CFrame.Position.Y - root.Position.Y) or nil, root and root.Position or nil)
	end)
end)

------------------------------------------------------------ COUNTDOWN ENEMY HIGHLIGHT
-- during the 3-2-1 the other team glows red (through walls) so you know where they are.
-- Colours: EnemyHighlightColor / EnemyHighlightFill (transparency) attributes on MatchUI.
local enemyHighlights = {}
highlightEnemies = function(on)
	for _, h in enemyHighlights do h:Destroy() end
	table.clear(enemyHighlights)
	if not on then return end
	local myMatch, myTeamId = player:GetAttribute("MatchId"), player:GetAttribute("MatchTeam")
	local enemies = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("MatchId") == myMatch and other:GetAttribute("MatchTeam") ~= myTeamId and other.Character then
			table.insert(enemies, other.Character)
		end
	end
	-- (match bots on the other team too: ServerStorage > Bots)
	local bf = workspace:FindFirstChild("Bots")
	for _, m in bf and bf:GetChildren() or {} do
		if m:GetAttribute("MatchId") == myMatch and m:GetAttribute("MatchTeam") ~= myTeamId then table.insert(enemies, m) end
	end
	for _, enemyChar in enemies do
		do
			-- THE LOOK: MatchUI > Templates > EnemyHighlight (else the colour attributes on MatchUI)
			local tpl = gui:FindFirstChild("Templates") and gui.Templates:FindFirstChild("EnemyHighlight")
			local h = tpl and tpl:Clone() or Instance.new("Highlight")
			h.Name = "CountdownEnemyHighlight"
			h.Enabled = true
			if not tpl then
				local c = color("EnemyHighlightColor") or Color3.fromRGB(255, 45, 45)
				h.FillColor = c
				h.OutlineColor = c
				h.FillTransparency = gui:GetAttribute("EnemyHighlightFill") or 0.5
				h.OutlineTransparency = 0
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			end
			h.Adornee = enemyChar
			h.Parent = enemyChar
			table.insert(enemyHighlights, h)
		end
	end
end

------------------------------------------------------------ FINAL KILL REPLAY
-- the last few seconds before the match-winning kill, seen through the killer's eyes, for everyone in the match.
-- Look: MatchUI > KillReplay (Title / Sub / TopBar / BottomBar). Settings: Matchmaking > Config > KillReplay / KillReplayTime
local BalloonFolder = RS:FindFirstChild("BalloonCombat")

-- everyone's real body in the replay: players + the match bots (ServerStorage > Bots)
local function liveBodies()
	local list = {}
	for _, pl in Players:GetPlayers() do if pl.Character then table.insert(list, pl.Character) end end
	local bf = workspace:FindFirstChild("Bots")
	for _, m in bf and bf:GetChildren() or {} do table.insert(list, m) end
	return list
end
local function bodyOf(userId)
	local p = Players:GetPlayerByUserId(userId)
	if p then return p.Character end
	local bf = workspace:FindFirstChild("Bots")
	for _, m in bf and bf:GetChildren() or {} do
		if m:GetAttribute("BotUserId") == userId and m:GetAttribute("MatchId") == player:GetAttribute("MatchId") then return m end
	end
	return nil
end

local function makeGhost(char)
	char.Archivable = true
	local ok, ghost = pcall(function() return char:Clone() end)
	if not ok or not ghost then return nil end
	for _, d in ghost:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("Highlight") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			d.Enabled = false
		end
	end
	for _, d in ghost:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			-- body parts are placed every frame; accessories and the held balloon stay welded to them
			d.Anchored = d.Parent == ghost and d.Name ~= "HeldBalloon"
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = ghost:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
	end
	ghost.Name = "ReplayGhost"
	return ghost
end

local function frameAt(frames, t)
	if t <= frames[1].t then return frames[1], frames[1], 0 end
	for i = 1, #frames - 1 do
		local a, b = frames[i], frames[i + 1]
		if t <= b.t then return a, b, (t - a.t) / math.max(b.t - a.t, 1e-3) end
	end
	return frames[#frames], frames[#frames], 0
end

local function replayShot(from, to, pop, skin, base)
	-- the thrower's own balloon (wrap on their base)
	local okS, Skins = pcall(function() return require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig")) end)
	local b = okS and skin and Skins.ById[skin] and Skins.Model(skin, base)
	local tpl = BalloonFolder and BalloonFolder:FindFirstChild("BalloonTemplate")
	b = b or (tpl and tpl:Clone()) or Instance.new("Part")
	b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
	if b:IsA("BasePart") then b.Size *= 0.6 end
	for _, d in b:GetDescendants() do if d:IsA("Beam") then d.Enabled = false end end
	b.CFrame = CFrame.new(from)
	b.Parent = workspace
	local t = TweenService:Create(b, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {CFrame = CFrame.new(to)})
	t:Play()
	t.Completed:Connect(function()
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

function handlers.KillReplay(data)
	stopEarlySpectate()
	if type(data.People) ~= "table" or #data.People == 0 then return end
	endRoundResult(true)
	player:SetAttribute("NoTabMenu", true) -- no Tab during the replay either (cleared when the next screen comes)
	highlightEnemies(false)
	SFX.Play("ReplayStart")
	fadeToBlack()
	hideAll()
	-- hide the other UI while it plays
	-- (the combat UI stays, but only the crosshair + reload bar: it should feel like you ARE the killer)
	local hiddenGuis, hiddenCombat = {}, {}
	local cui = combatUI()
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g ~= cui and g.Enabled then g.Enabled = false table.insert(hiddenGuis, g) end
	end
	if cui then
		cui.Enabled = true
		for _, o in cui:GetChildren() do
			if o.Name == "KillPopup" and o:IsA("GuiObject") then o.Visible = false end -- the replay's own popup shows here
			if o:IsA("GuiObject") and o.Visible and o.Name ~= "Crosshair" and o.Name ~= "ReloadBar" and o.Name ~= "ReloadHolder" and o.Name ~= "KillPopup" then
				o.Visible = false table.insert(hiddenCombat, o)
			end
		end
	end
	local cam = workspace.CurrentCamera
	local ClientActions = BalloonFolder and BalloonFolder:FindFirstChild("ClientActions")
	local function action(...) if ClientActions then ClientActions:Fire(...) end end

	-- ghosts of everyone, played back from the recording
	local folder = Instance.new("Folder")
	folder.Name = "KillReplay"
	folder.Parent = workspace
	local actors = {}
	local ghostOf = {} -- [UserId] = ghost model
	local killerFrames
	for _, person in data.People do
		local body = bodyOf(person.UserId)
		local ghost = body and makeGhost(body)
		if ghost then
			ghost.Parent = folder
			local isKiller = person.UserId == data.Killer
			if isKiller then
				killerFrames = person.Frames
				-- first person: don't draw the killer's own body
				for _, d in ghost:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then d.Transparency = 1 end
				end
			end
			table.insert(actors, {ghost = ghost, frames = person.Frames, killer = isKiller})
			ghostOf[person.UserId] = ghost
		end
	end
	if not killerFrames then
		folder:Destroy()
		for _, g in hiddenGuis do g.Enabled = true end
		for _, o in hiddenCombat do o.Visible = true end
		return
	end
	action("ReplayStart", data.Killer) -- the killer's arms (their shirt / skin) + balloon + crosshair on your screen

	local rp = gui:FindFirstChild("KillReplay")
	setText(get(rp, "Sub"), (data.KillerName or "?") .. "'s POV")

	local length = data.Length or 3
	local shots = data.Shots or {}
	local nextShot = 1
	-- the killer's hits: damage numbers + red flash, shown when the balloon lands (like in a real fight)
	local ReplayFX = BalloonFolder and BalloonFolder:FindFirstChild("ReplayFX")
	local bcConfig = BalloonFolder and BalloonFolder:FindFirstChild("Config") and require(BalloonFolder.Config)
	local hits = {}
	for _, h in data.Hits or {} do
		if h.Attacker == data.Killer then table.insert(hits, h) end
	end
	local nextHit = 1
	local killShown = false
	local lastHitDelay = 0
	local function flightTime(h)
		if h.melee or not bcConfig or not bcConfig.DamageWaitsForBalloon then return 0 end
		-- the killer's shot that caused this hit (the last one fired before it)
		local best
		for _, s in shots do
			if s.UserId == data.Killer and s.kind ~= "swing" and s.t <= h.t + 0.05 then best = s end
		end
		if not best or typeof(best.from) ~= "Vector3" then return 0 end
		local d = (h.pos - best.from).Magnitude
		return math.min(d / (bcConfig.ShotVisualSpeed or 200), bcConfig.ShotMaxTravelTime or math.huge)
	end
	local replayAlive = true
	local REPLAY = "FinalKillReplay"
	-- SLOW MOTION around the kill (Matchmaking > Config > KillReplaySlowMo / KillReplaySlowBefore / KillReplaySlowAfter)
	local slow = math.clamp(Config.KillReplaySlowMo or 1, 0.05, 1)
	local slowFrom = (data.KillAt or length) - (Config.KillReplaySlowBefore or 0)
	local slowTo = (data.KillAt or length) + (Config.KillReplaySlowAfter or 0)
	local clockT = 0
	local lastClock = os.clock()
	RunService:BindToRenderStep(REPLAY, Enum.RenderPriority.Last.Value + 20, function()
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now
		clockT = math.min(clockT + dt * ((clockT >= slowFrom and clockT < slowTo) and slow or 1), length)
		local t = clockT
		-- real characters stay hidden (the ghosts stand in for them)
		for _, body in liveBodies() do
			for _, d in body:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 end
			end
		end
		-- everyone else is shown where the KILLER saw them (they reached the killer's screen late: the killer's ping
		-- there and back + Roblox smoothing ~0.1s - MatchUI attribute KillReplayViewDelay). Hits were judged on that view.
		local kp = Players:GetPlayerByUserId(data.Killer)
		local viewDelay = math.clamp((tonumber(kp and kp:GetAttribute("Ping")) or 0) / 1000 + (gui:GetAttribute("KillReplayViewDelay") or 0.1), 0, 0.6)
		for _, a in actors do
			local fa, fb, alpha = frameAt(a.frames, a.killer and t or math.max(t - viewDelay, 0))
			for name, cfA in fa.parts do
				local part = a.ghost:FindFirstChild(name)
				local cfB = fb.parts[name] or cfA
				if part then part.CFrame = cfA:Lerp(cfB, alpha) end
			end
		end
		-- camera = the killer's eyes
		local ka, kb, ka2 = frameAt(killerFrames, t)
		local headA, headB = ka.parts.Head, kb.parts.Head or ka.parts.Head
		if headA then
			local pos = headA.Position:Lerp(headB.Position, ka2) + Vector3.new(0, 0.2, 0)
			local lookA = ka.look or headA.LookVector
			local lookB = kb.look or lookA
			local look = lookA:Lerp(lookB, ka2)
			if look.Magnitude < 0.01 then look = headA.LookVector end
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(pos, pos + look.Unit)
		end
		-- shots fired during the replay
		while shots[nextShot] and shots[nextShot].t <= t do
			local s = shots[nextShot]
			if s.UserId == data.Killer then
				-- the killer's own throws / swings play on the first-person arms, exactly like when you play
				if s.kind == "swing" then action("ReplaySwing")
				elseif typeof(s.to) == "Vector3" then action("ReplayShot", s.to, s.pop) end
			elseif s.kind ~= "swing" and typeof(s.from) == "Vector3" and typeof(s.to) == "Vector3" then
				local sp = Players:GetPlayerByUserId(s.UserId or 0)
				replayShot(s.from, s.to, s.pop, sp and sp:GetAttribute("EquippedSkin"), sp and sp:GetAttribute("EquippedBase"))
			end
			nextShot += 1
		end
		-- hits + the kill popup
		while hits[nextHit] and hits[nextHit].t <= t do
			local h = hits[nextHit]
			nextHit += 1
			local delay = flightTime(h)
			lastHitDelay = delay
			if ReplayFX and typeof(h.pos) == "Vector3" then
				task.delay(delay, function()
					if not replayAlive then return end
					ReplayFX:Fire("Damage", {pos = h.pos, amount = h.amount or 0, head = h.head, melee = h.melee, target = ghostOf[h.Victim]})
				end)
			end
		end
		if not killShown and data.KillAt and t >= data.KillAt then
			killShown = true
			if ReplayFX then
				local dist = 0
				local kf = frameAt(killerFrames, data.KillAt)
				local lastHit = hits[nextHit - 1]
				if kf and kf.parts.Head and lastHit and typeof(lastHit.pos) == "Vector3" then
					dist = math.floor((kf.parts.Head.Position - lastHit.pos).Magnitude + 0.5)
				end
				task.delay(lastHitDelay, function()
					if not replayAlive then return end
					ReplayFX:Fire("Kill", {victim = data.VictimName or "?", tags = data.Tags or {}, distance = dist, victimUserId = data.Victim, target = ghostOf[data.Victim]})
				end)
			end
		end
	end)
	reveal(rp)
	show(rp, true)
	fadeFromBlack()
	local waitStart = os.clock()
	repeat task.wait() until clockT >= length or os.clock() - waitStart > length + 6
	fadeToBlack()
	replayAlive = false
	pcall(function() RunService:UnbindFromRenderStep(REPLAY) end)
	do
		local kp = cui and cui:FindFirstChild("KillPopup")
		if kp and kp:IsA("GuiObject") then kp.Visible = false end
	end
	show(rp, false)
	folder:Destroy()
	for _, body in liveBodies() do
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end
		end
	end
	action("ReplayEnd")
	for _, g in hiddenGuis do if g.Parent then g.Enabled = true end end
	for _, o in hiddenCombat do if o.Parent then o.Visible = true end end
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	-- stays black: the victory / defeat screen fades in next
end

-- the match UI must be on (it's easy to untick MatchUI > Enabled in Studio while designing - then nothing shows)
gui.Enabled = true
MatchEvent.OnClientEvent:Connect(function(event, data)
	if not gui.Enabled then gui.Enabled = true end
	local h = handlers[event]
	if h then
		task.spawn(function()
			local ok, err = pcall(h, data or {})
			if not ok then warn(("[MatchUI] %s: %s"):format(event, tostring(err))) end
		end)
	end
end)

hideAll()
show(Fade(), false)

-- tell the server our match UI is loaded (match servers wait for this before starting, so nobody misses the intro / map vote)
task.spawn(function()
	local r = Remotes:WaitForChild("ClientReady", 15)
	if r then r:FireServer() end
end)
