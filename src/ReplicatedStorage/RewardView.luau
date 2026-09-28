-- SHOWS A REWARD'S PICTURE on a card (client). RewardView.Show(iconImageLabel, reward, coinImage)
--   coins -> the ImageLabel's picture (or coinImage)   chest / balloon -> its 3D model in a ViewportFrame on top of it
--   reward.Image -> that picture
local RS = game:GetService("ReplicatedStorage")
local RewardInfo = require(RS:WaitForChild("RewardInfo"))
local M = {}

local function frame(vp, model)
	local cf, size = model:GetBoundingBox()
	local r = size.Magnitude / 2
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, r * 0.35, r / math.tan(math.rad(15)) * 1.05), cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

function M.Show(icon, reward, coinImage)
	if not icon then return end
	local old = icon.Parent and icon.Parent:FindFirstChild(icon.Name .. "_3D")
	if old then old:Destroy() end
	icon.Visible = true
	if type(reward) == "table" and type(reward.Image) == "string" and reward.Image ~= "" then
		if icon:IsA("ImageLabel") then icon.Image = reward.Image end
		return
	end
	local main = RewardInfo.Parts(reward)[1]
	if not main then return end
	if main.Kind == "Coins" then
		if coinImage and coinImage ~= "" and icon:IsA("ImageLabel") then icon.Image = coinImage end
		return
	end
	local src
	if main.Kind == "Crate" then
		local cfg = require(RS:WaitForChild("Crates"):WaitForChild("CrateConfig"))
		local c = cfg.ById[main.Id]
		src = RS.Crates:WaitForChild("Models"):FindFirstChild(c and c.Model or main.Id)
	else
		local Skins = require(RS:WaitForChild("BalloonSkins"):WaitForChild("SkinConfig"))
		src = Skins.Model(main.Id)
	end
	if not src then return end
	local m = main.Kind == "Crate" and src:Clone() or src
	if m:IsA("BasePart") then local mdl = Instance.new("Model") m.CFrame = CFrame.new() m.Parent = mdl m = mdl end
	local vp = Instance.new("ViewportFrame")
	vp.Name = icon.Name .. "_3D"
	vp.BackgroundTransparency = 1
	vp.AnchorPoint, vp.Position, vp.Size, vp.ZIndex = icon.AnchorPoint, icon.Position, icon.Size, icon.ZIndex
	vp.LayoutOrder = icon.LayoutOrder
	vp.Ambient = Color3.fromRGB(170, 170, 170)
	vp.LightDirection = Vector3.new(-1, -1.5, -1)
	m.Parent = vp
	frame(vp, m)
	for _, c in icon:GetChildren() do if c:IsA("UIAspectRatioConstraint") then c:Clone().Parent = vp end end
	vp.Parent = icon.Parent
	icon.Visible = false
end

return M
