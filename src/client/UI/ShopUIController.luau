--!strict
--[=[ OVERCLOCK: Shop UI Controller (Cosmetics Premium Overhaul) ]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UIFolder = script.Parent
local UITheme = require(UIFolder:WaitForChild("UITheme") :: any)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)
local ControllersFolder = script.Parent.Parent:WaitForChild("Controllers")
local PremiumWeaponPresentation = require(ControllersFolder:WaitForChild("PremiumWeaponPresentation") :: any)
local PremiumWeaponCatalog = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("PremiumWeaponCatalog") :: any)

local ShopUIController = {}
local screenGui: ScreenGui? = nil
local panelFrame: Frame? = nil
local equipped: string = "ObsidianVector"
local currentWeaponForSkin: string = "AssaultRifle"

-- Active Viewport rotations
local renderConnections: {RBXScriptConnection} = {}


local function requestSkin(skinId: string)
	local remote = RemoteEvents.GetReliable("WeaponSkinRequest")
	PremiumWeaponPresentation.RequestSkin(remote, currentWeaponForSkin, skinId)
	equipped = skinId
end

local function create3DPreview(weaponId: string, skinId: string): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0

	-- Build premium viewmodel and clone for viewport isolation (real geometry)
	local model = PremiumWeaponPresentation.BuildViewmodel(weaponId, skinId)
	local previewModel = model:Clone()
	previewModel.Parent = viewport
	model:Destroy()

	-- Optional WorldModel for proper viewport rendering
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel

	local cam = Instance.new("Camera")
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.new(Vector3.new(3, 2, 4), Vector3.new(0, 0.2, 0))
	cam.FieldOfView = 50
	viewport.CurrentCamera = cam
	cam.Parent = viewport

	-- Animate rotation via cloned model pivot
	local angle = 0
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt)
		if not viewport.Parent or not viewport.Visible then return end
		if not previewModel.Parent then return end
		angle += dt * 0.5
		previewModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, angle, 0.2))
	end)
	table.insert(renderConnections, conn)

	return viewport
end

function ShopUIController.Destroy()
	for _, conn in renderConnections do
		conn:Disconnect()
	end
	table.clear(renderConnections)
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	panelFrame = nil
end

function ShopUIController.Init(playerGui: PlayerGui)
	if screenGui then
		ShopUIController.Destroy()
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Premium Glassmorphism Background
	local panel = Instance.new("CanvasGroup")
	panel.Name = "ShopPanel"
	panel.Size = UDim2.new(0.8, 0, 0.8, 0)
	panel.Position = UDim2.new(0.1, 0, 0.1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	
	UITheme.applyCorner(panel, UDim.new(0, 16))
	local panelStroke = UITheme.applyStroke(panel, Color3.fromRGB(0, 220, 255), 2)
	panelStroke.Transparency = 0.5
	panelFrame = panel

	-- Top Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.Parent = panel
	
	local title = UITheme.createLabel(header, "EXCLUSIVE GEAR", UDim2.new(0.4, 0, 1, 0), UDim2.new(0.03, 0, 0, 0))
	title.TextSize = 28
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	
	local subtitle = UITheme.createLabel(header, "Customize your operative with high-end cosmetics.", UDim2.new(0.4, 0, 1, 0), UDim2.new(0.03, 0, 0, 20))
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(150, 160, 180)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left

	-- Close button
	local closeBtn = UITheme.createButton(header, "✕", UDim2.new(0, 40, 0, 40), UDim2.new(1, -50, 0.5, -20))
	closeBtn.TextSize = 20
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 70)
	closeBtn.BackgroundTransparency = 0.8
	closeBtn.MouseButton1Click:Connect(function() ShopUIController.Hide() end)
	
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.new(0, 0, 1, 0)
	divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider.BackgroundTransparency = 0.8
	divider.Parent = header

	-- Horizontal Scroll Carousel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -40, 1, -100)
	scroll.Position = UDim2.new(0, 20, 0, 80)
	scroll.BackgroundTransparency = 1
	scroll.CanvasSize = UDim2.new(2, 0, 0, 0)
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 20)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local cardStrokes: {[string]: UIStroke} = {}
	local equipButtons: {[string]: TextButton} = {}

	for _, skinId in ipairs(PremiumWeaponCatalog.GetSkinOrder()) do
		local skinSpec = PremiumWeaponCatalog.GetSkin(skinId)
		if not skinSpec then continue end
		local card = Instance.new("Frame")
		card.Name = skinId
		card.Size = UDim2.new(0, 280, 1, -20)
		card.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
		card.BackgroundTransparency = 0.3
		card.BorderSizePixel = 0
		card.Parent = scroll
		UITheme.applyCorner(card, UDim.new(0, 12))
		local stroke = UITheme.applyStroke(card, if skinId == equipped then UITheme.Colors.Accent else Color3.fromRGB(40, 45, 60), 2)
		cardStrokes[skinId] = stroke
		
		-- 3D Viewport Frame with real cloned model
		local viewport = create3DPreview(currentWeaponForSkin, skinId)
		viewport.Size = UDim2.new(1, 0, 0.6, 0)
		viewport.Position = UDim2.new(0, 0, 0, 0)
		viewport.Parent = card
		
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150,150,150))
		})
		gradient.Rotation = 90
		gradient.Parent = card

		local infoFrame = Instance.new("Frame")
		infoFrame.Size = UDim2.new(1, 0, 0.4, 0)
		infoFrame.Position = UDim2.new(0, 0, 0.6, 0)
		infoFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
		infoFrame.BorderSizePixel = 0
		infoFrame.Parent = card
		UITheme.applyCorner(infoFrame, UDim.new(0, 12))
		
		-- Fix bottom corner overlap hack
		local fixFrame = Instance.new("Frame")
		fixFrame.Size = UDim2.new(1, 0, 0.2, 0)
		fixFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
		fixFrame.BorderSizePixel = 0
		fixFrame.Parent = infoFrame

		local nameL = UITheme.createLabel(infoFrame, string.upper(skinSpec.displayName), UDim2.new(1, -30, 0, 30), UDim2.new(0, 15, 0, 15))
		nameL.TextSize = 20
		nameL.Font = Enum.Font.GothamBold
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.TextColor3 = skinSpec.primaryColor
		
		local rarityText = string.upper(skinSpec.rarity)
		local rarityL = UITheme.createLabel(infoFrame, rarityText, UDim2.new(1, -30, 0, 15), UDim2.new(0, 15, 0, 45))
		rarityL.TextSize = 12
		rarityL.TextColor3 = if skinSpec.rarity == "Legendary" then Color3.fromRGB(255, 184, 46) else Color3.fromRGB(122, 92, 255)
		rarityL.TextXAlignment = Enum.TextXAlignment.Left

		local equipBtn = UITheme.createAccentButton(infoFrame, if skinId == equipped then "EQUIPPED" else "PURCHASE / EQUIP", UDim2.new(1, -30, 0, 45), UDim2.new(0, 15, 1, -60))
		equipBtn.TextSize = 16
		equipBtn.Font = Enum.Font.GothamBold
		equipButtons[skinId] = equipBtn

		equipBtn.MouseButton1Click:Connect(function()
			requestSkin(skinId)
			for id, s in cardStrokes do
				s.Color = if id == skinId then UITheme.Colors.Accent else Color3.fromRGB(40, 45, 60)
			end
			for id, btn in equipButtons do
				btn.Text = if id == skinId then "EQUIPPED" else "PURCHASE / EQUIP"
				btn.BackgroundColor3 = if id == skinId then UITheme.Colors.Success else UITheme.Colors.Accent
			end
		end)
	end
end

function ShopUIController.Show()
	if screenGui then
		screenGui.Enabled = true
		if panelFrame then
			panelFrame.Position = UDim2.new(0.1, 0, 0.2, 0)
			panelFrame.GroupTransparency = 1
			TweenService:Create(panelFrame, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.1, 0, 0.1, 0),
				GroupTransparency = 0
			}):Play()
		end
	end
end

function ShopUIController.Hide()
	if screenGui and panelFrame then
		local tween = TweenService:Create(panelFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.1, 0, 0.15, 0),
			GroupTransparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			screenGui.Enabled = false
		end)
	end
end

function ShopUIController.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

return ShopUIController
