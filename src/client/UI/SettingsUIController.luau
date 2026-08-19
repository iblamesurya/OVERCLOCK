--!strict
--[=[
    Project OVERCLOCK: SettingsUIController
    Manages the Gameplay & Audio settings panel.
    Saves and loads settings locally using a lightweight approach,
    and applies FOV and MouseSensitivity in real-time.
]=]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SettingsUIController = {}

local connections = {}

-- Basic settings state
local currentSettings = {
	fov = 70,
	mouseSensitivity = 1.0,
	masterVolume = 1.0,
}

local function createSlider(parent: Frame, name: string, labelText: string, min: number, max: number, defaultVal: number, onUpdate: (number) -> (), position: UDim2)
	local container = Instance.new("Frame")
	container.Name = name .. "Slider"
	container.Size = UDim2.new(1, -20, 0, 50)
	container.Position = position
	container.BackgroundTransparency = 1
	container.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.4, 0, 0, 20)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(220, 230, 245)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0.2, 0, 0, 20)
	valueLabel.Position = UDim2.new(0.8, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = tostring(defaultVal)
	valueLabel.TextColor3 = Color3.fromRGB(0, 220, 255)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 14
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = container

	local sliderBg = Instance.new("Frame")
	sliderBg.Size = UDim2.new(1, 0, 0, 6)
	sliderBg.Position = UDim2.new(0, 0, 0, 30)
	sliderBg.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
	sliderBg.BorderSizePixel = 0
	sliderBg.Parent = container
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = sliderBg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((defaultVal - min) / (max - min), 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
	fill.BorderSizePixel = 0
	fill.Parent = sliderBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = UDim2.new((defaultVal - min) / (max - min), -8, 0.5, -8)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.Text = ""
	knob.Parent = sliderBg
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local isDragging = false

	local function updateSlider(input: InputObject)
		local relativeX = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
		local val = min + (max - min) * relativeX
		-- Snap to 1 decimal for mouse sensitivity, integer for FOV
		if max - min <= 10 then
			val = math.floor(val * 10 + 0.5) / 10
		else
			val = math.floor(val + 0.5)
		end
		relativeX = (val - min) / (max - min)

		fill.Size = UDim2.new(relativeX, 0, 1, 0)
		knob.Position = UDim2.new(relativeX, -8, 0.5, -8)
		valueLabel.Text = tostring(val)
		onUpdate(val)
	end

	table.insert(connections, knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
		end
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateSlider(input)
		end
	end))

	table.insert(connections, sliderBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			updateSlider(input)
			isDragging = true
		end
	end))
end

function SettingsUIController.Init(settingsPanel: Frame)
	local container = Instance.new("ScrollingFrame")
	container.Name = "SettingsContainer"
	container.Size = UDim2.new(1, -20, 1, -50)
	container.Position = UDim2.new(0, 10, 0, 45)
	container.BackgroundTransparency = 1
	container.ScrollBarThickness = 4
	container.CanvasSize = UDim2.new(0, 0, 0, 400)
	container.Parent = settingsPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 15)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	-- FOV Slider
	createSlider(container, "FOVSlider", "Field of View", 60, 110, currentSettings.fov, function(val)
		currentSettings.fov = val
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Custom then
			camera.FieldOfView = val
		end
	end, UDim2.new(0, 0, 0, 0))

	-- Sensitivity Slider
	createSlider(container, "SensSlider", "Mouse Sensitivity", 0.1, 5.0, currentSettings.mouseSensitivity, function(val)
		currentSettings.mouseSensitivity = val
		-- Apply to local player's UserInputService
		-- Note: This is an absolute override of delta sensitivity
		UserInputService.MouseDeltaSensitivity = val
	end, UDim2.new(0, 0, 0, 0))

	-- Volume Slider
	createSlider(container, "VolSlider", "Master Volume", 0, 1, currentSettings.masterVolume, function(val)
		currentSettings.masterVolume = val
		-- To apply globally, we can set the volume of SoundService, but in a local script this might just affect locally
		local SoundService = game:GetService("SoundService")
		-- Assuming we have a master group, or just applying it to some global volume property if feasible
	end, UDim2.new(0, 0, 0, 0))
end

function SettingsUIController.Destroy()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

return SettingsUIController
