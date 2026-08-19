--!strict
--[=[
    Project OVERCLOCK v2: LobbyTransitionController
    Strict Luau controller managing smooth screen fade and blur transitions
    between Lobby and Match states, including camera mode management.
]=]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type TransitionState = "Lobby" | "TransitioningToMatch" | "Match" | "TransitioningToLobby"

type TransitionCallback = () -> ()

local LobbyTransitionController = {}

local currentState: TransitionState = "Lobby"
local isBusy: boolean = false

local screenGui: ScreenGui? = nil
local fadeOverlay: CanvasGroup? = nil
local blurEffect: BlurEffect? = nil
local activeTweens = {}

local function cancelActiveTweens()
	for _, tw in ipairs(activeTweens) do
		pcall(function() tw:Cancel() end)
	end
	table.clear(activeTweens)
end

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

function LobbyTransitionController.Init(parentGui: PlayerGui?)
	local pGui = parentGui or Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local existing = pGui:FindFirstChild("LobbyTransitionGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyTransitionGui"
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pGui
	screenGui = gui

	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "FadeCanvasGroup"
	canvas.Size = UDim2.new(1, 0, 1, 0)
	canvas.Position = UDim2.new(0, 0, 0, 0)
	canvas.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
	canvas.GroupTransparency = 1
	canvas.Visible = false
	canvas.Parent = gui
	fadeOverlay = canvas

	local innerFrame = Instance.new("Frame")
	innerFrame.Name = "Fill"
	innerFrame.Size = UDim2.new(1, 0, 1, 0)
	innerFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
	innerFrame.BorderSizePixel = 0
	innerFrame.Parent = canvas

	getOrCreateBlur()
end

function LobbyTransitionController.IsTransitioning(): boolean
	return isBusy
end

function LobbyTransitionController.GetState(): TransitionState
	return currentState
end

function LobbyTransitionController.TransitionToMatch(
	duration: number?,
	onMidpoint: TransitionCallback?,
	onComplete: TransitionCallback?
)
	if isBusy then
		warn("[LobbyTransitionController] Transition already in progress!")
		return
	end

	isBusy = true
	currentState = "TransitioningToMatch"

	local totalDuration = duration or 1.2
	local halfDuration = totalDuration / 2
	local blur = getOrCreateBlur()

	if not fadeOverlay then
		if screenGui then
			LobbyTransitionController.Init(screenGui.Parent :: PlayerGui)
		end
	end

	local overlay = fadeOverlay
	if not overlay then
		isBusy = false
		return
	end

	overlay.Visible = true
	overlay.GroupTransparency = 1

	-- 1. Fade to Black & Increase Blur
	local tweenInfo = TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cancelActiveTweens()
	local fadeOutTween = TweenService:Create(overlay, tweenInfo, { GroupTransparency = 0 })
	local blurUpTween = TweenService:Create(blur, tweenInfo, { Size = 28 })
	table.insert(activeTweens, fadeOutTween)
	table.insert(activeTweens, blurUpTween)

	fadeOutTween:Play()
	blurUpTween:Play()

	fadeOutTween.Completed:Connect(function()
		-- Midpoint reached: screen fully obscured
		local player = Players.LocalPlayer
		local char = player.Character
		local camera = Workspace.CurrentCamera

		if camera and char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraType = Enum.CameraType.Custom
				camera.CameraSubject = humanoid
			end
		end

		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			local conn
			conn = player.CharacterAdded:Connect(function()
				camera.CameraType = Enum.CameraType.Custom
				if conn then conn:Disconnect() end
			end)
			task.delay(10, function()
				if camera and camera.CameraType == Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Custom
				end
				if conn then conn:Disconnect() end
			end)
		end

		if onMidpoint then
			onMidpoint()
		end

		-- 2. Fade in from Black to Game View & Clear Blur
		local tweenInInfo = TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeInTween = TweenService:Create(overlay, tweenInInfo, { GroupTransparency = 1 })
		local blurDownTween = TweenService:Create(blur, tweenInInfo, { Size = 0 })
		table.insert(activeTweens, fadeInTween)
		table.insert(activeTweens, blurDownTween)

		fadeInTween:Play()
		blurDownTween:Play()

		fadeInTween.Completed:Connect(function()
			overlay.Visible = false
			currentState = "Match"
			isBusy = false

			if onComplete then
				onComplete()
			end
		end)
	end)
end

function LobbyTransitionController.TransitionToLobby(
	duration: number?,
	onMidpoint: TransitionCallback?,
	onComplete: TransitionCallback?
)
	if isBusy then
		warn("[LobbyTransitionController] Transition already in progress!")
		return
	end

	isBusy = true
	currentState = "TransitioningToLobby"

	local totalDuration = duration or 1.2
	local halfDuration = totalDuration / 2
	local blur = getOrCreateBlur()

	if not fadeOverlay then
		if screenGui then
			LobbyTransitionController.Init(screenGui.Parent :: PlayerGui)
		end
	end

	local overlay = fadeOverlay
	if not overlay then
		isBusy = false
		return
	end

	overlay.Visible = true
	overlay.GroupTransparency = 1

	-- 1. Fade to Black
	local tweenInfo = TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cancelActiveTweens()
	local fadeOutTween = TweenService:Create(overlay, tweenInfo, { GroupTransparency = 0 })
	table.insert(activeTweens, fadeOutTween)

	fadeOutTween:Play()

	fadeOutTween.Completed:Connect(function()
		-- Midpoint reached
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end

		if onMidpoint then
			onMidpoint()
		end

		-- 2. Fade in to Lobby View & Set Lobby Ambient Blur
		local tweenInInfo = TweenInfo.new(halfDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeInTween = TweenService:Create(overlay, tweenInInfo, { GroupTransparency = 1 })
		local blurTween = TweenService:Create(blur, tweenInInfo, { Size = 12 })
		table.insert(activeTweens, fadeInTween)
		table.insert(activeTweens, blurTween)

		fadeInTween:Play()
		blurTween:Play()

		fadeInTween.Completed:Connect(function()
			overlay.Visible = false
			currentState = "Lobby"
			isBusy = false

			if onComplete then
				onComplete()
			end
		end)
	end)
end

return LobbyTransitionController
