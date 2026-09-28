local QuestConfig = {}

QuestConfig.QuestsPerDay = 3
QuestConfig.CycleHours = 24
QuestConfig.QuickKillWindow = 20 -- seconds, for the "Kill 5 Players Within 20 Seconds" quest

-- colours in the UI
QuestConfig.DoneColor = Color3.fromRGB(85, 255, 0)   -- progress text / bar when a quest is finished
QuestConfig.BarTweenTime = 0.9                          -- how long the end screen bars take to fill

QuestConfig.Quests = {
	{Id = "Kills20",      Name = "Kill 20 Players",                    Stat = "Kills",         Goal = 20,   XP = 150, Coins = 100},
	{Id = "Play1v1x3",    Name = "Play Three 1v1 Matches",             Stat = "Matches1v1",    Goal = 3,    XP = 100, Coins = 75},
	{Id = "Headshot5",    Name = "Headshot 5 Players",                 Stat = "HeadshotKills", Goal = 5,    XP = 125, Coins = 90},
	{Id = "Wins5",        Name = "Win 5 Games",                        Stat = "Wins",          Goal = 5,    XP = 200, Coins = 150},
	{Id = "Jumpshot10",   Name = "JumpShot 10 Players",                Stat = "JumpshotKills", Goal = 10,   XP = 175, Coins = 120},
	{Id = "Damage2500",   Name = "Deal 2500 Damage",                   Stat = "Damage",        Goal = 2500, XP = 150, Coins = 100},
	{Id = "Play15",       Name = "Play For 15 Minutes",                Stat = "Minutes",       Goal = 15,   XP = 75,  Coins = 50},
	{Id = "LongRange5",   Name = "5 Long Range Kills",        Stat = "LongKills",     Goal = 5,    XP = 150, Coins = 100},
	{Id = "Streak3",      Name = "3 Kills Without Dying", Stat = "Streak3",       Goal = 1,    XP = 125, Coins = 90},
	{Id = "MVP2",         Name = "Get MVP Twice",                      Stat = "MVP",           Goal = 2,    XP = 200, Coins = 150},
	{Id = "QuickKills5",  Name = "5 Kills In 20 Seconds",   Stat = "QuickKills",    Goal = 5,    XP = 250, Coins = 175},
}

return QuestConfig
