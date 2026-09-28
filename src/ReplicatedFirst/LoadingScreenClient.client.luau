-- LOADING SCREEN (ReplicatedFirst > LoadingScreen)
-- Shows straight away (before anything else loads) and waits for: the game, your character, the major assets
-- (logo, UI images, balloon, animations) and the map around you. The logo fills from grey to white with a soft
-- edge sweeping across it over LoadingConfig.Length seconds (never ahead of the real loading), then "Loaded!"
-- and a quick fade. Slow devices: never longer than LoadingConfig.MaxLoadTime.
-- Settings + tips: ReplicatedFirst > LoadingConfig
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RF = script.Parent
print("[LoadingScreen] script started")
local C = require(RF:WaitForChild("LoadingConfig"))
local player = Players.LocalPlayer
local gui = RF:WaitForChild("LoadingScreen", 10)
if not gui then warn("[LoadingScreen] no LoadingScreen ScreenGui in ReplicatedFirst") return end
gui.Enabled = true
gui.ResetOnSpawn = false -- (a respawn must never delete it)
gui.Parent = player:WaitForChild("PlayerGui")
pcall(function() RF:RemoveDefaultLoadingScreen() end)
print("[LoadingScreen] showing")

------------------------------------------------------------ NO CLICKING / HOVERING THE GAME UI WHILE IT'S UP
-- An invisible full-screen button on top of everything soaks up every click, tap and hover until the screen is gone.
-- (The loading screen also sits above all other UI, including the TopbarPlus buttons.)
gui.DisplayOrder = math.max(gui.DisplayOrder, 1000000)
gui.IgnoreGuiInset = true
local blocker = Instance.new("TextButton")
blocker.Name = "InputBlocker"
blocker.Text = ""
blocker.AutoButtonColor = false
blocker.BackgroundTransparency = 1
blocker.Size = UDim2.fromScale(1, 1)
blocker.ZIndex = 100000
blocker.Selectable = false
blocker.Active = true
blocker.Modal = true -- (PC) keeps the mouse free instead of locked to the centre
blocker:SetAttribute("NoButtonFX", true)
blocker:SetAttribute("NoClickSound", true)
blocker.Parent = gui

------------------------------------------------------------ NO MOVING WHILE IT'S UP
-- While the screen is up your character can't walk or jump (keyboard, gamepad and phone alike):
-- the "Loading" attribute makes the Movement script hold walk speed at 0, and jumping is switched off here.
local released = false
player:SetAttribute("Loading", true)
task.spawn(function()
	while not released do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
			if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
		end
		task.wait()
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
end)

local t0 = os.clock()
-- WaitForChild (not FindFirstChild): this script can start before every part of the screen has arrived,
-- which used to make the fill / text silently not work some of the time
local main = gui:WaitForChild("Main", 10)
local logo = main and main:WaitForChild("Logo", 5)
local loadingLabel = main and main:WaitForChild("Loading", 5)
local tipLabel = main and main:WaitForChild("FunFacs", 5)
if logo and logo:IsA("ImageLabel") then logo:WaitForChild("UIAspectRatioConstraint", 1) end
print(("[LoadingScreen] parts: logo=%s text=%s tip=%s"):format(tostring(logo ~= nil), tostring(loadingLabel ~= nil), tostring(tipLabel ~= nil)))

------------------------------------------------------------ TIP (one random one)
if tipLabel and #C.Tips > 0 then
	tipLabel.Text = C.Tips[math.random(1, #C.Tips)]
end

------------------------------------------------------------ LOGO FILL
-- a white copy of the logo sits on top; a gradient shows only its left part, with a soft edge that sweeps right
local fill, fillGrad
if logo and logo:IsA("ImageLabel") then
	logo.ImageColor3 = C.EmptyColor
	fill = logo:Clone()
	fill.Name = "LogoFill"
	fill.ImageColor3 = C.FullColor
	fill.ZIndex = logo.ZIndex + 1
	for _, c in fill:GetChildren() do if not c:IsA("UIAspectRatioConstraint") then c:Destroy() end end
	fillGrad = Instance.new("UIGradient")
	-- which way the white sweeps (LoadingConfig.FillDirection), plus the slant (FillAngle)
	local base = ({LeftToRight = 0, TopToBottom = 90, RightToLeft = 180, BottomToTop = 270})[C.FillDirection or "LeftToRight"] or 0
	fillGrad.Rotation = base + (C.FillAngle or 0)
	fillGrad.Parent = fill
	fill.Parent = logo.Parent
	-- make sure the logo image itself has downloaded before the sweep starts (max 2s)
	local ready = false
	task.spawn(function() pcall(function() ContentProvider:PreloadAsync({logo}) end) ready = true end)
	local w = os.clock()
	while not ready and os.clock() - w < 2 do task.wait() end
end
local function setFill(p)
	if not fillGrad then return end
	p = math.clamp(p, 0, 1)
	if p <= 0.001 then fillGrad.Transparency = NumberSequence.new(1) return end
	if p >= 0.999 then fillGrad.Transparency = NumberSequence.new(0) return end
	-- the soft edge travels from just off the left side to just off the right side
	local s = math.max(0.01, (C.FillSoftness or 0.18) / 2)
	local e = -s + p * (1 + 2 * s)
	local function alpha(x) return math.clamp((x - (e - s)) / (2 * s), 0, 1) end
	local xs = {0, e - s, e + s, 1}
	local pts, last = {}, -1
	for _, x in xs do
		x = math.clamp(x, 0, 1)
		if x > last + 1e-4 or #pts == 0 then
			if #pts > 0 and x >= 1 then x = 1 end
			table.insert(pts, NumberSequenceKeypoint.new(x, alpha(x)))
			last = x
		end
	end
	if pts[#pts].Time < 1 then table.insert(pts, NumberSequenceKeypoint.new(1, alpha(1))) end
	fillGrad.Transparency = NumberSequence.new(pts)
end
setFill(0)

------------------------------------------------------------ PROGRESS (shown value eases toward the real one)
local target, shown = 0, 0
local sweepStart = os.clock() -- (after the logo image is ready)
-- LoadingConfig.Mode = "Timed": exactly Length seconds - don't wait for anything (assets still preload behind it)
local timed = C.Mode == "Timed"
if timed then target = 1 end
local finished = false
local conn = RunService.Heartbeat:Connect(function(dt) -- (Heartbeat keeps running even while the game is still loading)
	-- the sweep follows the clock (Length seconds from grey to white), but never gets ahead of the real loading
	local byTime = (os.clock() - sweepStart) / math.max(0.5, C.Length or 7)
	shown = math.max(shown, math.min(target, byTime))
	setFill(shown)
	if loadingLabel and not finished then
		loadingLabel.Text = C.LoadingText:format(math.floor(shown * 100 + 0.5))
	end
end)

local function timeLeft()
	if timed then return 0 end -- (timed mode: none of the waits below hold anything up)
	return C.MaxLoadTime - (os.clock() - t0)
end

local RESERVE = 1.5 -- seconds of MaxLoadTime kept for finishing the sweep

-- 1) the game itself (0 - 20%)
if not game:IsLoaded() then
	local loaded = false
	local c = game.Loaded:Connect(function() loaded = true end)
	while not loaded and timeLeft() > RESERVE do
		target = math.min(0.18, (os.clock() - t0) * 0.1)
		task.wait()
	end
	c:Disconnect()
end
target = math.max(target, 0.2)

-- 2) your character (20 - 30%)
while not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) and timeLeft() > RESERVE do task.wait(0.05) end
target = math.max(target, 0.3)

-- 3) the major assets (30 - 60%)
-- assets = what the bar waits for (things you SEE straight away); background = preloaded too, but not waited for
local assets, background, seen = {}, {}, {}
local function add(a, bg)
	if a == nil or a == "" or seen[a] then return end
	seen[a] = true
	table.insert(bg and background or assets, a)
end
local RS = game:GetService("ReplicatedStorage")
if logo then add(logo.Image) end
-- sounds (every sound in SoundConfig that isn't switched Off)
pcall(function()
	local cfg = require(RS:WaitForChild("SoundConfig", math.max(0.1, timeLeft())))
	local function scan(t, depth)
		if depth > 3 then return end
		for _, v in t do
			if type(v) == "table" then
				if type(v.Id) == "string" and v.Id ~= "" and not v.Off then
					local id = v.Id:match("^rbxassetid://") and v.Id or ("rbxassetid://" .. v.Id)
					add(id, true) -- sounds load in the background (there are lots and they're slow)
				else
					scan(v, depth + 1)
				end
			end
		end
	end
	scan(cfg, 0)
end)
-- movement animations
pcall(function()
	local m = require(RS:WaitForChild("MovementConfig", math.max(0.1, timeLeft())))
	for _, id in m.Anims or {} do
		local a = Instance.new("Animation")
		a.AnimationId = id
		add(a)
	end
end)
-- the balloon
pcall(function()
	local bc = RS:FindFirstChild("BalloonCombat")
	local b = bc and bc:FindFirstChild("BalloonTemplate")
	if b then add(b) end
end)
-- UI images
pcall(function()
	local n = 0
	for _, d in game:GetService("StarterGui"):GetDescendants() do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" and not d.Image:find("rbxthumb") then
			if not seen[d.Image] then n += 1 add(d.Image) end
			if n >= 80 then break end
		end
	end
end)

local total, done = #assets, 0
if total > 0 then
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(assets, function()
				done += 1
				target = math.max(target, 0.3 + 0.3 * (done / total))
			end)
		end)
		done = total
	end)
	while done < total and timeLeft() > RESERVE do task.wait() end
end
target = math.max(target, 0.6)

-- 4) the map around you (60 - 100%): the world streams in around your character and its meshes / textures
-- queue up to download - wait until that queue has been empty for a moment
local peak = math.max(1, ContentProvider.RequestQueueSize)
local emptySince
while timeLeft() > RESERVE do
	local q = ContentProvider.RequestQueueSize
	peak = math.max(peak, q)
	target = math.max(target, 0.6 + 0.38 * (1 - q / peak))
	if q == 0 then
		emptySince = emptySince or os.clock()
		if os.clock() - emptySince > 0.6 then break end
	else
		emptySince = nil
	end
	task.wait(0.1)
end

-- 5) done (or out of time): let the sweep finish, "Loaded!", fade
target = 1
-- (out of time on a slow device: the sweep still plays to the end at its normal speed from where it is)
while shown < 0.999 do task.wait() end
shown = 1
setFill(1)
finished = true
if loadingLabel then loadingLabel.Text = C.LoadedText end
task.wait(C.LoadedHoldTime)

-- let them move again as the screen fades
released = true
player:SetAttribute("Loading", nil)
local ti = TweenInfo.new(C.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, d in gui:GetDescendants() do
	local props = {}
	if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then props.BackgroundTransparency = 1 end
	if d:IsA("TextLabel") or d:IsA("TextButton") then props.TextTransparency = 1 props.TextStrokeTransparency = 1 end
	if d:IsA("ImageLabel") or d:IsA("ImageButton") then props.ImageTransparency = 1 end
	if d:IsA("UIStroke") then props.Transparency = 1 end
	if next(props) then TweenService:Create(d, ti, props):Play() end
end
task.wait(C.FadeTime + 0.05)
conn:Disconnect()
gui:Destroy()
print(("[LoadingScreen] done after %.1fs"):format(os.clock() - t0))
-- now the sounds, in the background (starting them earlier made the screen hitch)
if #background > 0 then
	task.defer(function() pcall(function() ContentProvider:PreloadAsync(background) end) end)
end
