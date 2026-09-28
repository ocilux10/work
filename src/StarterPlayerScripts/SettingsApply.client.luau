-- APPLIES THE SETTINGS (ReplicatedStorage > GameSettings) that aren't handled inside other scripts:
-- sensitivity, shadows, materials, performance stats, sound / music volume, crosshair, dummy enemies / teammates.
-- (Keybinds, auto sprint, FOV and camera motion are read by Movement / BalloonCombatClient / TabMenu / MoveKeys.)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local GS = require(RS:WaitForChild("GameSettings"))
local SFX = require(RS:WaitForChild("SFX"))
local Crosshair = require(RS:WaitForChild("CrosshairBuilder"))

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local shadowsDefault = Lighting.GlobalShadows

------------------------------------------------------------ SENSITIVITY
-- Roblox won't let games change the player's own mouse sensitivity, so this turns the camera a bit MORE (or less)
-- by the same mouse movement, just before Roblox's camera runs (it keeps the new angle). 1 = normal Roblox speed.
local RunService = game:GetService("RunService")
local sensitivity = 1
RunService:BindToRenderStep("SettingsSensitivity", Enum.RenderPriority.Camera.Value - 1, function()
	if math.abs(sensitivity - 1) < 0.01 then return end
	if UIS.MouseBehavior == Enum.MouseBehavior.Default then return end -- only while the mouse turns the camera
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then return end
	local d = UIS:GetMouseDelta()
	if d.Magnitude < 0.001 then return end
	local k = 0.002 * math.pi * (sensitivity - 1) -- same turn-per-pixel Roblox's camera uses (mouse delta already includes the player's Roblox sensitivity)
	local pitch, yaw = cam.CFrame:ToEulerAnglesYXZ()
	pitch = math.clamp(pitch - d.Y * k * 0.75, math.rad(-80), math.rad(80))
	yaw -= d.X * k
	-- keep the camera orbiting its focus (third person) instead of spinning in place
	local focus = cam.Focus.Position
	local dist = (cam.CFrame.Position - focus).Magnitude
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	if dist > 0.6 then
		cam.CFrame = CFrame.new(focus) * rot * CFrame.new(0, 0, dist)
	else
		cam.CFrame = CFrame.new(cam.CFrame.Position) * rot
	end
end)

-- CONTROLLER SENSITIVITY (Settings > Controls > Controller): the right stick turns the camera a bit more / less than
-- Roblox's own speed (1 = normal)
local padSens = 1
local stick = Vector2.zero
UIS.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick = Vector2.new(input.Position.X, input.Position.Y) end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick = Vector2.zero end
end)
RunService:BindToRenderStep("SettingsPadSensitivity", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if math.abs(padSens - 1) < 0.01 or stick.Magnitude < 0.15 then return end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then return end
	local rate = 4 * (padSens - 1) * dt -- (Roblox turns about 4 radians a second at full stick)
	local pitch, yaw = cam.CFrame:ToEulerAnglesYXZ()
	pitch = math.clamp(pitch + stick.Y * rate * 0.75, math.rad(-80), math.rad(80))
	yaw -= stick.X * rate
	local focus = cam.Focus.Position
	local dist = (cam.CFrame.Position - focus).Magnitude
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	if dist > 0.6 then cam.CFrame = CFrame.new(focus) * rot * CFrame.new(0, 0, dist) else cam.CFrame = CFrame.new(cam.CFrame.Position) * rot end
end)

------------------------------------------------------------ MATERIALS
local savedMat = setmetatable({}, {__mode = "k"})
local matConn
local function simplify(p)
	if p:IsA("BasePart") and p.Material ~= Enum.Material.SmoothPlastic and p.Material ~= Enum.Material.Neon and p.Material ~= Enum.Material.Glass and p.Material ~= Enum.Material.ForceField then
		savedMat[p] = savedMat[p] or {p.Material, p.MaterialVariant}
		p.Material = Enum.Material.SmoothPlastic
		p.MaterialVariant = ""
	end
end
local function setMaterials(off)
	if off then
		for _, d in workspace:GetDescendants() do simplify(d) end
		if not matConn then matConn = workspace.DescendantAdded:Connect(simplify) end
	else
		if matConn then matConn:Disconnect() matConn = nil end
		for p, m in savedMat do if p.Parent then p.Material = m[1] p.MaterialVariant = m[2] end end
		table.clear(savedMat)
	end
end

------------------------------------------------------------ DUMMY SKINS (matches only, only on your screen)
local stash = {} -- [character] = {items = {}, colors = {}}
local DUMMY_COLOR = Color3.fromRGB(163, 162, 165)
local function undummy(char)
	local s = stash[char]
	if not s then return end
	stash[char] = nil
	for inst, parent in s.items do if parent.Parent then inst.Parent = parent end end
	for part, col in s.colors do if part.Parent then part.Color = col end end
end
local function dummy(char)
	if stash[char] then return end
	local s = {items = {}, colors = {}}
	stash[char] = s
	for _, d in char:GetDescendants() do
		if d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or (d:IsA("Decal") and d.Name == "face") then
			s.items[d] = d.Parent
			d.Parent = nil
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not d:FindFirstAncestorOfClass("Accessory") and not d:FindFirstAncestor("HeldBalloon") and d.Name ~= "HeldBalloon" then
			s.colors[d] = d.Color
			d.Color = DUMMY_COLOR
		end
	end
end
local function refreshDummies()
	local myMatch, myTeam = player:GetAttribute("MatchId"), player:GetAttribute("MatchTeam")
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char and p ~= player then
			local want = false
			if myMatch and p:GetAttribute("MatchId") == myMatch then
				local enemy = p:GetAttribute("MatchTeam") ~= myTeam
				want = (enemy and GS.Get("DummyEnemies")) or (not enemy and GS.Get("DummyTeammates"))
			end
			if want then dummy(char) else undummy(char) end
		end
	end
	for char in stash do if not char.Parent then stash[char] = nil end end
end
local function hookPlayer(p)
	p.CharacterAdded:Connect(function() task.wait(1) refreshDummies() end)
	for _, a in {"MatchId", "MatchTeam"} do p:GetAttributeChangedSignal(a):Connect(refreshDummies) end
end
for _, p in Players:GetPlayers() do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

------------------------------------------------------------ CROSSHAIR
local function drawCrosshair()
	local ui = pg:FindFirstChild("BalloonCombatUI")
	local ch = ui and ui:FindFirstChild("Crosshair")
	if not ch then return end
	-- the frame itself is just the centre point; the drawing is made of CH_ parts inside it
	ch.BackgroundTransparency = 1
	local st = ch:FindFirstChildOfClass("UIStroke") if st then st.Enabled = false end
	Crosshair.Draw(ch, 1)
end
pg.ChildAdded:Connect(function(c) if c.Name == "BalloonCombatUI" then task.wait(0.2) drawCrosshair() end end)
Crosshair.Changed.Event:Connect(drawCrosshair) -- (a crosshair ID turned out to be a decal: redraw with its picture)

------------------------------------------------------------ APPLY
local function musicGroup()
	local g = SoundService:FindFirstChild("Music")
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = "Music" -- put background music Sounds in this group (SoundGroup property) so the Music slider controls them
		g.Parent = SoundService
	end
	return g
end
local APPLY = {
	Sensitivity = function(v) sensitivity = v end, -- used by the SENSITIVITY render step below
	PadSensitivity = function(v) padSens = v end,
	DisableShadows = function(v) Lighting.GlobalShadows = shadowsDefault and not v end,
	DisableMaterials = setMaterials,
	PerfStats = function(v) local g = pg:FindFirstChild("NetStats") if g then g.Enabled = v end end,
	SoundVolume = function(v) SFX.VolumeScale = v / 100 end,
	MusicVolume = function(v) musicGroup().Volume = v / 100 end,
	DummyEnemies = refreshDummies, DummyTeammates = refreshDummies,
	CrossLines = drawCrosshair, DotStyle = drawCrosshair, DotSize = drawCrosshair, DotColor = drawCrosshair, CrossOutline = drawCrosshair, OutlineThickness = drawCrosshair,
	CrosshairImage = drawCrosshair, CrosshairImageSize = drawCrosshair, CrosshairImageTint = drawCrosshair,
}
for key, fn in APPLY do task.spawn(fn, GS.Get(key)) end
GS.Changed:Connect(function(key, v) local fn = APPLY[key] if fn then fn(v) end end)
pg.ChildAdded:Connect(function(c) if c.Name == "NetStats" then APPLY.PerfStats(GS.Get("PerfStats")) end end)
