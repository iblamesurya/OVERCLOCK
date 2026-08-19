--!strict
--[[
	OVERCLOCK: PremiumWeaponCatalog
	Place at ReplicatedStorage.Data.PremiumWeaponCatalog.

	Cosmetics are intentionally separate from WeaponStats. A skin may change only
	presentation materials/colors; it must never contain gameplay modifiers.
--]]

local PremiumWeaponCatalog = {}

export type WeaponId = "AssaultRifle" | "Shotgun" | "SniperRifle" | "Pistol"
export type SkinRole = "Primary" | "Secondary" | "Accent" | "Optic" | "Muzzle" | "Grip"

export type SkinSpec = {
	id: string,
	displayName: string,
	rarity: "Epic" | "Legendary",
		primaryColor: Color3,
	secondaryColor: Color3,
	accentColor: Color3,
	opticColor: Color3,
	primaryMaterial: Enum.Material,
	secondaryMaterial: Enum.Material,
	accentMaterial: Enum.Material,
}

local WEAPON_ORDER: { WeaponId } = {
	"AssaultRifle",
	"Shotgun",
	"SniperRifle",
	"Pistol",
}

local SKIN_ORDER: { string } = {
	"ObsidianVector",
	"AuroraCircuit",
	"GildedProtocol",
	"CrimsonRelay",
	"GlacierSignal",
}

local SKINS: { [string]: SkinSpec } = {
	ObsidianVector = {
		id = "ObsidianVector",
		displayName = "Obsidian Vector",
		rarity = "Epic",
		primaryColor = Color3.fromRGB(31, 35, 43),
		secondaryColor = Color3.fromRGB(12, 15, 20),
		accentColor = Color3.fromRGB(0, 221, 255),
		opticColor = Color3.fromRGB(126, 255, 244),
		primaryMaterial = Enum.Material.Metal,
		secondaryMaterial = Enum.Material.SmoothPlastic,
		accentMaterial = Enum.Material.Neon,
	},
	AuroraCircuit = {
		id = "AuroraCircuit",
		displayName = "Aurora Circuit",
		rarity = "Legendary",
		primaryColor = Color3.fromRGB(48, 39, 94),
		secondaryColor = Color3.fromRGB(18, 20, 48),
		accentColor = Color3.fromRGB(105, 255, 197),
		opticColor = Color3.fromRGB(226, 136, 255),
		primaryMaterial = Enum.Material.Metal,
		secondaryMaterial = Enum.Material.SmoothPlastic,
		accentMaterial = Enum.Material.Neon,
	},
	GildedProtocol = {
		id = "GildedProtocol",
		displayName = "Gilded Protocol",
		rarity = "Legendary",
		primaryColor = Color3.fromRGB(185, 141, 46),
		secondaryColor = Color3.fromRGB(29, 28, 24),
		accentColor = Color3.fromRGB(255, 222, 118),
		opticColor = Color3.fromRGB(255, 244, 196),
		primaryMaterial = Enum.Material.Metal,
		secondaryMaterial = Enum.Material.SmoothPlastic,
		accentMaterial = Enum.Material.Neon,
	},
	CrimsonRelay = {
		id = "CrimsonRelay",
		displayName = "Crimson Relay",
		rarity = "Epic",
		primaryColor = Color3.fromRGB(93, 25, 36),
		secondaryColor = Color3.fromRGB(26, 15, 21),
		accentColor = Color3.fromRGB(255, 90, 70),
		opticColor = Color3.fromRGB(255, 170, 90),
		primaryMaterial = Enum.Material.Metal,
		secondaryMaterial = Enum.Material.SmoothPlastic,
		accentMaterial = Enum.Material.Neon,
	},
	GlacierSignal = {
		id = "GlacierSignal",
		displayName = "Glacier Signal",
		rarity = "Epic",
		primaryColor = Color3.fromRGB(163, 185, 202),
		secondaryColor = Color3.fromRGB(49, 67, 84),
		accentColor = Color3.fromRGB(90, 218, 255),
		opticColor = Color3.fromRGB(220, 250, 255),
		primaryMaterial = Enum.Material.Metal,
		secondaryMaterial = Enum.Material.DiamondPlate,
		accentMaterial = Enum.Material.Neon,
	},
}

local WEAPON_SET: { [string]: boolean } = {}
for _, weaponId in ipairs(WEAPON_ORDER) do
	WEAPON_SET[weaponId] = true
end

function PremiumWeaponCatalog.IsWeaponId(weaponId: any): boolean
	return type(weaponId) == "string" and WEAPON_SET[weaponId] == true
end

function PremiumWeaponCatalog.IsSkinId(skinId: any): boolean
	return type(skinId) == "string" and SKINS[skinId] ~= nil
end

function PremiumWeaponCatalog.GetSkin(skinId: string): SkinSpec?
	return SKINS[skinId]
end

function PremiumWeaponCatalog.GetSkinOrder(): { string }
	return table.clone(SKIN_ORDER)
end

function PremiumWeaponCatalog.GetWeaponOrder(): { WeaponId }
	return table.clone(WEAPON_ORDER)
end

function PremiumWeaponCatalog.GetDefaultSkinId(): string
	return "ObsidianVector"
end

function PremiumWeaponCatalog.IsCompatible(weaponId: any, skinId: any): boolean
	return PremiumWeaponCatalog.IsWeaponId(weaponId) and PremiumWeaponCatalog.IsSkinId(skinId)
end

return PremiumWeaponCatalog
