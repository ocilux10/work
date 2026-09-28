-- ROBUX PURCHASES with a loading screen (StarterGui > PurchaseLoading: dark overlay + spinning circle + blur)
--   local Purchase = require(game.ReplicatedStorage.Purchase)
--   Purchase.Product(productId)   -- developer products (coin packs ...)
--   Purchase.GamePass(passId)     -- game passes
-- Shows "Waiting for purchase..." while Roblox's buy window is open, "Processing..." after a buy until
-- the reward arrives (Coins go up), then "Purchase complete!". Cancel = closes straight away.
-- SOUND: "Purchase" in ReplicatedStorage > SoundConfig (plays instead of the normal button click).
-- TIMINGS: ReplicatedStorage > ShopConfig > Purchase (ProcessingMaxTime, CompleteShowTime, ShowComplete).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local SFX = require(game:GetService("ReplicatedStorage"):WaitForChild("SFX"))
local ShopConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))
local function cfg(name, default)
	local c = ShopConfig.Purchase
	local v = c and c[name]
	if v == nil then return default end
	return v
end
local function buySound()
	SFX.Play("Purchase") -- ReplicatedStorage > SoundConfig > Purchase
end
local Purchase = {}
local busy = false
local spinConn
local token = 0

local function ui() return player:WaitForChild("PlayerGui"):WaitForChild("PurchaseLoading", 5) end
local function blur()
	local b = Lighting:FindFirstChild("PurchaseBlur")
	if not b then
		b = Instance.new("BlurEffect")
		b.Name = "PurchaseBlur"
		b.Size = 0
		b.Parent = Lighting
	end
	return b
end
local function setText(s)
	local g = ui()
	local t = g and g:FindFirstChild("Text", true)
	if t then t.Text = s end
end

local function show()
	local g = ui()
	if not g then return end
	token += 1
	g.Enabled = true
	local ov = g:FindFirstChild("Overlay")
	local box = ov and ov:FindFirstChild("Box")
	if ov then
		ov.BackgroundTransparency = 1
		TweenService:Create(ov, TweenInfo.new(0.25), {BackgroundTransparency = 0.45}):Play()
	end
	if box then
		local s = box:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = box
		s.Scale = 0.8
		TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end
	TweenService:Create(blur(), TweenInfo.new(0.3), {Size = 16}):Play()
	local spinner = g:FindFirstChild("Spinner", true)
	if spinConn then spinConn:Disconnect() end
	spinConn = RunService.RenderStepped:Connect(function(dt)
		if spinner then spinner.Rotation = (spinner.Rotation + dt * 360) % 360 end
	end)
end

local function hide(delay)
	local my = token
	task.delay(delay or 0, function()
		if my ~= token then return end
		local g = ui()
		local ov = g and g:FindFirstChild("Overlay")
		TweenService:Create(blur(), TweenInfo.new(0.25), {Size = 0}):Play()
		if ov then TweenService:Create(ov, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play() end
		task.wait(0.2)
		if my ~= token then return end
		if g then g.Enabled = false end
		if spinConn then spinConn:Disconnect() spinConn = nil end
		busy = false
	end)
end

-- after "bought": wait for the reward to land (coins change) so the player sees it worked
local attr = cfg
local function complete()
	if attr("ShowComplete", true) == false then hide() return end
	setText("Purchase complete!")
	hide(attr("CompleteShowTime", 0.6))
end
local function finish(bought, isPass)
	if not bought then hide() return end
	if isPass then complete() return end -- (a game pass has no coins to wait for)
	setText("Processing...")
	local before = player:GetAttribute("Coins")
	local t0 = os.clock()
	local maxWait = attr("ProcessingMaxTime", 1.5)
	task.spawn(function()
		while os.clock() - t0 < maxWait and player:GetAttribute("Coins") == before do task.wait(0.05) end
		complete()
	end)
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, bought)
	if userId == player.UserId and busy then finish(bought) end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, _, bought)
	if p == player and busy then finish(bought, true) end
end)

function Purchase.Product(productId)
	if busy then return end
	busy = true
	buySound()
	setText("Waiting for purchase...")
	show()
	local ok = pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
	if not ok then hide() end
	-- safety: never stay stuck
	local my = token
	task.delay(90, function() if busy and my == token then hide() end end)
end

function Purchase.GamePass(passId)
	if busy then return end
	busy = true
	buySound()
	setText("Waiting for purchase...")
	show()
	local ok = pcall(function() MarketplaceService:PromptGamePassPurchase(player, passId) end)
	if not ok then hide() end
	local my = token
	task.delay(90, function() if busy and my == token then hide() end end)
end

return Purchase
