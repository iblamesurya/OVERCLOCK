--!strict
--[=[
    Unit Tests for MapRegistry & Milestone 5 Maps (DuelArena & PracticeRangeMap)
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapRegistry = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("MapRegistry"))

local function runTests()
	print("[MapRegistry.spec] Starting MapRegistry verification tests...")

	-- 1. Test Default Auto-Registered Maps
	local registeredNames = MapRegistry.GetRegisteredMapNames()
	assert(#registeredNames >= 5, "Expected at least 5 registered map names")
	print("[MapRegistry.spec] Registered maps count: " .. tostring(#registeredNames))

	-- Verify OVERCLOCK M5 Map Registrations
	assert(MapRegistry.IsMapRegistered("DuelArena"), "DuelArena should be registered in MapRegistry")
	assert(MapRegistry.IsMapRegistered("PracticeRangeMap"), "PracticeRangeMap should be registered in MapRegistry")

	-- 2. Test Legacy Maps Metadata & Loading
	local legacyMapsToTest = {
		"ForestOutpost",
		"UrbanWarehouse",
		"DesertRuins",
		"CyberArena",
		"ClassicGreybox",
	}

	for _, mapId in legacyMapsToTest do
		if MapRegistry.IsMapRegistered(mapId) then
			local meta = MapRegistry.GetMapMetadata(mapId)
			assert(meta ~= nil, "Metadata for " .. mapId .. " must not be nil")
			assert(meta.mapId == mapId, "Metadata mapId mismatch for " .. mapId)

			local folder = MapRegistry.LoadMapInstance(mapId, Workspace)
			assert(folder ~= nil, "LoadMapInstance must return Folder for " .. mapId)
			assert(MapRegistry.GetActiveMapId() == mapId, "Active map ID mismatch for " .. mapId)

			MapRegistry.UnloadMapInstance()
			assert(MapRegistry.GetActiveMapId() == nil, "Active map ID should be nil after unload")
		end
	end

	-- 3. Test DuelArena Map Loading & Metadata
	do
		local mapId = "DuelArena"
		local meta = MapRegistry.GetMapMetadata(mapId)
		assert(meta ~= nil, "Metadata for DuelArena must not be nil")
		assert(meta.mapId == "DuelArena", "Metadata mapId mismatch for DuelArena")
		assert(meta.spawnCountRed >= 4, "Expected at least 4 Red/Team1 spawns for DuelArena")
		assert(meta.spawnCountBlue >= 4, "Expected at least 4 Blue/Team2 spawns for DuelArena")

		local folder = MapRegistry.LoadMapInstance(mapId, Workspace)
		assert(folder ~= nil, "LoadMapInstance must return Folder for DuelArena")
		assert(folder.Name == "DuelArenaMap", "DuelArena map folder name mismatch")
		assert(MapRegistry.GetActiveMapId() == mapId, "Active map ID mismatch for DuelArena")

		local spawns = folder:FindFirstChild("Spawns")
		assert(spawns ~= nil, "Spawns folder missing in DuelArenaMap")
		assert(spawns:FindFirstChild("Team1Spawn") ~= nil, "Team1Spawn folder missing in DuelArenaMap")
		assert(spawns:FindFirstChild("Team2Spawn") ~= nil, "Team2Spawn folder missing in DuelArenaMap")

		MapRegistry.UnloadMapInstance()
		assert(MapRegistry.GetActiveMapId() == nil, "Active map ID should be nil after unload")
	end

	-- 4. Test PracticeRangeMap Loading & Optional Sites Metadata Guard
	do
		local mapId = "PracticeRangeMap"
		local meta = MapRegistry.GetMapMetadata(mapId)
		assert(meta ~= nil, "Metadata for PracticeRangeMap must not be nil")
		assert(meta.mapId == "PracticeRangeMap", "Metadata mapId mismatch for PracticeRangeMap")
		assert(meta.siteA == Vector3.zero or meta.siteA == Vector3.new(500, 100, 0), "PracticeRangeMap siteA should default to Vector3.zero or MAP_OFFSET")
		assert(meta.siteB == Vector3.zero or meta.siteB == Vector3.new(500, 100, 0), "PracticeRangeMap siteB should default to Vector3.zero or MAP_OFFSET")

		local folder = MapRegistry.LoadMapInstance(mapId, Workspace)
		assert(folder ~= nil, "LoadMapInstance must return Folder for PracticeRangeMap")
		assert(folder.Name == "PracticeRangeMap", "PracticeRangeMap folder name mismatch")
		assert(MapRegistry.GetActiveMapId() == mapId, "Active map ID mismatch for PracticeRangeMap")

		local targetWall = folder:FindFirstChild("TargetWallSection")
		assert(targetWall ~= nil, "TargetWallSection folder missing in PracticeRangeMap")

		local patrolBot = folder:FindFirstChild("PatrolBotSection")
		assert(patrolBot ~= nil, "PatrolBotSection folder missing in PracticeRangeMap")

		MapRegistry.UnloadMapInstance()
		assert(MapRegistry.GetActiveMapId() == nil, "Active map ID should be nil after unload")
	end

	print("[MapRegistry.spec] All MapRegistry verification tests passed successfully!")
end

runTests()
return true
