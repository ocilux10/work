-- GIVE A REWARD (server): GiveReward(player, reward) -> true / false. Format: ReplicatedStorage > RewardInfo.
-- Chests are opened straight away (CrateServer rolls the balloon and the player sees the spin).
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RewardInfo = require(RS:WaitForChild("RewardInfo"))

return function(p, reward)
	if not PlayerData.Get(p) then return false end
	for _, part in RewardInfo.Parts(reward) do
		if part.Kind == "Coins" then
			PlayerData.AddCoins(p, math.floor(part.Amount))
		elseif part.Kind == "Crate" then
			local give = SSS:WaitForChild("CrateServer"):WaitForChild("Give")
			for _ = 1, part.Amount do give:Invoke(p, part.Id) end
		elseif part.Kind == "Balloon" then
			SSS:WaitForChild("SkinServer"):WaitForChild("Grant"):Invoke(p, part.Id, part.Amount)
		end
	end
	return true
end
