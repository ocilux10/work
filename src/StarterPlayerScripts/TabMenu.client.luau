-- HOLD TAB
--   Practice arena: your mouse is free while Tab is held (look around the UI / click things).
--   In a match:     mouse free + the match scoreboard (MatchUI > Scoreboard): Player, Device, Ping, K/D/A.
-- Scoreboard look (all restyleable): Header, List, RowTemplate > Tile (Headshot / Level / Streak), PlayerName,
-- DeviceSlot, Ping, KDA, TeamLine. Colours: MyTeamColor / EnemyTeamColor attributes on Scoreboard.
-- K = kills, D = deaths, A = assists (you damaged someone this round and a teammate got the kill).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names

local player = Players.LocalPlayer
local PlayerCard = require(RS:WaitForChild("Matchmaking"):WaitForChild("PlayerCard"))
local KEY = Enum.KeyCode.Tab -- (default; the real key is Settings > Controls > Scoreboard)
local GS = require(RS:WaitForChild("GameSettings"))

local function inMatch() return player:GetAttribute("MatchId") ~= nil end
local function inArena() return player:GetAttribute("InArena") == true end

local function scoreboard()
	local ui = player.PlayerGui:FindFirstChild("MatchUI")
	return ui and ui:FindFirstChild("Scoreboard")
end

------------------------------------------------------------ SCOREBOARD
local rows = {} -- [player] = row

local function pingColor(ms)
	if ms < 100 then return Color3.fromRGB(80, 230, 90) end
	if ms < 200 then return Color3.fromRGB(255, 200, 60) end
	return Color3.fromRGB(255, 70, 70)
end

local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton")) then o.Text = t end end

local function fillRow(row, p, mine)
	local sb = scoreboard()
	local tile = row:FindFirstChild("Tile")
	local head = tile and tile:FindFirstChild("Headshot")
	if head and head:IsA("ImageLabel") and head.Image == "" then
		head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(p.UserId)
	end
	setText(tile and tile:FindFirstChild("Level"), tostring(p:GetAttribute("Level") or 1))
	local streak = tile and tile:FindFirstChild("Streak")
	local ws = p:GetAttribute("WinStreak") or 0
	if streak and streak:IsA("TextLabel") then
		streak.Text = (streak:FindFirstChildWhichIsA("ImageLabel", true) and "" or "\u{1F525}") .. ws
		streak.Visible = ws > 0
	end
	setText(row:FindFirstChild("PlayerName"), NameBadge.Of(p))
	local slot = row:FindFirstChild("DeviceSlot")
	local device = p:GetAttribute("Device") or "PC"
	if slot and slot:GetAttribute("Shown") ~= device then
		slot:SetAttribute("Shown", device)
		for _, c in slot:GetChildren() do if c.Name == "Device" then c:Destroy() end end
		local icon = PlayerCard.DeviceIcon(device, slot)
		for _, d in icon:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = slot.ZIndex + 1 end end
	end
	local ping = row:FindFirstChild("Ping")
	local ms = p:GetAttribute("Ping") or 0
	if ping and ping:IsA("TextLabel") then
		ping.Text = ms .. " ms"
		ping.TextColor3 = pingColor(ms)
	end
	setText(row:FindFirstChild("KDA"), ("%d/%d/%d"):format(p:GetAttribute("MatchKills") or 0, p:GetAttribute("MatchDeaths") or 0, p:GetAttribute("MatchAssists") or 0))
	local line = row:FindFirstChild("TeamLine")
	if line and line:IsA("GuiObject") then
		line.BackgroundColor3 = mine and (sb:GetAttribute("MyTeamColor") or Color3.fromRGB(40, 220, 80))
			or (sb:GetAttribute("EnemyTeamColor") or Color3.fromRGB(230, 30, 30))
	end
end

local function refresh()
	local sb = scoreboard()
	local list = sb and sb:FindFirstChild("List")
	local template = sb and sb:FindFirstChild("RowTemplate")
	if not (list and template) then return end
	template.Visible = false
	list.Visible = true
	local hdr = sb:FindFirstChild("Header")
	if hdr and hdr:IsA("GuiObject") then hdr.Visible = true end
	-- player rows always sit right under the header, wherever the header is moved to
	local header = sb:FindFirstChild("Header")
	if header and header:IsA("GuiObject") then
		local y = header.Position.Y.Scale + header.Size.Y.Scale + (sb:GetAttribute("HeaderGap") or 0.015)
		list.Position = UDim2.new(list.Position.X.Scale, list.Position.X.Offset, y, 0) -- (size kept, so rows stay the same size)
	end
	local myMatch, myTeam = player:GetAttribute("MatchId"), player:GetAttribute("MatchTeam")
	local present = {}
	for _, p in Players:GetPlayers() do
		if myMatch and p:GetAttribute("MatchId") == myMatch then
			present[p] = true
			local row = rows[p]
			if not row or not row.Parent then
				row = template:Clone()
				row.Name = "Row_" .. p.Name
				row.Visible = true
				row.Parent = list
				rows[p] = row
			end
			local mine = p:GetAttribute("MatchTeam") == myTeam
			-- other team on top, your team underneath (you last)
			row.LayoutOrder = (mine and 100 or 0) + (p == player and 50 or 0)
			fillRow(row, p, mine)
		end
	end
	for p, row in rows do
		if not present[p] then row:Destroy() rows[p] = nil end
	end
end

------------------------------------------------------------ HOLD TAB
local held = false
local SFX = require(RS:WaitForChild("SFX")) -- sounds: ReplicatedStorage > SoundConfig
local function setHeld(on)
	if held == on then return end
	held = on
	if on then SFX.Play("TabOpen") end
	player:SetAttribute("TabHeld", on or nil) -- BalloonCombatClient ignores attack clicks while this is set
	local sb = scoreboard()
	if sb then
		sb.Visible = on and inMatch()
		if sb.Visible then refresh() end
	end
	if not on then
		-- give the mouse back to the game (crosshair in the arena)
		UIS.MouseIconEnabled = not inArena()
	end
end

UIS.InputBegan:Connect(function(input, gpe)
	if not GS.Is("Scoreboard", input) or UIS:GetFocusedTextBox() then return end
	-- not during the round won / round lost screen (or the final kill replay)
	if player:GetAttribute("NoTabMenu") then return end
	-- only while actually in combat (practice arena or fighting in a match) -
	-- not while voting for a map, loading in, spectating or on the end screen
	if inArena() then setHeld(true) end
end)
-- the round result appearing closes it straight away
player:GetAttributeChangedSignal("NoTabMenu"):Connect(function()
	if player:GetAttribute("NoTabMenu") then setHeld(false) end
end)
UIS.InputEnded:Connect(function(input)
	if GS.Is("Scoreboard", input) then setHeld(false) end
end)
-- leaving the arena / match while holding it
player:GetAttributeChangedSignal("InArena"):Connect(function() if not inArena() then setHeld(false) end end)

-- free mouse: runs after the camera, which would otherwise lock it to the centre every frame
RunService:BindToRenderStep("TabFreeMouse", Enum.RenderPriority.Last.Value + 50, function()
	if held then
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		UIS.MouseIconEnabled = true
	end
end)

-- live numbers while it's open
task.spawn(function()
	while true do
		task.wait(0.5)
		local sb = scoreboard()
		if held and sb and sb.Visible then refresh() end
	end
end)

-- Roblox's own Tab player list (leaderstats) is off in a match AND in the practice arena,
-- so Tab only does our thing there. It comes back in the lobby.
local function syncCoreList()
	local off = inMatch() or inArena()
	-- the round result screen hides it too and puts it back after; don't fight it
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not off) end)
end
player:GetAttributeChangedSignal("MatchId"):Connect(syncCoreList)
player:GetAttributeChangedSignal("InArena"):Connect(syncCoreList)
syncCoreList()

-- hidden until Tab is held (it's left visible in Studio for designing)
task.spawn(function()
	local ui = player:WaitForChild("PlayerGui"):WaitForChild("MatchUI", 20)
	local sb = ui and ui:WaitForChild("Scoreboard", 5)
	if sb then sb.Visible = false end
end)
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	local sb = scoreboard()
	if sb and not held then sb.Visible = false end
end)
