--!strict
--[=[
    Project OVERCLOCK: MapRegistry
    Central registry interface managing map module registration, metadata retrieval,
    dynamic map instance loading (LoadMapInstance), and unloading (UnloadMapInstance).
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
	mapId: string?,
	mapName: string,
	theme: string?,
	bounds: MapBounds,
	redSpawns: { Vector3 },
	blueSpawns: { Vector3 },
	sites: SitePositions?,
	coverPositions: { Vector3 },
	lanes: { [string]: LaneData }?,
}

export type MapModule = {
	BuildMap: (parent: Instance?) -> Folder,
	DestroyMap: () -> (),
	GetSpawnPoints: (teamName: string) -> { Vector3 },
	GetCoverPositions: () -> { Vector3 },
	GetSitePositions: () -> SitePositions?,
	GetMapBounds: () -> (Vector3, Vector3),
	GetLayoutData: () -> MapLayoutData,
}

export type MapMetadata = {
	mapId: string,
	mapName: string,
	theme: string,
	bounds: MapBounds,
	spawnCountRed: number,
	spawnCountBlue: number,
	siteA: Vector3,
	siteB: Vector3,
}

local MapRegistry = {}

local _registeredMaps: { [string]: MapModule } = {}
local _activeMapId: string? = nil
local _activeMapFolder: Folder? = nil

--[=[
    Registers a map module under a unique map ID.
]=]
function MapRegistry.RegisterMap(mapId: string, mapModule: MapModule): boolean
	if type(mapId) ~= "string" or mapId == "" then
		warn("[MapRegistry] Invalid mapId provided for registration.")
		return false
	end

	if type(mapModule) ~= "table" then
		warn("[MapRegistry] Invalid mapModule provided for mapId: " .. mapId)
		return false
	end

	_registeredMaps[mapId] = mapModule
	return true
end

--[=[
    Unregisters a map module by map ID.
]=]
function MapRegistry.UnregisterMap(mapId: string): boolean
	if _registeredMaps[mapId] ~= nil then
		if _activeMapId == mapId then
			MapRegistry.UnloadMapInstance()
		end
		_registeredMaps[mapId] = nil
		return true
	end
	return false
end

--[=[
    Checks if a map ID is registered.
]=]
function MapRegistry.IsMapRegistered(mapId: string): boolean
	return _registeredMaps[mapId] ~= nil
end

--[=[
    Returns a list of all registered map IDs.
]=]
function MapRegistry.GetRegisteredMapNames(): { string }
	local names: { string } = {}
	for mapId in _registeredMaps do
		table.insert(names, mapId)
	end
	table.sort(names)
	return names
end

--[=[
    Retrieves metadata for a specific registered map.
]=]
function MapRegistry.GetMapMetadata(mapId: string): MapMetadata?
	local module = _registeredMaps[mapId]
	if not module then
		return nil
	end

	local layout = module.GetLayoutData()
	local sites = layout.sites
	return {
		mapId = layout.mapId or mapId,
		mapName = layout.mapName or mapId,
		theme = layout.theme or "Tactical Greybox",
		bounds = layout.bounds,
		spawnCountRed = layout.redSpawns and #layout.redSpawns or 0,
		spawnCountBlue = layout.blueSpawns and #layout.blueSpawns or 0,
		siteA = sites and sites.siteA or Vector3.zero,
		siteB = sites and sites.siteB or Vector3.zero,
	}
end

--[=[
    Retrieves a list of metadata for all registered maps.
]=]
function MapRegistry.GetAllMapMetadata(): { MapMetadata }
	local list: { MapMetadata } = {}
	for mapId in _registeredMaps do
		local meta = MapRegistry.GetMapMetadata(mapId)
		if meta then
			table.insert(list, meta)
		end
	end
	table.sort(list, function(a: MapMetadata, b: MapMetadata)
		return a.mapId < b.mapId
	end)
	return list
end

--[=[
    Loads a dynamic instance of a registered map into Workspace or specified parent.
    Unloads any currently active map prior to loading the new map.
]=]
function MapRegistry.LoadMapInstance(mapId: string, parent: Instance?): Folder?
	local module = _registeredMaps[mapId]
	if not module then
		warn("[MapRegistry] Failed to load map instance: Map ID '" .. tostring(mapId) .. "' is not registered.")
		return nil
	end

	if _activeMapId ~= nil then
		MapRegistry.UnloadMapInstance()
	end

	local targetParent = parent or Workspace
	local folder = module.BuildMap(targetParent)
	_activeMapId = mapId
	_activeMapFolder = folder

	return folder
end

--[=[
    Unloads and destroys the currently active map instance.
]=]
function MapRegistry.UnloadMapInstance()
	if _activeMapId ~= nil then
		local module = _registeredMaps[_activeMapId]
		if module then
			module.DestroyMap()
		end
		_activeMapId = nil
		_activeMapFolder = nil
	elseif _activeMapFolder ~= nil then
		_activeMapFolder:Destroy()
		_activeMapFolder = nil
	end
end

--[=[
    Gets the map ID of the currently active map instance.
]=]
function MapRegistry.GetActiveMapId(): string?
	return _activeMapId
end

--[=[
    Gets the Folder instance of the currently active map instance.
]=]
function MapRegistry.GetActiveMapFolder(): Folder?
	return _activeMapFolder
end

--[=[
    Gets the MapLayoutData of the currently active map instance.
]=]
function MapRegistry.GetActiveMapLayoutData(): MapLayoutData?
	if _activeMapId == nil then
		return nil
	end
	local module = _registeredMaps[_activeMapId]
	if not module then
		return nil
	end
	return module.GetLayoutData()
end

--[=[
    Attempts to lazy-load and auto-register standard project map modules if available.
]=]
function MapRegistry.AutoRegisterDefaultMaps()
	local mapFolder = script.Parent
	if not mapFolder then
		return
	end

	local defaultMapNames = {
		"ForestOutpostMap",
		"UrbanWarehouseMap",
		"DesertRuinsMap",
		"CyberArenaMap",
		"ClassicGreyboxMap",
		"GreyboxArenaMap",
		"NeonSubwayMap",
		"DuelArenaMap",
		"PracticeRangeMapLayout",
		"PracticeRangeMap",
		"CommunityArenaMap",
		"CityArenaMap",
	}

	for _, name in defaultMapNames do
		local child = mapFolder:FindFirstChild(name)
		if child and child:IsA("ModuleScript") then
			local success, result = pcall(function()
				return require(child) :: any
			end)
			if success and type(result) == "table" and type(result.BuildMap) == "function" then
				local cleanId = name
				if name == "DuelArenaMap" then
					cleanId = "DuelArena"
				elseif name == "PracticeRangeMapLayout" or name == "PracticeRangeMap" then
					cleanId = "PracticeRangeMap"
				else
					cleanId = name:gsub("Map$", "")
				end
				MapRegistry.RegisterMap(cleanId, result :: MapModule)
			end
		end
	end
end

-- Execute auto-registration upon module require
MapRegistry.AutoRegisterDefaultMaps()

return MapRegistry
