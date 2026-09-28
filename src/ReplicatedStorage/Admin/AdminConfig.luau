-- ADMIN PANEL SETTINGS (StarterGui > Main > AdminFrame, ServerScriptService > AdminServer)
local C = {}
-- who gets the panel (and the shield button in the top bar)
C.UserIds = {4297323135, 2006839416}  -- add more user ids here
C.GroupId = 742983897
C.MinGroupRank = 255                  -- 255 = the group owner only. Lower it (e.g. 250) to let more ranks in
C.ConfirmTime = 3                     -- seconds you wait before you can press Confirm
C.ConfirmWindow = 6                   -- seconds Confirm stays clickable after that
C.LogKeep = 200                       -- how many actions the logs remember (all servers)
C.ChatPrefix = "[ADMIN]"              -- in front of the chat messages
C.ChatColor = "#FF4B4B"
C.MaxCoins = 100000000                -- biggest amount one command can give / set
return C
