--!strict
--[=[
    Unit Tests for DuelArenaMap
    Verifies 1v1 and 2v2 tactical greybox map generation, hierarchy, part property invariants (Anchored = true),
    team spawn resolution, cover points, layout metadata, and clean teardown.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DuelArenaMap = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("DuelArenaMap"))

local function runTests()
	print("[DuelArenaMap.spec] Starting DuelArenaMap unit tests...")

	-- 1. Test Map Building
	local mapFolder = DuelArenaMap.BuildMap(Workspace)
	assert(mapFolder ~= nil, "BuildMap must return a valid Folder instance")
	assert(mapFolder.Name == "DuelArenaMap", "Map folder name must be 'DuelArenaMap'")
	assert(mapFolder.Parent == Workspace, "Map folder must be parented to Workspace")

	-- 2. Test Structure Hierarchy
	local perimeter = mapFolder:FindFirstChild("Perimeter")
	assert(perimeter ~= nil, "Perimeter folder missing")
	assert(perimeter:FindFirstChild("MainFloor") ~= nil, "MainFloor part missing")
	assert(perimeter:FindFirstChild("NorthWall") ~= nil, "NorthWall part missing")
	assert(perimeter:FindFirstChild("SouthWall") ~= nil, "SouthWall part missing")

	local spawns = mapFolder:FindFirstChild("Spawns")
	assert(spawns ~= nil, "Spawns folder missing")

	local team1Folder = spawns:FindFirstChild("Team1Spawn")
	assert(team1Folder ~= nil, "Team1Spawn folder missing")
	assert(team1Folder:FindFirstChild("Spawn_Team1_1") ~= nil, "Spawn_Team1_1 missing")
	assert(team1Folder:FindFirstChild("Spawn_Team1_2") ~= nil, "Spawn_Team1_2 missing")
	assert(team1Folder:FindFirstChild("Spawn_Team1_3") ~= nil, "Spawn_Team1_3 missing")
	assert(team1Folder:FindFirstChild("Spawn_Team1_4") ~= nil, "Spawn_Team1_4 missing")

	local team2Folder = spawns:FindFirstChild("Team2Spawn")
	assert(team2Folder ~= nil, "Team2Spawn folder missing")
	assert(team2Folder:FindFirstChild("Spawn_Team2_1") ~= nil, "Spawn_Team2_1 missing")
	assert(team2Folder:FindFirstChild("Spawn_Team2_2") ~= nil, "Spawn_Team2_2 missing")
	assert(team2Folder:FindFirstChild("Spawn_Team2_3") ~= nil, "Spawn_Team2_3 missing")
	assert(team2Folder:FindFirstChild("Spawn_Team2_4") ~= nil, "Spawn_Team2_4 missing")

	local lanes = mapFolder:FindFirstChild("Lanes")
	assert(lanes ~= nil, "Lanes folder missing")
	assert(lanes:FindFirstChild("MainLane") ~= nil, "MainLane missing")

	local cover = mapFolder:FindFirstChild("Cover")
	assert(cover ~= nil, "Cover folder missing")
	assert(cover:FindFirstChild("Pillar_Center") ~= nil, "Pillar_Center missing")

	-- 3. Test Spawn & Cover API
	local team1Spawns = DuelArenaMap.GetSpawnPoints("Team1")
	assert(#team1Spawns == 4, "Expected 4 Team1 spawn points, got " .. #team1Spawns)

	local redSpawns = DuelArenaMap.GetSpawnPoints("Red")
	assert(#redSpawns == 4, "Expected 4 Red spawn points, got " .. #redSpawns)

	local team2Spawns = DuelArenaMap.GetSpawnPoints("Team2")
	assert(#team2Spawns == 4, "Expected 4 Team2 spawn points, got " .. #team2Spawns)

	local blueSpawns = DuelArenaMap.GetSpawnPoints("Blue")
	assert(#blueSpawns == 4, "Expected 4 Blue spawn points, got " .. #blueSpawns)

	local coverPositions = DuelArenaMap.GetCoverPositions()
	assert(#coverPositions >= 8, "Expected at least 8 cover positions, got " .. #coverPositions)

	-- 4. Test Part Properties Invariants
	for _, desc in mapFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			assert(desc.Anchored == true, "Part '" .. desc.Name .. "' must be Anchored = true")

			if desc.Name:sub(1, 11) == "Spawn_Team1" or desc.Name:sub(1, 11) == "Spawn_Team2" then
				assert(desc.CanCollide == false, "Spawn part '" .. desc.Name .. "' must have CanCollide = false")
			end
		end
	end

	-- 5. Test Layout Data & Bounds
	local layoutData = DuelArenaMap.GetLayoutData()
	assert(layoutData.mapId == "DuelArena", "Layout mapId mismatch")
	assert(layoutData.mapName == "DuelArena_1v1_2v2", "Layout mapName mismatch")
	assert(layoutData.bounds.min.X == -60 or layoutData.bounds.min.X == -560, "Min bound X mismatch")
	assert(layoutData.bounds.max.X == 60 or layoutData.bounds.max.X == -440, "Max bound X mismatch")
	assert(layoutData.bounds.min.Z == -80, "Min bound Z mismatch")
	assert(layoutData.bounds.max.Z == 80, "Max bound Z mismatch")

	-- 6. Test Map Teardown
	DuelArenaMap.DestroyMap()
	assert(mapFolder.Parent == nil, "Map folder must be unparented after DestroyMap()")

	print("[DuelArenaMap.spec] All DuelArenaMap tests passed successfully!")
end

runTests()
return true
