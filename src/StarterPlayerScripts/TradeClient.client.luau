-- TRADING (client). Settings / texts: ReplicatedStorage > Trade > TradeConfig. Server: ServerScriptService > TradeServer.
-- UI (restyle freely, everything is found by name):
--   Main > Buttons > Trade          opens Main > TradeListFrame (Search + one row per player: View = the eye, Trade)
--   Main > TradeViewFrame           someone's balloons (the eye): Header / ScrollingFrame / TradeButton / Close
--   Main > TradePrompt              incoming request: Headshot / Title / AcceptButton / DeclineButton / TimerBar
--   Main > TradeFrame               MySide / TheirSide (Header, Grid, CoinsRow), AcceptButton, DeclineButton, Status,
--                                   Picker (your "+"), Templates (Slot / AddSlot / EmptySlot)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("Trade"):WaitForChild("TradeConfig"))
local Remote = RS.Trade:WaitForChild("Remote")
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local NameBadge = require(RS:WaitForChild("NameBadge"))
local SFX = require(RS:WaitForChild("SFX"))
local T = Config.Text or {}
local MAX = Config.MaxItems or 12

local function fmt(t, v) t = t or "" for k, x in v or {} do t = t:gsub("{" .. k .. "}", tostring(x)) end return t end
local function headshot(id) return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(id or 1, 1)) end
local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then o.Text = t end end
local function btnText(b, t) if not b then return end local l = b:FindFirstChild("Text") setText(l or b, t) end
local function decodeInv(p)
	local raw = p:GetAttribute("BalloonInv")
	local ok, t = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
	t = ok and type(t) == "table" and t or {}
	t[Skins.DefaultId] = nil -- (never tradable)
	return t
end
local function sortedIds(items)
	local ids = {}
	for id, n in items do if Skins.ById[id] and n > 0 then table.insert(ids, id) end end
	table.sort(ids, function(a, b)
		local ra, rb = Skins.Rarity(a).Order, Skins.Rarity(b).Order
		if ra ~= rb then return ra > rb end
		return Skins.Get(a).Index < Skins.Get(b).Index
	end)
	return ids
end
local function countItems(items) local n, c = 0, 0 for _, x in items do n += 1 c += x end return n, c end

-- a balloon square (Slot template): picture, name, rarity, count
local function fillSlot(s, id, n)
	local sk, r = Skins.Get(id), Skins.Rarity(id)
	setText(s:FindFirstChild("SkinName"), sk.Name)
	setText(s:FindFirstChild("SkinType"), r.Text .. " " .. sk.Type)
	local bar = s:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = r.Color end
	local cnt = s:FindFirstChild("Count")
	if cnt then cnt.Visible = (n or 1) > 1 setText(cnt, "x" .. tostring(n)) end
	local vp = s:FindFirstChild("View")
	if vp and vp:IsA("ViewportFrame") and vp:GetAttribute("Shows") ~= id then
		vp:SetAttribute("Shows", id)
		for _, c in vp:GetChildren() do if not c:IsA("UIComponent") then c:Destroy() end end
		local m = Skins.ForViewport(Skins.Model(id))
		if m then
			m.CFrame = CFrame.new()
			m.Parent = vp
			local cam = Instance.new("Camera")
			cam.FieldOfView = 30
			cam.CFrame = CFrame.lookAt(Vector3.new(0, m.Size.Y * 0.05, m.Size.Y * 2.5), Vector3.zero)
			cam.Parent = vp
			vp.CurrentCamera = cam
			require(RS:WaitForChild("BalloonSkins"):WaitForChild("CardFX")).Attach(vp, id)
		end
	end
end

local main, list, prompt, view, tf
local rows = {}
local sentAt = {}
local function notice(text)
	local n = main and main:FindFirstChild("DuelNotice")
	if not (n and n:IsA("TextLabel") and text) then return end
	n.Text = text
	n.Visible = true
	local token = (n:GetAttribute("Token") or 0) + 1
	n:SetAttribute("Token", token)
	task.delay(2.5, function() if n:GetAttribute("Token") == token then n.Visible = false end end)
end
local function request(p)
	local cd = Config.RequestCooldown or 10
	if sentAt[p.UserId] and os.clock() - sentAt[p.UserId] < cd then SFX.Play("Error") return end
	sentAt[p.UserId] = os.clock()
	SFX.Play("Invite")
	Remote:FireServer({Action = "Request", Target = p})
end

local function inspectBalloon(id, from)
	local bc = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("BalloonsClient")
	local ev = bc and bc:FindFirstChild("Inspect")
	if ev then ev:Fire(id, from) end
end

------------------------------------------------------------ SOMEONE'S BALLOONS (the eye)
local viewing
local function showView(p)
	if not view then return end
	viewing = p
	local h = view:FindFirstChild("Header")
	if h then
		setText(h:FindFirstChild("PlayerName"), NameBadge.Of(p))
		setText(h:FindFirstChild("Username"), "@" .. p.Name)
		local av = h:FindFirstChild("Avatar") if av then av.Image = headshot(p.UserId) end
	end
	local sc = view:FindFirstChild("ScrollingFrame")
	local tpl = view:FindFirstChild("Templates") and view.Templates:FindFirstChild("Slot")
	for _, c in sc:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local inv = decodeInv(p)
	local _, total = countItems(inv)
	for i, id in sortedIds(inv) do
		local s = tpl:Clone()
		s.Visible = true
		s.LayoutOrder = i
		fillSlot(s, id, inv[id])
		-- click one = inspect it (the Balloons menu's inspect screen, then back here)
		local b = s:FindFirstChild("Button")
		if b and b:IsA("GuiButton") then b.Activated:Connect(function() inspectBalloon(id, view) end) end
		s.Parent = sc
	end
	if h then setText(h:FindFirstChild("Count"), total .. (total == 1 and " balloon" or " balloons")) end
	local e = view:FindFirstChild("Empty") if e then e.Visible = total == 0 setText(e, T.TheirEmpty or "No balloons yet") end
	local tb = view:FindFirstChild("TradeButton") if tb then tb.Visible = p ~= player end -- (your own balloons: nothing to trade)
	view.Visible = true
	SFX.Play("Open")
end

------------------------------------------------------------ PLAYER LIST
local function refreshList()
	if not list then return end
	local sc = list:FindFirstChild("ScrollingFrame")
	local tpl = sc and sc:FindFirstChild("Frame")
	if not tpl then return end
	tpl.Visible = false
	for _, r in rows do r:Destroy() end
	table.clear(rows)
	local search = list:FindFirstChild("Search")
	local q = search and search.Text:lower() or ""
	local any = false
	local others = Players:GetPlayers()
	table.sort(others, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
	for i, p in others do
		-- (Studio testing alone: set your player's TradeTestSelf attribute to see yourself in the list)
		local testSelf = p == player and RunService:IsStudio() and player:GetAttribute("TradeTestSelf")
		if (p ~= player or testSelf) and (q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
			any = true
			local r = tpl:Clone()
			r.Name = "Row_" .. p.UserId
			r.Visible = true
			r.LayoutOrder = i
			setText(r:FindFirstChild("Username"), NameBadge.Of(p))
			setText(r:FindFirstChild("Display"), "@" .. p.Name)
			local av = r:FindFirstChild("Avatar") if av and av:IsA("ImageLabel") then av.Image = headshot(p.UserId) end
			local eye = r:FindFirstChild("View")
			if eye and eye:IsA("GuiButton") then eye.Activated:Connect(function() showView(p) end) end
			local btn = r:FindFirstChild("Trade")
			if btn and btn:IsA("GuiButton") then
				btn:SetAttribute("NoClickSound", true)
				btn.Activated:Connect(function() request(p) end)
			end
			r.Parent = sc
			table.insert(rows, r)
		end
	end
	local e = sc:FindFirstChild("Empty")
	if e then e.Visible = not any setText(e, T.Empty or "No one else is in this server") end
end
-- the Trade buttons count down after you ask (TradeConfig.RequestCooldown)
task.spawn(function()
	while true do
		task.wait(0.25)
		if list and list.Visible then
			for _, r in rows do
				local id = tonumber(r.Name:match("%d+"))
				local btn = r:FindFirstChild("Trade")
				local left = id and sentAt[id] and ((Config.RequestCooldown or 10) - (os.clock() - sentAt[id])) or 0
				btnText(btn, left > 0 and (math.ceil(left) .. "s") or "Trade")
				if btn then
					if btn:GetAttribute("BaseColor") == nil then btn:SetAttribute("BaseColor", btn.BackgroundColor3) end
					btn.BackgroundColor3 = left > 0 and Color3.fromRGB(90, 90, 90) or btn:GetAttribute("BaseColor")
					local g = btn:FindFirstChildOfClass("UIGradient") if g then g.Enabled = left <= 0 end
				end
			end
		end
	end
end)

------------------------------------------------------------ THE TRADE
local session -- {id, partner, mine = {items, coins, accepted}, theirs = {...}, endsAt}
local myItems, myCoins = {}, 0 -- what I'm offering (sent to the server on every change)
local function sendOffer()
	if not session then return end
	Remote:FireServer({Action = "Offer", Id = session.id, Items = myItems, Coins = myCoins})
end
local function mySide() return tf:FindFirstChild("MySide") end
local function theirSide() return tf:FindFirstChild("TheirSide") end

local picker
local paint -- forward
local function refreshPicker()
	if not (picker and picker.Visible) then return end
	local sc = picker:FindFirstChild("ScrollingFrame")
	local tpl = tf.Templates:FindFirstChild("Slot")
	for _, c in sc:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local inv = decodeInv(player)
	local any = false
	for i, id in sortedIds(inv) do
		local left = inv[id] - (myItems[id] or 0)
		if left > 0 then
			any = true
			local s = tpl:Clone()
			s.Visible = true
			s.LayoutOrder = i
			for _, d in s:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex += 20 end end
			s.ZIndex += 20
			fillSlot(s, id, left)
			local b = s:FindFirstChild("Button")
			b.Activated:Connect(function()
				local slots = countItems(myItems)
				if not myItems[id] and slots >= MAX then SFX.Play("Error") notice("Max " .. MAX .. " different balloons") return end
				if (myItems[id] or 0) >= (decodeInv(player)[id] or 0) then SFX.Play("Error") return end
				myItems[id] = (myItems[id] or 0) + 1
				SFX.Play("Toggle")
				sendOffer()
				paint()
				refreshPicker()
			end)
			s.Parent = sc
		end
	end
	local e = picker:FindFirstChild("Empty") if e then e.Visible = not any end
end

local function paintSide(sideFrame, items, coins, accepted, who, mine)
	if not sideFrame then return end
	local h = sideFrame:FindFirstChild("Header")
	local n, c = countItems(items)
	if h then
		setText(h:FindFirstChild("PlayerName"), NameBadge.Of(who))
		setText(h:FindFirstChild("Username"), "@" .. who.Name)
		local av = h:FindFirstChild("Avatar") if av then av.Image = headshot(who.UserId) end
		local text = fmt(T.Count or "{n}/{max} • {items} balloons", {n = n, max = MAX, items = c})
		if c == 1 then text = text:gsub("balloons", "balloon") end
		setText(h:FindFirstChild("Count"), text)
		local ready = h:FindFirstChild("Ready")
		if ready then ready.Visible = accepted == true setText(ready, T.TheyAccepted or "READY") end
	end
	local grid = sideFrame:FindFirstChild("Grid")
	if grid then
		for _, g in grid:GetChildren() do if g:IsA("GuiObject") then g:Destroy() end end
		local order = 0
		for _, id in sortedIds(items) do
			order += 1
			local s = tf.Templates.Slot:Clone()
			s.Visible = true
			s.LayoutOrder = order
			fillSlot(s, id, items[id])
			if mine then
				-- click one of yours = take one back out
				s.Button.Activated:Connect(function()
					myItems[id] = (myItems[id] or 1) - 1
					if myItems[id] <= 0 then myItems[id] = nil end
					SFX.Play("Toggle")
					sendOffer()
					paint()
					refreshPicker()
				end)
			end
			s.Parent = grid
		end
		if mine and order < MAX then
			order += 1
			local a = tf.Templates.AddSlot:Clone()
			a.Visible = true
			a.LayoutOrder = order
			a.Activated:Connect(function()
				if not picker then return end
				picker.Visible = not picker.Visible
				SFX.Play(picker.Visible and "Open" or "Close")
				refreshPicker()
			end)
			a.Parent = grid
		end
		for i = order + 1, MAX do
			local e = tf.Templates.EmptySlot:Clone()
			e.Visible = true
			e.LayoutOrder = i
			e.Parent = grid
		end
	end
	local cr = sideFrame:FindFirstChild("CoinsRow")
	if cr then
		cr.Visible = Config.AllowCoins ~= false
		local amt = cr:FindFirstChild("Amount")
		if amt and not (amt:IsA("TextBox") and amt:IsFocused()) then
			setText(amt, (mine and coins == 0) and "" or tostring(coins))
		end
	end
end

paint = function()
	if not (session and tf) then return end
	local st = session.state or {Mine = {Items = {}, Coins = 0}, Theirs = {Items = {}, Coins = 0}}
	-- my side shows what I've picked straight away (the server confirms it a moment later)
	paintSide(mySide(), myItems, myCoins, st.Mine.Accepted, player, true)
	paintSide(theirSide(), st.Theirs.Items or {}, st.Theirs.Coins or 0, st.Theirs.Accepted, session.partner, false)
	local acc = tf:FindFirstChild("AcceptButton")
	btnText(acc, st.Mine.Accepted and (T.Accepted or "Accepted") or (T.Accept or "Accept"))
end

local function closeTrade(text)
	session = nil
	table.clear(myItems)
	myCoins = 0
	if picker then picker.Visible = false end
	if tf then tf.Visible = false end
	if text then notice(text) end
end

local function hookTrade()
	picker = tf:FindFirstChild("Picker")
	if picker then
		picker.Visible = false
		local c = picker:FindFirstChild("Close", true)
		if c and c:IsA("GuiButton") then c.Activated:Connect(function() picker.Visible = false SFX.Play("Close") end) end
	end
	local acc, dec = tf:FindFirstChild("AcceptButton"), tf:FindFirstChild("DeclineButton")
	if acc then acc.Activated:Connect(function()
		if not session then return end
		local on = not (session.state and session.state.Mine.Accepted)
		Remote:FireServer({Action = "Accept", Id = session.id, On = on})
		SFX.Play(on and "DuelAccepted" or "Toggle")
	end) end
	if dec then dec.Activated:Connect(function()
		if not session then return end
		Remote:FireServer({Action = "Cancel", Id = session.id})
		SFX.Play("DuelDeclined")
		closeTrade()
	end) end
	local amt = mySide() and mySide():FindFirstChild("CoinsRow") and mySide().CoinsRow:FindFirstChild("Amount")
	if amt and amt:IsA("TextBox") then
		amt:GetPropertyChangedSignal("Text"):Connect(function()
			local digits = amt.Text:gsub("%D", "")
			if digits ~= amt.Text then amt.Text = digits end
		end)
		amt.FocusLost:Connect(function()
			local n = math.floor(tonumber(amt.Text) or 0)
			n = math.clamp(n, 0, math.min(Config.MaxCoins or math.huge, player:GetAttribute("Coins") or 0))
			if n ~= myCoins then myCoins = n sendOffer() end
			amt.Text = n > 0 and tostring(n) or ""
		end)
	end
	-- closed some other way (controller B, another menu) = cancel
	tf:GetPropertyChangedSignal("Visible"):Connect(function()
		if not tf.Visible and session then
			Remote:FireServer({Action = "Cancel", Id = session.id})
			closeTrade()
		end
	end)
	local back = tf:FindFirstChild("PadBack") or Instance.new("BindableEvent")
	back.Name = "PadBack" back.Parent = tf
end

-- countdown text
RunService.Heartbeat:Connect(function()
	if not (session and tf and tf.Visible) then return end
	local status = tf:FindFirstChild("Status")
	local st = session.state
	if not (status and st) then return end
	if st.EndsAt then
		local left = math.max(math.ceil(st.EndsAt - workspace:GetServerTimeNow()), 0)
		status.Text = fmt(T.Countdown or "Trading in {n}...", {n = left})
	elseif st.Theirs.Accepted then
		status.Text = fmt("{name} accepted", {name = session.partner.DisplayName})
	elseif st.Mine.Accepted then
		status.Text = "Waiting for " .. session.partner.DisplayName .. "..."
	else
		status.Text = ""
	end
end)

------------------------------------------------------------ INCOMING REQUESTS
local current
local function closePrompt() if prompt then prompt.Visible = false end current = nil end
local function answer(yes)
	if not current then return end
	Remote:FireServer({Action = "Respond", Id = current, Accept = yes})
	SFX.Play(yes and "DuelAccepted" or "DuelDeclined")
	closePrompt()
end

Remote.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.Kind == "Notice" then
		notice(msg.Text) SFX.Play("Error")
	elseif msg.Kind == "Incoming" and prompt then
		current = msg.Id
		local id = msg.Id
		setText(prompt:FindFirstChild("Title", true), msg.Text or fmt(T.Request, {name = NameBadge.Format(msg.FromName or "?", msg.FromVerified)}))
		local head = prompt:FindFirstChild("Headshot", true)
		if head and head:IsA("ImageLabel") then head.Image = headshot(msg.FromUserId) end
		prompt.Visible = true
		SFX.Play("DuelRequest")
		local tb = prompt:FindFirstChild("TimerBar", true)
		if tb then
			tb.Size = UDim2.fromScale(1, tb.Size.Y.Scale)
			TweenService:Create(tb, TweenInfo.new(msg.Timeout or 20, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(0, tb.Size.Y.Scale)}):Play()
		end
		task.delay(msg.Timeout or 20, function() if current == id then closePrompt() end end)
	elseif msg.Kind == "Open" then
		closePrompt()
		if list then list.Visible = false end
		if view then view.Visible = false end
		table.clear(myItems)
		myCoins = 0
		session = {id = msg.Id, partner = msg.Partner}
		if tf then tf.Visible = true end
		SFX.Play("Open")
		paint()
	elseif msg.Kind == "State" and session and session.id == msg.Id then
		session.state = msg
		-- the server's copy of my offer wins (e.g. it dropped something I don't have)
		table.clear(myItems)
		for id, n in msg.Mine.Items or {} do myItems[id] = n end
		myCoins = msg.Mine.Coins or 0
		paint()
		refreshPicker()
	elseif (msg.Kind == "Done" or msg.Kind == "Closed") and session and session.id == msg.Id then
		if msg.Kind == "Done" then SFX.Play("Purchase") end
		closeTrade(msg.Text)
	end
end)

------------------------------------------------------------ HOOK UP (again after every respawn)
local function hook(m)
	main = m
	list = m:WaitForChild("TradeListFrame", 10)
	prompt = m:FindFirstChild("TradePrompt")
	view = m:FindFirstChild("TradeViewFrame")
	tf = m:FindFirstChild("TradeFrame")
	if list then
		list.Visible = false
		local btn = m:FindFirstChild("Buttons") and m.Buttons:FindFirstChild("Trade", true)
		if btn and btn:IsA("GuiButton") then btn.Activated:Connect(function()
			list.Visible = not list.Visible
			if list.Visible then refreshList() end
			SFX.Play(list.Visible and "Open" or "Close")
		end) end
		local cancel = list:FindFirstChild("Cancel", true)
		if cancel and cancel:IsA("GuiButton") then cancel.Activated:Connect(function() list.Visible = false SFX.Play("Close") end) end
		local search = list:FindFirstChild("Search")
		if search and search:IsA("TextBox") then search:GetPropertyChangedSignal("Text"):Connect(refreshList) end
	end
	if view then
		view.Visible = false
		-- other scripts (player profile > Inventory): TradeViewFrame.Show:Fire(player)
		local showEv = view:FindFirstChild("Show") or Instance.new("BindableEvent")
		showEv.Name = "Show" showEv.Parent = view
		showEv.Event:Connect(function(p) if typeof(p) == "Instance" and p:IsA("Player") then showView(p) end end)
		local c = view:FindFirstChild("Close", true)
		if c and c:IsA("GuiButton") then c.Activated:Connect(function() view.Visible = false if list then list.Visible = true refreshList() end end) end
		local tb = view:FindFirstChild("TradeButton")
		if tb and tb:IsA("GuiButton") then tb:SetAttribute("NoClickSound", true) tb.Activated:Connect(function() if viewing and viewing.Parent then request(viewing) end end) end
	end
	if prompt then
		prompt.Visible = false
		local a, d = prompt:FindFirstChild("AcceptButton", true), prompt:FindFirstChild("DeclineButton", true)
		if a then a:SetAttribute("NoClickSound", true) a.Activated:Connect(function() answer(true) end) end
		if d then d:SetAttribute("NoClickSound", true) d.Activated:Connect(function() answer(false) end) end
		local back = prompt:FindFirstChild("PadBack") or Instance.new("BindableEvent")
		back.Name = "PadBack" back.Parent = prompt
		back.Event:Connect(function() answer(false) end)
	end
	if tf then tf.Visible = false hookTrade() end
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
Players.PlayerAdded:Connect(function() if list and list.Visible then refreshList() end end)
Players.PlayerRemoving:Connect(function() task.defer(function() if list and list.Visible then refreshList() end end) end)
player:GetAttributeChangedSignal("BalloonInv"):Connect(function() refreshPicker() end)
-- no trading in a real match (the practice arena / aim training are fine: requests still come in there)
local function lobbyOnly()
	if player:GetAttribute("MatchId") ~= nil then
		if list then list.Visible = false end
		if view then view.Visible = false end
		closePrompt()
	elseif player:GetAttribute("InArena") then
		if list then list.Visible = false end
		if view then view.Visible = false end
	end
end
-- in first person (arena) the mouse is locked + hidden: free it while the trade window is open
local UIS = game:GetService("UserInputService")
local modal
RunService.Heartbeat:Connect(function()
	local open = tf and tf.Visible and tf.Parent ~= nil
	if open and not modal then
		modal = Instance.new("TextButton")
		modal.Name = "FreeMouse"
		modal.Text = ""
		modal.BackgroundTransparency = 1
		modal.Size = UDim2.fromOffset(0, 0)
		modal.Modal = true
		modal.Parent = tf
	elseif not open and modal then
		modal:Destroy()
		modal = nil
		if player:GetAttribute("InArena") then UIS.MouseIconEnabled = false end
	end
	if open and player:GetAttribute("InArena") and not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
end)
player:GetAttributeChangedSignal("MatchId"):Connect(lobbyOnly)
player:GetAttributeChangedSignal("InArena"):Connect(lobbyOnly)
