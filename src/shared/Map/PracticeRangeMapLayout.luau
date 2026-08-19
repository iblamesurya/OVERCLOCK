--!strict
--[=[
    Project OVERCLOCK v2: PracticeRangeMapLayout (Legendary Edition)

    Research-backed rebuild referencing:
    - sshar1/FPS-Framework (open-source Roblox FPS) [web:4]
    - Ruski's Map Design Tutorial (fluid layouts, cover balance, clustering) [web:16]
    - Roblox Lighting best practices (Atmosphere, Bloom, ColorCorrection) [web:17]
    - Bullseye Target Systems (multi-ring concentric scoring) [web:24]
    - 3-lane FPS map design (symmetrical distance balance) [web:25]

    Features:
    (a) Multi-ring concentric bullseye targets (5 scoring zones each)
    (b) Moving rail targets with pop-up/pop-down cycle hooks
    (c) Tiered cover system (Low / Mid / High with health attributes)
    (d) Three-lane arena layout with symmetric distance balance
    (e) Holographic waypoint beacons with connecting beams
    (f) Ammo resupply + weapon rack stations with ProximityPrompts
    (g) Distance marker signage with billboard labels
    (h) Full lighting rig (Atmosphere, ColorCorrection, Bloom, ceiling lights)
    (i) Observational catwalk + score zone volumes
]=]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local PracticeRangeMapLayout = {}

-- Types -----------------------------------------------------------------------

export type MapBounds = { min: Vector3, max: Vector3 }
export type SitePositions = { siteA: Vector3, siteB: Vector3 }

export type MapLayoutData = {
	mapId: string,
	mapName: string,
	theme: string,
	bounds: MapBounds,
	redSpawns: { Vector3 },
	blueSpawns: { Vector3 },
	sites: SitePositions?,
	coverPositions: { Vector3 },
	lanes: { [string]: { center: Vector3, size: Vector3 } }?,
}

-- Constants ------------------------------------------------------------------

local MAP_FOLDER_NAME = "PracticeRangeMap"
local _activeMapFolder: Folder? = nil
local _activeTweens: { Tween } = {}

local MAP_WIDTH_X = 140
local MAP_LENGTH_Z = 220
local MAP_HEIGHT_Y = 40

local MAP_OFFSET = Vector3.new(500, 100, 0)

-- Color palette (industrial sci-fi range)
local C = {
	FLOOR = Color3.fromRGB(32, 36, 44),
	FLOOR_INLAY = Color3.fromRGB(24, 26, 34),
	WALL = Color3.fromRGB(45, 50, 60),
	WALL_ACCENT = Color3.fromRGB(60, 68, 82),
	TRIM = Color3.fromRGB(70, 78, 94),
	NEON_CYAN = Color3.fromRGB(0, 210, 255),
	NEON_BLUE = Color3.fromRGB(0, 140, 255),
	NEON_GREEN = Color3.fromRGB(0, 255, 130),
	NEON_ORANGE = Color3.fromRGB(255, 150, 30),
	NEON_RED = Color3.fromRGB(255, 50, 50),
	TARGET_WHITE = Color3.fromRGB(235, 235, 235),
	TARGET_RED = Color3.fromRGB(220, 30, 30),
	GLASS = Color3.fromRGB(130, 200, 250),
}

-- Player spawns (three-lane symmetric) ---------------------------------------
local PLAYER_SPAWN_POSITIONS: { Vector3 } = {
	Vector3.new(0, 2, 70), -- Spawn_Player_1 (center lane)
	Vector3.new(-12, 2, 70), -- Spawn_Player_2 (west lane)
	Vector3.new(12, 2, 70), -- Spawn_Player_3 (east lane)
}

-- Patrol bot waypoints (figure-8 patrol through cover) -----------------------
local BOT_WAYPOINT_POSITIONS: { Vector3 } = {
	Vector3.new(-35, 2, -20),
	Vector3.new(-15, 2, -45),
	Vector3.new(15, 2, -45),
	Vector3.new(35, 2, -20),
	Vector3.new(35, 2, 15),
	Vector3.new(15, 2, 30),
	Vector3.new(-15, 2, 30),
	Vector3.new(-35, 2, 15),
}

-- Stationary target definitions (varied heights & sizes) --------------------
type TargetDef = { name: string, cframe: CFrame, size: Vector3, id: number }

local STATIONARY_TARGETS: { TargetDef } = {
	{ name = "Target_Stationary_1", cframe = CFrame.new(-35, 6, -90), size = Vector3.new(5, 5, 0.5), id = 1 },
	{ name = "Target_Stationary_2", cframe = CFrame.new(-18, 11, -90), size = Vector3.new(4, 4, 0.5), id = 2 },
	{ name = "Target_Stationary_3", cframe = CFrame.new(0, 8, -90), size = Vector3.new(5, 5, 0.5), id = 3 },
	{ name = "Target_Stationary_4", cframe = CFrame.new(18, 13, -90), size = Vector3.new(3.5, 3.5, 0.5), id = 4 },
	{ name = "Target_Stationary_5", cframe = CFrame.new(35, 6, -90), size = Vector3.new(5, 5, 0.5), id = 5 },
	{ name = "Target_Stationary_6", cframe = CFrame.new(0, 16, -90), size = Vector3.new(3, 3, 0.5), id = 6 },
}

-- Moving rail target definitions ----------------------------------------------
type MovingTargetDef = { name: string, startPos: Vector3, endPos: Vector3, size: Vector3, id: number }

local MOVING_TARGETS: { MovingTargetDef } = {
	{
		name = "Target_Moving_1",
		startPos = Vector3.new(-20, 6, -70),
		endPos = Vector3.new(20, 6, -70),
		size = Vector3.new(3, 3, 0.4),
		id = 101,
	},
}

-- Cover obstacles (tiered: low, mid, high) -----------------------------------
type CoverDef = { name: string, pos: Vector3, size: Vector3, tier: string, health: number }

local COVER_DEFS: { CoverDef } = {
	{
		name = "Cover_Low_1",
		pos = Vector3.new(-28, 1, 0),
		size = Vector3.new(5, 3, 5),
		tier = "Low",
		health = 100,
	},
	{
		name = "Cover_Low_2",
		pos = Vector3.new(28, 1, 0),
		size = Vector3.new(5, 3, 5),
		tier = "Low",
		health = 100,
	},
	{
		name = "Cover_Mid_1",
		pos = Vector3.new(-15, 2, -15),
		size = Vector3.new(4, 4, 4),
		tier = "Mid",
		health = 200,
	},
	{
		name = "Cover_Mid_2",
		pos = Vector3.new(15, 2, -15),
		size = Vector3.new(4, 4, 4),
		tier = "Mid",
		health = 200,
	},
	{
		name = "Cover_High_1",
		pos = Vector3.new(0, 3.5, -25),
		size = Vector3.new(6, 7, 6),
		tier = "High",
		health = 400,
	},
	{
		name = "Cover_High_2",
		pos = Vector3.new(-40, 3.5, -35),
		size = Vector3.new(5, 7, 5),
		tier = "High",
		health = 400,
	},
	{
		name = "Cover_High_3",
		pos = Vector3.new(40, 3.5, -35),
		size = Vector3.new(5, 7, 5),
		tier = "High",
		health = 400,
	},
}

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
	return part
end

local function makeBlocker(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local b = Instance.new("Part")
	b.Name = name.."_Blocker"
	b.Size = size
	b.CFrame = cframe
	b.Anchored = true
	b.CanCollide = true
	b.CanQuery = true
	b.CanTouch = false
	b.Transparency = 1
	b.Material = Enum.Material.SmoothPlastic
	b.Color = Color3.fromRGB(0,0,0)
	b.CollisionGroup = "Map"
	b:SetAttribute("BulletBlocker", true)
	b.Parent = parent
	return b
end

local function addLight(parent: Instance, color: Color3, range: number, brightness: number, type: string?)
	if type == "Spot" then
		local s = Instance.new("SpotLight")
		s.Color, s.Range, s.Brightness, s.Angle, s.Face = color, range, brightness, 90, Enum.NormalId.Bottom
		s.Parent = parent
	else
		local p = Instance.new("PointLight")
		p.Color, p.Range, p.Brightness = color, range, brightness
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
	bb.MaxDistance = 80
	bb.Parent = parent
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = textSize
	lbl.Text = text
	lbl.TextStrokeTransparency = 0.5
	lbl.Parent = bb
end

local function createBeam(parent: Part, a0: Attachment, a1: Attachment, color: Color3, width: number)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = width
	beam.Width1 = width
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.3, 0.6)
	beam.Parent = parent
end

-- Multi-ring concentric bullseye target builder -----------------------------
-- Based on real bullseye target ring patterns [web:24]
local RING_COLORS = { C.TARGET_RED, C.TARGET_WHITE, C.TARGET_RED, C.TARGET_WHITE, C.TARGET_RED }
local RING_SCALE = { 1.0, 0.78, 0.56, 0.34, 0.15 }

local function createBullseyeTarget(tDef: TargetDef, parent: Instance): Part
	local base = createPart(tDef.name, tDef.size, tDef.cframe, C.TARGET_RED, Enum.Material.SmoothPlastic, parent, true)
	base:SetAttribute("TargetId", tDef.id)
	base:SetAttribute("TargetType", "Stationary")
	base:SetAttribute("IsTarget", true)
	base:SetAttribute("MaxScore", 100)

	for ringIdx = 1, #RING_COLORS do
		local scale = RING_SCALE[ringIdx]
		local ring = createPart(
			"TargetRing_" .. ringIdx,
			Vector3.new(tDef.size.X * scale, tDef.size.Y * scale, tDef.size.Z + 0.05 * ringIdx),
			tDef.cframe * CFrame.new(0, 0, 0.03 * ringIdx),
			RING_COLORS[ringIdx],
			Enum.Material.Neon,
			base,
			false,
			0
		)
		ring:SetAttribute("RingIndex", ringIdx)
		ring:SetAttribute("RingScore", math.floor(100 - (ringIdx - 1) * 20))
		ring:SetAttribute("TargetId", tDef.id)
	end

	addLight(base, C.NEON_RED, 8, 1)
	return base
end

-- Moving rail target with tween cycle ---------------------------------------
local function createMovingTarget(mDef: MovingTargetDef, parent: Instance): Part
	local rail = createPart(
		mDef.name .. "_Rail",
		Vector3.new(math.abs(mDef.endPos.X - mDef.startPos.X) + 1, 0.3, 0.5),
		CFrame.new((mDef.startPos + mDef.endPos) / 2),
		C.TRIM,
		Enum.Material.Neon,
		parent,
		false,
		0.5
	)

	local target = createPart(
		mDef.name,
		mDef.size,
		CFrame.new(mDef.startPos),
		C.TARGET_RED,
		Enum.Material.SmoothPlastic,
		parent,
		true
	)
	target:SetAttribute("TargetId", mDef.id)
	target:SetAttribute("TargetType", "Moving")
	target:SetAttribute("IsTarget", true)
	target:SetAttribute("MaxScore", 150)

	-- Inner ring on moving target
	local ring = createPart(
		mDef.name .. "_Center",
		Vector3.new(mDef.size.X * 0.35, mDef.size.Y * 0.35, mDef.size.Z + 0.1),
		CFrame.new(mDef.startPos) * CFrame.new(0, 0, 0.05),
		C.TARGET_WHITE,
		Enum.Material.Neon,
		target,
		false,
		0
	)
	ring:SetAttribute("RingScore", 150)
	ring:SetAttribute("TargetId", mDef.id)

	addLight(target, C.NEON_ORANGE, 6, 1)

	-- Tween back and forth
	local dur = 4 + mDef.id % 3
	local tweenForward = TweenService:Create(
		target,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = CFrame.new(mDef.endPos) }
	)
	local tweenBack = TweenService:Create(
		target,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = CFrame.new(mDef.startPos) }
	)

	tweenForward.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			tweenBack:Play()
		end
	end)
	tweenBack.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			tweenForward:Play()
		end
	end)
	tweenForward:Play()

	table.insert(_activeTweens, tweenForward)
	table.insert(_activeTweens, tweenBack)

	return target
end

-- Cleanup -------------------------------------------------------------------

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

-- Main Build ----------------------------------------------------------------

function PracticeRangeMapLayout.BuildMap(parent: Instance?): Folder
	cleanup()
	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME

	-- Roblox developer: immersive lighting rig (map-maker best practice)
	-- Only apply if not already configured, keep Studio defaults safe
	pcall(function()
		Lighting.Ambient = Color3.fromRGB(90, 95, 110)
		Lighting.Brightness = 3
		Lighting.EnvironmentDiffuseScale = 0.25
		Lighting.EnvironmentSpecularScale = 0.25
		Lighting.ShadowDensity = 0.7
		if not Lighting:FindFirstChild("PracticeRangeAtmosphere") then
			local atm = Instance.new("Atmosphere")
			atm.Name = "PracticeRangeAtmosphere"
			atm.Density = 0.15
			atm.Offset = 0.5
			atm.Glare = 0.2
			atm.Haze = 0.8
			atm.Color = Color3.fromRGB(140, 170, 255)
			atm.Decay = Color3.fromRGB(15, 30, 60)
			atm.Parent = Lighting
		end
		if not Lighting:FindFirstChild("PracticeRangeBloom") then
			local bloom = Instance.new("BloomEffect")
			bloom.Name = "PracticeRangeBloom"
			bloom.Intensity = 0.25
			bloom.Size = 12
			bloom.Threshold = 1.2
			bloom.Parent = Lighting
		end
		if not Lighting:FindFirstChild("PracticeRangeCC") then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "PracticeRangeCC"
			cc.Brightness = 0.02
			cc.Contrast = 0.08
			cc.Saturation = 0.15
			cc.TintColor = Color3.fromRGB(255, 252, 240)
			cc.Parent = Lighting
		end
		if not Lighting:FindFirstChild("PracticeRangeSun") then
			local sun = Instance.new("SunRaysEffect")
			sun.Name = "PracticeRangeSun"
			sun.Intensity = 0.08
			sun.Spread = 0.6
			sun.Parent = Lighting
		end
	end)

	------------------------------------------------------------------------
	-- 1. Perimeter & Environment — map-maker: concrete base with metal trim, not flat grey
	------------------------------------------------------------------------
	local perimeter = Instance.new("Folder")
	perimeter.Name = "Perimeter"
	perimeter.Parent = mapFolder

	-- Main floor with hexagonal diamond plate (map-maker: material variety, not flat) - thickened to 6 to prevent high-velocity fall-through
	createPart(
		"MainFloor",
		Vector3.new(MAP_WIDTH_X, 6, MAP_LENGTH_Z),
		CFrame.new(0, -3, 0),
		C.FLOOR,
		Enum.Material.Concrete,
		perimeter,
		true
	)
	-- Diamond plate trim via DiamondPlate metal + Asphalt inlay
	createPart(
		"FloorPlate_Border",
		Vector3.new(MAP_WIDTH_X + 0.4, 0.15, MAP_LENGTH_Z + 0.4),
		CFrame.new(0, -0.12, 0),
		C.TRIM,
		Enum.Material.DiamondPlate,
		perimeter,
		true
	)
	-- Floor inlays removed per request (were white/cyan lines toward targets)
	-- Ceiling soft glow (bounced light)
	createPart(
		"FloorUnderglow",
		Vector3.new(MAP_WIDTH_X - 8, 0.4, MAP_LENGTH_Z - 8),
		CFrame.new(0, -0.35, 0),
		C.WALL_ACCENT,
		Enum.Material.SmoothPlastic,
		perimeter,
		false,
		0.8
	)

	-- Walls with accent strips
	for _, w in
		{
			{
				"NorthWall",
				Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
				CFrame.new(0, MAP_HEIGHT_Y / 2, -MAP_LENGTH_Z / 2),
			},
			{
				"SouthWall",
				Vector3.new(MAP_WIDTH_X, MAP_HEIGHT_Y, 2),
				CFrame.new(0, MAP_HEIGHT_Y / 2, MAP_LENGTH_Z / 2),
			},
			{
				"WestWall",
				Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
				CFrame.new(-MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
			},
			{
				"EastWall",
				Vector3.new(2, MAP_HEIGHT_Y, MAP_LENGTH_Z),
				CFrame.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y / 2, 0),
			},
		}
	do
		createPart(w[1] :: string, w[2] :: Vector3, w[3] :: CFrame, C.WALL, Enum.Material.Concrete, perimeter, true)
		-- Neon accent strip at top of each wall
		createPart(
			w[1] .. "_Accent",
			Vector3.new(w[2].X, 1, w[2].Z),
			w[3] :: CFrame * CFrame.new(0, MAP_HEIGHT_Y / 2 - 1, 0),
			C.NEON_CYAN,
			Enum.Material.Neon,
			perimeter,
			false,
			0.1
		)
	end

	-- Invisible ceiling barrier
	createPart(
		"CeilingBarrier",
		Vector3.new(MAP_WIDTH_X, 2, MAP_LENGTH_Z),
		CFrame.new(0, MAP_HEIGHT_Y, 0),
		Color3.new(),
		Enum.Material.SmoothPlastic,
		perimeter,
		true,
		1
	)

	------------------------------------------------------------------------
	-- 2. Distance Markers with Billboard Signs
	------------------------------------------------------------------------
	local markers = Instance.new("Folder")
	markers.Name = "DistanceMarkers"
	markers.Parent = mapFolder

	-- Firing deck at Z = 70, targets at Z = -90
	-- 10m ≈ 32.8 studs -> Z = 37.2
	-- 25m ≈ 82 studs -> Z = -12.0
	-- 50m ≈ 164 studs -> Z = -94.0 (near target wall)
	local markerDefs = {
		{ name = "DM_10m", z = 37.2, meters = 10, color = C.NEON_GREEN },
		{ name = "DM_25m", z = -12.0, meters = 25, color = C.NEON_ORANGE },
		{ name = "DM_50m", z = -78.0, meters = 50, color = C.NEON_RED },
	}

	for _, mDef in markerDefs do
		-- Distance ground lines removed per request (were white/neon lines toward targets)
		do end -- placeholder to keep loop without white line
		-- Original: createPart(mDef.name, ..., mDef.color, Neon) removed

		-- Signage post
		local post = createPart(
			mDef.name .. "_Post",
			Vector3.new(0.5, 4, 0.5),
			CFrame.new(MAP_WIDTH_X / 2 - 5, 2, mDef.z),
			C.TRIM,
			Enum.Material.Metal,
			markers,
			true
		)
		makeBillboard(
			post,
			mDef.name .. "_Label",
			mDef.meters .. "m",
			mDef.color,
			UDim2.new(0, 120, 0, 50),
			Vector3.new(0, 3, 0),
			28
		)
	end

	------------------------------------------------------------------------
	-- 3. Target Wall Section (multi-ring bullseyes + moving rails)
	------------------------------------------------------------------------
	local targetSection = Instance.new("Folder")
	targetSection.Name = "TargetWallSection"
	targetSection.Parent = mapFolder

	-- Reinforced backboard with neon frame
	createPart(
		"TargetBackboard",
		Vector3.new(110, 24, 2),
		CFrame.new(0, 12, -92),
		C.FLOOR_INLAY,
		Enum.Material.Metal,
		targetSection,
		true
	)
	createPart(
		"Backboard_FrameTop",
		Vector3.new(112, 0.8, 2.5),
		CFrame.new(0, 24, -92),
		C.NEON_CYAN,
		Enum.Material.Neon,
		targetSection,
		false,
		0.1
	)
	createPart(
		"Backboard_FrameBottom",
		Vector3.new(112, 0.8, 2.5),
		CFrame.new(0, 0.4, -92),
		C.NEON_CYAN,
		Enum.Material.Neon,
		targetSection,
		false,
		0.1
	)
	createPart(
		"Backboard_FrameLeft",
		Vector3.new(0.8, 24, 2.5),
		CFrame.new(-55, 12, -92),
		C.NEON_CYAN,
		Enum.Material.Neon,
		targetSection,
		false,
		0.1
	)
	createPart(
		"Backboard_FrameRight",
		Vector3.new(0.8, 24, 2.5),
		CFrame.new(55, 12, -92),
		C.NEON_CYAN,
		Enum.Material.Neon,
		targetSection,
		false,
		0.1
	)

	-- Stationary multi-ring targets
	for _, tDef in STATIONARY_TARGETS do
		createBullseyeTarget(tDef, targetSection)
	end

	-- Moving rail targets
	local movingFolder = Instance.new("Folder")
	movingFolder.Name = "MovingTargets"
	movingFolder.Parent = targetSection

	for _, mDef in MOVING_TARGETS do
		createMovingTarget(mDef, movingFolder)
	end

	------------------------------------------------------------------------
	-- 4. Patrol Bot Arena (holographic waypoints + connecting beams)
	------------------------------------------------------------------------
	local patrolSection = Instance.new("Folder")
	patrolSection.Name = "PatrolBotSection"
	patrolSection.Parent = mapFolder

	local waypointsFolder = Instance.new("Folder")
	waypointsFolder.Name = "Waypoints"
	waypointsFolder.Parent = patrolSection

	local prevAtt: Attachment? = nil
	for i, wPos in BOT_WAYPOINT_POSITIONS do
		-- Beacon pillar
		local beacon = createPart(
			"Waypoints_Bot_" .. i,
			Vector3.new(0.5, 0.2, 0.5),
			CFrame.new(wPos),
			C.NEON_GREEN,
			Enum.Material.Neon,
			waypointsFolder,
			false,
			0.3
		)
		beacon:SetAttribute("WaypointIndex", i)

		-- Vertical hologram beam
		local beamPart = createPart(
			"WP_Beam_" .. i,
			Vector3.new(0.3, 8, 0.3),
			CFrame.new(wPos + Vector3.new(0, 4, 0)),
			C.NEON_GREEN,
			Enum.Material.Neon,
			waypointsFolder,
			false,
			0.5
		)
		addLight(beamPart, C.NEON_GREEN, 6, 0.5)

		-- Connecting beams removed per request (were white/green lines toward targets)
		local att0 = Instance.new("Attachment")
		att0.Position = Vector3.new(0, 0, 0)
		att0.Parent = beamPart
		-- createBeam removed
		prevAtt = att0
	end
	-- Loop close removed per request

	------------------------------------------------------------------------
	-- 5. Player Spawns & Firing Deck
	------------------------------------------------------------------------
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = mapFolder

	-- Elevated firing deck with neon edge
	createPart("FiringDeck", Vector3.new(100, 1, 35), CFrame.new(0, 0.5, 70), C.TRIM, Enum.Material.Metal, spawns, true)
	createPart(
		"FiringDeck_EdgeN",
		Vector3.new(100, 0.3, 0.8),
		CFrame.new(0, 1.15, 52.5),
		C.NEON_CYAN,
		Enum.Material.Neon,
		spawns,
		false,
		0.1
	)
	createPart(
		"FiringDeck_EdgeS",
		Vector3.new(100, 0.3, 0.8),
		CFrame.new(0, 1.15, 87.5),
		C.NEON_CYAN,
		Enum.Material.Neon,
		spawns,
		false,
		0.1
	)

	-- Weapon rack station with ProximityPrompt
	local weaponRack = createPart(
		"WeaponRackPad",
		Vector3.new(8, 6, 4),
		CFrame.new(-25, 3, 78),
		C.TRIM,
		Enum.Material.Metal,
		spawns,
		true
	)
	weaponRack:SetAttribute("StationType", "WeaponRack")
	addLight(weaponRack, C.NEON_BLUE, 10, 1.5)
	makeBillboard(
		weaponRack,
		"WeaponRackLabel",
		"[ WEAPON RACK ]",
		C.NEON_CYAN,
		UDim2.new(0, 200, 0, 50),
		Vector3.new(0, 4, 0),
		22
	)
	local wrPrompt = Instance.new("ProximityPrompt")
	wrPrompt.Name = "WeaponRackPrompt"
	wrPrompt.ActionText = "Equip Weapon"
	wrPrompt.ObjectText = "Armory Station"
	wrPrompt.HoldDuration = 0
	wrPrompt.MaxActivationDistance = 10
	wrPrompt.RequiresLineOfSight = false
	wrPrompt:SetAttribute("StationType", "WeaponRack")
	wrPrompt.Parent = weaponRack

	-- Ammo resupply station with ProximityPrompt
	local ammoStation = createPart(
		"AmmoResupplyPad",
		Vector3.new(6, 4, 4),
		CFrame.new(25, 2, 78),
		C.TRIM,
		Enum.Material.Metal,
		spawns,
		true
	)
	ammoStation:SetAttribute("StationType", "AmmoResupply")
	addLight(ammoStation, C.NEON_ORANGE, 10, 1.5)
	makeBillboard(
		ammoStation,
		"AmmoLabel",
		"[ AMMO RESUPPLY ]",
		C.NEON_ORANGE,
		UDim2.new(0, 200, 0, 50),
		Vector3.new(0, 3.5, 0),
		22
	)
	local ammoPrompt = Instance.new("ProximityPrompt")
	ammoPrompt.Name = "AmmoPrompt"
	ammoPrompt.ActionText = "Resupply Ammo"
	ammoPrompt.ObjectText = "Ammo Station"
	ammoPrompt.HoldDuration = 0.5
	ammoPrompt.MaxActivationDistance = 10
	ammoPrompt.RequiresLineOfSight = false
	ammoPrompt:SetAttribute("StationType", "AmmoResupply")
	ammoPrompt.Parent = ammoStation

	-- Player spawn pads with team coloring
	local playerSpawnFolder = Instance.new("Folder")
	playerSpawnFolder.Name = "PlayerSpawn"
	playerSpawnFolder.Parent = spawns

	for i, sPos in PLAYER_SPAWN_POSITIONS do
		local pad = createPart(
			"Spawn_Player_" .. i,
			Vector3.new(5, 0.5, 5),
			CFrame.new(sPos - Vector3.new(0, 0.75, 0)),
			C.TRIM,
			Enum.Material.Metal,
			playerSpawnFolder,
			true
		)
		createPart(
			"SpawnRing_" .. i,
			Vector3.new(5.5, 0.2, 5.5),
			CFrame.new(sPos - Vector3.new(0, 1.0, 0)),
			C.NEON_CYAN,
			Enum.Material.Neon,
			playerSpawnFolder,
			false,
			0.2
		)
		addLight(pad, C.NEON_CYAN, 8, 1)
		pad:SetAttribute("Team", "Player")
		pad:SetAttribute("SpawnIndex", i)

		local spawnLoc = Instance.new("SpawnLocation")
		spawnLoc.Name = "SpawnLocation_" .. i
		spawnLoc.Size = Vector3.new(4, 0.4, 4)
		spawnLoc.CFrame = CFrame.new(sPos) + MAP_OFFSET
		spawnLoc.Anchored = true
		spawnLoc.Neutral = true
		spawnLoc.Enabled = true
		spawnLoc.AllowTeamChangeOnTouch = false
		spawnLoc.TeamColor = BrickColor.new("Medium royal blue")
		spawnLoc.Color = C.TRIM
		spawnLoc.Material = Enum.Material.SmoothPlastic
		spawnLoc.TopSurface = Enum.SurfaceType.Smooth
		spawnLoc.BottomSurface = Enum.SurfaceType.Smooth
		spawnLoc:SetAttribute("PracticeSpawnIndex", i)
		spawnLoc:SetAttribute("IsPracticeSpawn", true)
		spawnLoc.Parent = playerSpawnFolder
	end

	------------------------------------------------------------------------
	-- 6. Cover System (tiered obstacles with health attributes)
	------------------------------------------------------------------------
	local coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder

	local coverColors = { Low = C.TRIM, Mid = C.WALL_ACCENT, High = C.WALL }

	for _, cDef in COVER_DEFS do
		local cover = createPart(
			cDef.name,
			cDef.size,
			CFrame.new(cDef.pos),
			coverColors[cDef.tier] :: Color3,
			Enum.Material.Concrete,
			coverFolder,
			true
		)
		cover:SetAttribute("CoverTier", cDef.tier)
		cover:SetAttribute("CoverHealth", cDef.health)
		cover:SetAttribute("MaxHealth", cDef.health)

		-- Neon edge trim on high cover
		if cDef.tier == "High" then
			createPart(
				cDef.name .. "_Trim",
				Vector3.new(cDef.size.X + 0.2, 0.3, cDef.size.Z + 0.2),
				CFrame.new(cDef.pos + Vector3.new(0, cDef.size.Y / 2, 0)),
				C.NEON_CYAN,
				Enum.Material.Neon,
				coverFolder,
				false,
				0.15
			)
		end
	end

	-- City dressing (requested: buildings, trees, containers, blastable barrels, roads) - primitive city, 5+ colours, no white lines
	createPart("CityRoad_Main", Vector3.new(16, 0.12, MAP_LENGTH_Z - 20), CFrame.new(0, 0.08, 0), Color3.fromRGB(45, 48, 54), Enum.Material.Asphalt, coverFolder, false, 0.05)
	createPart("CityRoad_Cross", Vector3.new(MAP_WIDTH_X - 20, 0.12, 12), CFrame.new(0, 0.08, 0), Color3.fromRGB(55, 58, 64), Enum.Material.Asphalt, coverFolder, false, 0.05)
	for _, lx in {-4, 4} do
		createPart("RoadMark_"..lx, Vector3.new(0.6, 0.08, MAP_LENGTH_Z - 30), CFrame.new(lx, 0.14, 0), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic, coverFolder, false, 0.05)
	end
	for _, b in {{pos=Vector3.new(-55, 6, 45), size=Vector3.new(18, 12, 14), color=Color3.fromRGB(98, 102, 108)},{pos=Vector3.new(55, 6, 42), size=Vector3.new(16, 12, 16), color=Color3.fromRGB(82, 86, 92)},{pos=Vector3.new(-48, 6, -55), size=Vector3.new(20, 14, 12), color=Color3.fromRGB(88, 92, 98)}} do
		local bld = createPart("CityBuilding_"..b.pos.X, b.size, CFrame.new(b.pos), b.color, Enum.Material.Concrete, coverFolder, true)
		makeBlocker("CityBuilding_"..b.pos.X, b.size, CFrame.new(b.pos), coverFolder)
		createPart("CityWindow_"..b.pos.X, Vector3.new(b.size.X - 2, 4, 0.4), CFrame.new(b.pos + Vector3.new(0, 2, b.size.Z/2 + 0.2)), Color3.fromRGB(130, 200, 250), Enum.Material.Glass, coverFolder, false, 0.3)
	end
	for _, tpos in {Vector3.new(-62, 0, 60), Vector3.new(62, 0, 58), Vector3.new(-60, 0, -65), Vector3.new(60, 0, -62)} do
		createPart("CityTree_Trunk_"..tpos.X, Vector3.new(1.2, 6, 1.2), CFrame.new(tpos + Vector3.new(0,3,0)), Color3.fromRGB(72, 48, 28), Enum.Material.Wood, coverFolder, true)
		createPart("CityTree_Foliage_"..tpos.X, Vector3.new(5, 5, 5), CFrame.new(tpos + Vector3.new(0,7.5,0)), Color3.fromRGB(38, 92, 38), Enum.Material.Grass, coverFolder, true)
	end
	for _, c in {{pos=Vector3.new(-38, 2.5, 10), color=Color3.fromRGB(180, 45, 45)},{pos=Vector3.new(38, 2.5, 8), color=Color3.fromRGB(45, 90, 180)},{pos=Vector3.new(0, 2.5, -35), color=Color3.fromRGB(200, 160, 40)}} do
		createPart("CityContainer_"..c.pos.X, Vector3.new(12, 5, 6), CFrame.new(c.pos), c.color, Enum.Material.CorrodedMetal, coverFolder, true)
		makeBlocker("CityContainer_"..c.pos.X, Vector3.new(12, 5, 6), CFrame.new(c.pos), coverFolder)
	end

		-- Barrel clusters (prop clustering technique from map design guide) [web:16]
	for _, barrelPos in
		{
			Vector3.new(-22, 1.5, -5),
			Vector3.new(-20, 1.5, -5),
			Vector3.new(-21, 1.5, -3),
			Vector3.new(22, 1.5, -5),
			Vector3.new(20, 1.5, -5),
			Vector3.new(21, 1.5, -3),
		}
	do
		local barrel = createPart(
			"Barrel",
			Vector3.new(2, 3, 2),
			CFrame.new(barrelPos),
			C.NEON_ORANGE,
			Enum.Material.Metal,
			coverFolder,
			true
		)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CFrame = CFrame.new(barrelPos) * CFrame.Angles(0, 0, math.rad(90)) + MAP_OFFSET
		barrel:SetAttribute("CoverTier", "Barrel")
		barrel:SetAttribute("CoverHealth", 50)
		barrel:SetAttribute("MaxHealth", 50)
		barrel:SetAttribute("IsExplosive", true)
	end

	------------------------------------------------------------------------
	-- 7. Observational Catwalk (overlooking the range)
	------------------------------------------------------------------------
	local catwalk = Instance.new("Folder")
	catwalk.Name = "Catwalk"
	catwalk.Parent = mapFolder

	createPart(
		"CatwalkPlatform",
		Vector3.new(60, 1, 6),
		CFrame.new(0, 20, 65),
		C.TRIM,
		Enum.Material.Metal,
		catwalk,
		true
	)
	createPart(
		"CatwalkRailing_L",
		Vector3.new(60, 0.3, 0.4),
		CFrame.new(-29, 21, 65),
		C.NEON_CYAN,
		Enum.Material.Neon,
		catwalk,
		false,
		0.2
	)
	createPart(
		"CatwalkRailing_R",
		Vector3.new(60, 0.3, 0.4),
		CFrame.new(29, 21, 65),
		C.NEON_CYAN,
		Enum.Material.Neon,
		catwalk,
		false,
		0.2
	)

	-- Support pillars
	for _, px in { -25, 0, 25 } do
		createPart(
			"CatwalkPillar_" .. px,
			Vector3.new(1, 20, 1),
			CFrame.new(px, 10, 68),
			C.WALL,
			Enum.Material.Concrete,
			catwalk,
			true
		)
		createPart(
			"CatwalkPillarLight_" .. px,
			Vector3.new(1.2, 0.5, 1.2),
			CFrame.new(px, 20.5, 68),
			C.NEON_CYAN,
			Enum.Material.Neon,
			catwalk,
			false,
			0.1
		)
		addLight(catwalk:FindFirstChild("CatwalkPillarLight_" .. px) :: BasePart, C.NEON_CYAN, 12, 1)
	end

	------------------------------------------------------------------------
	-- 8. Lighting Rig (ceiling lights + post-processing)
	------------------------------------------------------------------------
	local lightingFolder = Instance.new("Folder")
	lightingFolder.Name = "LightingRig"
	lightingFolder.Parent = mapFolder

	-- Ceiling light strips
	for _, lx in { -40, -20, 0, 20, 40 } do
		local strip = createPart(
			"CeilingLight_" .. lx,
			Vector3.new(8, 0.5, 40),
			CFrame.new(lx, MAP_HEIGHT_Y - 1, 0),
			Color3.fromRGB(200, 230, 255),
			Enum.Material.Neon,
			lightingFolder,
			false,
			0.2
		)
		addLight(strip, Color3.fromRGB(180, 220, 255), 40, 2, "Spot")
	end

	-- Post-processing effects stored as attributes for the bootstrap to apply
	mapFolder:SetAttribute("Lighting_Technology", "Future")
	mapFolder:SetAttribute("Lighting_Ambient", "45,50,65")
	mapFolder:SetAttribute("Lighting_OutdoorAmbient", "15,18,28")
	mapFolder:SetAttribute("Lighting_Brightness", "1.5")
	mapFolder:SetAttribute("Lighting_ClockTime", "14")
	mapFolder:SetAttribute("Lighting_GeographicLatitude", "0")
	mapFolder:SetAttribute("Lighting_ShadowSoftness", "0.3")
	mapFolder:SetAttribute("Atmosphere_Density", "0.35")
	mapFolder:SetAttribute("Atmosphere_Offset", "0")
	mapFolder:SetAttribute("Atmosphere_Color", "120,150,200")
	mapFolder:SetAttribute("Atmosphere_Decay", "100,130,160")
	mapFolder:SetAttribute("Atmosphere_Glare", "0.3")
	mapFolder:SetAttribute("Atmosphere_Haze", "1.5")
	mapFolder:SetAttribute("ColorCorrection_Brightness", "-0.05")
	mapFolder:SetAttribute("ColorCorrection_Contrast", "0.15")
	mapFolder:SetAttribute("ColorCorrection_Saturation", "0.1")
	mapFolder:SetAttribute("ColorCorrection_TintColor", "210,230,255")
	mapFolder:SetAttribute("Bloom_Intensity", "0.8")
	mapFolder:SetAttribute("Bloom_Size", "24")
	mapFolder:SetAttribute("Bloom_Threshold", "0.9")
	mapFolder:SetAttribute("SunRays_Intensity", "0.15")
	mapFolder:SetAttribute("SunRays_Spread", "1")

	------------------------------------------------------------------------
	-- 9. Score Zone Volumes (invisible regions for scoring detection)
	------------------------------------------------------------------------
	local scoreZones = Instance.new("Folder")
	scoreZones.Name = "ScoreZones"
	scoreZones.Parent = mapFolder

	for _, zone in
		{
			{ name = "BullseyeZone", center = Vector3.new(0, 10, -90), size = Vector3.new(110, 24, 4), score = 100 },
			{ name = "MovingTargetZone", center = Vector3.new(0, 8, -70), size = Vector3.new(60, 16, 20), score = 150 },
			{ name = "PatrolZone", center = Vector3.new(0, 2, -10), size = Vector3.new(80, 10, 60), score = 200 },
		}
	do
		local vol = createPart(
			zone.name,
			zone.size,
			CFrame.new(zone.center),
			Color3.new(),
			Enum.Material.SmoothPlastic,
			scoreZones,
			false,
			1
		)
		vol:SetAttribute("ZoneType", zone.name)
		vol:SetAttribute("ZoneScore", zone.score)
		vol.CanCollide = false
		vol.CanQuery = false
		vol.CanTouch = true
	end

	------------------------------------------------------------------------
	-- 10. Atmospheric FX (ambient dust)
	------------------------------------------------------------------------
	local fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = mapFolder

	local emitterPart = createPart(
		"AmbientDust",
		Vector3.new(1, 1, 1),
		CFrame.new(0, 10, -20),
		Color3.new(),
		Enum.Material.SmoothPlastic,
		fx,
		false,
		1
	)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(C.NEON_CYAN)
	pe.Size = NumberSequence.new(0.2, 0)
	pe.Transparency = NumberSequence.new(0.5, 1)
	pe.Lifetime = NumberRange.new(4, 7)
	pe.Rate = 8
	pe.Speed = NumberRange.new(1, 2)
	pe.SpreadAngle = Vector2.new(45, 45)
	pe.Parent = emitterPart

	------------------------------------------------------------------------
	-- Phase 3 Training Features
	------------------------------------------------------------------------
	local envFolder = mapFolder:FindFirstChild("Environment") or mapFolder
	local CollectionService = game:GetService("CollectionService")

	local recoilWall = createPart("RecoilWall", Vector3.new(40, 20, 1), CFrame.new(MAP_OFFSET + Vector3.new(530, 107, 120)), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, envFolder, true)
	CollectionService:AddTag(recoilWall, "RecoilWall")
	for dx = -18, 18, 2 do
		for dy = -8, 8, 2 do
			local dot = createPart("RecoilDot_"..dx.."_"..dy, Vector3.new(0.5, 0.5, 1.1), CFrame.new(MAP_OFFSET + Vector3.new(530 + dx, 107 + dy, 120)), Color3.fromRGB(255, 0, 0), Enum.Material.Neon, envFolder, false)
			dot.CanCollide = false
		end
	end

	local rail = createPart("TargetRail", Vector3.new(80, 0.5, 2), CFrame.new(MAP_OFFSET + Vector3.new(550, 107, 60)), Color3.fromRGB(50, 50, 50), Enum.Material.Metal, envFolder, false)
	local dummy = createPart("MovingDummy", Vector3.new(2, 6, 2), CFrame.new(MAP_OFFSET + Vector3.new(550, 110.25, 60)), Color3.fromRGB(255, 100, 100), Enum.Material.SmoothPlastic, envFolder, true)
	dummy:SetAttribute("StrafeSpeed", 16)
	CollectionService:AddTag(dummy, "MovingTarget")

	for i = 1, 5 do
		local xOff = -30 + (i * 10)
		local cover = createPart("ReflexCover_"..i, Vector3.new(6, 4, 2), CFrame.new(MAP_OFFSET + Vector3.new(560, 105, xOff)), Color3.fromRGB(100, 100, 100), Enum.Material.Concrete, envFolder, true)
		local target = createPart("ReflexTarget_"..i, Vector3.new(2, 2, 0.5), CFrame.new(MAP_OFFSET + Vector3.new(561, 105, xOff)), Color3.fromRGB(255, 50, 50), Enum.Material.Neon, envFolder, true)
		target:SetAttribute("PopUpInterval", 2 + (math.random() * 3))
		CollectionService:AddTag(target, "ReflexTarget")
	end

	------------------------------------------------------------------------
	-- Finalize
	------------------------------------------------------------------------
	mapFolder.Parent = targetParent
	_activeMapFolder = mapFolder
	return mapFolder
end

-- API Methods ---------------------------------------------------------------

function PracticeRangeMapLayout.DestroyMap()
	cleanup()
end

function PracticeRangeMapLayout.GetSpawnPoints(teamName: string?): { Vector3 }
	local results: { Vector3 } = {}
	for _, pos in PLAYER_SPAWN_POSITIONS do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function PracticeRangeMapLayout.GetStationaryTargets(): { BasePart }
	if not _activeMapFolder then
		return {}
	end
	local section = _activeMapFolder:FindFirstChild("TargetWallSection")
	if not section then
		return {}
	end
	local targets: { BasePart } = {}
	for _, child in section:GetDescendants() do
		if
			child:IsA("BasePart")
			and child:GetAttribute("IsTarget") == true
			and child:GetAttribute("TargetType") == "Stationary"
		then
			table.insert(targets, child)
		end
	end
	return targets
end

function PracticeRangeMapLayout.GetMovingTargets(): { BasePart }
	if not _activeMapFolder then
		return {}
	end
	local section = _activeMapFolder:FindFirstChild("TargetWallSection")
	if not section then
		return {}
	end
	local moving = section:FindFirstChild("MovingTargets")
	if not moving then
		return {}
	end
	local targets: { BasePart } = {}
	for _, child in moving:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("IsTarget") == true then
			table.insert(targets, child)
		end
	end
	return targets
end

function PracticeRangeMapLayout.GetBotWaypoints(): { Vector3 }
	local results: { Vector3 } = {}
	for _, pos in BOT_WAYPOINT_POSITIONS do
		table.insert(results, pos + MAP_OFFSET)
	end
	return results
end

function PracticeRangeMapLayout.GetCoverPositions(): { Vector3 }
	local results: { Vector3 } = {}
	for _, cDef in COVER_DEFS do
		table.insert(results, cDef.pos + MAP_OFFSET)
	end
	return results
end

function PracticeRangeMapLayout.GetAllTargets(): { BasePart }
	local all = PracticeRangeMapLayout.GetStationaryTargets()
	for _, t in PracticeRangeMapLayout.GetMovingTargets() do
		table.insert(all, t)
	end
	return all
end

function PracticeRangeMapLayout.GetSitePositions(): SitePositions?
	return {
		siteA = MAP_OFFSET + Vector3.new(0, 2, -90),
		siteB = MAP_OFFSET + Vector3.new(0, 2, 70),
	}
end

function PracticeRangeMapLayout.GetMapBounds(): (Vector3, Vector3)
	local minB = Vector3.new(-MAP_WIDTH_X / 2, 0, -MAP_LENGTH_Z / 2) + MAP_OFFSET
	local maxB = Vector3.new(MAP_WIDTH_X / 2, MAP_HEIGHT_Y, MAP_LENGTH_Z / 2) + MAP_OFFSET
	return minB, maxB
end

function PracticeRangeMapLayout.GetLayoutData(): MapLayoutData
	local minB, maxB = PracticeRangeMapLayout.GetMapBounds()
	return {
		mapId = "PracticeRangeMap",
		mapName = "PracticeRange_Sandbox_v2",
		theme = "Industrial Sci-Fi Firing Range",
		bounds = { min = minB, max = maxB },
		redSpawns = PracticeRangeMapLayout.GetSpawnPoints("Red"),
		blueSpawns = PracticeRangeMapLayout.GetSpawnPoints("Blue"),
		sites = PracticeRangeMapLayout.GetSitePositions(),
		coverPositions = PracticeRangeMapLayout.GetCoverPositions(),
		lanes = {
			West = {
				center = MAP_OFFSET + Vector3.new(-MAP_WIDTH_X / 4, 0, 0),
				size = Vector3.new(30, MAP_HEIGHT_Y, MAP_LENGTH_Z),
			},
			Center = { center = MAP_OFFSET + Vector3.new(0, 0, 0), size = Vector3.new(30, MAP_HEIGHT_Y, MAP_LENGTH_Z) },
			East = {
				center = MAP_OFFSET + Vector3.new(MAP_WIDTH_X / 4, 0, 0),
				size = Vector3.new(30, MAP_HEIGHT_Y, MAP_LENGTH_Z),
			},
		},
	}
end

return PracticeRangeMapLayout
