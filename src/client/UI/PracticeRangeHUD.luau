--!strict
--[=[ OVERCLOCK: Practice Range HUD ]=]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = script.Parent
local UITheme = require(UIFolder:WaitForChild("UITheme") :: any)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)

local PracticeRangeHUD = {}
local screenGui: ScreenGui? = nil
local statsLabels: { [string]: TextLabel } = {}

local WEAPONS = {"Pistol", "AssaultRifle", "SniperRifle", "Shotgun"}
local OPERATIVES = {"Vex", "Warden", "Fray", "Choke", "Pulse", "Bastion"}

local isInitialized = false

function PracticeRangeHUD.Init(playerGui: PlayerGui)
	if isInitialized then return end
	isInitialized = true
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PracticeRangeGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Stats panel (top-right)
	local statsPanel = UITheme.createFrame(screenGui, UDim2.new(0, 220, 0, 200), UDim2.new(1, -230, 0, 10))
	statsPanel.BackgroundTransparency = 0.15

	local statsTitle = UITheme.createLabel(statsPanel, "RANGE STATS", UDim2.new(0.9, 0, 0, 22), UDim2.new(0.05, 0, 0, 5))
	statsTitle.TextSize = 14
	statsTitle.TextColor3 = UITheme.Colors.Accent

	local statNames = {"Shots Fired", "Hits", "Accuracy", "Headshot %"}
	local statKeys = {"totalShotsFired", "totalHits", "accuracyPercent", "headshotPercent"}
	for i, name in statNames do
		local lbl = UITheme.createLabel(statsPanel, name .. ": 0", UDim2.new(0.9, 0, 0, 20), UDim2.new(0.05, 0, 0, 28 + (i * 28)))
		lbl.TextSize = 14
		lbl.TextColor3 = UITheme.Colors.TextSecondary
		statsLabels[statKeys[i]] = lbl
	end

	local resetBtn = UITheme.createButton(statsPanel, "RESET", UDim2.new(0.9, 0, 0, 30), UDim2.new(0.05, 0, 1, -35))
	resetBtn.TextSize = 13
	resetBtn.MouseButton1Click:Connect(function()
		pcall(function() RemoteEvents.GetReliable("ResetRangeStats"):FireServer() end)
	end)

	-- Combined Left Sidebar Container (prevent overlapping)
	local leftSidebar = UITheme.createFrame(screenGui, UDim2.new(0, 180, 0, 480), UDim2.new(0, 10, 0.5, -220))
	leftSidebar.BackgroundTransparency = 0.15

	local leftScroll = Instance.new("ScrollingFrame")
	leftScroll.Size = UDim2.new(1, -10, 1, -20)
	leftScroll.Position = UDim2.new(0, 5, 0, 10)
	leftScroll.BackgroundTransparency = 1
	leftScroll.ScrollBarThickness = 4
	leftScroll.CanvasSize = UDim2.new(0, 0, 0, 540)
	leftScroll.Parent = leftSidebar

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 6)
	leftLayout.Parent = leftScroll

	-- Weapons Section
	local wpTitle = UITheme.createLabel(leftScroll, "WEAPONS", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 0))
	wpTitle.TextSize = 13
	wpTitle.Font = Enum.Font.GothamBold
	wpTitle.TextColor3 = UITheme.Colors.Accent

	for i, wId in WEAPONS do
		local btn = UITheme.createButton(leftScroll, wId, UDim2.new(1, -10, 0, 28), UDim2.new(0, 0, 0, 0))
		btn.TextSize = 12
		btn.MouseButton1Click:Connect(function()
			pcall(function() RemoteEvents.GetReliable("SwitchWeapon"):FireServer(wId) end)
		end)
	end

	-- Operatives Section
	local opDivider = Instance.new("Frame")
	opDivider.Size = UDim2.new(1, -10, 0, 10)
	opDivider.BackgroundTransparency = 1
	opDivider.Parent = leftScroll

	local opTitle = UITheme.createLabel(leftScroll, "OPERATIVE", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 0))
	opTitle.TextSize = 13
	opTitle.Font = Enum.Font.GothamBold
	opTitle.TextColor3 = UITheme.Colors.Accent

	for i, opId in OPERATIVES do
		local btn = UITheme.createButton(leftScroll, opId, UDim2.new(1, -10, 0, 28), UDim2.new(0, 0, 0, 0))
		btn.TextSize = 12
		btn.MouseButton1Click:Connect(function()
			pcall(function() RemoteEvents.GetReliable("SwitchOperative"):FireServer(opId) end)
		end)
	end

	-- Exit button (top-left)
	local exitBtn = UITheme.createButton(screenGui, "← EXIT TO LOBBY", UDim2.new(0, 160, 0, 36), UDim2.new(0, 10, 0, 10))
	exitBtn.TextSize = 13
	exitBtn.BackgroundColor3 = UITheme.Colors.Danger
	exitBtn.MouseButton1Click:Connect(function()
		pcall(function() RemoteEvents.GetReliable("LeavePracticeRange"):FireServer() end)
	end)

	-- Listen for stats updates
	pcall(function()
		RemoteEvents.GetReliable("RangeStatsUpdated").OnClientEvent:Connect(function(data: any)
			PracticeRangeHUD.UpdateStats(data)
		end)
	end)
end

function PracticeRangeHUD.Show()
	if screenGui then screenGui.Enabled = true end
end

function PracticeRangeHUD.Hide()
	if screenGui then screenGui.Enabled = false end
end

function PracticeRangeHUD.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

function PracticeRangeHUD.UpdateStats(data: any)
	if typeof(data) ~= "table" then return end
	if statsLabels.totalShotsFired then statsLabels.totalShotsFired.Text = "Shots Fired: " .. tostring(data.totalShotsFired or 0) end
	if statsLabels.totalHits then statsLabels.totalHits.Text = "Hits: " .. tostring(data.totalHits or 0) end
	if statsLabels.accuracyPercent then statsLabels.accuracyPercent.Text = "Accuracy: " .. string.format("%.1f%%", data.accuracyPercent or 0) end
	if statsLabels.headshotPercent then statsLabels.headshotPercent.Text = "Headshot %: " .. string.format("%.1f%%", data.headshotPercent or 0) end
end

return PracticeRangeHUD
