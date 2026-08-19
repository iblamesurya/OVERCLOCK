--!strict
--[=[ OVERCLOCK: Buy Menu Controller ]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIFolder = script.Parent
local UITheme = require(UIFolder:WaitForChild("UITheme") :: any)
local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)

local BuyMenuController = {}
local screenGui: ScreenGui? = nil
local creditsLabel: TextLabel? = nil
local currentCredits = 0
local purchased: { [string]: boolean } = {}

local CATALOG = {
	{id = "Pistol", price = 0, cat = "Sidearm"},
	{id = "AssaultRifle", price = 2900, cat = "Rifle"},
	{id = "SniperRifle", price = 4500, cat = "Sniper"},
	{id = "Shotgun", price = 1800, cat = "Shotgun"},
	{id = "LightArmor", price = 400, cat = "Armor"},
	{id = "HeavyArmor", price = 1000, cat = "Armor"},
}

local isInitialized = false

function BuyMenuController.Init(playerGui: PlayerGui)
	if isInitialized then return end
	isInitialized = true
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuyMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 14
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.65, 0, 0.75, 0)
	panel.Position = UDim2.new(0.175, 0, 0.125, 0)
	panel.BackgroundColor3 = UITheme.Colors.Background
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	UITheme.applyCorner(panel)
	UITheme.applyStroke(panel, UITheme.Colors.Border, 2)

	local title = UITheme.createLabel(panel, "BUY MENU", UDim2.new(0.3, 0, 0, 30), UDim2.new(0.05, 0, 0.02, 0))
	title.TextSize = 22

	creditsLabel = UITheme.createLabel(panel, "CREDITS: 0", UDim2.new(0.3, 0, 0, 30), UDim2.new(0.65, 0, 0.02, 0))
	creditsLabel.TextSize = 20
	creditsLabel.TextColor3 = UITheme.Colors.Gold
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Right

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(0.92, 0, 0.82, 0)
	grid.Position = UDim2.new(0.04, 0, 0.12, 0)
	grid.BackgroundTransparency = 1
	grid.Parent = panel

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.18, -8, 0.28, -8)
	layout.CellPadding = UDim2.new(0.01, 0, 0.02, 0)
	layout.Parent = grid

	for _, item in CATALOG do
		local card = Instance.new("TextButton")
		card.Name = item.id
		card.BackgroundColor3 = UITheme.Colors.Panel
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.Parent = grid
		UITheme.applyCorner(card)
		UITheme.applyStroke(card, UITheme.Colors.Border)

		local wData = WeaponStats.Get(item.id)
		local displayName = if wData then wData.displayName else item.id

		local nameL = UITheme.createLabel(card, displayName, UDim2.new(0.9, 0, 0, 16), UDim2.new(0.05, 0, 0.05, 0))
		nameL.TextSize = 12
		nameL.TextXAlignment = Enum.TextXAlignment.Center

		local catL = UITheme.createLabel(card, item.cat, UDim2.new(0.9, 0, 0, 14), UDim2.new(0.05, 0, 0.25, 0))
		catL.TextSize = 10
		catL.TextColor3 = UITheme.Colors.TextSecondary
		catL.TextXAlignment = Enum.TextXAlignment.Center

		local priceL = UITheme.createLabel(card, if item.price == 0 then "FREE" else "$" .. tostring(item.price), UDim2.new(0.9, 0, 0, 18), UDim2.new(0.05, 0, 0.55, 0))
		priceL.TextSize = 14
		priceL.TextColor3 = if item.price == 0 then UITheme.Colors.Success else UITheme.Colors.Gold
		priceL.TextXAlignment = Enum.TextXAlignment.Center

		if wData then
			local statL = UITheme.createLabel(card, "DMG:" .. tostring(wData.damage) .. " RPM:" .. tostring(wData.fireRate), UDim2.new(0.9, 0, 0, 12), UDim2.new(0.05, 0, 0.78, 0))
			statL.TextSize = 9
			statL.TextColor3 = UITheme.Colors.TextSecondary
			statL.TextXAlignment = Enum.TextXAlignment.Center
		end

		UITheme.addHoverFeedback(card)

		card.MouseButton1Click:Connect(function()
			if purchased[item.id] then return end
			pcall(function()
				RemoteEvents.GetReliable("RequestPurchase"):FireServer(item.id)
			end)
		end)
	end

	-- Listen for purchase results
	pcall(function()
		RemoteEvents.GetReliable("PurchaseResult").OnClientEvent:Connect(function(data: any)
			if typeof(data) ~= "table" then return end
			if data.success then
				purchased[data.itemId] = true
				currentCredits = data.balance or currentCredits
				if creditsLabel then creditsLabel.Text = "CREDITS: " .. tostring(currentCredits) end
				local card = grid:FindFirstChild(data.itemId)
				if card then
					TweenService:Create(card, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(20, 60, 30)}):Play()
				end
			else
				local card = grid:FindFirstChild(data.itemId)
				if card then
					TweenService:Create(card, TweenInfo.new(0.15), {BackgroundColor3 = UITheme.Colors.Danger}):Play()
					task.delay(0.3, function()
						TweenService:Create(card, TweenInfo.new(0.15), {BackgroundColor3 = UITheme.Colors.Panel}):Play()
					end)
				end
			end
		end)
	end)

	-- Close on B key
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.B and screenGui and screenGui.Enabled then
			BuyMenuController.Hide()
		end
	end)
end

function BuyMenuController.Show(credits: number?)
	if not screenGui then return end
	purchased = {}
	currentCredits = credits or 0
	if creditsLabel then creditsLabel.Text = "CREDITS: " .. tostring(currentCredits) end
	screenGui.Enabled = true
end

function BuyMenuController.Hide()
	if screenGui then screenGui.Enabled = false end
end

function BuyMenuController.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

return BuyMenuController
