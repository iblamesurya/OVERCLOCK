--!strict
--[=[
    Project OVERCLOCK: DesertRuinsMap
    Procedural 5v5 FPS Desert Ruins layout builder module.
    Generates an ancient desert archaeological environment featuring sandstone pillars,
    ancient grand arches, sand dunes, crumbling stone walls, open courtyards with
    long sightlines and cover, spawn locations, and objective sites.
]=]

local Workspace = game:GetService("Workspace")

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

local DesertRuinsMap = {}

local MAP_FOLDER_NAME = "DesertRuinsMap"
local _activeMapFolder: Folder? = nil

-- Map Dimension Constants
local MAP_WIDTH_X = 180
local MAP_LENGTH_Z = 260
local MAP_HEIGHT_Y = 36

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

local SITE_A_POSITION = Vector3.new(-55, 1, -40)
local SITE_B_POSITION = Vector3.new(55, 1, 40)

local COVER_POSITIONS: { Vector3 } = {
	-- Site A Crumbling Walls & Pillars
	Vector3.new(-55, 4, -40),
	Vector3.new(-68, 3, -30),
	Vector3.new(-42, 3, -52),
	-- Site B Crumbling Walls & Pillars
	Vector3.new(55, 4, 40),
	Vector3.new(68, 3, 30),
	Vector3.new(42, 3, 52),
	-- Mid Oasis & Sunken Plaza Cover
	Vector3.new(-22, 5, 0),
	Vector3.new(22, 5, 0),
	Vector3.new(0, 3.5, -25),
	Vector3.new(0, 3.5, 25),
	-- Archway High Perches
	Vector3.new(-50, 16, -80),
	Vector3.new(50, 16, 80),
}

local LANES_DATA: { [string]: LaneData } = {
	SunkenPlaza = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(30, 0.4, 170) },
	ColonnadeWest = { center = Vector3.new(-55, 0.2, 0), size = Vector3.new(26, 0.4, 190) },
	DuneFlankEast = { center = Vector3.new(55, 0.2, 0), size = Vector3.new(26, 0.4, 190) },
	ArchPassA = { center = Vector3.new(-28, 0.2, -40), size = Vector3.new(28, 0.4, 18) },
	ArchPassB = { center = Vector3.new(28, 0.2, 40), size = Vector3.new(28, 0.4, 18) },
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

-- Helper to create sandstone pillars (standing or broken)
local function buildSandstonePillar(
	name: string,
	position: Vector3,
	height: number,
	isBroken: boolean,
	parent: Instance
)
	local pillarFolder = Instance.new("Folder")
	pillarFolder.Name = name
	pillarFolder.Parent = parent

	local sandstoneColor = Color3.fromRGB(215, 175, 125)
	local trimColor = Color3.fromRGB(190, 145, 95)
	local radius = 3.5

	if not isBroken then
		-- Base
		createPart(
			"Base",
			Vector3.new(radius + 1.5, 2, radius + 1.5),
			CFrame.new(position + Vector3.new(0, 1, 0)),
			trimColor,
			Enum.Material.Sandstone,
			pillarFolder
		)
		-- Main Shaft
		createPart(
			"Shaft",
			Vector3.new(radius, height - 4, radius),
			CFrame.new(position + Vector3.new(0, (height - 4) / 2 + 2, 0)),
			sandstoneColor,
			Enum.Material.Sandstone,
			pillarFolder
		)
		-- Capital Top
		createPart(
			"Capital",
			Vector3.new(radius + 2, 2, radius + 2),
			CFrame.new(position + Vector3.new(0, height - 1, 0)),
			trimColor,
			Enum.Material.Sandstone,
			pillarFolder
		)
	else
		-- Broken Stump
		local stumpHeight = height * 0.4
		createPart(
			"StumpBase",
			Vector3.new(radius + 1.5, 2, radius + 1.5),
			CFrame.new(position + Vector3.new(0, 1, 0)),
			trimColor,
			Enum.Material.Sandstone,
			pillarFolder
		)
		createPart(
			"StumpShaft",
			Vector3.new(radius, stumpHeight, radius),
			CFrame.new(position + Vector3.new(0, stumpHeight / 2 + 2, 0)),
			sandstoneColor,
			Enum.Material.Sandstone,
			pillarFolder
		)

		-- Fallen Column Segment lying on ground
		local fallenLength = height * 0.55
		local fallenCF = CFrame.new(position + Vector3.new(4, 1.8, 4))
			* CFrame.Angles(0, math.rad(45), math.rad(80))
		createPart(
			"FallenSegment",
			Vector3.new(radius, fallenLength, radius),
			fallenCF,
			sandstoneColor,
			Enum.Material.Sandstone,
			pillarFolder
		)
	end
end

-- Helper to create grand ancient arches
local function buildAncientArch(
	name: string,
	centerPosition: Vector3,
	width: number,
	height: number,
	parent: Instance
)
	local archFolder = Instance.new("Folder")
	archFolder.Name = name
	archFolder.Parent = parent

	local sandstoneColor = Color3.fromRGB(215, 175, 125)
	local pillarWidth = 4.5

	-- Left Pillar Leg
	createPart(
		"LegLeft",
		Vector3.new(pillarWidth, height, pillarWidth),
		CFrame.new(centerPosition + Vector3.new(-width / 2 + pillarWidth / 2, height / 2, 0)),
		sandstoneColor,
		Enum.Material.Sandstone,
		archFolder
	)

	-- Right Pillar Leg
	createPart(
		"LegRight",
		Vector3.new(pillarWidth, height, pillarWidth),
		CFrame.new(centerPosition + Vector3.new(width / 2 - pillarWidth / 2, height / 2, 0)),
		sandstoneColor,
		Enum.Material.Sandstone,
		archFolder
	)

	-- Top Arch Keystone Span
	local spanHeight = 4.5
	createPart(
		"ArchSpan",
		Vector3.new(width + 2, spanHeight, pillarWidth + 1),
		CFrame.new(centerPosition + Vector3.new(0, height + spanHeight / 2, 0)),
		sandstoneColor,
		Enum.Material.Sandstone,
		archFolder
	)
end

-- Helper to create crumbling stone wall
local function buildCrumblingWall(
	name: string,
	startPos: Vector3,
	length: number,
	maxHeight: number,
	rotationDeg: number,
	parent: Instance
)
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = name
	wallFolder.Parent = parent

	local stoneColor = Color3.fromRGB(195, 160, 115)
	local wallThickness = 2.5
	local numSegments = math.floor(length / 6)

	local cfBase = CFrame.new(startPos) * CFrame.Angles(0, math.rad(rotationDeg), 0)

	for i = 0, numSegments - 1 do
		local zOffset = i * 6 - length / 2 + 3
		-- Irregular crumbling heights
		local segHeight = maxHeight - (i % 3) * 1.5
		if segHeight < 2 then
			segHeight = 2
		end

		createPart(
			"WallSegment_" .. i,
			Vector3.new(wallThickness, segHeight, 5.8),
			cfBase * CFrame.new(0, segHeight / 2, zOffset),
			stoneColor,
			Enum.Material.Sandstone,
			wallFolder
		)
	end
end

function DesertRuinsMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Sand Terrain Ground
	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "Perimeter"
	terrainFolder.Parent = mapFolder

	local sandColor = Color3.fromRGB(225, 185, 130)
	local rockColor = Color3.fromRGB(175, 135, 90)

	-- Sand Ground Base
	createPart(
		"DesertFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		sandColor,
		Enum.Material.Sand,
		terrainFolder
	)

	-- Sand Dunes (Sloped elevations)
	createWedge(
		"Dune_West_Slope",
		Vector3.new(50, 8, 70),
		CFrame.new(-60, 4, -10) * CFrame.Angles(0, math.rad(-90), 0),
		sandColor,
		Enum.Material.Sand,
		terrainFolder
	)
	createWedge(
		"Dune_East_Slope",
		Vector3.new(50, 8, 70),
		CFrame.new(60, 4, 10) * CFrame.Angles(0, math.rad(90), 0),
		sandColor,
		Enum.Material.Sand,
		terrainFolder
	)

	-- Outer Canyon Wall Boundaries
	createPart(
		"NorthCanyonWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 4),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"SouthCanyonWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 4),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"WestCanyonWall",
		Vector3.new(4, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		rockColor,
		Enum.Material.Slate,
		terrainFolder
	)
	createPart(
		"EastCanyonWall",
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
		"RedOasisBase",
		Vector3.new(40, 1, 26),
		CFrame.new(0, 0.5, -110),
		Color3.fromRGB(160, 45, 45),
		Enum.Material.Sandstone,
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
		"BlueExcavationBase",
		Vector3.new(40, 1, 26),
		CFrame.new(0, 0.5, 110),
		Color3.fromRGB(45, 95, 165),
		Enum.Material.Sandstone,
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

	-- 3. Environment Assets Folder (Pillars, Arches, Crumbling Walls, Obelisks)
	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = mapFolder

	-- Ancient Sandstone Pillars
	buildSandstonePillar("Pillar_Intact_1", Vector3.new(-50, 0, -80), 16, false, envFolder)
	buildSandstonePillar("Pillar_Intact_2", Vector3.new(50, 0, 80), 16, false, envFolder)
	buildSandstonePillar("Pillar_Broken_1", Vector3.new(-55, 0, 30), 14, true, envFolder)
	buildSandstonePillar("Pillar_Broken_2", Vector3.new(55, 0, -30), 14, true, envFolder)

	-- Grand Ancient Arches
	buildAncientArch("Arch_NorthPortal", Vector3.new(0, 0, -70), 22, 14, envFolder)
	buildAncientArch("Arch_SouthPortal", Vector3.new(0, 0, 70), 22, 14, envFolder)
	buildAncientArch("Arch_WestEntry", Vector3.new(-55, 0, 0), 18, 12, envFolder)
	buildAncientArch("Arch_EastEntry", Vector3.new(55, 0, 0), 18, 12, envFolder)

	-- Crumbling Stone Walls
	buildCrumblingWall("CrumblingWall_SiteA", Vector3.new(-65, 0, -35), 24, 7, 30, envFolder)
	buildCrumblingWall("CrumblingWall_SiteB", Vector3.new(65, 0, 35), 24, 7, -30, envFolder)
	buildCrumblingWall("CrumblingWall_MidWest", Vector3.new(-22, 0, 0), 20, 8, 90, envFolder)
	buildCrumblingWall("CrumblingWall_MidEast", Vector3.new(22, 0, 0), 20, 8, -90, envFolder)

	-- Sandstone Obelisk in Sunken Plaza Center
	local obeliskColor = Color3.fromRGB(205, 165, 115)
	createPart(
		"CentralObelisk",
		Vector3.new(5, 16, 5),
		CFrame.new(0, 8, 0),
		obeliskColor,
		Enum.Material.Sandstone,
		envFolder
	)

	-- 4. Objective Sites Folder
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "Sites"
	sitesFolder.Parent = mapFolder

	local siteA = createPart(
		"SiteA",
		Vector3.new(30, 0.4, 30),
		CFrame.new(SITE_A_POSITION),
		Color3.fromRGB(240, 175, 35),
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
		Color3.fromRGB(240, 175, 35),
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteB.Transparency = 0.5
	siteB:SetAttribute("SiteName", "B")

	-- 5. Cover Folder
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	local rubbleColor = Color3.fromRGB(185, 150, 105)

	-- Site A Rubble & Pillars
	createPart("RubbleBlock_SiteA_1", Vector3.new(6, 4, 6), CFrame.new(-55, 2, -40), rubbleColor, Enum.Material.Sandstone, coverFolder)
	createPart("RubbleBlock_SiteA_2", Vector3.new(5, 3.5, 5), CFrame.new(-68, 1.75, -30), rubbleColor, Enum.Material.Sandstone, coverFolder)
	createPart("RubbleBlock_SiteA_3", Vector3.new(5, 3.5, 5), CFrame.new(-42, 1.75, -52), rubbleColor, Enum.Material.Sandstone, coverFolder)

	-- Site B Rubble & Pillars
	createPart("RubbleBlock_SiteB_1", Vector3.new(6, 4, 6), CFrame.new(55, 2, 40), rubbleColor, Enum.Material.Sandstone, coverFolder)
	createPart("RubbleBlock_SiteB_2", Vector3.new(5, 3.5, 5), CFrame.new(68, 1.75, 30), rubbleColor, Enum.Material.Sandstone, coverFolder)
	createPart("RubbleBlock_SiteB_3", Vector3.new(5, 3.5, 5), CFrame.new(42, 1.75, 52), rubbleColor, Enum.Material.Sandstone, coverFolder)

	-- Mid Plaza Cover
	createPart("PlazaCover_North", Vector3.new(8, 3.5, 4), CFrame.new(0, 1.75, -25), rubbleColor, Enum.Material.Sandstone, coverFolder)
	createPart("PlazaCover_South", Vector3.new(8, 3.5, 4), CFrame.new(0, 1.75, 25), rubbleColor, Enum.Material.Sandstone, coverFolder)

	-- 6. Lanes Folder
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = mapFolder

	for laneName, data in LANES_DATA do
		createPart(
			laneName,
			data.size,
			CFrame.new(data.center),
			Color3.fromRGB(205, 165, 115),
			Enum.Material.SmoothPlastic,
			lanesFolder,
			false
		)
	end

	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder

	return mapFolder
end

function DesertRuinsMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function DesertRuinsMap.GetSpawnPoints(teamName: string): { Vector3 }
	if teamName == "Red" then
		return table.clone(RED_SPAWN_POSITIONS)
	elseif teamName == "Blue" then
		return table.clone(BLUE_SPAWN_POSITIONS)
	else
		warn("[DesertRuinsMap] Invalid team name: " .. tostring(teamName))
		return {}
	end
end

function DesertRuinsMap.GetCoverPositions(): { Vector3 }
	return table.clone(COVER_POSITIONS)
end

function DesertRuinsMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION,
		siteB = SITE_B_POSITION,
	}
end

function DesertRuinsMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2)
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2)
	return minBounds, maxBounds
end

function DesertRuinsMap.GetLayoutData(): MapLayoutData
	local minB, maxB = DesertRuinsMap.GetMapBounds()
	return {
		mapId = "DesertRuins",
		mapName = "Desert Ruins",
		theme = "Desert",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = table.clone(RED_SPAWN_POSITIONS),
		blueSpawns = table.clone(BLUE_SPAWN_POSITIONS),
		sites = DesertRuinsMap.GetSitePositions(),
		coverPositions = table.clone(COVER_POSITIONS),
		lanes = LANES_DATA,
	}
end

return DesertRuinsMap
