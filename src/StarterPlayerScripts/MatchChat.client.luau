-- MATCH CHAT (client)
-- In a match the server puts you in a private channel with only the players in your match (and takes you out of
-- the lobby chat). This makes the chat box send to that channel, and styles match messages:
--   [You] name: text     (tag + name green, text white)
--   [Team] name: text    (tag + name green, text white - teammates in 2v2 / 3v3 / 4v4)
--   [Enemy] name: text   (all white)
-- Back in the lobby everything goes back to normal.
-- Colours: attributes on this script, MyTeamColor / EnemyTeamColor (Color3).
-- Tags: attributes YouTag / TeamTag / EnemyTag (e.g. "[You]").

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local player = Players.LocalPlayer
local GREEN = script:GetAttribute("MyTeamColor") or Color3.fromRGB(70, 230, 110)
local ENEMY = script:GetAttribute("EnemyTeamColor") or Color3.fromRGB(255, 0, 0)
local function tag(name, default) return script:GetAttribute(name) or default end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function channel(name)
	local folder = TextChatService:FindFirstChild("TextChannels")
	return folder and name and folder:FindFirstChild(name)
end

-- which channel the chat box sends to
local function updateTarget()
	local cfg = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if not cfg then return end
	local name = player:GetAttribute("MatchChannel")
	local target = name and channel(name)
	-- the channel can take a moment to show up
	local t0 = os.clock()
	while name and not target and os.clock() - t0 < 5 do
		task.wait(0.2)
		target = channel(name)
	end
	-- only send to the match channel once we're actually in it (otherwise messages go nowhere)
	local function joined(ch)
		if not ch then return false end
		for _, src in ch:GetChildren() do
			if src:IsA("TextSource") and src.UserId == player.UserId then return true end
		end
		return false
	end
	t0 = os.clock()
	while target and not joined(target) and os.clock() - t0 < 5 do task.wait(0.2) end
	if target then
		cfg.TargetTextChannel = target
	else
		local general = channel("RBXGeneral")
		if general then cfg.TargetTextChannel = general end
	end
end
player:GetAttributeChangedSignal("MatchChannel"):Connect(updateTarget)
task.spawn(updateTarget)

-- colour match messages
-- LEADERBOARD TAG in front of the name, e.g. [#1 KILLS]  (ServerScriptService > ChatTags, ReplicatedStorage > ChatTagConfig)
local function lbTag(speaker)
	local t = speaker and speaker:GetAttribute("ChatTag")
	if type(t) ~= "string" or t == "" then return "" end
	local c = speaker:GetAttribute("ChatTagColor")
	t = t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return ('<font color="%s">%s</font> '):format(hex(typeof(c) == "Color3" and c or Color3.new(1, 1, 1)), t)
end

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local ch = message.TextChannel
	if message.TextSource and not (ch and ch.Name:match("^Match_")) then
		-- lobby / normal chat: [tag] name:
		local speaker = Players:GetPlayerByUserId(message.TextSource.UserId)
		local tagText = lbTag(speaker)
		if tagText ~= "" then props.PrefixText = tagText .. message.PrefixText end
	end
	if ch and ch.Name:match("^Match_") and message.TextSource then
		local speaker = Players:GetPlayerByUserId(message.TextSource.UserId)
		local mine = player:GetAttribute("MatchTeam")
		local isMe = speaker == player or message.TextSource.UserId == player.UserId
		local sameTeam = isMe or (speaker and mine ~= nil and speaker:GetAttribute("MatchTeam") == mine)
		local label = isMe and tag("YouTag", "[You]") or (sameTeam and tag("TeamTag", "[Team]") or tag("EnemyTag", "[Enemy]"))
		local name = speaker and NameBadge.Of(speaker) or (message.PrefixText:gsub(":%s*$", ""))
		local c = hex(sameTeam and GREEN or ENEMY)
		-- [You] lux: hi   /   in 2v2+ when they're dead:  [DEAD] [You] lux: hi
		local dead = ""
		if speaker and speaker:GetAttribute("MatchDead") and (speaker:GetAttribute("MatchTeamSize") or 1) > 1 then
			dead = ('<font color="%s">%s</font> '):format(hex(script:GetAttribute("DeadColor") or Color3.fromRGB(190, 190, 190)), tag("DeadTag", "[DEAD]"))
		end
		props.PrefixText = dead .. lbTag(speaker) .. ('<font color="%s">%s %s:</font>'):format(c, label, name)
		-- the message itself is always white (TextColor attribute on this script to change it)
		props.Text = ('<font color="%s">%s</font>'):format(hex(script:GetAttribute("TextColor") or Color3.new(1, 1, 1)), message.Text)
	end
	return props
end

-- CHAT BUBBLES (the ones over heads)
--   in a match: no bubbles at all
--   practice arena: you don't see YOUR OWN bubble (it gets in the way while you're moving fast); others still do
--   lobby: normal
local bubbleCfg = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
local HIDE_OWN = Vector3.new(0, -5000, 0) -- your own bubble is moved way out of sight (nobody else's is affected)
local function updateBubbles()
	if not bubbleCfg then return end
	bubbleCfg.Enabled = player:GetAttribute("MatchId") == nil
	-- practice arena: you never see your OWN bubble (it gets in the way while you're moving fast)
	local practice = player:GetAttribute("InArena") == true and player:GetAttribute("MatchId") == nil
	pcall(function() bubbleCfg.LocalPlayerStudsOffset = practice and HIDE_OWN or Vector3.zero end)
end
player:GetAttributeChangedSignal("MatchId"):Connect(updateBubbles)
player:GetAttributeChangedSignal("InArena"):Connect(updateBubbles)
updateBubbles()
TextChatService.OnBubbleAdded = function(message, adornee)
	local src = message.TextSource
	if src and src.UserId == player.UserId and player:GetAttribute("InArena") and player:GetAttribute("MatchId") == nil then
		local props = Instance.new("BubbleChatMessageProperties")
		props.BackgroundTransparency = 1
		props.TextSize = 1
		props.TextColor3 = Color3.new(0, 0, 0)
		props.TailVisible = false
		return props
	end
	return nil
end

-- sound when someone ELSE says something in match chat (SoundConfig > ChatMessage)
do
	local SFX = require(game:GetService("ReplicatedStorage"):WaitForChild("SFX"))
	local TCS = game:GetService("TextChatService")
	local me = game:GetService("Players").LocalPlayer
	TCS.MessageReceived:Connect(function(msg)
		local src = msg.TextSource
		local ch = msg.TextChannel
		if src and src.UserId ~= me.UserId and ch and ch.Name:match("^Match_") then SFX.Play("ChatMessage") end
	end)
end
