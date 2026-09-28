-- SHOP: EXCLUSIVES + PASSES sections (Main > ShopFrame > ScrollingFrame). Everything shown: ReplicatedStorage > ShopConfig
--   ExclusiveSection1 > Frame   one card per ShopConfig.Exclusives line (the first card is the template):
--                               SkinName (balloon name), BalloonName ("Exclusive Balloon"), Tag, Time (time left), Buy, Gift,
--                               Shadow > Bar (rarity colour). The balloon's 3D model is added on the card.
--   PassesSection1 > <card>     one card per ShopConfig.Passes line: PassName, Perks, ImageLabel, ValueBadge, Tag, Buy, Gift
-- Buying: Exclusives = Developer Products, Passes = game passes (gifting a pass = its GiftProductId). ServerScriptService >
-- ShopServer gives them. Gifts use the shop's gift list (ShopFrame > GiftCrate event).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local ShopConfig = require(RS:WaitForChild("ShopConfig"))
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
local Purchase = require(RS:WaitForChild("Purchase"))
local SFX = require(RS:WaitForChild("SFX"))
local CardFX = require(RS:WaitForChild("BalloonSkins"):WaitForChild("CardFX"))

local function fmt(n) return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end
local function btnText(b, t) local l = b and b:FindFirstChild("Text") if l then setText(l, t) elseif b then setText(b, t) end end
local function robuxText(n) return "\u{E002} " .. fmt(n or 0) end
local function clock(sec)
	sec = math.max(0, math.floor(sec))
	local d, h, m, s = sec // 86400, sec % 86400 // 3600, sec % 3600 // 60, sec % 60
	if d > 0 then return ("%dd %02d:%02d:%02d"):format(d, h, m, s) end
	return ("%02d:%02d:%02d"):format(h, m, s)
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

-- the white outline on hover (same as the coin packs / chests)
local function hoverRing(card)
	if card:FindFirstChild("HoverRing") then return end
	local ring = Instance.new("Frame")
	ring.Name = "HoverRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.ZIndex = card.ZIndex + 5
	local rs = Instance.new("UIStroke") rs.Color = Color3.new(1, 1, 1) rs.Thickness = 2 rs.Transparency = 1 rs.Parent = ring
	local cc = card:FindFirstChildOfClass("UICorner") if cc then cc:Clone().Parent = ring end
	ring.Parent = card
	local function to(grow, alpha, t)
		local info = TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(ring, info, {Size = UDim2.new(1, grow, 1, grow)}):Play()
		TweenService:Create(rs, info, {Transparency = alpha}):Play()
	end
	card.MouseEnter:Connect(function() to(10, 0.15, 0.22) end)
	card.MouseLeave:Connect(function() to(0, 1, 0.2) end)
end

-- cards of a section, in reading order (the first is the template for extra ones)
local function cardsIn(section)
	local list = {}
	for _, c in section:GetChildren() do
		if c:IsA("GuiObject") and c:FindFirstChild("Buy") then table.insert(list, c) end
	end
	table.sort(list, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
		if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) > 4 then return a.AbsolutePosition.Y < b.AbsolutePosition.Y end
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	return list
end
-- exactly `n` cards: extra ones copied from the first, unused ones hidden
local function cardsFor(section, n)
	local list = cardsIn(section)
	local tpl = list[1]
	if not tpl then return {} end
	while #list < n do
		local c = tpl:Clone()
		c.LayoutOrder = tpl.LayoutOrder + #list
		c.Parent = section
		table.insert(list, c)
	end
	for i, c in list do c.Visible = i <= n end
	return list
end
local function gift(shop, id, productId)
	local ev = shop:FindFirstChild("GiftCrate")
	if ev then ev:Fire({Id = id, Price = {ProductId = productId}}) end
end

------------------------------------------------------------ EXCLUSIVES
local exCards = {} -- {card, entry, index}
local function showBalloon(card, id)
	local vp = card:FindFirstChild("BalloonView")
	if not vp then
		vp = Instance.new("ViewportFrame")
		vp.Name = "BalloonView"
		vp.BackgroundTransparency = 1
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.Position = UDim2.fromScale(0.5, 0.45)
		vp.Size = UDim2.fromScale(0.45, 0.6)
		vp.ZIndex = card.ZIndex + 1
		vp.Ambient = Color3.fromRGB(170, 170, 170)
		vp.LightDirection = Vector3.new(-1, -1.5, -1)
		local ar = Instance.new("UIAspectRatioConstraint") ar.Parent = vp
		vp.Parent = card
	end
	for _, c in vp:GetChildren() do if not c:IsA("UIComponent") then c:Destroy() end end
	local m = Skins.ForViewport(Skins.Model(id))
	if not m then return end
	m.CFrame = CFrame.new()
	m.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, m.Size.Y * 0.05, m.Size.Y * 2.6), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	CardFX.Attach(vp, id)
end

local function paintExclusives()
	for _, e in exCards do
		local x, card = e.entry, e.card
		local active = ShopConfig.ExclusiveActive(x)
		card.Visible = active
		if active then
			local Crates = require(RS:WaitForChild("Crates"):WaitForChild("CrateConfig"))
			local en = Crates.ParseTime(x.End)
			local t = card:FindFirstChild("Time")
			if t then t.Visible = en ~= nil if en then setText(t:FindFirstChild("Text") or t, clock(en - os.time())) end end
			local owned = false
			if ShopConfig.OwnedExclusiveText then
				local ok, inv = pcall(function() return game:GetService("HttpService"):JSONDecode(player:GetAttribute("BalloonInv") or "{}") end)
				owned = ok and type(inv) == "table" and (inv[x.Balloon] or 0) > 0
			end
			btnText(card:FindFirstChild("Buy"), owned and ShopConfig.OwnedExclusiveText or ((x.ProductId or 0) == 0 and (ShopConfig.NotSetUpText or "SOON") or robuxText(x.Robux)))
			local g = card:FindFirstChild("Gift") if g then g.Visible = (x.ProductId or 0) ~= 0 and ShopConfig.GiftingEnabled ~= false end
		end
	end
end

local function hookExclusives(shop, section)
	table.clear(exCards)
	local list = cardsFor(section, #(ShopConfig.Exclusives or {}))
	for i, x in ShopConfig.Exclusives or {} do
		local card = list[i]
		local s = Skins.Get(x.Balloon)
		local r = Skins.Rarities[s.Rarity] or Skins.Rarities.Common
		setText(card:FindFirstChild("SkinName"), s.Name)
		setText(card:FindFirstChild("BalloonName"), ((ShopConfig.ExclusiveTypeText or "{rarity} {type}"):gsub("{rarity}", r.Text):gsub("{type}", s.Type)))
		local tag = card:FindFirstChild("Tag")
		if tag then tag.Visible = (x.Tag or "") ~= "" btnText(tag, x.Tag or "") end
		local bar = card:FindFirstChild("Bar", true) if bar then bar.BackgroundColor3 = r.Color end
		showBalloon(card, x.Balloon)
		hoverRing(card)
		local buy = card:FindFirstChild("Buy")
		if buy and buy:IsA("GuiButton") then
			buy:SetAttribute("ClickSound", "")
			buy.Activated:Connect(function()
				if not ShopConfig.ExclusiveActive(x) then SFX.Play("Error") notice("That balloon isn't in the shop any more") return end
				if (x.ProductId or 0) == 0 then SFX.Play("Error") notice("This isn't available yet") return end
				Purchase.Product(x.ProductId)
			end)
		end
		local g = card:FindFirstChild("Gift")
		if g and g:IsA("GuiButton") then g.Activated:Connect(function() gift(shop, "Exclusive:" .. i, x.ProductId) end) end
		table.insert(exCards, {card = card, entry = x, index = i})
	end
	paintExclusives()
end

------------------------------------------------------------ PASSES
local passCards = {}
local function paintPasses()
	for _, e in passCards do
		local ps, card = e.entry, e.card
		local owned = player:GetAttribute("Pass_" .. ps.Name) == true
		btnText(card:FindFirstChild("Buy"), owned and (ShopConfig.OwnedText or "OWNED") or ((ps.Id or 0) == 0 and (ShopConfig.NotSetUpText or "SOON") or robuxText(ps.Robux)))
		local g = card:FindFirstChild("Gift") if g then g.Visible = (ps.GiftProductId or 0) ~= 0 and ShopConfig.GiftingEnabled ~= false end
	end
end
local function hookPasses(shop, section)
	table.clear(passCards)
	local list = cardsFor(section, #(ShopConfig.Passes or {}))
	for i, ps in ShopConfig.Passes or {} do
		local card = list[i]
		card.Name = "Pass_" .. ps.Name
		setText(card:FindFirstChild("PassName"), ps.Name)
		if ps.Perks then setText(card:FindFirstChild("Perks"), ps.Perks) end
		local img = card:FindFirstChild("ImageLabel")
		if img and (ps.Image or "") ~= "" then img.Image = ps.Image end
		local badge = card:FindFirstChild("ValueBadge")
		if badge then
			badge.Visible = (ps.Badge or "") ~= ""
			setText(badge:FindFirstChild("ValueLabel"), ps.Badge or "")
		end
		local tag = card:FindFirstChild("Tag")
		if tag then tag.Visible = (ps.Tag or "") ~= "" btnText(tag, ps.Tag or "") end
		hoverRing(card)
		local buy = card:FindFirstChild("Buy")
		if buy and buy:IsA("GuiButton") then
			buy:SetAttribute("ClickSound", "")
			buy.Activated:Connect(function()
				if player:GetAttribute("Pass_" .. ps.Name) then SFX.Play("Error") notice("You already own " .. ps.Name) return end
				if (ps.Id or 0) == 0 then SFX.Play("Error") notice("This pass isn't available yet") return end
				Purchase.GamePass(ps.Id)
			end)
		end
		local g = card:FindFirstChild("Gift")
		if g and g:IsA("GuiButton") then g.Activated:Connect(function() gift(shop, "Pass:" .. ps.Name, ps.GiftProductId) end) end
		player:GetAttributeChangedSignal("Pass_" .. ps.Name):Connect(paintPasses)
		table.insert(passCards, {card = card, entry = ps})
	end
	paintPasses()
end

------------------------------------------------------------ HOOK (again after every respawn)
local shopFrame
local function hook(main)
	local shop = main:WaitForChild("ShopFrame", 10)
	if not shop then return end
	shopFrame = shop
	local scroll = shop:WaitForChild("ScrollingFrame")
	task.wait() -- (let it lay out: cards are put in reading order by position)
	local ex = scroll:FindFirstChild("ExclusiveSection1")
	if ex then hookExclusives(shop, ex) end
	local ps = scroll:FindFirstChild("PassesSection1")
	if ps then hookPasses(shop, ps) end
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
player:GetAttributeChangedSignal("BalloonInv"):Connect(paintExclusives)

-- timers once a second; exclusive balloons turn slowly
task.spawn(function()
	while true do
		task.wait(1)
		if shopFrame and shopFrame.Visible then paintExclusives() end
	end
end)
