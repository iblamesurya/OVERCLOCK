--!strict
--[=[
    Project OVERCLOCK v2: MatchmakingQueueUI
    Client-side UI controller for queue selection (1v1 vs 2v2 mode tabs), 5-map voting grid,
    queue timer, cancel queue button, and match found notification modal.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QueueEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("QueueEvents"))

export type QueueMode = QueueEvents.QueueMode

local MAP_LIST = {
	"GreyboxArena",
	"CyberCity",
	"DesertOutpost",
	"NeonSubway",
	"Hangar18",
}

local MAP_DESCRIPTIONS: { [string]: string } = {
	["GreyboxArena"] = "Standard symmetrical testing arena with balanced sightlines.",
	["CyberCity"] = "High-tech urban battlefield with multi-level verticality.",
	["DesertOutpost"] = "Arid desert outpost featuring open sniper corridors.",
	["NeonSubway"] = "Subterranean metro system with intense close-quarters combat.",
	["Hangar18"] = "Industrial facility with central control objectives.",
}

local MatchmakingQueueUI = {}

local currentMode: QueueMode = "1v1"
local isInQueue = false
local queueStartTime = 0
local timerThread: thread? = nil
local activeMatchId: string? = nil
local userVotedMap: string? = nil

local screenGui: ScreenGui? = nil
local mainFrame: Frame? = nil
local modeTab1v1: TextButton? = nil
local modeTab2v2: TextButton? = nil
local queueButton: TextButton? = nil
local cancelButton: TextButton? = nil
local queueStatusLabel: TextLabel? = nil
local queueTimerLabel: TextLabel? = nil

local matchModalFrame: Frame? = nil
local matchTitleLabel: TextLabel? = nil
local matchTimerLabel: TextLabel? = nil
local teamsContainer: Frame? = nil
local mapGridFrame: Frame? = nil
local mapCards: { [string]: { cardFrame: Frame, voteButton: TextButton, voteCountLabel: TextLabel } } = {}
local winnerAnnounceLabel: TextLabel? = nil

local isUIInitialized = false
local bindEvents: () -> ()

local function formatTimer(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

local function updateTabStyles()
	if not modeTab1v1 or not modeTab2v2 then
		return
	end

	if currentMode == "1v1" then
		modeTab1v1.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
		modeTab1v1.TextColor3 = Color3.fromRGB(255, 255, 255)
		modeTab2v2.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		modeTab2v2.TextColor3 = Color3.fromRGB(180, 180, 180)
	else
		modeTab1v1.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		modeTab1v1.TextColor3 = Color3.fromRGB(180, 180, 180)
		modeTab2v2.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
		modeTab2v2.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

local function stopQueueTimer()
	if timerThread then
		task.cancel(timerThread)
		timerThread = nil
	end
	if queueTimerLabel then
		queueTimerLabel.Text = "00:00"
	end
end

local function startQueueTimer()
	stopQueueTimer()
	queueStartTime = os.time()
	timerThread = task.spawn(function()
		while isInQueue do
			local elapsed = os.time() - queueStartTime
			if queueTimerLabel then
				queueTimerLabel.Text = formatTimer(elapsed)
			end
			task.wait(1.0)
		end
	end)
end

local function createUIElements(targetParent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchmakingQueueGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14
	gui.Enabled = false
	gui.Parent = targetParent
	screenGui = gui

	-- Main Queue Panel
	local panel = Instance.new("Frame")
	panel.Name = "QueuePanel"
	panel.Size = UDim2.new(0, 420, 0, 320)
	panel.Position = UDim2.new(0.5, -210, 0.5, -160)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	mainFrame = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(60, 65, 80)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	-- Title Header
	local header = Instance.new("TextLabel")
	header.Name = "HeaderLabel"
	header.Size = UDim2.new(1, -50, 0, 45)
	header.Position = UDim2.new(0, 10, 0, 0)
	header.BackgroundTransparency = 1
	header.Text = "OVERCLOCK MATCHMAKING"
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.TextSize = 18
	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	-- Top-Right Close Button ("✕")
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -38, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
	closeBtn.TextSize = 14
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		MatchmakingQueueUI.HideQueuePanel()
		if isInQueue then
			MatchmakingQueueUI.CancelQueue()
		end
		local ok, LobbyUICtrl = pcall(function()
			return require(script.Parent:WaitForChild("LobbyUIController") :: any)
		end)
		if ok and LobbyUICtrl and LobbyUICtrl.SetState then
			LobbyUICtrl.SetState("Main")
		end
	end)

	-- Mode Selection Tabs (1v1 vs 2v2)
	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "TabContainer"
	tabContainer.Size = UDim2.new(1, -40, 0, 40)
	tabContainer.Position = UDim2.new(0, 20, 0, 50)
	tabContainer.BackgroundTransparency = 1
	tabContainer.Parent = panel

	local t1v1 = Instance.new("TextButton")
	t1v1.Name = "Tab1v1"
	t1v1.Size = UDim2.new(0.48, 0, 1, 0)
	t1v1.Position = UDim2.new(0, 0, 0, 0)
	t1v1.Text = "1v1 DUEL"
	t1v1.Font = Enum.Font.GothamBold
	t1v1.TextSize = 14
	t1v1.Parent = tabContainer
	modeTab1v1 = t1v1

	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0, 8)
	c1.Parent = t1v1

	local t2v2 = Instance.new("TextButton")
	t2v2.Name = "Tab2v2"
	t2v2.Size = UDim2.new(0.48, 0, 1, 0)
	t2v2.Position = UDim2.new(0.52, 0, 0, 0)
	t2v2.Text = "2v2 TEAM"
	t2v2.Font = Enum.Font.GothamBold
	t2v2.TextSize = 14
	t2v2.Parent = tabContainer
	modeTab2v2 = t2v2

	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 8)
	c2.Parent = t2v2

	-- Status Information Labels
	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "QueueStatusLabel"
	statusLbl.Size = UDim2.new(1, -40, 0, 30)
	statusLbl.Position = UDim2.new(0, 20, 0, 105)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = "Select Mode and Enter Queue"
	statusLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
	statusLbl.TextSize = 14
	statusLbl.Font = Enum.Font.Gotham
	statusLbl.Parent = panel
	queueStatusLabel = statusLbl

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "QueueTimerLabel"
	timerLbl.Size = UDim2.new(1, -40, 0, 45)
	timerLbl.Position = UDim2.new(0, 20, 0, 140)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Text = "00:00"
	timerLbl.TextColor3 = Color3.fromRGB(0, 220, 130)
	timerLbl.TextSize = 32
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.Parent = panel
	queueTimerLabel = timerLbl

	-- Enter Queue Button
	local qBtn = Instance.new("TextButton")
	qBtn.Name = "EnterQueueButton"
	qBtn.Size = UDim2.new(1, -40, 0, 45)
	qBtn.Position = UDim2.new(0, 20, 0, 195)
	qBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	qBtn.Text = "ENTER QUEUE"
	qBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	qBtn.TextSize = 16
	qBtn.Font = Enum.Font.GothamBold
	qBtn.Parent = panel
	queueButton = qBtn

	local qBtnCorner = Instance.new("UICorner")
	qBtnCorner.CornerRadius = UDim.new(0, 8)
	qBtnCorner.Parent = qBtn

	-- Cancel Queue Button
	local cBtn = Instance.new("TextButton")
	cBtn.Name = "CancelQueueButton"
	cBtn.Size = UDim2.new(1, -40, 0, 45)
	cBtn.Position = UDim2.new(0, 20, 0, 250)
	cBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 60)
	cBtn.Text = "CANCEL QUEUE"
	cBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	cBtn.TextSize = 16
	cBtn.Font = Enum.Font.GothamBold
	cBtn.Visible = false
	cBtn.Parent = panel
	cancelButton = cBtn

	local cBtnCorner = Instance.new("UICorner")
	cBtnCorner.CornerRadius = UDim.new(0, 8)
	cBtnCorner.Parent = cBtn

	-- Match Found & 5-Map Voting Modal Frame
	local modal = Instance.new("Frame")
	modal.Name = "MatchFoundModal"
	modal.Size = UDim2.new(0, 720, 0, 520)
	modal.Position = UDim2.new(0.5, -360, 0.5, -260)
	modal.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = gui
	matchModalFrame = modal

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 14)
	modalCorner.Parent = modal

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Color3.fromRGB(0, 162, 255)
	modalStroke.Thickness = 3
	modalStroke.Parent = modal

	local mTitle = Instance.new("TextLabel")
	mTitle.Name = "MatchTitle"
	mTitle.Size = UDim2.new(1, 0, 0, 40)
	mTitle.Position = UDim2.new(0, 0, 0, 10)
	mTitle.BackgroundTransparency = 1
	mTitle.Text = "MATCH FOUND — VOTE FOR MAP"
	mTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	mTitle.TextSize = 22
	mTitle.Font = Enum.Font.GothamBold
	mTitle.Parent = modal
	matchTitleLabel = mTitle

	local mTimer = Instance.new("TextLabel")
	mTimer.Name = "MatchTimer"
	mTimer.Size = UDim2.new(1, 0, 0, 30)
	mTimer.Position = UDim2.new(0, 0, 0, 50)
	mTimer.BackgroundTransparency = 1
	mTimer.Text = "Voting Ends In: 10s"
	mTimer.TextColor3 = Color3.fromRGB(255, 200, 0)
	mTimer.TextSize = 18
	mTimer.Font = Enum.Font.GothamBold
	mTimer.Parent = modal
	matchTimerLabel = mTimer

	local teamsFrame = Instance.new("Frame")
	teamsFrame.Name = "TeamsContainer"
	teamsFrame.Size = UDim2.new(1, -40, 0, 60)
	teamsFrame.Position = UDim2.new(0, 20, 0, 85)
	teamsFrame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	teamsFrame.Parent = modal
	teamsContainer = teamsFrame

	local teamsCorner = Instance.new("UICorner")
	teamsCorner.CornerRadius = UDim.new(0, 8)
	teamsCorner.Parent = teamsFrame

	-- 5-Map Voting Grid Frame
	local grid = Instance.new("Frame")
	grid.Name = "MapVotingGrid"
	grid.Size = UDim2.new(1, -40, 0, 310)
	grid.Position = UDim2.new(0, 20, 0, 155)
	grid.BackgroundTransparency = 1
	grid.Parent = modal
	mapGridFrame = grid

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 128, 0, 145)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for idx, mapName in ipairs(MAP_LIST) do
		local card = Instance.new("Frame")
		card.Name = "MapCard_" .. mapName
		card.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
		card.LayoutOrder = idx
		card.Parent = grid

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = Color3.fromRGB(60, 65, 80)
		cardStroke.Thickness = 1
		cardStroke.Parent = card

		local mapNameLbl = Instance.new("TextLabel")
		mapNameLbl.Size = UDim2.new(1, -8, 0, 24)
		mapNameLbl.Position = UDim2.new(0, 4, 0, 4)
		mapNameLbl.BackgroundTransparency = 1
		mapNameLbl.Text = mapName
		mapNameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		mapNameLbl.TextSize = 12
		mapNameLbl.Font = Enum.Font.GothamBold
		mapNameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, -8, 0, 50)
		descLbl.Position = UDim2.new(0, 4, 0, 28)
		descLbl.BackgroundTransparency = 1
		descLbl.Text = MAP_DESCRIPTIONS[mapName] or "Arena map"
		descLbl.TextColor3 = Color3.fromRGB(170, 170, 185)
		descLbl.TextSize = 10
		descLbl.TextWrapped = true
		descLbl.Font = Enum.Font.Gotham
		descLbl.Parent = card

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(1, 0, 0, 20)
		countLbl.Position = UDim2.new(0, 0, 0, 80)
		countLbl.BackgroundTransparency = 1
		countLbl.Text = "Votes: 0"
		countLbl.TextColor3 = Color3.fromRGB(0, 220, 130)
		countLbl.TextSize = 12
		countLbl.Font = Enum.Font.GothamBold
		countLbl.Parent = card

		local vBtn = Instance.new("TextButton")
		vBtn.Size = UDim2.new(1, -12, 0, 32)
		vBtn.Position = UDim2.new(0, 6, 0, 105)
		vBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 230)
		vBtn.Text = "VOTE MAP"
		vBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		vBtn.TextSize = 11
		vBtn.Font = Enum.Font.GothamBold
		vBtn.Parent = card

		local vBtnCorner = Instance.new("UICorner")
		vBtnCorner.CornerRadius = UDim.new(0, 6)
		vBtnCorner.Parent = vBtn

		vBtn.MouseButton1Click:Connect(function()
			MatchmakingQueueUI.VoteForMap(mapName)
		end)

		mapCards[mapName] = {
			cardFrame = card,
			voteButton = vBtn,
			voteCountLabel = countLbl,
		}
	end

	local winAnnounce = Instance.new("TextLabel")
	winAnnounce.Name = "WinnerAnnouncement"
	winAnnounce.Size = UDim2.new(1, -40, 0, 35)
	winAnnounce.Position = UDim2.new(0, 20, 0, 475)
	winAnnounce.BackgroundTransparency = 1
	winAnnounce.Text = ""
	winAnnounce.TextColor3 = Color3.fromRGB(255, 220, 0)
	winAnnounce.TextSize = 16
	winAnnounce.Font = Enum.Font.GothamBold
	winAnnounce.Parent = modal
	winnerAnnounceLabel = winAnnounce

	updateTabStyles()
	bindEvents()
end

--- Connects UI signals to tab buttons and queue action buttons.
local eventsBound = false
bindEvents = function()
	if eventsBound then return end
	eventsBound = true
	if not modeTab1v1 or not modeTab2v2 or not queueButton or not cancelButton then
		return
	end

	modeTab1v1.MouseButton1Click:Connect(function()
		if not isInQueue then
			currentMode = "1v1"
			updateTabStyles()
		end
	end)

	modeTab2v2.MouseButton1Click:Connect(function()
		if not isInQueue then
			currentMode = "2v2"
			updateTabStyles()
		end
	end)

	queueButton.MouseButton1Click:Connect(function()
		if not isInQueue then
			MatchmakingQueueUI.StartQueue()
		end
	end)

	cancelButton.MouseButton1Click:Connect(function()
		if isInQueue then
			MatchmakingQueueUI.CancelQueue()
		end
	end)

	-- Network Listeners
	local statusRemote = QueueEvents.GetRemoteEvent("QueueStatusUpdate")
	statusRemote.OnClientEvent:Connect(function(payload: QueueEvents.QueueStatusData)
		isInQueue = payload.inQueue

		if queueStatusLabel then
			if payload.inQueue then
				queueStatusLabel.Text = string.format("Searching for %s Match (%d in queue)...", payload.mode or currentMode, payload.playersInQueue)
			else
				queueStatusLabel.Text = "Select Mode and Enter Queue"
			end
		end

		if queueButton and cancelButton then
			queueButton.Visible = not payload.inQueue
			cancelButton.Visible = payload.inQueue
		end

		if payload.inQueue then
			startQueueTimer()
		else
			stopQueueTimer()
		end
	end)

	local matchFoundRemote = QueueEvents.GetRemoteEvent("QueueMatchFound")
	matchFoundRemote.OnClientEvent:Connect(function(data: QueueEvents.MatchFoundData)
		MatchmakingQueueUI.ShowMatchFound(data)
	end)

	local voteUpdateRemote = QueueEvents.GetRemoteEvent("MapVoteUpdate")
	voteUpdateRemote.OnClientEvent:Connect(function(result: QueueEvents.MapVoteResult)
		MatchmakingQueueUI.UpdateVoteResults(result)
	end)
end

--- Enters the current queue mode via network remote function.
function MatchmakingQueueUI.StartQueue()
	local enterFn = QueueEvents.GetRemoteFunction("QueueEnter")
	local success, reason = enterFn:InvokeServer(currentMode)

	if success then
		isInQueue = true
		if queueStatusLabel then
			queueStatusLabel.Text = "Searching for " .. currentMode .. " Match..."
		end
		if queueButton and cancelButton then
			queueButton.Visible = false
			cancelButton.Visible = true
		end
		startQueueTimer()
	else
		if queueStatusLabel then
			queueStatusLabel.Text = "Queue Error: " .. (reason or "Failed to enter queue")
		end
	end
end

--- Cancels and leaves the active queue via network remote function.
function MatchmakingQueueUI.CancelQueue()
	local leaveFn = QueueEvents.GetRemoteFunction("QueueLeave")
	local success, reason = leaveFn:InvokeServer()

	if success then
		isInQueue = false
		stopQueueTimer()
		if queueStatusLabel then
			queueStatusLabel.Text = "Select Mode and Enter Queue"
		end
		if queueButton and cancelButton then
			queueButton.Visible = true
			cancelButton.Visible = false
		end
	else
		if queueStatusLabel then
			queueStatusLabel.Text = "Cancel Error: " .. (reason or "Failed to leave queue")
		end
	end
end

--- Displays the Match Found notification modal and map voting grid.
function MatchmakingQueueUI.ShowMatchFound(data: QueueEvents.MatchFoundData)
	isInQueue = false
	stopQueueTimer()
	activeMatchId = data.matchId
	userVotedMap = nil

	if mainFrame then
		mainFrame.Visible = false
	end

	if matchModalFrame then
		matchModalFrame.Visible = true
		matchModalFrame.Size = UDim2.new(0, 10, 0, 10)
		matchModalFrame.Position = UDim2.new(0.5, -5, 0.5, -5)
		TweenService:Create(matchModalFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 720, 0, 520),
			Position = UDim2.new(0.5, -360, 0.5, -260),
		}):Play()
	end

	if matchTitleLabel then
		matchTitleLabel.Text = string.format("MATCH FOUND (%s) — VOTE FOR MAP", data.mode)
	end

	if winnerAnnounceLabel then
		winnerAnnounceLabel.Text = ""
	end

	-- Render Team Roster
	if teamsContainer then
		for _, child in ipairs(teamsContainer:GetChildren()) do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end

		local team1Text = "Team 1: "
		for i, tm in ipairs(data.teammates) do
			team1Text ..= tm.displayName .. (i < #data.teammates and ", " or "")
		end

		local team2Text = "VS  Team 2: "
		for i, op in ipairs(data.opponents) do
			team2Text ..= op.displayName .. (i < #data.opponents and ", " or "")
		end

		local rosterLabel = Instance.new("TextLabel")
		rosterLabel.Size = UDim2.new(1, -20, 1, 0)
		rosterLabel.Position = UDim2.new(0, 10, 0, 0)
		rosterLabel.BackgroundTransparency = 1
		rosterLabel.Text = team1Text .. "   " .. team2Text
		rosterLabel.TextColor3 = Color3.fromRGB(220, 220, 235)
		rosterLabel.TextSize = 13
		rosterLabel.Font = Enum.Font.GothamBold
		rosterLabel.Parent = teamsContainer
	end

	-- Reset Voting Card States
	for mapName, cardInfo in pairs(mapCards) do
		cardInfo.voteCountLabel.Text = "Votes: 0"
		cardInfo.voteButton.BackgroundColor3 = Color3.fromRGB(0, 140, 230)
		cardInfo.voteButton.Text = "VOTE MAP"
	end

	-- Voting Timer Countdown
	task.spawn(function()
		local remaining = data.votingDurationSeconds
		while remaining > 0 and activeMatchId == data.matchId do
			if matchTimerLabel then
				matchTimerLabel.Text = string.format("Voting Ends In: %ds", remaining)
			end
			task.wait(1.0)
			remaining -= 1
		end
	end)
end

--- Submits map vote selection for the current active match.
function MatchmakingQueueUI.VoteForMap(mapName: string)
	if not activeMatchId then
		return
	end

	userVotedMap = mapName

	for mName, cardInfo in pairs(mapCards) do
		if mName == mapName then
			cardInfo.voteButton.BackgroundColor3 = Color3.fromRGB(0, 220, 120)
			cardInfo.voteButton.Text = "VOTED ✓"
		else
			cardInfo.voteButton.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
			cardInfo.voteButton.Text = "VOTE MAP"
		end
	end

	local voteFn = QueueEvents.GetRemoteFunction("MapVoteSubmit")
	voteFn:InvokeServer(activeMatchId, mapName)
end

--- Updates the voting tallies and winner announcement modal.
function MatchmakingQueueUI.UpdateVoteResults(result: QueueEvents.MapVoteResult)
	if activeMatchId ~= result.matchId then
		return
	end

	for mapName, cardInfo in pairs(mapCards) do
		local count = result.mapVotes[mapName] or 0
		cardInfo.voteCountLabel.Text = "Votes: " .. tostring(count)
	end

	if result.votingEnded and result.winningMap then
		if winnerAnnounceLabel then
			winnerAnnounceLabel.Text = string.format("WINNING MAP: %s! Teleporting to Arena...", string.upper(result.winningMap))
		end

		if matchTimerLabel then
			matchTimerLabel.Text = "MAP SELECTED!"
		end

		task.delay(3.0, function()
			if matchModalFrame then
				matchModalFrame.Visible = false
			end
			if mainFrame then
				mainFrame.Visible = true
			end
			activeMatchId = nil
		end)
	end
end

--- Shows the main queue panel.
function MatchmakingQueueUI.ShowQueuePanel()
	if screenGui then
		screenGui.Enabled = true
	end
	if mainFrame then
		mainFrame.Visible = true
	end
	if matchModalFrame then
		matchModalFrame.Visible = false
	end
end

--- Hides the queue panel.
function MatchmakingQueueUI.HideQueuePanel()
	if screenGui then
		screenGui.Enabled = false
	end
	if mainFrame then
		mainFrame.Visible = false
	end
	if matchModalFrame then
		matchModalFrame.Visible = false
	end
end

--- Returns true if queue panel is currently visible.
function MatchmakingQueueUI.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled and mainFrame ~= nil and mainFrame.Visible
end

--- Initializes the MatchmakingQueueUI module.
function MatchmakingQueueUI.Initialize(targetPlayerGui: PlayerGui?)
	if isUIInitialized then
		return
	end
	isUIInitialized = true

	local playerGui = targetPlayerGui or Players.LocalPlayer:WaitForChild("PlayerGui")
	createUIElements(playerGui)
	bindEvents()
end

return MatchmakingQueueUI
