--!strict
--[=[
    Project OVERCLOCK: ForestOutpostMap
    Procedural 5v5 FPS Forest Outpost layout builder module.
    Generates a natural wilderness environment featuring trees with canopies/branches,
    foliage, log barricades, elevated wooden watchtowers, uneven terrain mounds,
    chokepoints, spawn locations, and objective sites.
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

local ForestOutpostMap = {}

local MAP_FOLDER_NAME = "ForestOutpostMap"
local _activeMapFolder: Folder? = nil

-- Map Dimension Constants
local MAP_WIDTH_X = 180
local MAP_LENGTH_Z = 260
local MAP_HEIGHT_Y = 35

local RED_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-15, 2, -110),
	Vector3.new(-7.5, 2, -110),
	Vector3.new(0, 2, -110),
	Vector3.new(7.5, 2, -110),
	Vector3.new(15, 2, -110),
}

local BLUE_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-15, 2, 110),
	Vector3.new(-7.5, 2, 110),
	Vector3.new(0, 2, 110),
	Vector3.new(7.5, 2, 110),
	Vector3.new(15, 2, 110),
}

local SITE_A_POSITION = Vector3.new(-55, 1, -35)
local SITE_B_POSITION = Vector3.new(55, 1, 35)

local COVER_POSITIONS: { Vector3 } = {
	-- Site A Covers
	Vector3.new(-55, 3.5, -35),
	Vector3.new(-65, 3.5, -25),
	Vector3.new(-45, 3.5, -45),
	-- Site B Covers
	Vector3.new(55, 3.5, 35),
	Vector3.new(65, 3.5, 25),
	Vector3.new(45, 3.5, 45),
	-- Mid Ridge & Chokepoints
	Vector3.new(-20, 3.5, 0),
	Vector3.new(20, 3.5, 0),
	Vector3.new(0, 3.5, -25),
	Vector3.new(0, 3.5, 25),
	-- Watchtowers (Elevated)
	Vector3.new(-50, 14, -80),
	Vector3.new(50, 14, 80),
}

local LANES_DATA: { [string]: LaneData } = {
	CentralGorge = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(28, 0.4, 170) },
	RidgePassWest = { center = Vector3.new(-55, 0.2, 0), size = Vector3.new(26, 0.4, 190) },
	EastTreeFlank = { center = Vector3.new(55, 0.2, 0), size = Vector3.new(26, 0.4, 190) },
	ChokeConnectorA = { center = Vector3.new(-28, 0.2, -35), size = Vector3.new(28, 0.4, 18) },
	ChokeConnectorB = { center = Vector3.new(28, 0.2, 35), size = Vector3.new(28, 0.4, 18) },
}

-- Helper functions
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

-- Tree builder helper
local function buildTree(name: string, basePos: Vector3, height: number, parent: Instance)
	local treeFolder = Instance.new("Folder")
	treeFolder.Name = name
	treeFolder.Parent = parent

	-- Trunk
	local trunkColor = Color3.fromRGB(85, 55, 30)
	local trunkRadius = 2.5
	createPart(
		"Trunk",
		Vector3.new(trunkRadius, height, trunkRadius),
		CFrame.new(basePos + Vector3.new(0, height / 2, 0)),
		trunkColor,
		Enum.Material.Wood,
		treeFolder
	)

	-- Branches
	local branchColor = Color3.fromRGB(75, 48, 25)
	local branchAngles = { 0, math.pi / 2, math.pi, math.pi * 1.5 }
	for idx, angle in branchAngles do
		local branchLength = 6
		local branchHeightOffset = height * 0.6 + (idx * 1.5)
		local branchCF = CFrame.new(basePos + Vector3.new(0, branchHeightOffset, 0))
			* CFrame.Angles(0, angle, 0)
			* CFrame.Angles(0, 0, math.rad(30))
			* CFrame.new(branchLength / 2, 0, 0)
		createPart(
			"Branch_" .. idx,
			Vector3.new(branchLength, 1, 1),
			branchCF,
			branchColor,
			Enum.Material.Wood,
			treeFolder
		)
	end

	-- Foliage Canopy Layer 1 (Lower Broad)
	local foliageColor = Color3.fromRGB(35, 100, 45)
	createPart(
		"Canopy_Lower",
		Vector3.new(16, 8, 16),
		CFrame.new(basePos + Vector3.new(0, height + 2, 0)),
		foliageColor,
		Enum.Material.Leaves,
		treeFolder
	)

	-- Foliage Canopy Layer 2 (Upper Cone/Mid)
	createPart(
		"Canopy_Upper",
		Vector3.new(11, 7, 11),
		CFrame.new(basePos + Vector3.new(0, height + 8, 0)),
		Color3.fromRGB(45, 120, 50),
		Enum.Material.Leaves,
		treeFolder
	)
end

-- Watchtower builder helper
local function buildWatchtower(name: string, position: Vector3, parent: Instance)
	local towerFolder = Instance.new("Folder")
	towerFolder.Name = name
	towerFolder.Parent = parent

	local legColor = Color3.fromRGB(90, 60, 35)
	local platformColor = Color3.fromRGB(110, 75, 45)
	local roofColor = Color3.fromRGB(70, 45, 25)

	local towerHeight = 14
	local platWidth = 14
	local platLength = 14

	-- 4 Support Legs
	local offsets = {
		Vector3.new(-platWidth / 2 + 1, towerHeight / 2, -platLength / 2 + 1),
		Vector3.new(platWidth / 2 - 1, towerHeight / 2, -platLength / 2 + 1),
		Vector3.new(-platWidth / 2 + 1, towerHeight / 2, platLength / 2 - 1),
		Vector3.new(platWidth / 2 - 1, towerHeight / 2, platLength / 2 - 1),
	}
	for i, legOffset in offsets do
		createPart(
			"Leg_" .. i,
			Vector3.new(1.8, towerHeight, 1.8),
			CFrame.new(position + legOffset),
			legColor,
			Enum.Material.Wood,
			towerFolder
		)
	end

	-- Elevated Platform Floor
	local platCF = CFrame.new(position + Vector3.new(0, towerHeight, 0))
	createPart(
		"PlatformFloor",
		Vector3.new(platWidth, 1.2, platLength),
		platCF,
		platformColor,
		Enum.Material.WoodPlanks,
		towerFolder
	)

	-- Railings around Platform
	local railHeight = 3.5
	local railThickness = 0.6
	createPart(
		"Railing_North",
		Vector3.new(platWidth, railHeight, railThickness),
		platCF * CFrame.new(0, railHeight / 2, -platLength / 2),
		platformColor,
		Enum.Material.Wood,
		towerFolder
	)
	createPart(
		"Railing_South",
		Vector3.new(platWidth, railHeight, railThickness),
		platCF * CFrame.new(0, railHeight / 2, platLength / 2),
		platformColor,
		Enum.Material.Wood,
		towerFolder
	)
	createPart(
		"Railing_West",
		Vector3.new(railThickness, railHeight, platLength),
		platCF * CFrame.new(-platWidth / 2, railHeight / 2, 0),
		platformColor,
		Enum.Material.Wood,
		towerFolder
	)
	createPart(
		"Railing_East",
		Vector3.new(railThickness, railHeight, platLength),
		platCF * CFrame.new(platWidth / 2, railHeight / 2, 0),
		platformColor,
		Enum.Material.Wood,
		towerFolder
	)

	-- Access Stair Ramp
	local stairLength = 18
	local stairWidth = 5
	createWedge(
		"AccessStairs",
		Vector3.new(stairWidth, towerHeight, stairLength),
		CFrame.new(position + Vector3.new(0, towerHeight / 2, -platLength / 2 - stairLength / 2)),
		platformColor,
		Enum.Material.WoodPlanks,
		towerFolder
	)

	-- Roof Structure
	createPart(
		"RoofCanopy",
		Vector3.new(platWidth + 4, 1.5, platLength + 4),
		platCF * CFrame.new(0, 9, 0),
		roofColor,
		Enum.Material.Wood,
		towerFolder
	)
end

function ForestOutpostMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Terrain Ground
	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "Perimeter"
	terrainFolder.Parent = mapFolder

	local grassColor = Color3.fromRGB(60, 110, 45)
	local dirtColor = Color3.fromRGB(95, 70, 45)
	local rockColor = Color3.fromRGB(105, 100, 95)

	-- Main Ground Base
	createPart(
		"ForestFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		grassColor,
		Enum.Material.Grass,
		terrainFolder
	)

	-- Uneven Terrain Mounds & Hills
	createPart(
		"TerrainMound_West",
		Vector3.new(45, 6, 80),
		CFrame.new(-60, 2, 0),
		grassColor,
		Enum.Material.Grass,
		terrainFolder
	)
	createPart(
		"TerrainMound_East",
		Vector3.new(45, 6, 80),
		CFrame.new(60, 2, 0),
		grassColor,
		Enum.Material.Grass,
		terrainFolder
	)
	createPart(
		"CentralGorgeRidge",
		Vector3.new(30, 4, 40),
		CFrame.new(0, 1, 0),
		dirtColor,
		Enum.Material.Ground,
		terrainFolder
	)

	-- Outer Cliff Boundary Walls
	createPart(
		"NorthCliff",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 4),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"SouthCliff",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 4),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"WestCliff",
		Vector3.new(4, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"EastCliff",
		Vector3.new(4, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)

	-- 2. Spawns Folder
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = mapFolder

	local redSpawnFolder = Instance.new("Folder")
	redSpawnFolder.Name = "RedSpawn"
	redSpawnFolder.Parent = spawnsFolder

	createPart(
		"RedOutpostBase",
		Vector3.new(40, 1, 26),
		CFrame.new(0, 0.5, -110),
		Color3.fromRGB(150, 40, 40),
		Enum.Material.WoodPlanks,
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
		"BlueOutpostBase",
		Vector3.new(40, 1, 26),
		CFrame.new(0, 0.5, 110),
		Color3.fromRGB(40, 90, 160),
		Enum.Material.WoodPlanks,
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

	-- 3. Environment Assets Folder (Trees, Watchtowers, Foliage)
	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = mapFolder

	-- Trees
	local treePositions = {
		Vector3.new(-70, 0, -90),
		Vector3.new(-35, 0, -75),
		Vector3.new(35, 0, -75),
		Vector3.new(70, 0, -90),
		Vector3.new(-75, 3, -15),
		Vector3.new(-40, 0, 20),
		Vector3.new(40, 0, -20),
		Vector3.new(75, 3, 15),
		Vector3.new(-70, 0, 90),
		Vector3.new(-35, 0, 75),
		Vector3.new(35, 0, 75),
		Vector3.new(70, 0, 90),
	}
	for i, tPos in treePositions do
		buildTree("Tree_" .. i, tPos, 16 + (i % 3) * 3, envFolder)
	end

	-- Watchtowers
	buildWatchtower("Watchtower_Red", Vector3.new(-50, 0, -80), envFolder)
	buildWatchtower("Watchtower_Blue", Vector3.new(50, 0, 80), envFolder)

	-- Fallen Logs & Foliage Patches
	local logColor = Color3.fromRGB(70, 45, 25)
	createPart(
		"FallenLog_1",
		Vector3.new(16, 2.5, 2.5),
		CFrame.new(-25, 1.25, -45) * CFrame.Angles(0, math.rad(35), math.rad(10)),
		logColor,
		Enum.Material.Wood,
		envFolder
	)
	createPart(
		"FallenLog_2",
		Vector3.new(16, 2.5, 2.5),
		CFrame.new(25, 1.25, 45) * CFrame.Angles(0, math.rad(-35), math.rad(-10)),
		logColor,
		Enum.Material.Wood,
		envFolder
	)

	-- Foliage Bushes
	local bushPositions = {
		Vector3.new(-60, 3, -40),
		Vector3.new(-50, 3, -20),
		Vector3.new(60, 3, 40),
		Vector3.new(50, 3, 20),
		Vector3.new(-10, 0.5, 0),
		Vector3.new(10, 0.5, 0),
	}
	for idx, bPos in bushPositions do
		createPart(
			"FoliageBush_" .. idx,
			Vector3.new(5, 3.5, 5),
			CFrame.new(bPos),
			Color3.fromRGB(45, 115, 40),
			Enum.Material.Leaves,
			envFolder,
			false
		)
	end

	-- 4. Objective Sites Folder
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "Sites"
	sitesFolder.Parent = mapFolder

	local siteA = createPart(
		"SiteA",
		Vector3.new(28, 0.4, 28),
		CFrame.new(SITE_A_POSITION),
		Color3.fromRGB(240, 170, 30),
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteA.Transparency = 0.5
	siteA:SetAttribute("SiteName", "A")

	local siteB = createPart(
		"SiteB",
		Vector3.new(28, 0.4, 28),
		CFrame.new(SITE_B_POSITION),
		Color3.fromRGB(240, 170, 30),
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteB.Transparency = 0.5
	siteB:SetAttribute("SiteName", "B")

	-- 5. Cover & Log Barricades Folder
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	-- Site A Log Barricades
	createPart(
		"LogBarricade_SiteA_1",
		Vector3.new(10, 3.5, 3),
		CFrame.new(-55, 3.5, -35),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)
	createPart(
		"LogBarricade_SiteA_2",
		Vector3.new(8, 3.5, 3),
		CFrame.new(-65, 3.5, -25),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)
	createPart(
		"RockCover_SiteA",
		Vector3.new(7, 6, 7),
		CFrame.new(-45, 3.5, -45),
		rockColor,
		Enum.Material.Slate,
		coverFolder
	)

	-- Site B Log Barricades
	createPart(
		"LogBarricade_SiteB_1",
		Vector3.new(10, 3.5, 3),
		CFrame.new(55, 3.5, 35),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)
	createPart(
		"LogBarricade_SiteB_2",
		Vector3.new(8, 3.5, 3),
		CFrame.new(65, 3.5, 25),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)
	createPart(
		"RockCover_SiteB",
		Vector3.new(7, 6, 7),
		CFrame.new(45, 3.5, 45),
		rockColor,
		Enum.Material.Slate,
		coverFolder
	)

	-- Mid Ridge Chokepoint Rocks & Logs
	createPart(
		"MidGorgeRock_West",
		Vector3.new(8, 7, 8),
		CFrame.new(-20, 3.5, 0),
		rockColor,
		Enum.Material.Slate,
		coverFolder
	)
	createPart(
		"MidGorgeRock_East",
		Vector3.new(8, 7, 8),
		CFrame.new(20, 3.5, 0),
		rockColor,
		Enum.Material.Slate,
		coverFolder
	)
	createPart(
		"LogStack_Mid_North",
		Vector3.new(8, 3.5, 4),
		CFrame.new(0, 3.5, -25),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)
	createPart(
		"LogStack_Mid_South",
		Vector3.new(8, 3.5, 4),
		CFrame.new(0, 3.5, 25),
		logColor,
		Enum.Material.Wood,
		coverFolder
	)

	-- 6. Lanes Folder
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = mapFolder

	for laneName, data in LANES_DATA do
		createPart(
			laneName,
			data.size,
			CFrame.new(data.center),
			Color3.fromRGB(80, 110, 65),
			Enum.Material.SmoothPlastic,
			lanesFolder,
			false
		)
	end

	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder

	return mapFolder
end

function ForestOutpostMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function ForestOutpostMap.GetSpawnPoints(teamName: string): { Vector3 }
	if teamName == "Red" then
		return table.clone(RED_SPAWN_POSITIONS)
	elseif teamName == "Blue" then
		return table.clone(BLUE_SPAWN_POSITIONS)
	else
		warn("[ForestOutpostMap] Invalid team name: " .. tostring(teamName))
		return {}
	end
end

function ForestOutpostMap.GetCoverPositions(): { Vector3 }
	return table.clone(COVER_POSITIONS)
end

function ForestOutpostMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION,
		siteB = SITE_B_POSITION,
	}
end

function ForestOutpostMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2)
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2)
	return minBounds, maxBounds
end

function ForestOutpostMap.GetLayoutData(): MapLayoutData
	local minB, maxB = ForestOutpostMap.GetMapBounds()
	return {
		mapId = "ForestOutpost",
		mapName = "Forest Outpost",
		theme = "Forest",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = table.clone(RED_SPAWN_POSITIONS),
		blueSpawns = table.clone(BLUE_SPAWN_POSITIONS),
		sites = ForestOutpostMap.GetSitePositions(),
		coverPositions = table.clone(COVER_POSITIONS),
		lanes = LANES_DATA,
	}
end

return ForestOutpostMap
