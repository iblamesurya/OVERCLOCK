--!strict
-- src/shared/Map/PrototypeArena.luau — primitive-first arena builder (handoff §4)
-- Implements vetted pipeline: invisible BulletBlocker primitives own collision (Map, CanQuery=true)
-- while vetted meshes are cloned from ServerStorage.Templates.VettedProps into VettedPropSlots.
-- Zero-art fallback: if VettedProps empty, map is still fully playable with primitives only.
-- 8 vetted IDs (AssetRegistry): LowPolyTree 10355960847, LowPolyTreePack 4870769649, LowPolyRocks 6562523344,
--   WoodenBox02 430288318, LowPolyBarrel 4204999283, SciFiContainer 13679876057, EnergyRifleVisual 443695083, TankBotVisual 7198227425
-- Pipeline: Workspace.ScratchAssetAudit -> AuditAsset.luau -> ServerStorage.Templates.VettedProps -> VettedPropSlots
-- Hard-cover pairing: decoration mesh CanQuery=false / Decoration; hard-cover mesh paired with invisible BulletBlocker (Map, CanQuery=true)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PrototypeArena = {}

local function clearGenerated(parent: Instance)
	local existing = parent:FindFirstChild("GeneratedPrototype")
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "GeneratedPrototype"
	folder.Parent = parent
	return folder
end

local function vettedClone(assetKey: string): Instance?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local vp = templates:FindFirstChild("VettedProps")
	if not vp then return nil end
	local byKey = vp:FindFirstChild(assetKey)
	if byKey then return byKey:Clone() end
	-- Fallback by id via AssetRegistry
	local ok, reg = pcall(function()
		local ar = ReplicatedStorage:FindFirstChild("AssetRegistry") or ReplicatedStorage:FindFirstChild("Shared")
		if ar then
			local child = ar:FindFirstChild("AssetRegistry")
			if child then return require(child) end
			if ar:IsA("ModuleScript") then return require(ar) end
		end
		return nil
	end)
	if ok and type(reg) == "table" then
		local rec = (reg :: any)[assetKey]
		if rec and rec.id then
			local byId = vp:FindFirstChild(tostring(rec.id))
			if byId then return byId:Clone() end
			for _, child in vp:GetChildren() do
				if child:GetAttribute("SourceAssetId") == rec.id then
					return child:Clone()
				end
			end
		end
	end
	return nil
end

local function applyVisualProps(inst: Instance, assetKey: string)
	local rec: any = nil
	pcall(function()
		local ar = ReplicatedStorage:FindFirstChild("AssetRegistry")
		if not ar then ar = ReplicatedStorage:FindFirstChild("Shared") end
		if ar then
			local mod = ar:FindFirstChild("AssetRegistry")
			if mod then rec = require(mod) end
		end
	end)
	local role = rec and rec[assetKey] and rec[assetKey].role or "Decoration"
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CollisionGroup = "Decoration"
			d.CanQuery = false
			if role == "HardCover" then
				d:SetAttribute("IsHardCoverVisual", true)
			else
				d:SetAttribute("IsDecoration", true)
			end
		end
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		(inst :: BasePart).CanCollide = false
		(inst :: BasePart).CanTouch = false
		(inst :: BasePart).CollisionGroup = "Decoration"
		(inst :: BasePart).CanQuery = false
		if role == "HardCover" then
			inst:SetAttribute("IsHardCoverVisual", true)
		else
			inst:SetAttribute("IsDecoration", true)
		end
	end
	pcall(function()
		CollectionService:AddTag(inst, "VettedAsset")
		CollectionService:AddTag(inst, "MapProp")
	end)
end

function PrototypeArena.Build(): (Folder, Folder)
	local map = Workspace:WaitForChild("Map")
	local spawns = Workspace:WaitForChild("Spawns")

	local generatedMap = clearGenerated(map)
	local generatedSpawns = clearGenerated(spawns)

	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CollisionGroup = "Map"
		p.Parent = generatedMap
		return p
	end

	local floor = part("ArenaFloor", Vector3.new(220, 4, 160), CFrame.new(0, -2, 0), Color3.fromRGB(46, 62, 75), Enum.Material.Slate)
	CollectionService:AddTag(floor, "MapProp")

	-- Perimeter walls — always BulletBlocker primitives (Map, CanQuery=true)
	for _, cframe in {
		CFrame.new(0, 12, -80),
		CFrame.new(0, 12, 80),
		CFrame.new(-110, 12, 0) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(110, 12, 0) * CFrame.Angles(0, math.rad(90), 0),
	} do
		local wall = part("Boundary", Vector3.new(220, 28, 4), cframe, Color3.fromRGB(22, 30, 38), Enum.Material.Metal)
		wall.CollisionGroup = "Map"
		wall.CanQuery = true
		CollectionService:AddTag(wall, "BulletBlocker")
	end

	-- 8 cover positions — primitive BulletBlocker invisibles (gameplay collision owners)
	-- Each pairs with a vetted mesh clone when available (visual dressing only)
	local coverPositions = {
		Vector3.new(-45, 5, -28),
		Vector3.new(45, 5, -28),
		Vector3.new(-45, 5, 28),
		Vector3.new(45, 5, 28),
		Vector3.new(0, 5, -38),
		Vector3.new(0, 5, 38),
		Vector3.new(-15, 4, 0),
		Vector3.new(15, 4, 0),
	}
	-- Mapping for hard-cover dressing (pairs with invisible blockers)
	-- Covers use 3 hard-cover assets repeating to demonstrate city/warehouse crates
	local hardCoverKeys = { "WoodenBox02", "SciFiContainer", "LowPolyBarrel", "WoodenBox02", "SciFiContainer", "LowPolyBarrel", "WoodenBox02", "SciFiContainer" }
	local hardCoverOffsets = { Vector3.new(0, 1, 0), Vector3.new(0, 2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 2, 0) }

	for index, position in coverPositions do
		-- Invisible primitive owns WeaponRay/ProjectileRay collision (Map, CanQuery=true)
		local blocker = Instance.new("Part")
		blocker.Name = "CoverBlocker_" .. index
		blocker.Size = Vector3.new(12, 10, 4)
		blocker.CFrame = CFrame.new(position)
		blocker.Anchored = true
		blocker.CanCollide = true
		blocker.CanQuery = true
		blocker.CanTouch = false
		blocker.Transparency = 1
		blocker.Color = Color3.fromRGB(109, 72, 51)
		blocker.Material = Enum.Material.SmoothPlastic
		blocker.CollisionGroup = "Map"
		blocker.Parent = generatedMap
		CollectionService:AddTag(blocker, "MapProp")
		CollectionService:AddTag(blocker, "BulletBlocker")

		-- Attempt vetted visual clone (fallback-safe: if no template, blocker alone keeps map playable)
		local assetKey = hardCoverKeys[index]
		local vis = vettedClone(assetKey)
		if vis then
			local off = hardCoverOffsets[index]
			local cf = blocker.CFrame + off
			if vis:IsA("Model") then
				pcall(function() (vis :: Model):PivotTo(cf) end)
				vis.Parent = generatedMap
			elseif vis:IsA("BasePart") then
				(vis :: BasePart).CFrame = cf
				vis.Parent = generatedMap
			else
				pcall(function() (vis :: any):PivotTo(cf) end)
				vis.Parent = generatedMap
			end
			applyVisualProps(vis, assetKey)
		end
	end

	-- VettedPropSlots — holds dressing clones (decoration + weapon/bot) separate from collision
	-- When VettedProps empty, slots are empty markers but blockers still provide cover => zero-art fallback
	local visualSlots = Instance.new("Folder")
	visualSlots.Name = "VettedPropSlots"
	visualSlots.Parent = generatedMap

	local slotDefs = {
		{ key = "LowPolyTree", pos = Vector3.new(-68, 0, -58), offset = Vector3.new(0, 3, 0) },
		{ key = "LowPolyTreePack", pos = Vector3.new(68, 0, -58), offset = Vector3.new(0, 3, 0) },
		{ key = "LowPolyRocks", pos = Vector3.new(-68, 0, 58), offset = Vector3.new(0, 1, 0) },
		{ key = "LowPolyRocks", pos = Vector3.new(68, 0, 58), offset = Vector3.new(0, 1, 0) },
		{ key = "LowPolyTree", pos = Vector3.new(-20, 0, -60), offset = Vector3.new(0, 3, 0) },
		{ key = "LowPolyTreePack", pos = Vector3.new(20, 0, 60), offset = Vector3.new(0, 3, 0) },
		{ key = "EnergyRifleVisual", pos = Vector3.new(-75, 0, 0), offset = Vector3.new(0, 2, 0) },
		{ key = "TankBotVisual", pos = Vector3.new(75, 0, 0), offset = Vector3.new(0, 3, 0) },
	}
	for i, def in slotDefs do
		local marker = Instance.new("Part")
		marker.Name = "AssetSlot_" .. i .. "_" .. def.key
		marker.Anchored = true
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Size = Vector3.new(1, 1, 1)
		marker.CFrame = CFrame.new(def.pos)
		marker.CollisionGroup = "Decoration"
		marker.Parent = visualSlots
		-- Try clone vetted mesh into slot (parent to slots folder, at marker)
		local vis = vettedClone(def.key)
		if vis then
			local cf = marker.CFrame + def.offset
			if vis:IsA("Model") then
				pcall(function() (vis :: Model):PivotTo(cf) end)
				vis.Parent = visualSlots
			elseif vis:IsA("BasePart") then
				(vis :: BasePart).CFrame = cf
				vis.Parent = visualSlots
			else
				pcall(function() (vis :: any):PivotTo(cf) end)
				vis.Parent = visualSlots
			end
			applyVisualProps(vis, def.key)
		end
	end

	-- Fallback markers kept for handoff compatibility (3 original slots if above fails)
	if #visualSlots:GetChildren() < 3 then
		for i, position in { Vector3.new(-48, 0, -28), Vector3.new(48, 0, 28), Vector3.new(0, 0, -38) } do
			if not visualSlots:FindFirstChild("AssetSlot_" .. i) then
				local marker = Instance.new("Part")
				marker.Name = "AssetSlot_" .. i
				marker.Anchored = true
				marker.Transparency = 1
				marker.CanCollide = false
				marker.CanTouch = false
				marker.CanQuery = false
				marker.Size = Vector3.new(1, 1, 1)
				marker.CFrame = CFrame.new(position)
				marker.CollisionGroup = "Decoration"
				marker.Parent = visualSlots
			end
		end
	end

	local function spawnLocation(name: string, position: Vector3, teamColor: BrickColor)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = name
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = position
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.TeamColor = teamColor
		spawn.CollisionGroup = "Triggers"
		spawn.Parent = generatedSpawns
		CollectionService:AddTag(spawn, "SpawnPoint")
	end

	spawnLocation("NorthSpawn", Vector3.new(0, 1, -62), BrickColor.new("Bright blue"))
	spawnLocation("SouthSpawn", Vector3.new(0, 1, 62), BrickColor.new("Bright red"))

	print("Primitive-first arena built: valid spawns, cover (invisible BulletBlocker + vetted dressing), VettedPropSlots, zero-art fallback")
	return generatedMap, generatedSpawns
end

return PrototypeArena
