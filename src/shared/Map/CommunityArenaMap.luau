--!strict
--[=[
	Project OVERCLOCK: CommunityArenaMap — Good Visuals + Good Gameplay
	Uses the 8 verified Creator Store candidates as *visual dressing only*.
	Gameplay collision is ALWAYS the primitive BulletBlocker (MapSafety §6.4).
	If VettedProps are not yet staged, map is still fully playable with primitives.
	Pipeline: Workspace.ScratchAssetAudit -> AuditAsset.luau -> ServerStorage.Templates.VettedProps -> VettedPropSlots
	Hard-cover pairing: mesh CanQuery=false/Decoration + invisible BulletBlocker (Map, CanQuery=true)
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

local MAP_FOLDER_NAME = "CommunityArenaMap"
local MAP_OFFSET = Vector3.new(1500, 100, 0)

local CommunityArenaMap = {}
local _activeFolder: Folder? = nil

local function vettedClone(assetKey: string): Instance?
	if VettedPropHelper and VettedPropHelper.CloneVetted then
		return VettedPropHelper.CloneVetted(assetKey)
	end
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local vp = templates:FindFirstChild("VettedProps")
	if not vp then return nil end
	local mdl = vp:FindFirstChild(assetKey)
	if mdl then return mdl:Clone() end
	if AssetRegistry then
		local reg = AssetRegistry[assetKey]
		if reg then
			local byId = vp:FindFirstChild(tostring(reg.id))
			if byId then return byId:Clone() end
			for _, child in vp:GetChildren() do
				if child:GetAttribute("SourceAssetId") == reg.id then return child:Clone() end
			end
		end
	end
	return nil
end

local function applyVisualProps(inst: Instance, assetKey: string)
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
			if assetKey == "WoodenBox02" or assetKey == "LowPolyBarrel" or assetKey == "SciFiContainer" then
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
	end
	CollectionService:AddTag(inst, "VettedAsset")
	CollectionService:AddTag(inst, "MapProp")
end

local function makeBlocker(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
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
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1
	p.Color = Color3.fromRGB(90, 90, 90)
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
		applyVisualProps(vis, assetKey)
	elseif vis:IsA("BasePart") then
		(vis :: BasePart).CFrame = cf
		vis.Parent = blocker.Parent
		applyVisualProps(vis, assetKey)
	else
		vis.Parent = blocker.Parent
		pcall(function() (vis :: any):PivotTo(cf) end)
		applyVisualProps(vis, assetKey)
	end
	return vis
end

function CommunityArenaMap.BuildMap(parent: Instance?): Folder
	local targetParent = parent or Workspace
	local existing = targetParent:FindFirstChild(MAP_FOLDER_NAME)
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = MAP_FOLDER_NAME
	folder.Parent = targetParent
	_activeFolder = folder

	local gen = Instance.new("Folder")
	gen.Name = "GeneratedCommunity"
	gen.Parent = folder

	-- Floor — flat tactical, no gradient, matte concrete
	local floor = Instance.new("Part")
	floor.Name = "ArenaFloor"
	floor.Size = Vector3.new(240, 4, 180)
	floor.CFrame = CFrame.new(MAP_OFFSET + Vector3.new(0, -2, 0))
	floor.Anchored = true
	floor.Material = Enum.Material.Concrete
	floor.Color = Color3.fromRGB(32, 33, 35)
	floor.CollisionGroup = "Map"
	floor.Parent = gen
	CollectionService:AddTag(floor, "MapProp")

	-- Perimeter walls — flat, no aurora, no glass (BulletBlocker primitives)
	for _, cf in {
		CFrame.new(MAP_OFFSET + Vector3.new(0, 12, -90)),
		CFrame.new(MAP_OFFSET + Vector3.new(0, 12, 90)),
		CFrame.new(MAP_OFFSET + Vector3.new(-120, 12, 0)) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(MAP_OFFSET + Vector3.new(120, 12, 0)) * CFrame.Angles(0, math.rad(90), 0),
	} do
		local w = Instance.new("Part")
		w.Name = "Boundary"
		w.Size = Vector3.new(240, 28, 4)
		w.CFrame = cf
		w.Anchored = true
		w.Color = Color3.fromRGB(36, 37, 40)
		w.Material = Enum.Material.Concrete
		w.CollisionGroup = "Map"
		w.CanQuery = true
		w.Parent = gen
		CollectionService:AddTag(w, "BulletBlocker")
	end

	-- Hard cover blockers (gameplay) + community visuals (dressing)
	-- Uses all 3 HardCover vetted assets: WoodenBox02, SciFiContainer, LowPolyBarrel
	local hardCoverDefs = {
		{ pos = MAP_OFFSET + Vector3.new(-50, 3.5, -30), size = Vector3.new(14, 10, 6), vis = "WoodenBox02", offset = Vector3.new(0, 0, 0) },
		{ pos = MAP_OFFSET + Vector3.new(50, 3.5, -30), size = Vector3.new(14, 10, 6), vis = "SciFiContainer", offset = Vector3.new(0, 2, 0) },
		{ pos = MAP_OFFSET + Vector3.new(-50, 3.5, 30), size = Vector3.new(14, 10, 6), vis = "WoodenBox02", offset = Vector3.new(0, 0, 0) },
		{ pos = MAP_OFFSET + Vector3.new(50, 3.5, 30), size = Vector3.new(14, 10, 6), vis = "LowPolyBarrel", offset = Vector3.new(0, 0, 0) },
		{ pos = MAP_OFFSET + Vector3.new(0, 3.5, -45), size = Vector3.new(16, 10, 6), vis = "SciFiContainer", offset = Vector3.new(0, 2, 0) },
		{ pos = MAP_OFFSET + Vector3.new(0, 3.5, 45), size = Vector3.new(16, 10, 6), vis = "WoodenBox02", offset = Vector3.new(0, 0, 0) },
	}
	for i, def in hardCoverDefs do
		local blocker = makeBlocker("CoverBlocker_" .. i, def.size, CFrame.new(def.pos), gen)
		placeVisual(blocker, def.vis, def.offset)
	end

	-- Decoration clusters (no collision) — trees & rocks (pure dressing, CanQuery=false)
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "DecorationCluster"
	decoFolder.Parent = gen
	local treePositions = {
		MAP_OFFSET + Vector3.new(-90, 0, -70),
		MAP_OFFSET + Vector3.new(90, 0, -70),
		MAP_OFFSET + Vector3.new(-90, 0, 70),
		MAP_OFFSET + Vector3.new(90, 0, 70),
		MAP_OFFSET + Vector3.new(-70, 0, 0),
		MAP_OFFSET + Vector3.new(70, 0, 0),
	}
	for i, pos in treePositions do
		local pad = Instance.new("Part")
		pad.Name = "TreePad_" .. i
		pad.Size = Vector3.new(4, 1, 4)
		pad.CFrame = CFrame.new(pos)
		pad.Anchored = true
		pad.Transparency = 1
		pad.CanCollide = false
		pad.CanQuery = false
		pad.CanTouch = false
		pad.CollisionGroup = "Decoration"
		pad.Parent = decoFolder
		local key = if i % 2 == 0 then "LowPolyTree" else "LowPolyTreePack"
		-- Use VettedPropHelper placement for decoration (no blocker needed)
		local vis = vettedClone(key)
		if vis then
			local cf = pad.CFrame + Vector3.new(0, 2, 0)
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
			applyVisualProps(vis, key)
		end
	end
	local rockPositions = {
		MAP_OFFSET + Vector3.new(-60, 0, -60),
		MAP_OFFSET + Vector3.new(60, 0, 60),
		MAP_OFFSET + Vector3.new(-60, 0, 60),
		MAP_OFFSET + Vector3.new(60, 0, -60),
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
		pad.CanTouch = false
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
			applyVisualProps(vis, "LowPolyRocks")
		end
	end

	-- Weapon visual demo (EnergyRifleVisual) — shell only, parented inside locally-authored Tool context when equipped,
	-- here dressing on a pad to show vetted pipeline without giving gameplay advantage
	local weaponPad = Instance.new("Part")
	weaponPad.Name = "WeaponPad_Rifle"
	weaponPad.Size = Vector3.new(4, 1, 4)
	weaponPad.CFrame = CFrame.new(MAP_OFFSET + Vector3.new(-20, 0, -60))
	weaponPad.Anchored = true
	weaponPad.Transparency = 1
	weaponPad.CanCollide = false
	weaponPad.CanQuery = false
	weaponPad.CollisionGroup = "Decoration"
	weaponPad.Parent = gen
	local weaponVis = vettedClone("EnergyRifleVisual")
	if weaponVis then
		local cf = weaponPad.CFrame + Vector3.new(0, 2, 0)
		if weaponVis:IsA("Model") then
			pcall(function() (weaponVis :: Model):PivotTo(cf) end)
			weaponVis.Parent = gen
		elseif weaponVis:IsA("BasePart") then
			(weaponVis :: BasePart).CFrame = cf
			weaponVis.Parent = gen
		else
			pcall(function() (weaponVis :: any):PivotTo(cf) end)
			weaponVis.Parent = gen
		end
		applyVisualProps(weaponVis, "EnergyRifleVisual")
	else
		-- Keep pad as marker for zero-art fallback
	end

	-- Enemy visual demo target (non-functional, dressing only)
	local targetPad = Instance.new("Part")
	targetPad.Name = "TargetPad_Bot"
	targetPad.Size = Vector3.new(6, 1, 6)
	targetPad.CFrame = CFrame.new(MAP_OFFSET + Vector3.new(0, 0, -70))
	targetPad.Anchored = true
	targetPad.Transparency = 1
	targetPad.CanCollide = false
	targetPad.CanQuery = false
	targetPad.CanTouch = false
	targetPad.CollisionGroup = "Decoration"
	targetPad.Parent = gen
	placeVisual(targetPad, "TankBotVisual", Vector3.new(0, 3, 0))

	-- Spawn points
	local spawns = Instance.new("Folder")
	spawns.Name = "SpawnPoints"
	spawns.Parent = folder
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
	addSpawn("Community_Red_1", MAP_OFFSET + Vector3.new(-50, 2, 60))
	addSpawn("Community_Red_2", MAP_OFFSET + Vector3.new(-30, 2, 60))
	addSpawn("Community_Blue_1", MAP_OFFSET + Vector3.new(50, 2, -60))
	addSpawn("Community_Blue_2", MAP_OFFSET + Vector3.new(30, 2, -60))

	-- VettedPropSlots — 8 slots covering all 8 vetted assets (handoff pattern)
	-- Each slot is a transparent marker (Decoration, CanQuery=false) that optionally parents a vetted clone
	local slots = Instance.new("Folder")
	slots.Name = "VettedPropSlots"
	slots.Parent = gen
	local slotDefs = {
		{ key = "LowPolyTree", pos = MAP_OFFSET + Vector3.new(-45, 0, -30) },
		{ key = "LowPolyTreePack", pos = MAP_OFFSET + Vector3.new(45, 0, -30) },
		{ key = "LowPolyRocks", pos = MAP_OFFSET + Vector3.new(0, 0, 45) },
		{ key = "WoodenBox02", pos = MAP_OFFSET + Vector3.new(-45, 0, 30) },
		{ key = "LowPolyBarrel", pos = MAP_OFFSET + Vector3.new(45, 0, 30) },
		{ key = "SciFiContainer", pos = MAP_OFFSET + Vector3.new(0, 0, -45) },
		{ key = "EnergyRifleVisual", pos = MAP_OFFSET + Vector3.new(-25, 0, -45) },
		{ key = "TankBotVisual", pos = MAP_OFFSET + Vector3.new(25, 0, 45) },
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
			applyVisualProps(vis, def.key)
		end
	end

	print("[CommunityArenaMap] Built with 8 vetted slots (Tree/TreePack/Rocks/Box/Barrel/Container/Rifle/TankBot) + hard-cover blockers + zero-art fallback")
	return folder
end

function CommunityArenaMap.DestroyMap()
	if _activeFolder and _activeFolder.Parent then
		_activeFolder:Destroy()
		_activeFolder = nil
	end
end

function CommunityArenaMap.GetSpawnPoints(team: string?): { Vector3 }
	if team == "Blue" then
		return { MAP_OFFSET + Vector3.new(50, 2, -60), MAP_OFFSET + Vector3.new(30, 2, -60) }
	elseif team == "Red" then
		return { MAP_OFFSET + Vector3.new(-50, 2, 60), MAP_OFFSET + Vector3.new(-30, 2, 60) }
	end
	return {
		MAP_OFFSET + Vector3.new(-50, 2, 60),
		MAP_OFFSET + Vector3.new(-30, 2, 60),
		MAP_OFFSET + Vector3.new(50, 2, -60),
		MAP_OFFSET + Vector3.new(30, 2, -60),
	}
end

function CommunityArenaMap.GetCoverPositions(): { Vector3 }
	return {
		MAP_OFFSET + Vector3.new(-50, 3.5, -30),
		MAP_OFFSET + Vector3.new(50, 3.5, -30),
		MAP_OFFSET + Vector3.new(-50, 3.5, 30),
		MAP_OFFSET + Vector3.new(50, 3.5, 30),
		MAP_OFFSET + Vector3.new(0, 3.5, -45),
		MAP_OFFSET + Vector3.new(0, 3.5, 45),
	}
end

function CommunityArenaMap.GetSitePositions(): { siteA: Vector3, siteB: Vector3 }?
	return {
		siteA = MAP_OFFSET + Vector3.new(-40, 0, 0),
		siteB = MAP_OFFSET + Vector3.new(40, 0, 0),
	}
end

function CommunityArenaMap.GetMapBounds(): (Vector3, Vector3)
	return MAP_OFFSET + Vector3.new(-120, 0, -90), MAP_OFFSET + Vector3.new(120, 40, 90)
end

function CommunityArenaMap.GetLayoutData()
	local red, blue = CommunityArenaMap.GetSpawnPoints("Red"), CommunityArenaMap.GetSpawnPoints("Blue")
	local min, max = CommunityArenaMap.GetMapBounds()
	return {
		mapId = "CommunityArena",
		mapName = "Community Arena",
		theme = "Industrial Dressed",
		bounds = { min = min, max = max },
		redSpawns = red,
		blueSpawns = blue,
		sites = CommunityArenaMap.GetSitePositions(),
		coverPositions = CommunityArenaMap.GetCoverPositions(),
		lanes = nil,
	}
end

return CommunityArenaMap
