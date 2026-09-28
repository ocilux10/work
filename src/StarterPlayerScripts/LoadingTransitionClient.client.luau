-- QUICK LOADING SCREEN going into / out of the practice arena or aim training.
-- Look: StarterGui > LoadingScreen (Fade = whole screen; Title / Bar > Fill are optional - restyle or delete).
-- Timing (seconds) + on / off: ReplicatedStorage > LoadingTransition attributes Enabled / FadeIn / Hold / FadeOut.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local remote = RS:WaitForChild("LoadingTransition")
local token = 0
local function parts()
	local g = pg:FindFirstChild("LoadingScreen")
	local fade = g and g:FindFirstChild("Fade")
	if not fade then return end
	local list = {}
	for _, d in {fade, table.unpack(fade:GetDescendants())} do
		if d:IsA("GuiObject") then
			local props = {}
			if d:GetAttribute("BgT") == nil then d:SetAttribute("BgT", d.BackgroundTransparency) end
			props.BackgroundTransparency = d:GetAttribute("BgT")
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				if d:GetAttribute("TxtT") == nil then d:SetAttribute("TxtT", d.TextTransparency) end
				props.TextTransparency = d:GetAttribute("TxtT")
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
				if d:GetAttribute("ImgT") == nil then d:SetAttribute("ImgT", d.ImageTransparency) end
				props.ImageTransparency = d:GetAttribute("ImgT")
			end
			table.insert(list, {d, props})
		end
	end
	return g, fade, list
end
local function set(list, a, time)
	for _, e in list do
		local goal = {}
		for k, v in e[2] do goal[k] = 1 - (1 - v) * a end
		if time > 0 then TweenService:Create(e[1], TweenInfo.new(time, Enum.EasingStyle.Quad), goal):Play()
		else for k, v in goal do e[1][k] = v end end
	end
end
-- other client scripts (e.g. the balloon Inspect screen): LoadingTransitionClient.Play:Fire("In" / "Out")
local function run(kind)
	local g, fade, list = parts()
	if not g then return end
	token += 1
	local my = token
	local fill = fade:FindFirstChild("Fill", true)
	if kind == "In" then
		g.Enabled = true
		set(list, 0, 0)
		set(list, 1, remote:GetAttribute("FadeIn") or 0.15)
		if fill then
			fill.Size = UDim2.fromScale(0, 1)
			local total = (remote:GetAttribute("FadeIn") or 0.15) + (remote:GetAttribute("Hold") or 0.12)
			TweenService:Create(fill, TweenInfo.new(total, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(1, 1)}):Play()
		end
		task.delay(3, function() if token == my and g.Enabled then g.Enabled = false end end) -- (never stuck)
	elseif kind == "Out" then
		local t = remote:GetAttribute("FadeOut") or 0.3
		set(list, 0, t)
		task.delay(t, function() if token == my then g.Enabled = false end end)
	end
end
remote.OnClientEvent:Connect(run)
local play = script:FindFirstChild("Play") or Instance.new("BindableEvent")
play.Name = "Play"
play.Parent = script
play.Event:Connect(run)
