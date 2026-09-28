-- BALLOON SKINS - every balloon in the game. Edit freely.
--   Models: ReplicatedStorage > BalloonSkins > Models > <Id>  (one MeshPart each; its effects = the FX_ items inside it:
--           glow / particles / ring beams - recolour, resize or delete them)
--   Add a balloon: put its MeshPart in Models (named like its Id) and add a line to SKINS below.
local M = {}

-- rarities: order (for sorting, 1 = lowest), colour of the card bar / glow, and the text shown
M.Rarities = {
	Default   = {Order = 0, Color = Color3.fromRGB(176, 176, 176), Text = "Default"},
	Common    = {Order = 1, Color = Color3.fromRGB(190, 200, 210), Text = "Common"},
	Rare      = {Order = 2, Color = Color3.fromRGB(60, 140, 255), Text = "Rare"},
	Epic      = {Order = 3, Color = Color3.fromRGB(170, 80, 255), Text = "Epic"},
	Legendary = {Order = 4, Color = Color3.fromRGB(255, 180, 40), Text = "Legendary"},
	Mythic    = {Order = 5, Color = Color3.fromRGB(255, 60, 110), Text = "Mythic"},
}

-- Id = the model's name. Name = shown on cards. Type = the small line under the name.
-- Size = how big it is IN HANDS (your first-person view + what others see you holding) and when thrown.
--        1 = normal, 0.8 = smaller, 1.2 = bigger. (Every balloon at once: BalloonCombat > Config >
--        ViewmodelBalloonScale / HeldBalloonScale / ShotVisualScale.)
M.Skins = {
	{Id = "Default",    Name = "Default",      Type = "Balloon", Rarity = "Default",   Size = 1.2},
	{Id = "Honeycomb",  Name = "Honeycomb",    Type = "Balloon", Rarity = "Common",    Size = 1.2},
	{Id = "CandySwirl", Name = "Candy Swirl",  Type = "Balloon", Rarity = "Rare",      Size = 1.2},
	{Id = "Heartbreak", Name = "Heartbreak",   Type = "Balloon", Rarity = "Rare",      Size = 1.2},
	{Id = "Frostbite",  Name = "Frostbite",    Type = "Balloon", Rarity = "Epic",      Size = 1.2},
	{Id = "Toxic",      Name = "Toxic",        Type = "Balloon", Rarity = "Epic",      Size = 1.2},
	{Id = "Glitch",     Name = "Glitch",       Type = "Balloon", Rarity = "Epic",      Size = 1.2},
	{Id = "Inferno",    Name = "Inferno",      Type = "Balloon", Rarity = "Legendary", Size = 1.2},
	{Id = "Thunder",    Name = "Thunder",      Type = "Balloon", Rarity = "Legendary", Size = 1.2},
	{Id = "ShadowVoid", Name = "Shadow Void",  Type = "Balloon", Rarity = "Legendary", Size = 1.2},
	{Id = "Cosmic",     Name = "Cosmic",       Type = "Balloon", Rarity = "Mythic",    Size = 1.2},
	{Id = "Royal",      Name = "Royal",        Type = "Balloon", Rarity = "Mythic",    Size = 1.2},
}
M.DefaultId = "Default" -- everyone always has it; can't be deleted

-- TESTERS: these usernames get 1 of every balloon (and 2 of the ones in TesterDoubles) the first time they join.
-- Add usernames here (admin commands can use SkinServer.Grant later).
M.Testers = {"ocilux", "hhdonor", "hitboxmadefr"}
M.TesterDoubles = {"Cosmic", "Inferno"}

M.ById = {}
for i, s in M.Skins do s.Index = i M.ById[s.Id] = s end

function M.Get(id) return M.ById[id] or M.ById[M.DefaultId] end
-- in-hand / thrown size multiplier of a balloon (Size above; 1 when not set)
function M.Size(id) local s = M.ById[id or ""] return (s and tonumber(s.Size)) or 1 end
function M.Rarity(id) local s = M.Get(id) return M.Rarities[s.Rarity] or M.Rarities.Common end
-- a fresh copy of the balloon (a MeshPart) - the Default one if that model is missing
function M.Model(id)
	local models = script.Parent:WaitForChild("Models")
	local m = models:FindFirstChild(id or "") or models:FindFirstChild(M.DefaultId)
	return m and m:Clone()
end
return M
 