--!strict
--[=[
    Unit Tests for LobbyFolder
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LobbyFolder = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("LobbyFolder") :: any)

local function runTests()
	-- 1. Test Lobby Building
	local folder = LobbyFolder.BuildLobby(Workspace)
	assert(folder ~= nil, "BuildLobby must return folder instance")
	assert(folder.Name == "LobbyFolder", "Lobby folder name mismatch")
	assert(folder.Parent == Workspace, "Lobby folder parent mismatch")

	-- 2. Test Structure Hierarchy
	local boundsFolder = folder:FindFirstChild("LobbyBounds")
	assert(boundsFolder ~= nil, "LobbyBounds folder missing")
	assert(boundsFolder:FindFirstChild("BoundingBox") ~= nil, "BoundingBox missing")

	local spawnsFolder = folder:FindFirstChild("SpawnLocations")
	assert(spawnsFolder ~= nil, "SpawnLocations folder missing")

	local triggersFolder = folder:FindFirstChild("InteractiveTriggers")
	assert(triggersFolder ~= nil, "InteractiveTriggers folder missing")
	assert(triggersFolder:FindFirstChild("PlayTriggerPart") ~= nil, "PlayTriggerPart missing")
	assert(triggersFolder:FindFirstChild("ChallengeTriggerPart") ~= nil, "ChallengeTriggerPart missing")
	assert(triggersFolder:FindFirstChild("LoadoutTriggerPart") ~= nil, "LoadoutTriggerPart missing")
	assert(triggersFolder:FindFirstChild("SettingsTriggerPart") ~= nil, "SettingsTriggerPart missing")

	local geometryFolder = folder:FindFirstChild("Geometry")
	assert(geometryFolder ~= nil, "Geometry folder missing")
	assert(geometryFolder:FindFirstChild("LobbyFloor") ~= nil, "LobbyFloor missing")

	-- 3. Test Getter API
	local spawns = LobbyFolder.GetSpawnLocations()
	assert(#spawns == 6, "Expected 6 spawn locations")

	local triggers = LobbyFolder.GetInteractiveTriggers()
	assert(triggers["Play"] ~= nil, "Play trigger missing in getter map")
	assert(triggers["Challenge"] ~= nil, "Challenge trigger missing in getter map")
	assert(triggers["Loadout"] ~= nil, "Loadout trigger missing in getter map")
	assert(triggers["Settings"] ~= nil, "Settings trigger missing in getter map")

	local minB, maxB = LobbyFolder.GetLobbyBounds()
	assert(maxB.X - minB.X == 120, "Lobby width X should be 120")
	assert(maxB.Z - minB.Z == 120, "Lobby length Z should be 120")

	local layoutData = LobbyFolder.GetLayoutData()
	assert(layoutData.lobbyName == "MainLobby_Paradigm", "Lobby name mismatch")
	assert(#layoutData.spawnPositions == 6, "Layout data spawn count mismatch")

	-- 4. Test Lobby Destruction
	LobbyFolder.DestroyLobby()
	assert(folder.Parent == nil, "Lobby folder should be destroyed")

	print("[LobbyFolder.spec] All tests passed!")
end

runTests()
return true
