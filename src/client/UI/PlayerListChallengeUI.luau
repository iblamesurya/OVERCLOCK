--!strict
--[=[
    Project OVERCLOCK v2: PlayerListChallengeUI
    Client-side player list / leaderboard UI displaying online players,
    their current lobby status ("In Lobby", "In Queue", "In Match"),
    and a "Challenge 1v1" action button to send direct 1v1 duel invites.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ChallengeEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("ChallengeEvents"))

export type PlayerStatusMap = { [number]: string }

local PlayerListChallengeUI = {}

local screenGui: ScreenGui? = nil
local mainFrame: Frame? = nil
local listScrollFrame: ScrollingFrame? = nil
local toggleButton: TextButton? = nil

local isUIInitialized = false
local isVisible = true
local cachedStatuses: { [number]: string } = {}

local STATUS_COLORS: { [string]: Color3 } = {
	["In Lobby"] = Color3.fromRGB(0, 220, 120),
	["In Queue"] = Color3.fromRGB(255, 190, 0),
	["In Match"] = Color3.fromRGB(230, 60, 70),
}

local function getStatusColor(status: string): Color3
	return STATUS_COLORS[status] or Color3.fromRGB(180, 180, 180)
end

--- Sends a direct 1v1 challenge to a target player UserId.
local function sendChallengeToUser(targetUserId: number)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or localPlayer.UserId == targetUserId then
		return
	end

	local sendRemote = ChallengeEvents.GetRemoteEvent("ChallengeSend")
	sendRemote:FireServer(targetUserId)
end

--- Clears and rebuilds the player entry rows in the scrolling container.
function PlayerListChallengeUI.UpdatePlayerList()
	if not listScrollFrame then
		return
	end

	for _, child in ipairs(listScrollFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local localPlayer = Players.LocalPlayer
	local localUserId = if localPlayer then localPlayer.UserId else 0
	local localStatus = cachedStatuses[localUserId] or "In Lobby"

	local onlinePlayers = Players:GetPlayers()

	for idx, player in ipairs(onlinePlayers) do
		local userId = player.UserId
		local status = cachedStatuses[userId] or "In Lobby"
		local isSelf = (userId == localUserId)

		local row = Instance.new("Frame")
		row.Name = "PlayerRow_" .. tostring(userId)
		row.Size = UDim2.new(1, 0, 0, 42)
		row.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		row.Parent = listScrollFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		-- Name Label
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0.42, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 10, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = player.DisplayName .. (isSelf and " (You)" or "")
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 13
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		-- Status Tag Frame
		local statusTag = Instance.new("Frame")
		statusTag.Name = "StatusTag"
		statusTag.Size = UDim2.new(0.24, 0, 0, 24)
		statusTag.Position = UDim2.new(0.43, 0, 0.5, -12)
		statusTag.BackgroundColor3 = getStatusColor(status)
		statusTag.BackgroundTransparency = 0.8
		statusTag.Parent = row

		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 4)
		tagCorner.Parent = statusTag

		local tagStroke = Instance.new("UIStroke")
		tagStroke.Color = getStatusColor(status)
		tagStroke.Thickness = 1
		tagStroke.Parent = statusTag

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Size = UDim2.new(1, 0, 1, 0)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Text = status
		statusLabel.TextColor3 = getStatusColor(status)
		statusLabel.TextSize = 10
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.Parent = statusTag

		-- Challenge 1v1 Action Button
		local challengeBtn = Instance.new("TextButton")
		challengeBtn.Name = "ChallengeButton"
		challengeBtn.Size = UDim2.new(0.28, -10, 0, 28)
		challengeBtn.Position = UDim2.new(0.70, 5, 0.5, -14)
		challengeBtn.Font = Enum.Font.GothamBold
		challengeBtn.TextSize = 11
		challengeBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = challengeBtn

		if isSelf then
			challengeBtn.Text = "YOU"
			challengeBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
			challengeBtn.TextColor3 = Color3.fromRGB(140, 140, 150)
			challengeBtn.AutoButtonColor = false
		elseif status ~= "In Lobby" or localStatus ~= "In Lobby" then
			challengeBtn.Text = "BUSY"
			challengeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 70)
			challengeBtn.TextColor3 = Color3.fromRGB(150, 150, 160)
			challengeBtn.AutoButtonColor = false
		else
			challengeBtn.Text = "CHALLENGE 1v1"
			challengeBtn.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
			challengeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			challengeBtn.AutoButtonColor = true

			challengeBtn.MouseButton1Click:Connect(function()
				sendChallengeToUser(userId)
			end)
		end
	end

	if listScrollFrame then
		listScrollFrame.CanvasSize = UDim2.new(0, 0, 0, #onlinePlayers * 48)
	end
end

--- Updates the stored status for a given user ID and refreshes UI.
function PlayerListChallengeUI.SetPlayerStatus(userId: number, status: string)
	cachedStatuses[userId] = status
	PlayerListChallengeUI.UpdatePlayerList()
end

--- Toggles the visibility of the player list UI panel.
function PlayerListChallengeUI.ToggleVisibility()
	if not mainFrame then
		return
	end
	isVisible = not isVisible
	mainFrame.Visible = isVisible
end

--- Explicitly sets the visibility of the player list UI panel.
function PlayerListChallengeUI.SetVisible(visible: boolean)
	isVisible = visible
	if mainFrame then
		mainFrame.Visible = visible
	end
end

local function createUIElements(targetParent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerListChallengeGui"
	gui.ResetOnSpawn = false
	gui.Parent = targetParent
	screenGui = gui

	-- Main Container Panel
	local panel = Instance.new("Frame")
	panel.Name = "PlayerListPanel"
	panel.Size = UDim2.new(0, 360, 0, 380)
	panel.Position = UDim2.new(1, -380, 0, 60)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	mainFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(50, 55, 70)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	-- Header Title
	local header = Instance.new("TextLabel")
	header.Name = "HeaderLabel"
	header.Size = UDim2.new(1, -50, 0, 45)
	header.Position = UDim2.new(0, 15, 0, 0)
	header.BackgroundTransparency = 1
	header.Text = "PLAYERS IN LOBBY"
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.TextSize = 16
	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	-- Toggle / Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "ToggleButton"
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -38, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	closeBtn.Text = "—"
	closeBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
	closeBtn.TextSize = 14
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = panel
	toggleButton = closeBtn

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		PlayerListChallengeUI.ToggleVisibility()
	end)

	-- Player List Scroll Container
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PlayerScrollFrame"
	scroll.Size = UDim2.new(1, -20, 1, -60)
	scroll.Position = UDim2.new(0, 10, 0, 50)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
	scroll.Parent = panel
	listScrollFrame = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = scroll
end

local function bindEvents()
	Players.PlayerAdded:Connect(function()
		PlayerListChallengeUI.UpdatePlayerList()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		cachedStatuses[player.UserId] = nil
		PlayerListChallengeUI.UpdatePlayerList()
	end)

	local respondRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")
	respondRemote.OnClientEvent:Connect(function(data: ChallengeEvents.ChallengeResponseData)
		if data.accepted then
			cachedStatuses[data.challengerUserId] = "In Match"
			cachedStatuses[data.targetUserId] = "In Match"
			PlayerListChallengeUI.UpdatePlayerList()
		end
	end)
end

--- Initializes the PlayerListChallengeUI controller.
function PlayerListChallengeUI.Initialize(targetPlayerGui: PlayerGui?)
	if isUIInitialized then
		return
	end
	isUIInitialized = true

	ChallengeEvents.Initialize()

	local playerGui = targetPlayerGui or Players.LocalPlayer:WaitForChild("PlayerGui")
	createUIElements(playerGui)
	bindEvents()
	PlayerListChallengeUI.UpdatePlayerList()
end

return PlayerListChallengeUI
