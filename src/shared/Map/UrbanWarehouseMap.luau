--!strict
--[=[
    Project OVERCLOCK: UrbanWarehouseMap
    Procedural 5v5 FPS Urban Warehouse layout builder module.
    Generates an industrial warehouse environment featuring shipping containers,
    steel crates, elevated catwalks with access stairs, heavy concrete pillars,
    interior room/rack mazes, spawn locations, and objective sites.
]=]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

export type MapBounds = {
	min: Vector3,
	max: Vector3,
}

export type SitePositions = {
	siteA: Vector3,
	siteB: Vector3,
}

export type LaneData = {
	center: Vector3,
	size: Vector3,
}

export type MapLayoutData = {
	mapId: string,
	mapName: string,
	theme: string,
	bounds: MapBounds,
	redSpawns: { Vector3 },
	blueSpawns: { Vector3 },
	sites: SitePositions,
	coverPositions: { Vector3 },
	lanes: { [string]: LaneData },
}

local UrbanWarehouseMap = {}

local MAP_FOLDER_NAME = "UrbanWarehouseMap"
local _activeMapFolder: Folder? = nil

-- Map Dimension Constants
local MAP_WIDTH_X = 170
local MAP_LENGTH_Z = 250
local MAP_HEIGHT_Y = 32

local RED_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-14, 2, -105),
	Vector3.new(-7, 2, -105),
	Vector3.new(0, 2, -105),
	Vector3.new(7, 2, -105),
	Vector3.new(14, 2, -105),
}

local BLUE_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-14, 2, 105),
	Vector3.new(-7, 2, 105),
	Vector3.new(0, 2, 105),
	Vector3.new(7, 2, 105),
	Vector3.new(14, 2, 105),
}

local SITE_A_POSITION = Vector3.new(-50, 1, -40)
local SITE_B_POSITION = Vector3.new(50, 1, 40)

local COVER_POSITIONS: { Vector3 } = {
	-- Site A Containers & Crates
	Vector3.new(-50, 5, -40),
	Vector3.new(-62, 2.5, -30),
	Vector3.new(-38, 2.5, -50),
	-- Site B Containers & Crates
	Vector3.new(50, 5, 40),
	Vector3.new(62, 2.5, 30),
	Vector3.new(38, 2.5, 50),
	-- Mid Interior Pillars & Steel Crates
	Vector3.new(-18, 6, 0),
	Vector3.new(18, 6, 0),
	Vector3.new(0, 2.5, -20),
	Vector3.new(0, 2.5, 20),
	-- Catwalk Vantage Points
	Vector3.new(-45, 14, -75),
	Vector3.new(45, 14, 75),
}

local LANES_DATA: { [string]: LaneData } = {
	CentralAisle = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(26, 0.4, 165) },
	WestStorageBay = { center = Vector3.new(-50, 0.2, 0), size = Vector3.new(28, 0.4, 185) },
	EastLoadingDock = { center = Vector3.new(50, 0.2, 0), size = Vector3.new(28, 0.4, 185) },
	RackConnectorNorth = { center = Vector3.new(-25, 0.2, -40), size = Vector3.new(26, 0.4, 16) },
	RackConnectorSouth = { center = Vector3.new(25, 0.2, 40), size = Vector3.new(26, 0.4, 16) },
}

local function createPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = if canCollide ~= nil then canCollide else true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	if part.Size.Y >= 3 and part.CollisionGroup == "Map" then
		CollectionService:AddTag(part, "BulletBlocker")
	end
	return part
end

local function createWedge(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.Anchored = true
	wedge.CanCollide = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

-- Helper to create corrugated shipping containers
local function createShippingContainer(
	name: string,
	position: Vector3,
	rotationYDeg: number,
	color: Color3,
	parent: Instance
)
	local containerFolder = Instance.new("Folder")
	containerFolder.Name = name
	containerFolder.Parent = parent

	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationYDeg), 0)
	local containerSize = Vector3.new(10, 9, 24)

	-- Main Box Body
	createPart(
		"Body",
		containerSize,
		cf * CFrame.new(0, containerSize.Y / 2, 0),
		color,
		Enum.Material.Corrugated,
		containerFolder
	)

	-- Steel End Frame Highlights
	local darkMetal = Color3.fromRGB(45, 45, 50)
	createPart(
		"FrontFrame",
		Vector3.new(containerSize.X + 0.4, containerSize.Y + 0.4, 0.8),
		cf * CFrame.new(0, containerSize.Y / 2, containerSize.Z / 2),
		darkMetal,
		Enum.Material.DiamondPlate,
		containerFolder
	)
	createPart(
		"BackFrame",
		Vector3.new(containerSize.X + 0.4, containerSize.Y + 0.4, 0.8),
		cf * CFrame.new(0, containerSize.Y / 2, -containerSize.Z / 2),
		darkMetal,
		Enum.Material.DiamondPlate,
		containerFolder
	)
end

-- Helper to create steel crates
local function createSteelCrate(
	name: string,
	size: Vector3,
	cframe: CFrame,
	parent: Instance
)
	local crateColor = Color3.fromRGB(90, 95, 100)
	local crate = createPart(
		name,
		size,
		cframe,
		crateColor,
		Enum.Material.DiamondPlate,
		parent
	)
	crate:SetAttribute("CoverType", "SteelCrate")
end

-- Helper to create elevated catwalk with stairs
local function buildCatwalk(
	name: string,
	startPos: Vector3,
	length: number,
	height: number,
	parent: Instance
)
	local catwalkFolder = Instance.new("Folder")
	catwalkFolder.Name = name
	catwalkFolder.Parent = parent

	local metalColor = Color3.fromRGB(70, 75, 80)
	local railColor = Color3.fromRGB(180, 185, 190)
	local width = 6

	-- Main Deck Platform
	local deckCF = CFrame.new(startPos + Vector3.new(0, height, length / 2))
	createPart(
		"CatwalkDeck",
		Vector3.new(width, 1, length),
		deckCF,
		metalColor,
		Enum.Material.DiamondPlate,
		catwalkFolder
	)

	-- Railings
	createPart(
		"RailingLeft",
		Vector3.new(0.5, 3.5, length),
		deckCF * CFrame.new(-width / 2 + 0.25, 2, 0),
		railColor,
		Enum.Material.Metal,
		catwalkFolder
	)
	createPart(
		"RailingRight",
		Vector3.new(0.5, 3.5, length),
		deckCF * CFrame.new(width / 2 - 0.25, 2, 0),
		railColor,
		Enum.Material.Metal,
		catwalkFolder
	)

	-- Support Columns underneath
	local numColumns = math.floor(length / 20) + 1
	for i = 0, numColumns do
		local zOffset = (i / numColumns) * length
		createPart(
			"SupportPillar_" .. i,
			Vector3.new(1.5, height, 1.5),
			CFrame.new(startPos + Vector3.new(0, height / 2, zOffset)),
			metalColor,
			Enum.Material.Metal,
			catwalkFolder
		)
	end

	-- Stair Ramp Access
	local stairLength = 16
	createWedge(
		"StairsRamp",
		Vector3.new(width, height, stairLength),
		CFrame.new(startPos + Vector3.new(0, height / 2, -stairLength / 2)),
		metalColor,
		Enum.Material.DiamondPlate,
		catwalkFolder
	)
end

function UrbanWarehouseMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Concrete Floor
	local perimeterFolder = Instance.new("Folder")
	perimeterFolder.Name = "Perimeter"
	perimeterFolder.Parent = mapFolder

	local concreteColor = Color3.fromRGB(85, 88, 92)
	local wallColor = Color3.fromRGB(65, 70, 75)

	-- Warehouse Slab Floor
	createPart(
		"WarehouseFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		concreteColor,
		Enum.Material.Concrete,
		perimeterFolder
	)

	-- Outer Reinforced Walls
	createPart(
		"NorthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		wallColor,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"SouthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		wallColor,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"WestWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallColor,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"EastWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallColor,
		Enum.Material.Concrete,
		perimeterFolder
	)

	-- Ceiling Girders (Structural Roof Trusses)
	for z = -100, 100, 40 do
		createPart(
			"RoofTruss_" .. z,
			Vector3.new(MAP_WIDTH_X, 3, 2),
			CFrame.new(0, MAP_HEIGHT_Y - 1.5, z),
			Color3.fromRGB(50, 55, 60),
			Enum.Material.Metal,
			perimeterFolder
		)
	end

	-- 2. Spawns Folder
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = mapFolder

	local redSpawnFolder = Instance.new("Folder")
	redSpawnFolder.Name = "RedSpawn"
	redSpawnFolder.Parent = spawnsFolder

	createPart(
		"RedLoadingBayPad",
		Vector3.new(38, 1, 24),
		CFrame.new(0, 0.5, -105),
		Color3.fromRGB(170, 50, 50),
		Enum.Material.DiamondPlate,
		redSpawnFolder
	)

	for i, pos in RED_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(230, 80, 80),
			Enum.Material.Neon,
			redSpawnFolder,
			false
		)
		sp:SetAttribute("Team", "Red")
		sp:SetAttribute("Index", i)
	end

	local blueSpawnFolder = Instance.new("Folder")
	blueSpawnFolder.Name = "BlueSpawn"
	blueSpawnFolder.Parent = spawnsFolder

	createPart(
		"BlueOfficePad",
		Vector3.new(38, 1, 24),
		CFrame.new(0, 0.5, 105),
		Color3.fromRGB(50, 100, 170),
		Enum.Material.DiamondPlate,
		blueSpawnFolder
	)

	for i, pos in BLUE_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(80, 140, 230),
			Enum.Material.Neon,
			blueSpawnFolder,
			false
		)
		sp:SetAttribute("Team", "Blue")
		sp:SetAttribute("Index", i)
	end

	-- 3. Environment Assets Folder (Containers, Pillars, Catwalks, Interior Maze)
	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = mapFolder

	-- Shipping Containers (Red, Blue, Yellow, Teal)
	createShippingContainer("Container_Red_1", Vector3.new(-50, 0, -40), 15, Color3.fromRGB(180, 45, 45), envFolder)
	createShippingContainer("Container_Blue_1", Vector3.new(50, 0, 40), -15, Color3.fromRGB(45, 90, 180), envFolder)
	createShippingContainer("Container_Yellow_1", Vector3.new(-55, 0, 30), 90, Color3.fromRGB(200, 160, 40), envFolder)
	createShippingContainer("Container_Teal_1", Vector3.new(55, 0, -30), -90, Color3.fromRGB(40, 160, 150), envFolder)

	-- Stacked Upper Containers
	createShippingContainer("Container_Red_Upper", Vector3.new(-50, 9, -40), 15, Color3.fromRGB(160, 40, 40), envFolder)
	createShippingContainer("Container_Blue_Upper", Vector3.new(50, 9, 40), -15, Color3.fromRGB(40, 80, 160), envFolder)

	-- Heavy Concrete Interior Support Pillars
	local pillarPositions = {
		Vector3.new(-18, 16, -60),
		Vector3.new(18, 16, -60),
		Vector3.new(-18, 16, 0),
		Vector3.new(18, 16, 0),
		Vector3.new(-18, 16, 60),
		Vector3.new(18, 16, 60),
	}
	for i, pPos in pillarPositions do
		createPart(
			"ConcretePillar_" .. i,
			Vector3.new(6, 32, 6),
			CFrame.new(pPos),
			Color3.fromRGB(100, 105, 110),
			Enum.Material.Concrete,
			envFolder
		)
	end

	-- Elevated Catwalks with Stairs
	buildCatwalk("Catwalk_West", Vector3.new(-45, 0, -80), 60, 14, envFolder)
	buildCatwalk("Catwalk_East", Vector3.new(45, 0, 20), 60, 14, envFolder)

	-- Storage Rack Partition Maze Walls
	local rackColor = Color3.fromRGB(110, 75, 40)
	createPart(
		"StorageRack_North_1",
		Vector3.new(24, 10, 4),
		CFrame.new(-30, 5, -70),
		rackColor,
		Enum.Material.WoodPlanks,
		envFolder
	)
	createPart(
		"StorageRack_North_2",
		Vector3.new(24, 10, 4),
		CFrame.new(30, 5, -70),
		rackColor,
		Enum.Material.WoodPlanks,
		envFolder
	)
	createPart(
		"StorageRack_South_1",
		Vector3.new(24, 10, 4),
		CFrame.new(-30, 5, 70),
		rackColor,
		Enum.Material.WoodPlanks,
		envFolder
	)
	createPart(
		"StorageRack_South_2",
		Vector3.new(24, 10, 4),
		CFrame.new(30, 5, 70),
		rackColor,
		Enum.Material.WoodPlanks,
		envFolder
	)

	-- 4. Sites Folder
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "Sites"
	sitesFolder.Parent = mapFolder

	local siteA = createPart(
		"SiteA",
		Vector3.new(30, 0.4, 30),
		CFrame.new(SITE_A_POSITION),
		Color3.fromRGB(240, 180, 40),
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteA.Transparency = 0.5
	siteA:SetAttribute("SiteName", "A")

	local siteB = createPart(
		"SiteB",
		Vector3.new(30, 0.4, 30),
		CFrame.new(SITE_B_POSITION),
		Color3.fromRGB(240, 180, 40),
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteB.Transparency = 0.5
	siteB:SetAttribute("SiteName", "B")

	-- 5. Cover & Steel Crates Folder
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	-- Steel Crates around Site A
	createSteelCrate("SteelCrate_SiteA_1", Vector3.new(5, 5, 5), CFrame.new(-62, 2.5, -30), coverFolder)
	createSteelCrate("SteelCrate_SiteA_2", Vector3.new(6, 5, 4), CFrame.new(-38, 2.5, -50), coverFolder)

	-- Steel Crates around Site B
	createSteelCrate("SteelCrate_SiteB_1", Vector3.new(5, 5, 5), CFrame.new(62, 2.5, 30), coverFolder)
	createSteelCrate("SteelCrate_SiteB_2", Vector3.new(6, 5, 4), CFrame.new(38, 2.5, 50), coverFolder)

	-- Mid Aisle Steel Crates
	createSteelCrate("SteelCrate_Mid_1", Vector3.new(7, 5, 5), CFrame.new(0, 2.5, -20), coverFolder)
	createSteelCrate("SteelCrate_Mid_2", Vector3.new(7, 5, 5), CFrame.new(0, 2.5, 20), coverFolder)

	-- 6. Lanes Folder
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = mapFolder

	for laneName, data in LANES_DATA do
		createPart(
			laneName,
			data.size,
			CFrame.new(data.center),
			Color3.fromRGB(100, 105, 110),
			Enum.Material.SmoothPlastic,
			lanesFolder,
			false
		)
	end

	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder

	return mapFolder
end

function UrbanWarehouseMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function UrbanWarehouseMap.GetSpawnPoints(teamName: string): { Vector3 }
	if teamName == "Red" then
		return table.clone(RED_SPAWN_POSITIONS)
	elseif teamName == "Blue" then
		return table.clone(BLUE_SPAWN_POSITIONS)
	else
		warn("[UrbanWarehouseMap] Invalid team name: " .. tostring(teamName))
		return {}
	end
end

function UrbanWarehouseMap.GetCoverPositions(): { Vector3 }
	return table.clone(COVER_POSITIONS)
end

function UrbanWarehouseMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION,
		siteB = SITE_B_POSITION,
	}
end

function UrbanWarehouseMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2)
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2)
	return minBounds, maxBounds
end

function UrbanWarehouseMap.GetLayoutData(): MapLayoutData
	local minB, maxB = UrbanWarehouseMap.GetMapBounds()
	return {
		mapId = "UrbanWarehouse",
		mapName = "Urban Warehouse",
		theme = "Urban",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = table.clone(RED_SPAWN_POSITIONS),
		blueSpawns = table.clone(BLUE_SPAWN_POSITIONS),
		sites = UrbanWarehouseMap.GetSitePositions(),
		coverPositions = table.clone(COVER_POSITIONS),
		lanes = LANES_DATA,
	}
end

return UrbanWarehouseMap
