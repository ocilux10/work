-- BALLOON SKINS - every balloon in the game. Edit freely.
--   Two kinds of balloon:
--   1) with its OWN model: ReplicatedStorage > BalloonSkins > Models > <Id> (one MeshPart; its effects = the FX_ items
--      inside it). ExtraFX = more effects added on top (see BalloonSkins > BalloonLook for the list).
--   2) BUILT from a Look: uses another balloon's 3D shape with its own colour / material / glow / effects - no model
--      needed. Everything about the look is in its Look = {...} (BalloonSkins > BalloonLook explains every option).
--   A balloon with a model in Models always uses that model (so you can replace any built one with a real model later).
--   Add a balloon: add a line to SKINS below (+ its model in Models, or a Look). It shows up everywhere by itself:
--   inventory (search / filters), shop contents, spins, inspect, trading, admin panel, profiles.
local M = {}

-- rarities: order (for sorting, 1 = lowest), colour of the card bar / glow, and the text shown
M.Rarities = {
	Default   = {Order = 0, Color = Color3.fromRGB(176, 176, 176), Text = "Default"},
	Common    = {Order = 1, Color = Color3.fromRGB(190, 200, 210), Text = "Common"},
	Rare      = {Order = 2, Color = Color3.fromRGB(60, 140, 255), Text = "Rare"},
	Epic      = {Order = 3, Color = Color3.fromRGB(170, 80, 255), Text = "Epic"},
	Legendary = {Order = 4, Color = Color3.fromRGB(255, 180, 40), Text = "Legendary"},
	Mythic    = {Order = 5, Color = Color3.fromRGB(255, 60, 110), Text = "Mythic"},
	Exclusive = {Order = 6, Color = Color3.fromRGB(255, 35, 35), Text = "Exclusive"},
}
-- the order of the Show: filter in the Balloons menu
M.RarityOrder = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Exclusive"}

local C = Color3.fromRGB
-- Id = the model's name / the balloon's id (never change it once players own it). Name = shown on cards.
-- Type = the small line under the name. Rarity = one of the rarities above. Desc = the description (inspect screen).
-- Size = how big it is IN HANDS and when thrown (1 = normal, 0.8 = smaller, 1.2 = bigger).
M.Skins = {
	-------------------------------------------------- THE ORIGINALS (own models)
	{Id = "Default",    Name = "Default",      Type = "Balloon", Rarity = "Default",   Size = 1.2, Desc = "The one everyone starts with."},
	{Id = "Honeycomb",  Name = "Honeycomb",    Type = "Balloon", Rarity = "Common",    Size = 1.2, Desc = "Sticky, sweet and buzzing.",
		ExtraFX = {FX = {"Sparkles"}, FXColor = C(255, 200, 60)}},
	{Id = "CandySwirl", Name = "Candy Swirl",  Type = "Balloon", Rarity = "Rare",      Size = 1.2, Desc = "A sugar rush in balloon form.",
		ExtraFX = {FX = {"Sparkles"}, FXColor = C(255, 140, 210), FXColor2 = C(140, 220, 255)}},
	{Id = "Heartbreak", Name = "Heartbreak",   Type = "Balloon", Rarity = "Rare",      Size = 1.2, Desc = "It hurts more than it looks.",
		ExtraFX = {FX = {"Aura"}, FXColor = C(255, 60, 100)}},
	{Id = "Frostbite",  Name = "Frostbite",    Type = "Balloon", Rarity = "Epic",      Size = 1.2, Desc = "Cold enough to freeze the air around it.",
		ExtraFX = {FX = {"Snow"}, FXColor = C(210, 240, 255)}},
	{Id = "Toxic",      Name = "Toxic",        Type = "Balloon", Rarity = "Epic",      Size = 1.2, Desc = "Do not pop near your face.",
		ExtraFX = {FX = {"Bubbles"}, FXColor = C(120, 255, 80)}},
	{Id = "Glitch",     Name = "Glitch",       Type = "Balloon", Rarity = "Epic",      Size = 1.2, Desc = "Is it really there?",
		ExtraFX = {FX = {"Vortex"}, FXColor = C(60, 255, 230), FXColor2 = C(255, 60, 220)}},
	{Id = "Inferno",    Name = "Inferno",      Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Burns hotter the more you throw it.",
		ExtraFX = {FX = {"Smoke"}, FXColor = C(60, 40, 35)}},
	{Id = "Thunder",    Name = "Thunder",      Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Crackling with stored lightning.",
		ExtraFX = {FX = {"Embers"}, FXColor = C(255, 240, 120), FXColor2 = C(120, 200, 255)}},
	{Id = "ShadowVoid", Name = "Shadow Void",  Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "A hole in the world, tied to a string.",
		ExtraFX = {FX = {"Ring"}, FXColor = C(150, 60, 255)}},
	{Id = "Cosmic",     Name = "Cosmic",       Type = "Balloon", Rarity = "Mythic",    Size = 1.2, Desc = "A whole galaxy squeezed inside.",
		ExtraFX = {FX = {"Aura"}, FXColor = C(120, 80, 255)}},
	{Id = "Royal",      Name = "Royal",        Type = "Balloon", Rarity = "Mythic",    Size = 1.2, Desc = "Fit for a king.",
		ExtraFX = {FX = {"Halo", "Sparkles"}, FXColor = C(255, 210, 70), Glow = C(255, 200, 80)}},

	-------------------------------------------------- COMMON
	-- (every balloon below has its own colour + shape + material combo: no two look the same)
	{Id = "Bubblegum", Name = "Bubblegum", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "Pink, chewy and ready to pop.",
		Look = {Shape = "Default", Color = C(255, 120, 185), Material = "SmoothPlastic", Reflectance = 0.05, FX = {"Bubbles"}, FXColor = C(255, 170, 215)}},
	{Id = "Mint", Name = "Mint", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "Fresh as it gets.",
		Look = {Shape = "Default", Color = C(110, 230, 170), Material = "SmoothPlastic", Reflectance = 0.05}},
	{Id = "Sky", Name = "Sky", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "A little piece of a clear day.",
		Look = {Shape = "Default", Color = C(95, 175, 255), Material = "SmoothPlastic", Reflectance = 0.05}},
	{Id = "Lemon", Name = "Lemon", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "Sour on impact.",
		Look = {Shape = "Default", Color = C(255, 225, 60), Material = "SmoothPlastic", Reflectance = 0.05}},
	{Id = "Coal", Name = "Coal", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "For the ones on the naughty list.",
		Look = {Shape = "Default", Color = C(50, 50, 56), Material = "Slate", FX = {"Smoke"}, FXColor = C(60, 60, 60)}},
	{Id = "Beehive", Name = "Beehive", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "The honeycomb's plain cousin.",
		Look = {Shape = "Honeycomb", Color = C(150, 95, 35), Material = "Wood"}},
	{Id = "Peppermint", Name = "Peppermint", Type = "Balloon", Rarity = "Common", Size = 1.2, Desc = "Red, white and minty.",
		Look = {Shape = "CandySwirl", Color = C(230, 45, 55), Material = "SmoothPlastic", Reflectance = 0.1}},

	-------------------------------------------------- RARE
	{Id = "Chrome", Name = "Chrome", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "You can see yourself in it.",
		Look = {Shape = "Default", Color = C(175, 180, 190), Material = "Metal", Reflectance = 0.45, FX = {"Sparkles"}, FXColor = C(255, 255, 255)}},
	{Id = "GlassBalloon", Name = "Glass", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Handle with care.",
		Look = {Shape = "Default", Color = C(150, 240, 225), Material = "Glass", Transparency = 0.3, Reflectance = 0.2, FX = {"Bubbles"}, FXColor = C(200, 255, 245)}},
	{Id = "NeonLime", Name = "Neon Lime", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Visible from space.",
		Look = {Shape = "Default", Color = C(140, 255, 40), Material = "Neon", Glow = C(140, 255, 40), FX = {"Aura"}, FXColor = C(140, 255, 40)}},
	{Id = "Marble", Name = "Marble", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Carved by a very patient sculptor.",
		Look = {Shape = "Default", Color = C(240, 236, 228), Material = "Marble", Reflectance = 0.1}},
	{Id = "CottonCandy", Name = "Cotton Candy", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Fluffy, pastel and very sweet.",
		Look = {Shape = "CandySwirl", Color = C(190, 165, 255), Material = "Fabric", FX = {"Sparkles"}, FXColor = C(255, 180, 230), FXColor2 = C(170, 220, 255)}},
	{Id = "Lovestruck", Name = "Lovestruck", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Hit someone with love. Literally.",
		Look = {Shape = "Heartbreak", Color = C(255, 90, 140), Material = "SmoothPlastic", Reflectance = 0.15, FX = {"Sparkles"}, FXColor = C(255, 140, 180)}},
	{Id = "Glacier", Name = "Glacier", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Slow, cold and unstoppable.",
		Look = {Shape = "Frostbite", Color = C(120, 190, 255), Material = "Ice", Reflectance = 0.15, FX = {"Snow"}, FXColor = C(230, 245, 255)}},
	{Id = "StormCloud", Name = "Storm Cloud", Type = "Balloon", Rarity = "Rare", Size = 1.2, Desc = "Grumbling, grey and about to rain.",
		Look = {Shape = "Thunder", Color = C(105, 110, 128), Material = "Concrete", FX = {"Smoke"}, FXColor = C(90, 95, 110)}},

	-------------------------------------------------- EPIC
	{Id = "GoldRush", Name = "Gold Rush", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Struck it rich.",
		Look = {Shape = "Default", Color = C(255, 185, 30), Material = "Foil", Reflectance = 0.35, FX = {"Sparkles"}, FXColor = C(255, 225, 120), Glow = C(255, 200, 80)}},
	{Id = "Hologram", Name = "Hologram", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Projected from somewhere far away.",
		Look = {Shape = "Default", Color = C(40, 130, 255), Material = "ForceField", FX = {"Vortex"}, FXColor = C(80, 200, 255), Glow = C(60, 160, 255)}},
	{Id = "RoyalJelly", Name = "Royal Jelly", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Only the queen bee gets this.",
		Look = {Shape = "Honeycomb", Color = C(255, 215, 90), Material = "Foil", Reflectance = 0.2, FX = {"Drip", "Sparkles"}, FXColor = C(255, 190, 50), Glow = C(255, 170, 40)}},
	{Id = "BrokenHearted", Name = "Broken Hearted", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Some wounds never heal.",
		Look = {Shape = "Heartbreak", Color = C(85, 25, 115), Material = "Slate", FX = {"Smoke", "Sparkles"}, FXColor = C(150, 60, 200)}},
	{Id = "AcidRain", Name = "Acid Rain", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Bring an umbrella.",
		Look = {Shape = "Toxic", Color = C(215, 255, 30), Material = "Neon", FX = {"Drip", "Bubbles"}, FXColor = C(200, 255, 60), Glow = C(180, 255, 40)}},
	{Id = "Corrupted", Name = "Corrupted", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Something went very wrong.",
		Look = {Shape = "Glitch", Color = C(255, 30, 190), Material = "ForceField", FX = {"Sparkles"}, FXColor = C(255, 60, 220), FXColor2 = C(60, 255, 230)}},
	{Id = "Magma", Name = "Magma", Type = "Balloon", Rarity = "Epic", Size = 1.2, Desc = "Straight out of a volcano.",
		Look = {Shape = "Inferno", Color = C(210, 80, 15), Material = "CrackedLava", FX = {"Embers"}, FXColor = C(255, 140, 40), Glow = C(255, 90, 20)}},

	-------------------------------------------------- LEGENDARY
	{Id = "Blizzard", Name = "Blizzard", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "A snowstorm on a string.",
		Look = {Shape = "Frostbite", Color = C(245, 250, 255), Material = "Snow", FX = {"Snow", "Aura"}, FXColor = C(200, 235, 255), Glow = C(180, 225, 255)}},
	{Id = "Radioactive", Name = "Radioactive", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Glows in the dark. And the light.",
		Look = {Shape = "Toxic", Color = C(0, 200, 95), Material = "Neon", FX = {"Aura", "Embers"}, FXColor = C(90, 255, 140), Glow = {Color = C(40, 255, 120), Brightness = 2.5, Range = 10}}},
	{Id = "Error404", Name = "Error 404", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Balloon not found.",
		Look = {Shape = "Glitch", Color = C(230, 20, 20), Material = "Neon", FX = {"Vortex", "Implode"}, FXColor = C(255, 40, 40), FXColor2 = C(20, 20, 20)}},
	{Id = "BlueFlame", Name = "Blue Flame", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "The hottest part of the fire.",
		Look = {Shape = "Inferno", Color = C(30, 90, 255), Material = "Neon", FX = {"Fire", "Embers"}, FXColor = C(90, 170, 255), FXColor2 = C(20, 40, 255), Glow = C(60, 140, 255)}},
	{Id = "Voltage", Name = "Voltage", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Ten thousand volts, handle with gloves.",
		Look = {Shape = "Thunder", Color = C(255, 230, 40), Material = "Neon", FX = {"Vortex", "Embers"}, FXColor = C(255, 245, 120), FXColor2 = C(120, 220, 255), Glow = C(255, 240, 80)}},
	{Id = "Eclipse", Name = "Eclipse", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "When the moon covers the sun.",
		Look = {Shape = "ShadowVoid", Color = C(120, 55, 15), Material = "Metal", Reflectance = 0.2, FX = {"Ring", "Aura"}, FXColor = C(255, 150, 40), Glow = C(255, 130, 40)}},
	{Id = "Nebula", Name = "Nebula", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Where stars are born.",
		Look = {Shape = "Cosmic", Color = C(225, 95, 245), Material = "Foil", Reflectance = 0.15, FX = {"Stars", "Smoke"}, FXColor = C(255, 140, 230), FXColor2 = C(120, 90, 255)}},
	{Id = "Emperor", Name = "Emperor", Type = "Balloon", Rarity = "Legendary", Size = 1.2, Desc = "Bow before it.",
		Look = {Shape = "Royal", Color = C(105, 35, 185), Material = "Foil", Reflectance = 0.25, FX = {"Sparkles", "Halo"}, FXColor = C(255, 210, 70)}},

	-------------------------------------------------- MYTHIC
	{Id = "Hellfire", Name = "Hellfire", Type = "Balloon", Rarity = "Mythic", Size = 1.2, Desc = "Forged in the underworld.",
		Look = {Shape = "Inferno", Color = C(110, 0, 10), Material = "Basalt", FX = {"Fire", "Smoke", "Embers"}, FXColor = C(255, 60, 20), FXColor2 = C(120, 0, 0), Glow = {Color = C(255, 50, 20), Brightness = 2.5, Range = 10}}},
	{Id = "Plasma", Name = "Plasma", Type = "Balloon", Rarity = "Mythic", Size = 1.2, Desc = "The fourth state of matter.",
		Look = {Shape = "Thunder", Color = C(160, 50, 255), Material = "ForceField", FX = {"Vortex", "Ring", "Sparkles"}, FXColor = C(200, 120, 255), FXColor2 = C(80, 200, 255), Glow = C(170, 90, 255)}},
	{Id = "Abyss", Name = "Abyss", Type = "Balloon", Rarity = "Mythic", Size = 1.2, Desc = "Stare into it. It stares back.",
		Look = {Shape = "ShadowVoid", Color = C(15, 35, 120), Material = "Glass", Transparency = 0.1, FX = {"Implode", "Smoke", "Stars"}, FXColor = C(40, 90, 255), FXColor2 = C(0, 0, 20), Glow = C(30, 70, 255)}},
	{Id = "Galaxy", Name = "Galaxy", Type = "Balloon", Rarity = "Mythic", Size = 1.2, Desc = "Billions of stars and one string.",
		Look = {Shape = "Cosmic", Color = C(20, 40, 95), Material = "Metal", Reflectance = 0.3, FX = {"Stars", "DoubleRing"}, FXColor = C(170, 200, 255), FXColor2 = C(255, 140, 255), Glow = C(120, 140, 255)}},
	{Id = "Diamond", Name = "Diamond", Type = "Balloon", Rarity = "Mythic", Size = 1.2, Desc = "Pressure made this.",
		Look = {Shape = "Royal", Color = C(165, 235, 255), Material = "Glass", Transparency = 0.15, Reflectance = 0.5, FX = {"Sparkles", "Aura"}, FXColor = C(220, 250, 255), Glow = C(200, 240, 255)}},

	-------------------------------------------------- EXCLUSIVE
	{Id = "RainbowPrism", Name = "Rainbow Prism", Type = "Balloon", Rarity = "Exclusive", Size = 1.2, Desc = "All the colours at once.",
		Look = {Shape = "Default", Color = C(215, 185, 255), Material = "Foil", Reflectance = 0.3, FX = {"Sparkles", "Ring", "Aura"}, FXColor = "Rainbow", Glow = C(255, 255, 255), RainbowBody = true}},
	{Id = "Celestial", Name = "Celestial", Type = "Balloon", Rarity = "Exclusive", Size = 1.2, Desc = "Sent down from the heavens.",
		Look = {Shape = "Royal", Color = C(255, 205, 90), Material = "Neon", FX = {"Halo", "DoubleRing", "Sparkles", "Aura"}, FXColor = C(255, 225, 130), FXColor2 = C(255, 255, 255), Glow = {Color = C(255, 230, 150), Brightness = 3, Range = 12}}},
	{Id = "VoidKing", Name = "Void King", Type = "Balloon", Rarity = "Exclusive", Size = 1.2, Desc = "Rules over nothing. And everything.",
		Look = {Shape = "ShadowVoid", Color = C(75, 10, 120), Material = "CrackedLava", FX = {"Fire", "DoubleRing", "Implode", "Halo"}, FXColor = C(170, 60, 255), FXColor2 = C(40, 0, 80), Glow = {Color = C(150, 50, 255), Brightness = 3, Range = 12}}},
}
M.DefaultId = "Default" -- everyone always has it; can't be deleted

-- TESTERS: these usernames get 1 of every balloon (and 2 of the ones in TesterDoubles) the first time they join.
-- Add usernames here (admin commands can use SkinServer.Grant later).
M.Testers = {"ocilux", "hhdonor", "hitboxmadefr"}
M.TesterDoubles = {"Cosmic", "Inferno"}

M.ById = {}
for i, s in M.Skins do s.Index = i M.ById[s.Id] = s end

function M.Get(id) return M.ById[id] or M.ById[M.DefaultId] end
-- ViewportFrames (menu pictures) can't show Neon (all white), ForceField (just an outline) or see-through Glass well:
-- this swaps them for materials that keep the balloon's real colour there. SkinConfig.ForViewport(part) -> part
M.ViewportSwap = {Neon = "SmoothPlastic", ForceField = "Glass", Glass = "Glass"}
function M.ForViewport(part)
	if not (part and part:IsA("BasePart")) then return part end
	local swap = M.ViewportSwap[part.Material.Name]
	if swap then
		part.Material = Enum.Material[swap]
		if swap == "Glass" then part.Transparency = math.min(part.Transparency, 0.1) end
		if part.Material == Enum.Material.SmoothPlastic then part.Reflectance = math.max(part.Reflectance, 0.15) end
	end
	return part
end
-- in-hand / thrown size multiplier of a balloon (Size above; 1 when not set)
function M.Size(id) local s = M.ById[id or ""] return (s and tonumber(s.Size)) or 1 end
function M.Rarity(id) local s = M.Get(id) return M.Rarities[s.Rarity] or M.Rarities.Common end
-- a fresh copy of the balloon (a MeshPart) - the Default one if that model is missing
local Look -- (BalloonLook, loaded when first needed)
function M.Model(id)
	local models = script.Parent:WaitForChild("Models")
	local s = M.ById[id or ""]
	local own = models:FindFirstChild(id or "")
	Look = Look or require(script.Parent:WaitForChild("BalloonLook"))
	if own then
		local m = own:Clone()
		if s and s.ExtraFX then Look.Extra(m, s.ExtraFX) end
		return m
	end
	if s and s.Look then
		local shape = models:FindFirstChild(s.Look.Shape or M.DefaultId) or models:FindFirstChild(M.DefaultId)
		if shape then
			local m = Look.Build(shape:Clone(), s.Look)
			m.Name = s.Id
			return m
		end
	end
	local d = models:FindFirstChild(M.DefaultId)
	return d and d:Clone()
end
return M
