--!strict
--[=[
    Project OVERCLOCK: GreyboxArenaMap
    Rojo-compatible 5v5 greybox arena layout builder module.
    Constructs geometric shapes for lanes, cover positions, spawn areas,
    objective sites, and outer map boundaries for round-based competitive play.
]=]

local Workspace = game:GetService("Workspace")

local GreyboxArenaMap = {}

export type MapBounds = {
	min: Vector3,
	max: Vector3,
}

export type SitePositions = {
	siteA: Vector3,
	siteB: Vector3,
}

export type MapLayoutData = {
	mapName: string,
	bounds: MapBounds,
	redSpawns: { Vector3 },
	blueSpawns: { Vector3 },
	sites: SitePositions,
	coverPositions: { Vector3 },
	lanes: { [string]: { center: Vector3, size: Vector3 } },
}

local MAP_FOLDER_NAME = "GreyboxArenaMap"
local _activeMapFolder: Folder? = nil

-- Map Dimensions Constants
local MAP_WIDTH_X = 160
local MAP_LENGTH_Z = 240
local MAP_HEIGHT_Y = 30

local RED_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-12, 2, -100),
	Vector3.new(-6, 2, -100),
	Vector3.new(0, 2, -100),
	Vector3.new(6, 2, -100),
	Vector3.new(12, 2, -100),
}

local BLUE_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-12, 2, 100),
	Vector3.new(-6, 2, 100),
	Vector3.new(0, 2, 100),
	Vector3.new(6, 2, 100),
	Vector3.new(12, 2, 100),
}

local SITE_A_POSITION = Vector3.new(-50, 1, -40)
local SITE_B_POSITION = Vector3.new(50, 1, 40)

local COVER_POSITIONS: { Vector3 } = {
	-- Site A Cover
	Vector3.new(-50, 4, -40),
	Vector3.new(-60, 2, -30),
	Vector3.new(-40, 2, -50),
	-- Site B Cover
	Vector3.new(50, 5, 40),
	Vector3.new(60, 2, 30),
	Vector3.new(40, 2, 50),
	-- Mid Lane Cover
	Vector3.new(-15, 3, 0),
	Vector3.new(15, 3, 0),
	Vector3.new(0, 2.5, -20),
	Vector3.new(0, 2.5, 20),
	-- Sniper Perches
	Vector3.new(-65, 8, -80),
	Vector3.new(65, 8, 80),
}

local LANES_DATA: { [string]: { center: Vector3, size: Vector3 } } = {
	MainLane = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(24, 0.4, 160) },
	LeftFlank = { center = Vector3.new(-50, 0.2, 0), size = Vector3.new(24, 0.4, 180) },
	RightFlank = { center = Vector3.new(50, 0.2, 0), size = Vector3.new(24, 0.4, 180) },
	ConnectorA = { center = Vector3.new(-25, 0.2, -40), size = Vector3.new(30, 0.4, 16) },
	ConnectorB = { center = Vector3.new(25, 0.2, 40), size = Vector3.new(30, 0.4, 16) },
}

local MAP_OFFSET = Vector3.new(0, 100, 0)

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
	part.CFrame = cframe + MAP_OFFSET
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
	wedge.CFrame = cframe + MAP_OFFSET
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.Anchored = true
	wedge.CanCollide = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

function GreyboxArenaMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Floor
	local perimeterFolder = Instance.new("Folder")
	perimeterFolder.Name = "Perimeter"
	perimeterFolder.Parent = mapFolder

	-- Main Floor
	createPart(
		"MainFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		Color3.fromRGB(80, 80, 85),
		Enum.Material.Concrete,
		perimeterFolder
	)

	-- Outer Walls
	createPart(
		"NorthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		Color3.fromRGB(60, 60, 65),
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"SouthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		Color3.fromRGB(60, 60, 65),
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"WestWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		Color3.fromRGB(60, 60, 65),
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"EastWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		Color3.fromRGB(60, 60, 65),
		Enum.Material.Concrete,
		perimeterFolder
	)

	-- 2. Spawns Folder
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = mapFolder

	local redSpawnFolder = Instance.new("Folder")
	redSpawnFolder.Name = "RedSpawn"
	redSpawnFolder.Parent = spawnsFolder

	createPart(
		"RedPlatform",
		Vector3.new(40, 1, 30),
		CFrame.new(0, 0.5, -100),
		Color3.fromRGB(180, 50, 50),
		Enum.Material.SmoothPlastic,
		redSpawnFolder
	)

	for i, pos in RED_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(220, 80, 80),
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
		"BluePlatform",
		Vector3.new(40, 1, 30),
		CFrame.new(0, 0.5, 100),
		Color3.fromRGB(50, 100, 180),
		Enum.Material.SmoothPlastic,
		blueSpawnFolder
	)

	for i, pos in BLUE_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(80, 140, 220),
			Enum.Material.Neon,
			blueSpawnFolder,
			false
		)
		sp:SetAttribute("Team", "Blue")
		sp:SetAttribute("Index", i)
	end

	-- 3. Lanes Folder
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

	-- 5. Cover & Obstacles Folder
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	-- Site A Covers
	createPart(
		"HighCover_SiteA",
		Vector3.new(6, 8, 6),
		CFrame.new(Vector3.new(-50, 4, -40)),
		Color3.fromRGB(140, 145, 150),
		Enum.Material.Concrete,
		coverFolder
	)
	createPart(
		"LowCover_SiteA_1",
		Vector3.new(4, 4, 4),
		CFrame.new(Vector3.new(-60, 2, -30)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)
	createPart(
		"LowCover_SiteA_2",
		Vector3.new(4, 4, 4),
		CFrame.new(Vector3.new(-40, 2, -50)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)

	-- Site B Covers
	createPart(
		"HighCover_SiteB",
		Vector3.new(6, 10, 6),
		CFrame.new(Vector3.new(50, 5, 40)),
		Color3.fromRGB(140, 145, 150),
		Enum.Material.Concrete,
		coverFolder
	)
	createPart(
		"LowCover_SiteB_1",
		Vector3.new(4, 4, 4),
		CFrame.new(Vector3.new(60, 2, 30)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)
	createPart(
		"LowCover_SiteB_2",
		Vector3.new(4, 4, 4),
		CFrame.new(Vector3.new(40, 2, 50)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)

	-- Mid Lane Covers & Chokepoint Pillars
	createPart(
		"Pillar_Mid_Left",
		Vector3.new(6, 12, 6),
		CFrame.new(Vector3.new(-15, 6, 0)),
		Color3.fromRGB(160, 165, 170),
		Enum.Material.Concrete,
		coverFolder
	)
	createPart(
		"Pillar_Mid_Right",
		Vector3.new(6, 12, 6),
		CFrame.new(Vector3.new(15, 6, 0)),
		Color3.fromRGB(160, 165, 170),
		Enum.Material.Concrete,
		coverFolder
	)
	createPart(
		"LowCover_Mid_1",
		Vector3.new(6, 3.5, 4),
		CFrame.new(Vector3.new(0, 1.75, -20)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)
	createPart(
		"LowCover_Mid_2",
		Vector3.new(6, 3.5, 4),
		CFrame.new(Vector3.new(0, 1.75, 20)),
		Color3.fromRGB(120, 125, 130),
		Enum.Material.SmoothPlastic,
		coverFolder
	)

	-- Sniper Perches & Ramps
	createPart(
		"Perch_Red",
		Vector3.new(16, 2, 16),
		CFrame.new(Vector3.new(-65, 8, -80)),
		Color3.fromRGB(170, 175, 180),
		Enum.Material.SmoothPlastic,
		coverFolder
	)
	createWedge(
		"Ramp_Red",
		Vector3.new(8, 8, 12),
		CFrame.new(Vector3.new(-65, 4, -92)),
		Color3.fromRGB(150, 155, 160),
		Enum.Material.Concrete,
		coverFolder
	)

	createPart(
		"Perch_Blue",
		Vector3.new(16, 2, 16),
		CFrame.new(Vector3.new(65, 8, 80)),
		Color3.fromRGB(170, 175, 180),
		Enum.Material.SmoothPlastic,
		coverFolder
	)
	createWedge(
		"Ramp_Blue",
		Vector3.new(8, 8, 12),
		CFrame.new(Vector3.new(65, 4, 92)) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(150, 155, 160),
		Enum.Material.Concrete,
		coverFolder
	)

	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder

	return mapFolder
end

function GreyboxArenaMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function GreyboxArenaMap.GetSpawnPoints(teamName: string): { Vector3 }
	local baseSpawns = if teamName == "Red" then RED_SPAWN_POSITIONS elseif teamName == "Blue" then BLUE_SPAWN_POSITIONS else {}
	local results: { Vector3 } = {}
	for _, pos in baseSpawns do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function GreyboxArenaMap.GetCoverPositions(): { Vector3 }
	local results: { Vector3 } = {}
	for _, pos in COVER_POSITIONS do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function GreyboxArenaMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION + MAP_OFFSET,
		siteB = SITE_B_POSITION + MAP_OFFSET,
	}
end

function GreyboxArenaMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2) + MAP_OFFSET
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2) + MAP_OFFSET
	return minBounds, maxBounds
end

function GreyboxArenaMap.GetLayoutData(): MapLayoutData
	local minB, maxB = GreyboxArenaMap.GetMapBounds()
	local mappedLanes = {}
	for laneName, data in LANES_DATA do
		mappedLanes[laneName] = {
			center = data.center + MAP_OFFSET,
			size = data.size
		}
	end

	return {
		mapName = "Greybox_Arena_5v5",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = GreyboxArenaMap.GetSpawnPoints("Red"),
		blueSpawns = GreyboxArenaMap.GetSpawnPoints("Blue"),
		sites = GreyboxArenaMap.GetSitePositions(),
		coverPositions = GreyboxArenaMap.GetCoverPositions(),
		lanes = mappedLanes,
	}
end

return GreyboxArenaMap
