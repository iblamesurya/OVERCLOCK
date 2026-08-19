--!strict
--[=[ OVERCLOCK: Post-Match Summary UI ]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIFolder = script.Parent
local UITheme = require(UIFolder:WaitForChild("UITheme") :: any)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)

local PostMatchSummaryUI = {}
local screenGui: ScreenGui? = nil
local mainFrame: Frame? = nil

local isInitialized = false

function PostMatchSummaryUI.Init(playerGui: PlayerGui)
	if isInitialized then return end
	isInitialized = true
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PostMatchGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 20
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0.7, 0, 0.8, 0)
	mainFrame.Position = UDim2.new(0.15, 0, 0.1, 0)
	mainFrame.BackgroundColor3 = UITheme.Colors.Background
	mainFrame.BackgroundTransparency = 0.05
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	UITheme.applyCorner(mainFrame)
	UITheme.applyStroke(mainFrame, UITheme.Colors.Border, 2)

	-- Listen for match result
	pcall(function()
		RemoteEvents.GetReliable("MatchResult").OnClientEvent:Connect(function(data: any)
			PostMatchSummaryUI.Show(data)
		end)
	end)
end

function PostMatchSummaryUI.Show(matchData: any)
	if not screenGui or not mainFrame then return end
	-- Clear previous
	for _, c in mainFrame:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") then c:Destroy() end
	end

	local localPlayer = Players.LocalPlayer
	local isWin = false
	if typeof(matchData) == "table" then
		isWin = matchData.winner == localPlayer.Name or matchData.winnerTeam == matchData.myTeam
	end

	-- Banner
	local banner = UITheme.createLabel(mainFrame, if isWin then "VICTORY" else "DEFEAT", UDim2.new(0.8, 0, 0, 60), UDim2.new(0.1, 0, 0.02, 0))
	banner.TextSize = 48
	banner.TextColor3 = if isWin then UITheme.Colors.Success else UITheme.Colors.Danger
	banner.TextXAlignment = Enum.TextXAlignment.Center

	-- Score
	local t1 = if typeof(matchData) == "table" then matchData.team1Score or 0 else 0
	local t2 = if typeof(matchData) == "table" then matchData.team2Score or 0 else 0
	local scoreL = UITheme.createLabel(mainFrame, tostring(t1) .. " — " .. tostring(t2), UDim2.new(0.6, 0, 0, 40), UDim2.new(0.2, 0, 0.12, 0))
	scoreL.TextSize = 32
	scoreL.TextXAlignment = Enum.TextXAlignment.Center

	-- Scoreboard header
	local headers = {"Player", "Agent", "K", "D", "A", "DMG"}
	local colWidths = {0.25, 0.15, 0.1, 0.1, 0.1, 0.15}
	local headerY = 0.22
	local xOff = 0.05
	for i, h in headers do
		local hl = UITheme.createLabel(mainFrame, h, UDim2.new(colWidths[i], 0, 0, 20), UDim2.new(xOff, 0, headerY, 0))
		hl.TextSize = 13
		hl.TextColor3 = UITheme.Colors.Accent
		xOff += colWidths[i]
	end

	-- Player rows
	local playerList = if typeof(matchData) == "table" then matchData.players else nil
	if typeof(playerList) == "table" then
		for idx, pData in playerList :: {any} do
			local rowY = headerY + 0.03 + (idx * 0.05)
			xOff = 0.05
			local vals = {
				tostring(pData.name or "?"),
				tostring(pData.operative or "?"),
				tostring(pData.kills or 0),
				tostring(pData.deaths or 0),
				tostring(pData.assists or 0),
				tostring(pData.damage or 0),
			}
			for i, v in vals do
				local vl = UITheme.createLabel(mainFrame, v, UDim2.new(colWidths[i], 0, 0, 18), UDim2.new(xOff, 0, rowY, 0))
				vl.TextSize = 14
				vl.TextColor3 = UITheme.Colors.TextSecondary
				xOff += colWidths[i]
			end
		end
	end

	-- XP / Credits
	local xp = if typeof(matchData) == "table" then matchData.xpGained or 0 else 0
	local cr = if typeof(matchData) == "table" then matchData.creditsGained or 0 else 0
	local rewardL = UITheme.createLabel(mainFrame, "+" .. tostring(xp) .. " XP   +" .. tostring(cr) .. " Credits", UDim2.new(0.6, 0, 0, 24), UDim2.new(0.2, 0, 0.78, 0))
	rewardL.TextSize = 18
	rewardL.TextColor3 = UITheme.Colors.Gold
	rewardL.TextXAlignment = Enum.TextXAlignment.Center

	-- Continue button
	local contBtn = UITheme.createAccentButton(mainFrame, "CONTINUE", UDim2.new(0.25, 0, 0, 40), UDim2.new(0.375, 0, 0.87, 0))
	contBtn.TextSize = 16
	contBtn.MouseButton1Click:Connect(function()
		PostMatchSummaryUI.Hide()
		pcall(function()
			RemoteEvents.GetReliable("MatchPhaseTransition"):FireServer({action = "ReturnToLobby"})
		end)
	end)

	screenGui.Enabled = true

	-- Auto-dismiss
	task.delay(15, function()
		if screenGui and screenGui.Enabled then PostMatchSummaryUI.Hide() end
	end)
end

function PostMatchSummaryUI.Hide()
	if screenGui then screenGui.Enabled = false end
end

return PostMatchSummaryUI
