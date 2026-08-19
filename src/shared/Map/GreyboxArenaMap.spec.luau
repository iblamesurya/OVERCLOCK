--!strict
--[=[
    Unit Tests for GreyboxArenaMap
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GreyboxArenaMap = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("GreyboxArenaMap"))

local function runTests()
	-- 1. Test Map Building
	local mapFolder = GreyboxArenaMap.BuildMap(Workspace)
	assert(mapFolder ~= nil, "BuildMap must return folder instance")
	assert(mapFolder.Name == "GreyboxArenaMap", "Map folder name mismatch")
	assert(mapFolder.Parent == Workspace, "Map folder parent mismatch")

	-- 2. Test Structure Hierarchy
	local spawns = mapFolder:FindFirstChild("Spawns")
	assert(spawns ~= nil, "Spawns folder missing")

	local redSpawn = spawns and spawns:FindFirstChild("RedSpawn")
	assert(redSpawn ~= nil, "RedSpawn folder missing")

	local blueSpawn = spawns and spawns:FindFirstChild("BlueSpawn")
	assert(blueSpawn ~= nil, "BlueSpawn folder missing")

	local sites = mapFolder:FindFirstChild("Sites")
	assert(sites ~= nil, "Sites folder missing")
	assert(sites and sites:FindFirstChild("SiteA") ~= nil, "SiteA missing")
	assert(sites and sites:FindFirstChild("SiteB") ~= nil, "SiteB missing")

	-- 3. Test Spawn & Cover API
	local redSpawnPoints = GreyboxArenaMap.GetSpawnPoints("Red")
	assert(#redSpawnPoints == 5, "Red team spawn points count should be 5")

	local blueSpawnPoints = GreyboxArenaMap.GetSpawnPoints("Blue")
	assert(#blueSpawnPoints == 5, "Blue team spawn points count should be 5")

	local coverPositions = GreyboxArenaMap.GetCoverPositions()
	assert(#coverPositions >= 10, "Expected at least 10 cover positions")

	-- 4. Test Layout Data & Bounds
	local layoutData = GreyboxArenaMap.GetLayoutData()
	assert(layoutData.mapName == "Greybox_Arena_5v5", "Map name mismatch")
	assert(layoutData.bounds.min.X == -80, "Min bound X mismatch")
	assert(layoutData.bounds.max.X == 80, "Max bound X mismatch")

	-- 5. Test Map Destruction
	GreyboxArenaMap.DestroyMap()
	assert(mapFolder.Parent == nil, "Map folder should be destroyed")

	print("[GreyboxArenaMap.spec] All tests passed!")
end

runTests()
return true
