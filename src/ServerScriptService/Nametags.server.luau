-- NAMETAGS
-- Level | win-streak flame | device icon, then display name and @username, above every player's head.
-- Look: ReplicatedStorage > Matchmaking > NametagTemplate (a BillboardGui – restyle it freely).
--   The script fills these children if they exist (found anywhere inside the template):
--     Level (TextLabel)  Streak (Frame/TextLabel, hidden when the streak is 0) with a Value TextLabel inside
--     DeviceSlot (Frame – gets the PC / Mobile / Console icon)  DisplayName (TextLabel)  Username (TextLabel)
-- Hidden during real matches (lobby + practice arena only). Your own tag is visible to you in the lobby,
-- but hidden from you while you're in combat mode (practice arena) so it doesn't get in your view.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local MM = RS:WaitForChild("Matchmaking")
local PlayerCard = require(MM:WaitForChild("PlayerCard"))
local TEMPLATE_NAME = "NametagTemplate"

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local function refresh(player)
	local char = player.Character
	local tag = char and char:FindFirstChild("Nametag", true)
	if not tag then return end
	-- hidden in real matches
	tag.Enabled = player:GetAttribute("MatchId") == nil
	-- while you're fighting (combat mode, e.g. practice arena) you don't see your OWN tag –
	-- it would float in view when sprinting / jumping. Everyone else still sees it.
	tag.PlayerToHideFrom = player:GetAttribute("InArena") and player or nil

	local level = find(tag, "Level")
	if level and level:IsA("TextLabel") then level.Text = tostring(player:GetAttribute("Level") or 1) end

	local streakValue = player:GetAttribute("WinStreak") or 0
	local streak = find(tag, "Streak")
	if streak then
		if streak:IsA("GuiObject") then streak.Visible = streakValue > 0 end
		local v = streak:IsA("TextLabel") and streak or find(streak, "Value")
		if v and v:IsA("TextLabel") then v.Text = tostring(streakValue) end
	end

	local slot = find(tag, "DeviceSlot")
	if slot then
		local device = player:GetAttribute("Device") or "PC"
		if slot:GetAttribute("Shown") ~= device then
			slot:SetAttribute("Shown", device)
			for _, c in slot:GetChildren() do if c:GetAttribute("DeviceIcon") then c:Destroy() end end
			local icon = PlayerCard.DeviceIcon(device, slot)
			icon:SetAttribute("DeviceIcon", true)
		end
	end

	local dn = find(tag, "DisplayName")
	if dn and dn:IsA("TextLabel") then dn.Text = NameBadge.Of(player) end
	local un = find(tag, "Username")
	if un and un:IsA("TextLabel") then un.Text = "@" .. player.Name end
end

local function attach(player, char)
	local template = MM:FindFirstChild(TEMPLATE_NAME)
	if not template then warn("[Nametags] ReplicatedStorage > Matchmaking > NametagTemplate is missing") return end
	local head = char:WaitForChild("Head", 10)
	if not head or char.Parent == nil then return end
	local old = head:FindFirstChild("Nametag")
	if old then old:Destroy() end
	local tag = template:Clone()
	tag.Name = "Nametag"
	tag.Adornee = head
	tag.Parent = head
	refresh(player)
	-- (Enabled is set by refresh: off in matches)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char) attach(player, char) end)
	if player.Character then task.spawn(attach, player, player.Character) end
	for _, attr in {"Level", "WinStreak", "Device", "MatchId", "InArena"} do
		player:GetAttributeChangedSignal(attr):Connect(function() refresh(player) end)
	end
	player:GetPropertyChangedSignal("DisplayName"):Connect(function() refresh(player) end)
end

for _, p in Players:GetPlayers() do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)
