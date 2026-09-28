-- VERIFIED BADGE next to display names (Roblox's own blue tick character, shows in any TextLabel font)
--   NameBadge.Of(player)                 -> "DisplayName" or "DisplayName <tick>" if the account is verified
--   NameBadge.Format(name, isVerified)   -> same thing from saved data (replays, offline profiles)
-- Usernames (@name) never get it.
local NameBadge = {}
NameBadge.Tick = utf8.char(0xE000)

function NameBadge.Format(name, verified)
	name = tostring(name or "")
	if verified and name ~= "" then return name .. " " .. NameBadge.Tick end
	return name
end

function NameBadge.Verified(p)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then return false end
	local ok, v = pcall(function() return p.HasVerifiedBadge end)
	return ok and v == true
end

function NameBadge.Of(p)
	if typeof(p) ~= "Instance" then return "" end
	return NameBadge.Format(p.DisplayName, NameBadge.Verified(p))
end

return NameBadge
