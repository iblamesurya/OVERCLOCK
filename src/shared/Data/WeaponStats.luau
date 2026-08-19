--!strict
--[=[
    Project OVERCLOCK: Weapon Statistics Registry
    Centralized data module defining weapon parameters, recoil characteristics,
    fire modes, mobility multipliers, ballistic constants, skins, and attachment modifiers.
]=]

export type FireMode = "Semi" | "Auto" | "Burst"

export type ScopeConfiguration = {
	FieldOfView: number,
	FocusDistance: number,
	SensitivityScalar: number,
	ScopeImageId: string?, -- If nil, just standard iron sights FOV zoom without 2D overlay
}

export type WeaponData = {
	id: string,
	displayName: string,
	damage: number,
	headshotMultiplier: number,
	fireRate: number, -- Shots per minute (RPM)
	spreadMin: number, -- Minimum spread angle in degrees
	spreadMax: number, -- Maximum spread angle in degrees
	spreadIncreasePerShot: number, -- Added spread per fired round
	spreadRecoveryRate: number, -- Spread recovery speed in degrees/sec
	recoilImpulse: Vector3, -- Pitch, Yaw, Roll/Kick impulse vector
	recoilImpulseADS: Vector3, -- Recoil impulse vector when Aiming Down Sights
	mobilitySpeed: number, -- Walk speed multiplier (0.0 to 1.0)
	reloadDuration: number, -- Full reload time in seconds
	fireMode: FireMode,
	magazineCapacity: number,
	reserveCapacity: number,
	bulletVelocity: number, -- Studs per second
	maxRange: number, -- Maximum effective range in studs
	adsFov: number, -- Camera FOV when ADS (legacy fallback)
	zoomSpeed: number, -- Exponential decay transition speed for ADS
	burstCount: number?, -- Shots per burst if fireMode is "Burst"
	burstDelay: number?, -- Cooldown between bursts in seconds
	scopeConfig: ScopeConfiguration?, -- Advanced ADS Architecture configuration
}

export type AttachmentSpec = {
	displayName: string,
	damageMult: number?,
	recoilMult: number?,
	rangeMult: number?,
	mobilityMult: number?,
}

export type AttachmentsState = {
	optic: string,
	muzzle: string,
	underbarrel: string,
	magazine: string,
}

export type SkinSpec = {
	displayName: string,
	primaryColor: Color3,
	secondaryColor: Color3,
	material: Enum.Material,
}

export type ModifiedWeaponData = WeaponData & {
	recoil: number,
	mobility: number,
	damageMult: number,
	recoilMult: number,
	rangeMult: number,
	mobilityMult: number,
}

export type ArmorData = {
	id: string,
	displayName: string,
	shield: number,
	cost: number,
}

local ArmorRegistry: { [string]: ArmorData } = {
	LightArmor = {
		id = "LightArmor",
		displayName = "Light Armor",
		shield = 25,
		cost = 400,
	},
	HeavyArmor = {
		id = "HeavyArmor",
		displayName = "Heavy Armor",
		shield = 50,
		cost = 1000,
	},
}

local WeaponRegistry: { [string]: WeaponData } = {
	Pistol = {
		id = "Pistol",
		displayName = "OC-P9 Sidearm",
		damage = 24,
		headshotMultiplier = 2.0,
		fireRate = 450,
		spreadMin = 0.3,
		spreadMax = 2.5,
		spreadIncreasePerShot = 0.35,
		spreadRecoveryRate = 8.0,
		recoilImpulse = Vector3.new(0.025, 0.010, 0.030),
		recoilImpulseADS = Vector3.new(0.012, 0.005, 0.015),
		mobilitySpeed = 1.00,
		reloadDuration = 1.4,
		fireMode = "Semi",
		magazineCapacity = 12,
		reserveCapacity = 60,
		bulletVelocity = 2000,
		maxRange = 500,
		adsFov = 65,
		zoomSpeed = 16,
	},
	AssaultRifle = {
		id = "AssaultRifle",
		displayName = "OC-Vanguard AR",
		damage = 32,
		headshotMultiplier = 2.5,
		fireRate = 600,
		spreadMin = 0.3,
		spreadMax = 3.0,
		spreadIncreasePerShot = 0.3,
		spreadRecoveryRate = 6.0,
		recoilImpulse = Vector3.new(0.035, 0.015, 0.060),
		recoilImpulseADS = Vector3.new(0.018, 0.008, 0.030),
		mobilitySpeed = 0.95,
		reloadDuration = 2.2,
		fireMode = "Auto",
		magazineCapacity = 30,
		reserveCapacity = 120,
		bulletVelocity = 2600,
		maxRange = 1000,
		adsFov = 55,
		zoomSpeed = 14,
		scopeConfig = {
			FieldOfView = 50,
			FocusDistance = 100,
			SensitivityScalar = 0.6,
			ScopeImageId = nil, -- No overlay, just FOV zoom and DoF blur
		},
	},
	SniperRifle = {
		id = "SniperRifle",
		displayName = "OC-Apex Sniper",
		damage = 105,
		headshotMultiplier = 2.5,
		fireRate = 45,
		spreadMin = 0.05,
		spreadMax = 8.0,
		spreadIncreasePerShot = 2.0,
		spreadRecoveryRate = 4.0,
		recoilImpulse = Vector3.new(0.160, 0.040, 0.220),
		recoilImpulseADS = Vector3.new(0.080, 0.020, 0.120),
		mobilitySpeed = 0.82,
		reloadDuration = 3.5,
		fireMode = "Semi",
		magazineCapacity = 5,
		reserveCapacity = 25,
		bulletVelocity = 4000,
		maxRange = 2500,
		adsFov = 25,
		zoomSpeed = 10,
		scopeConfig = {
			FieldOfView = 20, -- 20 FOV for intense zoom
			FocusDistance = 50, -- Standard focal distance (will be dynamically updated by raycast)
			SensitivityScalar = 0.2, -- 20% of base sensitivity
			ScopeImageId = "rbxassetid://13476307137", -- Crosshair overlay
		},
	},
	Shotgun = {
		id = "Shotgun",
		displayName = "OC-Enforcer Shotgun",
		damage = 80,
		headshotMultiplier = 2.0,
		fireRate = 100,
		spreadMin = 1.5,
		spreadMax = 6.0,
		spreadIncreasePerShot = 1.0,
		spreadRecoveryRate = 5.0,
		recoilImpulse = Vector3.new(0.120, 0.050, 0.150),
		recoilImpulseADS = Vector3.new(0.080, 0.030, 0.100),
		mobilitySpeed = 0.90,
		reloadDuration = 2.8,
		fireMode = "Semi",
		magazineCapacity = 6,
		reserveCapacity = 24,
		bulletVelocity = 1500,
		maxRange = 350,
		adsFov = 65,
		zoomSpeed = 14,
	},
	Grenade = {
		id = "Grenade",
		displayName = "Frag Grenade",
		damage = 120,
		headshotMultiplier = 1.0,
		fireRate = 30,
		spreadMin = 0.1,
		spreadMax = 0.1,
		spreadIncreasePerShot = 0.0,
		spreadRecoveryRate = 1.0,
		recoilImpulse = Vector3.new(0, 0, 0),
		recoilImpulseADS = Vector3.new(0, 0, 0),
		mobilitySpeed = 1.00,
		reloadDuration = 1.0,
		fireMode = "Semi",
		magazineCapacity = 1,
		reserveCapacity = 3,
		bulletVelocity = 800,
		maxRange = 300,
		adsFov = 70,
		zoomSpeed = 10,
	}
}

-- Centralized Skins Registry — 12 production skins (Color3 + Material variety, no placeholder rbxassetid)
local SKINS_DATA: { [string]: SkinSpec } = {
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
	},
	GoldParadigm = {
		displayName = "Gold Paradigm",
		primaryColor = Color3.fromRGB(220, 175, 40),
		secondaryColor = Color3.fromRGB(40, 35, 20),
		material = Enum.Material.Metal,
	},
	ArcticTide = {
		displayName = "Arctic Tide",
		primaryColor = Color3.fromRGB(200, 230, 255),
		secondaryColor = Color3.fromRGB(120, 160, 200),
		material = Enum.Material.Granite,
	},
	CrimsonDusk = {
		displayName = "Crimson Dusk",
		primaryColor = Color3.fromRGB(140, 20, 30),
		secondaryColor = Color3.fromRGB(40, 10, 15),
		material = Enum.Material.SmoothPlastic,
	},
	OliveTactical = {
		displayName = "Olive Tactical",
		primaryColor = Color3.fromRGB(85, 95, 60),
		secondaryColor = Color3.fromRGB(45, 50, 35),
		material = Enum.Material.Wood,
	},
	GraphiteStealth = {
		displayName = "Graphite Stealth",
		primaryColor = Color3.fromRGB(50, 55, 60),
		secondaryColor = Color3.fromRGB(25, 28, 32),
		material = Enum.Material.Slate,
	},
	PrismPulse = {
		displayName = "Prism Pulse",
		primaryColor = Color3.fromRGB(120, 40, 180),
		secondaryColor = Color3.fromRGB(0, 200, 200),
		material = Enum.Material.Neon,
	},
	AshenWood = {
		displayName = "Ashen Wood",
		primaryColor = Color3.fromRGB(110, 85, 65),
		secondaryColor = Color3.fromRGB(60, 45, 35),
		material = Enum.Material.WoodPlanks,
	},
	GraniteSlate = {
		displayName = "Granite Slate",
		primaryColor = Color3.fromRGB(95, 95, 100),
		secondaryColor = Color3.fromRGB(55, 55, 60),
		material = Enum.Material.Concrete,
	},
	ForcefieldEcho = {
		displayName = "Forcefield Echo",
		primaryColor = Color3.fromRGB(40, 180, 255),
		secondaryColor = Color3.fromRGB(10, 40, 80),
		material = Enum.Material.ForceField,
	},
}

-- Centralized Attachment Categories & Options
local ATTACHMENT_OPTIONS: { [string]: { [string]: AttachmentSpec } } = {
	optic = {
		["Stock Sights"] = { displayName = "Stock Sights", damageMult = 1.0, recoilMult = 1.0, rangeMult = 1.0, mobilityMult = 1.0 },
		["Red Dot"] = { displayName = "Red Dot Sight", damageMult = 1.0, recoilMult = 0.95, rangeMult = 1.05, mobilityMult = 0.99 },
		["Holographic"] = { displayName = "Holo Sight", damageMult = 1.0, recoilMult = 0.92, rangeMult = 1.10, mobilityMult = 0.98 },
		["Scope 4x"] = { displayName = "4x Scope", damageMult = 1.0, recoilMult = 0.88, rangeMult = 1.25, mobilityMult = 0.94 },
	},
	muzzle = {
		["Default Muzzle"] = { displayName = "Default Muzzle", damageMult = 1.0, recoilMult = 1.0, rangeMult = 1.0, mobilityMult = 1.0 },
		["Suppressor"] = { displayName = "Tactical Suppressor", damageMult = 0.95, recoilMult = 0.85, rangeMult = 0.95, mobilityMult = 0.98 },
		["Compensator"] = { displayName = "Compensator", damageMult = 1.0, recoilMult = 0.80, rangeMult = 1.0, mobilityMult = 0.97 },
	},
	underbarrel = {
		["None"] = { displayName = "None", damageMult = 1.0, recoilMult = 1.0, rangeMult = 1.0, mobilityMult = 1.0 },
		["Vertical Grip"] = { displayName = "Vertical Grip", damageMult = 1.0, recoilMult = 0.75, rangeMult = 1.0, mobilityMult = 0.96 },
		["Tac Laser"] = { displayName = "Tac Laser", damageMult = 1.0, recoilMult = 0.95, rangeMult = 1.0, mobilityMult = 1.05 },
	},
	magazine = {
		["Standard"] = { displayName = "Standard Mag", damageMult = 1.0, recoilMult = 1.0, rangeMult = 1.0, mobilityMult = 1.0 },
		["Extended Mag"] = { displayName = "Extended Mag", damageMult = 1.0, recoilMult = 1.02, rangeMult = 1.0, mobilityMult = 0.95 },
	},
}

local WeaponStats = {}

WeaponStats.SKINS_DATA = SKINS_DATA
WeaponStats.ATTACHMENT_OPTIONS = ATTACHMENT_OPTIONS

local _warnedUnknown: { [string]: boolean } = {}
function WeaponStats.Get(weaponId: string): WeaponData?
	local data = WeaponRegistry[weaponId]
	if not data and weaponId == "SMG" then
		data = WeaponRegistry.Pistol
	end
	if not data then
		-- Quiet once per unknown id to avoid 6× spam per client → lag
		if not _warnedUnknown[weaponId] then
			_warnedUnknown[weaponId] = true
			warn(string.format("[WeaponStats] Unknown weaponId requested (first occurrence): %s", tostring(weaponId)))
		end
		return nil
	end
	return data
end

function WeaponStats.GetAll(): { [string]: WeaponData }
	return WeaponRegistry
end

function WeaponStats.GetArmor(armorId: string): ArmorData?
	return ArmorRegistry[armorId]
end

function WeaponStats.GetAllArmor(): { [string]: ArmorData }
	return ArmorRegistry
end

function WeaponStats.GetModifiedStats(
	weaponId: string,
	attachments: { optic: string?, muzzle: string?, underbarrel: string?, magazine: string? }?
): ModifiedWeaponData?
	local base = WeaponStats.Get(weaponId)
	if not base then
		warn(string.format("[WeaponStats] Unknown weaponId in GetModifiedStats: %s", tostring(weaponId)))
		return nil
	end

	local atts = attachments or {}
	local opticKey = atts.optic or "Stock Sights"
	local muzzleKey = atts.muzzle or "Default Muzzle"
	local underbarrelKey = atts.underbarrel or "None"
	local magazineKey = atts.magazine or "Standard"

	local opt = ATTACHMENT_OPTIONS.optic[opticKey] or ATTACHMENT_OPTIONS.optic["Stock Sights"]
	local muz = ATTACHMENT_OPTIONS.muzzle[muzzleKey] or ATTACHMENT_OPTIONS.muzzle["Default Muzzle"]
	local und = ATTACHMENT_OPTIONS.underbarrel[underbarrelKey] or ATTACHMENT_OPTIONS.underbarrel["None"]
	local mag = ATTACHMENT_OPTIONS.magazine[magazineKey] or ATTACHMENT_OPTIONS.magazine["Standard"]

	local dMult = (opt.damageMult or 1.0) * (muz.damageMult or 1.0) * (und.damageMult or 1.0) * (mag.damageMult or 1.0)
	local rMult = (opt.recoilMult or 1.0) * (muz.recoilMult or 1.0) * (und.recoilMult or 1.0) * (mag.recoilMult or 1.0)
	local rngMult = (opt.rangeMult or 1.0) * (muz.rangeMult or 1.0) * (und.rangeMult or 1.0) * (mag.rangeMult or 1.0)
	local mobMult = (opt.mobilityMult or 1.0) * (muz.mobilityMult or 1.0) * (und.mobilityMult or 1.0) * (mag.mobilityMult or 1.0)

	local recoilMag = base.recoilImpulse.Magnitude * 1000

	local result: ModifiedWeaponData = {
		id = base.id,
		displayName = base.displayName,
		damage = math.round(base.damage * dMult),
		headshotMultiplier = base.headshotMultiplier,
		fireRate = base.fireRate,
		spreadMin = base.spreadMin,
		spreadMax = base.spreadMax,
		spreadIncreasePerShot = base.spreadIncreasePerShot,
		spreadRecoveryRate = base.spreadRecoveryRate,
		recoilImpulse = base.recoilImpulse * rMult,
		recoilImpulseADS = base.recoilImpulseADS * rMult,
		mobilitySpeed = base.mobilitySpeed * mobMult,
		reloadDuration = base.reloadDuration,
		fireMode = base.fireMode,
		magazineCapacity = base.magazineCapacity,
		reserveCapacity = base.reserveCapacity,
		bulletVelocity = base.bulletVelocity,
		maxRange = math.round(base.maxRange * rngMult),
		adsFov = base.adsFov,
		zoomSpeed = base.zoomSpeed,
		burstCount = base.burstCount,
		burstDelay = base.burstDelay,
		recoil = math.round(recoilMag * rMult),
		mobility = math.round(base.mobilitySpeed * 100 * mobMult),
		damageMult = dMult,
		recoilMult = rMult,
		rangeMult = rngMult,
		mobilityMult = mobMult,
	}

	return result
end

function WeaponStats.CalculateDamage(weaponId: string, isHeadshot: boolean, distance: number): number
	local stats = WeaponStats.Get(weaponId)
	if not stats then
		return 0
	end

	local baseDamage = stats.damage
	local mult = isHeadshot and stats.headshotMultiplier or 1.0

	-- Distance falloff calculation (linear dropoff past maxRange * 0.5)
	local falloffStart = stats.maxRange * 0.5
	local damageScale = 1.0

	if distance > falloffStart then
		local excess = distance - falloffStart
		local falloffRange = stats.maxRange - falloffStart
		if falloffRange <= 0 then
			return math.floor(baseDamage * mult + 0.5)
		end
		local falloffPercent = math.clamp(excess / falloffRange, 0, 0.6) -- Max 60% reduction
		damageScale = 1.0 - falloffPercent
	end

	return math.floor(baseDamage * mult * damageScale + 0.5)
end

return WeaponStats

