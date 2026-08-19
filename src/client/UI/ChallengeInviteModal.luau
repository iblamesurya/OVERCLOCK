--!strict
--[=[
    Project OVERCLOCK v2: ChallengeInviteModal
    Client-side modal popup UI for incoming 1v1 duel challenges, featuring
    Accept/Decline action buttons and a 15-second radial/countdown timer bar.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ChallengeEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("ChallengeEvents"))

local TOTAL_TIMEOUT_SECONDS = 15

local ChallengeInviteModal = {}

local screenGui: ScreenGui? = nil
local modalFrame: Frame? = nil
local challengerNameLabel: TextLabel? = nil
local countdownTextLabel: TextLabel? = nil
local timerProgressBar: Frame? = nil
local acceptButton: TextButton? = nil
local declineButton: TextButton? = nil

local isUIInitialized = false
local currentActiveChallengeId: string? = nil
local timerThread: thread? = nil

--- Hides and resets the invite modal popup.
function ChallengeInviteModal.Hide()
	if timerThread then
		task.cancel(timerThread)
		timerThread = nil
	end

	currentActiveChallengeId = nil

	if modalFrame then
		TweenService:Create(modalFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 10, 0, 10),
			Position = UDim2.new(0.5, -5, 0.5, -5),
		}):Play()

		task.delay(0.2, function()
			if modalFrame then
				modalFrame.Visible = false
			end
		end)
	end
end

--- Shows the challenge invitation modal with challenger info and 15s timer.
function ChallengeInviteModal.ShowInvite(data: ChallengeEvents.ChallengeRequestData)
	currentActiveChallengeId = data.challengeId

	if challengerNameLabel then
		challengerNameLabel.Text = string.format("%s (@%s)", data.challenger.displayName, data.challenger.username)
	end

	if timerProgressBar then
		timerProgressBar.Size = UDim2.new(1, 0, 1, 0)
	end

	if modalFrame then
		modalFrame.Visible = true
		modalFrame.Size = UDim2.new(0, 10, 0, 10)
		modalFrame.Position = UDim2.new(0.5, -5, 0.5, -5)

		TweenService:Create(modalFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 440, 0, 260),
			Position = UDim2.new(0.5, -220, 0.5, -130),
		}):Play()
	end

	-- Start 15s Radial/Countdown Timer
	if timerThread then
		task.cancel(timerThread)
	end

	timerThread = task.spawn(function()
		local startTime = os.clock()
		local duration = TOTAL_TIMEOUT_SECONDS

		while true do
			local elapsed = os.clock() - startTime
			local remaining = math.max(0, duration - elapsed)
			local fraction = math.clamp(remaining / duration, 0, 1)

			if countdownTextLabel then
				countdownTextLabel.Text = string.format("Auto-declines in: %.1fs", remaining)
			end

			if timerProgressBar then
				timerProgressBar.Size = UDim2.new(fraction, 0, 1, 0)
				timerProgressBar.BackgroundColor3 = Color3.fromRGB(
					math.floor(255 * (1 - fraction)),
					math.floor(220 * fraction),
					100
				)
			end

			if remaining <= 0 then
				break
			end

			task.wait(0.05)
		end

		ChallengeInviteModal.Hide()
	end)
end

local function respondToChallenge(accept: boolean)
	if not currentActiveChallengeId then
		return
	end

	local challengeId = currentActiveChallengeId
	ChallengeInviteModal.Hide()

	local respondRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")
	respondRemote:FireServer(challengeId, accept)
end

local function createUIElements(targetParent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ChallengeInviteModalGui"
	gui.ResetOnSpawn = false
	gui.Parent = targetParent
	screenGui = gui

	-- Centered Modal Frame
	local frame = Instance.new("Frame")
	frame.Name = "InviteModalFrame"
	frame.Size = UDim2.new(0, 440, 0, 260)
	frame.Position = UDim2.new(0.5, -220, 0.5, -130)
	frame.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	modalFrame = frame

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 12)
	frameCorner.Parent = frame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(0, 162, 255)
	frameStroke.Thickness = 2
	frameStroke.Parent = frame

	-- Header Banner
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.Position = UDim2.new(0, 0, 0, 12)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⚔️ 1v1 DUEL CHALLENGE ⚔️"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = frame

	-- Subtitle Info
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Size = UDim2.new(1, -40, 0, 20)
	subLabel.Position = UDim2.new(0, 20, 0, 52)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "You have been challenged to a direct 1v1 match by:"
	subLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
	subLabel.TextSize = 12
	subLabel.Font = Enum.Font.Gotham
	subLabel.Parent = frame

	-- Challenger Name Display
	local cName = Instance.new("TextLabel")
	cName.Name = "ChallengerNameLabel"
	cName.Size = UDim2.new(1, -40, 0, 32)
	cName.Position = UDim2.new(0, 20, 0, 76)
	cName.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
	cName.Text = "ChallengerName"
	cName.TextColor3 = Color3.fromRGB(255, 255, 255)
	cName.TextSize = 16
	cName.Font = Enum.Font.GothamBold
	cName.Parent = frame
	challengerNameLabel = cName

	local cNameCorner = Instance.new("UICorner")
	cNameCorner.CornerRadius = UDim.new(0, 6)
	cNameCorner.Parent = cName

	-- Timer Text Label
	local timerTxt = Instance.new("TextLabel")
	timerTxt.Name = "CountdownTextLabel"
	timerTxt.Size = UDim2.new(1, -40, 0, 20)
	timerTxt.Position = UDim2.new(0, 20, 0, 116)
	timerTxt.BackgroundTransparency = 1
	timerTxt.Text = "Auto-declines in: 15.0s"
	timerTxt.TextColor3 = Color3.fromRGB(200, 205, 220)
	timerTxt.TextSize = 12
	timerTxt.Font = Enum.Font.GothamBold
	timerTxt.Parent = frame
	countdownTextLabel = timerTxt

	-- Timer Progress Bar Track & Fill
	local track = Instance.new("Frame")
	track.Name = "TimerTrack"
	track.Size = UDim2.new(1, -40, 0, 8)
	track.Position = UDim2.new(0, 20, 0, 140)
	track.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local bar = Instance.new("Frame")
	bar.Name = "TimerProgressBar"
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(0, 220, 120)
	bar.BorderSizePixel = 0
	bar.Parent = track
	timerProgressBar = bar

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 4)
	barCorner.Parent = bar

	-- Action Buttons Container
	local btnContainer = Instance.new("Frame")
	btnContainer.Name = "ButtonContainer"
	btnContainer.Size = UDim2.new(1, -40, 0, 45)
	btnContainer.Position = UDim2.new(0, 20, 0, 190)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent = frame

	-- Decline Button
	local decBtn = Instance.new("TextButton")
	decBtn.Name = "DeclineButton"
	decBtn.Size = UDim2.new(0.48, 0, 1, 0)
	decBtn.Position = UDim2.new(0, 0, 0, 0)
	decBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 60)
	decBtn.Text = "DECLINE"
	decBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	decBtn.TextSize = 14
	decBtn.Font = Enum.Font.GothamBold
	decBtn.Parent = btnContainer
	declineButton = decBtn

	local decCorner = Instance.new("UICorner")
	decCorner.CornerRadius = UDim.new(0, 8)
	decCorner.Parent = decBtn

	-- Accept Button
	local accBtn = Instance.new("TextButton")
	accBtn.Name = "AcceptButton"
	accBtn.Size = UDim2.new(0.48, 0, 1, 0)
	accBtn.Position = UDim2.new(0.52, 0, 0, 0)
	accBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	accBtn.Text = "ACCEPT"
	accBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	accBtn.TextSize = 14
	accBtn.Font = Enum.Font.GothamBold
	accBtn.Parent = btnContainer
	acceptButton = accBtn

	local accCorner = Instance.new("UICorner")
	accCorner.CornerRadius = UDim.new(0, 8)
	accCorner.Parent = accBtn
end

local function bindEvents()
	if acceptButton and declineButton then
		acceptButton.MouseButton1Click:Connect(function()
			respondToChallenge(true)
		end)

		declineButton.MouseButton1Click:Connect(function()
			respondToChallenge(false)
		end)
	end

	-- Listen for incoming challenge requests
	local receiveRemote = ChallengeEvents.GetRemoteEvent("ChallengeReceive")
	receiveRemote.OnClientEvent:Connect(function(data: ChallengeEvents.ChallengeRequestData)
		ChallengeInviteModal.ShowInvite(data)
	end)

	-- Listen for challenge cancel event
	local cancelRemote = ChallengeEvents.GetRemoteEvent("ChallengeCancel")
	cancelRemote.OnClientEvent:Connect(function(data: ChallengeEvents.ChallengeCancelData)
		if currentActiveChallengeId == data.challengeId then
			ChallengeInviteModal.Hide()
		end
	end)

	-- Listen for challenge expired event
	local expiredRemote = ChallengeEvents.GetRemoteEvent("ChallengeExpired")
	expiredRemote.OnClientEvent:Connect(function(data: ChallengeEvents.ChallengeExpiredData)
		if currentActiveChallengeId == data.challengeId then
			ChallengeInviteModal.Hide()
		end
	end)

	-- Listen for challenge respond event
	local respondRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")
	respondRemote.OnClientEvent:Connect(function(data: ChallengeEvents.ChallengeResponseData)
		if currentActiveChallengeId == data.challengeId then
			ChallengeInviteModal.Hide()
		end
	end)
end

--- Initializes the ChallengeInviteModal controller.
function ChallengeInviteModal.Initialize(targetPlayerGui: PlayerGui?)
	if isUIInitialized then
		return
	end
	isUIInitialized = true

	ChallengeEvents.Initialize()

	local playerGui = targetPlayerGui or Players.LocalPlayer:WaitForChild("PlayerGui")
	createUIElements(playerGui)
	bindEvents()
end

return ChallengeInviteModal
