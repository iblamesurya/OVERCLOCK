--!strict
--[=[
    Project OVERCLOCK v2: DuelArenaMap (Legendary Edition)

    Research-backed competitive 1v1 / 2v2 tactical arena:
    - 3-lane design with symmetrical travel times [web:25][web:39]
    - Rotational symmetry (180°) so both teams have identical layouts [web:34]
    - Choke points, connectors, risk/reward high ground [web:35][web:43]
    - Tiered cover (Low / Mid / High) with health attributes
    - Proper SpawnLocation instances + team platforms
    - Capture / control sites with neon rings + billboards
    - Full lighting rig attributes + ambient FX
    - No duplicate geometry (legacy Red/Blue aliases via attributes only)
]=]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local DuelArenaMap = {}

-- Types ----------------------------------------------------------------------

export type MapBounds = {
	min: Vector3,
	max: Vector3,
}

export type SitePositions = {
	siteA: Vector3,
	siteB: Vector3,
}

export type MapLayoutData = {
	mapId: string,
	mapName: string,
	theme: string,
	bounds: MapBounds,
	redSpawns: { Vector3 },
	blueSpawns: { Vector3 },
	sites: SitePositions?,
	coverPositions: { Vector3 },
	lanes: { [string]: { center: Vector3, size: Vector3 } },
}

-- Constants ------------------------------------------------------------------

local MAP_FOLDER_NAME = "DuelArenaMap"
local _activeMapFolder: Folder? = nil
local _activeTweens: { Tween } = {}

local MAP_WIDTH_X = 120
local MAP_LENGTH_Z = 160
local MAP_HEIGHT_Y = 32

local MAP_OFFSET = Vector3.new(-500, 100, 0)

local C = {
	FLOOR       = Color3.fromRGB(22, 26, 34),
	FLOOR_ALT   = Color3.fromRGB(28, 32, 42),
	WALL        = Color3.fromRGB(40, 46, 56),
	WALL_ACCENT = Color3.fromRGB(55, 62, 74),
	TRIM        = Color3.fromRGB(65, 72, 88),
	CONCRETE    = Color3.fromRGB(50, 56, 66),
	NEON_CYAN   = Color3.fromRGB(0, 210, 255),
	NEON_BLUE   = Color3.fromRGB(0, 140, 255),
	NEON_RED    = Color3.fromRGB(255, 55, 55),
	NEON_GREEN  = Color3.fromRGB(0, 230, 140),
	NEON_GOLD   = Color3.fromRGB(255, 190, 50),
	SITE_TEAL   = Color3.fromRGB(0, 220, 190),
	GLASS       = Color3.fromRGB(120, 190, 240),
	WHITE       = Color3.fromRGB(220, 235, 255),
}

-- Spawns (4 per team, clustered for 1v1 / 2v2) -------------------------------
local TEAM1_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-10, 2, -62),
	Vector3.new(10, 2, -62),
	Vector3.new(-4, 2, -66),
	Vector3.new(4, 2, -66),
}

local TEAM2_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(-10, 2, 62),
	Vector3.new(10, 2, 62),
	Vector3.new(-4, 2, 66),
	Vector3.new(4, 2, 66),
}

local SITE_POSITIONS = {
	siteA = Vector3.new(-32, 1, 0),
	siteB = Vector3.new(32, 1, 0),
}

-- Lane metadata (world-space centers before offset) --------------------------
local LANES_DATA: { [string]: { center: Vector3, size: Vector3 } } = {
	MainLane = { center = Vector3.new(0, 0.2, 0), size = Vector3.new(22, 0.4, 124) },
	LeftFlank = { center = Vector3.new(-40, 0.2, 0), size = Vector3.new(18, 0.4, 124) },
	RightFlank = { center = Vector3.new(40, 0.2, 0), size = Vector3.new(18, 0.4, 124) },
	Connector_North = { center = Vector3.new(0, 0.2, -28), size = Vector3.new(62, 0.4, 14) },
	Connector_South = { center = Vector3.new(0, 0.2, 28), size = Vector3.new(62, 0.4, 14) },
}

-- Cover definitions (tiered + rotational pairs) ------------------------------
type CoverDef = {
	name: string,
	pos: Vector3,
	size: Vector3,
	tier: string, -- "Low" | "Mid" | "High" | "Pillar"
	health: number,
	rotation: number?, -- yaw degrees
}

local COVER_DEFS: { CoverDef } = {
	-- Mid lane
	{ name = "Pillar_Center", pos = Vector3.new(0, 6, 0), size = Vector3.new(7, 12, 7), tier = "Pillar", health = 9999 },
	{ name = "LowCover_Mid_N", pos = Vector3.new(0, 1.75, -22), size = Vector3.new(8, 3.5, 3.5), tier = "Low", health = 120 },
	{ name = "LowCover_Mid_S", pos = Vector3.new(0, 1.75, 22), size = Vector3.new(8, 3.5, 3.5), tier = "Low", health = 120 },
	{ name = "MidCover_Mid_N", pos = Vector3.new(0, 1.75, -38), size = Vector3.new(5, 3.5, 4), tier = "Mid", health = 220 },
	{ name = "MidCover_Mid_S", pos = Vector3.new(0, 1.75, 38), size = Vector3.new(5, 3.5, 4), tier = "Mid", health = 220 },

	-- Left flank
	{ name = "LowCover_Left_N", pos = Vector3.new(-40, 1.75, -28), size = Vector3.new(4, 3.5, 9), tier = "Low", health = 120 },
	{ name = "LowCover_Left_S", pos = Vector3.new(-40, 1.75, 28), size = Vector3.new(4, 3.5, 9), tier = "Low", health = 120 },
	{ name = "MidCover_Left_Mid", pos = Vector3.new(-38, 1.75, 0), size = Vector3.new(5, 3.5, 6), tier = "Mid", health = 220 },

	-- Right flank
	{ name = "LowCover_Right_N", pos = Vector3.new(40, 1.75, -28), size = Vector3.new(4, 3.5, 9), tier = "Low", health = 120 },
	{ name = "LowCover_Right_S", pos = Vector3.new(40, 1.75, 28), size = Vector3.new(4, 3.5, 9), tier = "Low", health = 120 },
	{ name = "MidCover_Right_Mid", pos = Vector3.new(38, 1.75, 0), size = Vector3.new(5, 3.5, 6), tier = "Mid", health = 220 },

	-- Connector choke blocks
	{ name = "Choke_NW", pos = Vector3.new(-18, 1.75, -28), size = Vector3.new(4, 3.5, 4), tier = "Mid", health = 200 },
	{ name = "Choke_NE", pos = Vector3.new(18, 1.75, -28), size = Vector3.new(4, 3.5, 4), tier = "Mid", health = 200 },
	{ name = "Choke_SW", pos = Vector3.new(-18, 1.75, 28), size = Vector3.new(4, 3.5, 4), tier = "Mid", health = 200 },
	{ name = "Choke_SE", pos = Vector3.new(18, 1.75, 28), size = Vector3.new(4, 3.5, 4), tier = "Mid", health = 200 },
}

local COVER_POSITIONS: { Vector3 } = {}
for _, d in COVER_DEFS do
	table.insert(COVER_POSITIONS, d.pos)
end

-- Helpers --------------------------------------------------------------------

local function createPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance,
	canCollide: boolean?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe + MAP_OFFSET
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = if canCollide ~= nil then canCollide else true
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = (transparency or 0) < 0.5
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

local function addLight(parent: Instance, color: Color3, range: number, brightness: number, spot: boolean?)
	if spot then
		local s = Instance.new("SpotLight")
		s.Color = color
		s.Range = range
		s.Brightness = brightness
		s.Angle = 95
		s.Face = Enum.NormalId.Bottom
		s.Parent = parent
	else
		local p = Instance.new("PointLight")
		p.Color = color
		p.Range = range
		p.Brightness = brightness
		p.Parent = parent
	end
end

local function makeBillboard(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	size: UDim2,
	offset: Vector3,
	textSize: number
)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = size
	bb.StudsOffset = offset
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = textSize
	lbl.Text = text
	lbl.TextStrokeTransparency = 0.45
	lbl.Parent = bb
end

local function cleanup()
	for _, t in _activeTweens do
		t:Cancel()
	end
	table.clear(_activeTweens)
	if _activeMapFolder then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

-- Build ----------------------------------------------------------------------

function DuelArenaMap.BuildMap(parent: Instance?): Folder
	cleanup()

	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	------------------------------------------------------------------------
	-- 1. Perimeter & Floor (dark tactical base)
	------------------------------------------------------------------------
	local perimeter = Instance.new("Folder")
	perimeter.Name = "Perimeter"
	perimeter.Parent = mapFolder

	createPart("MainFloor", Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, -1, 0), C.FLOOR, Enum.Material.Concrete, perimeter, true)

	-- Subtle center lane inlay (navigation landmark)
	createPart("FloorInlay_Mid", Vector3.new(1.5, 0.06, MAP_LENGTH_Z - 8),
		CFrame.new(0, 0.03, 0), C.NEON_CYAN, Enum.Material.Neon, perimeter, false, 0.45)
	createPart("FloorInlay_Left", Vector3.new(1.2, 0.06, MAP_LENGTH_Z - 8),
		CFrame.new(-40, 0.03, 0), C.NEON_BLUE, Enum.Material.Neon, perimeter, false, 0.55)
	createPart("FloorInlay_Right", Vector3.new(1.2, 0.06, MAP_LENGTH_Z - 8),
		CFrame.new(40, 0.03, 0), C.NEON_BLUE, Enum.Material.Neon, perimeter, false, 0.55)

	local wallColor = C.WALL
	for _, w in {
		{ "NorthWall", Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2), CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2) },
		{ "SouthWall", Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2), CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2) },
		{ "WestWall", Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z), CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0) },
		{ "EastWall", Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z), CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0) },
	} do
		createPart(w[1] :: string, w[2] :: Vector3, w[3] :: CFrame, wallColor,
			Enum.Material.Concrete, perimeter, true)
		createPart((w[1] :: string) .. "_Accent",
			Vector3.new((w[2] :: Vector3).X, 0.8, (w[2] :: Vector3).Z),
			(w[3] :: CFrame) * CFrame.new(0, MAP_HEIGHT_Y / 2 - 1.2, 0),
			C.NEON_CYAN, Enum.Material.Neon, perimeter, false, 0.15)
	end

	-- Invisible ceiling
	createPart("CeilingBarrier", Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, MAP_HEIGHT_Y, 0), Color3.new(),
		Enum.Material.SmoothPlastic, perimeter, true, 1)

	------------------------------------------------------------------------
	-- 2. Lanes (visual floor strips + metadata attributes)
	------------------------------------------------------------------------
	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = mapFolder

	for laneName, data in LANES_DATA do
		local lane = createPart(laneName, data.size, CFrame.new(data.center),
			C.FLOOR_ALT, Enum.Material.SmoothPlastic, lanesFolder, false, 0.35)
		lane:SetAttribute("LaneName", laneName)
		lane:SetAttribute("IsLane", true)
	end

	------------------------------------------------------------------------
	-- 3. Team Spawns (single geometry, dual attributes, real SpawnLocations)
	------------------------------------------------------------------------
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = mapFolder

	local function buildTeamSpawn(
		folderName: string,
		legacyName: string,
		teamAttr: string,
		legacyTeam: string,
		positions: { Vector3 },
		platformZ: number,
		teamColor: Color3,
		neonColor: Color3,
		brickTeam: string
	)
		local teamFolder = Instance.new("Folder")
		teamFolder.Name = folderName
		teamFolder.Parent = spawnsFolder

		-- Legacy alias folder (empty, for FindFirstChild compatibility)
		local legacyFolder = Instance.new("Folder")
		legacyFolder.Name = legacyName
		legacyFolder.Parent = spawnsFolder
		legacyFolder:SetAttribute("AliasOf", folderName)
		legacyFolder:SetAttribute("Team", legacyTeam)

		-- Raised spawn platform
		local platform = createPart("Platform_" .. folderName, Vector3.new(38, 1, 22),
			CFrame.new(0, 0.5, platformZ), teamColor, Enum.Material.Metal, teamFolder, true)
		createPart("PlatformEdge_" .. folderName, Vector3.new(38.4, 0.25, 0.6),
			CFrame.new(0, 1.1, platformZ + (if platformZ < 0 then 11 else -11)),
			neonColor, Enum.Material.Neon, teamFolder, false, 0.1)
		addLight(platform, neonColor, 18, 1.2)

		makeBillboard(platform, folderName .. "Label",
			"[ " .. string.upper(legacyTeam) .. " SPAWN ]",
			neonColor, UDim2.new(0, 280, 0, 50), Vector3.new(0, 8, 0), 22)

		for i, pos in positions do
			-- Visual pad
			local pad = createPart("Spawn_" .. folderName .. "_" .. i, Vector3.new(4.5, 0.4, 4.5),
				CFrame.new(pos - Vector3.new(0, 0.3, 0)), C.TRIM,
				Enum.Material.Metal, teamFolder, true)
			createPart("SpawnRing_" .. folderName .. "_" .. i, Vector3.new(5, 0.15, 5),
				CFrame.new(pos - Vector3.new(0, 0.55, 0)), neonColor,
				Enum.Material.Neon, teamFolder, false, 0.2)
			pad:SetAttribute("Team", teamAttr)
			pad:SetAttribute("LegacyTeam", legacyTeam)
			pad:SetAttribute("SpawnIndex", i)
			pad:SetAttribute("Index", i)

			-- Real SpawnLocation (Neutral = false for team games if you set teams later)
			local spawnLoc = Instance.new("SpawnLocation")
			spawnLoc.Name = "SpawnLocation_" .. folderName .. "_" .. i
			spawnLoc.Size = Vector3.new(4, 0.35, 4)
			spawnLoc.CFrame = CFrame.new(pos) + MAP_OFFSET
			spawnLoc.Anchored = true
			spawnLoc.CanCollide = true
			spawnLoc.Neutral = true
			spawnLoc.AllowTeamChangeOnTouch = false
			spawnLoc.TeamColor = BrickColor.new(brickTeam)
			spawnLoc.Color = neonColor
			spawnLoc.Material = Enum.Material.SmoothPlastic
			spawnLoc.TopSurface = Enum.SurfaceType.Smooth
			spawnLoc.BottomSurface = Enum.SurfaceType.Smooth
			spawnLoc:SetAttribute("Team", teamAttr)
			spawnLoc:SetAttribute("LegacyTeam", legacyTeam)
			spawnLoc:SetAttribute("SpawnIndex", i)
			spawnLoc.Parent = teamFolder

			-- Lightweight proxy in legacy folder (for old scripts that scan RedSpawn/BlueSpawn)
			local proxy = Instance.new("ObjectValue")
			proxy.Name = "SpawnPoint" .. i
			proxy.Value = spawnLoc
			proxy:SetAttribute("Team", legacyTeam)
			proxy:SetAttribute("Index", i)
			proxy.Parent = legacyFolder
		end
	end

	buildTeamSpawn("Team1Spawn", "RedSpawn", "Team1", "Red",
		TEAM1_SPAWN_POSITIONS, -62, Color3.fromRGB(140, 35, 40), C.NEON_RED, "Bright red")
	buildTeamSpawn("Team2Spawn", "BlueSpawn", "Team2", "Blue",
		TEAM2_SPAWN_POSITIONS, 62, Color3.fromRGB(25, 90, 160), C.NEON_BLUE, "Bright blue")

	-- Spawn safety barriers (prevent early spawn peeks)
	createPart("SpawnGate_Team1", Vector3.new(40, 8, 1.5),
		CFrame.new(0, 4, -50), C.WALL_ACCENT, Enum.Material.Concrete, spawnsFolder, true)
	createPart("SpawnGate_Team2", Vector3.new(40, 8, 1.5),
		CFrame.new(0, 4, 50), C.WALL_ACCENT, Enum.Material.Concrete, spawnsFolder, true)
	-- Gate doors (semi-open corridors)
	createPart("SpawnGateDoor_T1_L", Vector3.new(8, 6, 1.2),
		CFrame.new(-14, 3, -50), C.TRIM, Enum.Material.Metal, spawnsFolder, true)
	createPart("SpawnGateDoor_T1_R", Vector3.new(8, 6, 1.2),
		CFrame.new(14, 3, -50), C.TRIM, Enum.Material.Metal, spawnsFolder, true)
	createPart("SpawnGateDoor_T2_L", Vector3.new(8, 6, 1.2),
		CFrame.new(-14, 3, 50), C.TRIM, Enum.Material.Metal, spawnsFolder, true)
	createPart("SpawnGateDoor_T2_R", Vector3.new(8, 6, 1.2),
		CFrame.new(14, 3, 50), C.TRIM, Enum.Material.Metal, spawnsFolder, true)

	------------------------------------------------------------------------
	-- 4. Control Sites (A / B) with rings, lights, prompts hooks
	------------------------------------------------------------------------
	local sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "Sites"
	sitesFolder.Parent = mapFolder

	local function buildSite(name: string, siteKey: string, pos: Vector3, accent: Color3)
		local pad = createPart(name, Vector3.new(18, 0.35, 18),
			CFrame.new(pos), accent, Enum.Material.Neon, sitesFolder, false, 0.55)
		pad:SetAttribute("SiteName", siteKey)
		pad:SetAttribute("IsSite", true)

		createPart(name .. "_RingOuter", Vector3.new(20, 0.2, 20),
			CFrame.new(pos - Vector3.new(0, 0.1, 0)), accent,
			Enum.Material.Neon, sitesFolder, false, 0.25)
		createPart(name .. "_RingInner", Vector3.new(10, 0.25, 10),
			CFrame.new(pos + Vector3.new(0, 0.05, 0)), C.WHITE,
			Enum.Material.Neon, sitesFolder, false, 0.4)

		-- Soft pillars at corners of site
		for i, off in {
			Vector3.new(-8, 2.5, -8), Vector3.new(8, 2.5, -8),
			Vector3.new(-8, 2.5, 8), Vector3.new(8, 2.5, 8),
		} do
			local p = createPart(name .. "_Pillar" .. i, Vector3.new(1.2, 5, 1.2),
				CFrame.new(pos + off), C.TRIM, Enum.Material.Metal, sitesFolder, true)
			addLight(p, accent, 10, 0.8)
		end

		makeBillboard(pad, name .. "Billboard", "[ SITE " .. siteKey .. " ]",
			accent, UDim2.new(0, 220, 0, 48), Vector3.new(0, 7, 0), 24)

		-- Capture volume (invisible)
		local vol = createPart(name .. "_CaptureVolume", Vector3.new(16, 8, 16),
			CFrame.new(pos + Vector3.new(0, 4, 0)), Color3.new(),
			Enum.Material.SmoothPlastic, sitesFolder, false, 1)
		vol.CanCollide = false
		vol.CanTouch = true
		vol:SetAttribute("SiteName", siteKey)
		vol:SetAttribute("IsCaptureVolume", true)
	end

	buildSite("SiteA", "A", SITE_POSITIONS.siteA, C.SITE_TEAL)
	buildSite("SiteB", "B", SITE_POSITIONS.siteB, C.NEON_GOLD)

	------------------------------------------------------------------------
	-- 5. Cover & Structures
	------------------------------------------------------------------------
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	local tierColor = {
		Low = C.TRIM,
		Mid = C.WALL_ACCENT,
		High = C.CONCRETE,
		Pillar = C.CONCRETE,
	}

	for _, def in COVER_DEFS do
		local cf = CFrame.new(def.pos)
		if def.rotation then
			cf = cf * CFrame.Angles(0, math.rad(def.rotation), 0)
		end
		local part = createPart(def.name, def.size, cf,
			tierColor[def.tier] or C.TRIM, Enum.Material.Concrete, coverFolder, true)
		part:SetAttribute("CoverTier", def.tier)
		part:SetAttribute("CoverHealth", def.health)
		part:SetAttribute("MaxHealth", def.health)
		part:SetAttribute("IsCover", true)

		if def.tier == "Pillar" or def.tier == "High" then
			createPart(def.name .. "_Trim",
				Vector3.new(def.size.X + 0.3, 0.25, def.size.Z + 0.3),
				CFrame.new(def.pos + Vector3.new(0, def.size.Y / 2, 0)),
				C.NEON_CYAN, Enum.Material.Neon, coverFolder, false, 0.2)
		end
	end

	-- Barrel clusters near connectors (prop clustering)
	for _, bPos in {
		Vector3.new(-12, 1.4, -18), Vector3.new(-10, 1.4, -16),
		Vector3.new(12, 1.4, 18), Vector3.new(10, 1.4, 16),
		Vector3.new(-42, 1.4, 8), Vector3.new(42, 1.4, -8),
	} do
		local barrel = createPart("Barrel", Vector3.new(2, 2.8, 2),
			CFrame.new(bPos), C.NEON_GOLD, Enum.Material.Metal, coverFolder, true)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CFrame = (CFrame.new(bPos) * CFrame.Angles(0, 0, math.rad(90))) + MAP_OFFSET
		barrel:SetAttribute("CoverTier", "Barrel")
		barrel:SetAttribute("CoverHealth", 40)
		barrel:SetAttribute("MaxHealth", 40)
		barrel:SetAttribute("IsExplosive", true)
	end

	------------------------------------------------------------------------
	-- 6. High Ground / Sniper Perches (risk vs reward, mirrored)
	------------------------------------------------------------------------
	local highGround = Instance.new("Folder")
	highGround.Name = "HighGround"
	highGround.Parent = mapFolder

	-- Team1 side perch (NW) — favors Team1 approaching mid-left
	createPart("Perch_NW_Platform", Vector3.new(14, 1.5, 12),
		CFrame.new(-44, 6, -48), C.TRIM, Enum.Material.Metal, highGround, true)
	createPart("Perch_NW_RailN", Vector3.new(14, 0.3, 0.4),
		CFrame.new(-44, 7.2, -54), C.NEON_RED, Enum.Material.Neon, highGround, false, 0.15)
	createPart("Perch_NW_RailS", Vector3.new(14, 0.3, 0.4),
		CFrame.new(-44, 7.2, -42), C.NEON_RED, Enum.Material.Neon, highGround, false, 0.15)
	createWedge("Ramp_NW", Vector3.new(8, 6, 12),
		CFrame.new(-44, 3, -58), C.CONCRETE, Enum.Material.Concrete, highGround)
	createPart("Perch_NW_Support", Vector3.new(2, 6, 2),
		CFrame.new(-44, 3, -48), C.WALL, Enum.Material.Concrete, highGround, true)
	addLight(highGround:FindFirstChild("Perch_NW_Platform") :: BasePart, C.NEON_RED, 14, 1)
	makeBillboard(highGround:FindFirstChild("Perch_NW_Platform") :: BasePart,
		"PerchNW_Label", "PERCH", C.NEON_RED, UDim2.new(0, 120, 0, 36), Vector3.new(0, 4, 0), 18)

	-- Team2 side perch (SE) — 180° rotational pair
	createPart("Perch_SE_Platform", Vector3.new(14, 1.5, 12),
		CFrame.new(44, 6, 48), C.TRIM, Enum.Material.Metal, highGround, true)
	createPart("Perch_SE_RailN", Vector3.new(14, 0.3, 0.4),
		CFrame.new(44, 7.2, 42), C.NEON_BLUE, Enum.Material.Neon, highGround, false, 0.15)
	createPart("Perch_SE_RailS", Vector3.new(14, 0.3, 0.4),
		CFrame.new(44, 7.2, 54), C.NEON_BLUE, Enum.Material.Neon, highGround, false, 0.15)
	createWedge("Ramp_SE", Vector3.new(8, 6, 12),
		CFrame.new(44, 3, 58) * CFrame.Angles(0, math.pi, 0),
		C.CONCRETE, Enum.Material.Concrete, highGround)
	createPart("Perch_SE_Support", Vector3.new(2, 6, 2),
		CFrame.new(44, 3, 48), C.WALL, Enum.Material.Concrete, highGround, true)
	addLight(highGround:FindFirstChild("Perch_SE_Platform") :: BasePart, C.NEON_BLUE, 14, 1)
	makeBillboard(highGround:FindFirstChild("Perch_SE_Platform") :: BasePart,
		"PerchSE_Label", "PERCH", C.NEON_BLUE, UDim2.new(0, 120, 0, 36), Vector3.new(0, 4, 0), 18)

	-- Secondary mid-height balconies (risk/reward near sites)
	createPart("Balcony_West", Vector3.new(10, 1.2, 8),
		CFrame.new(-48, 4.5, 0), C.TRIM, Enum.Material.Metal, highGround, true)
	createWedge("Balcony_West_Ramp", Vector3.new(6, 4, 8),
		CFrame.new(-48, 2, -8) * CFrame.Angles(0, math.rad(90), 0),
		C.CONCRETE, Enum.Material.Concrete, highGround)
	createPart("Balcony_East", Vector3.new(10, 1.2, 8),
		CFrame.new(48, 4.5, 0), C.TRIM, Enum.Material.Metal, highGround, true)
	createWedge("Balcony_East_Ramp", Vector3.new(6, 4, 8),
		CFrame.new(48, 2, 8) * CFrame.Angles(0, math.rad(-90), 0),
		C.CONCRETE, Enum.Material.Concrete, highGround)

	------------------------------------------------------------------------
	-- 7. Mid Landmark (center pillar details)
	------------------------------------------------------------------------
	local landmark = Instance.new("Folder")
	landmark.Name = "Landmark"
	landmark.Parent = mapFolder

	local centerCore = createPart("CenterCore", Vector3.new(4, 10, 4),
		CFrame.new(0, 6, 0), C.NEON_CYAN, Enum.Material.Neon, landmark, false, 0.35)
	addLight(centerCore, C.NEON_CYAN, 22, 2)
	makeBillboard(centerCore, "MidLabel", "⬡ MID ⬡", C.WHITE,
		UDim2.new(0, 160, 0, 40), Vector3.new(0, 8, 0), 20)

	-- Soft spin on core for life
	local spin = TweenService:Create(centerCore,
		TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ CFrame = (CFrame.new(0, 6, 0) + MAP_OFFSET) * CFrame.Angles(0, math.rad(360), 0) })
	spin:Play()
	table.insert(_activeTweens, spin)

	------------------------------------------------------------------------
	-- 8. Lighting Rig + Atmosphere attributes
	------------------------------------------------------------------------
	local lightingFolder = Instance.new("Folder")
	lightingFolder.Name = "LightingRig"
	lightingFolder.Parent = mapFolder

	for _, lx in { -35, 0, 35 } do
		for _, lz in { -40, 0, 40 } do
			local strip = createPart("CeilLight_" .. lx .. "_" .. lz,
				Vector3.new(6, 0.4, 6),
				CFrame.new(lx, MAP_HEIGHT_Y - 1.5, lz),
				Color3.fromRGB(190, 220, 255), Enum.Material.Neon, lightingFolder, false, 0.25)
			addLight(strip, Color3.fromRGB(170, 210, 255), 35, 1.8, true)
		end
	end

	-- Team-colored ambient strips near spawns
	createPart("AmbientStrip_Red", Vector3.new(36, 0.4, 2),
		CFrame.new(0, 12, -70), C.NEON_RED, Enum.Material.Neon, lightingFolder, false, 0.2)
	createPart("AmbientStrip_Blue", Vector3.new(36, 0.4, 2),
		CFrame.new(0, 12, 70), C.NEON_BLUE, Enum.Material.Neon, lightingFolder, false, 0.2)

	mapFolder:SetAttribute("Lighting_Technology", "Future")
	mapFolder:SetAttribute("Lighting_Ambient", "35,40,55")
	mapFolder:SetAttribute("Lighting_OutdoorAmbient", "12,14,22")
	mapFolder:SetAttribute("Lighting_Brightness", "1.4")
	mapFolder:SetAttribute("Lighting_ClockTime", "20")
	mapFolder:SetAttribute("Lighting_ShadowSoftness", "0.25")
	mapFolder:SetAttribute("Atmosphere_Density", "0.4")
	mapFolder:SetAttribute("Atmosphere_Offset", "0.1")
	mapFolder:SetAttribute("Atmosphere_Color", "80,100,140")
	mapFolder:SetAttribute("Atmosphere_Decay", "60,80,110")
	mapFolder:SetAttribute("Atmosphere_Glare", "0.2")
	mapFolder:SetAttribute("Atmosphere_Haze", "1.8")
	mapFolder:SetAttribute("ColorCorrection_Brightness", "-0.08")
	mapFolder:SetAttribute("ColorCorrection_Contrast", "0.2")
	mapFolder:SetAttribute("ColorCorrection_Saturation", "0.05")
	mapFolder:SetAttribute("ColorCorrection_TintColor", "200,220,255")
	mapFolder:SetAttribute("Bloom_Intensity", "0.9")
	mapFolder:SetAttribute("Bloom_Size", "28")
	mapFolder:SetAttribute("Bloom_Threshold", "0.85")
	mapFolder:SetAttribute("SunRays_Intensity", "0.05")
	mapFolder:SetAttribute("SunRays_Spread", "0.8")

	------------------------------------------------------------------------
	-- 9. Kill / Out-of-bounds volumes
	------------------------------------------------------------------------
	local volumes = Instance.new("Folder")
	volumes.Name = "Volumes"
	volumes.Parent = mapFolder

	-- Mid fight volume (for analytics / music intensity hooks)
	local midVol = createPart("MidFightVolume", Vector3.new(50, 16, 50),
		CFrame.new(0, 8, 0), Color3.new(), Enum.Material.SmoothPlastic, volumes, false, 1)
	midVol.CanCollide = false
	midVol.CanTouch = true
	midVol:SetAttribute("VolumeType", "MidFight")

	------------------------------------------------------------------------
	-- 10. FX
	------------------------------------------------------------------------
	local fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = mapFolder

	local dust = createPart("AmbientDust", Vector3.new(1, 1, 1),
		CFrame.new(0, 8, 0), Color3.new(), Enum.Material.SmoothPlastic, fx, false, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(C.NEON_CYAN)
	pe.Size = NumberSequence.new(0.15, 0)
	pe.Transparency = NumberSequence.new(0.55, 1)
	pe.Lifetime = NumberRange.new(3, 6)
	pe.Rate = 6
	pe.Speed = NumberRange.new(0.8, 1.8)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Parent = dust

	------------------------------------------------------------------------
	-- Finalize
	------------------------------------------------------------------------
	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder
	return mapFolder
end

-- API ------------------------------------------------------------------------

function DuelArenaMap.DestroyMap()
	cleanup()
end

function DuelArenaMap.GetSpawnPoints(teamName: string): { Vector3 }
	local baseSpawns: { Vector3 } = {}
	if teamName == "Team1" or teamName == "Red" then
		baseSpawns = TEAM1_SPAWN_POSITIONS
	elseif teamName == "Team2" or teamName == "Blue" then
		baseSpawns = TEAM2_SPAWN_POSITIONS
	end
	local results: { Vector3 } = {}
	for _, pos in baseSpawns do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function DuelArenaMap.GetSpawnLocations(teamName: string?): { SpawnLocation }
	local result: { SpawnLocation } = {}
	if not _activeMapFolder then
		return result
	end
	local spawns = _activeMapFolder:FindFirstChild("Spawns")
	if not spawns then
		return result
	end
	for _, desc in spawns:GetDescendants() do
		if desc:IsA("SpawnLocation") then
			if not teamName then
				table.insert(result, desc)
			else
				local t = desc:GetAttribute("Team")
				local legacy = desc:GetAttribute("LegacyTeam")
				if t == teamName or legacy == teamName then
					table.insert(result, desc)
				end
			end
		end
	end
	return result
end

function DuelArenaMap.GetCoverPositions(): { Vector3 }
	local results: { Vector3 } = {}
	for _, pos in COVER_POSITIONS do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function DuelArenaMap.GetSitePositions(): SitePositions
	return {
		siteA = SITE_POSITIONS.siteA + MAP_OFFSET,
		siteB = SITE_POSITIONS.siteB + MAP_OFFSET,
	}
end

function DuelArenaMap.GetMapBounds(): (Vector3, Vector3)
	local minBounds = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2) + MAP_OFFSET
	local maxBounds = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2) + MAP_OFFSET
	return minBounds, maxBounds
end

function DuelArenaMap.GetLanes(): { [string]: { center: Vector3, size: Vector3 } }
	local out: { [string]: { center: Vector3, size: Vector3 } } = {}
	for name, data in LANES_DATA do
		out[name] = {
			center = data.center + MAP_OFFSET,
			size = data.size,
		}
	end
	return out
end

function DuelArenaMap.GetLayoutData(): MapLayoutData
	local minB, maxB = DuelArenaMap.GetMapBounds()
	return {
		mapId = "DuelArena",
		mapName = "DuelArena_1v1_2v2_v2",
		theme = "Dark Tactical Competitive",
		bounds = {
			min = minB,
			max = maxB,
		},
		redSpawns = DuelArenaMap.GetSpawnPoints("Red"),
		blueSpawns = DuelArenaMap.GetSpawnPoints("Blue"),
		sites = DuelArenaMap.GetSitePositions(),
		coverPositions = DuelArenaMap.GetCoverPositions(),
		lanes = DuelArenaMap.GetLanes(),
	}
end

return DuelArenaMap
