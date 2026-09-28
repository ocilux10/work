-- MONTHLY LEADERBOARD REWARDS - edit freely. Server: ServerScriptService > LeaderboardRewardsServer.
-- When a month ends, the top players of each MONTHLY leaderboard below (ReplicatedStorage > LeaderboardConfig) win the
-- reward of their tier. They claim it at the podium (Workspace > Lobby > Podium > Prox > ProximityPrompt) - or it's
-- given by itself when they join, see Delivery. Last month's rewards can be claimed until the NEXT month ends.
-- A reward is written like this (any mix - see ReplicatedStorage > RewardInfo):
--   {Coins = 5000}   {Crate = "Exclusive"}   {Crate = "Premium", CrateCount = 3}   {Coins = 2000, Crate = "Basic"}
local M = {}

-- Board = the Name of a monthly board in LeaderboardConfig. Title = shown in the menu.
-- Tiers: Top = the lowest place that gets this reward (Top = 5 -> places 4 and 5 when the tier before is Top = 3).
M.Boards = {
	{
		Board = "Kills", Title = "Monthly Kills",
		Tiers = {
			{Top = 1,   Reward = {Coins = 25000, Crate = "Exclusive", CrateCount = 3}},
			{Top = 2,   Reward = {Coins = 15000, Crate = "Exclusive", CrateCount = 2}},
			{Top = 3,   Reward = {Coins = 10000, Crate = "Exclusive"}},
			{Top = 5,   Reward = {Coins = 7500,  Crate = "Premium", CrateCount = 2}},
			{Top = 10,  Reward = {Coins = 5000,  Crate = "Premium"}},
			{Top = 25,  Reward = {Crate = "Premium"}},
			{Top = 50,  Reward = {Coins = 2500}},
			{Top = 100, Reward = {Coins = 1000}},
		},
	},
	{
		Board = "Wins", Title = "Monthly Wins",
		Tiers = {
			{Top = 1,   Reward = {Coins = 25000, Crate = "Exclusive", CrateCount = 3}},
			{Top = 2,   Reward = {Coins = 15000, Crate = "Exclusive", CrateCount = 2}},
			{Top = 3,   Reward = {Coins = 10000, Crate = "Exclusive"}},
			{Top = 5,   Reward = {Coins = 7500,  Crate = "Premium", CrateCount = 2}},
			{Top = 10,  Reward = {Coins = 5000,  Crate = "Premium"}},
			{Top = 25,  Reward = {Crate = "Premium"}},
			{Top = 50,  Reward = {Coins = 2500}},
			{Top = 100, Reward = {Coins = 1000}},
		},
	},
}

M.Delivery = "Claim"      -- "Claim" = press Claim at the podium,  "Auto" = given by itself as soon as they join
M.MinScore = 1            -- you need at least this much on the board to win anything

-- THE PODIUM (in Workspace): path to the ProximityPrompt that opens the menu
M.PromptPath = {"Lobby", "Podium", "Prox", "ProximityPrompt"}
M.PromptActionText = "Leaderboard Rewards" -- the prompt's text ("" = leave it as it is in Studio)
M.PromptObjectText = "Monthly"

-- TEXTS ({time} = "3d 4h", {board} = board title, {place} = "#4", {reward} = "5,000 Coins + Premium Chest")
M.Title = "LEADERBOARD REWARDS"
M.InfoText = "Rewards are MONTHLY! Finish in the top 100 by the end of the month to win. This month ends in {time}."
M.PlaceText = "#{place}"             -- a card for one place (#1, #2, #3)
M.RangeText = "TOP {top}"            -- a card for a range (TOP 5, TOP 10 ...)
M.ClaimText = "CLAIM"
M.NothingText = "NOTHING TO CLAIM"   -- button when you didn't place last month
M.ClaimedText = "CLAIMED"            -- button when you already took last month's
M.WonText = "You placed {place} on {board} last month: {reward}!"
M.SwitchText = "{board}  >"          -- the button that switches between boards

M.YourPlaceColor = Color3.fromRGB(255, 200, 40) -- outline on the card you won last month

return M
