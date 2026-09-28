-- PLAYER PROFILES
-- Answers "show me this player's profile" (inspect → Main > PlayerProfile) with their saved stats.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local PlayerData = require(SS:WaitForChild("PlayerData"))
local GetProfile = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes"):WaitForChild("GetProfile")

local lastAsk = {}
GetProfile.OnServerInvoke = function(asker, target)
	-- light rate limit
	local now = os.clock()
	if lastAsk[asker] and now - lastAsk[asker] < 0.25 then return nil end
	lastAsk[asker] = now
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then return nil end
	return PlayerData.GetPublicProfile(target)
end

Players.PlayerRemoving:Connect(function(p) lastAsk[p] = nil end)
