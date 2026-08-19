--!strict
--[=[
    Project OVERCLOCK: ClassicGreyboxMap
    Procedural 5v5 FPS Competitive Greybox layout builder module.
    Generates a pristine competitive 3-lane FPS blockout map featuring grid blocks,
    mid-lane sniper walls with head-shot window cutouts, flank corridors with L-corners,
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

local ClassicGreyboxMap = {}

local MAP_FOLDER_NAME = "ClassicGreyboxMap"
local _activeMapFolder: Folder? = nil

-- Map Dimension Constants
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
	-- Site A Covers
	Vector3.new(-50, 4, -40),
	Vector3.new(-60, 2, -30),
	Vector3.new(-40, 2, -50),
	-- Site B Covers
	Vector3.new(50, 5, 40),
	Vector3.new(60, 2, 30),
	Vector3.new(40, 2, 50),
	-- Mid Lane Covers & Sniper Walls
	Vector3.new(-15, 6, 0),
	Vector3.new(15, 6, 0),
	Vector3.new(0, 2.5, -20),
	Vector3.new(0, 2.5, 20),
	-- Sniper Perches
	Vector3.new(-65, 8, -80),
	Vector3.new(65, 8, 80),
}

local LANES_DATA: { [string]: LaneData } = {
	CenterMid = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(24, 0.4, 160) },
	LeftFlankCorridor = { center = Vector3.new(-50, 0.2, 0), size = Vector3.new(24, 0.4, 180) },
	RightFlankCorridor = { center = Vector3.new(50, 0.2, 0), size = Vector3.new(24, 0.4, 180) },
	ConnectorSiteA = { center = Vector3.new(-25, 0.2, -40), size = Vector3.new(30, 0.4, 16) },
	ConnectorSiteB = { center = Vector3.new(25, 0.2, 40), size = Vector3.new(30, 0.4, 16) },
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

-- Helper to create mid-lane sniper wall with headshot window cutout
local function createSniperWall(
	name: string,
	position: Vector3,
	rotationYDeg: number,
	parent: Instance
)
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = name
	wallFolder.Parent = parent

	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationYDeg), 0)
	local greyColor = Color3.fromRGB(140, 145, 150)
	local windowWidth = 6
	local totalWidth = 20
	local wallHeight = 10
	local sideWidth = (totalWidth - windowWidth) / 2

	-- Left Pillar Side
	createPart(
		"WallLeft",
		Vector3.new(sideWidth, wallHeight, 3),
		cf * CFrame.new(-totalWidth / 2 + sideWidth / 2, wallHeight / 2, 0),
		greyColor,
		Enum.Material.Concrete,
		wallFolder
	)

	-- Right Pillar Side
	createPart(
		"WallRight",
		Vector3.new(sideWidth, wallHeight, 3),
		cf * CFrame.new(totalWidth / 2 - sideWidth / 2, wallHeight / 2, 0),
		greyColor,
		Enum.Material.Concrete,
		wallFolder
	)

	-- Lower Wall Sill below Window (Headshot height)
	createPart(
		"WallSill",
		Vector3.new(windowWidth, 4, 3),
		cf * CFrame.new(0, 2, 0),
		greyColor,
		Enum.Material.Concrete,
		wallFolder
	)

	-- Upper Arch Lintels above Window
	createPart(
		"WallLintel",
		Vector3.new(windowWidth, 2, 3),
		cf * CFrame.new(0, 9, 0),
		greyColor,
		Enum.Material.Concrete,
		wallFolder
	)
end

-- Helper to build flank corridor with L-corners and low cover
local function createFlankCorridor(
	name: string,
	centerPos: Vector3,
	isWest: boolean,
	parent: Instance
)
	local corridorFolder = Instance.new("Folder")
	corridorFolder.Name = name
	corridorFolder.Parent = parent

	local darkGrey = Color3.fromRGB(90, 95, 100)
	local dir = if isWest then -1 else 1

	-- L-Corner Wall 1
	createPart(
		"LWall_Outer",
		Vector3.new(4, 12, 40),
		CFrame.new(centerPos + Vector3.new(dir * 12, 6, 0)),
		darkGrey,
		Enum.Material.Concrete,
		corridorFolder
	)

	-- L-Corner Wall 2
	createPart(
		"LWall_Inner",
		Vector3.new(20, 12, 4),
		CFrame.new(centerPos + Vector3.new(dir * 2, 6, 20)),
		darkGrey,
		Enum.Material.Concrete,
		corridorFolder
	)
end

function ClassicGreyboxMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Grid Floor
	local perimeterFolder = Instance.new("Folder")
	perimeterFolder.Name = "Perimeter"
	perimeterFolder.Parent = mapFolder

	local floorGrey = Color3.fromRGB(110, 115, 120)
	local wallGrey = Color3.fromRGB(70, 75, 80)

	-- Grid Floor Base
	createPart(
		"MainFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		floorGrey,
		Enum.Material.Concrete,
		perimeterFolder
	)

	-- Boundary Walls
	createPart(
		"NorthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		wallGrey,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"SouthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		wallGrey,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"WestWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallGrey,
		Enum.Material.Concrete,
		perimeterFolder
	)
	createPart(
		"EastWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallGrey,
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

	-- 3. Environment Assets (Mid-lane Sniper Walls & Flank Corridors)
	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = mapFolder

	-- Mid-lane Sniper Walls with Window Cutouts
	createSniperWall("SniperWall_NorthMid", Vector3.new(0, 0, -35), 0, envFolder)
	createSniperWall("SniperWall_SouthMid", Vector3.new(0, 0, 35), 0, envFolder)

	-- Flank Corridors
	createFlankCorridor("FlankCorridor_West", Vector3.new(-50, 0, 0), true, envFolder)
	createFlankCorridor("FlankCorridor_East", Vector3.new(50, 0, 0), false, envFolder)

	-- 4. Objective Sites Folder
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

	local blockColor = Color3.fromRGB(130, 135, 140)

	-- Site A Cover Blocks
	createPart("HighCover_SiteA", Vector3.new(6, 7.0, 6), CFrame.new(-50, 3.5, -40), blockColor, Enum.Material.Concrete, coverFolder)
	createPart("LowCover_SiteA_1", Vector3.new(4, 3.5, 4), CFrame.new(-60, 1.75, -30), blockColor, Enum.Material.SmoothPlastic, coverFolder)
	createPart("LowCover_SiteA_2", Vector3.new(4, 3.5, 4), CFrame.new(-40, 1.75, -50), blockColor, Enum.Material.SmoothPlastic, coverFolder)

	-- Site B Cover Blocks
	createPart("HighCover_SiteB", Vector3.new(6, 7.0, 6), CFrame.new(50, 3.5, 40), blockColor, Enum.Material.Concrete, coverFolder)
	createPart("LowCover_SiteB_1", Vector3.new(4, 3.5, 4), CFrame.new(60, 1.75, 30), blockColor, Enum.Material.SmoothPlastic, coverFolder)
	createPart("LowCover_SiteB_2", Vector3.new(4, 3.5, 4), CFrame.new(40, 1.75, 50), blockColor, Enum.Material.SmoothPlastic, coverFolder)

	-- Mid Lane Covers & Chokepoint Pillars
	createPart("Pillar_Mid_Left", Vector3.new(6, 7.0, 6), CFrame.new(-15, 3.5, 0), blockColor, Enum.Material.Concrete, coverFolder)
	createPart("Pillar_Mid_Right", Vector3.new(6, 7.0, 6), CFrame.new(15, 3.5, 0), blockColor, Enum.Material.Concrete, coverFolder)
	createPart("LowCover_Mid_1", Vector3.new(6, 3.5, 4), CFrame.new(0, 1.75, -20), blockColor, Enum.Material.SmoothPlastic, coverFolder)
	createPart("LowCover_Mid_2", Vector3.new(6, 3.5, 4), CFrame.new(0, 1.75, 20), blockColor, Enum.Material.SmoothPlastic, coverFolder)

	-- Sniper Perches & Ramps
	createPart("Perch_Red", Vector3.new(16, 2, 16), CFrame.new(-65, 8, -80), blockColor, Enum.Material.SmoothPlastic, coverFolder)
	createWedge("Ramp_Red", Vector3.new(8, 8, 12), CFrame.new(-65, 4, -92), blockColor, Enum.Material.Concrete, coverFolder)

	createPart("Perch_Blue", Vector3.new(16, 2, 16), CFrame.new(65, 8, 80), blockColor, Enum.Material.SmoothPlastic, coverFolder)
	createWedge("Ramp_Blue", Vector3.new(8, 8, 12), CFrame.new(65, 4, 92) * CFrame.Angles(0, math.pi, 0), blockColor, Enum.Material.Concrete, coverFolder)

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

function ClassicGreyboxMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function ClassicGreyboxMap.GetSpawnPoints(teamName: string): { Vector3 }
	if teamName == "Red" then
		return table.clone(RED_SPAWN_POSITIONS)
	elseif teamName == "Blue" then
		return table.clone(BLUE_SPAWN_POSITIONS)
	else
		warn("[ClassicGreyboxMap] Invalid team name: " .. tostring(teamName))
		return {}
	end
end

function ClassicGreyboxMap.GetCoverPositions(): { Vector3 }
	return table.clone(COVER_POSITIONS)
end

function ClassicGreyboxMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION,
		siteB = SITE_B_POSITION,
	}
end

function ClassicGreyboxMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2)
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2)
	return minBounds, maxBounds
end

function ClassicGreyboxMap.GetLayoutData(): MapLayoutData
	local minB, maxB = ClassicGreyboxMap.GetMapBounds()
	return {
		mapId = "ClassicGreybox",
		mapName = "Classic Greybox",
		theme = "Competitive Greybox",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = table.clone(RED_SPAWN_POSITIONS),
		blueSpawns = table.clone(BLUE_SPAWN_POSITIONS),
		sites = ClassicGreyboxMap.GetSitePositions(),
		coverPositions = table.clone(COVER_POSITIONS),
		lanes = LANES_DATA,
	}
end

return ClassicGreyboxMap
