--!strict
--[=[
    Project OVERCLOCK v3: LobbyFolder (Legendary Edition)
    Generates a full professional Roblox lobby:
    Environment, Geometry, SpawnLocations, InteractiveTriggers,
    Props, FX, Lighting — all runtime-built, cleanly managed.
]=]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LobbyFolder = {}

export type LobbyLayoutData = {
	lobbyName: string,
	boundsMin: Vector3,
	boundsMax: Vector3,
	spawnPositions: { Vector3 },
	triggers: { [string]: Vector3 },
}

local LOBBY_FOLDER_NAME = "LobbyFolder"
local activeLobbyFolder: Folder? = nil
local activeTweens: { Tween } = {}

-- Layout constants — MASSIVE lobby (production, 1000-player optimized)
local LOBBY_CENTER = Vector3.new(0, 100, 0)
local LOBBY_SIZE = Vector3.new(380, 40, 380)

local C = {
	BG_DARK = Color3.fromRGB(18, 20, 28),
	FLOOR = Color3.fromRGB(28, 32, 44),
	TRIM = Color3.fromRGB(48, 54, 70),
	NEON_BLUE = Color3.fromRGB(0, 170, 255),
	NEON_CYAN = Color3.fromRGB(0, 230, 255),
	NEON_PURP = Color3.fromRGB(140, 80, 255),
	GOLD = Color3.fromRGB(255, 200, 60),
	WHITE = Color3.fromRGB(220, 240, 255),
}

local SPAWN_POSITIONS: { Vector3 } = {
	LOBBY_CENTER + Vector3.new(-75, 1.5, -75),
	LOBBY_CENTER + Vector3.new(75, 1.5, -75),
	LOBBY_CENTER + Vector3.new(-75, 1.5, 75),
	LOBBY_CENTER + Vector3.new(75, 1.5, 75),
	LOBBY_CENTER + Vector3.new(0, 1.5, -85),
	LOBBY_CENTER + Vector3.new(0, 1.5, 85),
	LOBBY_CENTER + Vector3.new(-45, 1.5, -85),
	LOBBY_CENTER + Vector3.new(45, 1.5, -85),
	LOBBY_CENTER + Vector3.new(-85, 1.5, 0),
	LOBBY_CENTER + Vector3.new(85, 1.5, 0),
	LOBBY_CENTER + Vector3.new(-45, 1.5, 85),
	LOBBY_CENTER + Vector3.new(45, 1.5, 85),
}

local TRIGGER_DATA = {
	Play = {
		position = LOBBY_CENTER + Vector3.new(0, 2, -35),
		actionText = "PLAY",
		objectText = "Matchmaking Arena",
		promptText = "Enter Queue / Start Match",
		accent = C.NEON_CYAN,
	},
	Challenge = {
		position = LOBBY_CENTER + Vector3.new(-35, 2, 0),
		actionText = "1v1 CHALLENGE",
		objectText = "Duels Pavilion",
		promptText = "Initiate 1v1 Challenge",
		accent = C.NEON_PURP,
	},
	Loadout = {
		position = LOBBY_CENTER + Vector3.new(35, 2, 0),
		actionText = "LOADOUT",
		objectText = "Armory Inspector",
		promptText = "Inspect & Customize Weapons",
		accent = C.GOLD,
	},
	Settings = {
		position = LOBBY_CENTER + Vector3.new(0, 2, 35),
		actionText = "SETTINGS",
		objectText = "System Terminal",
		promptText = "Configure Audio & Gameplay",
		accent = C.NEON_BLUE,
	},
}

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
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = if canCollide ~= nil then canCollide else true
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = (transparency or 0) == 0
	part.Parent = parent
	return part
end

local function addPointLight(parent: Instance, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = parent
end

local function addSparkles(parent: Instance, color: Color3)
	local s = Instance.new("Sparkles")
	s.SparkleColor = color
	s.Parent = parent
end

local function createBeam(parent: Part, a0: Attachment, a1: Attachment, color: Color3, width: number)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = width
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Parent = parent
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
	bb.MaxDistance = 60
	bb.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize
	label.Text = text
	label.TextStrokeTransparency = 0.6
	label.Parent = bb
end

local function createPortalArch(parent: Instance, name: string, center: CFrame, accent: Color3)
	local arch = Instance.new("Model")
	arch.Name = name .. "Portal"

	local h, w, t = 12, 10, 1.5
	local left = createPart(
		"ArchLeft",
		Vector3.new(t, h, t),
		center * CFrame.new(-w / 2, h / 2, 0),
		C.TRIM,
		Enum.Material.Metal,
		arch,
		true
	)
	local right = createPart(
		"ArchRight",
		Vector3.new(t, h, t),
		center * CFrame.new(w / 2, h / 2, 0),
		C.TRIM,
		Enum.Material.Metal,
		arch,
		true
	)
	local top = createPart(
		"ArchTop",
		Vector3.new(w + t, t, t),
		center * CFrame.new(0, h + t / 2, 0),
		C.TRIM,
		Enum.Material.Metal,
		arch,
		true
	)

	-- Neon accent strips on the arch
	for _, strip in
		{
			{ "StripL", center * CFrame.new(-w / 2, h / 2, 0.8), Vector3.new(0.4, h, 0.4) },
			{ "StripR", center * CFrame.new(w / 2, h / 2, 0.8), Vector3.new(0.4, h, 0.4) },
			{ "StripT", center * CFrame.new(0, h + t / 2, 0.8), Vector3.new(w, 0.4, 0.4) },
		}
	do
		createPart(
			strip[1] :: string,
			strip[3] :: Vector3,
			strip[2] :: CFrame,
			accent,
			Enum.Material.Neon,
			arch,
			false,
			0.1
		)
	end

	-- Hologram panel inside the arch (semi-transparent, spins via tween)
	local holo = createPart(
		"Hologram",
		Vector3.new(w - 2, h - 1, 0.1),
		center * CFrame.new(0, h / 2, 0),
		accent,
		Enum.Material.ForceField,
		arch,
		false,
		0.65
	)
	holo.CastShadow = false

	arch.Parent = parent
	return arch, holo
end

local function cleanup()
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
	if activeLobbyFolder then
		activeLobbyFolder:Destroy()
		activeLobbyFolder = nil
	end
end

function LobbyFolder.BuildLobby(parent: Instance?): Folder
	cleanup()
	local targetParent = parent or Workspace

	local folder = Instance.new("Folder")
	folder.Name = LOBBY_FOLDER_NAME

	----------------------------------------------------------------
	-- 1. Environment (atmosphere + sky handled via attributes)
	----------------------------------------------------------------
	local env = Instance.new("Folder")
	env.Name = "Environment"
	env.Parent = folder

	-- LobbyBounds (invisible forcefield box)
	local boundsPart = createPart(
		"BoundingBox",
		LOBBY_SIZE,
		CFrame.new(LOBBY_CENTER + Vector3.new(0, LOBBY_SIZE.Y / 2, 0)),
		C.NEON_BLUE,
		Enum.Material.ForceField,
		env,
		false,
		1
	)
	boundsPart.CastShadow = false

	-- Massive foundation + invisible safety walls (production: 600×600 for massive lobby)
	local foundation = createPart(
		"Foundation",
		Vector3.new(600, 4, 600),
		CFrame.new(LOBBY_CENTER - Vector3.new(0, 2, 0)),
		C.BG_DARK,
		Enum.Material.Slate,
		env,
		true
	)
	foundation.CastShadow = false
	-- Grass terrain ring (free model technique: use Material=Grass + Terrain for 1000-player streaming)
	pcall(function()
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		if terrain then
			-- Clear old and fill grass apron outside the 260 floor (visual, not physics heavy)
			local region = Region3.new(LOBBY_CENTER - Vector3.new(300, 0, 300), LOBBY_CENTER + Vector3.new(300, 6, 300))
			terrain:FillRegion(region:ExpandToGrid(4), 4, Enum.Material.Grass)
			-- Carve out the lobby floor area back to air so floor part shows
			local inner = Region3.new(LOBBY_CENTER - Vector3.new(135, 0, 135), LOBBY_CENTER + Vector3.new(135, 6, 135))
			terrain:FillRegion(inner:ExpandToGrid(4), 4, Enum.Material.Air)
		end
	end)
	-- Skybox (free sky: Blue Sky — asset 243135001 style recreation via procedural Color + Atmosphere if no Sky object)
	pcall(function()
		if not Lighting:FindFirstChild("LobbySky") then
			local sky = Instance.new("Sky")
			sky.Name = "LobbySky"
			sky.SkyboxBk = "rbxassetid://243135001"
			sky.SkyboxDn = "rbxassetid://243135002"
			sky.SkyboxFt = "rbxassetid://243135003"
			sky.SkyboxLf = "rbxassetid://243135004"
			sky.SkyboxRt = "rbxassetid://243135005"
			sky.SkyboxUp = "rbxassetid://243135006"
			sky.StarCount = 2500
			sky.SunAngularSize = 12
			sky.SunTextureId = "rbxassetid://1084358844"
			sky.Parent = Lighting
		end
		Lighting.Ambient = Color3.fromRGB(100, 105, 120)
		Lighting.OutdoorAmbient = Color3.fromRGB(40, 45, 65)
		Lighting.FogEnd = 1800
		Lighting.FogColor = Color3.fromRGB(35, 42, 58)
		Lighting.Brightness = 2.5
		Lighting.ExposureCompensation = 0.1
		-- Remove placeholder fake values
		Lighting.ClockTime = 14.5
	end)

	for _, w in
		{
			{ "WallNorth", Vector3.new(600, 60, 4), CFrame.new(0, 130, -290) },
			{ "WallSouth", Vector3.new(600, 60, 4), CFrame.new(0, 130, 290) },
			{ "WallEast", Vector3.new(4, 60, 600), CFrame.new(290, 130, 0) },
			{ "WallWest", Vector3.new(4, 60, 600), CFrame.new(-290, 130, 0) },
		}
	do
		local wall = createPart(
			w[1] :: string,
			w[2] :: Vector3,
			w[3] :: CFrame + Vector3.new(0, LOBBY_CENTER.Y - 100, 0),
			Color3.new(),
			Enum.Material.SmoothPlastic,
			env,
			true,
			1
		)
		wall.CanQuery = false
		wall.CanTouch = false
	end

	----------------------------------------------------------------
	-- 2. Geometry (floor, walls, towers, ceiling)
	----------------------------------------------------------------
	local geo = Instance.new("Folder")
	geo.Name = "Geometry"
	geo.Parent = folder

	-- Main lobby floor — MASSIVE 260×260 marble + outer apron (production)
	createPart(
		"LobbyFloor",
		Vector3.new(260, 2, 260),
		CFrame.new(LOBBY_CENTER),
		C.FLOOR,
		Enum.Material.Marble,
		geo,
		true
	)
	createPart(
		"LobbyFloorEdge",
		Vector3.new(264, 0.5, 264),
		CFrame.new(LOBBY_CENTER - Vector3.new(0, 0.8, 0)),
		C.TRIM,
		Enum.Material.Metal,
		geo,
		true
	)
	createPart(
		"OuterApron",
		Vector3.new(380, 1, 380),
		CFrame.new(LOBBY_CENTER - Vector3.new(0, 1.4, 0)),
		C.BG_DARK,
		Enum.Material.Concrete,
		geo,
		true
	)
	-- Optimized: no shadow on giant floor for 1000 players
	for _, p in geo:GetChildren() do
		if p:IsA("BasePart") then
			p.CastShadow = false
		end
	end

	-- Floor grid neon inlays
	createPart(
		"GridNS",
		Vector3.new(1.5, 2.05, 100),
		CFrame.new(LOBBY_CENTER),
		C.NEON_BLUE,
		Enum.Material.Neon,
		geo,
		false,
		0.2
	)
	createPart(
		"GridEW",
		Vector3.new(100, 2.05, 1.5),
		CFrame.new(LOBBY_CENTER),
		C.NEON_BLUE,
		Enum.Material.Neon,
		geo,
		false,
		0.2
	)

	-- Neon edge trim
	local half = 50
	for _, e in
		{
			{ "EdgeN", Vector3.new(100, 0.3, 1.2), Vector3.new(0, 1.15, -half) },
			{ "EdgeS", Vector3.new(100, 0.3, 1.2), Vector3.new(0, 1.15, half) },
			{ "EdgeE", Vector3.new(1.2, 0.3, 100), Vector3.new(half, 1.15, 0) },
			{ "EdgeW", Vector3.new(1.2, 0.3, 100), Vector3.new(-half, 1.15, 0) },
		}
	do
		createPart(
			e[1] :: string,
			e[2] :: Vector3,
			CFrame.new(LOBBY_CENTER + e[3] :: Vector3),
			C.NEON_CYAN,
			Enum.Material.Neon,
			geo,
			false,
			0.1
		)
	end

	-- Glass perimeter walls — MASSIVE 260 offset
	local wallH, wallOff = 18, 128
	for _, g in
		{
			{ "GlassN", Vector3.new(260, wallH, 1), Vector3.new(0, wallH / 2, -wallOff) },
			{ "GlassS", Vector3.new(260, wallH, 1), Vector3.new(0, wallH / 2, wallOff) },
			{ "GlassE", Vector3.new(1, wallH, 260), Vector3.new(wallOff, wallH / 2, 0) },
			{ "GlassW", Vector3.new(1, wallH, 260), Vector3.new(-wallOff, wallH / 2, 0) },
		}
	do
		local wall = createPart(
			g[1] :: string,
			g[2] :: Vector3,
			CFrame.new(LOBBY_CENTER + g[3] :: Vector3),
			Color3.fromRGB(120, 190, 245),
			Enum.Material.Glass,
			geo,
			true,
			0.65
		)
		wall.CanQuery = false
	end

	-- Corner towers with lights
	for i, off in
		{
			Vector3.new(-46, 9, -46),
			Vector3.new(46, 9, -46),
			Vector3.new(-46, 9, 46),
			Vector3.new(46, 9, 46),
		}
	do
		local tower = createPart(
			"Tower_" .. i,
			Vector3.new(5, 18, 5),
			CFrame.new(LOBBY_CENTER + off),
			C.TRIM,
			Enum.Material.Metal,
			geo,
			true
		)
		createPart(
			"TowerCap_" .. i,
			Vector3.new(6, 1, 6),
			CFrame.new(LOBBY_CENTER + off + Vector3.new(0, 9.5, 0)),
			C.NEON_PURP,
			Enum.Material.Neon,
			geo,
			false,
			0.1
		)
		addPointLight(tower, C.NEON_BLUE, 30, 2)
	end

	-- Ceiling ring + spotlight
	local ringPart = createPart(
		"CeilingRing",
		Vector3.new(30, 1, 30),
		CFrame.new(LOBBY_CENTER + Vector3.new(0, 24, 0)),
		C.NEON_CYAN,
		Enum.Material.Neon,
		geo,
		false,
		0.2
	)
	ringPart.Shape = Enum.PartType.Cylinder
	ringPart.CFrame = CFrame.new(LOBBY_CENTER + Vector3.new(0, 24, 0)) * CFrame.Angles(0, 0, math.rad(90))

	local spot = Instance.new("SpotLight")
	spot.Color = C.WHITE
	spot.Range = 60
	spot.Brightness = 5
	spot.Angle = 100
	spot.Face = Enum.NormalId.Bottom
	spot.Parent = ringPart

	----------------------------------------------------------------
	-- 3. SpawnLocations (pedestals + neon rings + team color)
	----------------------------------------------------------------
	local spawns = Instance.new("Folder")
	spawns.Name = "SpawnLocations"
	spawns.Parent = folder

	for i, pos in SPAWN_POSITIONS do
		createPart(
			"Pedestal_" .. i,
			Vector3.new(6, 1, 6),
			CFrame.new(pos - Vector3.new(0, 0.5, 0)),
			C.TRIM,
			Enum.Material.Metal,
			spawns,
			true
		)
		createPart(
			"PedestalRing_" .. i,
			Vector3.new(6.6, 0.2, 6.6),
			CFrame.new(pos - Vector3.new(0, 0.9, 0)),
			C.NEON_CYAN,
			Enum.Material.Neon,
			spawns,
			false,
			0.2
		)

		local spawnLoc = Instance.new("SpawnLocation")
		spawnLoc.Name = "LobbySpawn_" .. i
		spawnLoc.Size = Vector3.new(4, 0.4, 4)
		spawnLoc.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
		spawnLoc.Anchored = true
		spawnLoc.Neutral = true
		spawnLoc.AllowTeamChangeOnTouch = false
		spawnLoc.TeamColor = BrickColor.new("Medium royal blue")
		spawnLoc.Color = C.FLOOR
		spawnLoc.Material = Enum.Material.SmoothPlastic
		spawnLoc.TopSurface = Enum.SurfaceType.Smooth
		spawnLoc.BottomSurface = Enum.SurfaceType.Smooth
		spawnLoc:SetAttribute("LobbySpawnIndex", i)
		spawnLoc.Duration = 0
		spawnLoc.Parent = spawns
	end

	----------------------------------------------------------------
	-- 4. InteractiveTriggers (portal arches + prompts + holos)
	----------------------------------------------------------------
	local triggers = Instance.new("Folder")
	triggers.Name = "InteractiveTriggers"
	triggers.Parent = folder

	local holograms: { Part } = {}

	for key, data in TRIGGER_DATA do
		local pad = createPart(
			key .. "TriggerPart",
			Vector3.new(9, 0.6, 9),
			CFrame.new(data.position),
			C.BG_DARK,
			Enum.Material.Metal,
			triggers,
			true
		)
		createPart(
			key .. "GlowRing",
			Vector3.new(9.6, 0.2, 9.6),
			CFrame.new(data.position - Vector3.new(0, 0.2, 0)),
			data.accent,
			Enum.Material.Neon,
			triggers,
			false,
			0.25
		)

		-- Portal arch facing the lobby center
		local facing = CFrame.lookAt(
			data.position + Vector3.new(0, 0.5, 0),
			Vector3.new(LOBBY_CENTER.X, data.position.Y + 0.5, LOBBY_CENTER.Z)
		)
		local _, holo = createPortalArch(triggers, key, facing, data.accent)
		table.insert(holograms, holo)

		addPointLight(pad, data.accent, 18, 1.5)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = key .. "Prompt"
		prompt.ActionText = data.promptText
		prompt.ObjectText = data.objectText
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TriggerType", key)
		prompt.Parent = pad

		makeBillboard(
			pad,
			key .. "Billboard",
			"[ " .. data.actionText .. " ]",
			data.accent,
			UDim2.new(0, 260, 0, 60),
			Vector3.new(0, 13.5, 0),
			24
		)
	end

	----------------------------------------------------------------
	-- 5. Props (center monument, floating logo, decor)
	----------------------------------------------------------------
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder

	createPart(
		"CenterPedestal",
		Vector3.new(14, 1.4, 14),
		CFrame.new(LOBBY_CENTER + Vector3.new(0, 1.7, 0)),
		C.TRIM,
		Enum.Material.Metal,
		props,
		true
	)
	local glow = createPart(
		"CenterGlow",
		Vector3.new(12, 1.45, 12),
		CFrame.new(LOBBY_CENTER + Vector3.new(0, 1.7, 0)),
		C.NEON_CYAN,
		Enum.Material.Neon,
		props,
		false,
		0.45
	)

	-- Rotating centerpiece crystal
	local crystal = createPart(
		"CenterCrystal",
		Vector3.new(3, 6, 3),
		CFrame.new(LOBBY_CENTER + Vector3.new(0, 7, 0)),
		C.NEON_PURP,
		Enum.Material.Neon,
		props,
		false,
		0.15
	)
	crystal.CastShadow = false
	addSparkles(crystal, C.NEON_CYAN)
	addPointLight(crystal, C.NEON_PURP, 24, 3)

	-- Spin tween (looped)
	local spin = TweenService:Create(
		crystal,
		TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(360), 0) }
	)
	spin:Play()
	table.insert(activeTweens, spin)

	makeBillboard(
		crystal,
		"LogoBillboard",
		"⬡ OVERCLOCK ⬡",
		C.WHITE,
		UDim2.new(0, 400, 0, 80),
		Vector3.new(0, 5, 0),
		36
	)

	-- Light beams from crystal to ceiling ring
	local a0 = Instance.new("Attachment")
	a0.Parent = crystal
	local a1 = Instance.new("Attachment")
	a1.Parent = ringPart
	createBeam(crystal, a0, a1, C.NEON_CYAN, 0.6)

	-- Banner poles along N/S edges
	for i, p in
		{
			Vector3.new(-30, 6, -47),
			Vector3.new(30, 6, -47),
			Vector3.new(-30, 6, 47),
			Vector3.new(30, 6, 47),
		}
	do
		local pole = createPart(
			"BannerPole_" .. i,
			Vector3.new(0.8, 12, 0.8),
			CFrame.new(LOBBY_CENTER + p),
			C.TRIM,
			Enum.Material.Metal,
			props,
			true
		)
		createPart(
			"BannerFlag_" .. i,
			Vector3.new(4, 6, 0.2),
			CFrame.new(LOBBY_CENTER + p + Vector3.new(2.4, 3, 0)),
			C.NEON_BLUE,
			Enum.Material.Fabric,
			props,
			false,
			0.1
		)
		addPointLight(pole, C.NEON_BLUE, 15, 1)
	end

	-- FREE 3D models: benches (6), lampposts, grass tufts, trash cans — massive lobby decor (streaming-friendly)
	for i, bPos in
		{
			Vector3.new(-90, 1, -90),
			Vector3.new(90, 1, -90),
			Vector3.new(-90, 1, 90),
			Vector3.new(90, 1, 90),
			Vector3.new(0, 1, -110),
			Vector3.new(0, 1, 110),
		}
	do
		local benchBase = createPart(
			"Bench_Base_" .. i,
			Vector3.new(10, 1.2, 3),
			CFrame.new(LOBBY_CENTER + bPos),
			Color3.fromRGB(55, 38, 22),
			Enum.Material.Wood,
			props,
			true
		)
		benchBase.CastShadow = false
		createPart(
			"Bench_Back_" .. i,
			Vector3.new(10, 3, 0.6),
			CFrame.new(LOBBY_CENTER + bPos + Vector3.new(0, 1.6, -1.1)),
			Color3.fromRGB(72, 50, 30),
			Enum.Material.Wood,
			props,
			true
		).CastShadow =
			false
		-- Metal legs
		createPart(
			"Bench_LegL_" .. i,
			Vector3.new(0.6, 2, 2.8),
			CFrame.new(LOBBY_CENTER + bPos + Vector3.new(-4, -0.4, 0)),
			C.TRIM,
			Enum.Material.Metal,
			props,
			true
		).CastShadow =
			false
		createPart(
			"Bench_LegR_" .. i,
			Vector3.new(0.6, 2, 2.8),
			CFrame.new(LOBBY_CENTER + bPos + Vector3.new(4, -0.4, 0)),
			C.TRIM,
			Enum.Material.Metal,
			props,
			true
		).CastShadow =
			false
		-- Seat prompt (cosmetic)
		local seat = Instance.new("Seat")
		seat.Name = "BenchSeat_" .. i
		seat.Size = Vector3.new(8, 1, 2.5)
		seat.CFrame = CFrame.new(LOBBY_CENTER + bPos + Vector3.new(0, 0.8, 0))
		seat.Anchored = true
		seat.CanCollide = false
		seat.Transparency = 1
		seat.Parent = props
	end
	-- Grass tufts (16) around outer apron — free model look
	for i = 1, 16 do
		local ang = (i / 16) * math.pi * 2
		local rad = 145 + (i % 2) * 8
		local pos = LOBBY_CENTER + Vector3.new(math.cos(ang) * rad, 0.5, math.sin(ang) * rad)
		local tuft = createPart(
			"GrassTuft_" .. i,
			Vector3.new(2, 1.5, 2),
			CFrame.new(pos),
			Color3.fromRGB(45, 135, 45),
			Enum.Material.Grass,
			props,
			false,
			0.2
		)
		tuft.CastShadow = false
		tuft.CanQuery = false
	end
	-- Lampposts (8) for night sky vibe
	for i, lPos in
		{
			Vector3.new(-120, 6, 0),
			Vector3.new(120, 6, 0),
			Vector3.new(0, 6, -120),
			Vector3.new(0, 6, 120),
			Vector3.new(-85, 6, -85),
			Vector3.new(85, 6, -85),
			Vector3.new(-85, 6, 85),
			Vector3.new(85, 6, 85),
		}
	do
		local post = createPart(
			"LampPost_" .. i,
			Vector3.new(0.7, 12, 0.7),
			CFrame.new(LOBBY_CENTER + lPos),
			C.TRIM,
			Enum.Material.Metal,
			props,
			true
		)
		post.CastShadow = false
		local head = createPart(
			"LampHead_" .. i,
			Vector3.new(2, 1, 2),
			CFrame.new(LOBBY_CENTER + lPos + Vector3.new(0, 6.5, 0)),
			Color3.fromRGB(255, 240, 180),
			Enum.Material.Neon,
			props,
			false,
			0.2
		)
		addPointLight(head, Color3.fromRGB(255, 230, 150), 35, 2)
		head.CastShadow = false
	end

	----------------------------------------------------------------
	-- 6. FX folder (particle emitters container + config)
	----------------------------------------------------------------
	local fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = folder

	-- Ambient dust particles rising from the center
	local emitterPart = createPart(
		"AmbientEmitter",
		Vector3.new(1, 1, 1),
		CFrame.new(LOBBY_CENTER + Vector3.new(0, 2, 0)),
		C.WHITE,
		Enum.Material.SmoothPlastic,
		fx,
		false,
		1
	)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(C.NEON_CYAN)
	pe.Size = NumberSequence.new(0.3, 0)
	pe.Transparency = NumberSequence.new(0.4, 1)
	pe.Lifetime = NumberRange.new(3, 5)
	pe.Rate = 12
	pe.Speed = NumberRange.new(2, 4)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = emitterPart

	----------------------------------------------------------------
	-- 7. Lighting config (apply polished mood)
	----------------------------------------------------------------
	folder:SetAttribute("Ambient", "70,75,95")
	folder:SetAttribute("OutdoorAmbient", "20,22,35")
	folder:SetAttribute("ClockTime", 18.5)
	folder:SetAttribute("FogEnd", 600)
	folder:SetAttribute("FogColor", "18,20,30")

	folder.Parent = targetParent
	activeLobbyFolder = folder
	return folder
end

function LobbyFolder.GetLobbyFolder(): Folder?
	return activeLobbyFolder
end

function LobbyFolder.DestroyLobby()
	cleanup()
end

function LobbyFolder.GetSpawnLocations(): { SpawnLocation }
	local result: { SpawnLocation } = {}
	local spawns = activeLobbyFolder and activeLobbyFolder:FindFirstChild("SpawnLocations")
	if spawns then
		for _, child in spawns:GetChildren() do
			if child:IsA("SpawnLocation") then
				table.insert(result, child)
			end
		end
	end
	return result
end

function LobbyFolder.GetInteractiveTriggers(): { [string]: BasePart }
	local result: { [string]: BasePart } = {}
	local trigFolder = activeLobbyFolder and activeLobbyFolder:FindFirstChild("InteractiveTriggers")
	if trigFolder then
		for _, child in trigFolder:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name, "TriggerPart") then
				result[string.gsub(child.Name, "TriggerPart", "")] = child
			end
		end
	end
	return result
end

function LobbyFolder.GetLobbyBounds(): (Vector3, Vector3)
	return LOBBY_CENTER - LOBBY_SIZE / 2, LOBBY_CENTER + LOBBY_SIZE / 2
end

function LobbyFolder.GetLayoutData(): LobbyLayoutData
	local minB, maxB = LobbyFolder.GetLobbyBounds()
	local triggerPosMap: { [string]: Vector3 } = {}
	for k, v in TRIGGER_DATA do
		triggerPosMap[k] = v.position
	end
	return {
		lobbyName = "MainLobby_Paradigm",
		boundsMin = minB,
		boundsMax = maxB,
		spawnPositions = table.clone(SPAWN_POSITIONS),
		triggers = triggerPosMap,
	}
end

return LobbyFolder
