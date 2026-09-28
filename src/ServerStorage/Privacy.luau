-- WHO CAN SEND YOU REQUESTS (Settings > Other > Privacy): "Everyone" / "Friends" / "No one"
--   Privacy.Allows(target, sender, "PartyRequests" / "DuelRequests" / "TradeRequests") -> true / false
local Privacy = {}
local friendCache = {} -- ["a_b"] = {result, time}
function Privacy.Allows(target, sender, key)
	local mode = target:GetAttribute("Pref_" .. key) or "Everyone"
	if mode == "Everyone" then return true end
	if mode == "No one" then return false end
	-- Friends
	local id = math.min(target.UserId, sender.UserId) .. "_" .. math.max(target.UserId, sender.UserId)
	local c = friendCache[id]
	if c and os.clock() - c[2] < 60 then return c[1] end
	local ok, isFriend = pcall(function() return target:IsFriendsWith(sender.UserId) end)
	isFriend = ok and isFriend == true
	friendCache[id] = {isFriend, os.clock()}
	return isFriend
end
return Privacy
