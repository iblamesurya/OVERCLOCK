--!strict
--[=[
    Unit Tests for PracticeRangeMapLayout
    Verifies singleplayer Practice Range sandbox map layout generation, hierarchy,
    target wall section (Target_Stationary_1..6), bot waypoints (Waypoints_Bot_1..8),
    distance markers, part property invariants (Anchored = true), and clean teardown.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PracticeRangeMapLayout = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("PracticeRangeMapLayout"))

local function runTests()
	print("[PracticeRangeMapLayout.spec] Starting PracticeRangeMapLayout unit tests...")

	-- 1. Test Map Building
	local mapFolder = PracticeRangeMapLayout.BuildMap(Workspace)
	assert(mapFolder ~= nil, "BuildMap must return a valid Folder instance")
	assert(mapFolder.Name == "PracticeRangeMap", "Map folder name must be 'PracticeRangeMap'")
	assert(mapFolder.Parent == Workspace, "Map folder must be parented to Workspace")

	-- 2. Test Hierarchy & Section Structures
	local perimeter = mapFolder:FindFirstChild("Perimeter")
	assert(perimeter ~= nil, "Perimeter folder missing")
	assert(perimeter:FindFirstChild("MainFloor") ~= nil, "MainFloor missing")

	local distanceMarkers = mapFolder:FindFirstChild("DistanceMarkers")
	assert(distanceMarkers ~= nil, "DistanceMarkers folder missing")
	assert(distanceMarkers:FindFirstChild("DistanceMarker_10m") ~= nil, "DistanceMarker_10m missing")
	assert(distanceMarkers:FindFirstChild("DistanceMarker_25m") ~= nil, "DistanceMarker_25m missing")
	assert(distanceMarkers:FindFirstChild("DistanceMarker_50m") ~= nil, "DistanceMarker_50m missing")

	local targetWallFolder = mapFolder:FindFirstChild("TargetWallSection")
	assert(targetWallFolder ~= nil, "TargetWallSection folder missing")
	assert(targetWallFolder:FindFirstChild("TargetWallBackboard") ~= nil, "TargetWallBackboard missing")

	for i = 1, 6 do
		local tName = "Target_Stationary_" .. i
		local targetPart = targetWallFolder:FindFirstChild(tName) :: BasePart?
		assert(targetPart ~= nil, tName .. " missing from TargetWallSection")
		assert(targetPart:GetAttribute("IsTarget") == true, tName .. " must have IsTarget = true")
		assert(targetPart:GetAttribute("TargetType") == "Stationary", tName .. " must have TargetType = 'Stationary'")
		assert(targetPart:GetAttribute("TargetId") == i, tName .. " TargetId attribute mismatch")

		local bullseye = targetPart:FindFirstChild("Bullseye") :: BasePart?
		assert(bullseye ~= nil, tName .. " must contain a Bullseye inner disc part")
		assert(bullseye:GetAttribute("IsBullseye") == true, "Bullseye must have IsBullseye = true")
		assert(bullseye.CanCollide == false, "Bullseye disc must have CanCollide = false")
	end

	local patrolBotFolder = mapFolder:FindFirstChild("PatrolBotSection")
	assert(patrolBotFolder ~= nil, "PatrolBotSection folder missing")
	local waypointsFolder = patrolBotFolder:FindFirstChild("Waypoints")
	assert(waypointsFolder ~= nil, "Waypoints folder missing")

	for i = 1, 8 do
		local wpName = "Waypoints_Bot_" .. i
		local wpPart = waypointsFolder:FindFirstChild(wpName) :: BasePart?
		assert(wpPart ~= nil, wpName .. " missing from Waypoints folder")
		assert(wpPart:GetAttribute("WaypointIndex") == i, wpName .. " WaypointIndex mismatch")
		assert(wpPart.CanCollide == false, wpName .. " must have CanCollide = false")
	end

	local spawnsFolder = mapFolder:FindFirstChild("Spawns")
	assert(spawnsFolder ~= nil, "Spawns folder missing")
	local playerSpawnFolder = spawnsFolder:FindFirstChild("PlayerSpawn")
	assert(playerSpawnFolder ~= nil, "PlayerSpawn folder missing")

	for i = 1, 3 do
		local sName = "Spawn_Player_" .. i
		local spPart = playerSpawnFolder:FindFirstChild(sName) :: BasePart?
		assert(spPart ~= nil, sName .. " missing from PlayerSpawn folder")
		assert(spPart.CanCollide == false, sName .. " must have CanCollide = false")
	end

	-- 3. Test API Helper Functions
	local stationaryTargets = PracticeRangeMapLayout.GetStationaryTargets()
	assert(#stationaryTargets == 6, "GetStationaryTargets must return 6 target parts, got " .. #stationaryTargets)

	local botWaypoints = PracticeRangeMapLayout.GetBotWaypoints()
	assert(#botWaypoints == 8, "GetBotWaypoints must return 8 waypoint positions, got " .. #botWaypoints)

	local playerSpawns = PracticeRangeMapLayout.GetSpawnPoints()
	assert(#playerSpawns == 3, "GetSpawnPoints must return 3 player spawn positions, got " .. #playerSpawns)

	local coverPositions = PracticeRangeMapLayout.GetCoverPositions()
	assert(#coverPositions >= 3, "GetCoverPositions must return at least 3 cover positions")

	-- 4. Test Part Property Invariants
	for _, desc in mapFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			assert(desc.Anchored == true, "Part '" .. desc.Name .. "' must be Anchored = true")
		end
	end

	-- 5. Test Layout Data & Bounds
	local layoutData = PracticeRangeMapLayout.GetLayoutData()
	assert(layoutData.mapId == "PracticeRangeMap", "Layout mapId mismatch")
	assert(layoutData.mapName == "PracticeRange_Sandbox", "Layout mapName mismatch")
	assert(layoutData.bounds.min.X == -70 or layoutData.bounds.min.X == 430, "Min bound X mismatch")
	assert(layoutData.bounds.max.X == 70 or layoutData.bounds.max.X == 570, "Max bound X mismatch")

	-- 6. Test Map Teardown
	PracticeRangeMapLayout.DestroyMap()
	assert(mapFolder.Parent == nil, "Map folder must be unparented after DestroyMap()")

	print("[PracticeRangeMapLayout.spec] All PracticeRangeMapLayout tests passed successfully!")
end

runTests()
return true
