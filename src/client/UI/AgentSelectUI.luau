--!strict
--[=[
    Project OVERCLOCK v3: AgentSelectUI (Legendary Edition)

    Pre-round operative select — Valorant-style agent pick:
    - Fullscreen cinematic select with countdown
    - Agent cards + live detail panel (role, kit, passive)
    - Hover / select / locked / banned visual states
    - Teammate pick strip + lock confirm
    - Auto-pick on timeout, server sync via RemoteEvents
    - UITheme integration, CanvasGroup fades, connection cleanup
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local UIFolder = script.Parent
local UITheme = require(UIFolder:WaitForChild("UITheme") :: ModuleScript)
local OperativeStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("OperativeStats") :: ModuleScript)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: ModuleScript)

export type AgentLockPayload = {
	operativeId: string,
	playerId: number?,
	playerName: string?,
	team: string?,
	allLocked: boolean?,
	banned: boolean?,
}

export type TeammatePick = {
	playerId: number,
	playerName: string,
	operativeId: string?,
	locked: boolean,
}

local AgentSelectUI = {}

-- ============================================================================
-- CONFIG
-- ============================================================================

local OPERATIVES = { "Vex", "Warden", "Fray", "Choke", "Pulse", "Bastion" }
local DEFAULT_LOCK_TIME = 30

local ROLE_COLORS: { [string]: Color3 } = {
	Duelist = Color3.fromRGB(255, 90, 90),
	Controller = Color3.fromRGB(160, 100, 255),
	Sentinel = Color3.fromRGB(80, 200, 255),
	Initiator = Color3.fromRGB(255, 190, 70),
	Support = Color3.fromRGB(80, 220, 140),
	Tank = Color3.fromRGB(100, 180, 255),
}

local ABILITY_KEYS = { "C", "Q", "E", "X" }

-- ============================================================================
-- STATE
-- ============================================================================

local isInitialized = false
local screenGui: ScreenGui? = nil
local rootGroup: CanvasGroup? = nil
local mainFrame: Frame? = nil

local selectedOp: string? = nil
local lockedIn = false
local lockedOps: { [string]: boolean } = {}
local bannedOps: { [string]: boolean } = {}
local teammatePicks: { [number]: TeammatePick } = {}

local timerLabel: TextLabel? = nil
local timerRing: Frame? = nil
local phaseLabel: TextLabel? = nil
local lockBtn: TextButton? = nil
local lockBtnLabel: TextLabel? = nil
local detailName: TextLabel? = nil
local detailRole: TextLabel? = nil
local detailDesc: TextLabel? = nil
local detailPassive: TextLabel? = nil
local abilityContainer: Frame? = nil
local teamStrip: Frame? = nil
local statusLabel: TextLabel? = nil

local cardFrames: { [string]: TextButton } = {}
local cardStrokes: { [string]: UIStroke } = {}
local abilityFrames: { Frame } = {}

local timerConn: RBXScriptConnection? = nil
local connections: { RBXScriptConnection } = {}
local activeTweens: { Tween } = {}
local lockTimeTotal = DEFAULT_LOCK_TIME
local lockTimeRemaining = DEFAULT_LOCK_TIME
local timerToken = 0

local C = UITheme.Colors

-- ============================================================================
-- UTILS
-- ============================================================================

local function trackConn(c: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, c)
	return c
end

local function trackTween(t: Tween): Tween
	table.insert(activeTweens, t)
	t.Completed:Once(function()
		local i = table.find(activeTweens, t)
		if i then
			table.remove(activeTweens, i)
		end
	end)
	return t
end

local function cancelTweens()
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
end

local function disconnectRuntime()
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
end

local function disconnectAll()
	disconnectRuntime()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

local function playUi(name: string, vol: number?)
	local s = SoundService:FindFirstChild(name)
	if s and s:IsA("Sound") then
		local cl = s:Clone()
		cl.Volume = vol or s.Volume
		cl.Parent = SoundService
		cl:Play()
		cl.Ended:Once(function()
			cl:Destroy()
		end)
	end
end

local function roleColor(role: string?): Color3
	if role and ROLE_COLORS[role] then
		return ROLE_COLORS[role]
	end
	return C.Accent
end

local function getOpData(opId: string): any?
	local ok, data = pcall(function()
		return OperativeStats.Get(opId)
	end)
	if ok then
		return data
	end
	return nil
end

local function fireSelect(opId: string, locked: boolean?)
	pcall(function()
		RemoteEvents.GetReliable("SelectAgent"):FireServer({
			operativeId = opId,
			locked = locked == true,
		})
	end)
end

-- ============================================================================
-- VISUAL STATE
-- ============================================================================

local function setCardVisual(opId: string)
	local card = cardFrames[opId]
	local stroke = cardStrokes[opId]
	if not card then
		return
	end

	local isBanned = bannedOps[opId] == true
	local isTaken = lockedOps[opId] == true
	local isSelected = selectedOp == opId

	if isBanned then
		card.BackgroundColor3 = Color3.fromRGB(28, 18, 18)
		card.BackgroundTransparency = 0.35
		if stroke then
			stroke.Color = Color3.fromRGB(120, 40, 40)
			stroke.Transparency = 0.2
		end
	elseif isTaken and not isSelected then
		card.BackgroundColor3 = Color3.fromRGB(36, 22, 22)
		card.BackgroundTransparency = 0.4
		if stroke then
			stroke.Color = Color3.fromRGB(140, 50, 50)
			stroke.Transparency = 0.35
		end
	elseif isSelected then
		card.BackgroundColor3 = C.PanelLight or Color3.fromRGB(32, 42, 58)
		card.BackgroundTransparency = 0.05
		if stroke then
			stroke.Color = C.Accent
			stroke.Transparency = 0
			stroke.Thickness = 2.5
		end
	else
		card.BackgroundColor3 = C.Panel
		card.BackgroundTransparency = 0.1
		if stroke then
			stroke.Color = C.Border
			stroke.Transparency = 0.35
			stroke.Thickness = 1.5
		end
	end

	local takenTag = card:FindFirstChild("TakenOverlay") :: Frame?
	if takenTag then
		takenTag.Visible = isTaken or isBanned
		local tl = takenTag:FindFirstChild("Label") :: TextLabel?
		if tl then
			tl.Text = if isBanned then "BANNED" else "LOCKED"
		end
	end
end

local function refreshAllCards()
	for _, opId in OPERATIVES do
		setCardVisual(opId)
	end
end

local function clearAbilityCards()
	for _, f in abilityFrames do
		f:Destroy()
	end
	table.clear(abilityFrames)
end

local function populateAbilities(opId: string)
	if not abilityContainer then
		return
	end
	clearAbilityCards()
	local data = getOpData(opId)
	if not data then
		return
	end

	-- Support several OperativeStats shapes
	local kit: { any } = {}
	if typeof(data.abilities) == "table" then
		kit = data.abilities
	elseif typeof(data.kit) == "table" then
		kit = data.kit
	else
		-- Fallback placeholders from known fields
		local names = {
			data.abilityC or data.util or "Utility",
			data.abilityQ or data.tactical or "Tactical",
			data.abilityE or data.signature or "Signature",
			data.abilityX or data.ultimate or "Ultimate",
		}
		for i, n in names do
			table.insert(kit, {
				key = ABILITY_KEYS[i] or "?",
				name = tostring(n),
				description = "",
			})
		end
	end

	for i, ab in kit do
		if i > 4 then
			break
		end
		local key = tostring(ab.key or ABILITY_KEYS[i] or "?")
		local name = tostring(ab.name or ab.id or "Ability")
		local desc = tostring(ab.description or ab.desc or "")

		local cell = Instance.new("Frame")
		cell.Name = "Ability_" .. key
		cell.Size = UDim2.new(0.24, -6, 1, 0)
		cell.BackgroundColor3 = C.Background or Color3.fromRGB(12, 14, 18)
		cell.BackgroundTransparency = 0.25
		cell.BorderSizePixel = 0
		cell.Parent = abilityContainer
		if UITheme.applyCorner then
			UITheme.applyCorner(cell)
		else
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = cell
		end

		local keyL = Instance.new("TextLabel")
		keyL.Size = UDim2.new(1, 0, 0, 18)
		keyL.Position = UDim2.new(0, 0, 0, 6)
		keyL.BackgroundTransparency = 1
		keyL.Font = Enum.Font.GothamBlack
		keyL.TextSize = 14
		keyL.TextColor3 = if key == "X" then C.AccentGold or Color3.fromRGB(255, 190, 70) else C.Accent
		keyL.Text = key
		keyL.Parent = cell

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(1, -10, 0, 16)
		nameL.Position = UDim2.new(0, 5, 0, 26)
		nameL.BackgroundTransparency = 1
		nameL.Font = Enum.Font.GothamBold
		nameL.TextSize = 12
		nameL.TextColor3 = C.TextPrimary or C.Text or Color3.new(1, 1, 1)
		nameL.Text = string.upper(name)
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.Parent = cell

		local descL = Instance.new("TextLabel")
		descL.Size = UDim2.new(1, -12, 1, -48)
		descL.Position = UDim2.new(0, 6, 0, 46)
		descL.BackgroundTransparency = 1
		descL.Font = Enum.Font.Gotham
		descL.TextSize = 10
		descL.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
		descL.Text = desc
		descL.TextWrapped = true
		descL.TextYAlignment = Enum.TextYAlignment.Top
		descL.TextXAlignment = Enum.TextXAlignment.Left
		descL.Parent = cell

		table.insert(abilityFrames, cell)
	end
end

local function updateDetail(opId: string?)
	if not opId then
		if detailName then
			detailName.Text = "SELECT AN OPERATIVE"
		end
		if detailRole then
			detailRole.Text = ""
		end
		if detailDesc then
			detailDesc.Text = "Choose your operative before the timer expires."
		end
		if detailPassive then
			detailPassive.Text = ""
		end
		clearAbilityCards()
		return
	end

	local data = getOpData(opId)
	local role = data and tostring(data.role or "Operative") or "Operative"
	local desc = data and tostring(data.description or data.bio or "") or ""
	local passive = data and tostring(data.passive or data.passiveDescription or "") or ""

	if detailName then
		detailName.Text = string.upper(opId)
	end
	if detailRole then
		detailRole.Text = string.upper(role)
		detailRole.TextColor3 = roleColor(role)
	end
	if detailDesc then
		detailDesc.Text = desc
	end
	if detailPassive then
		detailPassive.Text = if passive ~= "" then ("PASSIVE  ·  " .. passive) else ""
	end
	populateAbilities(opId)
end

local function updateLockButton()
	if not lockBtn then
		return
	end
	if lockedIn then
		lockBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
		if lockBtnLabel then
			lockBtnLabel.Text = "LOCKED IN"
		else
			lockBtn.Text = "LOCKED IN"
		end
		lockBtn.Active = false
		lockBtn.AutoButtonColor = false
	elseif selectedOp and not lockedOps[selectedOp] and not bannedOps[selectedOp] then
		lockBtn.BackgroundColor3 = C.Accent
		if lockBtnLabel then
			lockBtnLabel.Text = "LOCK IN  ·  " .. string.upper(selectedOp)
		else
			lockBtn.Text = "LOCK IN"
		end
		lockBtn.Active = true
	else
		lockBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
		if lockBtnLabel then
			lockBtnLabel.Text = "SELECT AN OPERATIVE"
		else
			lockBtn.Text = "SELECT AN OPERATIVE"
		end
		lockBtn.Active = false
	end
end

local function rebuildTeamStrip()
	if not teamStrip then
		return
	end
	for _, ch in teamStrip:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end

	local list: { TeammatePick } = {}
	for _, p in teammatePicks do
		table.insert(list, p)
	end
	table.sort(list, function(a, b)
		return a.playerName < b.playerName
	end)

	for i, p in list do
		local cell = Instance.new("Frame")
		cell.Name = "Mate_" .. p.playerId
		cell.Size = UDim2.new(0, if IS_MOBILE then 100 else 130, 1, 0)
		cell.BackgroundColor3 = C.Panel
		cell.BackgroundTransparency = 0.2
		cell.BorderSizePixel = 0
		cell.LayoutOrder = i
		cell.Parent = teamStrip
		if UITheme.applyCorner then
			UITheme.applyCorner(cell)
		end

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -8, 0, 16)
		name.Position = UDim2.new(0, 4, 0, 4)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 11
		name.TextColor3 = if p.playerId == LocalPlayer.UserId then C.Accent else (C.TextPrimary or Color3.new(1, 1, 1))
		name.Text = p.playerName
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = cell

		local op = Instance.new("TextLabel")
		op.Size = UDim2.new(1, -8, 0, 14)
		op.Position = UDim2.new(0, 4, 0, 22)
		op.BackgroundTransparency = 1
		op.Font = Enum.Font.GothamMedium
		op.TextSize = 11
		op.TextColor3 = if p.locked then (C.AccentGold or Color3.fromRGB(255, 190, 70)) else (C.TextSecondary or Color3.fromRGB(140, 150, 165))
		op.Text = if p.operativeId then string.upper(p.operativeId) else "…"
		op.Parent = cell
	end
end

-- ============================================================================
-- SELECTION / LOCK
-- ============================================================================

local function selectOperative(opId: string, silent: boolean?)
	if lockedIn then
		return
	end
	if lockedOps[opId] or bannedOps[opId] then
		return
	end
	selectedOp = opId
	if not silent then
		playUi("UI_Click", 0.35)
	end
	refreshAllCards()
	updateDetail(opId)
	updateLockButton()
	if statusLabel then
		statusLabel.Text = "Selected  " .. string.upper(opId) .. "  —  lock in to confirm"
	end
	-- Soft hover select to server (pre-lock)
	pcall(function()
		RemoteEvents.GetReliable("HoverAgent"):FireServer(opId)
	end)
end

local function lockIn()
	if lockedIn or not selectedOp then
		return
	end
	if lockedOps[selectedOp] or bannedOps[selectedOp] then
		return
	end
	lockedIn = true
	playUi("UI_LockIn", 0.55)
	updateLockButton()
	if statusLabel then
		statusLabel.Text = "LOCKED  ·  " .. string.upper(selectedOp)
		statusLabel.TextColor3 = C.AccentGold or Color3.fromRGB(255, 190, 70)
	end
	-- Pulse lock button
	if lockBtn then
		trackTween(TweenService:Create(lockBtn, TweenInfo.new(0.15), {
			Size = lockBtn.Size + UDim2.new(0, 8, 0, 4),
		})):Play()
		task.delay(0.15, function()
			if lockBtn then
				TweenService:Create(lockBtn, TweenInfo.new(0.2), {
					Size = UDim2.new(if IS_MOBILE then 0.5 else 0.22, 0, 0, 52),
				}):Play()
			end
		end)
	end
	fireSelect(selectedOp, true)
end

local function autoPick()
	if lockedIn then
		return
	end
	local available = {}
	for _, id in OPERATIVES do
		if not lockedOps[id] and not bannedOps[id] then
			table.insert(available, id)
		end
	end
	if not selectedOp or lockedOps[selectedOp] or bannedOps[selectedOp] then
		selectedOp = available[math.random(1, math.max(#available, 1))] or OPERATIVES[1]
	end
	if selectedOp then
		selectOperative(selectedOp, true)
		lockIn()
	end
end

-- ============================================================================
-- TIMER
-- ============================================================================

local function stopTimer()
	disconnectRuntime()
	timerToken += 1
end

local function startTimer(seconds: number)
	stopTimer()
	lockTimeTotal = seconds
	lockTimeRemaining = seconds
	local token = timerToken
	local acc = 0

	if timerLabel then
		timerLabel.Text = tostring(seconds)
		timerLabel.TextColor3 = C.Accent
	end

	timerConn = RunService.Heartbeat:Connect(function(dt)
		if token ~= timerToken then
			return
		end
		acc += dt
		if acc < 1 then
			return
		end
		acc -= 1
		lockTimeRemaining -= 1
		local left = math.max(0, lockTimeRemaining)
		if timerLabel then
			timerLabel.Text = string.format("%02d", left)
			if left <= 5 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
				-- punch
				trackTween(TweenService:Create(timerLabel, TweenInfo.new(0.12), {
					TextSize = 40,
				})):Play()
				task.delay(0.12, function()
					if timerLabel then
						TweenService:Create(timerLabel, TweenInfo.new(0.12), { TextSize = 34 }):Play()
					end
				end)
				playUi("UI_Tick", 0.25)
			elseif left <= 10 then
				timerLabel.TextColor3 = C.AccentGold or Color3.fromRGB(255, 190, 70)
			end
		end
		if left <= 0 then
			stopTimer()
			if not lockedIn then
				autoPick()
			end
		end
	end)
end

-- ============================================================================
-- BUILD UI
-- ============================================================================

local function createCard(opId: string, parent: Instance): TextButton
	local data = getOpData(opId)
	local role = data and tostring(data.role or "") or ""
	local desc = data and tostring(data.description or "") or ""
	local rc = roleColor(role)

	local card = Instance.new("TextButton")
	card.Name = opId
	card.BackgroundColor3 = C.Panel
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.ClipsDescendants = true
	card.Parent = parent
	if UITheme.applyCorner then
		UITheme.applyCorner(card)
	else
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = card
	end
	local stroke = if UITheme.applyStroke
		then UITheme.applyStroke(card, C.Border, 1.5)
		else (function()
			local s = Instance.new("UIStroke")
			s.Color = C.Border
			s.Thickness = 1.5
			s.Parent = card
			return s
		end)()
	cardStrokes[opId] = stroke

	-- Top role accent bar
	local accent = Instance.new("Frame")
	accent.Name = "RoleAccent"
	accent.Size = UDim2.new(1, 0, 0, 4)
	accent.BackgroundColor3 = rc
	accent.BorderSizePixel = 0
	accent.Parent = card

	-- Portrait placeholder block
	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Size = UDim2.new(1, -16, 0.38, 0)
	portrait.Position = UDim2.new(0, 8, 0, 16)
	portrait.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	portrait.BorderSizePixel = 0
	portrait.Parent = card
	if UITheme.applyCorner then
		UITheme.applyCorner(portrait)
	end
	local monogram = Instance.new("TextLabel")
	monogram.Size = UDim2.fromScale(1, 1)
	monogram.BackgroundTransparency = 1
	monogram.Font = Enum.Font.GothamBlack
	monogram.TextSize = if IS_MOBILE then 28 else 36
	monogram.TextColor3 = rc
	monogram.TextTransparency = 0.15
	monogram.Text = string.sub(opId, 1, 1)
	monogram.Parent = portrait

	local nameL = Instance.new("TextLabel")
	nameL.Name = "Name"
	nameL.Size = UDim2.new(1, -12, 0, 22)
	nameL.Position = UDim2.new(0, 6, 0.55, 0)
	nameL.BackgroundTransparency = 1
	nameL.Font = Enum.Font.GothamBlack
	nameL.TextSize = if IS_MOBILE then 14 else 18
	nameL.TextColor3 = C.TextPrimary or Color3.new(1, 1, 1)
	nameL.Text = string.upper(opId)
	nameL.Parent = card

	local roleL = Instance.new("TextLabel")
	roleL.Name = "Role"
	roleL.Size = UDim2.new(1, -12, 0, 16)
	roleL.Position = UDim2.new(0, 6, 0.55, 22)
	roleL.BackgroundTransparency = 1
	roleL.Font = Enum.Font.GothamBold
	roleL.TextSize = 12
	roleL.TextColor3 = rc
	roleL.Text = string.upper(role)
	roleL.Parent = card

	local descL = Instance.new("TextLabel")
	descL.Name = "Desc"
	descL.Size = UDim2.new(1, -14, 0.22, 0)
	descL.Position = UDim2.new(0, 7, 0.72, 0)
	descL.BackgroundTransparency = 1
	descL.Font = Enum.Font.Gotham
	descL.TextSize = 10
	descL.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
	descL.Text = desc
	descL.TextWrapped = true
	descL.TextYAlignment = Enum.TextYAlignment.Top
	descL.Parent = card

	local taken = Instance.new("Frame")
	taken.Name = "TakenOverlay"
	taken.Size = UDim2.fromScale(1, 1)
	taken.BackgroundColor3 = Color3.new(0, 0, 0)
	taken.BackgroundTransparency = 0.45
	taken.Visible = false
	taken.ZIndex = 5
	taken.Parent = card
	local takenL = Instance.new("TextLabel")
	takenL.Name = "Label"
	takenL.Size = UDim2.fromScale(1, 1)
	takenL.BackgroundTransparency = 1
	takenL.Font = Enum.Font.GothamBlack
	takenL.TextSize = 16
	takenL.TextColor3 = Color3.fromRGB(255, 120, 120)
	takenL.Text = "LOCKED"
	takenL.ZIndex = 6
	takenL.Parent = taken

	trackConn(card.MouseEnter:Connect(function()
		if lockedIn or lockedOps[opId] or bannedOps[opId] then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.12), {
			BackgroundColor3 = C.PanelLight or Color3.fromRGB(36, 46, 62),
		}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.12), { Transparency = 0.1 }):Play()
		end
		playUi("UI_Hover", 0.15)
	end))
	trackConn(card.MouseLeave:Connect(function()
		setCardVisual(opId)
	end))
	trackConn(card.MouseButton1Click:Connect(function()
		selectOperative(opId)
	end))

	local lastClick = 0
	trackConn(card.Activated:Connect(function()
		local now = os.clock()
		if selectedOp == opId and (now - lastClick) < 0.35 then
			lockIn()
		end
		lastClick = now
	end))

	cardFrames[opId] = card
	return card
end

function AgentSelectUI.Init(playerGui: PlayerGui)
	if isInitialized then
		AgentSelectUI.Destroy()
	end

	local existing = playerGui:FindFirstChild("AgentSelectGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AgentSelectGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Parent = gui
	rootGroup = root

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromScale(1, 1)
	main.BackgroundColor3 = C.Background
	main.BackgroundTransparency = 0.05
	main.BorderSizePixel = 0
	main.Parent = root
	mainFrame = main

	-- Vignette edges
	local topGrad = Instance.new("Frame")
	topGrad.Size = UDim2.new(1, 0, 0.18, 0)
	topGrad.BackgroundColor3 = Color3.new(0, 0, 0)
	topGrad.BorderSizePixel = 0
	topGrad.Parent = main
	local tg = Instance.new("UIGradient")
	tg.Rotation = 90
	tg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	tg.Parent = topGrad

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 0, 32)
	title.Position = UDim2.new(0.2, 0, 0.03, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = if IS_MOBILE then 22 else 28
	title.TextColor3 = C.TextPrimary or Color3.new(1, 1, 1)
	title.Text = "SELECT YOUR OPERATIVE"
	title.Parent = main

	phaseLabel = Instance.new("TextLabel")
	phaseLabel.Size = UDim2.new(0.4, 0, 0, 16)
	phaseLabel.Position = UDim2.new(0.3, 0, 0.03, 34)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = Enum.Font.GothamMedium
	phaseLabel.TextSize = 12
	phaseLabel.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
	phaseLabel.Text = "AGENT SELECT  ·  LOCK IN BEFORE TIME EXPIRES"
	phaseLabel.Parent = main

	-- Timer
	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(0, 80, 0, 40)
	timerLabel.Position = UDim2.new(0.5, 0, 0.095, 0)
	timerLabel.AnchorPoint = Vector2.new(0.5, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamBlack
	timerLabel.TextSize = 34
	timerLabel.TextColor3 = C.Accent
	timerLabel.Text = "30"
	timerLabel.Parent = main

	-- Team strip
	teamStrip = Instance.new("Frame")
	teamStrip.Name = "TeamStrip"
	teamStrip.Size = UDim2.new(0.7, 0, 0, 48)
	teamStrip.Position = UDim2.new(0.15, 0, 0.145, 0)
	teamStrip.BackgroundTransparency = 1
	teamStrip.Parent = main
	local tsList = Instance.new("UIListLayout")
	tsList.FillDirection = Enum.FillDirection.Horizontal
	tsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tsList.Padding = UDim.new(0, 8)
	tsList.Parent = teamStrip

	-- Card grid
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(0.92, 0, if IS_MOBILE then 0.38 else 0.42, 0)
	grid.Position = UDim2.new(0.04, 0, 0.22, 0)
	grid.BackgroundTransparency = 1
	grid.Parent = main

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = if IS_MOBILE
		then UDim2.new(0.3, -8, 0.48, -8)
		else UDim2.new(0.15, -12, 0.95, 0)
	layout.CellPadding = UDim2.new(0.01, 0, 0.02, 0)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, opId in OPERATIVES do
		local card = createCard(opId, grid)
		card.LayoutOrder = i
	end

	-- Detail panel
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Size = UDim2.new(0.92, 0, if IS_MOBILE then 0.22 else 0.2, 0)
	detail.Position = UDim2.new(0.04, 0, if IS_MOBILE then 0.62 else 0.66, 0)
	detail.BackgroundColor3 = C.Panel
	detail.BackgroundTransparency = 0.15
	detail.BorderSizePixel = 0
	detail.Parent = main
	if UITheme.applyCorner then
		UITheme.applyCorner(detail)
	end
	if UITheme.applyStroke then
		UITheme.applyStroke(detail, C.Border, 1)
	end

	detailName = Instance.new("TextLabel")
	detailName.Size = UDim2.new(0.35, 0, 0, 28)
	detailName.Position = UDim2.new(0, 18, 0, 12)
	detailName.BackgroundTransparency = 1
	detailName.Font = Enum.Font.GothamBlack
	detailName.TextSize = 22
	detailName.TextColor3 = C.TextPrimary or Color3.new(1, 1, 1)
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.Text = "SELECT AN OPERATIVE"
	detailName.Parent = detail

	detailRole = Instance.new("TextLabel")
	detailRole.Size = UDim2.new(0.3, 0, 0, 18)
	detailRole.Position = UDim2.new(0, 18, 0, 40)
	detailRole.BackgroundTransparency = 1
	detailRole.Font = Enum.Font.GothamBold
	detailRole.TextSize = 13
	detailRole.TextColor3 = C.Accent
	detailRole.TextXAlignment = Enum.TextXAlignment.Left
	detailRole.Text = ""
	detailRole.Parent = detail

	detailDesc = Instance.new("TextLabel")
	detailDesc.Size = UDim2.new(0.36, 0, 0.45, 0)
	detailDesc.Position = UDim2.new(0, 18, 0, 62)
	detailDesc.BackgroundTransparency = 1
	detailDesc.Font = Enum.Font.Gotham
	detailDesc.TextSize = 12
	detailDesc.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
	detailDesc.TextXAlignment = Enum.TextXAlignment.Left
	detailDesc.TextYAlignment = Enum.TextYAlignment.Top
	detailDesc.TextWrapped = true
	detailDesc.Text = "Choose your operative before the timer expires."
	detailDesc.Parent = detail

	detailPassive = Instance.new("TextLabel")
	detailPassive.Size = UDim2.new(0.36, 0, 0, 16)
	detailPassive.Position = UDim2.new(0, 18, 1, -24)
	detailPassive.BackgroundTransparency = 1
	detailPassive.Font = Enum.Font.GothamMedium
	detailPassive.TextSize = 11
	detailPassive.TextColor3 = C.AccentGold or Color3.fromRGB(255, 190, 70)
	detailPassive.TextXAlignment = Enum.TextXAlignment.Left
	detailPassive.Text = ""
	detailPassive.Parent = detail

	abilityContainer = Instance.new("Frame")
	abilityContainer.Name = "Abilities"
	abilityContainer.Size = UDim2.new(0.42, 0, 0, 10)
	abilityContainer.Position = UDim2.new(0.42, 0, 0, 10)
	abilityContainer.BackgroundTransparency = 1
	abilityContainer.Parent = detail
	local abList = Instance.new("UIListLayout")
	abList.FillDirection = Enum.FillDirection.Horizontal
	abList.Padding = UDim.new(0, 8)
	abList.Parent = abilityContainer

	-- Lock button
	lockBtn = Instance.new("TextButton")
	lockBtn.Name = "LockIn"
	lockBtn.Size = UDim2.new(if IS_MOBILE then 0.5 else 0.22, 0, 0, 52)
	lockBtn.Position = UDim2.new(0.5, 0, if IS_MOBILE then 0.9 else 0.9, 0)
	lockBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	lockBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
	lockBtn.Text = ""
	lockBtn.AutoButtonColor = false
	lockBtn.Parent = main
	if UITheme.applyCorner then
		UITheme.applyCorner(lockBtn)
	else
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = lockBtn
	end
	if UITheme.applyStroke then
		UITheme.applyStroke(lockBtn, C.Accent, 2)
	end

	lockBtnLabel = Instance.new("TextLabel")
	lockBtnLabel.Size = UDim2.fromScale(1, 1)
	lockBtnLabel.BackgroundTransparency = 1
	lockBtnLabel.Font = Enum.Font.GothamBlack
	lockBtnLabel.TextSize = 18
	lockBtnLabel.TextColor3 = Color3.fromRGB(10, 14, 20)
	lockBtnLabel.Text = "SELECT AN OPERATIVE"
	lockBtnLabel.Parent = lockBtn

	trackConn(lockBtn.MouseButton1Click:Connect(function()
		if lockBtn and lockBtn.Active then
			lockIn()
		end
	end))

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(0.5, 0, 0, 18)
	statusLabel.Position = UDim2.new(0.25, 0, 0.955, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
	statusLabel.Text = "Double-click an operative to quick lock"
	statusLabel.Parent = main

	-- Keyboard: 1-6 select, Enter lock
	trackConn(UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not AgentSelectUI.IsVisible() or lockedIn then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
			lockIn()
			return
		end
		local map = {
			[Enum.KeyCode.One] = 1,
			[Enum.KeyCode.Two] = 2,
			[Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5,
			[Enum.KeyCode.Six] = 6,
		}
		local idx = map[input.KeyCode]
		if idx and OPERATIVES[idx] then
			selectOperative(OPERATIVES[idx])
		end
	end))

	-- Server events
	pcall(function()
		trackConn(RemoteEvents.GetReliable("AgentLocked").OnClientEvent:Connect(function(data: any)
			AgentSelectUI.ApplyLockUpdate(data)
		end))
	end)
	pcall(function()
		trackConn(RemoteEvents.GetReliable("AgentSelectState").OnClientEvent:Connect(function(data: any)
			if typeof(data) ~= "table" then
				return
			end
			if typeof(data.banned) == "table" then
				table.clear(bannedOps)
				for _, id in data.banned do
					bannedOps[tostring(id)] = true
				end
			end
			if typeof(data.locked) == "table" then
				table.clear(lockedOps)
				for _, id in data.locked do
					lockedOps[tostring(id)] = true
				end
			end
			if typeof(data.teammates) == "table" then
				table.clear(teammatePicks)
				for _, t in data.teammates do
					if typeof(t) == "table" and t.playerId then
						teammatePicks[t.playerId] = {
							playerId = t.playerId,
							playerName = tostring(t.playerName or "Player"),
							operativeId = t.operativeId,
							locked = t.locked == true,
						}
					end
				end
				rebuildTeamStrip()
			end
			if typeof(data.timeLeft) == "number" then
				lockTimeRemaining = data.timeLeft
				if timerLabel then
					timerLabel.Text = string.format("%02d", math.max(0, data.timeLeft))
				end
			end
			refreshAllCards()
			updateLockButton()
		end))
	end)

	isInitialized = true
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function AgentSelectUI.ApplyLockUpdate(data: any)
	if typeof(data) ~= "table" then
		-- plain string operative id
		if typeof(data) == "string" then
			lockedOps[data] = true
			refreshAllCards()
		end
		return
	end

	local opId = data.operativeId or data.agentId or data.id
	if typeof(opId) == "string" then
		if data.banned then
			bannedOps[opId] = true
		else
			lockedOps[opId] = true
		end
	end

	if data.playerId and data.playerName then
		teammatePicks[data.playerId] = {
			playerId = data.playerId,
			playerName = tostring(data.playerName),
			operativeId = typeof(opId) == "string" and opId or nil,
			locked = true,
		}
		rebuildTeamStrip()
	end

	-- If our pick was stolen
	if selectedOp and lockedOps[selectedOp] and not lockedIn then
		if statusLabel then
			statusLabel.Text = string.upper(selectedOp) .. " was taken — pick another"
			statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		end
		selectedOp = nil
		updateDetail(nil)
	end

	refreshAllCards()
	updateLockButton()

	if data.allLocked then
		task.delay(0.6, function()
			AgentSelectUI.Hide()
		end)
	end
end

function AgentSelectUI.Show(mode: string?, playersInfo: any?, duration: number?)
	if not isInitialized or not screenGui or not rootGroup then
		return
	end

	selectedOp = nil
	lockedIn = false
	table.clear(lockedOps)
	table.clear(bannedOps)
	table.clear(teammatePicks)

	-- Seed local player into strip
	teammatePicks[LocalPlayer.UserId] = {
		playerId = LocalPlayer.UserId,
		playerName = LocalPlayer.DisplayName,
		operativeId = nil,
		locked = false,
	}
	if typeof(playersInfo) == "table" then
		for _, p in playersInfo do
			if typeof(p) == "table" and p.playerId then
				teammatePicks[p.playerId] = {
					playerId = p.playerId,
					playerName = tostring(p.playerName or "Player"),
					operativeId = p.operativeId,
					locked = p.locked == true,
				}
			end
		end
	end

	if phaseLabel then
		phaseLabel.Text = string.upper(tostring(mode or "RANKED")) .. "  ·  AGENT SELECT"
	end
	if statusLabel then
		statusLabel.Text = "Double-click an operative to quick lock  ·  Keys 1-6  ·  Enter"
		statusLabel.TextColor3 = C.TextSecondary or Color3.fromRGB(140, 150, 165)
	end

	refreshAllCards()
	updateDetail(nil)
	updateLockButton()
	rebuildTeamStrip()

	screenGui.Enabled = true
	rootGroup.GroupTransparency = 1
	trackTween(TweenService:Create(rootGroup, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	})):Play()

	startTimer(duration or DEFAULT_LOCK_TIME)
	playUi("UI_AgentSelectOpen", 0.4)
end

function AgentSelectUI.Hide()
	stopTimer()
	if rootGroup and screenGui and screenGui.Enabled then
		local tw = TweenService:Create(rootGroup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		trackTween(tw)
		tw:Play()
		tw.Completed:Once(function()
			if screenGui then
				screenGui.Enabled = false
			end
		end)
	elseif screenGui then
		screenGui.Enabled = false
	end
end

function AgentSelectUI.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

function AgentSelectUI.GetSelected(): string?
	return selectedOp
end

function AgentSelectUI.IsLockedIn(): boolean
	return lockedIn
end

function AgentSelectUI.Destroy()
	stopTimer()
	cancelTweens()
	disconnectAll()
	clearAbilityCards()
	if screenGui then
		screenGui:Destroy()
	end
	screenGui, rootGroup, mainFrame = nil, nil, nil
	timerLabel, lockBtn, lockBtnLabel = nil, nil, nil
	detailName, detailRole, detailDesc, detailPassive = nil, nil, nil, nil
	abilityContainer, teamStrip, statusLabel, phaseLabel = nil, nil, nil, nil
	table.clear(cardFrames)
	table.clear(cardStrokes)
	table.clear(lockedOps)
	table.clear(bannedOps)
	table.clear(teammatePicks)
	isInitialized = false
end

return AgentSelectUI
