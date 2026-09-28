-- PARTY INVITES
-- client -> server:  Party:FireServer({Action = "Invite", Target = player})
--                    Party:FireServer({Action = "Respond", Id = id, Accept = true/false})
--                    Party:FireServer({Action = "Leave"})
--                    Party:FireServer({Action = "Kick", Target = player})      (leader only)
--                    Party:FireServer({Action = "Mute", UserId = id, Muted = true/false})  (PartyPrompt > MuteToggle)
-- server -> client:  {Kind = "InviteOver", UserId}  (your invite to them was answered / ran out: button says Invite again)
-- server -> client:  {Kind = "Incoming", Id, FromUserId, FromName, FromUsername, Timeout}
-- Short messages go through the 1v1 notice (Main > DuelNotice).
-- Settings: ReplicatedStorage > Matchmaking > Config > Party
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local NameBadge = require(game:GetService("ReplicatedStorage"):WaitForChild("NameBadge")) -- verified tick after display names
local MM = RS:WaitForChild("Matchmaking")
local Config = require(MM:WaitForChild("Config"))
local Remotes = MM:WaitForChild("Remotes")
local PartyRemote = Remotes:WaitForChild("Party")
local DuelRemote = Remotes:WaitForChild("Duel")
local Parties = require(game:GetService("ServerStorage"):WaitForChild("Parties"))
local Privacy = require(game:GetService("ServerStorage"):WaitForChild("Privacy")) -- Settings > Other > Party Requests

local C = Config.Party or {}
local MAX = C.MaxSize or 4
local TIMEOUT = C.InviteTimeout or 20
local COOLDOWN = C.InviteCooldown or 3

local invites = {} -- [id] = {from, to}
-- MUTES: first mute of someone = MuteMinutes, muting them again = the rest of this server
local MUTE_MINUTES = C.MuteMinutes or Config.DuelMuteMinutes or 5
local mutes = {}       -- [player] = {[fromUserId] = expires (os.clock) or math.huge}
local mutedBefore = {} -- [player] = {[fromUserId] = true}
local function isMuted(p, fromUserId)
	local t = mutes[p] and mutes[p][fromUserId]
	return t ~= nil and os.clock() < t
end
local function inviteOver(from, to)
	if from and from.Parent == Players then PartyRemote:FireClient(from, {Kind = "InviteOver", UserId = to.UserId}) end
end
local lastAsk = {} -- [from] = {[to] = os.clock()}
local counter = 0

local function notice(p, text)
	if p and p.Parent == Players then DuelRemote:FireClient(p, {Kind = "Notice", Text = text}) end
end
local function busy(p)
	return p:GetAttribute("MatchId") ~= nil and not p:GetAttribute("MatchEnded")
end

PartyRemote.OnServerEvent:Connect(function(p, msg)
	if typeof(msg) ~= "table" then return end
	if msg.Action == "Invite" then
		local t = msg.Target
		if typeof(t) ~= "Instance" or not t:IsA("Player") or t == p or t.Parent ~= Players then return end
		if not Parties.IsLeader(p) then notice(p, "Only the party leader can invite") return end
		if Parties.Size(p) >= MAX then notice(p, "Your party is full") return end
		if Parties.Get(t) and Parties.Get(t) == Parties.Get(p) then notice(p, t.DisplayName .. " is already in your party") return end
		if busy(p) then notice(p, "You can't invite during a match") return end
		if busy(t) then notice(p, t.DisplayName .. " is in a match right now") return end
		lastAsk[p] = lastAsk[p] or {}
		if lastAsk[p][t] and os.clock() - lastAsk[p][t] < COOLDOWN then
			notice(p, ("You can invite %s again in %ds"):format(t.DisplayName, math.ceil(COOLDOWN - (os.clock() - lastAsk[p][t]))))
			return
		end
		if not Privacy.Allows(t, p, "PartyRequests") then
			lastAsk[p][t] = os.clock()
			notice(p, t.DisplayName .. " isn't accepting party invites")
			inviteOver(p, t)
			return
		end
		if isMuted(t, p.UserId) then
			lastAsk[p][t] = os.clock()
			notice(p, t.DisplayName .. " isn't accepting invites right now")
			inviteOver(p, t)
			return
		end
		lastAsk[p][t] = os.clock()
		counter += 1
		local id = counter
		invites[id] = {from = p, to = t}
		PartyRemote:FireClient(t, {Kind = "Incoming", Id = id, FromUserId = p.UserId, FromName = p.DisplayName, FromVerified = NameBadge.Verified(p), FromUsername = p.Name, Timeout = TIMEOUT,
			MuteForever = mutedBefore[t] ~= nil and mutedBefore[t][p.UserId] ~= nil, MuteMinutes = MUTE_MINUTES})
		PartyRemote:FireClient(p, {Kind = "Sent", UserId = t.UserId})
		notice(p, "Party invite sent to " .. t.DisplayName)
		task.delay(TIMEOUT, function()
			if invites[id] then
				invites[id] = nil
				notice(p, t.DisplayName .. " didn't answer your invite")
				inviteOver(p, t)
			end
		end)
	elseif msg.Action == "Respond" then
		local inv = invites[msg.Id]
		if not inv or inv.to ~= p then return end
		invites[msg.Id] = nil
		local from = inv.from
		inviteOver(from, p)
		if not msg.Accept then notice(from, p.DisplayName .. " declined your party invite") return end
		if from.Parent ~= Players then notice(p, "That party doesn't exist anymore") return end
		if busy(from) or busy(p) then notice(p, "Can't join a party during a match") return end
		if not Parties.IsLeader(from) then
			-- the inviter joined someone else's party meanwhile: join that one
			from = Parties.Leader(from)
		end
		if Parties.Size(from) >= MAX then notice(p, "That party is full") return end
		if Parties.Join(from, p, MAX) then
			for _, m in Parties.Members(p) do
				if m ~= p then notice(m, p.DisplayName .. " joined the party") end
			end
			notice(p, "You joined " .. Parties.Leader(p).DisplayName .. "'s party")
		end
	elseif msg.Action == "Mute" then
		local id = tonumber(msg.UserId)
		if not id then return end
		mutes[p] = mutes[p] or {}
		if msg.Muted then
			mutedBefore[p] = mutedBefore[p] or {}
			mutes[p][id] = mutedBefore[p][id] and math.huge or (os.clock() + MUTE_MINUTES * 60)
			mutedBefore[p][id] = true
			-- a muted person's pending invites to you are dropped
			for iid, inv in invites do
				if inv.to == p and inv.from.UserId == id then invites[iid] = nil inviteOver(inv.from, p) end
			end
		else
			mutes[p][id] = nil
		end
	elseif msg.Action == "Leave" then
		if not Parties.Get(p) then return end
		local others = Parties.Members(p)
		Parties.Leave(p, "left")
		notice(p, "You left the party")
		for _, m in others do if m ~= p then notice(m, p.DisplayName .. " left the party") end end
	elseif msg.Action == "Kick" then
		local t = msg.Target
		if typeof(t) ~= "Instance" or t == p or not Parties.IsLeader(p) or Parties.Get(t) ~= Parties.Get(p) or not Parties.Get(p) then return end
		local others = Parties.Members(p)
		Parties.Leave(t, "kicked")
		notice(t, "You were removed from the party")
		for _, m in others do if m ~= t then notice(m, t.DisplayName .. " was removed from the party") end end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	lastAsk[p] = nil
	mutes[p], mutedBefore[p] = nil, nil
	for id, inv in invites do if inv.from == p or inv.to == p then invites[id] = nil end end
end)
