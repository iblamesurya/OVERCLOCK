--!strict
--[=[
    Project OVERCLOCK v3: LobbyUIController (Hybrid Legendary Edition)

    Visual language from the tactical redesign:
    - THEME table, glass sidebar, Valorant-style accent bars
    - CanvasGroup panel fades + slide
    - Montserrat typography (falls back cleanly if unavailable)

    Production systems merged in:
    - Camera tween that is not overwritten mid-flight
    - Soft mouse parallax after settle
    - Connection + tween cleanup / Destroy()
    - Safe module requires (no WaitForChild hitch on every SetState)
    - Mobile open-menu chip, Esc/gamepad back, fade overlay
    - Shop state + optional UI sounds
]=]

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

-- Touch laptop ≠ phone
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_GAMEPAD = UserInputService.GamepadEnabled

export type LobbyMenuState = "Main" | "Play" | "Challenge" | "Loadout" | "Settings" | "Shop" | "Hidden"
type CallbackFn = () -> ()
type DisconnectFn = () -> ()

local LobbyUIController = {}

-- ============================================================================
-- THEME
-- ============================================================================

local THEME = {
	Colors = {
		Background = Color3.fromRGB(12, 14, 18),
		PanelBg = Color3.fromRGB(18, 22, 28),
		Accent = Color3.fromRGB(0, 210, 255),
		AccentHover = Color3.fromRGB(50, 230, 255),
		AccentGold = Color3.fromRGB(255, 190, 70),
		TextPrimary = Color3.fromRGB(240, 245, 250),
		TextSecondary = Color3.fromRGB(140, 150, 165),
		Border = Color3.fromRGB(35, 42, 55),
	},
	Fonts = {
		-- Prefer Montserrat if you've added it under FontFace / game fonts;
		-- Gotham* is always available as a safe runtime default.
		Header = Enum.Font.GothamBold,
		Body = Enum.Font.Gotham,
		Heavy = Enum.Font.GothamBlack,
	},
	Transparency = {
		Glass = 0.15,
		Panel = 0.2,
	},
	Tweens = {
		Hover = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		PanelFade = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		Camera = TweenInfo.new(0.55, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		Blur = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
	Blur = {
		Main = 12,
		Panel = 22,
	},
	ParallaxStrength = 1.6,
}

local LOBBY_CENTER = Vector3.new(0, 100, 0)

local CAMERA_PRESETS: { [LobbyMenuState]: { cframe: CFrame, fov: number } } = {
	Main = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(0, 14, 45), LOBBY_CENTER + Vector3.new(0, 3, 0)),
		fov = 68,
	},
	Play = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(0, 7, -18), LOBBY_CENTER + Vector3.new(0, 2, -35)),
		fov = 60,
	},
	Challenge = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(-22, 7, 0), LOBBY_CENTER + Vector3.new(-35, 2, 0)),
		fov = 60,
	},
	Loadout = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(18, 5, 8), LOBBY_CENTER + Vector3.new(0, 3, 0)),
		fov = 52,
	},
	Settings = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(0, 7, 22), LOBBY_CENTER + Vector3.new(0, 2, 35)),
		fov = 62,
	},
	Shop = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(12, 8, 18), LOBBY_CENTER + Vector3.new(0, 3, 0)),
		fov = 58,
	},
	Hidden = {
		cframe = CFrame.new(LOBBY_CENTER + Vector3.new(0, 14, 45), LOBBY_CENTER + Vector3.new(0, 3, 0)),
		fov = 70,
	},
}

-- ============================================================================
-- STATE
-- ============================================================================

local isInitialized = false
local currentState: LobbyMenuState = "Hidden"

local screenGui: ScreenGui? = nil
local sidebar: Frame? = nil
local centerCanvasGroup: CanvasGroup? = nil
local fadeOverlay: Frame? = nil
local openMenuButton: TextButton? = nil
local blurEffect: BlurEffect? = nil

local panels: { [string]: CanvasGroup } = {}

local activeTweens: { Tween } = {}
local connections: { RBXScriptConnection } = {}

local cameraConn: RBXScriptConnection? = nil
local camTween: Tween? = nil
local camTweenPlaying = false
local targetCamCFrame: CFrame = CAMERA_PRESETS.Main.cframe
local targetFov: number = CAMERA_PRESETS.Main.fov

-- Cached optional modules (resolved once)
local cachedQueueUI: any? = nil
local cachedLoadoutUI: any? = nil
local cachedSettingsUI: any? = nil
local modulesResolved = false

local playCallbacks: { CallbackFn } = {}
local challengeCallbacks: { CallbackFn } = {}
local loadoutCallbacks: { CallbackFn } = {}
local settingsCallbacks: { CallbackFn } = {}
local practiceCallbacks: { CallbackFn } = {}
local shopCallbacks: { CallbackFn } = {}

-- ============================================================================
-- UTILS
-- ============================================================================

local function trackTween(t: Tween): Tween
	table.insert(activeTweens, t)
	t.Completed:Once(function()
		local idx = table.find(activeTweens, t)
		if idx then
			table.remove(activeTweens, idx)
		end
	end)
	return t
end

local function cancelAllTweens()
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	camTweenPlaying = false
end

local function trackConn(c: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, c)
	return c
end

local function disconnectAll()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
end

local function tryRequireSibling(name: string): any?
	local child = script.Parent:FindFirstChild(name)
	if not child or not child:IsA("ModuleScript") then
		return nil
	end
	local ok, mod = pcall(require, child)
	if ok then
		return mod
	end
	warn("[LobbyUIController] Failed to require", name, mod)
	return nil
end

local function resolveModules()
	if modulesResolved then
		return
	end
	modulesResolved = true
	cachedQueueUI = tryRequireSibling("MatchmakingQueueUI")
	cachedLoadoutUI = tryRequireSibling("LoadoutInspectorUI")
	cachedSettingsUI = tryRequireSibling("SettingsUIController")
end

local function playUiSound(soundName: string, volume: number?)
	local template = SoundService:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		return
	end
	local clone = template:Clone()
	clone.Volume = volume or template.Volume
	clone.Parent = SoundService
	clone:Play()
	clone.Ended:Once(function()
		clone:Destroy()
	end)
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

-- ============================================================================
-- BLUR
-- ============================================================================

local function getOrCreateBlur(): BlurEffect
	if blurEffect and blurEffect.Parent then
		return blurEffect
	end
	local existing = Lighting:FindFirstChild("LobbyBlurEffect")
	if existing and existing:IsA("BlurEffect") then
		blurEffect = existing
		return existing
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "LobbyBlurEffect"
	blur.Size = 0
	blur.Enabled = true
	blur.Parent = Lighting
	blurEffect = blur
	return blur
end

function LobbyUIController.SetBlurSize(targetSize: number, duration: number?)
	local blur = getOrCreateBlur()
	local d = duration or 0.4
	if d <= 0 then
		blur.Size = targetSize
		return
	end
	trackTween(TweenService:Create(blur, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
	})):Play()
end

-- ============================================================================
-- CAMERA (tween-safe enforcement)
-- ============================================================================

local function getParallaxOffset(): Vector3
	if IS_MOBILE or IS_GAMEPAD then
		return Vector3.zero
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return Vector3.zero
	end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return Vector3.zero
	end
	local mouse = UserInputService:GetMouseLocation()
	local nx = ((mouse.X / vp.X) - 0.5) * 2
	local ny = ((mouse.Y / vp.Y) - 0.5) * 2
	local s = THEME.ParallaxStrength
	return Vector3.new(nx * s, -ny * s * 0.55, 0)
end

local function startCameraEnforcement()
	if cameraConn then
		return
	end
	cameraConn = RunService.RenderStepped:Connect(function()
		if currentState == "Hidden" then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable

		-- Do not stomp an active camera tween
		if camTweenPlaying then
			return
		end

		local parallax = getParallaxOffset()
		local base = targetCamCFrame
		local lookAt = base.Position + base.LookVector * 42 + parallax
		camera.CFrame = CFrame.new(base.Position, lookAt)
		camera.FieldOfView = targetFov
	end)
end

local function stopCameraEnforcement()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
end

function LobbyUIController.SetCameraTarget(targetCFrame: CFrame, fov: number?, duration: number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	local d = duration or 0.5
	local f = fov or 70

	targetCamCFrame = targetCFrame
	targetFov = f

	if camTween then
		camTween:Cancel()
		camTween = nil
	end

	if d <= 0 then
		camTweenPlaying = false
		camera.CFrame = targetCFrame
		camera.FieldOfView = f
		return
	end

	camTweenPlaying = true
	local t = TweenService:Create(camera, THEME.Tweens.Camera, {
		CFrame = targetCFrame,
		FieldOfView = f,
	})
	camTween = t
	trackTween(t)
	t:Play()
	t.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			camTweenPlaying = false
		elseif camTween == t then
			camTweenPlaying = false
		end
	end)
end

local function restorePlayerCamera()
	stopCameraEnforcement()
	camTweenPlaying = false
	if camTween then
		camTween:Cancel()
		camTween = nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70

	task.spawn(function()
		local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		local hum = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 5)
		if hum and hum:IsA("Humanoid") then
			camera.CameraSubject = hum
		end
	end)
end

-- ============================================================================
-- UI BUILDERS
-- ============================================================================

local function createMenuButton(
	name: string,
	text: string,
	layoutOrder: number,
	parent: Instance,
	accent: Color3?,
	onClick: () -> ()
): TextButton
	local accentColor = accent or THEME.Colors.Accent
	local btnHeight = if IS_MOBILE then 52 else 46
	local textSize = if IS_MOBILE then 17 else 15

	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.Size = UDim2.new(1, 0, 0, btnHeight)
	button.BackgroundColor3 = THEME.Colors.TextPrimary
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder
	button.Parent = parent

	-- Hover wash
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accentColor),
		ColorSequenceKeypoint.new(1, THEME.Colors.Background),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = button

	-- Valorant-style left accent (grows on hover)
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(0, 3, 0, 0)
	accentBar.Position = UDim2.new(0, 0, 0.5, 0)
	accentBar.AnchorPoint = Vector2.new(0, 0.5)
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = button

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, -24, 1, 0)
	textLabel.Position = UDim2.new(0, 20, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = string.upper(text)
	textLabel.TextColor3 = THEME.Colors.TextSecondary
	textLabel.Font = THEME.Fonts.Header
	textLabel.TextSize = textSize
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = button

	local function setHover(on: boolean)
		TweenService:Create(accentBar, THEME.Tweens.Hover, {
			Size = if on then UDim2.new(0, 4, 0.65, 0) else UDim2.new(0, 3, 0, 0),
		}):Play()
		TweenService:Create(button, THEME.Tweens.Hover, {
			BackgroundTransparency = if on then 0.82 else 1,
		}):Play()
		TweenService:Create(textLabel, THEME.Tweens.Hover, {
			TextColor3 = if on then THEME.Colors.TextPrimary else THEME.Colors.TextSecondary,
			Position = if on then UDim2.new(0, 28, 0, 0) else UDim2.new(0, 20, 0, 0),
		}):Play()
	end

	trackConn(button.MouseEnter:Connect(function()
		setHover(true)
		playUiSound("UI_Hover", 0.22)
	end))
	trackConn(button.MouseLeave:Connect(function()
		setHover(false)
	end))
	trackConn(button.SelectionGained:Connect(function()
		setHover(true)
	end))
	trackConn(button.SelectionLost:Connect(function()
		setHover(false)
	end))
	trackConn(button.MouseButton1Click:Connect(function()
		playUiSound("UI_Click", 0.38)
		local shrink = TweenService:Create(button, THEME.Tweens.Press, {
			Size = UDim2.new(1, -2, 0, btnHeight - 2),
		})
		shrink:Play()
		shrink.Completed:Once(function()
			TweenService:Create(button, THEME.Tweens.Hover, {
				Size = UDim2.new(1, 0, 0, btnHeight),
			}):Play()
		end)
		onClick()
	end))

	return button
end

local function createSubPanel(name: string, title: string, desc: string, parent: Instance): CanvasGroup
	local panel = Instance.new("CanvasGroup")
	panel.Name = name .. "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.GroupTransparency = 0
	panel.Visible = false
	panel.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 56)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = panel

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Name = "Title"
	panelTitle.Size = UDim2.new(1, 0, 0, 40)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Text = title
	panelTitle.TextColor3 = THEME.Colors.TextPrimary
	panelTitle.Font = THEME.Fonts.Heavy
	panelTitle.TextSize = if IS_MOBILE then 24 else 28
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.Parent = panel

	local accentLine = Instance.new("Frame")
	accentLine.Name = "AccentLine"
	accentLine.Size = UDim2.new(0, 64, 0, 3)
	accentLine.Position = UDim2.new(0, 0, 0, 46)
	accentLine.BackgroundColor3 = THEME.Colors.Accent
	accentLine.BorderSizePixel = 0
	accentLine.Parent = panel
	corner(accentLine, 1)

	local panelDesc = Instance.new("TextLabel")
	panelDesc.Name = "Description"
	panelDesc.Size = UDim2.new(1, 0, 0, 48)
	panelDesc.Position = UDim2.new(0, 0, 0, 60)
	panelDesc.BackgroundTransparency = 1
	panelDesc.Text = desc
	panelDesc.TextColor3 = THEME.Colors.TextSecondary
	panelDesc.Font = THEME.Fonts.Body
	panelDesc.TextSize = 15
	panelDesc.TextWrapped = true
	panelDesc.TextXAlignment = Enum.TextXAlignment.Left
	panelDesc.TextYAlignment = Enum.TextYAlignment.Top
	panelDesc.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -120)
	body.Position = UDim2.new(0, 0, 0, 118)
	body.BackgroundTransparency = 1
	body.Parent = panel

	panels[name] = panel
	return panel
end

-- ============================================================================
-- EXTERNAL MODALS
-- ============================================================================

local function setExternalModals(newState: LobbyMenuState)
	resolveModules()

	local queue = cachedQueueUI
	local loadout = cachedLoadoutUI

	if newState == "Play" or newState == "Challenge" then
		if loadout and loadout.Hide then
			pcall(loadout.Hide)
		end
		if queue and queue.ShowQueuePanel then
			local mode = if newState == "Challenge" then "2v2" else "1v1"
			pcall(function()
				queue.ShowQueuePanel(mode)
			end)
		end
	elseif newState == "Loadout" then
		if queue and queue.HideQueuePanel then
			pcall(queue.HideQueuePanel)
		end
		if loadout and loadout.Show then
			pcall(loadout.Show)
		end
	else
		if queue and queue.HideQueuePanel then
			pcall(queue.HideQueuePanel)
		end
		if loadout and loadout.Hide then
			pcall(loadout.Hide)
		end
	end
end

-- ============================================================================
-- INIT
-- ============================================================================

function LobbyUIController.Init(parentGui: PlayerGui?)
	if isInitialized then
		LobbyUIController.Destroy()
	end

	local pGui = parentGui or LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local existing = pGui:FindFirstChild("LobbyMenuGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyMenuGui"
	gui.DisplayOrder = 20
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pGui
	screenGui = gui

	-- Match transition fade
	local fade = Instance.new("Frame")
	fade.Name = "FadeOverlay"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.ZIndex = 200
	fade.Parent = gui
	fadeOverlay = fade

	-- ------------------------------------------------------------------
	-- Glass sidebar
	-- ------------------------------------------------------------------
	local side = Instance.new("Frame")
	side.Name = "SidebarFrame"
	if IS_MOBILE then
		side.Size = UDim2.new(0.82, 0, 1, 0)
		side.Position = UDim2.fromScale(0, 0)
	else
		side.Size = UDim2.new(0, 300, 1, 0)
		side.Position = UDim2.fromScale(0, 0)
		local sc = Instance.new("UISizeConstraint")
		sc.MinSize = Vector2.new(260, 0)
		sc.MaxSize = Vector2.new(340, math.huge)
		sc.Parent = side
	end
	side.BackgroundColor3 = THEME.Colors.Background
	side.BackgroundTransparency = THEME.Transparency.Glass
	side.BorderSizePixel = 0
	side.Visible = false
	side.Parent = gui
	sidebar = side

	-- Soft edge fade (does not crush text as hard as full 1.0)
	local sideGradient = Instance.new("UIGradient")
	sideGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.88, 0),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	sideGradient.Parent = side

	local sidePad = Instance.new("UIPadding")
	sidePad.PaddingLeft = UDim.new(0, if IS_MOBILE then 22 else 36)
	sidePad.PaddingRight = UDim.new(0, 16)
	sidePad.PaddingTop = UDim.new(0, if IS_MOBILE then 48 else 72)
	sidePad.PaddingBottom = UDim.new(0, 24)
	sidePad.Parent = side

	local header = Instance.new("TextLabel")
	header.Name = "HeaderTitle"
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundTransparency = 1
	header.Text = "OVERCLOCK"
	header.TextColor3 = THEME.Colors.TextPrimary
	header.Font = THEME.Fonts.Heavy
	header.TextSize = if IS_MOBILE then 28 else 32
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = side

	local subHeader = Instance.new("TextLabel")
	subHeader.Name = "HeaderSubtitle"
	subHeader.Size = UDim2.new(1, 0, 0, 18)
	subHeader.Position = UDim2.new(0, 0, 0, 40)
	subHeader.BackgroundTransparency = 1
	subHeader.Text = "TACTICAL PROTOCOL"
	subHeader.TextColor3 = THEME.Colors.Accent
	subHeader.Font = THEME.Fonts.Header
	subHeader.TextSize = 12
	subHeader.TextXAlignment = Enum.TextXAlignment.Left
	subHeader.Parent = side

	local btnList = Instance.new("ScrollingFrame")
	btnList.Name = "ButtonList"
	btnList.Size = UDim2.new(1, 12, 1, -120)
	btnList.Position = UDim2.new(0, -18, 0, 88)
	btnList.BackgroundTransparency = 1
	btnList.BorderSizePixel = 0
	btnList.ScrollBarThickness = 3
	btnList.ScrollBarImageColor3 = THEME.Colors.Accent
	btnList.CanvasSize = UDim2.new(0, 0, 0, 0)
	btnList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	btnList.ScrollingDirection = Enum.ScrollingDirection.Y
	btnList.Parent = side

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = btnList

	createMenuButton("Duel", "1v1 Duel", 1, btnList, THEME.Colors.Accent, function()
		LobbyUIController.SetState("Play")
		for _, cb in playCallbacks do
			task.spawn(cb)
		end
	end)

	createMenuButton("Team", "2v2 Team Match", 2, btnList, THEME.Colors.AccentGold, function()
		LobbyUIController.SetState("Challenge")
		for _, cb in challengeCallbacks do
			task.spawn(cb)
		end
	end)

	createMenuButton("Practice", "Practice Range", 3, btnList, THEME.Colors.Accent, function()
		for _, cb in practiceCallbacks do
			task.spawn(cb)
		end
	end)

	createMenuButton("Loadout", "Arsenal", 4, btnList, THEME.Colors.Accent, function()
		LobbyUIController.SetState("Loadout")
		for _, cb in loadoutCallbacks do
			task.spawn(cb)
		end
	end)

	createMenuButton("Shop", "Black Market", 5, btnList, THEME.Colors.AccentGold, function()
		LobbyUIController.SetState("Shop")
		for _, cb in shopCallbacks do
			task.spawn(cb)
		end
	end)

	createMenuButton("Settings", "Settings", 6, btnList, THEME.Colors.TextSecondary, function()
		LobbyUIController.SetState("Settings")
		for _, cb in settingsCallbacks do
			task.spawn(cb)
		end
	end)

	local roamLabel = if IS_MOBILE then "Roam Lobby" else "Roam Lobby  [TAB]"
	createMenuButton("Roam", roamLabel, 7, btnList, THEME.Colors.TextSecondary, function()
		LobbyUIController.ToggleFreeRoam()
	end)

	local footer = Instance.new("TextLabel")
	footer.Name = "FooterHint"
	footer.Size = UDim2.new(1, 0, 0, 20)
	footer.Position = UDim2.new(0, 0, 1, -20)
	footer.BackgroundTransparency = 1
	footer.Font = THEME.Fonts.Body
	footer.TextSize = 11
	footer.TextColor3 = THEME.Colors.TextSecondary
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Text = if IS_MOBILE then "Tap menu chip to return" else "TAB roam  ·  ESC back"
	footer.Parent = side

	-- ------------------------------------------------------------------
	-- Center CanvasGroup modal
	-- ------------------------------------------------------------------
	local centerGroup = Instance.new("CanvasGroup")
	centerGroup.Name = "MainCanvasGroup"
	centerGroup.AnchorPoint = Vector2.new(0.5, 0.5)
	if IS_MOBILE then
		centerGroup.Size = UDim2.new(0.9, 0, 0.5, 0)
		centerGroup.Position = UDim2.new(0.5, 0, 0.62, 0)
	else
		centerGroup.Size = UDim2.new(0.42, 0, 0.52, 0)
		centerGroup.Position = UDim2.new(0.58, 0, 0.5, 0)
		local csc = Instance.new("UISizeConstraint")
		csc.MinSize = Vector2.new(380, 300)
		csc.MaxSize = Vector2.new(560, 440)
		csc.Parent = centerGroup
	end
	centerGroup.BackgroundColor3 = THEME.Colors.PanelBg
	centerGroup.BackgroundTransparency = THEME.Transparency.Panel
	centerGroup.GroupTransparency = 1
	centerGroup.Visible = false
	centerGroup.Parent = gui
	centerCanvasGroup = centerGroup
	corner(centerGroup, 12)

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = THEME.Colors.Border
	centerStroke.Thickness = 1.25
	centerStroke.Transparency = 0.35
	centerStroke.Parent = centerGroup

	local centerPad = Instance.new("UIPadding")
	centerPad.PaddingTop = UDim.new(0, 28)
	centerPad.PaddingBottom = UDim.new(0, 20)
	centerPad.PaddingLeft = UDim.new(0, 32)
	centerPad.PaddingRight = UDim.new(0, 32)
	centerPad.Parent = centerGroup

	createSubPanel(
		"Play",
		"MATCHMAKING",
		"Select your division and queue for ranked or unranked tactical operations.",
		centerGroup
	)
	createSubPanel(
		"Challenge",
		"TEAM OPERATIONS",
		"Form a squad. Challenge lobby players to high-stakes 2v2 combat.",
		centerGroup
	)
	local settingsPanel = createSubPanel(
		"Settings",
		"SYSTEM SETTINGS",
		"Configure visual, audio, and gameplay parameters.",
		centerGroup
	)
	createSubPanel(
		"Shop",
		"BLACK MARKET",
		"Weapon skins, operator packs, and limited tactical bundles.",
		centerGroup
	)

	-- Mount settings into Body if module exists
	task.defer(function()
		resolveModules()
		if cachedSettingsUI and cachedSettingsUI.Init then
			local body = settingsPanel:FindFirstChild("Body")
			if body then
				pcall(function()
					cachedSettingsUI.Init(body)
				end)
			else
				pcall(function()
					cachedSettingsUI.Init(settingsPanel)
				end)
			end
		end
	end)

	-- Minimal back link
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.Size = UDim2.new(0, 140, 0, 30)
	backBtn.Position = UDim2.new(0, 0, 1, -8)
	backBtn.AnchorPoint = Vector2.new(0, 1)
	backBtn.BackgroundTransparency = 1
	backBtn.Text = "<  BACK TO MAIN"
	backBtn.TextColor3 = THEME.Colors.TextSecondary
	backBtn.Font = THEME.Fonts.Header
	backBtn.TextSize = 13
	backBtn.TextXAlignment = Enum.TextXAlignment.Left
	backBtn.AutoButtonColor = false
	backBtn.Parent = centerGroup

	trackConn(backBtn.MouseEnter:Connect(function()
		TweenService:Create(backBtn, THEME.Tweens.Hover, {
			TextColor3 = THEME.Colors.Accent,
		}):Play()
	end))
	trackConn(backBtn.MouseLeave:Connect(function()
		TweenService:Create(backBtn, THEME.Tweens.Hover, {
			TextColor3 = THEME.Colors.TextSecondary,
		}):Play()
	end))
	trackConn(backBtn.MouseButton1Click:Connect(function()
		playUiSound("UI_Click", 0.32)
		LobbyUIController.SetState("Main")
	end))

	-- ------------------------------------------------------------------
	-- Roam re-open chip (critical on mobile)
	-- ------------------------------------------------------------------
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "OpenMenuButton"
	openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Size = UDim2.new(0, if IS_MOBILE then 118 else 148, 0, 40)
	openBtn.Position = UDim2.new(0, 18, 1, -18)
	openBtn.BackgroundColor3 = THEME.Colors.Background
	openBtn.BackgroundTransparency = 0.18
	openBtn.Text = if IS_MOBILE then "☰  MENU" else "☰  MENU  [TAB]"
	openBtn.Font = THEME.Fonts.Header
	openBtn.TextSize = 14
	openBtn.TextColor3 = THEME.Colors.Accent
	openBtn.Visible = false
	openBtn.AutoButtonColor = false
	openBtn.Parent = gui
	corner(openBtn, 10)
	local openStroke = Instance.new("UIStroke")
	openStroke.Color = THEME.Colors.Accent
	openStroke.Thickness = 1.4
	openStroke.Transparency = 0.35
	openStroke.Parent = openBtn
	openMenuButton = openBtn

	if IS_MOBILE then
		local inset = GuiService:GetGuiInset()
		openBtn.Position = UDim2.new(0, 16, 1, -(14 + math.max(inset.Y, 0)))
	end

	trackConn(openBtn.MouseButton1Click:Connect(function()
		playUiSound("UI_Click", 0.35)
		LobbyUIController.SetState("Main")
	end))

	-- Input
	trackConn(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab
			or input.KeyCode == Enum.KeyCode.ButtonStart
			or input.KeyCode == Enum.KeyCode.ButtonSelect
		then
			LobbyUIController.ToggleFreeRoam()
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if currentState ~= "Main" and currentState ~= "Hidden" then
				LobbyUIController.SetState("Main")
			end
		end
	end))

	getOrCreateBlur()
	resolveModules()
	isInitialized = true
	if pendingState then
		local s = pendingState
		pendingState = nil
		LobbyUIController.SetState(s, false)
	end
end

-- ============================================================================
-- FADE API
-- ============================================================================

function LobbyUIController.FadeOut(duration: number?)
	if not fadeOverlay then
		return
	end
	fadeOverlay.BackgroundTransparency = 1
	local t = TweenService:Create(
		fadeOverlay,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 0 }
	)
	trackTween(t)
	t:Play()
	t.Completed:Wait()
end

function LobbyUIController.FadeIn(duration: number?)
	if not fadeOverlay then
		return
	end
	local t = TweenService:Create(
		fadeOverlay,
		TweenInfo.new(duration or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	trackTween(t)
	t:Play()
end

-- ============================================================================
-- STATE MACHINE
-- ============================================================================

local pendingState: LobbyMenuState? = nil
function LobbyUIController.SetState(newState: LobbyMenuState, animate: boolean?)
	if not isInitialized then
		pendingState = newState
		return
	end

	local prev = currentState
	currentState = newState
	local isAnimated = if animate ~= nil then animate else true
	local dur = if isAnimated then 0.5 else 0

	-- Camera + blur
	local preset = CAMERA_PRESETS[newState] or CAMERA_PRESETS.Main
	if newState == "Hidden" then
		LobbyUIController.SetBlurSize(0, dur)
		restorePlayerCamera()
	else
		startCameraEnforcement()
		LobbyUIController.SetCameraTarget(preset.cframe, preset.fov, dur)
		if newState == "Main" then
			LobbyUIController.SetBlurSize(THEME.Blur.Main, dur)
		else
			LobbyUIController.SetBlurSize(THEME.Blur.Panel, dur)
		end
	end

	-- Sidebar
	if sidebar then
		local showSide = (newState ~= "Hidden" and newState ~= "Loadout")
		sidebar.Visible = showSide
	end

	-- Roam chip
	if openMenuButton then
		openMenuButton.Visible = (newState == "Hidden")
	end

	-- Center CanvasGroup slide + fade
	if centerCanvasGroup then
		local showPanel = (
			newState == "Play"
			or newState == "Challenge"
			or newState == "Settings"
			or newState == "Shop"
		)

		if showPanel then
			for name, panel in panels do
				panel.Visible = (name == newState)
			end
			centerCanvasGroup.Visible = true
			if isAnimated and prev ~= newState then
				centerCanvasGroup.GroupTransparency = 1
				centerCanvasGroup.Position = if IS_MOBILE
					then UDim2.new(0.5, 0, 0.66, 0)
					else UDim2.new(0.62, 0, 0.5, 0)
			end
			local goalPos = if IS_MOBILE
				then UDim2.new(0.5, 0, 0.62, 0)
				else UDim2.new(0.58, 0, 0.5, 0)
			trackTween(TweenService:Create(centerCanvasGroup, THEME.Tweens.PanelFade, {
				GroupTransparency = 0,
				Position = goalPos,
			})):Play()
		else
			local outPos = if IS_MOBILE
				then UDim2.new(0.5, 0, 0.58, 0)
				else UDim2.new(0.54, 0, 0.5, 0)
			local fadeOut = TweenService:Create(centerCanvasGroup, THEME.Tweens.PanelFade, {
				GroupTransparency = 1,
				Position = outPos,
			})
			trackTween(fadeOut)
			fadeOut:Play()
			fadeOut.Completed:Once(function()
				if currentState ~= "Play"
					and currentState ~= "Challenge"
					and currentState ~= "Settings"
					and currentState ~= "Shop"
				then
					if centerCanvasGroup then
						centerCanvasGroup.Visible = false
					end
				end
			end)
		end
	end

	setExternalModals(newState)
end

function LobbyUIController.ToggleFreeRoam()
	if currentState == "Hidden" then
		LobbyUIController.SetState("Main")
	else
		LobbyUIController.SetState("Hidden")
	end
end

function LobbyUIController.GetState(): LobbyMenuState
	return currentState
end

function LobbyUIController.HideAllMenus()
	LobbyUIController.SetState("Hidden")
end

function LobbyUIController.ShowMainLobbyMenu()
	LobbyUIController.SetState("Main")
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

local function bind(list: { CallbackFn }, cb: CallbackFn): DisconnectFn
	table.insert(list, cb)
	return function()
		local idx = table.find(list, cb)
		if idx then
			table.remove(list, idx)
		end
	end
end

function LobbyUIController.OnPlayClicked(cb: CallbackFn): DisconnectFn
	return bind(playCallbacks, cb)
end
function LobbyUIController.OnChallengeClicked(cb: CallbackFn): DisconnectFn
	return bind(challengeCallbacks, cb)
end
function LobbyUIController.OnLoadoutClicked(cb: CallbackFn): DisconnectFn
	return bind(loadoutCallbacks, cb)
end
function LobbyUIController.OnSettingsClicked(cb: CallbackFn): DisconnectFn
	return bind(settingsCallbacks, cb)
end
function LobbyUIController.OnPracticeClicked(cb: CallbackFn): DisconnectFn
	return bind(practiceCallbacks, cb)
end
function LobbyUIController.OnShopClicked(cb: CallbackFn): DisconnectFn
	return bind(shopCallbacks, cb)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function LobbyUIController.Destroy()
	cancelAllTweens()
	disconnectAll()
	stopCameraEnforcement()
	if blurEffect then
		blurEffect.Size = 0
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	sidebar = nil
	centerCanvasGroup = nil
	fadeOverlay = nil
	openMenuButton = nil
	table.clear(panels)
	modulesResolved = false
	cachedQueueUI = nil
	cachedLoadoutUI = nil
	cachedSettingsUI = nil
	isInitialized = false
	currentState = "Hidden"
end

return LobbyUIController
