--!strict
--[[
	OVERCLOCK: PremiumWeaponViewmodel
	Place at ReplicatedStorage.Data.PremiumWeaponViewmodel beside PremiumWeaponCatalog.

	Builds client-local presentation models only. No weapon damage, ammunition,
	spread, projectiles, remotes, or authoritative state is stored here.
--]]

local Catalog = require(script.Parent:WaitForChild("PremiumWeaponCatalog") :: ModuleScript)

local PremiumWeaponViewmodel = {}

type WeaponId = Catalog.WeaponId
type SkinRole = Catalog.SkinRole

local function configureViewmodelPart(part: Part, role: SkinRole)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("SkinRole", role)
end

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	role: SkinRole,
	shape: Enum.PartType?
): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Size = size
	result.CFrame = cframe
	if shape then
		result.Shape = shape
	end
	configureViewmodelPart(result, role)
	result.Parent = model
	return result
end

local function cylinder(
	model: Model,
	name: string,
	length: number,
	diameter: number,
	cframe: CFrame,
	role: SkinRole
): Part
	return part(
		model,
		name,
		Vector3.new(length, diameter, diameter),
		cframe * CFrame.Angles(0, math.rad(90), 0),
		role,
		Enum.PartType.Cylinder
	)
end

local function addAccentStripe(model: Model, name: string, position: Vector3, length: number)
	part(model, name, Vector3.new(0.018, 0.055, length), CFrame.new(position), "Accent")
end

local function addFirePoint(model: Model, muzzle: BasePart)
	local firePoint = Instance.new("Attachment")
	firePoint.Name = "FirePoint"
	-- Cylinder length is the local X dimension; its construction rotates +X toward the barrel tip.
	firePoint.Position = Vector3.new(muzzle.Size.X * 0.5, 0, 0)
	firePoint.Parent = muzzle
end

local function addRail(model: Model, zStart: number, length: number, y: number)
	part(model, "TopRail", Vector3.new(0.16, 0.035, length), CFrame.new(0, y, zStart), "Secondary")
	for index = 1, math.max(2, math.floor(length / 0.15)) do
		local z = zStart - length * 0.5 + index * 0.14
		part(model, "RailNotch" .. tostring(index), Vector3.new(0.18, 0.03, 0.025), CFrame.new(0, y + 0.025, z), "Accent")
	end
end

local function addStock(model: Model, startZ: number, length: number, height: number)
	part(model, "StockArm", Vector3.new(0.22, height * 0.55, length), CFrame.new(0, 0.03, startZ), "Secondary")
	part(model, "StockPad", Vector3.new(0.32, height, 0.13), CFrame.new(0, -0.02, startZ + length * 0.5), "Grip")
	part(model, "StockAccent", Vector3.new(0.33, 0.06, 0.08), CFrame.new(0, height * 0.35, startZ + length * 0.5 + 0.05), "Accent")
end

local function addHoloOptic(model: Model, position: Vector3, size: Vector3)
	part(model, "OpticHousing", size, CFrame.new(position), "Secondary")
	part(model, "OpticLens", Vector3.new(size.X - 0.04, size.Y - 0.05, 0.045), CFrame.new(position + Vector3.new(0, 0, -size.Z * 0.5 - 0.025)), "Optic")
	part(model, "OpticMountFront", Vector3.new(size.X * 0.6, 0.07, 0.08), CFrame.new(position + Vector3.new(0, -size.Y * 0.5 - 0.035, -size.Z * 0.22)), "Primary")
	part(model, "OpticMountBack", Vector3.new(size.X * 0.6, 0.07, 0.08), CFrame.new(position + Vector3.new(0, -size.Y * 0.5 - 0.035, size.Z * 0.22)), "Primary")
end

local function buildAssaultRifle(model: Model)
	part(model, "Receiver", Vector3.new(0.38, 0.46, 1.65), CFrame.new(0, 0.22, -0.25), "Primary")
	part(model, "ReceiverCap", Vector3.new(0.40, 0.10, 1.58), CFrame.new(0, 0.48, -0.25), "Secondary")
	part(model, "Handguard", Vector3.new(0.42, 0.32, 0.72), CFrame.new(0, 0.13, -1.12), "Secondary")
	local muzzle = cylinder(model, "MuzzleBrake", 0.18, 0.16, CFrame.new(0, 0.25, -2.08), "Muzzle")
	cylinder(model, "Barrel", 1.18, 0.10, CFrame.new(0, 0.25, -1.48), "Primary")
	addFirePoint(model, muzzle)
	part(model, "Magazine", Vector3.new(0.24, 0.56, 0.34), CFrame.new(0, -0.25, -0.30) * CFrame.Angles(math.rad(12), 0, 0), "Grip")
	part(model, "Foregrip", Vector3.new(0.14, 0.34, 0.16), CFrame.new(0, -0.18, -1.18) * CFrame.Angles(math.rad(-10), 0, 0), "Grip")
	addStock(model, 0.92, 0.92, 0.34)
	addRail(model, -0.62, 1.35, 0.47)
	addHoloOptic(model, Vector3.new(0, 0.66, -0.40), Vector3.new(0.22, 0.18, 0.42))
	addAccentStripe(model, "ReceiverAccentLeft", Vector3.new(-0.205, 0.26, -0.42), 1.02)
	addAccentStripe(model, "ReceiverAccentRight", Vector3.new(0.205, 0.26, -0.42), 1.02)
	part(model, "EjectionPort", Vector3.new(0.02, 0.15, 0.28), CFrame.new(0.211, 0.25, 0.05), "Muzzle")
end

local function buildShotgun(model: Model)
	part(model, "ShotgunReceiver", Vector3.new(0.44, 0.48, 1.45), CFrame.new(0, 0.20, -0.05), "Primary")
	part(model, "Pump", Vector3.new(0.50, 0.30, 0.58), CFrame.new(0, -0.05, -1.34), "Grip")
	local muzzle = cylinder(model, "BreachMuzzle", 0.24, 0.26, CFrame.new(0, 0.24, -2.42), "Muzzle")
	cylinder(model, "PrimaryBarrel", 2.05, 0.15, CFrame.new(0, 0.25, -1.36), "Primary")
	cylinder(model, "TubeMagazine", 1.86, 0.13, CFrame.new(0, 0.02, -1.26), "Secondary")
	addFirePoint(model, muzzle)
	addStock(model, 0.92, 1.10, 0.42)
	part(model, "VentRib", Vector3.new(0.045, 0.04, 1.62), CFrame.new(0, 0.36, -1.43), "Accent")
	part(model, "ShellGate", Vector3.new(0.28, 0.06, 0.34), CFrame.new(0, -0.08, 0.06), "Secondary")
	part(model, "PumpAccent", Vector3.new(0.52, 0.06, 0.18), CFrame.new(0, 0.12, -1.34), "Accent")
	part(model, "IronSightFront", Vector3.new(0.045, 0.12, 0.06), CFrame.new(0, 0.43, -2.05), "Optic")
	part(model, "IronSightRear", Vector3.new(0.05, 0.10, 0.06), CFrame.new(0, 0.49, 0.34), "Optic")
end

local function buildSniperRifle(model: Model)
	part(model, "SniperReceiver", Vector3.new(0.40, 0.54, 2.25), CFrame.new(0, 0.22, -0.18), "Primary")
	part(model, "SniperHandguard", Vector3.new(0.34, 0.30, 1.10), CFrame.new(0, 0.15, -1.72), "Secondary")
	local muzzle = cylinder(model, "SuppressorMuzzle", 0.46, 0.22, CFrame.new(0, 0.26, -3.38), "Muzzle")
	cylinder(model, "PrecisionBarrel", 2.25, 0.11, CFrame.new(0, 0.26, -2.05), "Primary")
	addFirePoint(model, muzzle)
	part(model, "SniperMagazine", Vector3.new(0.26, 0.44, 0.44), CFrame.new(0, -0.24, -0.35), "Grip")
	addStock(model, 1.25, 1.34, 0.46)
	part(model, "CheekRiser", Vector3.new(0.24, 0.09, 0.72), CFrame.new(0, 0.26, 1.42), "Secondary")
	addRail(model, -0.60, 1.85, 0.54)
	cylinder(model, "ScopeBody", 1.35, 0.27, CFrame.new(0, 0.76, -0.55), "Secondary")
	cylinder(model, "ScopeFront", 0.14, 0.34, CFrame.new(0, 0.76, -1.28), "Optic")
	cylinder(model, "ScopeRear", 0.10, 0.31, CFrame.new(0, 0.76, 0.15), "Optic")
	part(model, "ScopeMountFront", Vector3.new(0.17, 0.10, 0.10), CFrame.new(0, 0.54, -0.86), "Primary")
	part(model, "ScopeMountRear", Vector3.new(0.17, 0.10, 0.10), CFrame.new(0, 0.54, -0.22), "Primary")
	for _, sign in ipairs({ -1, 1 }) do
		part(model, "BipodLeg" .. tostring(sign), Vector3.new(0.04, 0.04, 0.56), CFrame.new(sign * 0.16, -0.16, -1.86) * CFrame.Angles(math.rad(62), 0, math.rad(sign * 20)), "Secondary")
	end
	addAccentStripe(model, "SniperAccent", Vector3.new(-0.215, 0.26, -0.45), 1.45)
end

local function buildPistol(model: Model)
	part(model, "PistolFrame", Vector3.new(0.30, 0.26, 0.68), CFrame.new(0, 0.20, -0.02), "Primary")
	part(model, "PistolSlide", Vector3.new(0.33, 0.24, 0.72), CFrame.new(0, 0.43, -0.08), "Secondary")
	local muzzle = cylinder(model, "PistolMuzzle", 0.12, 0.11, CFrame.new(0, 0.32, -0.51), "Muzzle")
	addFirePoint(model, muzzle)
	part(model, "PistolGrip", Vector3.new(0.22, 0.46, 0.25), CFrame.new(0, -0.18, 0.20) * CFrame.Angles(math.rad(12), 0, 0), "Grip")
	part(model, "TriggerGuard", Vector3.new(0.18, 0.06, 0.26), CFrame.new(0, -0.02, 0.00), "Secondary")
	part(model, "MicroOptic", Vector3.new(0.18, 0.12, 0.18), CFrame.new(0, 0.60, 0.03), "Secondary")
	part(model, "MicroOpticLens", Vector3.new(0.13, 0.07, 0.025), CFrame.new(0, 0.60, -0.075), "Optic")
	part(model, "FrontSight", Vector3.new(0.035, 0.07, 0.04), CFrame.new(0, 0.59, -0.37), "Optic")
	for index = 1, 3 do
		part(model, "SlideSerration" .. tostring(index), Vector3.new(0.015, 0.13, 0.025), CFrame.new(0.175, 0.45, 0.15 - index * 0.08), "Accent")
	end
	addAccentStripe(model, "SlideAccent", Vector3.new(-0.172, 0.44, -0.09), 0.42)
end

function PremiumWeaponViewmodel.ApplySkin(model: Model, skinId: string): boolean
	local skin = Catalog.GetSkin(skinId)
	if not skin then
		return false
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local role = descendant:GetAttribute("SkinRole")
			if role == "Primary" then
				descendant.Color = skin.primaryColor
				descendant.Material = skin.primaryMaterial
			elseif role == "Secondary" then
				descendant.Color = skin.secondaryColor
				descendant.Material = skin.secondaryMaterial
			elseif role == "Grip" then
				descendant.Color = skin.secondaryColor
				descendant.Material = Enum.Material.Fabric
			elseif role == "Optic" then
				descendant.Color = skin.opticColor
				descendant.Material = Enum.Material.Glass
				descendant.Transparency = 0.15
			else
				descendant.Color = skin.accentColor
				descendant.Material = skin.accentMaterial
			end
		end
	end

	model:SetAttribute("AppliedSkin", skin.id)
	model:SetAttribute("SkinRarity", skin.rarity)
	return true
end

function PremiumWeaponViewmodel.Build(weaponId: WeaponId, skinId: string?): Model
	assert(Catalog.IsWeaponId(weaponId), "Unknown premium weapon id")
	local selectedSkin = skinId or Catalog.GetDefaultSkinId()
	assert(Catalog.IsSkinId(selectedSkin), "Unknown premium skin id")

	local model = Instance.new("Model")
	model.Name = "Premium_" .. weaponId
	model:SetAttribute("WeaponId", weaponId)
	model:SetAttribute("ViewmodelOnly", true)

	local handle = part(model, "Handle", Vector3.new(0.18, 0.48, 0.26), CFrame.new(0, -0.12, 0.38), "Grip")
	model.PrimaryPart = handle

	if weaponId == "AssaultRifle" then
		buildAssaultRifle(model)
	elseif weaponId == "Shotgun" then
		buildShotgun(model)
	elseif weaponId == "SniperRifle" then
		buildSniperRifle(model)
	else
		buildPistol(model)
	end

	PremiumWeaponViewmodel.ApplySkin(model, selectedSkin)
	return model
end

return PremiumWeaponViewmodel
