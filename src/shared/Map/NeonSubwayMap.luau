--!strict
--[[
	OVERCLOCK: NeonSubwayMap

	A server-built competitive 1v1/2v2 FPS arena.
	Place this ModuleScript at ReplicatedStorage.Map.NeonSubwayMap and register it
	under the existing "NeonSubway" map name.

	Design goals:
	- Three connected routes: north concourse, contested center, south service tunnel.
	- Symmetric red/blue travel options and spawn protection.
	- Controlled medium-range sightlines with close-range alternatives.
	- Anchored primitive geometry only; no free-model scripts or runtime loops.
--]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local NeonSubwayMap = {}

export type TeamName = "Red" | "Blue"

type SpawnSet = {
	Red: { CFrame },
	Blue: { CFrame },
}

local MAP_NAME = "NeonSubway"
local MAP_OFFSET = Vector3.new(1000, 100, 0) -- offset to avoid Lobby (0,100,0) and Community (500,100,0) overlap
local FLOOR_Y = 0
local SPAWN_Y = FLOOR_Y + 4

local COLORS = {
	Concrete = Color3.fromRGB(39, 45, 56),
	ConcreteDark = Color3.fromRGB(23, 27, 35),
	Steel = Color3.fromRGB(72, 82, 96),
	SteelDark = Color3.fromRGB(34, 40, 50),
	Red = Color3.fromRGB(224, 67, 67),
	Blue = Color3.fromRGB(67, 142, 224),
	Neutral = Color3.fromRGB(232, 188, 79),
	NeonBlue = Color3.fromRGB(70, 220, 255),
	NeonPurple = Color3.fromRGB(168, 92, 255),
}

-- Red faces east (+X); Blue faces west (-X). Positions are authored before MAP_OFFSET.
local SPAWNS: SpawnSet = {
	Red = {
		CFrame.new(-61, SPAWN_Y, -9) * CFrame.Angles(0, math.rad(-90), 0),
		CFrame.new(-61, SPAWN_Y, 9) * CFrame.Angles(0, math.rad(-90), 0),
		CFrame.new(-65, SPAWN_Y, -5) * CFrame.Angles(0, math.rad(-90), 0),
		CFrame.new(-65, SPAWN_Y, 5) * CFrame.Angles(0, math.rad(-90), 0),
	},
	Blue = {
		CFrame.new(61, SPAWN_Y, 9) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(61, SPAWN_Y, -9) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(65, SPAWN_Y, 5) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(65, SPAWN_Y, -5) * CFrame.Angles(0, math.rad(90), 0),
	},
}

local function toWorld(localPosition: Vector3): Vector3
	return localPosition + MAP_OFFSET
end

local function makeFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	localPosition: Vector3,
	color: Color3,
	material: Enum.Material,
	collidable: boolean?,
	queryable: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = toWorld(localPosition)
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = if collidable == nil then true else collidable
	part.CanQuery = if queryable == nil then true else queryable
	part.CanTouch = false
	part.Parent = parent
	if part.Size.Y >= 3 and part.CollisionGroup == "Map" then
		CollectionService:AddTag(part, "BulletBlocker")
	end
	return part
end

local function makeNeonStrip(
	parent: Instance,
	name: string,
	size: Vector3,
	localPosition: Vector3,
	color: Color3
): Part
	local strip = makePart(parent, name, size, localPosition, color, Enum.Material.Neon, false, false)
	strip.CastShadow = false
	return strip
end

local function makeSpawnMarker(parent: Instance, name: string, spawnCFrame: CFrame, team: TeamName, index: number): Part
	local marker = makePart(
		parent,
		name,
		Vector3.new(3, 0.2, 3),
		spawnCFrame.Position,
		if team == "Red" then COLORS.Red else COLORS.Blue,
		Enum.Material.ForceField,
		false,
		false
	)
	marker.CFrame = CFrame.new(toWorld(spawnCFrame.Position)) * (spawnCFrame - spawnCFrame.Position)
	marker.Transparency = 0.85
	marker:SetAttribute("Team", team)
	marker:SetAttribute("SpawnIndex", index)
	return marker
end

local function addStairs(
	parent: Instance,
	namePrefix: string,
	origin: Vector3,
	direction: Vector3,
	steps: number,
	color: Color3
)
	for step = 1, steps do
		local height = step * 1.5
		local position = origin + direction * (step * 1.35) + Vector3.new(0, height * 0.5, 0)
		makePart(
			parent,
			namePrefix .. tostring(step),
			Vector3.new(8, height, 2.2),
			position,
			color,
			Enum.Material.Metal,
			true,
			true
		)
	end
end

local function addCrateStack(parent: Instance, namePrefix: string, localPosition: Vector3, mirrored: boolean)
	local xNudge = if mirrored then -1.4 else 1.4
	makePart(parent, namePrefix .. "Base", Vector3.new(5, 3.5, 5), localPosition, COLORS.Steel, Enum.Material.Metal)
	makePart(
		parent,
		namePrefix .. "Top",
		Vector3.new(3.8, 3, 3.8),
		localPosition + Vector3.new(xNudge, 3.5, 0.3),
		COLORS.SteelDark,
		Enum.Material.DiamondPlate
	)
end

local function addSide(parent: Instance, team: TeamName)
	local sign = if team == "Red" then -1 else 1
	local teamColor = if team == "Red" then COLORS.Red else COLORS.Blue
	local baseX = 57 * sign
	local spawnFolder = parent:FindFirstChild("SpawnPoints") :: Folder
	local coverFolder = parent:FindFirstChild("Cover") :: Folder
	local geometryFolder = parent:FindFirstChild("Geometry") :: Folder
	local decorationFolder = parent:FindFirstChild("Decoration") :: Folder

	-- A solid back wall and central sightline blocker protect a newly spawned player.
	makePart(geometryFolder, team .. "SpawnBackWall", Vector3.new(2, 12, 34), Vector3.new(72 * sign, 6, 0), COLORS.ConcreteDark, Enum.Material.Concrete)
	makePart(geometryFolder, team .. "SpawnNorthWall", Vector3.new(12, 8, 2), Vector3.new(baseX, 4, -17), COLORS.Concrete, Enum.Material.Concrete)
	makePart(geometryFolder, team .. "SpawnSouthWall", Vector3.new(12, 8, 2), Vector3.new(baseX, 4, 17), COLORS.Concrete, Enum.Material.Concrete)
	makePart(coverFolder, team .. "SpawnSightBlocker", Vector3.new(4, 7, 20), Vector3.new(48 * sign, 3.5, 0), COLORS.SteelDark, Enum.Material.Metal)
	makePart(coverFolder, team .. "NorthExitCover", Vector3.new(7, 5.0, 3), Vector3.new(45 * sign, 2.5, -15), COLORS.Steel, Enum.Material.DiamondPlate)
	makePart(coverFolder, team .. "SouthExitCover", Vector3.new(7, 5.0, 3), Vector3.new(45 * sign, 2.5, 15), COLORS.Steel, Enum.Material.DiamondPlate)
	makeNeonStrip(decorationFolder, team .. "SpawnColorStrip", Vector3.new(0.25, 0.7, 24), Vector3.new(70 * sign, 8, 0), teamColor)
	makeNeonStrip(decorationFolder, team .. "ExitGuidance", Vector3.new(15, 0.15, 0.35), Vector3.new(53 * sign, 1.15, 0), teamColor)

	local sideSpawns = SPAWNS[team]
	for index, spawnCFrame in ipairs(sideSpawns) do
		makeSpawnMarker(spawnFolder, team .. "Spawn" .. tostring(index), spawnCFrame, team, index)
	end
end

function NeonSubwayMap.GetName(): string
	return MAP_NAME
end

function NeonSubwayMap.GetOffset(): Vector3
	return MAP_OFFSET
end

function NeonSubwayMap.GetSpawnPoints(team: TeamName): { Vector3 }
	local source = SPAWNS[team]
	local points: { Vector3 } = {}
	for _, spawnCFrame in ipairs(source) do
		table.insert(points, toWorld(spawnCFrame.Position))
	end
	return points
end

function NeonSubwayMap.GetSpawnCFrames(team: TeamName): { CFrame }
	local source = SPAWNS[team]
	local points: { CFrame } = {}
	for _, spawnCFrame in ipairs(source) do
		table.insert(points, CFrame.new(MAP_OFFSET) * spawnCFrame)
	end
	return points
end

function NeonSubwayMap.GetObjectiveCFrame(): CFrame
	return CFrame.new(toWorld(Vector3.new(0, 3, 0)))
end

function NeonSubwayMap.GetMapBounds(): (Vector3, Vector3)
	return toWorld(Vector3.new(-76, -8, -54)), toWorld(Vector3.new(76, 28, 54))
end

function NeonSubwayMap.BuildMap(parent: Instance?): Folder
	local targetParent = parent or Workspace
	local existing = targetParent:FindFirstChild(MAP_NAME)
	if existing then
		existing:Destroy()
	end

	local mapFolder = makeFolder(targetParent, MAP_NAME)
	mapFolder:SetAttribute("MapName", MAP_NAME)
	mapFolder:SetAttribute("RecommendedModes", "1v1,2v2")
	mapFolder:SetAttribute("MapOffset", MAP_OFFSET)
	mapFolder:SetAttribute("BuildVersion", 1)

	local geometry = makeFolder(mapFolder, "Geometry")
	local cover = makeFolder(mapFolder, "Cover")
	makeFolder(mapFolder, "SpawnPoints")
	local objectives = makeFolder(mapFolder, "Objectives")
	local decoration = makeFolder(mapFolder, "Decoration")
	local boundaries = makeFolder(mapFolder, "Boundaries")

	-- Walkable floor plan: two team platforms, central platform, and two outer loops.
	makePart(geometry, "RedPlatform", Vector3.new(34, 2, 38), Vector3.new(-56, FLOOR_Y, 0), COLORS.Concrete, Enum.Material.Concrete)
	makePart(geometry, "BluePlatform", Vector3.new(34, 2, 38), Vector3.new(56, FLOOR_Y, 0), COLORS.Concrete, Enum.Material.Concrete)
	makePart(geometry, "CentralPlatform", Vector3.new(32, 2, 32), Vector3.new(0, FLOOR_Y, 0), COLORS.ConcreteDark, Enum.Material.Slate)
	makePart(geometry, "NorthConcourseFloor", Vector3.new(120, 2, 16), Vector3.new(0, FLOOR_Y, -29), COLORS.Concrete, Enum.Material.Concrete)
	makePart(geometry, "SouthServiceFloor", Vector3.new(120, 2, 16), Vector3.new(0, FLOOR_Y, 29), COLORS.ConcreteDark, Enum.Material.Concrete)
	makePart(geometry, "NorthCenterBridge", Vector3.new(26, 2, 12), Vector3.new(0, FLOOR_Y, -17), COLORS.Concrete, Enum.Material.Concrete)
	makePart(geometry, "SouthCenterBridge", Vector3.new(26, 2, 12), Vector3.new(0, FLOOR_Y, 17), COLORS.Concrete, Enum.Material.Concrete)

	-- Perimeter: collidable walls and a lower kill-plane marker for integration with an out-of-bounds service.
	makePart(boundaries, "NorthBoundary", Vector3.new(156, 18, 2), Vector3.new(0, 9, -53), COLORS.ConcreteDark, Enum.Material.Concrete)
	makePart(boundaries, "SouthBoundary", Vector3.new(156, 18, 2), Vector3.new(0, 9, 53), COLORS.ConcreteDark, Enum.Material.Concrete)
	makePart(boundaries, "WestBoundary", Vector3.new(2, 18, 108), Vector3.new(-77, 9, 0), COLORS.ConcreteDark, Enum.Material.Concrete)
	makePart(boundaries, "EastBoundary", Vector3.new(2, 18, 108), Vector3.new(77, 9, 0), COLORS.ConcreteDark, Enum.Material.Concrete)
	local killPlane = makePart(boundaries, "KillPlane", Vector3.new(170, 1, 120), Vector3.new(0, -12, 0), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, false, false)
	killPlane.Transparency = 1
	killPlane:SetAttribute("OutOfBounds", true)

	-- Central focal point. Four cover pieces break the longest cross-map sightlines without hiding the objective.
	local objectivePad = makePart(objectives, "ControlNode", Vector3.new(10, 1, 10), Vector3.new(0, 1.5, 0), COLORS.Neutral, Enum.Material.DiamondPlate)
	objectivePad:SetAttribute("ObjectiveType", "Control")
	objectivePad:SetAttribute("ObjectiveId", "CentralNode")
	makeNeonStrip(decoration, "ObjectiveRingNorth", Vector3.new(8, 0.25, 0.3), Vector3.new(0, 2.1, -4.2), COLORS.NeonBlue)
	makeNeonStrip(decoration, "ObjectiveRingSouth", Vector3.new(8, 0.25, 0.3), Vector3.new(0, 2.1, 4.2), COLORS.NeonBlue)
	makePart(cover, "CenterCoverNorthWest", Vector3.new(6, 3.5, 3), Vector3.new(-9, 2, -7), COLORS.Steel, Enum.Material.Metal)
	makePart(cover, "CenterCoverNorthEast", Vector3.new(6, 3.5, 3), Vector3.new(9, 2, -7), COLORS.Steel, Enum.Material.Metal)
	makePart(cover, "CenterCoverSouthWest", Vector3.new(6, 3.5, 3), Vector3.new(-9, 2, 7), COLORS.Steel, Enum.Material.Metal)
	makePart(cover, "CenterCoverSouthEast", Vector3.new(6, 3.5, 3), Vector3.new(9, 2, 7), COLORS.Steel, Enum.Material.Metal)

	-- North: medium-range concourse. Angled freight cover prevents an uninterrupted sniper lane.
	for _, spec in ipairs({
		{ "NorthFreightWest", Vector3.new(-34, 4, -29), Vector3.new(13, 8, 4) },
		{ "NorthFreightEast", Vector3.new(34, 4, -29), Vector3.new(13, 8, 4) },
		{ "NorthMidWest", Vector3.new(-14, 3, -29), Vector3.new(7, 6, 5) },
		{ "NorthMidEast", Vector3.new(14, 3, -29), Vector3.new(7, 6, 5) },
	}) do
		makePart(cover, spec[1] :: string, spec[3] :: Vector3, spec[2] :: Vector3, COLORS.Steel, Enum.Material.Metal)
	end
	makePart(cover, "NorthCenterDivider", Vector3.new(4, 6, 12), Vector3.new(0, 3, -31), COLORS.SteelDark, Enum.Material.DiamondPlate)

	-- South: a lower-risk close-quarters service loop with mixed-height crate cover.
	addCrateStack(cover, "SouthCratesWest", Vector3.new(-34, 2, 29), false)
	addCrateStack(cover, "SouthCratesEast", Vector3.new(34, 2, 29), true)
	addCrateStack(cover, "SouthCratesInnerWest", Vector3.new(-16, 2, 29), true)
	addCrateStack(cover, "SouthCratesInnerEast", Vector3.new(16, 2, 29), false)
	makePart(cover, "SouthCenterBarrierWest", Vector3.new(8, 5, 3), Vector3.new(-6, 2.5, 29), COLORS.Steel, Enum.Material.DiamondPlate)
	makePart(cover, "SouthCenterBarrierEast", Vector3.new(8, 5, 3), Vector3.new(6, 2.5, 29), COLORS.Steel, Enum.Material.DiamondPlate)

	-- Two small, counterable catwalks. They have mirrored stairs from both directions.
	for _, sign in ipairs({ -1, 1 }) do
		local sideName = if sign < 0 then "West" else "East"
		local catwalkX = 23 * sign
		makePart(geometry, sideName .. "Catwalk", Vector3.new(15, 2, 8), Vector3.new(catwalkX, 9, -21), COLORS.SteelDark, Enum.Material.Metal)
		makePart(cover, sideName .. "CatwalkRail", Vector3.new(15, 2, 0.5), Vector3.new(catwalkX, 11, -24.6), COLORS.Steel, Enum.Material.Metal)
		addStairs(geometry, sideName .. "CatwalkNorthStep", Vector3.new(catwalkX, 1, -29), Vector3.new(0, 0, 1), 6, COLORS.Steel)
		addStairs(geometry, sideName .. "CatwalkSouthStep", Vector3.new(catwalkX, 1, -13), Vector3.new(0, 0, -1), 6, COLORS.Steel)
		makeNeonStrip(decoration, sideName .. "CatwalkStripe", Vector3.new(12, 0.15, 0.25), Vector3.new(catwalkX, 10.1, -20.5), COLORS.NeonPurple)
	end

	-- Visual guidance is deliberately non-collidable and low-density.
	makeNeonStrip(decoration, "NorthRouteStripe", Vector3.new(106, 0.12, 0.25), Vector3.new(0, 1.08, -36), COLORS.NeonBlue)
	makeNeonStrip(decoration, "SouthRouteStripe", Vector3.new(106, 0.12, 0.25), Vector3.new(0, 1.08, 36), COLORS.NeonPurple)
	makeNeonStrip(decoration, "CenterRouteStripe", Vector3.new(18, 0.12, 0.25), Vector3.new(0, 1.08, 0), COLORS.Neutral)

	addSide(mapFolder, "Red")
	addSide(mapFolder, "Blue")

	return mapFolder
end

return NeonSubwayMap
