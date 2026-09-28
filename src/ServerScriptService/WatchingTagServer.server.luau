-- WATCHING TAG: a tag over the head of anyone watching a replay or spectating a match, so other players can see
-- why they're standing still. Look: ReplicatedStorage > WatchingTag (restyle freely; its ReplayText / SpectateText
-- attributes are the texts). The pulse / float animation: StarterPlayerScripts > WatchingTagFX.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local template = RS:WaitForChild("WatchingTag")

local function update(p)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	local old = head and head:FindFirstChild("WatchingTag")
	local mode = (p:GetAttribute("WatchingReplay") and "Replay") or (p:GetAttribute("WatchingMatch") and "Spectate") or nil
	if not mode or not head then
		if old then old:Destroy() end
		return
	end
	local tag = old or template:Clone()
	tag.Name = "WatchingTag"
	local label = tag:FindFirstChild("Label", true)
	if label then label.Text = template:GetAttribute(mode .. "Text") or "WATCHING" end
	tag.Adornee = head
	tag.Parent = head
	CollectionService:AddTag(tag, "WatchingTag")
end
local function hook(p)
	p:GetAttributeChangedSignal("WatchingReplay"):Connect(function() update(p) end)
	p:GetAttributeChangedSignal("WatchingMatch"):Connect(function() update(p) end)
	p.CharacterAdded:Connect(function(c) c:WaitForChild("Head", 5) update(p) end)
	update(p)
end
Players.PlayerAdded:Connect(hook)
for _, p in Players:GetPlayers() do hook(p) end
