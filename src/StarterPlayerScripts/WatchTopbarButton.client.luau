-- SPECTATE / REPLAYS BUTTON IN THE ROBLOX TOP BAR (TopbarPlus, ReplicatedStorage > TopbarPlus)
-- A round dark camera next to the search button. Click = open / close Main > WatchFrame (Spectate + Replays tabs).
-- Settings = attributes on this script: Image, ImageScale, Color, Transparency.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Icon = require(RS:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local icon = Icon.new()
icon:setName("WatchMenu")
icon:setImage(script:GetAttribute("Image") or "rbxasset://textures/ui/ScreenshotHud/Camera.png")
icon:setImageScale(script:GetAttribute("ImageScale") or 0.6)
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
	local frame = main and main:FindFirstChild("WatchFrame")
	local toggle = frame and frame:FindFirstChild("ToggleWatch")
	if toggle then toggle:Fire() end
end)

-- lobby only: hidden in matches, the practice arena / aim training (InArena) and while you're already watching something
local function update()
	icon:setEnabled(player:GetAttribute("MatchId") == nil and not player:GetAttribute("InArena")
		and not player:GetAttribute("WatchingMatch") and not player:GetAttribute("WatchingReplay"))
end
for _, a in {"MatchId", "InArena", "WatchingMatch", "WatchingReplay"} do player:GetAttributeChangedSignal(a):Connect(update) end
update()
