-- LEAVE BUTTON IN THE TOP BAR (TopbarPlus, ReplicatedStorage > TopbarPlus)
-- A round top-bar button with a white exit-door icon that takes you out of the practice arena.
-- Shows on MOBILE while you're in the practice arena (phones don't have the G key); PC keeps G / the LEAVE button.
-- Settings = attributes on this script: Image, ImageScale, Caption, MobileOnly (false = everyone gets it).
-- More TopbarPlus styling: https://1foreverhd.github.io/TopbarPlus/
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Icon = require(RS:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local LeaveArena = RS:WaitForChild("BalloonCombat"):WaitForChild("Remotes"):WaitForChild("LeaveArena")

local function isMobile()
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

local icon = Icon.new()
icon:setName("LeaveArena")
icon:setImage(script:GetAttribute("Image") or "rbxassetid://7059852436")
icon:setImageScale(script:GetAttribute("ImageScale") or 0.65)
if (script:GetAttribute("Caption") or "") ~= "" then icon:setCaption(script:GetAttribute("Caption")) end
icon:oneClick() -- a button, not a toggle
-- LOOK: round dark circle with the white icon, like Roblox's own top bar buttons
-- (colours / transparency = attributes Color and Transparency on this script)
icon:modifyTheme({
	{"IconCorners", "CornerRadius", UDim.new(1, 0)},
	{"IconButton", "BackgroundColor3", script:GetAttribute("Color") or Color3.fromRGB(18, 18, 21)},
	{"IconButton", "BackgroundTransparency", script:GetAttribute("Transparency") or 0.08},
	{"IconImage", "ImageColor3", Color3.new(1, 1, 1)},
})
icon.selected:Connect(function()
	if player:GetAttribute("InArena") and player:GetAttribute("MatchId") == nil then
		LeaveArena:FireServer()
	end
end)

local function update()
	local show = player:GetAttribute("InArena") == true and player:GetAttribute("MatchId") == nil
	if script:GetAttribute("MobileOnly") ~= false and not isMobile() then show = false end
	icon:setEnabled(show)
end
player:GetAttributeChangedSignal("InArena"):Connect(update)
player:GetAttributeChangedSignal("MatchId"):Connect(update)
UIS.LastInputTypeChanged:Connect(update)
update()
