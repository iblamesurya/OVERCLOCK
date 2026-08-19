--!strict
--[=[
    Project OVERCLOCK: CyberArenaMap
    Procedural 5v5 FPS Sci-Fi Cyber Arena layout builder module.
    Generates a futuristic cyberpunk arena environment featuring glowing neon light barriers,
    glass wall sightline partitions, multi-level metallic platforms with energy ramps,
    holographic objective pads, spawn locations, and high-tech cover structures.
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

local CyberArenaMap = {}

local MAP_FOLDER_NAME = "CyberArenaMap"
local _activeMapFolder: Folder? = nil

-- Map Dimension Constants
local MAP_WIDTH_X = 160
local MAP_LENGTH_Z = 240
local MAP_HEIGHT_Y = 32

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

local SITE_A_POSITION = Vector3.new(-48, 1, -38)
local SITE_B_POSITION = Vector3.new(48, 1, 38)

local COVER_POSITIONS: { Vector3 } = {
	-- Site A Holo Barricades & Neon Pillars
	Vector3.new(-48, 4, -38),
	Vector3.new(-58, 2.5, -28),
	Vector3.new(-38, 2.5, -48),
	-- Site B Holo Barricades & Neon Pillars
	Vector3.new(48, 4, 38),
	Vector3.new(58, 2.5, 28),
	Vector3.new(38, 2.5, 48),
	-- Mid Energy Pillars & Low Light Shields
	Vector3.new(-16, 6, 0),
	Vector3.new(16, 6, 0),
	Vector3.new(0, 2.5, -20),
	Vector3.new(0, 2.5, 20),
	-- Upper Platform Perches
	Vector3.new(-42, 14, -72),
	Vector3.new(42, 14, 72),
}

local LANES_DATA: { [string]: LaneData } = {
	MainCyberGrid = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(24, 0.4, 160) },
	NeonWestConcourse = { center = Vector3.new(-48, 0.2, 0), size = Vector3.new(26, 0.4, 180) },
	NeonEastConcourse = { center = Vector3.new(48, 0.2, 0), size = Vector3.new(26, 0.4, 180) },
	GlassConnectorNorth = { center = Vector3.new(-24, 0.2, -38), size = Vector3.new(24, 0.4, 16) },
	GlassConnectorSouth = { center = Vector3.new(24, 0.2, 38), size = Vector3.new(24, 0.4, 16) },
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

-- Helper to create glowing neon light barriers
local function createNeonBarrier(
	name: string,
	size: Vector3,
	cframe: CFrame,
	neonColor: Color3,
	parent: Instance
)
	local barrierFolder = Instance.new("Folder")
	barrierFolder.Name = name
	barrierFolder.Parent = parent

	-- Semi-transparent neon core
	local core = createPart(
		"Core",
		size,
		cframe,
		neonColor,
		Enum.Material.Neon,
		barrierFolder,
		true
	)
	core.Transparency = 0.3

	-- Dark Metallic Border Frame
	local frameColor = Color3.fromRGB(30, 35, 45)
	local t = 0.6
	createPart(
		"FrameTop",
		Vector3.new(size.X + t, t, size.Z + t),
		cframe * CFrame.new(0, size.Y / 2, 0),
		frameColor,
		Enum.Material.Metal,
		barrierFolder
	)
	createPart(
		"FrameBottom",
		Vector3.new(size.X + t, t, size.Z + t),
		cframe * CFrame.new(0, -size.Y / 2, 0),
		frameColor,
		Enum.Material.Metal,
		barrierFolder
	)
end

-- Helper to create glass sightline walls
local function createGlassWall(
	name: string,
	size: Vector3,
	cframe: CFrame,
	parent: Instance
)
	local glass = createPart(
		name,
		size,
		cframe,
		Color3.fromRGB(180, 230, 255),
		Enum.Material.Glass,
		parent,
		true
	)
	glass.Transparency = 0.6
	glass:SetAttribute("WallType", "GlassSightline")
end

-- Helper to create multi-level metallic platform
local function buildMultiLevelPlatform(
	name: string,
	centerPos: Vector3,
	size: Vector3,
	height: number,
	parent: Instance
)
	local platFolder = Instance.new("Folder")
	platFolder.Name = name
	platFolder.Parent = parent

	local chromeColor = Color3.fromRGB(80, 85, 95)
	local neonCyan = Color3.fromRGB(0, 220, 255)

	-- Platform Floor
	local platCF = CFrame.new(centerPos + Vector3.new(0, height, 0))
	createPart(
		"PlatFloor",
		Vector3.new(size.X, 1.2, size.Z),
		platCF,
		chromeColor,
		Enum.Material.Metal,
		platFolder
	)

	-- Neon Under-Glow Strips
	createPart(
		"NeonStrip_1",
		Vector3.new(size.X, 0.4, 0.6),
		platCF * CFrame.new(0, -0.6, size.Z / 2),
		neonCyan,
		Enum.Material.Neon,
		platFolder,
		false
	)
	createPart(
		"NeonStrip_2",
		Vector3.new(size.X, 0.4, 0.6),
		platCF * CFrame.new(0, -0.6, -size.Z / 2),
		neonCyan,
		Enum.Material.Neon,
		platFolder,
		false
	)

	-- Metal Support Legs
	local legOffsets = {
		Vector3.new(-size.X / 2 + 1, height / 2, -size.Z / 2 + 1),
		Vector3.new(size.X / 2 - 1, height / 2, -size.Z / 2 + 1),
		Vector3.new(-size.X / 2 + 1, height / 2, size.Z / 2 - 1),
		Vector3.new(size.X / 2 - 1, height / 2, size.Z / 2 - 1),
	}
	for i, legOffset in legOffsets do
		createPart(
			"Leg_" .. i,
			Vector3.new(1.8, height, 1.8),
			CFrame.new(centerPos + legOffset),
			chromeColor,
			Enum.Material.Metal,
			platFolder
		)
	end

	-- Energy Ramp Access
	local rampLength = 16
	createWedge(
		"EnergyRamp",
		Vector3.new(6, height, rampLength),
		CFrame.new(centerPos + Vector3.new(0, height / 2, size.Z / 2 + rampLength / 2)),
		Color3.fromRGB(0, 180, 220),
		Enum.Material.SmoothPlastic,
		platFolder
	)
end

function CyberArenaMap.BuildMap(parent: Instance?): Folder
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- 1. Outer Perimeter & Metallic Grid Floor
	local perimeterFolder = Instance.new("Folder")
	perimeterFolder.Name = "Perimeter"
	perimeterFolder.Parent = mapFolder

	local darkGridColor = Color3.fromRGB(25, 28, 35)
	local wallColor = Color3.fromRGB(40, 45, 55)
	local neonPink = Color3.fromRGB(255, 0, 128)
	local neonCyan = Color3.fromRGB(0, 220, 255)

	-- Main Arena Metallic Floor
	createPart(
		"CyberFloor",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0),
		darkGridColor,
		Enum.Material.DiamondPlate,
		perimeterFolder
	)

	-- Neon Grid Lines on Floor
	createPart(
		"GridLine_CenterZ",
		Vector3.new(0.8, 0.1, MAP_LENGTH_Z),
		CFrame.new(0, 0.05, 0),
		neonCyan,
		Enum.Material.Neon,
		perimeterFolder,
		false
	)
	createPart(
		"GridLine_CenterX",
		Vector3.new(MAP_WIDTH_X, 0.1, 0.8),
		CFrame.new(0, 0.05, 0),
		neonPink,
		Enum.Material.Neon,
		perimeterFolder,
		false
	)

	-- Outer Enclosure Walls with Neon Trims
	createPart(
		"NorthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
		wallColor,
		Enum.Material.Metal,
		perimeterFolder
	)
	createPart(
		"SouthWall",
		Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
		CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
		wallColor,
		Enum.Material.Metal,
		perimeterFolder
	)
	createPart(
		"WestWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallColor,
		Enum.Material.Metal,
		perimeterFolder
	)
	createPart(
		"EastWall",
		Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
		CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
		wallColor,
		Enum.Material.Metal,
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
		"RedCyberBayPad",
		Vector3.new(36, 1, 24),
		CFrame.new(0, 0.5, -100),
		Color3.fromRGB(180, 30, 80),
		Enum.Material.SmoothPlastic,
		redSpawnFolder
	)

	for i, pos in RED_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(255, 50, 120),
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
		"BlueCyberBayPad",
		Vector3.new(36, 1, 24),
		CFrame.new(0, 0.5, 100),
		Color3.fromRGB(30, 140, 220),
		Enum.Material.SmoothPlastic,
		blueSpawnFolder
	)

	for i, pos in BLUE_SPAWN_POSITIONS do
		local sp = createPart(
			"SpawnPoint" .. i,
			Vector3.new(4, 1, 4),
			CFrame.new(pos),
			Color3.fromRGB(50, 200, 255),
			Enum.Material.Neon,
			blueSpawnFolder,
			false
		)
		sp:SetAttribute("Team", "Blue")
		sp:SetAttribute("Index", i)
	end

	-- 3. Environment Assets Folder (Neon Barriers, Glass Walls, Multi-level Platforms)
	local envFolder = Instance.new("Folder")
	envFolder.Name = "Environment"
	envFolder.Parent = mapFolder

	-- Glowing Neon Light Barriers
	createNeonBarrier("NeonBarrier_West_1", Vector3.new(8, 7, 2), CFrame.new(-48, 3.5, -20), neonPink, envFolder)
	createNeonBarrier("NeonBarrier_East_1", Vector3.new(8, 7, 2), CFrame.new(48, 3.5, 20), neonCyan, envFolder)

	-- Translucent Glass Sightline Walls
	createGlassWall("GlassWall_MidWest", Vector3.new(1, 10, 24), CFrame.new(-24, 5, 0), envFolder)
	createGlassWall("GlassWall_MidEast", Vector3.new(1, 10, 24), CFrame.new(24, 5, 0), envFolder)

	-- Multi-level Metallic Platforms with Energy Ramps
	buildMultiLevelPlatform("Platform_NorthWest", Vector3.new(-42, 0, -72), Vector3.new(16, 1.2, 16), 14, envFolder)
	buildMultiLevelPlatform("Platform_SouthEast", Vector3.new(42, 0, 72), Vector3.new(16, 1.2, 16), 14, envFolder)

	-- Metallic Sci-Fi Pillars
	local pillarColor = Color3.fromRGB(50, 55, 65)
	createPart("SciFiPillar_Mid_L", Vector3.new(5, 18, 5), CFrame.new(-16, 9, 0), pillarColor, Enum.Material.Metal, envFolder)
	createPart("SciFiPillar_Mid_R", Vector3.new(5, 18, 5), CFrame.new(16, 9, 0), pillarColor, Enum.Material.Metal, envFolder)

	-- 4. Objective Sites Folder (Holographic Pads)
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "Sites"
	sitesFolder.Parent = mapFolder

	local siteA = createPart(
		"SiteA",
		Vector3.new(28, 0.4, 28),
		CFrame.new(SITE_A_POSITION),
		neonPink,
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteA.Transparency = 0.4
	siteA:SetAttribute("SiteName", "A")

	local siteB = createPart(
		"SiteB",
		Vector3.new(28, 0.4, 28),
		CFrame.new(SITE_B_POSITION),
		neonCyan,
		Enum.Material.Neon,
		sitesFolder,
		false
	)
	siteB.Transparency = 0.4
	siteB:SetAttribute("SiteName", "B")

	-- 5. Cover & Holo Shield Folder
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	local metalCoverColor = Color3.fromRGB(60, 65, 75)

	-- Site A Covers
	createPart("HoloCover_SiteA_1", Vector3.new(6, 6, 6), CFrame.new(-48, 3, -38), metalCoverColor, Enum.Material.SmoothPlastic, coverFolder)
	createPart("HoloCover_SiteA_2", Vector3.new(5, 4, 5), CFrame.new(-58, 2, -28), metalCoverColor, Enum.Material.Metal, coverFolder)
	createPart("HoloCover_SiteA_3", Vector3.new(5, 4, 5), CFrame.new(-38, 2, -48), metalCoverColor, Enum.Material.Metal, coverFolder)

	-- Site B Covers
	createPart("HoloCover_SiteB_1", Vector3.new(6, 6, 6), CFrame.new(48, 3, 38), metalCoverColor, Enum.Material.SmoothPlastic, coverFolder)
	createPart("HoloCover_SiteB_2", Vector3.new(5, 4, 5), CFrame.new(58, 2, 28), metalCoverColor, Enum.Material.Metal, coverFolder)
	createPart("HoloCover_SiteB_3", Vector3.new(5, 4, 5), CFrame.new(38, 2, 48), metalCoverColor, Enum.Material.Metal, coverFolder)

	-- Mid Shields
	createPart("MidShield_North", Vector3.new(8, 4, 3), CFrame.new(0, 2, -20), neonCyan, Enum.Material.Neon, coverFolder)
	createPart("MidShield_South", Vector3.new(8, 4, 3), CFrame.new(0, 2, 20), neonPink, Enum.Material.Neon, coverFolder)

	-- 6. Lanes Folder
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = mapFolder

	for laneName, data in LANES_DATA do
		createPart(
			laneName,
			data.size,
			CFrame.new(data.center),
			Color3.fromRGB(40, 50, 65),
			Enum.Material.SmoothPlastic,
			lanesFolder,
			false
		)
	end

	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder

	return mapFolder
end

function CyberArenaMap.DestroyMap()
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

function CyberArenaMap.GetSpawnPoints(teamName: string): { Vector3 }
	if teamName == "Red" then
		return table.clone(RED_SPAWN_POSITIONS)
	elseif teamName == "Blue" then
		return table.clone(BLUE_SPAWN_POSITIONS)
	else
		warn("[CyberArenaMap] Invalid team name: " .. tostring(teamName))
		return {}
	end
end

function CyberArenaMap.GetCoverPositions(): { Vector3 }
	return table.clone(COVER_POSITIONS)
end

function CyberArenaMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_A_POSITION,
		siteB = SITE_B_POSITION,
	}
end

function CyberArenaMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2)
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2)
	return minBounds, maxBounds
end

function CyberArenaMap.GetLayoutData(): MapLayoutData
	local minB, maxB = CyberArenaMap.GetMapBounds()
	return {
		mapId = "CyberArena",
		mapName = "Cyber Arena",
		theme = "Sci-Fi Cyber",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = table.clone(RED_SPAWN_POSITIONS),
		blueSpawns = table.clone(BLUE_SPAWN_POSITIONS),
		sites = CyberArenaMap.GetSitePositions(),
		coverPositions = table.clone(COVER_POSITIONS),
		lanes = LANES_DATA,
	}
end

return CyberArenaMap
