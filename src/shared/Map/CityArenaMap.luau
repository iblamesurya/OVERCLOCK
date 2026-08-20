--!strict
--[=[
	Project OVERCLOCK: CityArenaMap — City/Warehouse pillar with vetted dressing
	Industrial city takeover: same vetted pipeline as CommunityArenaMap/PrototypeArena
	but with Urban Warehouse footprint (shipping containers, crates, catwalks).
	Gameplay collision is ALWAYS invisible BulletBlocker primitives (Map, CanQuery=true).
	Visual dressing is cloned from ServerStorage.Templates.VettedProps into VettedPropSlots.
	Zero-art fallback: if VettedProps empty, map is still fully playable with primitives.
	Pipeline: Workspace.ScratchAssetAudit -> audit_asset.luau -> VettedProps -> VettedPropSlots
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VettedPropHelper: any = nil
pcall(function()
	VettedPropHelper = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("VettedPropHelper") :: any)
end)

local AssetRegistry: any = nil
pcall(function()
	AssetRegistry = require(ReplicatedStorage:WaitForChild("AssetRegistry", 2) :: any)
end)
if not AssetRegistry then
	pcall(function()
		AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared", 2):WaitForChild("AssetRegistry", 2) :: any)
	end)
end

local MAP_FOLDER_NAME = "CityArenaMap"
local MAP_OFFSET = Vector3.new(2000, 100, 0) -- city district offset (away from Community@1500, Neon@1000, Practice@500)

local CityArenaMap = {}
local _activeFolder: Folder? = nil

local function vettedClone(assetKey: string): Instance?
	if VettedPropHelper and VettedPropHelper.CloneVetted then
		return VettedPropHelper.CloneVetted(assetKey)
	end
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local vp = templates:FindFirstChild("VettedProps")
	if not vp then return nil end
	local byKey = vp:FindFirstChild(assetKey)
	if byKey then return byKey:Clone() end
	if AssetRegistry then
		local rec = AssetRegistry[assetKey]
		if rec then
			local byId = vp:FindFirstChild(tostring(rec.id))
			if byId then return byId:Clone() end
			for _, child in vp:GetChildren() do
				if child:GetAttribute("SourceAssetId") == rec.id then return child:Clone() end
			end
		end
	end
	return nil
end

local function applyVisual(inst: Instance, assetKey: string)
	if VettedPropHelper and VettedPropHelper.ApplyVisualProps then
		VettedPropHelper.ApplyVisualProps(inst, assetKey)
		return
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CollisionGroup = "Decoration"
			d.CanQuery = false
		end
	end
	if inst:IsA("BasePart") then
		(inst :: BasePart).Anchored = true
		(inst :: BasePart).CanCollide = false
		(inst :: BasePart).CollisionGroup = "Decoration"
		(inst :: BasePart).CanQuery = false
	end
	pcall(function()
		CollectionService:AddTag(inst, "VettedAsset")
		CollectionService:AddTag(inst, "MapProp")
	end)
end

local function makeInvisibleBlocker(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	if VettedPropHelper and VettedPropHelper.MakeInvisibleBlocker then
		return VettedPropHelper.MakeInvisibleBlocker(name, size, cframe, parent)
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.Transparency = 1
	p.CollisionGroup = "Map"
	p.Parent = parent
	CollectionService:AddTag(p, "BulletBlocker")
	CollectionService:AddTag(p, "MapProp")
	return p
end

local function placeVisual(blocker: Part, assetKey: string, offset: Vector3?)
	local vis = vettedClone(assetKey)
	if not vis then return nil end
	local cf = blocker.CFrame
	if offset then cf += offset end
	if vis:IsA("Model") then
		pcall(function() (vis :: Model):PivotTo(cf) end)
		vis.Parent = blocker.Parent
	elseif vis:IsA("BasePart") then
		(vis :: BasePart).CFrame = cf
		vis.Parent = blocker.Parent
	else
		pcall(function() (vis :: any):PivotTo(cf) end)
		vis.Parent = blocker.Parent
	end
	applyVisual(vis, assetKey)
	return vis
end

local RED_SPAWNS: { Vector3 } = {
	MAP_OFFSET + Vector3.new(-14, 2, -105),
	MAP_OFFSET + Vector3.new(-7, 2, -105),
	MAP_OFFSET + Vector3.new(0, 2, -105),
	MAP_OFFSET + Vector3.new(7, 2, -105),
	MAP_OFFSET + Vector3.new(14, 2, -105),
}
local BLUE_SPAWNS: { Vector3 } = {
	MAP_OFFSET + Vector3.new(-14, 2, 105),
	MAP_OFFSET + Vector3.new(-7, 2, 105),
	MAP_OFFSET + Vector3.new(0, 2, 105),
	MAP_OFFSET + Vector3.new(7, 2, 105),
	MAP_OFFSET + Vector3.new(14, 2, 105),
}

local COVER_POSITIONS: { Vector3 } = {
	MAP_OFFSET + Vector3.new(-50, 3.5, -40),
	MAP_OFFSET + Vector3.new(-62, 1.75, -30),
	MAP_OFFSET + Vector3.new(-38, 1.75, -50),
	MAP_OFFSET + Vector3.new(50, 3.5, 40),
	MAP_OFFSET + Vector3.new(62, 1.75, 30),
	MAP_OFFSET + Vector3.new(38, 1.75, 50),
	MAP_OFFSET + Vector3.new(-18, 3.5, 0),
	MAP_OFFSET + Vector3.new(18, 3.5, 0),
}

function CityArenaMap.BuildMap(parent: Instance?): Folder
	if _activeFolder then
		_activeFolder:Destroy()
		_activeFolder = nil
	end
	local targetParent = parent or Workspace
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME
	mapFolder.Parent = targetParent
	_activeFolder = mapFolder

	local gen = Instance.new("Folder")
	gen.Name = "GeneratedCity"
	gen.Parent = mapFolder

	-- Floor & perimeter (city concrete)
	local function createPart(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, colGroup: string?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CollisionGroup = colGroup or "Map"
		p.Parent = gen
		if p.Size.Y >= 3 and p.CollisionGroup == "Map" then
		CollectionService:AddTag(p, "BulletBlocker")
	end
	return p
	end

	local floor = createPart("CityFloor", Vector3.new(240, 4, 260), CFrame.new(MAP_OFFSET + Vector3.new(0, -2, 0)), Color3.fromRGB(68, 72, 78), Enum.Material.Concrete, "Map")
	CollectionService:AddTag(floor, "MapProp")

	for _, cf in {
		CFrame.new(MAP_OFFSET + Vector3.new(0, 16, -130)),
		CFrame.new(MAP_OFFSET + Vector3.new(0, 16, 130)),
		CFrame.new(MAP_OFFSET + Vector3.new(-120, 16, 0)) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(MAP_OFFSET + Vector3.new(120, 16, 0)) * CFrame.Angles(0, math.rad(90), 0),
	} do
		local w = createPart("Boundary", Vector3.new(240, 32, 4), cf, Color3.fromRGB(35, 38, 45), Enum.Material.Concrete, "Map")
		CollectionService:AddTag(w, "BulletBlocker")
	end

	-- 8 invisible hard-cover blockers + vetted dressing (industrial city containers/barrels)
	local hardCoverDefs = {
		{ pos = MAP_OFFSET + Vector3.new(-50, 3.5, -40), size = Vector3.new(14, 7.0, 8), key = "SciFiContainer", offset = Vector3.new(0, 2, 0) },
		{ pos = MAP_OFFSET + Vector3.new(-62, 1.75, -30), size = Vector3.new(6, 3.5, 6), key = "WoodenBox02", offset = Vector3.new(0, 1, 0) },
		{ pos = MAP_OFFSET + Vector3.new(-38, 1.75, -50), size = Vector3.new(6, 3.5, 6), key = "LowPolyBarrel", offset = Vector3.new(0, 0, 0) },
		{ pos = MAP_OFFSET + Vector3.new(50, 3.5, 40), size = Vector3.new(14, 7.0, 8), key = "SciFiContainer", offset = Vector3.new(0, 2, 0) },
		{ pos = MAP_OFFSET + Vector3.new(62, 1.75, 30), size = Vector3.new(6, 3.5, 6), key = "WoodenBox02", offset = Vector3.new(0, 1, 0) },
		{ pos = MAP_OFFSET + Vector3.new(38, 1.75, 50), size = Vector3.new(6, 3.5, 6), key = "LowPolyBarrel", offset = Vector3.new(0, 0, 0) },
		{ pos = MAP_OFFSET + Vector3.new(-18, 3.5, 0), size = Vector3.new(8, 7.0, 8), key = "SciFiContainer", offset = Vector3.new(0, 2, 0) },
		{ pos = MAP_OFFSET + Vector3.new(18, 3.5, 0), size = Vector3.new(8, 7.0, 8), key = "WoodenBox02", offset = Vector3.new(0, 1, 0) },
	}
	for i, def in hardCoverDefs do
		local blocker = makeInvisibleBlocker("CoverBlocker_" .. i, def.size, CFrame.new(def.pos), gen)
		placeVisual(blocker, def.key, def.offset)
	end

	-- Decoration: city perimeter trees & rubble rocks (CanQuery=false, Decoration)
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "DecorationCluster"
	decoFolder.Parent = gen
	local treePositions = {
		MAP_OFFSET + Vector3.new(-95, 0, -100),
		MAP_OFFSET + Vector3.new(95, 0, -100),
		MAP_OFFSET + Vector3.new(-95, 0, 100),
		MAP_OFFSET + Vector3.new(95, 0, 100),
	}
	for i, pos in treePositions do
		local pad = Instance.new("Part")
		pad.Name = "TreePad_" .. i
		pad.Size = Vector3.new(2, 1, 2)
		pad.CFrame = CFrame.new(pos)
		pad.Anchored = true
		pad.Transparency = 1
		pad.CanCollide = false
		pad.CanQuery = false
		pad.CollisionGroup = "Decoration"
		pad.Parent = decoFolder
		local key = if i % 2 == 0 then "LowPolyTree" else "LowPolyTreePack"
		local vis = vettedClone(key)
		if vis then
			local cf = pad.CFrame + Vector3.new(0, 3, 0)
			if vis:IsA("Model") then
				pcall(function() (vis :: Model):PivotTo(cf) end)
				vis.Parent = decoFolder
			elseif vis:IsA("BasePart") then
				(vis :: BasePart).CFrame = cf
				vis.Parent = decoFolder
			else
				pcall(function() (vis :: any):PivotTo(cf) end)
				vis.Parent = decoFolder
			end
			applyVisual(vis, key)
		end
	end
	local rockPositions = {
		MAP_OFFSET + Vector3.new(-70, 0, -60),
		MAP_OFFSET + Vector3.new(70, 0, 60),
	}
	for i, pos in rockPositions do
		local pad = Instance.new("Part")
		pad.Name = "RockPad_" .. i
		pad.Size = Vector3.new(2, 1, 2)
		pad.CFrame = CFrame.new(pos)
		pad.Anchored = true
		pad.Transparency = 1
		pad.CanCollide = false
		pad.CanQuery = false
		pad.CollisionGroup = "Decoration"
		pad.Parent = decoFolder
		local vis = vettedClone("LowPolyRocks")
		if vis then
			local cf = pad.CFrame + Vector3.new(0, 1, 0)
			if vis:IsA("Model") then
				pcall(function() (vis :: Model):PivotTo(cf) end)
				vis.Parent = decoFolder
			elseif vis:IsA("BasePart") then
				(vis :: BasePart).CFrame = cf
				vis.Parent = decoFolder
			else
				pcall(function() (vis :: any):PivotTo(cf) end)
				vis.Parent = decoFolder
			end
			applyVisual(vis, "LowPolyRocks")
		end
	end

	-- Weapon & enemy dressing pads (demonstrate 443695083 and 7198227425 pipeline correctly parented, never as Tool)
	local weaponPad = Instance.new("Part")
	weaponPad.Name = "WeaponPad_Rifle"
	weaponPad.Size = Vector3.new(3, 1, 3)
	weaponPad.CFrame = CFrame.new(MAP_OFFSET + Vector3.new(-25, 0, -90))
	weaponPad.Anchored = true
	weaponPad.Transparency = 1
	weaponPad.CanCollide = false
	weaponPad.CanQuery = false
	weaponPad.CollisionGroup = "Decoration"
	weaponPad.Parent = gen
	local wVis = vettedClone("EnergyRifleVisual")
	if wVis then
		local cf = weaponPad.CFrame + Vector3.new(0, 2, 0)
		if wVis:IsA("Model") then
			pcall(function() (wVis :: Model):PivotTo(cf) end)
			wVis.Parent = gen
		elseif wVis:IsA("BasePart") then
			(wVis :: BasePart).CFrame = cf
			wVis.Parent = gen
		else
			pcall(function() (wVis :: any):PivotTo(cf) end)
			wVis.Parent = gen
		end
		applyVisual(wVis, "EnergyRifleVisual")
	end

	local botPad = Instance.new("Part")
	botPad.Name = "TargetPad_Bot"
	botPad.Size = Vector3.new(5, 1, 5)
	botPad.CFrame = CFrame.new(MAP_OFFSET + Vector3.new(0, 0, -80))
	botPad.Anchored = true
	botPad.Transparency = 1
	botPad.CanCollide = false
	botPad.CanQuery = false
	botPad.CollisionGroup = "Decoration"
	botPad.Parent = gen
	local botVis = vettedClone("TankBotVisual")
	if botVis then
		local cf = botPad.CFrame + Vector3.new(0, 3, 0)
		if botVis:IsA("Model") then
			pcall(function() (botVis :: Model):PivotTo(cf) end)
			botVis.Parent = gen
		elseif botVis:IsA("BasePart") then
			(botVis :: BasePart).CFrame = cf
			botVis.Parent = gen
		else
			pcall(function() (botVis :: any):PivotTo(cf) end)
			botVis.Parent = gen
		end
		applyVisual(botVis, "TankBotVisual")
	end

	-- VettedPropSlots — 8 slots covering all 8 IDs (city industrial showcase)
	local slots = Instance.new("Folder")
	slots.Name = "VettedPropSlots"
	slots.Parent = gen
	local slotDefs = {
		{ key = "LowPolyTree", pos = MAP_OFFSET + Vector3.new(-80, 0, -40) },
		{ key = "LowPolyTreePack", pos = MAP_OFFSET + Vector3.new(80, 0, 40) },
		{ key = "LowPolyRocks", pos = MAP_OFFSET + Vector3.new(-40, 0, -90) },
		{ key = "WoodenBox02", pos = MAP_OFFSET + Vector3.new(40, 0, -90) },
		{ key = "LowPolyBarrel", pos = MAP_OFFSET + Vector3.new(-40, 0, 90) },
		{ key = "SciFiContainer", pos = MAP_OFFSET + Vector3.new(40, 0, 90) },
		{ key = "EnergyRifleVisual", pos = MAP_OFFSET + Vector3.new(0, 0, -40) },
		{ key = "TankBotVisual", pos = MAP_OFFSET + Vector3.new(0, 0, 40) },
	}
	for i, def in slotDefs do
		local m = Instance.new("Part")
		m.Name = "AssetSlot_" .. i .. "_" .. def.key
		m.Size = Vector3.new(1, 1, 1)
		m.CFrame = CFrame.new(def.pos)
		m.Anchored = true
		m.Transparency = 1
		m.CanCollide = false
		m.CanTouch = false
		m.CanQuery = false
		m.CollisionGroup = "Decoration"
		m.Parent = slots
		local vis = vettedClone(def.key)
		if vis then
			local cf = m.CFrame + Vector3.new(0, 2, 0)
			if vis:IsA("Model") then
				pcall(function() (vis :: Model):PivotTo(cf) end)
				vis.Parent = slots
			elseif vis:IsA("BasePart") then
				(vis :: BasePart).CFrame = cf
				vis.Parent = slots
			else
				pcall(function() (vis :: any):PivotTo(cf) end)
				vis.Parent = slots
			end
			applyVisual(vis, def.key)
		end
	end

	-- Spawns
	local spawns = Instance.new("Folder")
	spawns.Name = "SpawnPoints"
	spawns.Parent = mapFolder
	local function addSpawn(name: string, pos: Vector3)
		local p = Instance.new("SpawnLocation")
		p.Name = name
		p.Size = Vector3.new(8, 1, 8)
		p.CFrame = CFrame.new(pos)
		p.Anchored = true
		p.Neutral = true
		p.AllowTeamChangeOnTouch = false
		p.CollisionGroup = "Triggers"
		p.Parent = spawns
		CollectionService:AddTag(p, "SpawnPoint")
	end
	addSpawn("City_Red_1", MAP_OFFSET + Vector3.new(-45, 2, 80))
	addSpawn("City_Red_2", MAP_OFFSET + Vector3.new(-25, 2, 80))
	addSpawn("City_Blue_1", MAP_OFFSET + Vector3.new(45, 2, -80))
	addSpawn("City_Blue_2", MAP_OFFSET + Vector3.new(25, 2, -80))

	print("[CityArenaMap] Built city warehouse vetted (8 blockers + 8 slots + trees/rocks/weapon/bot) — fallback-safe")
	return mapFolder
end

function CityArenaMap.DestroyMap()
	if _activeFolder and _activeFolder.Parent then
		_activeFolder:Destroy()
		_activeFolder = nil
	end
end

function CityArenaMap.GetSpawnPoints(team: string?): { Vector3 }
	if team == "Blue" then
		return { MAP_OFFSET + Vector3.new(45, 2, -80), MAP_OFFSET + Vector3.new(25, 2, -80) }
	elseif team == "Red" then
		return { MAP_OFFSET + Vector3.new(-45, 2, 80), MAP_OFFSET + Vector3.new(-25, 2, 80) }
	end
	return {
		MAP_OFFSET + Vector3.new(-45, 2, 80),
		MAP_OFFSET + Vector3.new(-25, 2, 80),
		MAP_OFFSET + Vector3.new(45, 2, -80),
		MAP_OFFSET + Vector3.new(25, 2, -80),
	}
end

function CityArenaMap.GetCoverPositions(): { Vector3 }
	return COVER_POSITIONS
end

function CityArenaMap.GetSitePositions(): { siteA: Vector3, siteB: Vector3 }?
	return {
		siteA = MAP_OFFSET + Vector3.new(-45, 1, -40),
		siteB = MAP_OFFSET + Vector3.new(45, 1, 40),
	}
end

function CityArenaMap.GetMapBounds(): (Vector3, Vector3)
	return MAP_OFFSET + Vector3.new(-120, 0, -130), MAP_OFFSET + Vector3.new(120, 36, 130)
end

function CityArenaMap.GetLayoutData()
	local red, blue = CityArenaMap.GetSpawnPoints("Red"), CityArenaMap.GetSpawnPoints("Blue")
	local min, max = CityArenaMap.GetMapBounds()
	return {
		mapId = "CityArena",
		mapName = "City Arena",
		theme = "City Industrial",
		bounds = { min = min, max = max },
		redSpawns = red,
		blueSpawns = blue,
		sites = CityArenaMap.GetSitePositions(),
		coverPositions = CityArenaMap.GetCoverPositions(),
		lanes = nil,
	}
end

return CityArenaMap
