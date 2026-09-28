-- SAVED SETTINGS: the Settings menu (ReplicatedStorage > GameSettings) saves everything as one "Prefs" JSON string.
-- It's kept in the player's data and put on the player as the attribute "Setting_Prefs" (the client reads it back).
-- Settings the SERVER needs (privacy, gifts) are also put on the player as "Pref_<Key>" attributes.
-- Small separate UI choices (like the lobby list being open) still use "Setting_<Name>".
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local PlayerData = require(game:GetService("ServerStorage"):WaitForChild("PlayerData"))
local Remote = RS:WaitForChild("Matchmaking"):WaitForChild("Remotes"):WaitForChild("SaveSetting")

local ALLOWED = {LobbiesOpen = "boolean", Prefs = "string"}
local SERVER_PREFS = {"PartyRequests", "DuelRequests", "TradeRequests", "AcceptGifts"}
local MAX_PREFS = 6000

local function mirror(p, json)
	local ok, t = pcall(HttpService.JSONDecode, HttpService, json or "{}")
	if not ok or type(t) ~= "table" then t = {} end
	for _, k in SERVER_PREFS do
		local v = t[k]
		if type(v) == "table" then v = nil end
		p:SetAttribute("Pref_" .. k, v)
	end
end

local function load(p)
	local t0 = os.clock()
	while p.Parent == Players and not PlayerData.Get(p) and os.clock() - t0 < 60 do task.wait(0.5) end
	local d = PlayerData.Get(p)
	if not d then return end
	d.Settings = d.Settings or {}
	for k, v in d.Settings do
		if ALLOWED[k] then p:SetAttribute("Setting_" .. k, v) end
	end
	mirror(p, d.Settings.Prefs)
	p:SetAttribute("SettingsLoaded", true)
end
Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do task.spawn(load, p) end

Remote.OnServerEvent:Connect(function(p, key, value)
	if type(key) ~= "string" or ALLOWED[key] ~= typeof(value) then return end
	if key == "Prefs" and #value > MAX_PREFS then return end
	local d = PlayerData.Get(p)
	if not d then return end
	d.Settings = d.Settings or {}
	d.Settings[key] = value
	p:SetAttribute("Setting_" .. key, value)
	if key == "Prefs" then mirror(p, value) end
end)
