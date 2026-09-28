-- REWARDS: one format for everything that gives stuff (Daily Rewards, Leaderboard Rewards).
--   {Coins = 250}                                   coins
--   {Crate = "Basic"}                               a chest (Crates > CrateConfig Id) - it's opened for you with the spin
--   {Crate = "Premium", CrateCount = 3}             3 of them
--   {Balloon = "Toxic"} / {Balloon = "Toxic", BalloonCount = 2}   a balloon (BalloonSkins > SkinConfig Id)
--   {Coins = 500, Crate = "Premium"}                any mix
-- Optional on any reward: Image = "rbxassetid://..." (the picture shown), Name = "..." (the text shown instead)
local RS = game:GetService("ReplicatedStorage")
local M = {}

local function fmt(n) return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
M.Fmt = fmt

-- the parts of a reward: {{Kind = "Coins" / "Crate" / "Balloon", Id, Amount, Name}, ...}
function M.Parts(r)
	local out = {}
	if type(r) ~= "table" then return out end
	if (tonumber(r.Coins) or 0) > 0 then table.insert(out, {Kind = "Coins", Amount = r.Coins, Name = "Coins"}) end
	if type(r.Crate) == "string" then
		local cfg = require(RS:WaitForChild("Crates"):WaitForChild("CrateConfig"))
		local c = cfg.ById[r.Crate]
		table.insert(out, {Kind = "Crate", Id = r.Crate, Amount = math.max(1, tonumber(r.CrateCount) or 1), Name = c and c.Name or r.Crate})
	end
	if type(r.Balloon) == "string" then
		local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
		local s = Skins.ById[r.Balloon]
		table.insert(out, {Kind = "Balloon", Id = r.Balloon, Amount = math.max(1, tonumber(r.BalloonCount) or 1), Name = s and s.Name or r.Balloon})
	end
	return out
end

-- "250 Coins", "2x Premium Chest", "500 Coins + Basic Chest"
function M.Text(r)
	if type(r) == "table" and type(r.Name) == "string" then return r.Name end
	local bits = {}
	for _, p in M.Parts(r) do
		if p.Kind == "Coins" then table.insert(bits, fmt(p.Amount) .. " Coins")
		else table.insert(bits, (p.Amount > 1 and (p.Amount .. "x ") or "") .. p.Name) end
	end
	return #bits > 0 and table.concat(bits, " + ") or "Nothing"
end

-- big number + small word for a reward card: ("250", "Coins"), ("x2", "Premium Chest"), ("500", "Coins + Basic Chest")
function M.CardText(r)
	local parts = M.Parts(r)
	if type(r) == "table" and type(r.Name) == "string" then return "", r.Name end
	if #parts == 0 then return "", "Nothing" end
	local first = parts[1]
	local amount = first.Kind == "Coins" and fmt(first.Amount) or (first.Amount > 1 and ("x" .. first.Amount) or "")
	local names = {}
	for i, p in parts do
		if i == 1 then table.insert(names, p.Name)
		else table.insert(names, (p.Kind == "Coins" and (fmt(p.Amount) .. " ") or (p.Amount > 1 and (p.Amount .. "x ") or "")) .. p.Name) end
	end
	return amount, table.concat(names, " + ")
end

return M
