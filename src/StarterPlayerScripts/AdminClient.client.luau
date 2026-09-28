-- ADMIN PANEL (client). Settings: ReplicatedStorage > Admin > AdminConfig. Server: ServerScriptService > AdminServer.
-- Admins get a button in the top bar (TopbarPlus) that opens / closes StarterGui > Main > AdminFrame.
-- Every command row (AdminFrame > ScrollingFrame > CommandsSecition > <Command>) is found by name:
--   Target / Amount / Reason / Duration / Pass = text boxes, RunButton = do it, SelectButton = pick a balloon.
--   Pressing RunButton asks to confirm: wait ConfirmTime seconds, then press it again.
-- LogsButton opens AdminFrame > Logs (LogRow = one line). SelectButton opens AdminFrame > BalloonPicker (Slot template).
-- Everyone (not just admins) gets the chat + notice messages from admin actions done to them.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("Admin")
local Config = require(folder:WaitForChild("AdminConfig"))
local Remote = folder:WaitForChild("Command")
local Notify = folder:WaitForChild("Notify")
local SFX = require(RS:WaitForChild("SFX"))
local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))

------------------------------------------------------------ MESSAGES (chat + notice)
local function notice(text)
	local main = pg:FindFirstChild("Main")
	local n = main and main:FindFirstChild("DuelNotice")
	if not (n and n:IsA("TextLabel")) then return end
	n.Text = text
	n.Visible = true
	local token = (n:GetAttribute("Token") or 0) + 1
	n:SetAttribute("Token", token)
	task.delay(3, function() if n:GetAttribute("Token") == token then n.Visible = false end end)
end
local function chat(text, prefix, color)
	pcall(function()
		local ch = TextChatService:WaitForChild("TextChannels", 5):WaitForChild("RBXGeneral", 5)
		local safe = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		ch:DisplaySystemMessage(('<font color="%s">%s</font> %s'):format(color or "#FF4B4B", prefix or "[ADMIN]", safe))
	end)
end
Notify.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" or type(msg.Text) ~= "string" then return end
	chat(msg.Text, msg.Prefix, msg.Color)
	notice(msg.Text)
	SFX.Play("Notify")
end)

------------------------------------------------------------ ONLY ADMINS FROM HERE
if not player:GetAttribute("IsAdmin") then player:GetAttributeChangedSignal("IsAdmin"):Wait() end

local frame
local selectedBalloon
local function setText(o, t) if o and (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then o.Text = t end end
local function label(b) return b and b:FindFirstChild("Text") end

-- TOP BAR BUTTON (icon only): a shield. Your own picture instead: put its image id in this script's Image attribute
-- (e.g. rbxassetid://123), ImageScale = its size.
local Icon = require(RS:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local icon = Icon.new()
icon:setName("AdminPanel")
if (script:GetAttribute("Image") or "") ~= "" then
	icon:setImage(script:GetAttribute("Image"))
	icon:setImageScale(script:GetAttribute("ImageScale") or 0.55)
else
	icon:setLabel("🛡️")
end
icon:align("Left")
icon:oneClick()
icon:modifyTheme({
	{"IconCorners", "CornerRadius", UDim.new(1, 0)},
	{"IconButton", "BackgroundColor3", Color3.fromRGB(18, 18, 21)},
	{"IconButton", "BackgroundTransparency", 0.08},
})
icon.selected:Connect(function()
	if frame then frame.Visible = not frame.Visible SFX.Play(frame.Visible and "Open" or "Close") end
end)

------------------------------------------------------------ CONFIRM (wait, then press again)
local function hookRun(row, btn, run)
	local lbl = label(btn)
	local original = lbl and lbl.Text or ""
	btn:SetAttribute("Original", original)
	local state, token = "idle", 0
	local function reset()
		token += 1
		state = "idle"
		setText(lbl, btn:GetAttribute("Original") or original)
		btn.AutoButtonColor = true
		local s = btn:FindFirstChild("ConfirmTint") if s then s:Destroy() end
	end
	btn.Activated:Connect(function()
		if state == "idle" then
			state = "waiting"
			token += 1
			local my = token
			SFX.Play("ButtonPress")
			btn:SetAttribute("Original", lbl and lbl.Text or original)
			local tint = Instance.new("UIGradient")
			tint.Name = "ConfirmTint"
			tint.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120))
			tint.Parent = btn
			for i = math.ceil(Config.ConfirmTime or 3), 1, -1 do
				if token ~= my then return end
				setText(lbl, "Confirm (" .. i .. ")")
				task.wait(1)
			end
			if token ~= my then return end
			tint:Destroy()
			state = "ready"
			setText(lbl, "Confirm?")
			SFX.Play("Toggle")
			task.delay(Config.ConfirmWindow or 6, function() if token == my and state == "ready" then reset() end end)
		elseif state == "ready" then
			state = "busy"
			setText(lbl, "...")
			local ok, res, msg = pcall(run)
			if not ok then res, msg = false, "Something went wrong" end
			if not res then notice(msg or "Failed") SFX.Play("Error") end
			reset()
		end
	end)
	return reset
end

local function field(row, name)
	local b = row:FindFirstChild(name)
	return b and b:IsA("TextBox") and b.Text:gsub("^%s+", ""):gsub("%s+$", "") or nil
end

------------------------------------------------------------ BALLOON PICKER
local function openPicker(onPick)
	local pk = frame:FindFirstChild("BalloonPicker")
	if not pk then return end
	local sc = pk:FindFirstChild("ScrollingFrame")
	local tpl = pk:FindFirstChild("Slot")
	local search = pk:FindFirstChild("Search")
	local function fill()
		for _, c in sc:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local q = search and search.Text:lower() or ""
		local i = 0
		for _, s in Skins.Skins do
			local r = Skins.Rarity(s.Id)
			if s.Id ~= Skins.DefaultId and (q == "" or s.Name:lower():find(q, 1, true) or r.Text:lower():find(q, 1, true)) then
				i += 1
				local c = tpl:Clone()
				c.Visible = true
				c.LayoutOrder = -r.Order * 100 + i
				setText(c:FindFirstChild("SkinName"), s.Name)
				setText(c:FindFirstChild("SkinType"), r.Text .. " " .. s.Type)
				local bar = c:FindFirstChild("Bar") if bar then bar.BackgroundColor3 = r.Color end
				local cnt = c:FindFirstChild("Count") if cnt then cnt.Visible = false end
				local vp = c:FindFirstChild("View")
				local m = Skins.ForViewport(Skins.Model(s.Id))
				if vp and m then
					m.CFrame = CFrame.new()
					m.Parent = vp
					local cam = Instance.new("Camera")
					cam.FieldOfView = 30
					cam.CFrame = CFrame.lookAt(Vector3.new(0, m.Size.Y * 0.05, m.Size.Y * 2.5), Vector3.zero)
					cam.Parent = vp
					vp.CurrentCamera = cam
				end
				c.Button.Activated:Connect(function()
					pk.Visible = false
					SFX.Play("Toggle")
					onPick(s.Id)
				end)
				c.Parent = sc
			end
		end
	end
	if search and not search:GetAttribute("Hooked") then
		search:SetAttribute("Hooked", true)
		search:GetPropertyChangedSignal("Text"):Connect(function() if pk.Visible then fill() end end)
	end
	fill()
	pk.Visible = true
	SFX.Play("Open")
end

------------------------------------------------------------ LOGS
local function openLogs()
	local lg = frame:FindFirstChild("Logs")
	if not lg then return end
	local sc = lg:FindFirstChild("ScrollingFrame")
	local tpl = lg:FindFirstChild("LogRow")
	for _, c in sc:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	lg.Visible = true
	SFX.Play("Open")
	local ok, res, list = pcall(function() return Remote:InvokeServer("Logs") end)
	list = ok and res and list or {}
	for i, e in list do
		local r = tpl:Clone()
		r.Visible = true
		r.LayoutOrder = i
		local okT, when = pcall(function() return DateTime.fromUnixTimestamp(e.t or 0):FormatLocalTime("DD/MM HH:mm", "en-gb") end)
		setText(r:FindFirstChild("When"), okT and when or "")
		setText(r:FindFirstChild("Line"), tostring(e.line or ""))
		r.Parent = sc
	end
	local empty = lg:FindFirstChild("Empty") if empty then empty.Visible = #list == 0 end
end

------------------------------------------------------------ STAT LOOKUP PAGE (a copy of AdminFrame > Logs: When = stat, Line = value)
local function openStats(title, rows)
	local page = frame:FindFirstChild("Stats")
	if not page then
		local logs = frame:FindFirstChild("Logs")
		if not logs then return end
		page = logs:Clone()
		page.Name = "Stats"
		page.Parent = frame
		local back = page:FindFirstChild("Back")
		if back and back:IsA("GuiButton") then back.Activated:Connect(function() page.Visible = false SFX.Play("Close") end) end
	end
	setText(page:FindFirstChild("Title"), title:upper())
	local empty = page:FindFirstChild("Empty") if empty then empty.Visible = false end
	local sc = page:FindFirstChild("ScrollingFrame")
	local tpl = page:FindFirstChild("LogRow")
	if tpl then tpl.Visible = false end
	for _, c in sc:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	for i, r in rows do
		local row = tpl:Clone()
		row.Name = "Stat" .. i
		row.Visible = true
		row.LayoutOrder = i
		setText(row:FindFirstChild("When"), tostring(r[1]))
		setText(row:FindFirstChild("Line"), tostring(r[2]))
		row.Parent = sc
	end
	page.Visible = true
	SFX.Play("Open")
end

-- the rows added by script (copies of the Join / Kick rows, so they look the same):
--   {name, copy of, command text, button text, keep these boxes}
local EXTRA_ROWS = {
	{"StatLookup", "Join", "Stat Lookup", "Look Up", {"Target"}},
	{"ReloadServer", "Join", "Reload Server", "Reload", {}},
	{"ShutdownServer", "Kick", "Shutdown Server", "Shutdown", {"Reason"}},
}
local function addExtraRows(cs)
	for i, e in EXTRA_ROWS do
		local name, from, text, btn, keep = e[1], e[2], e[3], e[4], e[5]
		local src = cs:FindFirstChild(from)
		if src and not cs:FindFirstChild(name) then
			local row = src:Clone()
			row.Name = name
			row.LayoutOrder = 1000 + i
			for _, box in {"Target", "Amount", "Reason", "Duration", "Pass"} do
				local b = row:FindFirstChild(box)
				if b and not table.find(keep, box) then b:Destroy() end
			end
			local r = row:FindFirstChild("Reason")
			if r and r:IsA("TextBox") then r.Text = "" r.PlaceholderText = "Kick message (optional)" end
			setText(row:FindFirstChild("CommandText"), text)
			setText(label(row:FindFirstChild("RunButton")), btn)
			row.Parent = cs
		end
	end
end

------------------------------------------------------------ HOOK THE PANEL (again after every respawn)
local function hook(main)
	frame = main:WaitForChild("AdminFrame", 10)
	if not frame then return end
	frame.Visible = false
	local off = frame:FindFirstChild("TopBar") and frame.TopBar:FindFirstChild("Off")
	if off and off:IsA("GuiButton") then off.Activated:Connect(function() frame.Visible = false SFX.Play("Close") end) end
	local oldStats = frame:FindFirstChild("Stats") if oldStats then oldStats:Destroy() end
	for _, n in {"Logs", "BalloonPicker"} do
		local p = frame:FindFirstChild(n)
		if p then
			p.Visible = false
			local back = p:FindFirstChild("Back")
			if back and back:IsA("GuiButton") then back.Activated:Connect(function() p.Visible = false SFX.Play("Close") end) end
		end
	end
	local logsBtn = frame:FindFirstChild("LogsButton", true)
	if logsBtn and logsBtn:IsA("GuiButton") then logsBtn.Activated:Connect(openLogs) end
	local cs = frame:FindFirstChild("CommandsSecition", true)
	if not cs then return end
	addExtraRows(cs)
	for _, row in cs:GetChildren() do
		if row:IsA("GuiObject") then
			-- the player box starts with YOUR name (until you change it)
			local tb = row:FindFirstChild("Target")
			if tb and tb:IsA("TextBox") and tb.Text == "" then tb.Text = player.Name end
			local run = row:FindFirstChild("RunButton")
			if run and run:IsA("GuiButton") and row.Name == "StatLookup" then
				-- (looking only: no confirm step)
				run.Activated:Connect(function()
					SFX.Play("ButtonPress")
					local ok, res, msg, rows = pcall(function() return Remote:InvokeServer("StatLookup", {Target = field(row, "Target")}) end)
					if ok and res and type(rows) == "table" then openStats(msg or "Stats", rows)
					else notice((ok and msg) or "Failed") SFX.Play("Error") end
				end)
			elseif run and run:IsA("GuiButton") then
				local cmd = row.Name
				hookRun(row, run, function()
					local args = {Target = field(row, "Target"), Amount = field(row, "Amount"), Reason = field(row, "Reason"),
						Duration = field(row, "Duration"), Pass = field(row, "Pass")}
					if cmd == "GiveBalloon" then args.Id = selectedBalloon end
					return Remote:InvokeServer(cmd, args)
				end)
			end
			local sel = row:FindFirstChild("SelectButton")
			if sel and sel:IsA("GuiButton") and run then
				sel.Activated:Connect(function()
					openPicker(function(id)
						selectedBalloon = id
						local l = label(run)
						setText(l, "Give " .. Skins.Get(id).Name)
						run:SetAttribute("Original", l and l.Text)
					end)
				end)
			end
		end
	end
end
local m0 = pg:FindFirstChild("Main")
if m0 then task.spawn(hook, m0) end
pg.ChildAdded:Connect(function(c) if c.Name == "Main" then task.spawn(hook, c) end end)
