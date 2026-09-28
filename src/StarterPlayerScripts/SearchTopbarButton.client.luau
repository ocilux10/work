-- PLAYER SEARCH BUTTON IN THE ROBLOX TOP BAR (TopbarPlus, ReplicatedStorage > TopbarPlus)
-- A round dark magnifier right next to Roblox's menu / chat buttons. Click = open / close Main > SearchFrame.
-- Settings = attributes on this script: Image, ImageScale, Color, Transparency.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Icon = require(RS:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local icon = Icon.new()
icon:setName("PlayerSearch")
icon:setImage(script:GetAttribute("Image") or "rbxasset://textures/ui/SearchIcon.png")
icon:setImageScale(script:GetAttribute("ImageScale") or 0.55)
icon:align("Left")
icon:oneClick()
icon:modifyTheme({
	{"IconCorners", "CornerRadius", UDim.new(1, 0)},
	{"IconButton", "BackgroundColor3", script:GetAttribute("Color") or Color3.fromRGB(18, 18, 21)},
	{"IconButton", "BackgroundTransparency", script:GetAttribute("Transparency") or 0.08},
	{"IconImage", "ImageColor3", Color3.new(1, 1, 1)},
})
icon.selected:Connect(function()
	local main = player.PlayerGui:FindFirstChild("Main")
	local frame = main and main:FindFirstChild("SearchFrame")
	local toggle = frame and frame:FindFirstChild("ToggleSearch")
	if toggle then toggle:Fire() end
end)

-- lobby only: hidden in matches, the practice arena and aim training (both set InArena)
local function update() icon:setEnabled(player:GetAttribute("MatchId") == nil and not player:GetAttribute("InArena")) end
for _, a in {"MatchId", "InArena"} do player:GetAttributeChangedSignal(a):Connect(update) end
update()
