-- PARTIES (server). Used by PartyServer (invites) and GlobalMatchmaking (searching as a party).
-- Each member gets attributes the UI reads:
--   PartyId (string), PartyLeader (userId), PartyMembers ("id,id,id" leader first), PartySize (number)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Parties = {}
local byId = {}      -- [partyId] = party {Id, LeaderId, Members = {player...}}
local partyOf = {}   -- [player] = party
local changed = Instance.new("BindableEvent")
Parties.Changed = changed.Event -- (party, reason) fires whenever members / leader change

local function leaderOf(party)
	for _, p in party.Members do if p.UserId == party.LeaderId then return p end end
	return party.Members[1]
end

local function publish(party)
	local lead = leaderOf(party)
	local ids = {}
	if lead then table.insert(ids, tostring(lead.UserId)) end
	for _, p in party.Members do if p ~= lead then table.insert(ids, tostring(p.UserId)) end end
	for _, p in party.Members do
		if p.Parent == Players then
			p:SetAttribute("PartyId", party.Id)
			p:SetAttribute("PartyLeader", lead and lead.UserId or 0)
			p:SetAttribute("PartyMembers", table.concat(ids, ","))
			p:SetAttribute("PartySize", #party.Members)
		end
	end
end

local function clearAttrs(p)
	if p.Parent ~= Players then return end
	for _, a in {"PartyId", "PartyLeader", "PartyMembers"} do p:SetAttribute(a, nil) end
	p:SetAttribute("PartySize", 1)
end

function Parties.Get(p) return partyOf[p] end
-- everyone in p's party (just {p} if they're not in one), leader first
function Parties.Members(p)
	local party = partyOf[p]
	if not party then return {p} end
	local lead = leaderOf(party)
	local out = {lead}
	for _, m in party.Members do if m ~= lead then table.insert(out, m) end end
	return out
end
function Parties.Leader(p)
	local party = partyOf[p]
	return party and leaderOf(party) or p
end
function Parties.IsLeader(p) return Parties.Leader(p) == p end
function Parties.Size(p) return partyOf[p] and #partyOf[p].Members or 1 end
-- {Id, Leader, Members = {userIds}} (for teleport data)
function Parties.Info(p)
	local party = partyOf[p]
	if not party then return nil end
	local ids = {}
	for _, m in party.Members do table.insert(ids, m.UserId) end
	return {Id = party.Id, Leader = leaderOf(party).UserId, Members = ids}
end

function Parties.Leave(p, reason)
	local party = partyOf[p]
	if not party then return end
	partyOf[p] = nil
	local i = table.find(party.Members, p)
	if i then table.remove(party.Members, i) end
	clearAttrs(p)
	if #party.Members <= 1 then
		-- nobody left to party with
		for _, m in party.Members do partyOf[m] = nil clearAttrs(m) end
		byId[party.Id] = nil
		party.Members = {}
	else
		if party.LeaderId == p.UserId then party.LeaderId = party.Members[1].UserId end
		publish(party)
	end
	changed:Fire(party, reason or "left", p)
end

-- adds `newMember` to `host`'s party (makes one if host has none)
function Parties.Join(host, newMember, maxSize)
	if host == newMember then return false end
	local party = partyOf[host]
	if party and #party.Members >= (maxSize or 4) then return false end
	if partyOf[newMember] then Parties.Leave(newMember, "switched") end
	if not party then
		party = {Id = HttpService:GenerateGUID(false):sub(1, 8), LeaderId = host.UserId, Members = {host}}
		byId[party.Id] = party
		partyOf[host] = party
	end
	table.insert(party.Members, newMember)
	partyOf[newMember] = party
	publish(party)
	changed:Fire(party, "joined", newMember)
	return true
end

-- after a teleport: put this player back into their party (info = Parties.Info from the old server)
function Parties.Restore(p, info)
	if type(info) ~= "table" or type(info.Id) ~= "string" then return end
	if partyOf[p] then return end
	local party = byId[info.Id]
	if not party then
		party = {Id = info.Id, LeaderId = tonumber(info.Leader) or p.UserId, Members = {}}
		byId[party.Id] = party
	end
	table.insert(party.Members, p)
	partyOf[p] = party
	if #party.Members >= 2 then publish(party) else p:SetAttribute("PartySize", 1) end
	changed:Fire(party, "restored", p)
end

Players.PlayerAdded:Connect(function(p) p:SetAttribute("PartySize", 1) end)
for _, p in Players:GetPlayers() do if not p:GetAttribute("PartySize") then p:SetAttribute("PartySize", 1) end end
Players.PlayerRemoving:Connect(function(p) Parties.Leave(p, "quit") end)

return Parties
