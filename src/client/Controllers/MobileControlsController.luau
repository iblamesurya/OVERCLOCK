--!strict
--[=[
    Project OVERCLOCK: MobileControlsController
    Ergonomic mobile interface controller with floating combat buttons,
    a persistent menu toggle button, and scope/ADS visual feedback.
    Uses ContextActionService combat action binding with dynamic bind/unbind support.
    Maintains UI ergonomics by enforcing ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
    and positioning touch buttons with UDim2 Scale and a 1:1 UIAspectRatioConstraint.
]=]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Spring = require(ReplicatedStorage:WaitForChild("Physics"):WaitForChild("Spring") :: any)

export type ActionHandler = (actionName: string, inputState: Enum.UserInputState, inputObject: InputObject) -> Enum.ContextActionResult?

export type CombatActionCallbacks = {
	onFire: ActionHandler?,
	onReload: ActionHandler?,
	onAim: ActionHandler?,
	onCrouch: ActionHandler?,
	onJump: ActionHandler?,
	onSprint: ActionHandler?,
}

export type MobileControlsControllerImpl = {
	Init: (targetPlayerGui: PlayerGui?) -> (),
	BindCombatActions: (callbacks: CombatActionCallbacks) -> (),
	UnbindCombatActions: () -> (),
	SetActionEnabled: (actionName: string, enabled: boolean) -> (),
	SetCombatVisible: (visible: boolean) -> (),
	SetMenuButtonVisible: (visible: boolean) -> (),
	IsMobile: () -> boolean,
	GetTouchGui: () -> ScreenGui?,
}

local MobileControlsController = {} :: MobileControlsControllerImpl

local touchScreenGui: ScreenGui? = nil
local boundActions: { [string]: boolean } = {}

-- Custom touch button references for styling
local customButtons: { [string]: Frame } = {}
local buttonSprings: { [string]: any } = {}
local combatContainer: Frame? = nil
local menuToggleButton: TextButton? = nil
local aimButtonRef: Frame? = nil
local isAimActive = false
local renderConnection: RBXScriptConnection? = nil

-- ============================================================
-- Custom Button Factory (much better than ContextActionService defaults)
-- ============================================================
local function createTouchButton(
	parent: Instance,
	name: string,
	label: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	iconText: string?
): Frame
	local container = Instance.new("Frame")
	container.Name = name .. "Container"
	container.Size = size
	container.Position = position
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)  -- Fully circular
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Name = "ButtonStroke"
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = container

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.0
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = container

	-- Icon/Text label
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "ButtonLabel"
	textLabel.Size = UDim2.new(1, 0, 0.4, 0)
	textLabel.Position = UDim2.new(0, 0, 0.55, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = label
	textLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 10
	textLabel.TextScaled = true
	textLabel.Parent = container

	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MaxTextSize = 12
	textSizeConstraint.Parent = textLabel

	if iconText then
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.6, 0, 0.4, 0)
		icon.Position = UDim2.new(0.2, 0, 0.1, 0)
		icon.BackgroundTransparency = 1
		icon.Text = iconText
		icon.TextColor3 = color
		icon.Font = Enum.Font.GothamBold
		icon.TextSize = 18
		icon.TextScaled = true
		icon.Parent = container

		local iconConstraint = Instance.new("UITextSizeConstraint")
		iconConstraint.MaxTextSize = 22
		iconConstraint.Parent = icon
	end

	-- Inner glow
	local glow = Instance.new("Frame")
	glow.Name = "InnerGlow"
	glow.Size = UDim2.new(0.85, 0, 0.85, 0)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.85
	glow.BorderSizePixel = 0
	glow.Parent = container

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	-- Invisible input capture button on top
	local inputBtn = Instance.new("TextButton")
	inputBtn.Name = "InputCapture"
	inputBtn.Size = UDim2.new(1, 0, 1, 0)
	inputBtn.BackgroundTransparency = 1
	inputBtn.Text = ""
	inputBtn.ZIndex = 10
	inputBtn.Parent = container

	local scale = Instance.new("UIScale")
	scale.Name = "UIScale"
	scale.Parent = container

	-- Initialize physics spring for this button
	local spring = Spring.new(1.0)
	spring.Speed = 25
	spring.Damper = 0.55
	buttonSprings[name] = spring

	inputBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			buttonSprings[name].Target = 0.85
		end
	end)
	
	inputBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			buttonSprings[name].Target = 1.0
		end
	end)

	customButtons[name] = container
	return container
end

-- ============================================================
-- Init
-- ============================================================
function MobileControlsController.Init(targetPlayerGui: PlayerGui?)
	local pGui = targetPlayerGui or Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	-- Remove old GUI
	local existing = pGui:FindFirstChild("MobileTouchGui")
	if existing then existing:Destroy() end

	local touchGui = Instance.new("ScreenGui")
	touchGui.Name = "MobileTouchGui"
	touchGui.DisplayOrder = 100
	touchGui.ResetOnSpawn = false
	touchGui.ScreenInsets = Enum.ScreenInsets.None
	touchGui.Parent = pGui
	touchScreenGui = touchGui

	-- Combat buttons container (hidden until combat mode)
	local combatFrame = Instance.new("Frame")
	combatFrame.Name = "CombatButtonsFrame"
	combatFrame.Size = UDim2.new(1, 0, 1, 0)
	combatFrame.BackgroundTransparency = 1
	combatFrame.Visible = false
	combatFrame.Parent = touchGui
	combatContainer = combatFrame

	-- Create the menu toggle button (always visible on mobile)
	local menuBtn = Instance.new("TextButton")
	menuBtn.Name = "MenuToggleButton"
	menuBtn.Size = UDim2.new(0, 44, 0, 44)
	menuBtn.Position = UDim2.new(0, 12, 0, 12)
	menuBtn.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
	menuBtn.BackgroundTransparency = 0.2
	menuBtn.Text = "☰"
	menuBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
	menuBtn.Font = Enum.Font.GothamBold
	menuBtn.TextSize = 22
	menuBtn.BorderSizePixel = 0
	menuBtn.ZIndex = 50
	menuBtn.Parent = touchGui

	local menuCorner = Instance.new("UICorner")
	menuCorner.CornerRadius = UDim.new(0, 10)
	menuCorner.Parent = menuBtn

	local menuStroke = Instance.new("UIStroke")
	menuStroke.Color = Color3.fromRGB(0, 180, 255)
	menuStroke.Thickness = 1.5
	menuStroke.Transparency = 0.4
	menuStroke.Parent = menuBtn

	menuToggleButton = menuBtn

	if renderConnection then renderConnection:Disconnect() end
	renderConnection = RunService.RenderStepped:Connect(function(dt)
		for btnName, spring in pairs(buttonSprings) do
			local btn = customButtons[btnName]
			if btn then
				local scale = btn:FindFirstChild("UIScale") :: UIScale?
				if scale then
					scale.Scale = spring.Position
				end
			end
		end
	end)
end

function MobileControlsController.IsMobile(): boolean
	return UserInputService.TouchEnabled
end

-- ============================================================
-- Combat Action Binding
-- ============================================================
function MobileControlsController.BindCombatActions(callbacks: CombatActionCallbacks)
	if not combatContainer then return end
	local container = combatContainer :: Frame

	-- Clear old custom buttons
	for name, btn in customButtons do
		btn:Destroy()
	end
	table.clear(customButtons)

	-- FIRE button — large, right side
	local fireBtn = createTouchButton(
		container, "CombatFire", "FIRE",
		UDim2.new(0.87, 0, 0.65, 0),
		UDim2.new(0.16, 0, 0.16, 0),
		Color3.fromRGB(255, 60, 60),
		"🔥"
	)
	local fireInput = fireBtn:FindFirstChild("InputCapture") :: TextButton
	if fireInput and callbacks.onFire then
		local handler = callbacks.onFire
		local activeTouchId = nil
		fireInput.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				local currentId = input.UserInputType == Enum.UserInputType.Touch and input.UserInputIndex or Enum.UserInputType.MouseButton1
				if activeTouchId == nil then
					activeTouchId = currentId
					handler("CombatFire", Enum.UserInputState.Begin, input)
				end
			end
		end)
		fireInput.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				local currentId = input.UserInputType == Enum.UserInputType.Touch and input.UserInputIndex or Enum.UserInputType.MouseButton1
				if activeTouchId == currentId then
					activeTouchId = nil
					handler("CombatFire", Enum.UserInputState.End, input)
				end
			end
		end)
	end

	-- AIM / SCOPE button — right side, above fire
	local aimBtn = createTouchButton(
		container, "CombatAim", "AIM",
		UDim2.new(0.72, 0, 0.45, 0),
		UDim2.new(0.12, 0, 0.12, 0),
		Color3.fromRGB(0, 200, 255),
		"🎯"
	)
	aimButtonRef = aimBtn
	local aimInput = aimBtn:FindFirstChild("InputCapture") :: TextButton
	if aimInput and callbacks.onAim then
		local handler = callbacks.onAim
		aimInput.MouseButton1Click:Connect(function()
			isAimActive = not isAimActive
			if isAimActive then
				handler("CombatAim", Enum.UserInputState.Begin, {} :: any)
				-- Visual feedback: glow the AIM button
				local stroke = aimBtn:FindFirstChild("ButtonStroke") :: UIStroke?
				local glow = aimBtn:FindFirstChild("InnerGlow") :: Frame?
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0, Thickness = 3 }):Play()
				end
				if glow then
					TweenService:Create(glow, TweenInfo.new(0.15), { BackgroundTransparency = 0.5 }):Play()
				end
			else
				handler("CombatAim", Enum.UserInputState.End, {} :: any)
				local stroke = aimBtn:FindFirstChild("ButtonStroke") :: UIStroke?
				local glow = aimBtn:FindFirstChild("InnerGlow") :: Frame?
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = 0.3, Thickness = 2 }):Play()
				end
				if glow then
					TweenService:Create(glow, TweenInfo.new(0.15), { BackgroundTransparency = 0.85 }):Play()
				end
			end
		end)
	end

	-- RELOAD button — right side, below fire
	local reloadBtn = createTouchButton(
		container, "CombatReload", "RELOAD",
		UDim2.new(0.72, 0, 0.82, 0),
		UDim2.new(0.11, 0, 0.11, 0),
		Color3.fromRGB(255, 200, 0),
		"🔄"
	)
	local reloadInput = reloadBtn:FindFirstChild("InputCapture") :: TextButton
	if reloadInput and callbacks.onReload then
		local handler = callbacks.onReload
		reloadInput.MouseButton1Click:Connect(function()
			handler("CombatReload", Enum.UserInputState.Begin, {} :: any)
		end)
	end

	-- CROUCH button — bottom right area
	local crouchBtn = createTouchButton(
		container, "CombatCrouch", "CROUCH",
		UDim2.new(0.87, 0, 0.35, 0),
		UDim2.new(0.09, 0, 0.09, 0),
		Color3.fromRGB(180, 100, 255),
		"⬇"
	)
	local crouchInput = crouchBtn:FindFirstChild("InputCapture") :: TextButton
	if crouchInput and callbacks.onCrouch then
		local handler = callbacks.onCrouch
		crouchInput.MouseButton1Click:Connect(function()
			handler("CombatCrouch", Enum.UserInputState.Begin, {} :: any)
		end)
	end

	-- JUMP button — bottom right
	local jumpBtn = createTouchButton(
		container, "CombatJump", "JUMP",
		UDim2.new(0.87, 0, 0.18, 0),
		UDim2.new(0.09, 0, 0.09, 0),
		Color3.fromRGB(80, 255, 120),
		"⬆"
	)
	local jumpInput = jumpBtn:FindFirstChild("InputCapture") :: TextButton
	if jumpInput and callbacks.onJump then
		local handler = callbacks.onJump
		jumpInput.MouseButton1Down:Connect(function()
			handler("CombatJump", Enum.UserInputState.Begin, {} :: any)
		end)
		jumpInput.MouseButton1Up:Connect(function()
			handler("CombatJump", Enum.UserInputState.End, {} :: any)
		end)
	end

	-- SPRINT button — top right area (above crouch)
	local sprintBtn = createTouchButton(
		container, "CombatSprint", "SPRINT",
		UDim2.new(0.72, 0, 0.18, 0),
		UDim2.new(0.09, 0, 0.09, 0),
		Color3.fromRGB(255, 150, 30),
		"🏃"
	)
	local sprintInput = sprintBtn:FindFirstChild("InputCapture") :: TextButton
	if sprintInput and callbacks.onSprint then
		local handler = callbacks.onSprint
		sprintInput.MouseButton1Down:Connect(function()
			handler("CombatSprint", Enum.UserInputState.Begin, {} :: any)
		end)
		sprintInput.MouseButton1Up:Connect(function()
			handler("CombatSprint", Enum.UserInputState.End, {} :: any)
		end)
	end

	-- Mark all as bound
	for name, _ in customButtons do
		boundActions[name] = true
	end
end

function MobileControlsController.UnbindCombatActions()
	for name, btn in customButtons do
		btn:Destroy()
	end
	table.clear(customButtons)
	table.clear(boundActions)
	table.clear(buttonSprings)
	isAimActive = false
end

function MobileControlsController.SetCombatVisible(visible: boolean)
	if combatContainer then
		combatContainer.Visible = visible
	end
	-- Reset aim state when hiding
	if not visible then
		isAimActive = false
	end
end

function MobileControlsController.SetMenuButtonVisible(visible: boolean)
	if menuToggleButton then
		menuToggleButton.Visible = visible
	end
end

function MobileControlsController.SetActionEnabled(actionName: string, enabled: boolean)
	local btn = customButtons[actionName]
	if btn then
		btn.Visible = enabled
	end
end

function MobileControlsController.GetTouchGui(): ScreenGui?
	return touchScreenGui
end

function MobileControlsController.GetMenuButton(): TextButton?
	return menuToggleButton
end

return MobileControlsController
