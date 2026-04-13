--[[
	SprintService — hold Left Shift (or mobile button) to sprint.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local DEFAULT_WALK = 16
local SPRINT_WALK = 24

-- Subtle lean while sprinting (no extra assets).
local CAMERA_OFFSET_SPRINT = Vector3.new(0, -0.05, -0.18)
local CAMERA_OFFSET_IDLE = Vector3.zero

local sprinting = false
local boundHumanoid: Humanoid? = nil

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function canSprint(): boolean
	local h = boundHumanoid or getHumanoid()
	if not h then
		return false
	end
	if h.Health <= 0 then
		return false
	end
	return true
end

local function applyWalkState(on: boolean)
	local h = boundHumanoid or getHumanoid()
	if not h then
		return
	end
	h.WalkSpeed = if on then SPRINT_WALK else DEFAULT_WALK
	h.CameraOffset = if on then CAMERA_OFFSET_SPRINT else CAMERA_OFFSET_IDLE
end

local function startSprint()
	if sprinting or not canSprint() then
		return
	end
	sprinting = true
	applyWalkState(true)
end

local function stopSprint()
	if not sprinting then
		return
	end
	sprinting = false
	applyWalkState(false)
end

local function bindHumanoid(h: Humanoid)
	boundHumanoid = h
	h.WalkSpeed = DEFAULT_WALK
	h.CameraOffset = CAMERA_OFFSET_IDLE

	h:GetPropertyChangedSignal("Health"):Connect(function()
		if h.Health <= 0 then
			stopSprint()
		end
	end)
	h.Died:Once(function()
		stopSprint()
	end)
end

local function onCharacterAdded(character: Model)
	sprinting = false
	boundHumanoid = nil
	local h = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if h then
		h.WalkSpeed = DEFAULT_WALK
		h.CameraOffset = CAMERA_OFFSET_IDLE
		bindHumanoid(h)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		startSprint()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessedEvent: boolean)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		stopSprint()
	end
end)

-- Mobile: hold button to sprint.
if UserInputService.TouchEnabled then
	local pg = player:WaitForChild("PlayerGui") :: PlayerGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "SprintServiceUI"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 5

	local btn = Instance.new("TextButton")
	btn.Name = "SprintButton"
	btn.AnchorPoint = Vector2.new(0, 1)
	btn.Position = UDim2.new(0, 14, 1, -14)
	btn.Size = UDim2.fromOffset(118, 42)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	btn.BackgroundTransparency = 0.25
	btn.Text = "🏃 Sprint"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 16
	btn.Font = Enum.Font.GothamMedium
	btn.AutoButtonColor = true
	btn.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 90, 100)
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = btn

	screen.Parent = pg

	btn.MouseButton1Down:Connect(function()
		startSprint()
	end)
	btn.MouseButton1Up:Connect(function()
		stopSprint()
	end)
end

UserInputService.WindowFocusReleased:Connect(function()
	stopSprint()
end)
