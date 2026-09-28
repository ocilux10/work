-- MONTHLY LEADERBOARD REWARDS (client). Settings: ReplicatedStorage > LeaderboardRewards > RewardsConfig.
-- The podium's ProximityPrompt (RewardsConfig.PromptPath) opens a menu showing every tier's reward, the "it's monthly"
-- info + time left, and Claim for last month's place. The menu is a copy of Main > DailyRewardsFrame (same look:
-- its cards, top bar and claim button) with the info line of Main > RewardsFrame > TopBar > Info. It's made when the
-- game starts as Main > LeaderboardRewardsFrame - to design it yourself, make a frame with that name (same parts
-- as DailyRewardsFrame + TopBar > Info + a SwitchBoard button) and it's used instead.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("LeaderboardRewards")
local Config = require(folder:WaitForChild("RewardsConfig"))
local Remote = folder:WaitForChild("Remote")
local RewardInfo = require(RS:WaitForChild("RewardInfo"))
local RewardView = require(RS:WaitForChild("RewardView"))
local SFX = require(RS:WaitForChild("SFX"))

local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end
local function btnText(b, t) local l = b and b:FindFirstChild("Text") if l then setText(l, t) elseif b then setText(b, t) end end
local function fill(s, vars) return (s:gsub("{(%w+)}", function(k) return vars[k] ~= nil and tostring(vars[k]) or "{" .. k .. "}" end)) end
local function timeText(s)
	s = math.max(0, math.floor(s))
	local d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm %ds"):format(m, s % 60)
end
local function notice(text)
	local main = pg:FindFirstChild("Main")
	local n = main and main:FindFirstChild("DuelNotice")
	if not (n and n:IsA("TextLabel")) then return end
	n.Text = text
	n.Visible = true
	local token = (n:GetAttribute("Token") or 0) + 1
	n:SetAttribute("Token", token)
	task.delay(4, function() if n:GetAttribute("Token") == token then n.Visible = false end end)
end

local frame, list, cardTpl, claimBtn, switchBtn, info
local boardIndex = 1
local lastState -- from the server ("State")
local cards = {}

------------------------------------------------------------ BUILD THE MENU (copy of DailyRewardsFrame)
local function makeFrame(main)
	local own = main:FindFirstChild("LeaderboardRewardsFrame")
	if own then return own end
	local daily = main:WaitForChild("DailyRewardsFrame", 10)
	if not daily then return nil end
	-- (DailyRewardsClient keeps a clean card in DailyRewardsFrame > Templates > DayCard)
	local tpls = daily:WaitForChild("Templates", 15)
	if not (tpls and tpls:WaitForChild("DayCard", 5)) then return nil end
	local f = daily:Clone()
	f.Name = "LeaderboardRewardsFrame"
	f.Visible = false
	local rewards = f:FindFirstChild("Rewards")
	if rewards then for _, c in rewards:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end end
	local top = f:FindFirstChild("TopBar")
	setText(top and top:FindFirstChild("Text"), Config.Title or "LEADERBOARD REWARDS")
	-- the info line (same as Main > RewardsFrame > TopBar > Info)
	local srcInfo = main:FindFirstChild("RewardsFrame") and main.RewardsFrame:FindFirstChild("TopBar") and main.RewardsFrame.TopBar:FindFirstChild("Info")
	if top and srcInfo and not top:FindFirstChild("Info") then srcInfo:Clone().Parent = top end
	-- a second button next to Claim: switch board
	local claim = f:FindFirstChild("ClaimReward")
	if claim and #Config.Boards > 1 and not f:FindFirstChild("SwitchBoard") then
		local sw = claim:Clone()
		sw.Name = "SwitchBoard"
		local w = claim.Size
		local shift = UDim2.new(w.X.Scale * 0.55, w.X.Offset * 0.55, 0, 0)
		sw.Position = claim.Position - shift
		claim.Position = claim.Position + shift
		for _, g in sw:GetDescendants() do if g:IsA("UIGradient") and g.Name ~= "WaitTint" then g.Color = ColorSequence.new(Color3.fromRGB(70, 70, 78), Color3.fromRGB(40, 40, 46)) end end
		sw.BackgroundColor3 = Color3.fromRGB(55, 55, 62)
		sw.Parent = f
	end
	local tint = claim and claim:FindFirstChild("WaitTint") if tint then tint:Destroy() end
	f.Parent = main
	return f
end

local function tierLabel(tiers, i)
	local t = tiers[i]
	local prev = tiers[i - 1]
	if (prev and prev.Top or 0) + 1 == t.Top then return fill(Config.PlaceText or "#{place}", {place = t.Top}) end
	return fill(Config.RangeText or "TOP {top}", {top = t.Top})
end

local function boardState()
	local b = Config.Boards[boardIndex]
	for _, s in (lastState and lastState.Boards) or {} do
		if s.Board == b.Board then return s end
	end
end

local function paint()
	if not frame then return end
	local b = Config.Boards[boardIndex]
	if not b then return end
	local st = boardState()
	-- which card is yours (last month)
	local mine
	if st and st.Place then
		for i, t in b.Tiers do if st.Place <= t.Top then mine = i break end end
	end
	for i, c in cards do
		local o = c:FindFirstChild("YourPlace")
		if o then o.Enabled = i == mine end
		local tick = c:FindFirstChild("ClamiedFrame") or c:FindFirstChild("ClaimedFrame")
		if tick then tick.Visible = i == mine and st and st.Claimed == true end
	end
	if info then
		info.Text = fill(Config.InfoText or "", {time = timeText(((lastState and lastState.EndsAt) or os.time()) - os.time()), board = b.Title or b.Board})
	end
	if switchBtn then
		local nxt = Config.Boards[boardIndex % #Config.Boards + 1]
		btnText(switchBtn, fill(Config.SwitchText or "{board}  >", {board = b.Title or b.Board}))
		switchBtn:SetAttribute("Next", nxt and nxt.Board)
	end
	if claimBtn then
		-- (claim takes every board at once, so the button looks at all of them)
		local anyWin, anyLeft = false, false
		for _, s in (lastState and lastState.Boards) or {} do
			if s.Place then anyWin = true if not s.Claimed then anyLeft = true end end
		end
		local can = anyLeft and Config.Delivery ~= "Auto"
		btnText(claimBtn, can and (Config.ClaimText or "CLAIM") or (anyWin and (Config.ClaimedText or "CLAIMED") or (Config.NothingText or "NOTHING TO CLAIM")))
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
	local b = Config.Boards[boardIndex]
	if not (b and list and cardTpl) then return end
	local tiers = table.clone(b.Tiers)
	table.sort(tiers, function(x, y) return x.Top < y.Top end)
	b.Tiers = tiers
	for i, t in tiers do
		local c = cardTpl:Clone()
		c.Name = "Tier" .. i
		c.LayoutOrder = i
		c.Visible = true
		for _, n in {"TodayOutline", "Icon_3D"} do local x = c:FindFirstChild(n) if x then x:Destroy() end end
		setText(c:FindFirstChild("Day", true), tierLabel(tiers, i))
		local amount, name = RewardInfo.CardText(t.Reward)
		setText(c:FindFirstChild("Amount"), amount)
		setText(c:FindFirstChild("ItemName"), name)
		local tick = c:FindFirstChild("ClamiedFrame") or c:FindFirstChild("ClaimedFrame")
		if tick then tick.Visible = false end
		local st = Instance.new("UIStroke")
		st.Name = "YourPlace"
		st.Color = Config.YourPlaceColor or Color3.fromRGB(255, 200, 40)
		st.Thickness = 2.5
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Enabled = false
		st.Parent = c
		c.Parent = list
		RewardView.Show(c:FindFirstChild("Icon"), t.Reward)
		cards[i] = c
	end
	-- more tiers than fit: shrink the cards to fit
	task.defer(function()
		local lay = list:FindFirstChildWhichIsA("UIGridStyleLayout")
		if not lay then return end
		local horizontal = not lay:IsA("UIListLayout") or lay.FillDirection == Enum.FillDirection.Horizontal
		local need = horizontal and lay.AbsoluteContentSize.X or lay.AbsoluteContentSize.Y
		local have = horizontal and list.AbsoluteSize.X or list.AbsoluteSize.Y
		if need > have and need > 0 then
			local k = have / need * 0.98
			for _, c in cards do
				local s = c:FindFirstChild("FitScale") or Instance.new("UIScale")
				s.Name = "FitScale" s.Scale = k s.Parent = c
			end
		end
	end)
	paint()
end

------------------------------------------------------------ OPEN / CLOSE
local OTHER_MENUS = {"SettingsFrame", "ShopFrame", "MatchmakingFrame", "SkinsFrame", "PartyInviteFrame", "GiftFrame", "SearchFrame", "WatchFrame", "DailyRewardsFrame"}
local function refresh()
	local ok, res, st = pcall(function() return Remote:InvokeServer("State") end)
	if ok and res and type(st) == "table" then lastState = st end
	paint()
end
local function open(on)
	if not frame then return end
	if on then
		for _, n in OTHER_MENUS do local m = frame.Parent:FindFirstChild(n) if m and m:IsA("GuiObject") then m.Visible = false end end
		local pop = frame:FindFirstChild("OpenPop") or Instance.new("UIScale")
		pop.Name = "OpenPop" pop.Parent = frame pop.Scale = 0.8
		TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		task.spawn(refresh)
	end
	frame.Visible = on
	SFX.Play(on and "Open" or "Close")
end

local claiming = false
local function claim()
	if claiming or Config.Delivery == "Auto" then return end
	claiming = true
	local ok, res, msg = pcall(function() return Remote:InvokeServer("Claim") end)
	claiming = false
	if ok and res then
		SFX.Play("QuestComplete")
		notice(msg or "Claimed!")
		refresh()
		task.delay(0.6, open, false) -- (chests play their spin)
	else
		SFX.Play("Error")
		notice((ok and msg) or "Couldn't claim")
	end
end

------------------------------------------------------------ HOOK (again after every respawn)
local function hook(main)
	local f = makeFrame(main)
	if not f then warn("[LeaderboardRewards] needs Main > DailyRewardsFrame to copy") return end
	frame = f
	frame.Visible = false
	list = frame:FindFirstChild("Rewards")
	local tpls = main:FindFirstChild("DailyRewardsFrame") and main.DailyRewardsFrame:FindFirstChild("Templates")
	cardTpl = (frame:FindFirstChild("Templates") and frame.Templates:FindFirstChild("DayCard")) or (tpls and tpls:FindFirstChild("DayCard"))
	claimBtn = frame:FindFirstChild("ClaimReward")
	switchBtn = frame:FindFirstChild("SwitchBoard")
	info = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Info")
	if claimBtn and claimBtn:IsA("GuiButton") then claimBtn.Activated:Connect(claim) end
	if switchBtn and switchBtn:IsA("GuiButton") then
		switchBtn.Activated:Connect(function()
			boardIndex = boardIndex % #Config.Boards + 1
			SFX.Play("Toggle")
			build()
		end)
	end
	local off = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Off")
	if off and off:IsA("GuiButton") then off.Activated:Connect(function() open(false) end) end
	build()
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)

------------------------------------------------------------ THE PODIUM PROMPT (Workspace > Lobby > Podium > Prox > ProximityPrompt)
local hooked = setmetatable({}, {__mode = "k"})
local function findPrompt()
	local o = workspace
	for _, n in Config.PromptPath or {} do
		o = o and o:FindFirstChild(n)
	end
	return o and o:IsA("ProximityPrompt") and o or nil
end
task.spawn(function()
	while true do
		local p = findPrompt()
		if p and not hooked[p] then
			hooked[p] = true
			if (Config.PromptActionText or "") ~= "" then p.ActionText = Config.PromptActionText end
			if (Config.PromptObjectText or "") ~= "" then p.ObjectText = Config.PromptObjectText end
			p.Triggered:Connect(function() if frame then open(not frame.Visible) end end)
		end
		task.wait(2) -- (StreamingEnabled: the podium may load in / out)
	end
end)

-- the timer in the info line
task.spawn(function()
	while true do
		task.wait(1)
		if frame and frame.Visible then paint() end
	end
end)
