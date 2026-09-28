-- WATCHING TAG animation (ReplicatedStorage > WatchingTag): the red dot pulses like a live recording light,
-- the outline shine sweeps round, and the tag floats up and down a little (its Bob attribute, in studs)
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, tag in CollectionService:GetTagged("WatchingTag") do
		if tag:IsA("BillboardGui") and tag.Parent then
			local base = tag:GetAttribute("BaseOffset")
			if base == nil then base = tag.StudsOffset tag:SetAttribute("BaseOffset", base) end
			tag.StudsOffset = base + Vector3.new(0, math.sin(t * 2.2) * (tag:GetAttribute("Bob") or 0.15), 0)
			local dot = tag:FindFirstChild("Dot", true)
			if dot then
				local a = (math.sin(t * 5) + 1) / 2
				dot.BackgroundTransparency = 0.05 + a * 0.45
				local glow = dot:FindFirstChild("Glow")
				if glow then glow.Transparency = 0.2 + a * 0.8 end
			end
			local pill = tag:FindFirstChild("Pill")
			local stroke = pill and pill:FindFirstChildOfClass("UIStroke")
			local shine = stroke and stroke:FindFirstChild("Shine")
			if shine then shine.Rotation = (t * 120) % 360 end
		end
	end
end)
