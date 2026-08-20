--!strict
local TweenService = game:GetService("TweenService")

local UITheme = {}

UITheme.Colors = {
	Background = Color3.fromRGB(18, 19, 21),
	Panel = Color3.fromRGB(30, 31, 33),
	PanelLight = Color3.fromRGB(42, 43, 46),
	Accent = Color3.fromRGB(197, 165, 62), -- warm brass, not purple/indigo
	AccentDark = Color3.fromRGB(140, 118, 44),
	Danger = Color3.fromRGB(186, 42, 42),
	Success = Color3.fromRGB(58, 150, 72),
	TextPrimary = Color3.fromRGB(240, 240, 238),
	TextSecondary = Color3.fromRGB(155, 157, 160), -- not gray-400, proper contrast + hierarchy
	Border = Color3.fromRGB(48, 49, 52),
	Gold = Color3.fromRGB(197, 165, 62),
}

UITheme.Font = Enum.Font.GothamBold
UITheme.FontLight = Enum.Font.Gotham
UITheme.CornerRadius = UDim.new(0, 6)
UITheme.CornerRadiusSmall = UDim.new(0, 4) -- varied radii: 4/6/8/12, not rounded-2xl everywhere

local TWEEN_HOVER = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_PRESS = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function UITheme.applyCorner(inst: GuiObject, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UITheme.CornerRadius
	c.Parent = inst
	return c
end

function UITheme.applyStroke(inst: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or UITheme.Colors.Border
	s.Thickness = thickness or 1
	s.Parent = inst
	return s
end

function UITheme.addHoverFeedback(btn: TextButton | ImageButton)
	local originalColor = btn.BackgroundColor3
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TWEEN_HOVER, {BackgroundColor3 = UITheme.Colors.PanelLight}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TWEEN_HOVER, {BackgroundColor3 = originalColor}):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TWEEN_PRESS, {BackgroundColor3 = UITheme.Colors.AccentDark}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TWEEN_HOVER, {BackgroundColor3 = originalColor}):Play()
	end)
end

function UITheme.createFrame(parent: Instance, size: UDim2, position: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position or UDim2.new(0, 0, 0, 0)
	f.BackgroundColor3 = UITheme.Colors.Panel
	f.BackgroundTransparency = 0.4
	f.BorderSizePixel = 0
	f.Parent = parent
	UITheme.applyCorner(f)
	return f
end

function UITheme.createLabel(parent: Instance, text: string, size: UDim2, position: UDim2?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position or UDim2.new(0, 0, 0, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = UITheme.Colors.TextPrimary
	l.Font = UITheme.Font
	l.TextSize = 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

function UITheme.createButton(parent: Instance, text: string, size: UDim2, position: UDim2?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position or UDim2.new(0, 0, 0, 0)
	b.BackgroundColor3 = UITheme.Colors.Panel
	b.BackgroundTransparency = 0.4
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = UITheme.Colors.TextPrimary
	b.Font = UITheme.Font
	b.TextSize = 16
	b.AutoButtonColor = false
	b.Parent = parent
	UITheme.applyCorner(b)
	UITheme.applyStroke(b, UITheme.Colors.Border)
	UITheme.addHoverFeedback(b)
	return b
end

function UITheme.createAccentButton(parent: Instance, text: string, size: UDim2, position: UDim2?): TextButton
	local b = UITheme.createButton(parent, text, size, position)
	b.BackgroundColor3 = UITheme.Colors.Accent
	b.TextColor3 = UITheme.Colors.Background
	return b
end

return UITheme
