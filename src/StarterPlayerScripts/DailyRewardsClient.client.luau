-- DAILY REWARDS (client). Settings: ReplicatedStorage > DailyRewards > DailyConfig. Server: DailyRewardsServer.
-- A gift button in the top bar (TopbarPlus) opens / closes StarterGui > Main > DailyRewardsFrame.
--   Rewards > Frame   one day's card (the first one is the template): Frame > Day, Icon, Amount, ItemName,
--                     ClamiedFrame (shown on days you've claimed), Shadow > Bar
--   ClaimReward       the claim button (its Text label)       TopBar > Off   close
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("DailyRewards")
local Config = require(folder:WaitForChild("DailyConfig"))
local Remote = folder:WaitForChild("Remote")
local RewardInfo = require(RS:WaitForChild("RewardInfo"))
local RewardView = require(RS:WaitForChild("RewardView"))
local SFX = require(RS:WaitForChild("SFX"))
local Icon = require(RS:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end
local function btnText(b, t) local l = b and b:FindFirstChild("Text") if l then setText(l, t) elseif b then setText(b, t) end end
local function timeText(s)
	s = math.max(0, math.floor(s))
	local h, m = s // 3600, s % 3600 // 60
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm %ds"):format(m, s % 60) end
	return s .. "s"
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

local frame, list, cardTpl, claimBtn
local cards = {}
local claiming = false

------------------------------------------------------------ THE CARDS
local function paint()
	if not frame then return end
	local can = player:GetAttribute("DailyCanClaim") == true
	local day = player:GetAttribute("DailyDay") or 1
	for i, c in cards do
		local claimed = i < day or (i == day and not can)
		local tick = c:FindFirstChild("ClamiedFrame") or c:FindFirstChild("ClaimedFrame")
		if tick then tick.Visible = claimed end
		-- today's card: outline
		local st = c:FindFirstChild("TodayOutline")
		if st then st.Enabled = i == day and can end
		-- days not reached yet: faded
		local fade = i > day and (Config.FutureTransparency or 0) or 0
		c.BackgroundTransparency = c:GetAttribute("BaseTransparency") + (1 - c:GetAttribute("BaseTransparency")) * fade
	end
	if claimBtn then
		if can then
			btnText(claimBtn, Config.ClaimText or "CLAIM")
		else
			local left = (player:GetAttribute("DailyResetAt") or 0) - os.time()
			btnText(claimBtn, (Config.WaitText or "NEXT IN {time}"):gsub("{time}", timeText(left)))
		end
		claimBtn.AutoButtonColor = can
		local grey = claimBtn:FindFirstChild("WaitTint")
		if not can and not grey then
			grey = Instance.new("UIGradient") grey.Name = "WaitTint" grey.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120)) grey.Parent = claimBtn
		elseif can and grey then grey:Destroy() end
	end
end

local function build()
	for _, c in cards do c:Destroy() end
	table.clear(cards)
	if not (list and cardTpl) then return end
	for i, reward in Config.Days do
		local c = cardTpl:Clone()
		c.Name = "Day" .. i
		c.LayoutOrder = i
		c.Visible = true
		c:SetAttribute("BaseTransparency", c.BackgroundTransparency)
		local dayLbl = c:FindFirstChild("Day", true)
		setText(dayLbl, (Config.DayText or "{day}"):gsub("{day}", tostring(i)))
		local amount, name = RewardInfo.CardText(reward)
		setText(c:FindFirstChild("Amount"), amount)
		setText(c:FindFirstChild("ItemName"), name)
		RewardView.Show(c:FindFirstChild("Icon"), reward, Config.CoinImage)
		local st = Instance.new("UIStroke")
		st.Name = "TodayOutline"
		st.Color = Config.TodayOutline or Color3.new(1, 1, 1)
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Enabled = false
		st.Parent = c
		c.Parent = list
		cards[i] = c
	end
	paint()
end

------------------------------------------------------------ OPEN / CLOSE
local OTHER_MENUS = {"SettingsFrame", "ShopFrame", "MatchmakingFrame", "SkinsFrame", "PartyInviteFrame", "GiftFrame", "SearchFrame", "WatchFrame"}
local function open(on)
	if not frame then return end
	if on then
		local main = frame.Parent
		for _, n in OTHER_MENUS do local m = main:FindFirstChild(n) if m and m:IsA("GuiObject") then m.Visible = false end end
		paint()
		local pop = frame:FindFirstChild("OpenPop") or Instance.new("UIScale")
		pop.Name = "OpenPop" pop.Parent = frame pop.Scale = 0.8
		TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end
	frame.Visible = on
	SFX.Play(on and "Open" or "Close")
end

local function claim()
	if claiming or player:GetAttribute("DailyCanClaim") ~= true then SFX.Play("Error") return end
	claiming = true
	local ok, res, msg = pcall(function() return Remote:InvokeServer("Claim") end)
	claiming = false
	if ok and res then
		SFX.Play("QuestComplete")
		notice(msg or "Claimed!")
		task.wait()
		paint()
		-- (a chest reward plays its spin: get the menu out of the way)
		local r = Config.Days[player:GetAttribute("DailyDay") or 1]
		if r and r.Crate then task.delay(0.6, open, false) end
	else
		SFX.Play("Error")
		notice((ok and msg) or "Couldn't claim")
	end
end

------------------------------------------------------------ TOP BAR BUTTON
local T = Config.Topbar or {}
local icon = Icon.new()
icon:setName("DailyRewards")
if (T.Image or "") ~= "" then
	icon:setImage(T.Image)
	icon:setImageScale(T.ImageScale or 0.6)
else
	icon:setLabel(T.Label or "🎁")
end
icon:align("Left")
icon:oneClick()
icon:modifyTheme({
	{"IconCorners", "CornerRadius", UDim.new(1, 0)},
	{"IconButton", "BackgroundColor3", T.Color or Color3.fromRGB(18, 18, 21)},
	{"IconButton", "BackgroundTransparency", 0.08},
})
icon.selected:Connect(function() if frame then open(not frame.Visible) end end)
local badgeOn = false
local function updateBadge()
	local want = T.Badge ~= false and player:GetAttribute("DailyCanClaim") == true
	if want and not badgeOn then icon:notify() elseif not want and badgeOn then icon:clearNotices() end
	badgeOn = want
end
local function updateEnabled()
	if T.LobbyOnly == false then return end
	icon:setEnabled(player:GetAttribute("MatchId") == nil and not player:GetAttribute("InArena"))
end
for _, a in {"MatchId", "InArena"} do player:GetAttributeChangedSignal(a):Connect(updateEnabled) end
updateEnabled()

------------------------------------------------------------ HOOK THE MENU (again after every respawn)
local openedOnJoin = false
local function hook(main)
	frame = main:WaitForChild("DailyRewardsFrame", 10)
	if not frame then return end
	frame.Visible = false
	list = frame:WaitForChild("Rewards")
	table.clear(cards)
	cardTpl = nil
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			if not cardTpl then cardTpl = c else c:Destroy() end
		end
	end
	if cardTpl then
		cardTpl.Parent = nil
		-- a clean copy for other menus that use the same card (LeaderboardRewardsClient): DailyRewardsFrame > Templates > DayCard
		local tf = frame:FindFirstChild("Templates") or Instance.new("Folder")
		tf.Name = "Templates"
		tf.Parent = frame
		if not tf:FindFirstChild("DayCard") then
			local keep = cardTpl:Clone()
			keep.Name = "DayCard"
			keep.Visible = false
			keep.Parent = tf
		end
	end
	claimBtn = frame:FindFirstChild("ClaimReward")
	if claimBtn and claimBtn:IsA("GuiButton") then claimBtn.Activated:Connect(claim) end
	local off = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Off")
	if off and off:IsA("GuiButton") then off.Activated:Connect(function() open(false) end) end
	build()
	if Config.OpenOnJoin and not openedOnJoin and player:GetAttribute("DailyCanClaim") == true
		and player:GetAttribute("MatchId") == nil then
		openedOnJoin = true
		task.delay(3, function() if frame and not frame.Visible then open(true) end end)
	end
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)

for _, a in {"DailyCanClaim", "DailyDay", "DailyResetAt"} do
	player:GetAttributeChangedSignal(a):Connect(function()
		updateBadge()
		paint()
		-- the reward became ready while the menu hook ran already (first load): open it once
		if a == "DailyCanClaim" and Config.OpenOnJoin and not openedOnJoin and frame and player:GetAttribute("DailyCanClaim") == true
			and player:GetAttribute("MatchId") == nil then
			openedOnJoin = true
			task.delay(3, function() if frame and not frame.Visible then open(true) end end)
		end
	end)
end
updateBadge()
-- the countdown on the button
task.spawn(function()
	while true do
		task.wait(1)
		if frame and frame.Visible and player:GetAttribute("DailyCanClaim") ~= true then paint() end
	end
end)
