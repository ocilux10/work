-- LEADERBOARD CHAT TAGS (settings: ReplicatedStorage > ChatTagConfig)
-- Reads each player's leaderboard places (attributes "LB_<Board>_<AllTime|Monthly>" = "rank|value", set by
-- ServerScriptService > Leaderboards) and puts their best tag on them: attributes ChatTag (text) + ChatTagColor.
-- StarterPlayerScripts > MatchChat adds it in front of their name in chat.
local Players = game:GetService("Players")
local C = require(game:GetService("ReplicatedStorage"):WaitForChild("ChatTagConfig"))

local function colorFor(rank)
	for _, c in C.Colors or {} do
		if rank <= c.UpTo then return c.Color end
	end
	return Color3.new(1, 1, 1)
end

local function priority(key)
	return table.find(C.Priority or {}, key) or 999
end

local function update(p)
	local bestRank, bestKey
	if C.Enabled ~= false then
		for board, texts in C.BoardText or {} do
			for period in texts do
				local key = board .. "_" .. period
				local v = p:GetAttribute("LB_" .. key)
				local rank = type(v) == "string" and tonumber(v:match("^(%d+)|"))
				if rank and rank >= 1 and rank <= (C.MaxRank or 100) then
					if not bestRank or rank < bestRank or (rank == bestRank and priority(key) < priority(bestKey)) then
						bestRank, bestKey = rank, key
					end
				end
			end
		end
	end
	if not bestRank then
		p:SetAttribute("ChatTag", nil)
		p:SetAttribute("ChatTagColor", nil)
		return
	end
	local board, period = bestKey:match("^(.-)_(%a+)$")
	local custom = C.Custom and C.Custom[bestKey] and C.Custom[bestKey][bestRank]
	local text = custom and custom.Text or (C.Format or "[#{rank} {board}]"):gsub("{rank}", tostring(bestRank)):gsub("{board}", C.BoardText[board][period])
	p:SetAttribute("ChatTag", text)
	p:SetAttribute("ChatTagColor", custom and custom.Color or colorFor(bestRank))
end

local function hook(p)
	p.AttributeChanged:Connect(function(name)
		if name:sub(1, 3) == "LB_" then update(p) end
	end)
	update(p)
end
Players.PlayerAdded:Connect(hook)
for _, p in Players:GetPlayers() do hook(p) end
