-- CHESTS (client): the chest cards in the shop, the contents page, buying, opening and the spin.
-- Settings: ReplicatedStorage > Crates > CrateConfig. Chests are OWNED first (buy = +1), then opened (CrateServer).
--   Card (CratesSection1 > Crate): Tag > CrateName + CrateName (name), PriceCoins / PriceRobux (prices), OwnedAmount,
--         Timer, ChestView (3D chest). Clicking the card opens the crate view.
--   Crate view (ShopFrame > CrateView): BuyCoins / BuyRobux (+1 owned), Open ("Open (3)" = open one with the spin),
--         OpenAll (shows with 2+ owned: no spins, a results list at the end), Gift, Back.
--   Open All results: StarterGui > CrateOpening > Window > Results (+ Close) - the spin screen's window, without the strip.
--   Shop cards:     Main > ShopFrame > ScrollingFrame > CratesSection1 > Crate (the first one is the template, one is made
--                   per chest). Put a TextLabel named "Timer" in it to place the "LEAVES IN" text yourself.
--   Contents page:  Main > ShopFrame > CrateView (Templates > Item = one balloon + its %)
--   Spin:           StarterGui > CrateOpening (Templates > Cell = one balloon on the strip, Strip > Marker = the line)
-- Coin chests ask CrateServer (Crates > Remote); Robux chests are bought, then CrateServer fires Crates > Opened.
-- After the spin: the inspect screen (BalloonsClient.Inspect), then back to the shop.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("Crates")
local Config = require(folder:WaitForChild("CrateConfig"))
local Remote = folder:WaitForChild("Remote")
local Opened = folder:WaitForChild("Opened")
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local SFX = require(RS:WaitForChild("SFX"))
local Purchase = require(RS:WaitForChild("Purchase"))
local CardFX = require(RS:WaitForChild("BalloonSkins"):WaitForChild("CardFX"))

local function fmt(n) return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end
local function btnText(b, t) local l = b and b:FindFirstChild("Text") if l then setText(l, t) elseif b then setText(b, t) end end
local function fill(s, vars) return (s:gsub("{(%w+)}", function(k) return vars[k] ~= nil and tostring(vars[k]) or "{" .. k .. "}" end)) end

-- a chest can have a coin price, a Robux price, or both (CrateConfig > Price)
local function coinText(crate) return fill(Config.CoinPriceText or "{price} Coins", {price = fmt(crate.Price.Coins)}) end
local function robuxText(crate)
	if not Config.RobuxReady(crate) then return Config.NotSetUpText or "SOON" end
	return fill(Config.RobuxPriceText or "\u{E002} {price}", {price = fmt(crate.Price.Robux or 0)})
end
local function now() return workspace:GetServerTimeNow() end
-- "LEAVES IN 2d 5h" / "COMING IN 3h 12m" / nil
local function timerText(crate)
	local state = Config.State(crate)
	if state == "soon" then
		local s = Config.ParseTime(crate.Start)
		return s and fill(Config.ComingText, {time = Config.TimeText(s - now())})
	end
	local e = Config.ParseTime(crate.End)
	if e and Config.ShowLeavingTimer ~= false then return fill(Config.LeavingText, {time = Config.TimeText(e - now())}) end
	return nil
end

-- how many of a chest you own (CrateServer puts them on you as the attribute CrateInv)
local HttpService = game:GetService("HttpService")
local function owned(crateId)
	local ok, t = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("CrateInv") or "{}")
	return ok and type(t) == "table" and tonumber(t[crateId]) or 0
end

------------------------------------------------------------ 3D IN A VIEWPORT
-- a chest model (Crates > Models > <Model>) or a balloon, framed to fit. Returns the thing shown (to spin it).
local function clearVp(vp) for _, c in vp:GetChildren() do if not c:IsA("UIComponent") then c:Destroy() end end end
local function showChest(vp, crate)
	clearVp(vp)
	local m = Config.ModelFor(crate)
	if not m then return nil end
	if m:IsA("Model") and not m.PrimaryPart then m.PrimaryPart = m:FindFirstChildWhichIsA("BasePart", true) end
	m:PivotTo(CFrame.new())
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local r = size.Magnitude / 2
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = r / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, r * 0.45, dist), cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return m, cf.Position
end
local function showBalloon(vp, id)
	clearVp(vp)
	local m = Skins.ForViewport(Skins.Model(id))
	if not m then return end
	m.CFrame = CFrame.new()
	m.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, m.Size.Y * 0.05, m.Size.Y * 2.45), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	CardFX.Attach(vp, id)
end
-- balloon card look (spin cells + contents items share the same parts: SkinName / SkinType / Bar / RarityGlow / View)
local function paintBalloon(c, id)
	local s = Skins.Get(id)
	local r = Skins.Rarities[s.Rarity] or Skins.Rarities.Common
	setText(c:FindFirstChild("SkinName"), s.Name)
	setText(c:FindFirstChild("SkinType"), s.Rarity == "Default" and s.Type or (r.Text .. " " .. s.Type))
	local bar = c:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = r.Color end
	local glow = c:FindFirstChild("RarityGlow") if glow then glow.BackgroundColor3 = r.Color end
	local st = c:FindFirstChildOfClass("UIStroke") if st then st.Color = r.Color end
	local vp = c:FindFirstChild("View")
	if vp and vp:IsA("ViewportFrame") then showBalloon(vp, id) end
end

-- a white outline that grows out of a card on hover (same as the coin packs in ShopClient)
local function hoverRing(card, area)
	local ring = Instance.new("Frame")
	ring.Name = "HoverRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.ZIndex = area.ZIndex + 5
	local rs = Instance.new("UIStroke") rs.Color = Color3.new(1, 1, 1) rs.Thickness = 2 rs.Transparency = 1 rs.Parent = ring
	local cc = card:FindFirstChildOfClass("UICorner") if cc then cc:Clone().Parent = ring end
	ring.Parent = card
	local function to(grow, alpha, t)
		local info = TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(ring, info, {Size = UDim2.new(1, grow, 1, grow)}):Play()
		TweenService:Create(rs, info, {Transparency = alpha}):Play()
	end
	local hovering = false
	area.MouseEnter:Connect(function() hovering = true to(10, 0.15, 0.22) end)
	area.MouseLeave:Connect(function() hovering = false to(0, 1, 0.2) end)
	area.MouseButton1Down:Connect(function() to(4, 0.05, 0.08) end)
	area.MouseButton1Up:Connect(function() to(hovering and 10 or 0, hovering and 0.15 or 1, 0.2) end)
end


------------------------------------------------------------ STATE
local main, shop, scroll, section, cardTpl, view, itemTpl
local cardTpls = {} -- all the Crate card designs from Studio
local templateFor -- forward
local cards = {}        -- crateId -> {card, model, center, hover}
local shownIds = ""     -- which chests the cards were built for (rebuilt when one leaves / arrives)
local viewing           -- the chest open on the contents page
local viewModel, viewCenter
local spinning = false
local queue = {}        -- chests opened while another one was spinning (Robux / gifts)

local function notice(text)
	local n = main and main:FindFirstChild("DuelNotice")
	if not (n and n:IsA("TextLabel")) then return end
	n.Text = text
	n.Visible = true
	local token = (n:GetAttribute("Token") or 0) + 1
	n:SetAttribute("Token", token)
	task.delay(2.5, function() if n:GetAttribute("Token") == token then n.Visible = false end end)
end

------------------------------------------------------------ THE SPIN (StarterGui > CrateOpening)
local playSpin -- forward

-- BUY: +1 owned. how = "Coins" / "Robux"
local function buyCrate(crate, how)
	if Config.State(crate) ~= "open" then SFX.Play("Error") notice("This chest isn't in the shop") return end
	if how == "Robux" then
		if not Config.RobuxReady(crate) then SFX.Play("Error") notice("This chest isn't available yet") return end
		Purchase.Product(crate.Price.ProductId) -- (ShopServer -> CrateServer.Give: +1 owned)
		return
	end
	if not Config.HasCoins(crate) then SFX.Play("Error") notice("This chest is bought with Robux") return end
	if (player:GetAttribute("Coins") or 0) < crate.Price.Coins then
		SFX.Play("Error")
		notice(Config.NotEnoughCoinsText or "Not enough coins!")
		local open = shop and shop:FindFirstChild("OpenShop")
		if open then open:Fire("Coins") end
		return
	end
	local ok, res = Remote:InvokeServer("Buy", crate.Id)
	if not ok then SFX.Play("Error") notice(res or "Couldn't buy it") return end
	SFX.Play("Purchase")
	notice(fill(Config.BoughtText or "+1 {name}!", {name = crate.Name}))
end

-- OPEN one owned chest: the spin
local function openOne(crate)
	if spinning then return end
	if owned(crate.Id) < 1 then SFX.Play("Error") notice(Config.NoneOwnedText or "You don't have one - buy it first") return end
	spinning = true -- (blocks double clicks while the server answers)
	local ok, res = Remote:InvokeServer("Open", crate.Id)
	spinning = false
	if not ok then SFX.Play("Error") notice(res or "Couldn't open the chest") return end
	playSpin(crate, res)
end

local showResults -- forward (Open All's list)
-- OPEN ALL: no spins, everything at once, then the results list
local function openAll(crate)
	if spinning then return end
	if owned(crate.Id) < 2 then return openOne(crate) end
	spinning = true
	local ok, res = Remote:InvokeServer("OpenAll", crate.Id)
	spinning = false
	if not ok or type(res) ~= "table" then SFX.Play("Error") notice((not ok and res) or "Couldn't open them") return end
	showResults(crate, res)
end

-- weighted random balloon from a chest (only for the balloons flying past - the real roll is on the server)
local function fakeRoll(odds, total)
	local r = math.random() * total
	for _, e in odds do r -= e.Chance if r <= 0 then return e.Id end end
	return odds[#odds].Id
end

playSpin = function(crate, wonId, from)
	if spinning then table.insert(queue, {crate, wonId, from}) return end
	local gui = pg:FindFirstChild("CrateOpening")
	local window = gui and gui:FindFirstChild("Window")
	local strip = window and window:FindFirstChild("Strip")
	local track = strip and strip:FindFirstChild("Track")
	local cellTpl = gui and gui:FindFirstChild("Templates") and gui.Templates:FindFirstChild("Cell")
	if not (track and cellTpl) then
		-- no spin screen: just say what they got
		notice(fill(Config.Spin.WonText or "You got {balloon}!", {balloon = Skins.Get(wonId).Name}))
		return
	end
	spinning = true
	local S = Config.Spin
	local odds, total = Config.Odds(crate)
	if #odds == 0 then odds, total = {{Id = wonId, Chance = 1}}, 1 end

	-- hide the shop while it spins
	local shopWasOpen = shop and shop.Visible
	if main then main.Enabled = false end
	setText(window:FindFirstChild("Title"), from and fill(S.GiftedText or "{from} gifted you a {name}!", {from = from, name = crate.Name})
		or fill(S.TitleText or "Opening {name}...", {name = crate.Name}))

	-- build the strip
	for _, c in track:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	strip.ClipsDescendants = true
	track.AnchorPoint = Vector2.zero
	track.Size = UDim2.fromScale(1, 1)
	track.Position = UDim2.fromScale(0, 0)
	track.BackgroundTransparency = 1
	gui.Enabled = true
	local count = math.max(S.Cells or 55, 12)
	local winIndex = count - 4
	local gap = S.CellGap or 8
	local probe = cellTpl:Clone()
	probe.Parent = track
	task.wait() -- (let it lay out to read its size)
	local cw, ch = probe.AbsoluteSize.X, probe.AbsoluteSize.Y
	probe:Destroy()
	if cw < 4 then ch = strip.AbsoluteSize.Y * 0.9 cw = ch * 0.8 end
	local cellsList = {}
	for i = 1, count do
		local c = cellTpl:Clone()
		c.Name = "Cell" .. i
		c.AnchorPoint = Vector2.new(0, 0.5)
		c.Size = UDim2.fromOffset(cw, ch)
		c.Position = UDim2.new(0, (i - 1) * (cw + gap), 0.5, 0)
		c.Visible = true
		paintBalloon(c, i == winIndex and wonId or fakeRoll(odds, total))
		c.Parent = track
		cellsList[i] = c
	end
	-- where it stops: the winner under the line in the middle, a little off-centre so it feels random
	local half = strip.AbsoluteSize.X / 2
	local marker = strip:FindFirstChild("Marker")
	if marker then half = marker.AbsolutePosition.X + marker.AbsoluteSize.X / 2 - strip.AbsolutePosition.X end
	local jitter = (math.random() - 0.5) * cw * 0.7
	local finalX = (winIndex - 1) * (cw + gap) + cw / 2 + jitter - half
	local startX = -half + cw / 2 -- (first cell under the line)
	startX = math.min(startX, 0)

	local skip = window:FindFirstChild("Skip")
	if skip then skip.Visible = S.Skip ~= false end
	local skipped = false
	local skipConn = skip and skip:IsA("GuiButton") and skip.Activated:Connect(function() skipped = true end)

	-- spin: fast at first, slowing right down at the end (ticks every time a balloon passes the line)
	local dur = S.Time or 6
	local t0 = os.clock()
	local lastCell = -1
	while true do
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		if skipped then a = 1 end
		local e = 1 - (1 - a) ^ 4
		local x = startX + (finalX - startX) * e
		track.Position = UDim2.fromOffset(-x, 0)
		local under = math.floor((x + half) / (cw + gap))
		if under ~= lastCell then
			lastCell = under
			if not skipped and S.TickSound and S.TickSound ~= "" then SFX.Play(S.TickSound) end
		end
		if a >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	if skipConn then skipConn:Disconnect() end
	if skip then skip.Visible = false end

	-- landed: the winner pops, the rest fade
	if S.WinSound and S.WinSound ~= "" then SFX.Play(S.WinSound) end
	local winner = cellsList[winIndex]
	local pop = Instance.new("UIScale") pop.Parent = winner
	winner.ZIndex += 2
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = S.WinnerPop or 1.12}):Play()
	for i, c in cellsList do
		if i ~= winIndex then
			TweenService:Create(c, TweenInfo.new(0.3), {BackgroundTransparency = math.max(c.BackgroundTransparency, 0.6)}):Play()
			local vp = c:FindFirstChild("View")
			if vp then TweenService:Create(vp, TweenInfo.new(0.3), {ImageTransparency = 0.6}):Play() end
		end
	end
	setText(window:FindFirstChild("Title"), fill(S.WonText or "You got {balloon}!", {balloon = Skins.Get(wonId).Name}))
	task.wait(S.RevealTime or 1.2)

	gui.Enabled = false
	for _, c in track:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	-- straight into the inspect screen (it brings the shop back when you press Stop)
	local inspect = S.InspectAfter ~= false and player:FindFirstChild("PlayerScripts")
		and player.PlayerScripts:FindFirstChild("BalloonsClient") and player.PlayerScripts.BalloonsClient:FindFirstChild("Inspect")
	local canInspect = inspect and not player:GetAttribute("InArena") and player:GetAttribute("MatchId") == nil
	if main then main.Enabled = true end
	if canInspect then
		inspect:Fire(wonId, shopWasOpen and shop or nil)
	elseif shopWasOpen and shop then
		shop.Visible = true
	end
	spinning = false
	-- next one waiting (Robux chests bought / gifted during the spin)
	local nxt = table.remove(queue, 1)
	if nxt then
		task.wait(0.5) -- (let the inspect screen open first)
		repeat task.wait(0.2) until not player:GetAttribute("InspectingBalloon")
		playSpin(nxt[1], nxt[2], nxt[3])
	end
end

Opened.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local crate = Config.ById[data.Crate]
	if crate and data.Stored then
		-- a chest arrived in your inventory (Robux purchase, gift, reward)
		SFX.Play("Notify")
		notice(data.From and fill(Config.GiftedStoredText or "{from} gifted you a {name}!", {from = data.From, name = crate.Name})
			or fill(Config.BoughtText or "+1 {name}!", {name = crate.Name}))
		return
	end
	if crate and Skins.ById[data.Id] then
		-- (after the Robux purchase screen has gone)
		task.delay(1.2, playSpin, crate, data.Id, data.From)
	end
end)

------------------------------------------------------------ OPEN ALL RESULTS (CrateOpening > Window > Results)
-- the same window as the spin: Title, Results (a grid of cells from Templates > Cell, "x3" in each cell's Count), Close.
-- Hides by itself after Spin.ResultsTime seconds (or Close / Skip).
showResults = function(crate, ids)
	local gui = pg:FindFirstChild("CrateOpening")
	local window = gui and gui:FindFirstChild("Window")
	local results = window and window:FindFirstChild("Results")
	local cellTpl = gui and gui:FindFirstChild("Templates") and gui.Templates:FindFirstChild("Cell")
	-- count them, rarest first
	local counts, order = {}, {}
	for _, id in ids do
		if not counts[id] then counts[id] = 0 table.insert(order, id) end
		counts[id] += 1
	end
	table.sort(order, function(x, y)
		local rx, ry = Skins.Rarity(x).Order or 0, Skins.Rarity(y).Order or 0
		if rx ~= ry then return rx > ry end
		return counts[x] > counts[y]
	end)
	if not (results and cellTpl) then
		local bits = {}
		for _, id in order do table.insert(bits, counts[id] .. "x " .. Skins.Get(id).Name) end
		notice(table.concat(bits, ", "))
		return
	end
	spinning = true
	local shopWasOpen = shop and shop.Visible
	if main then main.Enabled = false end
	local strip, skip = window:FindFirstChild("Strip"), window:FindFirstChild("Skip")
	if strip then strip.Visible = false end
	if skip then skip.Visible = false end
	for _, c in results:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	for i, id in order do
		local c = cellTpl:Clone()
		c.Name = "Result_" .. id
		c.LayoutOrder = i
		c.Visible = true
		paintBalloon(c, id)
		local n = c:FindFirstChild("Count")
		if n then n.Visible = counts[id] > 1 setText(n, "x" .. counts[id]) end
		c.Parent = results
	end
	setText(window:FindFirstChild("Title"), fill(Config.Spin.ResultsText or "You opened {n} {name}s!", {n = #ids, name = crate.Name}))
	results.Visible = true
	results.CanvasPosition = Vector2.zero
	gui.Enabled = true
	SFX.Play(Config.Spin.WinSound or "QuestComplete")
	-- close: the button, or by itself
	local done = false
	local close = window:FindFirstChild("Close")
	if close then close.Visible = true end
	local conn = close and close:IsA("GuiButton") and close.Activated:Connect(function() done = true end)
	local t0 = os.clock()
	repeat task.wait(0.1) until done or os.clock() - t0 >= (Config.Spin.ResultsTime or 6)
	if conn then conn:Disconnect() end
	gui.Enabled = false
	results.Visible = false
	if close then close.Visible = false end
	if strip then strip.Visible = true end
	for _, c in results:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	if main then main.Enabled = true end
	if shopWasOpen and shop then shop.Visible = true end
	spinning = false
end

------------------------------------------------------------ GIFTING A CHEST (coins or Robux)
-- Main > CrateGiftFrame (the player list; made from Main > GiftFrame if it isn't in StarterGui). Each player row
-- (ScrollingFrame > Frame = the template) has Gift = pay with coins and GiftRobux = pay with Robux, side by side.
-- Coins: CrateServer takes your coins and the other player gets the spin. Robux: a purchase (ShopServer gives it).
local NameBadge = require(RS:WaitForChild("NameBadge"))
local ShopConfigMod = require(RS:WaitForChild("ShopConfig"))
local ShopRemote = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes"):WaitForChild("Shop")
local giftUI, giftRows = nil, {}
local function canGiftAny(crate)
	return ShopConfigMod.GiftingEnabled ~= false and Config.State(crate) == "open" and (Config.HasCoins(crate) or Config.RobuxReady(crate))
end
local function closeGift(backToShop)
	if giftUI then giftUI.Visible = false end
	if backToShop and shop then shop.Visible = true end
end
-- the gift UI (in StarterGui, or made from GiftFrame the first time)
local function giftFrame()
	if giftUI and giftUI.Parent then return giftUI end
	giftUI = main and main:FindFirstChild("CrateGiftFrame")
	if not giftUI then
		local src = main and main:FindFirstChild("GiftFrame")
		if not src then return nil end
		giftUI = src:Clone()
		giftUI.Name = "CrateGiftFrame"
		local row = giftUI:FindFirstChild("ScrollingFrame") and giftUI.ScrollingFrame:FindFirstChild("Frame")
		local b = row and (row:FindFirstChild("Gift") or row:FindFirstChildWhichIsA("GuiButton"))
		if b and not row:FindFirstChild("GiftRobux") then
			b.Name = "Gift"
			local rb = b:Clone()
			rb.Name = "GiftRobux"
			local w = b.Size
			rb.Position = b.Position - UDim2.new(w.X.Scale * 1.08, w.X.Offset * 1.08 + (w.X.Offset == 0 and 0 or 6), 0, 0)
			rb.Parent = row
		end
		giftUI.Parent = main
	end
	giftUI.Visible = false
	local cancel = giftUI:FindFirstChild("Cancel", true)
	if cancel and cancel:IsA("GuiButton") then cancel.Activated:Connect(function() closeGift(true) end) end
	return giftUI
end
local function openGift(crate)
	if not canGiftAny(crate) then SFX.Play("Error") return end
	local ui = giftFrame()
	local sc = ui and ui:FindFirstChild("ScrollingFrame")
	local tpl = sc and sc:FindFirstChild("Frame")
	if not tpl then SFX.Play("Error") return end
	tpl.Visible = false
	for _, r in giftRows do r:Destroy() end
	table.clear(giftRows)
	local any = false
	for i, p in Players:GetPlayers() do
		if p ~= player then
			any = true
			local r = tpl:Clone()
			r.Name = "Row_" .. p.UserId
			r.Visible = true
			r.LayoutOrder = i
			local u, d = r:FindFirstChild("Username"), r:FindFirstChild("Display")
			if u then u.Text = NameBadge.Of(p) end
			if d then d.Text = "@" .. p.Name end
			local av = r:FindFirstChild("Avatar")
			if av and av:IsA("ImageLabel") then av.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(p.UserId) end
			local closed = p:GetAttribute("Pref_AcceptGifts") == false
			local b, rb = r:FindFirstChild("Gift"), r:FindFirstChild("GiftRobux")
			if b and b:IsA("GuiButton") then
				b.Visible = Config.HasCoins(crate)
				btnText(b, closed and "Off" or coinText(crate))
				b.Activated:Connect(function()
					local ok, msg = Remote:InvokeServer("GiftCoins", crate.Id, p)
					SFX.Play(ok and "QuestComplete" or "Error")
					notice(msg or (ok and "Gifted!" or "Couldn't gift"))
					if ok then closeGift(true) end
				end)
			end
			if rb and rb:IsA("GuiButton") then
				rb.Visible = Config.RobuxReady(crate)
				rb:SetAttribute("ClickSound", "")
				btnText(rb, closed and "Off" or robuxText(crate))
				rb.Activated:Connect(function()
					local ok, why = ShopRemote:InvokeServer("StartGift", {Target = p, Crate = crate.Id})
					if not ok then SFX.Play("Error") notice(why or "Can't gift right now") return end
					closeGift(false)
					Purchase.Product(crate.Price.ProductId)
					-- back to the shop once the purchase window is done
					local conn
					conn = game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(uid)
						if uid ~= player.UserId then return end
						conn:Disconnect()
						task.wait(0.8)
						if shop then shop.Visible = true end
					end)
				end)
			end
			r.Parent = sc
			table.insert(giftRows, r)
		end
	end
	local empty = sc:FindFirstChild("Empty") if empty then empty.Visible = not any end
	if shop then shop.Visible = false end
	ui.Visible = true
	SFX.Play("Open")
end

------------------------------------------------------------ CONTENTS PAGE (ShopFrame > CrateView)
local function setViewOpen(on)
	if not view then return end
	view.Visible = on
	if scroll then scroll.Visible = not on end
	if not on then viewing = nil viewModel = nil end
end

local function paintView()
	local crate = viewing
	if not (view and crate) then return end
	setText(view:FindFirstChild("Title"), crate.Name)
	local t = timerText(crate)
	local tl = view:FindFirstChild("Timer")
	if tl then tl.Visible = t ~= nil if t then setText(tl, t) end end
	local state = Config.State(crate)
	local n = owned(crate.Id)
	-- buy buttons (BuyCoins: its Text = the number, the coin icon is in the design)
	local bc, br = view:FindFirstChild("BuyCoins"), view:FindFirstChild("BuyRobux")
	if bc then bc.Visible = Config.HasCoins(crate) and state == "open" btnText(bc, Config.HasCoins(crate) and fmt(crate.Price.Coins) or "") end
	if br then br.Visible = Config.HasRobux(crate) and state == "open" btnText(br, robuxText(crate)) end
	-- open (owned)
	local open = view:FindFirstChild("Open")
	if open then
		btnText(open, fill(Config.OpenText or "Open ({n})", {n = n}))
		open.AutoButtonColor = n > 0
		local grey = open:FindFirstChild("NoneTint")
		if n < 1 and not grey then
			grey = Instance.new("UIGradient") grey.Name = "NoneTint" grey.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120)) grey.Parent = open
		elseif n > 0 and grey then grey:Destroy() end
	end
	local all = view:FindFirstChild("OpenAll")
	if all then all.Visible = n >= 2 btnText(all, fill(Config.OpenAllText or "Open All ({n})", {n = math.min(n, Config.MaxOpenAll or 100)})) end
	local orb = view:FindFirstChild("OpenRobux") if orb then orb.Visible = false end -- (old button: not used any more)
	local gift = view:FindFirstChild("Gift")
	if gift then gift.Visible = canGiftAny(crate) end
end

local function openView(crate)
	if not view then return end
	viewing = crate
	setViewOpen(true)
	local chestVp = view:FindFirstChild("ChestView")
	if chestVp and chestVp:IsA("ViewportFrame") then viewModel, viewCenter = showChest(chestVp, crate) end
	setText(view:FindFirstChild("OddsLabel"), Config.OddsText or "1 balloon per open")
	local items = view:FindFirstChild("Items")
	if items and itemTpl then
		for _, c in items:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		for i, e in Config.Odds(crate) do
			local c = itemTpl:Clone()
			c.Name = "Item_" .. e.Id
			c.LayoutOrder = i
			c.Visible = true
			paintBalloon(c, e.Id)
			setText(c:FindFirstChild("Percent"), Config.PercentText(e.Percent))
			c.Parent = items
		end
		items.CanvasPosition = Vector2.zero
	end
	paintView()
	SFX.Play("Open")
end

------------------------------------------------------------ SHOP CARDS
local function paintCard(entry, crate)
	local card = entry.card
	for _, d in card:GetDescendants() do
		if d.Name == "CrateName" then setText(d, crate.Name) end
	end
	-- (only one card design: tint it with the chest's Color. Several designs: each keeps its own colours from Studio)
	if #cardTpls <= 1 and crate.Color then
		local tag = card:FindFirstChild("Tag")
		if tag then tag.BackgroundColor3 = crate.Color end
		local bar = card:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = crate.Color end
	end
	local state = Config.State(crate)
	local pc, pr = card:FindFirstChild("PriceCoins"), card:FindFirstChild("PriceRobux")
	if pc then pc.Visible = Config.HasCoins(crate) if Config.HasCoins(crate) then setText(pc, fmt(crate.Price.Coins)) end end
	if pr then pr.Visible = Config.HasRobux(crate) setText(pr, Config.RobuxReady(crate) and ("\u{E002}" .. fmt(crate.Price.Robux or 0)) or (Config.NotSetUpText or "SOON")) end
	setText(card:FindFirstChild("OwnedAmount"), fill(Config.OwnedText or "Owned ({n})", {n = owned(crate.Id)}))
	if state == "soon" then setText(card:FindFirstChild("OwnedAmount"), "SOON") end
	local t = timerText(crate)
	local tl = card:FindFirstChild("Timer")
	if tl then tl.Visible = t ~= nil if t then setText(tl, t) end end
end


-- which design card a chest uses: the one whose shadow colour (Shadow > UIGradient, else the Bar) is closest to the
-- chest's Color in CrateConfig - so each chest keeps its own shadow / bar colours from Studio
local function cardColor(card)
	local sh = card:FindFirstChild("Shadow")
	local g = sh and sh:FindFirstChildOfClass("UIGradient")
	if g then local k = g.Color.Keypoints return k[#k].Value end
	local bar = card:FindFirstChild("Bar")
	local bg = bar and bar:FindFirstChildOfClass("UIGradient")
	if bg then local k = bg.Color.Keypoints return k[#k].Value end
	return Color3.new(1, 1, 1)
end
templateFor = function(crate)
	if #cardTpls <= 1 or not crate.Color then return cardTpl end
	local best, bestD
	for _, t in cardTpls do
		local c = cardColor(t)
		local d = (c.R - crate.Color.R) ^ 2 + (c.G - crate.Color.G) ^ 2 + (c.B - crate.Color.B) ^ 2
		if not bestD or d < bestD then best, bestD = t, d end
	end
	return best or cardTpl
end

local function buildCards()
	if not (section and cardTpl) then return end
	for _, e in cards do e.card:Destroy() end
	table.clear(cards)
	local list = Config.Visible()
	local ids = {}
	for i, crate in list do
		table.insert(ids, crate.Id .. ":" .. Config.State(crate))
		local card = templateFor(crate):Clone()
		card.Name = "Crate_" .. crate.Id
		-- the shadow also tinted with its own gradient colour (so its colour shows even if the gradient doesn't)
		local sh = card:FindFirstChild("Shadow")
		if sh and sh:IsA("ImageLabel") then sh.ImageColor3 = cardColor(sh.Parent) end
		card.LayoutOrder = i
		card.Visible = true
		local entry = {card = card}
		cards[crate.Id] = entry
		-- the chest model on the card (a ViewportFrame over the picture; the picture stays if the model is missing)
		local img = card:FindFirstChild("CrateImage")
		local vp = card:FindFirstChild("ChestView") -- (in StarterGui: the Crate card's ChestView)
		if not vp and img then
			vp = Instance.new("ViewportFrame")
			vp.Name = "ChestView"
			vp.BackgroundTransparency = 1
			vp.AnchorPoint, vp.Position, vp.Size = img.AnchorPoint, img.Position, img.Size
			vp.ZIndex = img.ZIndex
			vp.Ambient = Color3.fromRGB(170, 170, 170)
			vp.LightColor = Color3.new(1, 1, 1)
			vp.LightDirection = Vector3.new(-1, -1.5, -1)
			vp.Parent = card
		end
		if vp then
			entry.model, entry.center = showChest(vp, crate)
			if img then img.Visible = entry.model == nil end
		end
		-- whole card = contents page (Buy / Gift sit on top and keep working)
		local area = Instance.new("TextButton")
		area.Name = "ClickArea"
		area.Text = ""
		area.BackgroundTransparency = 1
		area.Size = UDim2.fromScale(1, 1)
		area.ZIndex = card.ZIndex
		area.AutoButtonColor = false
		area.Parent = card
		for _, n in {"Buy", "Gift"} do
			local b = card:FindFirstChild(n)
			if b and b.ZIndex <= area.ZIndex then b.ZIndex = area.ZIndex + 1 end
		end
		area.MouseEnter:Connect(function() entry.hover = true end)
		area.MouseLeave:Connect(function() entry.hover = false end)
		if Config.Card.HoverOutline ~= false then hoverRing(card, area) end
		-- the card = the crate view (buy / open / open all / gift are there)
		area.Activated:Connect(function() openView(crate) end)
		paintCard(entry, crate)
		card.Parent = section
	end
	shownIds = table.concat(ids, ",")
end

-- once a second: timers + chests leaving / arriving
task.spawn(function()
	while true do
		task.wait(1)
		if section and shop and shop.Parent then
			local ids = {}
			for _, crate in Config.Visible() do table.insert(ids, crate.Id .. ":" .. Config.State(crate)) end
			if table.concat(ids, ",") ~= shownIds then
				buildCards()
				if viewing and Config.State(viewing) == "hidden" then setViewOpen(false) end
			else
				for id, e in cards do paintCard(e, Config.ById[id]) end
			end
			if viewing then paintView() end
		end
	end
end)

-- the chests turn slowly (faster while hovered)
RunService.RenderStepped:Connect(function(dt)
	if not (shop and shop.Visible) then return end
	local C = Config.Card
	for _, e in cards do
		if e.model and e.model.Parent then
			local speed = e.hover and (C.HoverSpin or 90) or (C.ModelSpin or 20)
			if speed ~= 0 then
				e.model:PivotTo(CFrame.new(e.center) * CFrame.Angles(0, math.rad(speed) * dt, 0) * CFrame.new(-e.center) * e.model:GetPivot())
			end
		end
	end
	if viewModel and viewModel.Parent and viewCenter then
		viewModel:PivotTo(CFrame.new(viewCenter) * CFrame.Angles(0, math.rad(C.ModelSpin or 20) * dt, 0) * CFrame.new(-viewCenter) * viewModel:GetPivot())
	end
end)

------------------------------------------------------------ HOOK THE SHOP (again after every respawn)
local function hook(m)
	main = m
	shop = m:WaitForChild("ShopFrame", 10)
	if not shop then return end
	scroll = shop:WaitForChild("ScrollingFrame")
	section = scroll:WaitForChild("CratesSection1", 10)
	view = shop:FindFirstChild("CrateView")
	table.clear(cards)
	shownIds = ""
	viewing = nil
	-- the first Crate card is the template, any other copies made in Studio go
	if section then
		-- every Crate card in Studio is a design (its colours are matched to a chest in templateFor)
		table.clear(cardTpls)
		for _, c in section:GetChildren() do
			if c:IsA("GuiObject") and (c:FindFirstChild("OwnedAmount") or c:FindFirstChild("ChestView") or c:FindFirstChild("CrateImage") or c:FindFirstChild("Buy")) then
				table.insert(cardTpls, c)
			end
		end
		cardTpl = cardTpls[1]
		for _, t in cardTpls do t.Visible = false t.Parent = nil end
	end
	if view then
		local tpls = view:FindFirstChild("Templates")
		itemTpl = tpls and tpls:FindFirstChild("Item")
		if itemTpl then itemTpl.Visible = false end
		view.Visible = false
		local back = view:FindFirstChild("Back")
		if back and back:IsA("GuiButton") then back.Activated:Connect(function() setViewOpen(false) SFX.Play("Close") end) end
		local function on(name, fn)
			local b = view:FindFirstChild(name)
			if b and b:IsA("GuiButton") then b.Activated:Connect(function() if viewing then fn(viewing) end end) end
			return b
		end
		on("Open", openOne)
		on("OpenAll", openAll)
		on("BuyCoins", function(c) buyCrate(c, "Coins") end)
		local br = on("BuyRobux", function(c) buyCrate(c, "Robux") end)
		if br then br:SetAttribute("ClickSound", "") end -- (the "Purchase" ring plays instead)
		local orb = view:FindFirstChild("OpenRobux") if orb then orb.Visible = false end
		local gift = view:FindFirstChild("Gift")
		if gift and gift:IsA("GuiButton") then
			gift.Activated:Connect(function() if viewing then openGift(viewing) end end)
		end
		-- closing the shop / a top tab = back to the list
		shop:GetPropertyChangedSignal("Visible"):Connect(function()
			if not shop.Visible and not player:GetAttribute("InspectingBalloon") and not spinning then setViewOpen(false) end
		end)
		local tabs = shop:FindFirstChild("TopBar") and shop.TopBar:FindFirstChild("Tabs")
		if tabs then
			for _, b in tabs:GetChildren() do
				if b:IsA("GuiButton") then b.Activated:Connect(function() setViewOpen(false) end) end
			end
		end
	end
	buildCards()
end

-- the spin screen starts hidden
task.spawn(function()
	local g = pg:WaitForChild("CrateOpening", 30)
	if g then
		g.Enabled = false
		local tpls = g:FindFirstChild("Templates")
		if tpls then for _, c in tpls:GetChildren() do if c:IsA("GuiObject") then c.Visible = false end end end
	end
end)
pg.ChildAdded:Connect(function(c)
	if c.Name == "CrateOpening" and c:IsA("ScreenGui") and not spinning then c.Enabled = false end
end)

player:GetAttributeChangedSignal("CrateInv"):Connect(function()
	for id, e in cards do paintCard(e, Config.ById[id]) end
	if viewing then paintView() end
end)

local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
