--!strict
--[=[
    Project OVERCLOCK v3: HUDController (Behemoth Edition)

    Production FPS HUD state machine — Lobby | Match | Spectate
    Architecture:
      • 3 isolated ScreenGuis (MainHUD / MenuUI / DynamicUI) for render isolation [web:61]
      • Transient CanvasGroup only during fades — zero persistent CG cost [web:65]
      • ObjectPool for hitmarkers, damage numbers, directional dmg, killfeed
      • THEME-aligned with LobbyUIController tactical aesthetic
      • Dual HP + Shield bars (Valorant-style mitigation readout) [web:64]
      • Low-ammo pulse, ability slots, match clock, streak toast
      • Screen flash / vignette / suppress overlays
      • Full connection + tween cleanup, cached sibling requires
]=]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- 4 weapons matching WeaponStats (Pistol, AssaultRifle, SniperRifle, Shotgun) — keep HUD in sync with WeaponStats registry
local HUD_WEAPONS = { "Pistol", "AssaultRifle", "SniperRifle", "Shotgun" }

-- ObjectPool (graceful fallback if Utils missing during solo tests)
local ObjectPool: any = nil
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("ObjectPool") :: ModuleScript)
	end)
	if ok then
		ObjectPool = mod
	end
end

export type ContainerType = "MainHUD" | "MenuUI" | "DynamicUI"
export type HUDMode = "Lobby" | "Match" | "Spectate"

export type AbilitySlotData = {
	id: string,
	name: string,
	key: string,
	charges: number,
	maxCharges: number,
	cooldownRemaining: number?,
	cooldownTotal: number?,
	ready: boolean?,
}

export type ScoreboardData = {
	redScore: number,
	blueScore: number,
	roundText: string?,
	timerSeconds: number?,
	phase: string?, -- "Buy" | "Combat" | "Spike" | "End"
}

local HUDController = {}

-- ============================================================================
-- THEME (matches Lobby hybrid)
-- ============================================================================

local THEME = {
	Colors = {
		Bg = Color3.fromRGB(12, 14, 18),
		Panel = Color3.fromRGB(18, 22, 28),
		PanelSoft = Color3.fromRGB(24, 28, 36),
		Accent = Color3.fromRGB(0, 210, 255),
		AccentGold = Color3.fromRGB(255, 190, 70),
		Hp = Color3.fromRGB(46, 204, 113),
		HpLow = Color3.fromRGB(231, 76, 60),
		HpWarn = Color3.fromRGB(241, 196, 15),
		Shield = Color3.fromRGB(80, 170, 255),
		Text = Color3.fromRGB(240, 245, 250),
		TextDim = Color3.fromRGB(140, 150, 165),
		Red = Color3.fromRGB(255, 70, 70),
		Blue = Color3.fromRGB(70, 160, 255),
		Kill = Color3.fromRGB(255, 45, 45),
		Headshot = Color3.fromRGB(255, 210, 60),
		Border = Color3.fromRGB(35, 42, 55),
	},
	Fonts = {
		Heavy = Enum.Font.GothamBlack,
		Bold = Enum.Font.GothamBold,
		Med = Enum.Font.GothamMedium,
		Body = Enum.Font.Gotham,
	},
	Tween = {
		Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Med = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		Slow = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		Pulse = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		Bar = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
	Layout = {
		HealthW = if IS_MOBILE then 0.42 else 280,
		AmmoW = if IS_MOBILE then 0.36 else 240,
		KillfeedMax = 6,
		KillfeedLife = 4.2,
	},
}

-- ============================================================================
-- STATE
-- ============================================================================

local _playerGui: PlayerGui? = nil
local _initialized = false
local containers: { [ContainerType]: ScreenGui } = {} :: any
local currentHUDMode: HUDMode = "Lobby"

-- MainHUD refs
local rootMain: Frame? = nil
local healthFill: Frame? = nil
local shieldFill: Frame? = nil
local healthText: TextLabel? = nil
local shieldText: TextLabel? = nil
local healthGlow: UIStroke? = nil

local ammoMag: TextLabel? = nil
local ammoReserve: TextLabel? = nil
local weaponName: TextLabel? = nil
local ammoContainer: Frame? = nil
local lowAmmoPulse: Tween? = nil

local compassLabel: TextLabel? = nil
local compassStrip: Frame? = nil

local scoreRed: TextLabel? = nil
local scoreBlue: TextLabel? = nil
local scoreSep: TextLabel? = nil
local roundLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local phaseLabel: TextLabel? = nil

local abilityBar: Frame? = nil
local abilitySlots: { [string]: Frame } = {}

local objectiveLabel: TextLabel? = nil
local streakLabel: TextLabel? = nil
local spectateLabel: TextLabel? = nil

local killfeedList: Frame? = nil

-- MenuUI
local menuRoot: CanvasGroup? = nil
local menus: { [string]: Frame } = {}
local activeMenuName: string? = nil

-- Dynamic overlays
local hitmarkerRoot: Frame? = nil
local vignette: ImageLabel? = nil
local flashFrame: Frame? = nil
local suppressFrame: Frame? = nil
local scopeFrame: Frame? = nil

-- Pools
local hitmarkerPool: any = nil
local damageTextPool: any = nil
local directionalPool: any = nil
local killfeedPool: any = nil

-- Runtime
local activeFades: { [GuiObject]: CanvasGroup } = {}
local connections: { RBXScriptConnection } = {}
local activeTweens: { Tween } = {}
local killfeedOrder = 0
local lastHealthRatio = 1
local matchClockConn: RBXScriptConnection? = nil
local matchTimerEnd: number? = nil

-- Cached modules
local _lobbyUI: any? = nil
local _crosshair: any? = nil
local _modulesTried = false

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
	if lowAmmoPulse then
		lowAmmoPulse:Cancel()
		lowAmmoPulse = nil
	end
end

local function disconnectAll()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if matchClockConn then
		matchClockConn:Disconnect()
		matchClockConn = nil
	end
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end

local function stroke(p: Instance, col: Color3, th: number, tr: number?)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = th
	s.Transparency = tr or 0
	s.Parent = p
	return s
end

local function pad(p: Instance, t: number, b: number, l: number, r: number)
	local u = Instance.new("UIPadding")
	u.PaddingTop, u.PaddingBottom = UDim.new(0, t), UDim.new(0, b)
	u.PaddingLeft, u.PaddingRight = UDim.new(0, l), UDim.new(0, r)
	u.Parent = p
	return u
end

local function playSound(name: string, vol: number?)
	local s = SoundService:FindFirstChild(name)
	if s and s:IsA("Sound") then
		local c = s:Clone()
		c.Volume = vol or s.Volume
		c.Parent = SoundService
		c:Play()
		c.Ended:Once(function()
			c:Destroy()
		end)
	end
end

local function tryRequire(pathParts: { string }): any?
	local node: Instance? = script
	for _, part in pathParts do
		if not node then
			return nil
		end
		node = node:FindFirstChild(part) or (node.Parent and node.Parent:FindFirstChild(part))
	end
	-- explicit relative attempts
	return nil
end

local function resolveModules()
	if _modulesTried then
		return
	end
	_modulesTried = true

	-- LobbyUIController sibling
	local lobbyChild = script.Parent and script.Parent:FindFirstChild("LobbyUIController")
	if lobbyChild and lobbyChild:IsA("ModuleScript") then
		local ok, mod = pcall(require, lobbyChild)
		if ok then
			_lobbyUI = mod
		end
	end

	-- CrosshairController often under Controllers/
	local parent = script.Parent
	local grand = parent and parent.Parent
	local controllers = grand and grand:FindFirstChild("Controllers")
	local cross = controllers and controllers:FindFirstChild("CrosshairController")
	if cross and cross:IsA("ModuleScript") then
		local ok, mod = pcall(require, cross)
		if ok then
			_crosshair = mod
		end
	end
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function hpColor(ratio: number): Color3
	if ratio > 0.5 then
		return lerpColor(THEME.Colors.HpWarn, THEME.Colors.Hp, (ratio - 0.5) * 2)
	end
	return lerpColor(THEME.Colors.HpLow, THEME.Colors.HpWarn, ratio * 2)
end

-- Minimal pool if ObjectPool module absent
local function makeSimplePool(factory: () -> Instance, size: number, container: Instance, reset: (Instance) -> ())
	local free: { Instance } = {}
	for _ = 1, size do
		local inst = factory()
		inst.Parent = container
		reset(inst)
		table.insert(free, inst)
	end
	return {
		Get = function(_self: any): Instance
			local inst = table.remove(free)
			if not inst then
				inst = factory()
				inst.Parent = container
			end
			return inst
		end,
		Return = function(_self: any, inst: Instance)
			reset(inst)
			inst.Parent = container
			table.insert(free, inst)
		end,
	}
end

-- ============================================================================
-- BUILDERS — MainHUD
-- ============================================================================

local function buildBarBlock(
	name: string,
	parent: Instance,
	size: UDim2,
	pos: UDim2,
	anchor: Vector2
): (Frame, Frame, TextLabel)
	local box = Instance.new("Frame")
	box.Name = name
	box.Size = size
	box.Position = pos
	box.AnchorPoint = anchor
	box.BackgroundColor3 = THEME.Colors.Bg
	box.BackgroundTransparency = 0.22
	box.BorderSizePixel = 0
	box.Parent = parent
	corner(box, 8)
	stroke(box, THEME.Colors.Border, 1.2, 0.35)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -12, 0, 10)
	track.Position = UDim2.new(0, 6, 1, -14)
	track.BackgroundColor3 = THEME.Colors.PanelSoft
	track.BorderSizePixel = 0
	track.Parent = box
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = THEME.Colors.Hp
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.Size = UDim2.new(1, -16, 0, 22)
	label.Position = UDim2.new(0, 10, 0, 6)
	label.BackgroundTransparency = 1
	label.Font = THEME.Fonts.Bold
	label.TextSize = if IS_MOBILE then 16 else 18
	label.TextColor3 = THEME.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "100"
	label.Parent = box

	return box, fill, label
end

local function createMainHUD(gui: ScreenGui)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	rootMain = root

	-- ---- HEALTH + SHIELD (bottom-left) ----
	local vitals = Instance.new("Frame")
	vitals.Name = "Vitals"
	vitals.Size = if IS_MOBILE then UDim2.new(0.46, 0, 0, 72) else UDim2.new(0, 300, 0, 72)
	vitals.Position = UDim2.new(0.02, 0, 0.96, 0)
	vitals.AnchorPoint = Vector2.new(0, 1)
	vitals.BackgroundColor3 = THEME.Colors.Bg
	vitals.BackgroundTransparency = 0.55
	vitals.BorderSizePixel = 0
	vitals.Parent = root
	corner(vitals, 10)
	local vg = stroke(vitals, THEME.Colors.Border, 1.4, 0.3)
	healthGlow = vg

	local hpTitle = Instance.new("TextLabel")
	hpTitle.Size = UDim2.new(0.5, 0, 0, 14)
	hpTitle.Position = UDim2.new(0, 12, 0, 8)
	hpTitle.BackgroundTransparency = 1
	hpTitle.Font = THEME.Fonts.Med
	hpTitle.TextSize = 11
	hpTitle.TextColor3 = THEME.Colors.TextDim
	hpTitle.TextXAlignment = Enum.TextXAlignment.Left
	hpTitle.Text = "HEALTH"
	hpTitle.Parent = vitals

	local shTitle = Instance.new("TextLabel")
	shTitle.Size = UDim2.new(0.45, 0, 0, 14)
	shTitle.Position = UDim2.new(0.52, 0, 0, 8)
	shTitle.BackgroundTransparency = 1
	shTitle.Font = THEME.Fonts.Med
	shTitle.TextSize = 11
	shTitle.TextColor3 = THEME.Colors.TextDim
	shTitle.TextXAlignment = Enum.TextXAlignment.Left
	shTitle.Text = "SHIELD"
	shTitle.Parent = vitals

	healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Size = UDim2.new(0.45, 0, 0, 22)
	healthText.Position = UDim2.new(0, 12, 0, 22)
	healthText.BackgroundTransparency = 1
	healthText.Font = THEME.Fonts.Heavy
	healthText.TextSize = 20
	healthText.TextColor3 = THEME.Colors.Text
	healthText.TextXAlignment = Enum.TextXAlignment.Left
	healthText.Text = "100"
	healthText.Parent = vitals

	shieldText = Instance.new("TextLabel")
	shieldText.Name = "ShieldText"
	shieldText.Size = UDim2.new(0.45, 0, 0, 22)
	shieldText.Position = UDim2.new(0.52, 0, 0, 22)
	shieldText.BackgroundTransparency = 1
	shieldText.Font = THEME.Fonts.Heavy
	shieldText.TextSize = 20
	shieldText.TextColor3 = THEME.Colors.Shield
	shieldText.TextXAlignment = Enum.TextXAlignment.Left
	shieldText.Text = "50"
	shieldText.Parent = vitals

	local hpTrack = Instance.new("Frame")
	hpTrack.Name = "HpTrack"
	hpTrack.Size = UDim2.new(1, -24, 0, 8)
	hpTrack.Position = UDim2.new(0, 12, 1, -28)
	hpTrack.BackgroundColor3 = THEME.Colors.PanelSoft
	hpTrack.BorderSizePixel = 0
	hpTrack.Parent = vitals
	corner(hpTrack, 3)

	healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = THEME.Colors.Hp
	healthFill.BorderSizePixel = 0
	healthFill.Parent = hpTrack
	corner(healthFill, 3)

	local shTrack = Instance.new("Frame")
	shTrack.Name = "ShieldTrack"
	shTrack.Size = UDim2.new(1, -24, 0, 5)
	shTrack.Position = UDim2.new(0, 12, 1, -14)
	shTrack.BackgroundColor3 = THEME.Colors.PanelSoft
	shTrack.BorderSizePixel = 0
	shTrack.Parent = vitals
	corner(shTrack, 2)

	shieldFill = Instance.new("Frame")
	shieldFill.Name = "ShieldFill"
	shieldFill.Size = UDim2.fromScale(0.5, 1)
	shieldFill.BackgroundColor3 = THEME.Colors.Shield
	shieldFill.BorderSizePixel = 0
	shieldFill.Parent = shTrack
	corner(shieldFill, 2)

	-- ---- AMMO (bottom-right) ----
	local ammo = Instance.new("Frame")
	ammo.Name = "AmmoContainer"
	ammo.Size = if IS_MOBILE then UDim2.new(0.4, 0, 0, 70) else UDim2.new(0, 250, 0, 70)
	ammo.Position = UDim2.new(0.98, 0, 0.96, 0)
	ammo.AnchorPoint = Vector2.new(1, 1)
	ammo.BackgroundColor3 = THEME.Colors.Bg
	ammo.BackgroundTransparency = 0.55
	ammo.BorderSizePixel = 0
	ammo.Parent = root
	corner(ammo, 10)
	stroke(ammo, THEME.Colors.Border, 1.4, 0.3)
	ammoContainer = ammo

	ammoMag = Instance.new("TextLabel")
	ammoMag.Name = "Mag"
	ammoMag.Size = UDim2.new(0.48, 0, 0, 36)
	ammoMag.Position = UDim2.new(0.06, 0, 0, 8)
	ammoMag.BackgroundTransparency = 1
	ammoMag.Font = THEME.Fonts.Heavy
	ammoMag.TextSize = 32
	ammoMag.TextColor3 = THEME.Colors.Text
	ammoMag.TextXAlignment = Enum.TextXAlignment.Right
	ammoMag.Text = "30"
	ammoMag.Parent = ammo

	ammoReserve = Instance.new("TextLabel")
	ammoReserve.Name = "Reserve"
	ammoReserve.Size = UDim2.new(0.4, 0, 0, 28)
	ammoReserve.Position = UDim2.new(0.55, 0, 0, 14)
	ammoReserve.BackgroundTransparency = 1
	ammoReserve.Font = THEME.Fonts.Bold
	ammoReserve.TextSize = 18
	ammoReserve.TextColor3 = THEME.Colors.TextDim
	ammoReserve.TextXAlignment = Enum.TextXAlignment.Left
	ammoReserve.Text = "/ 120"
	ammoReserve.Parent = ammo

	weaponName = Instance.new("TextLabel")
	weaponName.Name = "Weapon"
	weaponName.Size = UDim2.new(0.9, 0, 0, 16)
	weaponName.Position = UDim2.new(0.05, 0, 1, -22)
	weaponName.BackgroundTransparency = 1
	weaponName.Font = THEME.Fonts.Med
	weaponName.TextSize = 12
	weaponName.TextColor3 = THEME.Colors.Accent
	weaponName.TextXAlignment = Enum.TextXAlignment.Left
	weaponName.Text = "RIFLE"
	weaponName.Parent = ammo

	-- ---- COMPASS (top center) ----
	local compass = Instance.new("Frame")
	compass.Name = "Compass"
	compass.Size = UDim2.new(0, if IS_MOBILE then 220 else 320, 0, 28)
	compass.Position = UDim2.new(0.5, 0, 0.02, 0)
	compass.AnchorPoint = Vector2.new(0.5, 0)
	compass.BackgroundColor3 = THEME.Colors.Bg
	compass.BackgroundTransparency = 0.55
	compass.BorderSizePixel = 0
	compass.Parent = root
	corner(compass, 6)
	stroke(compass, THEME.Colors.Border, 1, 0.4)

	compassLabel = Instance.new("TextLabel")
	compassLabel.Name = "Heading"
	compassLabel.Size = UDim2.fromScale(1, 1)
	compassLabel.BackgroundTransparency = 1
	compassLabel.Font = THEME.Fonts.Bold
	compassLabel.TextSize = 14
	compassLabel.TextColor3 = THEME.Colors.Text
	compassLabel.Text = "N  0°"
	compassLabel.Parent = compass

	-- center tick
	local tick = Instance.new("Frame")
	tick.Size = UDim2.new(0, 2, 0, 8)
	tick.Position = UDim2.new(0.5, 0, 1, 0)
	tick.AnchorPoint = Vector2.new(0.5, 0)
	tick.BackgroundColor3 = THEME.Colors.Accent
	tick.BorderSizePixel = 0
	tick.Parent = compass

	-- ---- SCOREBOARD + TIMER ----
	local sb = Instance.new("Frame")
	sb.Name = "Scoreboard"
	sb.Size = UDim2.new(0, if IS_MOBILE then 260 else 340, 0, 56)
	sb.Position = UDim2.new(0.5, 0, 0.055, 0)
	sb.AnchorPoint = Vector2.new(0.5, 0)
	sb.BackgroundColor3 = THEME.Colors.Bg
	sb.BackgroundTransparency = 0.55
	sb.BorderSizePixel = 0
	sb.Parent = root
	corner(sb, 8)
	stroke(sb, THEME.Colors.Border, 1.2, 0.3)

	scoreRed = Instance.new("TextLabel")
	scoreRed.Name = "Red"
	scoreRed.Size = UDim2.new(0.28, 0, 0, 28)
	scoreRed.Position = UDim2.new(0.04, 0, 0, 4)
	scoreRed.BackgroundTransparency = 1
	scoreRed.Font = THEME.Fonts.Heavy
	scoreRed.TextSize = 24
	scoreRed.TextColor3 = THEME.Colors.Red
	scoreRed.Text = "0"
	scoreRed.Parent = sb

	scoreSep = Instance.new("TextLabel")
	scoreSep.Size = UDim2.new(0.2, 0, 0, 28)
	scoreSep.Position = UDim2.new(0.4, 0, 0, 4)
	scoreSep.BackgroundTransparency = 1
	scoreSep.Font = THEME.Fonts.Bold
	scoreSep.TextSize = 18
	scoreSep.TextColor3 = THEME.Colors.TextDim
	scoreSep.Text = "—"
	scoreSep.Parent = sb

	scoreBlue = Instance.new("TextLabel")
	scoreBlue.Name = "Blue"
	scoreBlue.Size = UDim2.new(0.28, 0, 0, 28)
	scoreBlue.Position = UDim2.new(0.68, 0, 0, 4)
	scoreBlue.BackgroundTransparency = 1
	scoreBlue.Font = THEME.Fonts.Heavy
	scoreBlue.TextSize = 24
	scoreBlue.TextColor3 = THEME.Colors.Blue
	scoreBlue.Text = "0"
	scoreBlue.Parent = sb

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(0.4, 0, 0, 16)
	timerLabel.Position = UDim2.new(0.3, 0, 0, 32)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = THEME.Fonts.Bold
	timerLabel.TextSize = 13
	timerLabel.TextColor3 = THEME.Colors.Accent
	timerLabel.Text = "1:45"
	timerLabel.Parent = sb

	roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "Round"
	roundLabel.Size = UDim2.new(0.28, 0, 0, 14)
	roundLabel.Position = UDim2.new(0.02, 0, 0, 36)
	roundLabel.BackgroundTransparency = 1
	roundLabel.Font = THEME.Fonts.Med
	roundLabel.TextSize = 11
	roundLabel.TextColor3 = THEME.Colors.TextDim
	roundLabel.TextXAlignment = Enum.TextXAlignment.Left
	roundLabel.Text = "ROUND 1"
	roundLabel.Parent = sb

	phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "Phase"
	phaseLabel.Size = UDim2.new(0.28, 0, 0, 14)
	phaseLabel.Position = UDim2.new(0.7, 0, 0, 36)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = THEME.Fonts.Med
	phaseLabel.TextSize = 11
	phaseLabel.TextColor3 = THEME.Colors.AccentGold
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
	phaseLabel.Text = "COMBAT"
	phaseLabel.Parent = sb

	-- ---- ABILITY BAR (bottom center) ----
	abilityBar = Instance.new("Frame")
	abilityBar.Name = "AbilityBar"
	abilityBar.Size = UDim2.new(0, if IS_MOBILE then 220 else 280, 0, 54)
	abilityBar.Position = UDim2.new(0.5, 0, 0.97, 0)
	abilityBar.AnchorPoint = Vector2.new(0.5, 1)
	abilityBar.BackgroundTransparency = 1
	abilityBar.Parent = root

	local abList = Instance.new("UIListLayout")
	abList.FillDirection = Enum.FillDirection.Horizontal
	abList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	abList.Padding = UDim.new(0, 8)
	abList.Parent = abilityBar

	local function makeAbilitySlot(id: string, key: string, label: string)
		local slot = Instance.new("Frame")
		slot.Name = "Ability_" .. id
		slot.Size = UDim2.new(0, 58, 0, 54)
		slot.BackgroundColor3 = THEME.Colors.Bg
		slot.BackgroundTransparency = 0.6
		slot.BorderSizePixel = 0
		slot.Parent = abilityBar
		corner(slot, 8)
		stroke(slot, THEME.Colors.Border, 1, 0.35)

		local keyLbl = Instance.new("TextLabel")
		keyLbl.Name = "Key"
		keyLbl.Size = UDim2.new(1, 0, 0, 14)
		keyLbl.Position = UDim2.new(0, 0, 0, 4)
		keyLbl.BackgroundTransparency = 1
		keyLbl.Font = THEME.Fonts.Bold
		keyLbl.TextSize = 11
		keyLbl.TextColor3 = THEME.Colors.Accent
		keyLbl.Text = key
		keyLbl.Parent = slot

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "Name"
		nameLbl.Size = UDim2.new(1, -4, 0, 14)
		nameLbl.Position = UDim2.new(0, 2, 0, 20)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = THEME.Fonts.Med
		nameLbl.TextSize = 10
		nameLbl.TextColor3 = THEME.Colors.Text
		nameLbl.Text = label
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = slot

		local chargeLbl = Instance.new("TextLabel")
		chargeLbl.Name = "Charges"
		chargeLbl.Size = UDim2.new(1, 0, 0, 14)
		chargeLbl.Position = UDim2.new(0, 0, 1, -16)
		chargeLbl.BackgroundTransparency = 1
		chargeLbl.Font = THEME.Fonts.Bold
		chargeLbl.TextSize = 12
		chargeLbl.TextColor3 = THEME.Colors.TextDim
		chargeLbl.Text = "1/1"
		chargeLbl.Parent = slot

		local cd = Instance.new("Frame")
		cd.Name = "CooldownOverlay"
		cd.Size = UDim2.fromScale(1, 0)
		cd.Position = UDim2.fromScale(0, 1)
		cd.AnchorPoint = Vector2.new(0, 1)
		cd.BackgroundColor3 = Color3.new(0, 0, 0)
		cd.BackgroundTransparency = 0.45
		cd.BorderSizePixel = 0
		cd.ZIndex = 2
		cd.Parent = slot
		corner(cd, 8)

		abilitySlots[id] = slot
	end

	makeAbilitySlot("C", "C", "UTIL")
	makeAbilitySlot("Q", "Q", "TACT")
	makeAbilitySlot("E", "E", "SIG")
	makeAbilitySlot("X", "X", "ULT")

	-- ---- OBJECTIVE / STREAK ----
	objectiveLabel = Instance.new("TextLabel")
	objectiveLabel.Name = "Objective"
	objectiveLabel.Size = UDim2.new(0.5, 0, 0, 22)
	objectiveLabel.Position = UDim2.new(0.5, 0, 0.14, 0)
	objectiveLabel.AnchorPoint = Vector2.new(0.5, 0)
	objectiveLabel.BackgroundTransparency = 1
	objectiveLabel.Font = THEME.Fonts.Bold
	objectiveLabel.TextSize = 14
	objectiveLabel.TextColor3 = THEME.Colors.Accent
	objectiveLabel.Text = ""
	objectiveLabel.TextTransparency = 1
	objectiveLabel.Parent = root

	streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "Streak"
	streakLabel.Size = UDim2.new(0.4, 0, 0, 28)
	streakLabel.Position = UDim2.new(0.5, 0, 0.22, 0)
	streakLabel.AnchorPoint = Vector2.new(0.5, 0)
	streakLabel.BackgroundTransparency = 1
	streakLabel.Font = THEME.Fonts.Heavy
	streakLabel.TextSize = 22
	streakLabel.TextColor3 = THEME.Colors.AccentGold
	streakLabel.Text = ""
	streakLabel.TextTransparency = 1
	streakLabel.Parent = root

	spectateLabel = Instance.new("TextLabel")
	spectateLabel.Name = "Spectate"
	spectateLabel.Size = UDim2.new(0.6, 0, 0, 24)
	spectateLabel.Position = UDim2.new(0.5, 0, 0.88, 0)
	spectateLabel.AnchorPoint = Vector2.new(0.5, 0)
	spectateLabel.BackgroundTransparency = 1
	spectateLabel.Font = THEME.Fonts.Bold
	spectateLabel.TextSize = 16
	spectateLabel.TextColor3 = THEME.Colors.Text
	spectateLabel.Text = ""
	spectateLabel.Visible = false
	spectateLabel.Parent = root

	-- ---- KILLFEED (top-right) ----
	killfeedList = Instance.new("Frame")
	killfeedList.Name = "Killfeed"
	killfeedList.Size = UDim2.new(0, if IS_MOBILE then 200 else 300, 0, 200)
	killfeedList.Position = UDim2.new(0.985, 0, 0.12, 0)
	killfeedList.AnchorPoint = Vector2.new(1, 0)
	killfeedList.BackgroundTransparency = 1
	killfeedList.ClipsDescendants = true
	killfeedList.Parent = root

	local kfLayout = Instance.new("UIListLayout")
	kfLayout.SortOrder = Enum.SortOrder.LayoutOrder
	kfLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	kfLayout.Padding = UDim.new(0, 4)
	kfLayout.Parent = killfeedList
end

-- ============================================================================
-- BUILDERS — MenuUI / DynamicUI
-- ============================================================================

local function createMenuUI(gui: ScreenGui)
	local root = Instance.new("CanvasGroup")
	root.Name = "MenuRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0.45
	root.GroupTransparency = 1
	root.Visible = false
	root.Parent = gui
	menuRoot = root

	local panel = Instance.new("Frame")
	panel.Name = "MenuPanel"
	panel.Size = if IS_MOBILE then UDim2.new(0.9, 0, 0.7, 0) else UDim2.new(0, 420, 0, 480)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = THEME.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = root
	corner(panel, 12)
	stroke(panel, THEME.Colors.Accent, 1.5, 0.5)

	local function makeMenu(name: string, title: string)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Visible = false
		f.Parent = panel
		pad(f, 28, 28, 32, 32)

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 40)
		t.BackgroundTransparency = 1
		t.Font = THEME.Fonts.Heavy
		t.TextSize = 28
		t.TextColor3 = THEME.Colors.Text
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = title
		t.Parent = f

		local line = Instance.new("Frame")
		line.Size = UDim2.new(0, 56, 0, 3)
		line.Position = UDim2.new(0, 0, 0, 48)
		line.BackgroundColor3 = THEME.Colors.Accent
		line.BorderSizePixel = 0
		line.Parent = f

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.Size = UDim2.new(1, 0, 1, -70)
		body.Position = UDim2.new(0, 0, 0, 64)
		body.BackgroundTransparency = 1
		body.Parent = f

		menus[name] = f
		return f
	end

	makeMenu("PauseMenu", "PAUSED")
	makeMenu("SettingsMenu", "SETTINGS")
	makeMenu("ScoreboardMenu", "SCOREBOARD")

	-- Pause actions
	local pause = menus["PauseMenu"]
	local body = pause:FindFirstChild("Body") :: Frame
	local function pauseBtn(text: string, order: number, fn: () -> ())
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, 44)
		b.BackgroundColor3 = THEME.Colors.Bg
		b.BackgroundTransparency = 0.2
		b.Text = text
		b.Font = THEME.Fonts.Bold
		b.TextSize = 15
		b.TextColor3 = THEME.Colors.Text
		b.LayoutOrder = order
		b.AutoButtonColor = false
		b.Parent = body
		corner(b, 8)
		trackConn(b.MouseButton1Click:Connect(fn))
	end
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.Parent = body
	pauseBtn("RESUME", 1, function()
		HUDController.ToggleMenu("PauseMenu")
	end)
	pauseBtn("SETTINGS", 2, function()
		HUDController.ToggleMenu("SettingsMenu")
	end)
	pauseBtn("LEAVE MATCH", 3, function()
		-- bind externally via BindableEvent if needed
		local ev = ReplicatedStorage:FindFirstChild("Events")
		local leave = ev and ev:FindFirstChild("RequestLeaveMatch")
		if leave and leave:IsA("RemoteEvent") then
			leave:FireServer()
		end
	end)
end

local function createDynamicUI(gui: ScreenGui)
	-- Center hitmarker host (screen-space, not world billboard — snappier)
	hitmarkerRoot = Instance.new("Frame")
	hitmarkerRoot.Name = "HitmarkerRoot"
	hitmarkerRoot.Size = UDim2.fromScale(1, 1)
	hitmarkerRoot.BackgroundTransparency = 1
	hitmarkerRoot.Parent = gui

	-- Vignette (damage / low HP)
	vignette = Instance.new("ImageLabel")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.Image = "rbxassetid://277733811" -- soft vignette; replace with your asset
	vignette.ImageColor3 = THEME.Colors.HpLow
	vignette.ImageTransparency = 1
	vignette.ScaleType = Enum.ScaleType.Stretch
	vignette.ZIndex = 5
	vignette.Parent = gui

	flashFrame = Instance.new("Frame")
	flashFrame.Name = "ScreenFlash"
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.ZIndex = 8
	flashFrame.Parent = gui

	suppressFrame = Instance.new("Frame")
	suppressFrame.Name = "Suppress"
	suppressFrame.Size = UDim2.fromScale(1, 1)
	suppressFrame.BackgroundColor3 = Color3.fromRGB(180, 200, 220)
	suppressFrame.BackgroundTransparency = 1
	suppressFrame.BorderSizePixel = 0
	suppressFrame.ZIndex = 7
	suppressFrame.Parent = gui

	scopeFrame = Instance.new("Frame")
	scopeFrame.Name = "ScopeOverlay"
	scopeFrame.Size = UDim2.fromScale(1, 1)
	scopeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	scopeFrame.BackgroundTransparency = 1
	scopeFrame.BorderSizePixel = 0
	scopeFrame.ZIndex = 10
	scopeFrame.Visible = false
	scopeFrame.Parent = gui

	-- Add some basic sniper scope lines (black edges with a cross in the middle)
	local topMask = Instance.new("Frame")
	topMask.Size = UDim2.new(1, 0, 0.5, -200)
	topMask.Position = UDim2.fromScale(0, 0)
	topMask.BackgroundColor3 = Color3.new(0, 0, 0)
	topMask.BorderSizePixel = 0
	topMask.Parent = scopeFrame

	local bottomMask = Instance.new("Frame")
	bottomMask.Size = UDim2.new(1, 0, 0.5, -200)
	bottomMask.Position = UDim2.new(0, 0, 0.5, 200)
	bottomMask.BackgroundColor3 = Color3.new(0, 0, 0)
	bottomMask.BorderSizePixel = 0
	bottomMask.Parent = scopeFrame

	local leftMask = Instance.new("Frame")
	leftMask.Size = UDim2.new(0.5, -200, 1, 0)
	leftMask.Position = UDim2.fromScale(0, 0)
	leftMask.BackgroundColor3 = Color3.new(0, 0, 0)
	leftMask.BorderSizePixel = 0
	leftMask.Parent = scopeFrame

	local rightMask = Instance.new("Frame")
	rightMask.Size = UDim2.new(0.5, -200, 1, 0)
	rightMask.Position = UDim2.new(0.5, 200, 0, 0)
	rightMask.BackgroundColor3 = Color3.new(0, 0, 0)
	rightMask.BorderSizePixel = 0
	rightMask.Parent = scopeFrame

	local centerCircle = Instance.new("ImageLabel")
	centerCircle.Size = UDim2.new(0, 400, 0, 400)
	centerCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	centerCircle.Position = UDim2.fromScale(0.5, 0.5)
	centerCircle.BackgroundTransparency = 1
	centerCircle.Image = "rbxassetid://473857508" -- A generic scope circle or crosshair
	centerCircle.ImageColor3 = Color3.new(0, 0, 0)
	centerCircle.Parent = scopeFrame

	-- Pools
	local function hitFactory(): Instance
		local f = Instance.new("Frame")
		f.Name = "Hitmarker"
		f.Size = UDim2.new(0, 28, 0, 28)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.Visible = false
		local container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.fromScale(1, 1)
		container.BackgroundTransparency = 1
		container.Parent = f
		-- 4 diagonal ticks
		for i, rot in { 45, 135, 225, 315 } do
			local line = Instance.new("Frame")
			line.Name = "L" .. i
			line.Size = UDim2.new(0, 3, 0, 10)
			line.AnchorPoint = Vector2.new(0.5, 1)
			line.Position = UDim2.fromScale(0.5, 0.5)
			line.BackgroundColor3 = Color3.new(1, 1, 1)
			line.BorderSizePixel = 0
			line.Rotation = rot
			line.Parent = container
			-- offset outward along rotation roughly via Position after rotation parent
		end
		-- cleaner X hitmarker using 4 corner bars
		container:ClearAllChildren()
		local function arm(x: number, y: number, ang: number)
			local a = Instance.new("Frame")
			a.Size = UDim2.new(0, 12, 0, 2)
			a.AnchorPoint = Vector2.new(0.5, 0.5)
			a.Position = UDim2.new(x, 0, y, 0)
			a.BackgroundColor3 = Color3.new(1, 1, 1)
			a.BorderSizePixel = 0
			a.Rotation = ang
			a.Parent = container
		end
		arm(0.25, 0.25, 45)
		arm(0.75, 0.25, -45)
		arm(0.25, 0.75, -45)
		arm(0.75, 0.75, 45)
		return f
	end

	local function dmgFactory(): Instance
		local bb = Instance.new("BillboardGui")
		bb.Name = "DamageNumber"
		bb.Size = UDim2.new(0, 90, 0, 36)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Enabled = false
		local tl = Instance.new("TextLabel")
		tl.Name = "DamageText"
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Font = THEME.Fonts.Heavy
		tl.TextScaled = true
		tl.TextColor3 = THEME.Colors.Text
		tl.TextStrokeTransparency = 0.5
		tl.Parent = bb
		return bb
	end

	local function dirFactory(): Instance
		local f = Instance.new("Frame")
		f.Name = "DirDmg"
		f.Size = UDim2.new(0, 160, 0, 160)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.Visible = false
		local wedge = Instance.new("ImageLabel")
		wedge.Name = "Arc"
		wedge.Size = UDim2.new(0, 48, 0, 24)
		wedge.Position = UDim2.new(0.5, 0, 0, 4)
		wedge.AnchorPoint = Vector2.new(0.5, 0)
		wedge.BackgroundTransparency = 1
		wedge.Image = "rbxassetid://867619898" -- chevron; swap for your triangle
		wedge.ImageColor3 = THEME.Colors.Red
		wedge.Parent = f
		return f
	end

	local function kfFactory(): Instance
		local e = Instance.new("Frame")
		e.Name = "KFEntry"
		e.Size = UDim2.new(1, 0, 0, 26)
		e.BackgroundColor3 = THEME.Colors.Bg
		e.BackgroundTransparency = 0.65
		e.BorderSizePixel = 0
		e.Visible = false
		corner(e, 5)
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Text"
		lbl.Size = UDim2.new(1, -12, 1, 0)
		lbl.Position = UDim2.new(0, 6, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = THEME.Fonts.Bold
		lbl.TextSize = 12
		lbl.TextColor3 = THEME.Colors.Text
		lbl.TextXAlignment = Enum.TextXAlignment.Right
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = e
		return e
	end

	local dyn = gui
	if ObjectPool and ObjectPool.new then
		hitmarkerPool = ObjectPool.new({
			template = hitFactory,
			initialSize = 12,
			container = dyn,
			resetHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = false
				end
			end,
			getHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = true
				end
			end,
		})
		damageTextPool = ObjectPool.new({
			template = dmgFactory,
			initialSize = 28,
			container = dyn,
			resetHandler = function(inst: Instance)
				if inst:IsA("BillboardGui") then
					inst.Enabled = false
					inst.Adornee = nil
				end
			end,
			getHandler = function(inst: Instance)
				if inst:IsA("BillboardGui") then
					inst.Enabled = true
				end
			end,
		})
		directionalPool = ObjectPool.new({
			template = dirFactory,
			initialSize = 8,
			container = dyn,
			resetHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = false
					inst.Rotation = 0
				end
			end,
			getHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = true
				end
			end,
		})
		killfeedPool = ObjectPool.new({
			template = kfFactory,
			initialSize = 10,
			container = dyn,
			resetHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = false
					inst.Parent = dyn
				end
			end,
			getHandler = function(inst: Instance)
				if inst:IsA("Frame") then
					inst.Visible = true
				end
			end,
		})
	else
		hitmarkerPool = makeSimplePool(hitFactory, 12, dyn, function(i)
			(i :: Frame).Visible = false
		end)
		damageTextPool = makeSimplePool(dmgFactory, 28, dyn, function(i)
			local b = i :: BillboardGui
			b.Enabled = false
			b.Adornee = nil
		end)
		directionalPool = makeSimplePool(dirFactory, 8, dyn, function(i)
			(i :: Frame).Visible = false
			;(i :: Frame).Rotation = 0
		end)
		killfeedPool = makeSimplePool(kfFactory, 10, dyn, function(i)
			(i :: Frame).Visible = false
			i.Parent = dyn
		end)
	end
end

-- ============================================================================
-- INIT / MODE
-- ============================================================================

function HUDController.Init(targetPlayerGui: PlayerGui?)
	if _initialized then
		HUDController.Destroy()
	end

	local pGui = targetPlayerGui or LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	_playerGui = pGui

	for _, name in { "MainHUD", "MenuUI", "DynamicUI" } do
		local old = pGui:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local mainHUD = Instance.new("ScreenGui")
	mainHUD.Name = "MainHUD"
	mainHUD.DisplayOrder = 10
	mainHUD.ResetOnSpawn = false
	mainHUD.IgnoreGuiInset = true
	mainHUD.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainHUD.Parent = pGui
	containers.MainHUD = mainHUD
	createMainHUD(mainHUD)

	local menuUI = Instance.new("ScreenGui")
	menuUI.Name = "MenuUI"
	menuUI.DisplayOrder = 40
	menuUI.ResetOnSpawn = false
	menuUI.IgnoreGuiInset = true
	menuUI.Parent = pGui
	containers.MenuUI = menuUI
	createMenuUI(menuUI)

	local dynamicUI = Instance.new("ScreenGui")
	dynamicUI.Name = "DynamicUI"
	dynamicUI.DisplayOrder = 30
	dynamicUI.ResetOnSpawn = false
	dynamicUI.IgnoreGuiInset = true
	dynamicUI.Parent = pGui
	containers.DynamicUI = dynamicUI
	createDynamicUI(dynamicUI)

	-- Pause key
	trackConn(UserInputService.InputBegan:Connect(function(input, gp)
		if gp or currentHUDMode == "Lobby" then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonStart then
			HUDController.ToggleMenu("PauseMenu")
		end
	end))

	resolveModules()
	_initialized = true
	HUDController.SetHUDMode("Lobby")
end

function HUDController.SetHUDMode(mode: HUDMode)
	currentHUDMode = mode
	local mainHUD = containers.MainHUD
	local dynamicUI = containers.DynamicUI
	local menuUI = containers.MenuUI

	resolveModules()

	if mode == "Lobby" then
		if mainHUD then
			mainHUD.Enabled = false
		end
		if dynamicUI then
			dynamicUI.Enabled = false
		end
		if menuUI then
			menuUI.Enabled = false
		end
		if matchClockConn then
			matchClockConn:Disconnect()
			matchClockConn = nil
		end
		if _crosshair and _crosshair.SetVisible then
			pcall(_crosshair.SetVisible, false)
		end
		if _lobbyUI and _lobbyUI.ShowMainLobbyMenu then
			pcall(_lobbyUI.ShowMainLobbyMenu)
		end
	elseif mode == "Match" then
		if mainHUD then
			mainHUD.Enabled = true
		end
		if dynamicUI then
			dynamicUI.Enabled = true
		end
		if menuUI then
			menuUI.Enabled = true
		end
		if spectateLabel then
			spectateLabel.Visible = false
		end
		if _crosshair and _crosshair.SetVisible then
			pcall(_crosshair.SetVisible, true)
		end
		if _lobbyUI and _lobbyUI.HideAllMenus then
			pcall(_lobbyUI.HideAllMenus)
		end
	elseif mode == "Spectate" then
		if mainHUD then
			mainHUD.Enabled = true
		end
		if dynamicUI then
			dynamicUI.Enabled = true
		end
		if menuUI then
			menuUI.Enabled = true
		end
		if spectateLabel then
			spectateLabel.Visible = true
			spectateLabel.Text = "SPECTATING  ·  [Q]/E] next"
		end
		if _crosshair and _crosshair.SetVisible then
			pcall(_crosshair.SetVisible, false)
		end
		if _lobbyUI and _lobbyUI.HideAllMenus then
			pcall(_lobbyUI.HideAllMenus)
		end
	end
end

function HUDController.GetHUDMode(): HUDMode
	return currentHUDMode
end

-- ============================================================================
-- VITALS / AMMO / COMPASS / SCORE
-- ============================================================================

function HUDController.UpdateHealth(currentHealth: number, maxHealth: number, shield: number?, maxShield: number?)
	if not healthFill or not healthText then
		return
	end
	local maxH = math.max(maxHealth, 1)
	local ratio = math.clamp(currentHealth / maxH, 0, 1)
	local col = hpColor(ratio)

	trackTween(TweenService:Create(healthFill, THEME.Tween.Bar, {
		Size = UDim2.new(ratio, 0, 1, 0),
		BackgroundColor3 = col,
	})):Play()

	healthText.Text = tostring(math.ceil(currentHealth))
	healthText.TextColor3 = if ratio < 0.3 then THEME.Colors.HpLow else THEME.Colors.Text

	local sh = shield or 0
	local maxS = maxShield or 50
	local sRatio = math.clamp(sh / math.max(maxS, 1), 0, 1)
	if shieldFill then
		trackTween(TweenService:Create(shieldFill, THEME.Tween.Bar, {
			Size = UDim2.new(sRatio, 0, 1, 0),
		})):Play()
	end
	if shieldText then
		shieldText.Text = tostring(math.ceil(sh))
	end

	-- damage punch + vignette
	if ratio < lastHealthRatio - 0.02 and vignette then
		vignette.ImageTransparency = 0.35
		trackTween(TweenService:Create(vignette, THEME.Tween.Med, { ImageTransparency = if ratio < 0.25 then 0.55 else 1 })):Play()
		playSound("UI_Damage", 0.35)
	elseif ratio >= 0.35 and vignette and vignette.ImageTransparency < 1 then
		trackTween(TweenService:Create(vignette, THEME.Tween.Slow, { ImageTransparency = 1 })):Play()
	end
	lastHealthRatio = ratio

	if healthGlow then
		healthGlow.Color = if ratio < 0.25 then THEME.Colors.HpLow else THEME.Colors.Border
	end
end

function HUDController.UpdateAmmo(currentAmmo: number, reserveAmmo: number, weaponNameStr: string?)
	local mag = math.max(currentAmmo, 0)
	local res = math.max(reserveAmmo, 0)
	if ammoMag then
		ammoMag.Text = tostring(mag)
	end
	if ammoReserve then
		ammoReserve.Text = "/ " .. tostring(res)
	end
	if weaponNameStr and weaponName then
		weaponName.Text = string.upper(weaponNameStr)
	end

	local low = mag <= 5 and mag > 0
	local empty = mag <= 0
	if ammoMag then
		ammoMag.TextColor3 = if empty then THEME.Colors.HpLow elseif low then THEME.Colors.AccentGold else THEME.Colors.Text
	end

	if low or empty then
		if not lowAmmoPulse and ammoContainer then
			lowAmmoPulse = TweenService:Create(ammoContainer, THEME.Tween.Pulse, {
				BackgroundTransparency = 0.05,
			})
			lowAmmoPulse:Play()
		end
	else
		if lowAmmoPulse then
			lowAmmoPulse:Cancel()
			lowAmmoPulse = nil
		end
		if ammoContainer then
			ammoContainer.BackgroundTransparency = 0.2
		end
	end
end

function HUDController.UpdateCompass(headingDegrees: number)
	if not compassLabel then
		return
	end
	local deg = (math.floor(headingDegrees) % 360 + 360) % 360
	local cardinal = "N"
	local sectors = {
		{ 22.5, "N" }, { 67.5, "NE" }, { 112.5, "E" }, { 157.5, "SE" },
		{ 202.5, "S" }, { 247.5, "SW" }, { 292.5, "W" }, { 337.5, "NW" }, { 360, "N" },
	}
	for _, s in sectors do
		if deg < s[1] then
			cardinal = s[2] :: string
			break
		end
	end
	compassLabel.Text = string.format("%s   %d°", cardinal, deg)
end

function HUDController.UpdateScoreboard(redScore: number, blueScore: number, roundText: string?)
	if scoreRed then
		scoreRed.Text = tostring(redScore)
	end
	if scoreBlue then
		scoreBlue.Text = tostring(blueScore)
	end
	if roundText and roundLabel then
		roundLabel.Text = string.upper(roundText)
	end
end

function HUDController.UpdateScoreboardEx(data: ScoreboardData)
	HUDController.UpdateScoreboard(data.redScore, data.blueScore, data.roundText)
	if data.phase and phaseLabel then
		phaseLabel.Text = string.upper(data.phase)
		phaseLabel.TextColor3 = if data.phase == "Buy"
			then THEME.Colors.AccentGold
			elseif data.phase == "Spike" then THEME.Colors.HpLow
			else THEME.Colors.Accent
	end
	if data.timerSeconds ~= nil then
		HUDController.SetMatchTimer(data.timerSeconds)
	end
end

function HUDController.SetMatchTimer(secondsRemaining: number)
	matchTimerEnd = os.clock() + math.max(secondsRemaining, 0)
	if matchClockConn then
		return
	end
	matchClockConn = RunService.RenderStepped:Connect(function()
		if not matchTimerEnd or not timerLabel then
			return
		end
		local left = math.max(0, matchTimerEnd - os.clock())
		local m = math.floor(left / 60)
		local s = math.floor(left % 60)
		timerLabel.Text = string.format("%d:%02d", m, s)
		timerLabel.TextColor3 = if left <= 10 then THEME.Colors.HpLow else THEME.Colors.Accent
		if left <= 0 and matchClockConn then
			matchClockConn:Disconnect()
			matchClockConn = nil
		end
	end)
	table.insert(connections, matchClockConn)
end

function HUDController.SetObjective(text: string?, duration: number?)
	if not objectiveLabel then
		return
	end
	objectiveLabel.Text = text or ""
	objectiveLabel.TextTransparency = 0
	if duration then
		task.delay(duration, function()
			if objectiveLabel then
				trackTween(TweenService:Create(objectiveLabel, THEME.Tween.Med, { TextTransparency = 1 })):Play()
			end
		end)
	end
end

function HUDController.ShowStreak(text: string, duration: number?)
	if not streakLabel then
		return
	end
	streakLabel.Text = string.upper(text)
	streakLabel.TextTransparency = 0
	playSound("UI_Streak", 0.5)
	task.delay(duration or 2.2, function()
		if streakLabel then
			trackTween(TweenService:Create(streakLabel, THEME.Tween.Med, { TextTransparency = 1 })):Play()
		end
	end)
end

function HUDController.UpdateAbilitySlot(data: AbilitySlotData)
	local slot = abilitySlots[data.id]
	if not slot then
		return
	end
	local nameLbl = slot:FindFirstChild("Name") :: TextLabel?
	local chargeLbl = slot:FindFirstChild("Charges") :: TextLabel?
	local keyLbl = slot:FindFirstChild("Key") :: TextLabel?
	local cd = slot:FindFirstChild("CooldownOverlay") :: Frame?
	if nameLbl then
		nameLbl.Text = string.upper(data.name)
	end
	if keyLbl then
		keyLbl.Text = data.key
	end
	if chargeLbl then
		chargeLbl.Text = string.format("%d/%d", data.charges, data.maxCharges)
		chargeLbl.TextColor3 = if data.charges > 0 then THEME.Colors.Text else THEME.Colors.TextDim
	end
	local ready = if data.ready ~= nil then data.ready else (data.charges > 0)
	if cd then
		local rem = data.cooldownRemaining or 0
		local tot = math.max(data.cooldownTotal or 1, 0.001)
		local pct = if ready and rem <= 0 then 0 else math.clamp(rem / tot, 0, 1)
		cd.Size = UDim2.new(1, 0, pct, 0)
	end
	local st = slot:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if ready then THEME.Colors.Accent else THEME.Colors.Border
	end
end

function HUDController.SetSpectateTarget(name: string?)
	if spectateLabel then
		spectateLabel.Visible = true
		spectateLabel.Text = if name then ("SPECTATING  " .. string.upper(name)) else "SPECTATING"
	end
end

-- ============================================================================
-- KILLFEED / HIT / DAMAGE / DIR
-- ============================================================================

function HUDController.AddKillfeedEntry(
	attackerName: string,
	victimName: string,
	weaponNameStr: string?,
	isHeadshot: boolean?
)
	if not killfeedList or not killfeedPool then
		return
	end

	-- trim
	local kids = killfeedList:GetChildren()
	local entries = 0
	for _, k in kids do
		if k:IsA("Frame") and k.Name == "KFEntry" then
			entries += 1
		end
	end
	if entries >= THEME.Layout.KillfeedMax then
		for _, k in kids do
			if k:IsA("Frame") and k.Name == "KFEntry" then
				killfeedPool:Return(k)
				break
			end
		end
	end

	local entry = killfeedPool:Get() :: Frame
	entry.Name = "KFEntry"
	killfeedOrder += 1
	entry.LayoutOrder = killfeedOrder
	entry.BackgroundTransparency = 0.25
	entry.Parent = killfeedList

	local lbl = entry:FindFirstChild("Text") :: TextLabel?
	if lbl then
		local hs = if isHeadshot then " ●" else ""
		lbl.Text = string.format("%s  ⌁ %s  %s%s", attackerName, weaponNameStr or "WPN", victimName, hs)
		lbl.TextColor3 = if isHeadshot then THEME.Colors.Headshot else THEME.Colors.Text
		lbl.TextTransparency = 0
	end

	task.delay(THEME.Layout.KillfeedLife, function()
		if not entry.Parent then
			return
		end
		if lbl then
			TweenService:Create(lbl, THEME.Tween.Med, { TextTransparency = 1 }):Play()
		end
		local tw = TweenService:Create(entry, THEME.Tween.Med, { BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Once(function()
			if killfeedPool then
				killfeedPool:Return(entry)
			end
		end)
	end)
end

function HUDController.ShowHitmarker(isHeadshot: boolean?, isKill: boolean?)
	if not hitmarkerPool or not hitmarkerRoot then
		return
	end
	local hm = hitmarkerPool:Get() :: Frame
	hm.Parent = hitmarkerRoot
	hm.Visible = true
	hm.Size = UDim2.new(0, 22, 0, 22)

	local col = THEME.Colors.Text
	if isKill then
		col = THEME.Colors.Kill
	elseif isHeadshot then
		col = THEME.Colors.Headshot
	end
	local container = hm:FindFirstChild("Container")
	if container then
		for _, ch in container:GetChildren() do
			if ch:IsA("Frame") then
				ch.BackgroundColor3 = col
				ch.BackgroundTransparency = 0
			end
		end
	end

	playSound(if isKill then "UI_HitKill" elseif isHeadshot then "UI_HitHead" else "UI_Hit", 0.4)

	trackTween(TweenService:Create(hm, THEME.Tween.Fast, { Size = UDim2.new(0, 34, 0, 34) })):Play()
	task.delay(0.12, function()
		if container then
			for _, ch in container:GetChildren() do
				if ch:IsA("Frame") then
					TweenService:Create(ch, THEME.Tween.Fast, { BackgroundTransparency = 1 }):Play()
				end
			end
		end
		task.delay(0.12, function()
        if hitmarkerPool then
            hitmarkerPool:Return(hm)
        else
            hm:Destroy()
        end
    end)
	end)
end

function HUDController.ShowDamageNumber(worldPosition: Vector3, damage: number, isHeadshot: boolean?)
	if not damageTextPool then
		return
	end
	local bb = damageTextPool:Get() :: BillboardGui
	bb.Parent = containers.DynamicUI

	local part = Instance.new("Part")
	part.Name = "DmgAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = worldPosition + Vector3.new(math.random() - 0.5, 1.2, math.random() - 0.5)
	part.Parent = Workspace
	bb.Adornee = part
	bb.StudsOffset = Vector3.zero

	local tl = bb:FindFirstChild("DamageText") :: TextLabel?
	if tl then
		tl.Text = tostring(math.floor(damage)) .. (if isHeadshot then "!" else "")
		tl.TextColor3 = if isHeadshot then THEME.Colors.Headshot else THEME.Colors.Text
		tl.TextTransparency = 0
	end

	local rise = TweenService:Create(part, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = part.Position + Vector3.new(0, 2.5, 0),
	})
	rise:Play()
	if tl then
		task.delay(0.25, function()
			TweenService:Create(tl, THEME.Tween.Med, { TextTransparency = 1 }):Play()
		end)
	end
	task.delay(0.65, function()
		damageTextPool:Return(bb)
		part:Destroy()
	end)
end

function HUDController.ShowDirectionalIndicator(damageSourcePosition: Vector3, cameraCFrame: CFrame)
	if not directionalPool then
		return
	end
	local ind = directionalPool:Get() :: Frame
	ind.Parent = containers.DynamicUI
	ind.Visible = true

	local toSource = damageSourcePosition - cameraCFrame.Position
	local flat = Vector3.new(toSource.X, 0, toSource.Z)
	if flat.Magnitude < 0.05 then
		directionalPool:Return(ind)
		return
	end
	flat = flat.Unit
	local look = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z).Unit
	local right = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z).Unit
	local ang = math.deg(math.atan2(flat:Dot(right), flat:Dot(look)))
	ind.Rotation = ang

	local arc = ind:FindFirstChild("Arc") :: ImageLabel?
	if arc then
		arc.ImageTransparency = 0
		TweenService:Create(arc, TweenInfo.new(0.7), { ImageTransparency = 1 }):Play()
	end
	task.delay(0.75, function()
        if directionalPool then
            directionalPool:Return(ind)
        else
            ind:Destroy()
        end
    end)
end

-- ============================================================================
-- SCREEN FX
-- ============================================================================

function HUDController.FlashScreen(color: Color3?, duration: number?, peakTransparency: number?)
	if not flashFrame then
		return
	end
	flashFrame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = peakTransparency or 0.55
	trackTween(TweenService:Create(flashFrame, TweenInfo.new(duration or 0.35), {
		BackgroundTransparency = 1,
	})):Play()
end

function HUDController.ShowSuppression(intensity: number, duration: number?)
	if not suppressFrame then
		return
	end
	local peak = math.clamp(1 - intensity * 0.45, 0.4, 0.95)
	suppressFrame.BackgroundTransparency = peak
	trackTween(TweenService:Create(suppressFrame, TweenInfo.new(duration or 0.8), {
		BackgroundTransparency = 1,
	})):Play()
end

-- ============================================================================
-- FADE / MENUS (transient CanvasGroup)
-- ============================================================================

function HUDController.FadeFrame(
	frame: Frame,
	startTransparency: number,
	targetTransparency: number,
	duration: number,
	onComplete: (() -> ())?
)
	if activeFades[frame] then
		local old = activeFades[frame]
		for _, child in old:GetChildren() do
			child.Parent = frame
		end
		old:Destroy()
		activeFades[frame] = nil
	end

	local cg = Instance.new("CanvasGroup")
	cg.Name = frame.Name .. "_FadeCG"
	cg.Size = frame.Size
	cg.Position = frame.Position
	cg.AnchorPoint = frame.AnchorPoint
	cg.ZIndex = frame.ZIndex
	cg.LayoutOrder = frame.LayoutOrder
	cg.BackgroundColor3 = frame.BackgroundColor3
	cg.BackgroundTransparency = frame.BackgroundTransparency
	cg.BorderSizePixel = 0
	cg.GroupTransparency = startTransparency
	cg.Parent = frame.Parent
	activeFades[frame] = cg

	for _, child in frame:GetChildren() do
		child.Parent = cg
	end
	frame.Visible = false

	local tw = TweenService:Create(cg, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		GroupTransparency = targetTransparency,
	})
	trackTween(tw)
	tw:Play()
	tw.Completed:Once(function()
		if activeFades[frame] ~= cg then
			return
		end
		for _, child in cg:GetChildren() do
			child.Parent = frame
		end
		frame.Visible = targetTransparency < 0.99
		cg:Destroy()
		activeFades[frame] = nil
		if onComplete then
			onComplete()
		end
	end)
end

function HUDController.FadeIn(frame: Frame, duration: number, onComplete: (() -> ())?)
	HUDController.FadeFrame(frame, 1, 0, duration, onComplete)
end

function HUDController.FadeOut(frame: Frame, duration: number, onComplete: (() -> ())?)
	HUDController.FadeFrame(frame, 0, 1, duration, onComplete)
end

function HUDController.ToggleMenu(menuName: string, duration: number?)
	local fadeTime = duration or 0.28
	local target = menus[menuName]
	if not target or not menuRoot then
		return
	end

	if activeMenuName == menuName then
		local tw = TweenService:Create(menuRoot, THEME.Tween.Med, { GroupTransparency = 1 })
		trackTween(tw)
		tw:Play()
		tw.Completed:Once(function()
			if menuRoot then
				menuRoot.Visible = false
			end
			target.Visible = false
			activeMenuName = nil
		end)
	else
		for name, m in menus do
			m.Visible = (name == menuName)
		end
		activeMenuName = menuName
		menuRoot.Visible = true
		menuRoot.GroupTransparency = 1
		trackTween(TweenService:Create(menuRoot, THEME.Tween.Med, { GroupTransparency = 0 })):Play()
	end
end

function HUDController.GetScreenGuiContainer(containerType: ContainerType): ScreenGui?
	return containers[containerType]
end

function HUDController.IsMenuOpen(): boolean
	return activeMenuName ~= nil
end

function HUDController.SetScopeVisible(visible: boolean)
	if scopeFrame then
		scopeFrame.Visible = visible
	end
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function HUDController.Destroy()
	cancelTweens()
	disconnectAll()
	for frame, cg in activeFades do
		for _, ch in cg:GetChildren() do
			ch.Parent = frame
		end
		cg:Destroy()
	end
	table.clear(activeFades)

	for _, gui in containers do
		gui:Destroy()
	end
	table.clear(containers)
	table.clear(menus)
	table.clear(abilitySlots)

	healthFill, shieldFill, healthText, shieldText = nil, nil, nil, nil
	ammoMag, ammoReserve, weaponName, ammoContainer = nil, nil, nil, nil
	compassLabel, scoreRed, scoreBlue, roundLabel, timerLabel, phaseLabel = nil, nil, nil, nil, nil, nil
	killfeedList, menuRoot, hitmarkerRoot, vignette, flashFrame, suppressFrame, scopeFrame = nil, nil, nil, nil, nil, nil, nil
	rootMain, abilityBar, objectiveLabel, streakLabel, spectateLabel = nil, nil, nil, nil, nil
	hitmarkerPool, damageTextPool, directionalPool, killfeedPool = nil, nil, nil, nil
	_lobbyUI, _crosshair = nil, nil
	_modulesTried = false
	_initialized = false
	currentHUDMode = "Lobby"
end

return HUDController
