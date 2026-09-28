-- REBINDABLE MOVEMENT (Settings > Controls > Keybinds: Move Forward / Backward / Strafe / Jump)
-- Roblox's own controls only know W A S D / arrows / Space. When you change any of those binds, this script takes
-- over: it blocks Roblox's movement keys and moves / jumps you with your own keys instead.
-- With the default binds it does nothing (Roblox's normal controls are used).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local GS = require(RS:WaitForChild("GameSettings"))

local player = Players.LocalPlayer
local MOVE = {"MoveForward", "MoveBackward", "StrafeLeft", "StrafeRight", "Jump"}
local ROBLOX_KEYS = {Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down,
	Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space}
local active = false

local function custom()
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then return false end
	for _, a in MOVE do if not GS.IsDefault("Key_" .. a) then return true end end
	return false
end

local function locked()
	return player:GetAttribute("Loading") or player:GetAttribute("Frozen") or UIS:GetFocusedTextBox() ~= nil
end

local function step()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if locked() then player:Move(Vector3.zero, true) return end
	local f = (GS.IsDown("MoveForward") and 1 or 0) - (GS.IsDown("MoveBackward") and 1 or 0)
	local r = (GS.IsDown("StrafeRight") and 1 or 0) - (GS.IsDown("StrafeLeft") and 1 or 0)
	local v = Vector3.new(r, 0, -f)
	if v.Magnitude > 1 then v = v.Unit end
	player:Move(v, true)
end

local lastJump = 0
local function jump(input)
	if not active or locked() or not GS.Is("Jump", input) then return end
	if os.clock() - lastJump < 0.15 then return end -- (a blocked key can arrive twice)
	lastJump = os.clock()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end
UIS.InputBegan:Connect(function(input) jump(input) end)

local function refresh()
	local want = custom()
	if want == active then return end
	active = want
	if active then
		-- block Roblox's own movement keys (they'd still move you the default way)
		CAS:BindActionAtPriority("CustomMoveKeys", function(_, state, input)
			if state == Enum.UserInputState.Begin then jump(input) end
			return Enum.ContextActionResult.Sink
		end, false,
			Enum.ContextActionPriority.High.Value + 100, table.unpack(ROBLOX_KEYS))
		RunService:BindToRenderStep("CustomMoveKeys", Enum.RenderPriority.Input.Value + 1, step)
	else
		CAS:UnbindAction("CustomMoveKeys")
		pcall(function() RunService:UnbindFromRenderStep("CustomMoveKeys") end)
		player:Move(Vector3.zero, true)
	end
end
GS.Changed:Connect(function(key) if key:sub(1, 4) == "Key_" then refresh() end end)
refresh()
