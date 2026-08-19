--!strict
--[=[
    Project OVERCLOCK v3: LoadoutInspectorUI (Legendary Edition)

    Armory loadout inspector — research-backed:
    - Scale-based responsive layout + UISizeConstraint [75]
    - Client-side display stats from WeaponStats (server remains authority) [74]
    - ViewportFrame + WorldModel 3D preview with orbit / auto-frame
    - Base vs modified stat bars with delta readouts
    - Full attachment matrix (optic / muzzle / underbarrel / magazine)
    - Skin finishes, equip/save, CanvasGroup fade, connection cleanup
    - THEME aligned with LobbyUIController hybrid
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: ModuleScript)

export type LoadoutConfig = {
	weaponId: string,
	skinId: string,
	attachments: {
		optic: string,
		muzzle: string,
		underbarrel: string,
		magazine: string,
	},
}

export type AttachmentSlot = "optic" | "muzzle" | "underbarrel" | "magazine"

type AttDef = {
	displayName: string,
	damageMult: number,
	recoilMult: number,
	rangeMult: number,
	mobilityMult: number,
	fireRateMult: number?,
	magMult: number?,
}

type ModStats = {
	damage: number,
	fireRate: number,
	maxRange: number,
	recoil: number,
	mobility: number,
	magazine: number?,
}

local LoadoutInspectorUI = {}

-- ============================================================================
-- THEME
-- ============================================================================

local THEME = {
	Colors = {
		Bg = Color3.fromRGB(12, 14, 18),
		Panel = Color3.fromRGB(18, 22, 28),
		PanelSoft = Color3.fromRGB(24, 30, 40),
		Accent = Color3.fromRGB(0, 210, 255),
		AccentGold = Color3.fromRGB(255, 190, 70),
		Text = Color3.fromRGB(240, 245, 250),
		TextDim = Color3.fromRGB(140, 150, 165),
		Border = Color3.fromRGB(35, 42, 55),
		BarTrack = Color3.fromRGB(25, 30, 42),
		BarFill = Color3.fromRGB(0, 200, 255),
		BarBase = Color3.fromRGB(60, 70, 90),
		Up = Color3.fromRGB(80, 220, 140),
		Down = Color3.fromRGB(255, 90, 90),
		Danger = Color3.fromRGB(180, 40, 40),
		TabIdle = Color3.fromRGB(24, 30, 42),
		TabActive = Color3.fromRGB(0, 90, 120),
	},
	Fonts = {
		Heavy = Enum.Font.GothamBlack,
		Bold = Enum.Font.GothamBold,
		Med = Enum.Font.GothamMedium,
		Body = Enum.Font.Gotham,
	},
	Tween = {
		Hover = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		Bar = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Fade = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
}

-- ============================================================================
-- DATA
-- ============================================================================

local WEAPON_TABS = {
	{ id = "Pistol", label = "PST", full = "SIDEARM" },
	{ id = "AssaultRifle", label = "AR", full = "ASSAULT RIFLE" },
	{ id = "Shotgun", label = "SHG", full = "SHOTGUN" },
	{ id = "SniperRifle", label = "SNP", full = "SNIPER" },
}

local SKINS_DATA: {
	[string]: {
		displayName: string,
		primaryColor: Color3,
		secondaryColor: Color3,
		material: Enum.Material,
		accent: Color3?,
	},
} = {
	Default = {
		displayName = "Standard Military",
		primaryColor = Color3.fromRGB(45, 50, 60),
		secondaryColor = Color3.fromRGB(20, 22, 28),
		material = Enum.Material.SmoothPlastic,
	},
	CarbonFiber = {
		displayName = "Carbon Fiber",
		primaryColor = Color3.fromRGB(25, 25, 25),
		secondaryColor = Color3.fromRGB(10, 10, 10),
		material = Enum.Material.Fabric,
	},
	NeonCyber = {
		displayName = "Neon Cyber",
		primaryColor = Color3.fromRGB(10, 30, 50),
		secondaryColor = Color3.fromRGB(0, 220, 255),
		material = Enum.Material.Neon,
		accent = Color3.fromRGB(0, 255, 200),
	},
	GoldParadigm = {
		displayName = "Gold Paradigm",
		primaryColor = Color3.fromRGB(220, 175, 40),
		secondaryColor = Color3.fromRGB(40, 35, 20),
		material = Enum.Material.Metal,
		accent = Color3.fromRGB(255, 220, 100),
	},
	CrimsonOps = {
		displayName = "Crimson Ops",
		primaryColor = Color3.fromRGB(90, 20, 28),
		secondaryColor = Color3.fromRGB(30, 12, 14),
		material = Enum.Material.Metal,
		accent = Color3.fromRGB(255, 60, 60),
	},
}

local SKIN_ORDER = { "Default", "CarbonFiber", "NeonCyber", "GoldParadigm", "CrimsonOps" }

local ATTACHMENT_OPTIONS: { [string]: { [string]: AttDef } } = {
	optic = {
		["Stock Sights"] = { displayName = "Stock Sights", damageMult = 1, recoilMult = 1, rangeMult = 1, mobilityMult = 1 },
		["Red Dot"] = { displayName = "Red Dot", damageMult = 1, recoilMult = 0.95, rangeMult = 1.05, mobilityMult = 0.99 },
		["Holographic"] = { displayName = "Holo Sight", damageMult = 1, recoilMult = 0.92, rangeMult = 1.10, mobilityMult = 0.98 },
		["Scope 4x"] = { displayName = "4× Scope", damageMult = 1, recoilMult = 0.88, rangeMult = 1.25, mobilityMult = 0.94 },
	},
	muzzle = {
		["Default Muzzle"] = { displayName = "Default", damageMult = 1, recoilMult = 1, rangeMult = 1, mobilityMult = 1 },
		["Suppressor"] = { displayName = "Suppressor", damageMult = 0.95, recoilMult = 0.85, rangeMult = 0.95, mobilityMult = 0.98 },
		["Compensator"] = { displayName = "Compensator", damageMult = 1, recoilMult = 0.80, rangeMult = 1, mobilityMult = 0.97 },
		["Muzzle Brake"] = { displayName = "Muzzle Brake", damageMult = 1, recoilMult = 0.72, rangeMult = 0.98, mobilityMult = 0.96 },
	},
	underbarrel = {
		["None"] = { displayName = "None", damageMult = 1, recoilMult = 1, rangeMult = 1, mobilityMult = 1 },
		["Vertical Grip"] = { displayName = "Vertical Grip", damageMult = 1, recoilMult = 0.75, rangeMult = 1, mobilityMult = 0.96 },
		["Angled Grip"] = { displayName = "Angled Grip", damageMult = 1, recoilMult = 0.88, rangeMult = 1, mobilityMult = 1.02 },
		["Laser Sight"] = { displayName = "Tac Laser", damageMult = 1, recoilMult = 0.95, rangeMult = 1, mobilityMult = 1.05 },
	},
	magazine = {
		["Standard"] = { displayName = "Standard", damageMult = 1, recoilMult = 1, rangeMult = 1, mobilityMult = 1, magMult = 1 },
		["Extended Mag"] = { displayName = "Extended", damageMult = 1, recoilMult = 1.02, rangeMult = 1, mobilityMult = 0.95, magMult = 1.4 },
		["Drum Mag"] = { displayName = "Drum", damageMult = 1, recoilMult = 1.06, rangeMult = 1, mobilityMult = 0.88, magMult = 2.0 },
		["Fast Mag"] = { displayName = "Fast Mag", damageMult = 1, recoilMult = 1, rangeMult = 1, mobilityMult = 1.04, magMult = 0.9, fireRateMult = 1.02 },
	},
}

local ATT_ORDER: { [string]: { string } } = {
	optic = { "Stock Sights", "Red Dot", "Holographic", "Scope 4x" },
	muzzle = { "Default Muzzle", "Suppressor", "Compensator", "Muzzle Brake" },
	underbarrel = { "None", "Vertical Grip", "Angled Grip", "Laser Sight" },
	magazine = { "Standard", "Extended Mag", "Drum Mag", "Fast Mag" },
}

local STAT_META = {
	{ key = "Damage", field = "damage", cap = 120, fmt = "int" },
	{ key = "FireRate", field = "fireRate", cap = 1000, fmt = "int" },
	{ key = "Range", field = "maxRange", cap = 2500, fmt = "int" },
	{ key = "Recoil", field = "recoil", cap = 250, fmt = "int", invertGood = true },
	{ key = "Mobility", field = "mobility", cap = 120, fmt = "pct" },
}

-- ============================================================================
-- STATE
-- ============================================================================

local currentWeaponId = "AssaultRifle"
local currentSkinId = "Default"
local currentAttachments = {
	optic = "Stock Sights",
	muzzle = "Default Muzzle",
	underbarrel = "None",
	magazine = "Standard",
}

local isInitialized = false
local screenGui: ScreenGui? = nil
local rootGroup: CanvasGroup? = nil
local inspectorFrame: Frame? = nil
local viewportFrame: ViewportFrame? = nil
local viewportCamera: Camera? = nil
local worldModel: WorldModel? = nil
local previewWeaponModel: Model? = nil
local weaponTitleLabel: TextLabel? = nil
local weaponSubLabel: TextLabel? = nil
local ttkLabel: TextLabel? = nil

local statBars: { [string]: Frame } = {}
local statBaseBars: { [string]: Frame } = {}
local statValueLabels: { [string]: TextLabel } = {}
local statDeltaLabels: { [string]: TextLabel } = {}
local weaponTabButtons: { [string]: TextButton } = {}
local cycleButtons: { [string]: TextButton } = {}
local skinSwatches: { [string]: TextButton } = {}

local renderConnection: RBXScriptConnection? = nil
local connections: { RBXScriptConnection } = {}
local activeTweens: { Tween } = {}

local autoRotate = true
local currentRotation = 0
local orbitPitch = 12
local isDragging = false
local lastDragPos: Vector2? = nil

local equipCallbacks: { (LoadoutConfig) -> () } = {}
local changeCallbacks: { (LoadoutConfig) -> () } = {}

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

local function disconnectAll()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function stroke(p: Instance, col: Color3, th: number, tr: number?)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = th
	s.Transparency = tr or 0
	s.Parent = p
	return s
end

local function playUi(name: string, vol: number?)
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

local function safeLobbyShow()
	local child = script.Parent and script.Parent:FindFirstChild("LobbyUIController")
	if child and child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		if ok and mod and mod.ShowMainLobbyMenu then
			pcall(mod.ShowMainLobbyMenu)
		end
	end
end

local function notifyChange()
	local cfg = LoadoutInspectorUI.GetSelectedLoadout()
	for _, cb in changeCallbacks do
		task.spawn(cb, cfg)
	end
end

-- ============================================================================
-- STATS
-- ============================================================================

local function getBaseDisplayStats(weaponId: string): ModStats?
	local base = WeaponStats.Get(weaponId)
	if not base then
		return nil
	end
	local recoilMag = if typeof(base.recoilImpulse) == "Vector3"
		then base.recoilImpulse.Magnitude * 1000
		else (tonumber(base.recoil) or 50)
	return {
		damage = math.round(base.damage),
		fireRate = math.round(base.fireRate),
		maxRange = math.round(base.maxRange),
		recoil = math.round(recoilMag),
		mobility = math.round((base.mobilitySpeed or 1) * 100),
		magazine = base.magazineSize or base.magSize,
	}
end

local function calculateModifiedStats(weaponId: string): (ModStats?, ModStats?)
	local baseDisp = getBaseDisplayStats(weaponId)
	local base = WeaponStats.Get(weaponId)
	if not base or not baseDisp then
		return nil, nil
	end

	local opt = ATTACHMENT_OPTIONS.optic[currentAttachments.optic]
	local muz = ATTACHMENT_OPTIONS.muzzle[currentAttachments.muzzle]
	local und = ATTACHMENT_OPTIONS.underbarrel[currentAttachments.underbarrel]
	local mag = ATTACHMENT_OPTIONS.magazine[currentAttachments.magazine]

	local function mul(key: string): number
		local v = 1
		for _, a in { opt, muz, und, mag } do
			if a then
				local m = (a :: any)[key]
				if typeof(m) == "number" then
					v *= m
				end
			end
		end
		return v
	end

	local dMult = mul("damageMult")
	local rMult = mul("recoilMult")
	local rngMult = mul("rangeMult")
	local mobMult = mul("mobilityMult")
	local frMult = mul("fireRateMult")
	if frMult == 1 then
		frMult = (opt and opt.fireRateMult or 1)
			* (muz and muz.fireRateMult or 1)
			* (und and und.fireRateMult or 1)
			* (mag and mag.fireRateMult or 1)
	end
	local magMult = (mag and mag.magMult) or 1

	local recoilMag = if typeof(base.recoilImpulse) == "Vector3"
		then base.recoilImpulse.Magnitude * 1000
		else (tonumber(base.recoil) or 50)

	local mod: ModStats = {
		damage = math.round(base.damage * dMult),
		fireRate = math.round(base.fireRate * frMult),
		maxRange = math.round(base.maxRange * rngMult),
		recoil = math.round(recoilMag * rMult),
		mobility = math.round((base.mobilitySpeed or 1) * 100 * mobMult),
		magazine = if baseDisp.magazine then math.round(baseDisp.magazine * magMult) else nil,
	}
	return mod, baseDisp
end

local function estimateTTK(stats: ModStats): string
	-- Simple display TTK vs 100 HP body (client flavor only)
	local hp = 100
	local dmg = math.max(stats.damage, 1)
	local shots = math.ceil(hp / dmg)
	local rps = stats.fireRate / 60
	if rps <= 0 then
		return "—"
	end
	local ttk = (shots - 1) / rps
	return string.format("%.2fs TTK", ttk)
end

-- ============================================================================
-- 3D PREVIEW
-- ============================================================================

local function createPreviewPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build3DWeaponPreviewModel(weaponId: string, skinId: string): Model
	local model = Instance.new("Model")
	model.Name = "Preview_" .. weaponId

	local skin = SKINS_DATA[skinId] or SKINS_DATA.Default
	local pCol, sCol, mat = skin.primaryColor, skin.secondaryColor, skin.material
	local accent = skin.accent or sCol

	local function body(wId: string)
		if wId == "Pistol" then
			local rec = createPreviewPart("Receiver", Vector3.new(0.35, 0.45, 0.9), CFrame.new(), pCol, mat, model)
			model.PrimaryPart = rec
			createPreviewPart("Slide", Vector3.new(0.32, 0.3, 0.95), CFrame.new(0, 0.2, 0.02), sCol, Enum.Material.Metal, model)
			createPreviewPart("Barrel", Vector3.new(0.18, 0.18, 0.5), CFrame.new(0, 0.15, -0.6), sCol, Enum.Material.Metal, model)
			createPreviewPart("Grip", Vector3.new(0.28, 0.7, 0.35), CFrame.new(0, -0.45, 0.2) * CFrame.Angles(math.rad(-15), 0, 0), pCol, Enum.Material.SmoothPlastic, model)
			createPreviewPart("MagBase", Vector3.new(0.26, 0.15, 0.33), CFrame.new(0, -0.8, 0.28), sCol, Enum.Material.Metal, model)
		elseif wId == "AssaultRifle" then
			local rec = createPreviewPart("Receiver", Vector3.new(0.55, 0.75, 2.4), CFrame.new(), pCol, mat, model)
			model.PrimaryPart = rec
			createPreviewPart("Handguard", Vector3.new(0.5, 0.55, 1.4), CFrame.new(0, 0, -1.6), sCol, Enum.Material.Metal, model)
			createPreviewPart("Barrel", Vector3.new(0.25, 0.25, 1.8), CFrame.new(0, 0.05, -2.8), sCol, Enum.Material.Metal, model)
			createPreviewPart("Grip", Vector3.new(0.3, 1.0, 0.35), CFrame.new(0, -0.7, -0.4) * CFrame.Angles(math.rad(-15), 0, 0), pCol, Enum.Material.SmoothPlastic, model)
			createPreviewPart("BullpupMag", Vector3.new(0.35, 1.2, 0.5), CFrame.new(0, -0.6, 0.8) * CFrame.Angles(math.rad(15), 0, 0), sCol, Enum.Material.Metal, model)
			createPreviewPart("CarryRail", Vector3.new(0.35, 0.4, 2.0), CFrame.new(0, 0.55, -0.4), Color3.fromRGB(20, 22, 28), Enum.Material.Metal, model)
		elseif wId == "SniperRifle" then
			local rec = createPreviewPart("Receiver", Vector3.new(0.65, 0.85, 2.8), CFrame.new(), pCol, mat, model)
			model.PrimaryPart = rec
			createPreviewPart("Barrel", Vector3.new(0.3, 0.3, 4.5), CFrame.new(0, 0.1, -3.6), sCol, Enum.Material.Metal, model)
			createPreviewPart("MuzzleBrake", Vector3.new(0.45, 0.45, 0.6), CFrame.new(0, 0.1, -5.9), Color3.fromRGB(20, 20, 25), Enum.Material.Metal, model)
			createPreviewPart("Stock", Vector3.new(0.45, 0.8, 1.8), CFrame.new(0, -0.05, 2.2), sCol, mat, model)
			createPreviewPart("CheekRest", Vector3.new(0.4, 0.3, 0.8), CFrame.new(0, 0.5, 2.2), Color3.fromRGB(30, 30, 35), Enum.Material.SmoothPlastic, model)
			createPreviewPart("Grip", Vector3.new(0.3, 1.1, 0.4), CFrame.new(0, -0.7, 0.8) * CFrame.Angles(math.rad(-20), 0, 0), pCol, Enum.Material.SmoothPlastic, model)
			createPreviewPart("HeavyMag", Vector3.new(0.4, 0.9, 0.7), CFrame.new(0, -0.75, -0.3), sCol, Enum.Material.Metal, model)
			createPreviewPart("ScopeBody", Vector3.new(0.45, 0.45, 1.8), CFrame.new(0, 0.75, -0.2), Color3.fromRGB(15, 15, 20), Enum.Material.Metal, model)
			createPreviewPart("ScopeLensFront", Vector3.new(0.55, 0.55, 0.1), CFrame.new(0, 0.75, -1.1), accent, Enum.Material.Neon, model)
			createPreviewPart("ScopeLensBack", Vector3.new(0.4, 0.4, 0.1), CFrame.new(0, 0.75, 0.7), accent, Enum.Material.Neon, model)
		elseif wId == "Shotgun" then
			local rec = createPreviewPart("Receiver", Vector3.new(0.55, 0.75, 2.3), CFrame.new(), pCol, mat, model)
			model.PrimaryPart = rec
			createPreviewPart("Barrel", Vector3.new(0.32, 0.32, 2.8), CFrame.new(0, 0.1, -2.4), sCol, Enum.Material.Metal, model)
			createPreviewPart("TubeMag", Vector3.new(0.28, 0.28, 2.6), CFrame.new(0, -0.18, -2.3), Color3.fromRGB(20, 22, 28), Enum.Material.Metal, model)
			createPreviewPart("PumpHandle", Vector3.new(0.4, 0.45, 1.0), CFrame.new(0, -0.1, -1.8), pCol, Enum.Material.Fabric, model)
			createPreviewPart("Stock", Vector3.new(0.4, 0.65, 1.5), CFrame.new(0, -0.05, 1.7), sCol, mat, model)
			createPreviewPart("Grip", Vector3.new(0.3, 1.0, 0.4), CFrame.new(0, -0.7, 0.6) * CFrame.Angles(math.rad(-15), 0, 0), pCol, Enum.Material.SmoothPlastic, model)
		else
			local rec = createPreviewPart("Receiver", Vector3.new(0.5, 0.7, 2.2), CFrame.new(), pCol, mat, model)
			model.PrimaryPart = rec
			createPreviewPart("Handguard", Vector3.new(0.45, 0.5, 1.6), CFrame.new(0, 0, -1.8), sCol, Enum.Material.Metal, model)
			createPreviewPart("Barrel", Vector3.new(0.2, 0.2, 2.0), CFrame.new(0, 0.05, -3.2), sCol, Enum.Material.Metal, model)
			createPreviewPart("Stock", Vector3.new(0.35, 0.6, 1.4), CFrame.new(0, -0.05, 1.6), sCol, mat, model)
			createPreviewPart("Grip", Vector3.new(0.3, 1.1, 0.4), CFrame.new(0, -0.7, 0.5) * CFrame.Angles(math.rad(-15), 0, 0), pCol, Enum.Material.SmoothPlastic, model)
			createPreviewPart("CurvedMag", Vector3.new(0.3, 1.3, 0.6), CFrame.new(0, -0.7, -0.4) * CFrame.Angles(math.rad(15), 0, 0), sCol, Enum.Material.Metal, model)
			createPreviewPart("TopRail", Vector3.new(0.3, 0.3, 1.8), CFrame.new(0, 0.5, -0.2), Color3.fromRGB(20, 22, 28), Enum.Material.Metal, model)
		end
	end

	body(weaponId)

	-- Attachment visuals
	if currentAttachments.optic ~= "Stock Sights" and weaponId ~= "SniperRifle" then
		createPreviewPart("Optic", Vector3.new(0.4, 0.4, 0.85), CFrame.new(0, 0.7, -0.15), Color3.fromRGB(15, 15, 18), Enum.Material.Metal, model)
		createPreviewPart("OpticLens", Vector3.new(0.28, 0.28, 0.08), CFrame.new(0, 0.7, -0.55), accent, Enum.Material.Neon, model)
		if currentAttachments.optic == "Scope 4x" then
			createPreviewPart("ScopeTube", Vector3.new(0.38, 0.38, 1.2), CFrame.new(0, 0.72, -0.1), Color3.fromRGB(12, 12, 16), Enum.Material.Metal, model)
		end
	end

	if currentAttachments.muzzle == "Suppressor" then
		createPreviewPart("Suppressor", Vector3.new(0.28, 0.28, 1.1), CFrame.new(0, 0.05, -3.8), Color3.fromRGB(30, 32, 38), Enum.Material.Metal, model)
	elseif currentAttachments.muzzle == "Compensator" or currentAttachments.muzzle == "Muzzle Brake" then
		createPreviewPart("MuzzleDevice", Vector3.new(0.35, 0.32, 0.45), CFrame.new(0, 0.05, -3.5), Color3.fromRGB(40, 42, 48), Enum.Material.Metal, model)
	end

	if currentAttachments.underbarrel == "Vertical Grip" then
		createPreviewPart("VGrip", Vector3.new(0.22, 0.75, 0.22), CFrame.new(0, -0.55, -0.9), sCol, Enum.Material.SmoothPlastic, model)
	elseif currentAttachments.underbarrel == "Angled Grip" then
		createPreviewPart("AGrip", Vector3.new(0.35, 0.25, 0.55), CFrame.new(0, -0.35, -0.85) * CFrame.Angles(math.rad(25), 0, 0), sCol, Enum.Material.SmoothPlastic, model)
	elseif currentAttachments.underbarrel == "Laser Sight" then
		createPreviewPart("Laser", Vector3.new(0.15, 0.15, 0.4), CFrame.new(0.2, -0.15, -1.0), accent, Enum.Material.Neon, model)
	end

	if currentAttachments.magazine == "Extended Mag" or currentAttachments.magazine == "Drum Mag" then
		local h = if currentAttachments.magazine == "Drum Mag" then 0.9 else 1.6
		local w = if currentAttachments.magazine == "Drum Mag" then 0.7 else 0.32
		createPreviewPart("MagExt", Vector3.new(w, h, 0.55), CFrame.new(0, -0.95, -0.35) * CFrame.Angles(math.rad(12), 0, 0), sCol, Enum.Material.Metal, model)
	end

	return model
end

local function frameCameraOnModel(model: Model)
	if not viewportCamera then
		return
	end
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = math.clamp(maxDim * 1.35, 4.5, 14)
	local yaw = math.rad(currentRotation)
	local pitch = math.rad(orbitPitch)
	local offset = Vector3.new(
		math.sin(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.cos(yaw) * math.cos(pitch)
	) * dist
	local focus = cf.Position
	viewportCamera.FieldOfView = 42
	viewportCamera.CFrame = CFrame.new(focus + offset, focus)
end

local function updateViewportPreview()
	if not worldModel or not viewportCamera then
		return
	end
	if previewWeaponModel then
		previewWeaponModel:Destroy()
		previewWeaponModel = nil
	end
	local model = build3DWeaponPreviewModel(currentWeaponId, currentSkinId)
	model.Parent = worldModel
	previewWeaponModel = model
	frameCameraOnModel(model)
end

local function refreshWeaponTabs()
	for id, btn in weaponTabButtons do
		local active = id == currentWeaponId
		btn.BackgroundColor3 = if active then THEME.Colors.TabActive else THEME.Colors.TabIdle
		btn.TextColor3 = if active then THEME.Colors.Accent else THEME.Colors.Text
		local st = btn:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = if active then 0.2 else 0.65
		end
	end
end

local function refreshTitles()
	local full = currentWeaponId
	for _, w in WEAPON_TABS do
		if w.id == currentWeaponId then
			full = w.full
			break
		end
	end
	if weaponTitleLabel then
		weaponTitleLabel.Text = full
	end
	if weaponSubLabel then
		local skin = SKINS_DATA[currentSkinId]
		weaponSubLabel.Text = string.format(
			"%s  ·  %s  ·  %s",
			skin and skin.displayName or currentSkinId,
			currentAttachments.optic,
			currentAttachments.muzzle
		)
	end
end

local function updateStatBars()
	local mod, base = calculateModifiedStats(currentWeaponId)
	if not mod or not base then
		return
	end

	if ttkLabel then
		ttkLabel.Text = estimateTTK(mod) .. "  (100 HP body)"
	end

	for _, meta in STAT_META do
		local modVal = (mod :: any)[meta.field] :: number
		local baseVal = (base :: any)[meta.field] :: number
		local cap = meta.cap
		local modRatio = math.clamp(modVal / cap, 0, 1)
		local baseRatio = math.clamp(baseVal / cap, 0, 1)

		local fill = statBars[meta.key]
		local baseBar = statBaseBars[meta.key]
		if fill then
			trackTween(TweenService:Create(fill, THEME.Tween.Bar, {
				Size = UDim2.new(modRatio, 0, 1, 0),
			})):Play()
		end
		if baseBar then
			trackTween(TweenService:Create(baseBar, THEME.Tween.Bar, {
				Size = UDim2.new(baseRatio, 0, 1, 0),
			})):Play()
		end

		local label = statValueLabels[meta.key]
		if label then
			if meta.fmt == "pct" then
				label.Text = tostring(modVal) .. "%"
			else
				label.Text = tostring(modVal)
			end
		end

		local deltaLbl = statDeltaLabels[meta.key]
		if deltaLbl then
			local d = modVal - baseVal
			if math.abs(d) < 0.5 then
				deltaLbl.Text = ""
			else
				local good = if meta.invertGood then d < 0 else d > 0
				deltaLbl.Text = string.format("%s%d", if d > 0 then "+" else "", math.round(d))
				deltaLbl.TextColor3 = if good then THEME.Colors.Up else THEME.Colors.Down
			end
		end
	end
end

local function refreshAll()
	updateViewportPreview()
	updateStatBars()
	refreshWeaponTabs()
	refreshTitles()
	-- cycle button labels
	if cycleButtons.skin then
		local s = SKINS_DATA[currentSkinId]
		cycleButtons.skin.Text = s and s.displayName or currentSkinId
	end
	for slot, btn in cycleButtons do
		if slot ~= "skin" and currentAttachments[slot] then
			local def = ATTACHMENT_OPTIONS[slot] and ATTACHMENT_OPTIONS[slot][currentAttachments[slot]]
			btn.Text = def and def.displayName or currentAttachments[slot]
		end
	end
	for id, sw in skinSwatches do
		local st = sw:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = if id == currentSkinId then 0 else 0.7
			st.Color = if id == currentSkinId then THEME.Colors.Accent else THEME.Colors.Border
		end
	end
	notifyChange()
end

-- ============================================================================
-- UI BUILDERS
-- ============================================================================

local function createStatRow(name: string, layoutOrder: number, parent: Instance)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.26, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Text = string.upper(name)
	title.TextColor3 = THEME.Colors.TextDim
	title.Font = THEME.Fonts.Med
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(0.48, 0, 0, 10)
	track.Position = UDim2.new(0.28, 0, 0.5, 0)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = THEME.Colors.BarTrack
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = row
	corner(track, 4)

	-- Base ghost bar (under)
	local baseFill = Instance.new("Frame")
	baseFill.Name = "BaseFill"
	baseFill.Size = UDim2.new(0, 0, 1, 0)
	baseFill.BackgroundColor3 = THEME.Colors.BarBase
	baseFill.BackgroundTransparency = 0.35
	baseFill.BorderSizePixel = 0
	baseFill.ZIndex = 1
	baseFill.Parent = track
	corner(baseFill, 4)
	statBaseBars[name] = baseFill

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = THEME.Colors.BarFill
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = track
	corner(fill, 4)
	statBars[name] = fill

	local val = Instance.new("TextLabel")
	val.Name = "Value"
	val.Size = UDim2.new(0.12, 0, 1, 0)
	val.Position = UDim2.new(0.78, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = "0"
	val.TextColor3 = THEME.Colors.Text
	val.Font = THEME.Fonts.Bold
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row
	statValueLabels[name] = val

	local delta = Instance.new("TextLabel")
	delta.Name = "Delta"
	delta.Size = UDim2.new(0.1, 0, 1, 0)
	delta.Position = UDim2.new(0.9, 0, 0, 0)
	delta.BackgroundTransparency = 1
	delta.Text = ""
	delta.Font = THEME.Fonts.Bold
	delta.TextSize = 11
	delta.TextXAlignment = Enum.TextXAlignment.Left
	delta.Parent = row
	statDeltaLabels[name] = delta
end

local function makeCycleRow(
	parent: Instance,
	name: string,
	label: string,
	y: number,
	onCycle: () -> ()
): TextButton
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.Size = UDim2.new(1, -20, 0, 34)
	row.Position = UDim2.new(0, 10, 0, y)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.28, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = THEME.Colors.TextDim
	lbl.Font = THEME.Fonts.Med
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.Name = name .. "Btn"
	btn.Size = UDim2.new(0.7, 0, 1, 0)
	btn.Position = UDim2.new(0.3, 0, 0, 0)
	btn.BackgroundColor3 = THEME.Colors.PanelSoft
	btn.Text = "—"
	btn.TextColor3 = THEME.Colors.Text
	btn.Font = THEME.Fonts.Bold
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.Parent = row
	corner(btn, 6)
	stroke(btn, THEME.Colors.Border, 1, 0.45)

	trackConn(btn.MouseEnter:Connect(function()
		TweenService:Create(btn, THEME.Tween.Hover, { BackgroundColor3 = Color3.fromRGB(36, 48, 64) }):Play()
	end))
	trackConn(btn.MouseLeave:Connect(function()
		TweenService:Create(btn, THEME.Tween.Hover, { BackgroundColor3 = THEME.Colors.PanelSoft }):Play()
	end))
	trackConn(btn.MouseButton1Click:Connect(function()
		playUi("UI_Click", 0.3)
		onCycle()
	end))

	return btn
end

-- ============================================================================
-- INIT
-- ============================================================================

function LoadoutInspectorUI.Init(parentGui: PlayerGui?)
	if isInitialized then
		LoadoutInspectorUI.Destroy()
	end

	local pGui = parentGui or LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pGui:FindFirstChild("LoadoutInspectorGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutInspectorGui"
	gui.DisplayOrder = 26
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pGui
	screenGui = gui

	-- Dim backdrop
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Parent = gui
	rootGroup = root

	local main = Instance.new("Frame")
	main.Name = "InspectorMain"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	if IS_MOBILE then
		main.Size = UDim2.new(0.96, 0, 0.92, 0)
	else
		main.Size = UDim2.new(0.72, 0, 0.78, 0)
		local sc = Instance.new("UISizeConstraint")
		sc.MinSize = Vector2.new(720, 480)
		sc.MaxSize = Vector2.new(1100, 640)
		sc.Parent = main
	end
	main.BackgroundColor3 = THEME.Colors.Bg
	main.BackgroundTransparency = 0.08
	main.BorderSizePixel = 0
	main.Parent = root
	inspectorFrame = main
	corner(main, 14)
	stroke(main, THEME.Colors.Accent, 1.6, 0.45)

	-- Header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(0.7, 0, 0, 28)
	header.Position = UDim2.new(0, 24, 0, 16)
	header.BackgroundTransparency = 1
	header.Text = "ARMORY  ·  LOADOUT INSPECTOR"
	header.TextColor3 = THEME.Colors.Accent
	header.Font = THEME.Fonts.Heavy
	header.TextSize = if IS_MOBILE then 16 else 20
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = main

	local subHead = Instance.new("TextLabel")
	subHead.Size = UDim2.new(0.7, 0, 0, 16)
	subHead.Position = UDim2.new(0, 24, 0, 44)
	subHead.BackgroundTransparency = 1
	subHead.Text = "Inspect · Configure · Equip"
	subHead.TextColor3 = THEME.Colors.TextDim
	subHead.Font = THEME.Fonts.Med
	subHead.TextSize = 12
	subHead.TextXAlignment = Enum.TextXAlignment.Left
	subHead.Parent = main

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -48, 0, 14)
	closeBtn.BackgroundColor3 = THEME.Colors.Danger
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = THEME.Colors.Text
	closeBtn.Font = THEME.Fonts.Bold
	closeBtn.TextSize = 16
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = main
	corner(closeBtn, 8)
	trackConn(closeBtn.MouseButton1Click:Connect(function()
		playUi("UI_Click", 0.3)
		LoadoutInspectorUI.Hide()
		safeLobbyShow()
	end))

	-- LEFT: viewport + tabs
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = if IS_MOBILE then UDim2.new(1, -32, 0.48, 0) else UDim2.new(0.56, -28, 1, -100)
	left.Position = UDim2.new(0, 20, 0, 72)
	left.BackgroundTransparency = 1
	left.Parent = main

	local vp = Instance.new("ViewportFrame")
	vp.Name = "WeaponViewport"
	vp.Size = UDim2.new(1, 0, 1, -88)
	vp.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	vp.BorderSizePixel = 0
	vp.Parent = left
	viewportFrame = vp
	corner(vp, 12)
	stroke(vp, THEME.Colors.Border, 1, 0.4)

	local vpCam = Instance.new("Camera")
	vpCam.FieldOfView = 42
	vpCam.Parent = vp
	vp.CurrentCamera = vpCam
	viewportCamera = vpCam

	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	worldModel = wm

	-- Soft ground disc in viewport world
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.CanCollide = false
	ground.Size = Vector3.new(12, 0.1, 12)
	ground.CFrame = CFrame.new(0, -1.4, 0)
	ground.Color = Color3.fromRGB(16, 18, 24)
	ground.Material = Enum.Material.SmoothPlastic
	ground.Transparency = 0.3
	ground.Parent = wm

	weaponTitleLabel = Instance.new("TextLabel")
	weaponTitleLabel.Size = UDim2.new(0.7, 0, 0, 22)
	weaponTitleLabel.Position = UDim2.new(0, 12, 0, 10)
	weaponTitleLabel.BackgroundTransparency = 1
	weaponTitleLabel.Font = THEME.Fonts.Heavy
	weaponTitleLabel.TextSize = 18
	weaponTitleLabel.TextColor3 = THEME.Colors.Text
	weaponTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	weaponTitleLabel.Text = "ASSAULT RIFLE"
	weaponTitleLabel.Parent = vp

	weaponSubLabel = Instance.new("TextLabel")
	weaponSubLabel.Size = UDim2.new(0.85, 0, 0, 16)
	weaponSubLabel.Position = UDim2.new(0, 12, 0, 32)
	weaponSubLabel.BackgroundTransparency = 1
	weaponSubLabel.Font = THEME.Fonts.Body
	weaponSubLabel.TextSize = 11
	weaponSubLabel.TextColor3 = THEME.Colors.TextDim
	weaponSubLabel.TextXAlignment = Enum.TextXAlignment.Left
	weaponSubLabel.Text = ""
	weaponSubLabel.Parent = vp

	local orbitHint = Instance.new("TextLabel")
	orbitHint.Size = UDim2.new(1, -16, 0, 14)
	orbitHint.Position = UDim2.new(0, 8, 1, -20)
	orbitHint.BackgroundTransparency = 1
	orbitHint.Font = THEME.Fonts.Body
	orbitHint.TextSize = 10
	orbitHint.TextColor3 = THEME.Colors.TextDim
	orbitHint.Text = if IS_MOBILE then "Drag to orbit  ·  Double-tap reset" else "Drag to orbit  ·  Scroll zoom  ·  R reset"
	orbitHint.TextXAlignment = Enum.TextXAlignment.Left
	orbitHint.Parent = vp

	-- Drag orbit on viewport
	trackConn(vp.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDragging = true
			autoRotate = false
			lastDragPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	trackConn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			isDragging = false
			lastDragPos = nil
		end
	end))
	trackConn(UserInputService.InputChanged:Connect(function(input)
		if not isDragging or not lastDragPos then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - lastDragPos
			lastDragPos = pos
			currentRotation = (currentRotation + delta.X * 0.45) % 360
			orbitPitch = math.clamp(orbitPitch + delta.Y * 0.2, -25, 55)
			if previewWeaponModel then
				frameCameraOnModel(previewWeaponModel)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and viewportCamera then
			-- FOV zoom
			viewportCamera.FieldOfView = math.clamp(viewportCamera.FieldOfView - input.Position.Z * 2, 28, 60)
		end
	end))

	-- Weapon tabs
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "WeaponTabs"
	tabs.Size = UDim2.new(1, 0, 0, 44)
	tabs.Position = UDim2.new(0, 0, 1, -48)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.ScrollBarThickness = 3
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.Parent = left

	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.Padding = UDim.new(0, 6)
	tabList.Parent = tabs

	for i, entry in WEAPON_TABS do
		local btn = Instance.new("TextButton")
		btn.Name = entry.id
		btn.Size = UDim2.new(0, if IS_MOBILE then 64 else 72, 1, -4)
		btn.BackgroundColor3 = THEME.Colors.TabIdle
		btn.Text = entry.label
		btn.TextColor3 = THEME.Colors.Text
		btn.Font = THEME.Fonts.Bold
		btn.TextSize = 11
		btn.LayoutOrder = i
		btn.AutoButtonColor = false
		btn.Parent = tabs
		corner(btn, 8)
		stroke(btn, THEME.Colors.Accent, 1.2, 0.65)
		weaponTabButtons[entry.id] = btn
		trackConn(btn.MouseButton1Click:Connect(function()
			playUi("UI_Click", 0.3)
			LoadoutInspectorUI.SelectWeapon(entry.id)
		end))
	end

	-- RIGHT: stats + config
	local right = Instance.new("Frame")
	right.Name = "Right"
	if IS_MOBILE then
		right.Size = UDim2.new(1, -32, 0.42, 0)
		right.Position = UDim2.new(0, 16, 0.55, 0)
	else
		right.Size = UDim2.new(0.4, -24, 1, -100)
		right.Position = UDim2.new(0.58, 0, 0, 72)
	end
	right.BackgroundTransparency = 1
	right.Parent = main

	local statsBox = Instance.new("Frame")
	statsBox.Name = "Stats"
	statsBox.Size = UDim2.new(1, 0, 0, 210)
	statsBox.BackgroundColor3 = THEME.Colors.Panel
	statsBox.BackgroundTransparency = 0.2
	statsBox.BorderSizePixel = 0
	statsBox.Parent = right
	corner(statsBox, 10)
	stroke(statsBox, THEME.Colors.Border, 1, 0.4)

	local stTitle = Instance.new("TextLabel")
	stTitle.Size = UDim2.new(1, -16, 0, 22)
	stTitle.Position = UDim2.new(0, 12, 0, 10)
	stTitle.BackgroundTransparency = 1
	stTitle.Text = "DYNAMIC SPECS"
	stTitle.TextColor3 = THEME.Colors.Accent
	stTitle.Font = THEME.Fonts.Bold
	stTitle.TextSize = 12
	stTitle.TextXAlignment = Enum.TextXAlignment.Left
	stTitle.Parent = statsBox

	ttkLabel = Instance.new("TextLabel")
	ttkLabel.Size = UDim2.new(1, -16, 0, 14)
	ttkLabel.Position = UDim2.new(0, 12, 0, 30)
	ttkLabel.BackgroundTransparency = 1
	ttkLabel.Text = ""
	ttkLabel.TextColor3 = THEME.Colors.AccentGold
	ttkLabel.Font = THEME.Fonts.Med
	ttkLabel.TextSize = 11
	ttkLabel.TextXAlignment = Enum.TextXAlignment.Left
	ttkLabel.Parent = statsBox

	local rows = Instance.new("Frame")
	rows.Size = UDim2.new(1, -20, 0, 150)
	rows.Position = UDim2.new(0, 10, 0, 50)
	rows.BackgroundTransparency = 1
	rows.Parent = statsBox
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 2)
	rl.Parent = rows
	for i, meta in STAT_META do
		createStatRow(meta.key, i, rows)
	end

	-- Config
	local cfg = Instance.new("Frame")
	cfg.Name = "Config"
	cfg.Size = UDim2.new(1, 0, 0, 250)
	cfg.Position = UDim2.new(0, 0, 0, 222)
	cfg.BackgroundColor3 = THEME.Colors.Panel
	cfg.BackgroundTransparency = 0.2
	cfg.BorderSizePixel = 0
	cfg.Parent = right
	corner(cfg, 10)
	stroke(cfg, THEME.Colors.Border, 1, 0.4)

	local cfgTitle = Instance.new("TextLabel")
	cfgTitle.Size = UDim2.new(1, -16, 0, 22)
	cfgTitle.Position = UDim2.new(0, 12, 0, 8)
	cfgTitle.BackgroundTransparency = 1
	cfgTitle.Text = "FINISH & ATTACHMENTS"
	cfgTitle.TextColor3 = THEME.Colors.Accent
	cfgTitle.Font = THEME.Fonts.Bold
	cfgTitle.TextSize = 12
	cfgTitle.TextXAlignment = Enum.TextXAlignment.Left
	cfgTitle.Parent = cfg

	-- Skin swatches
	local swatchRow = Instance.new("Frame")
	swatchRow.Size = UDim2.new(1, -20, 0, 28)
	swatchRow.Position = UDim2.new(0, 10, 0, 34)
	swatchRow.BackgroundTransparency = 1
	swatchRow.Parent = cfg
	local swList = Instance.new("UIListLayout")
	swList.FillDirection = Enum.FillDirection.Horizontal
	swList.Padding = UDim.new(0, 6)
	swList.Parent = swatchRow

	for _, skinId in SKIN_ORDER do
		local data = SKINS_DATA[skinId]
		local sw = Instance.new("TextButton")
		sw.Name = skinId
		sw.Size = UDim2.new(0, 28, 0, 28)
		sw.BackgroundColor3 = data.primaryColor
		sw.Text = ""
		sw.AutoButtonColor = false
		sw.Parent = swatchRow
		corner(sw, 6)
		local st = stroke(sw, THEME.Colors.Border, 2, 0.7)
		skinSwatches[skinId] = sw
		trackConn(sw.MouseButton1Click:Connect(function()
			playUi("UI_Click", 0.28)
			LoadoutInspectorUI.SelectSkin(skinId)
		end))
	end

	cycleButtons.skin = makeCycleRow(cfg, "skin", "FINISH", 70, function()
		local idx = table.find(SKIN_ORDER, currentSkinId) or 1
		LoadoutInspectorUI.SelectSkin(SKIN_ORDER[(idx % #SKIN_ORDER) + 1])
	end)

	cycleButtons.optic = makeCycleRow(cfg, "optic", "OPTIC", 108, function()
		local opts = ATT_ORDER.optic
		local idx = table.find(opts, currentAttachments.optic) or 1
		LoadoutInspectorUI.SelectAttachment("optic", opts[(idx % #opts) + 1])
	end)

	cycleButtons.muzzle = makeCycleRow(cfg, "muzzle", "MUZZLE", 146, function()
		local opts = ATT_ORDER.muzzle
		local idx = table.find(opts, currentAttachments.muzzle) or 1
		LoadoutInspectorUI.SelectAttachment("muzzle", opts[(idx % #opts) + 1])
	end)

	cycleButtons.underbarrel = makeCycleRow(cfg, "underbarrel", "GRIP", 184, function()
		local opts = ATT_ORDER.underbarrel
		local idx = table.find(opts, currentAttachments.underbarrel) or 1
		LoadoutInspectorUI.SelectAttachment("underbarrel", opts[(idx % #opts) + 1])
	end)

	cycleButtons.magazine = makeCycleRow(cfg, "magazine", "MAG", 222, function()
		local opts = ATT_ORDER.magazine
		local idx = table.find(opts, currentAttachments.magazine) or 1
		LoadoutInspectorUI.SelectAttachment("magazine", opts[(idx % #opts) + 1])
	end)

	-- Equip bar
	local equipBtn = Instance.new("TextButton")
	equipBtn.Name = "EquipBtn"
	equipBtn.Size = UDim2.new(0, if IS_MOBILE then 160 else 200, 0, 40)
	equipBtn.Position = UDim2.new(1, if IS_MOBILE then -180 else -230, 1, -52)
	equipBtn.BackgroundColor3 = THEME.Colors.Accent
	equipBtn.Text = "EQUIP LOADOUT"
	equipBtn.TextColor3 = Color3.fromRGB(10, 14, 20)
	equipBtn.Font = THEME.Fonts.Heavy
	equipBtn.TextSize = 14
	equipBtn.AutoButtonColor = false
	equipBtn.Parent = main
	corner(equipBtn, 8)
	trackConn(equipBtn.MouseEnter:Connect(function()
		TweenService:Create(equipBtn, THEME.Tween.Hover, {
			BackgroundColor3 = THEME.Colors.AccentGold,
		}):Play()
	end))
	trackConn(equipBtn.MouseLeave:Connect(function()
		TweenService:Create(equipBtn, THEME.Tween.Hover, {
			BackgroundColor3 = THEME.Colors.Accent,
		}):Play()
	end))
	trackConn(equipBtn.MouseButton1Click:Connect(function()
		playUi("UI_Click", 0.4)
		local cfgData = LoadoutInspectorUI.GetSelectedLoadout()
		for _, cb in equipCallbacks do
			task.spawn(cb, cfgData)
		end
		-- Optional remote
		local evFolder = ReplicatedStorage:FindFirstChild("Events")
		local re = evFolder and evFolder:FindFirstChild("EquipLoadout")
		if re and re:IsA("RemoteEvent") then
			re:FireServer(cfgData)
		end
	end))

	local resetBtn = Instance.new("TextButton")
	resetBtn.Size = UDim2.new(0, 100, 0, 40)
	resetBtn.Position = UDim2.new(1, if IS_MOBILE then -290 else -340, 1, -52)
	resetBtn.BackgroundColor3 = THEME.Colors.PanelSoft
	resetBtn.Text = "RESET VIEW"
	resetBtn.TextColor3 = THEME.Colors.Text
	resetBtn.Font = THEME.Fonts.Bold
	resetBtn.TextSize = 12
	resetBtn.AutoButtonColor = false
	resetBtn.Parent = main
	corner(resetBtn, 8)
	trackConn(resetBtn.MouseButton1Click:Connect(function()
		currentRotation = 35
		orbitPitch = 12
		autoRotate = true
		if viewportCamera then
			viewportCamera.FieldOfView = 42
		end
		if previewWeaponModel then
			frameCameraOnModel(previewWeaponModel)
		end
	end))

	trackConn(UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not LoadoutInspectorUI.IsVisible() then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			currentRotation = 35
			orbitPitch = 12
			autoRotate = true
			if previewWeaponModel then
				frameCameraOnModel(previewWeaponModel)
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			LoadoutInspectorUI.Hide()
			safeLobbyShow()
		end
	end))

	refreshAll()
	isInitialized = true
end

-- ============================================================================
-- SHOW / HIDE
-- ============================================================================

function LoadoutInspectorUI.Show()
	if not isInitialized then
		LoadoutInspectorUI.Init()
	end
	if not screenGui or not rootGroup then
		return
	end
	screenGui.Enabled = true
	rootGroup.GroupTransparency = 1
	trackTween(TweenService:Create(rootGroup, THEME.Tween.Fade, { GroupTransparency = 0 })):Play()

	refreshAll()

	if renderConnection then
		renderConnection:Disconnect()
	end
	currentRotation = 35
	autoRotate = true
	renderConnection = RunService.RenderStepped:Connect(function(dt)
		if autoRotate and not isDragging then
			currentRotation = (currentRotation + dt * 28) % 360
		end
		if previewWeaponModel then
			-- Keep model at origin; camera orbits
			if previewWeaponModel.PrimaryPart then
				previewWeaponModel:PivotTo(CFrame.new())
			end
			frameCameraOnModel(previewWeaponModel)
		end
	end)
end

function LoadoutInspectorUI.Hide()
	if rootGroup and screenGui and screenGui.Enabled then
		local tw = TweenService:Create(rootGroup, THEME.Tween.Fade, { GroupTransparency = 1 })
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
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	isDragging = false
end

function LoadoutInspectorUI.IsVisible(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

-- ============================================================================
-- SELECTION API
-- ============================================================================

function LoadoutInspectorUI.SelectWeapon(weaponId: string)
	if not WeaponStats.Get(weaponId) then
		warn("[LoadoutInspectorUI] Unknown weapon:", weaponId)
		return
	end
	currentWeaponId = weaponId
	refreshAll()
end

function LoadoutInspectorUI.SelectSkin(skinId: string)
	if not SKINS_DATA[skinId] then
		return
	end
	currentSkinId = skinId
	refreshAll()
end

function LoadoutInspectorUI.SelectAttachment(slotName: string, attachmentId: string)
	if not ATTACHMENT_OPTIONS[slotName] or not ATTACHMENT_OPTIONS[slotName][attachmentId] then
		return
	end
	if slotName == "optic" or slotName == "muzzle" or slotName == "underbarrel" or slotName == "magazine" then
		currentAttachments[slotName] = attachmentId
	end
	refreshAll()
end

function LoadoutInspectorUI.GetSelectedLoadout(): LoadoutConfig
	return {
		weaponId = currentWeaponId,
		skinId = currentSkinId,
		attachments = table.clone(currentAttachments),
	}
end

function LoadoutInspectorUI.ApplyLoadout(config: LoadoutConfig)
	if config.weaponId and WeaponStats.Get(config.weaponId) then
		currentWeaponId = config.weaponId
	end
	if config.skinId and SKINS_DATA[config.skinId] then
		currentSkinId = config.skinId
	end
	if config.attachments then
		for _, slot in { "optic", "muzzle", "underbarrel", "magazine" } do
			local v = (config.attachments :: any)[slot]
			if typeof(v) == "string" and ATTACHMENT_OPTIONS[slot] and ATTACHMENT_OPTIONS[slot][v] then
				(currentAttachments :: any)[slot] = v
			end
		end
	end
	if isInitialized then
		refreshAll()
	end
end

function LoadoutInspectorUI.OnEquip(cb: (LoadoutConfig) -> ()): () -> ()
	table.insert(equipCallbacks, cb)
	return function()
		local i = table.find(equipCallbacks, cb)
		if i then
			table.remove(equipCallbacks, i)
		end
	end
end

function LoadoutInspectorUI.OnChanged(cb: (LoadoutConfig) -> ()): () -> ()
	table.insert(changeCallbacks, cb)
	return function()
		local i = table.find(changeCallbacks, cb)
		if i then
			table.remove(changeCallbacks, i)
		end
	end
end

function LoadoutInspectorUI.Destroy()
	cancelTweens()
	disconnectAll()
	if screenGui then
		screenGui:Destroy()
	end
	screenGui, rootGroup, inspectorFrame = nil, nil, nil
	viewportFrame, viewportCamera, worldModel, previewWeaponModel = nil, nil, nil, nil
	table.clear(statBars)
	table.clear(statBaseBars)
	table.clear(statValueLabels)
	table.clear(statDeltaLabels)
	table.clear(weaponTabButtons)
	table.clear(cycleButtons)
	table.clear(skinSwatches)
	isInitialized = false
end

return LoadoutInspectorUI
