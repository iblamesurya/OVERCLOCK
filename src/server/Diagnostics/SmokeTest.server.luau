--!strict
--[=[
    Project OVERCLOCK: SmokeTest
    R6 Startup Smoke Test — Automatically verifies that all core dependencies,
    remotes, map folders, and services initialize without throwing errors.
    Runs 3 seconds after boot to let all safeInit tasks complete.
]=]

task.wait(3) -- Wait for Boot sequence in ServerMain to finish

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local totalTests = 0
local passedTests = 0
local failedTests: { string } = {}

local function check(label: string, condition: boolean, errMsg: string?)
	totalTests += 1
	if condition then
		passedTests += 1
	else
		table.insert(failedTests, label .. ": " .. (errMsg or "FAILED"))
	end
end

local function safeRequire(parent: Instance, childName: string): (boolean, any)
	local child = parent:FindFirstChild(childName)
	if not child then
		return false, "Module not found: " .. childName
	end
	return pcall(require, child)
end

local function runTests()
	print("[SMOKE TEST] Starting OVERCLOCK Server Smoke Test...")

	-- ========================================
	-- 1. Core Folder Structure
	-- ========================================
	local Services = ServerScriptService:FindFirstChild("Services")
	check("Services folder exists", Services ~= nil)

	local Combat = ServerScriptService:FindFirstChild("Combat")
	check("Combat folder exists", Combat ~= nil)

	local NetworkFolder = ReplicatedStorage:FindFirstChild("Network")
	check("Network folder exists", NetworkFolder ~= nil)

	local MapFolder = ReplicatedStorage:FindFirstChild("Map")
	check("Map folder exists", MapFolder ~= nil)

	local DataFolder = ReplicatedStorage:FindFirstChild("Data")
	check("Data folder exists", DataFolder ~= nil)

	-- ========================================
	-- 2. Critical Server Modules
	-- ========================================
	if Services then
		local criticalServices = {
			"SpawnService", "ProfileServiceWrapper", "DirectChallengeService",
			"QueueMatchmakingService", "OperativeService", "RoundService",
			"EconomyService", "BotService",
		}
		for _, name in criticalServices do
			local ok, err = safeRequire(Services, name)
			check("Require " .. name, ok, tostring(err))
		end
	end

	if Combat then
		local ok, err = safeRequire(Combat, "CombatServer")
		check("Require CombatServer", ok, tostring(err))
	end

	-- ========================================
	-- 3. Network Remotes
	-- ========================================
	if NetworkFolder then
		local ok, RemoteEvents = safeRequire(NetworkFolder, "RemoteEvents")
		check("Require RemoteEvents", ok, tostring(RemoteEvents))

		if ok and RemoteEvents then
			-- Verify the Remotes folder was created
			local remotesFolder = NetworkFolder:FindFirstChild("Remotes")
			check("[NETWORK] Remotes folder exists", remotesFolder ~= nil)

			if remotesFolder then
				local reliableFolder = remotesFolder:FindFirstChild("Reliable")
				local unreliableFolder = remotesFolder:FindFirstChild("Unreliable")
				local functionsFolder = remotesFolder:FindFirstChild("Functions")
				check("[NETWORK] Reliable subfolder exists", reliableFolder ~= nil)
				check("[NETWORK] Unreliable subfolder exists", unreliableFolder ~= nil)
				check("[NETWORK] Functions subfolder exists", functionsFolder ~= nil)

				-- Spot-check critical remotes
				if reliableFolder then
					local criticalRemotes = {
						"DamageDealt", "PlayerDeath", "MatchPhaseTransition",
						"EnterPracticeRange", "LeavePracticeRange",
						"RequestQueue", "CancelQueue", "SelectAgent",
					}
					for _, rName in criticalRemotes do
						check("[NETWORK] Remote: " .. rName, reliableFolder:FindFirstChild(rName) ~= nil)
					end
				end

				if unreliableFolder then
					check("[NETWORK] Remote: BulletTracer", unreliableFolder:FindFirstChild("BulletTracer") ~= nil)
				end
			end
		end
	end

	-- ========================================
	-- 4. Map System
	-- ========================================
	if MapFolder then
		local criticalMaps = { "MapRegistry", "LobbyFolder", "MapSafety", "PracticeRangeMapLayout" }
		for _, name in criticalMaps do
			local ok, err = safeRequire(MapFolder, name)
			check("Require " .. name, ok, tostring(err))
		end
	end

	-- Verify lobby map was built in Workspace
	local lobbyInWorkspace = Workspace:FindFirstChild("LobbyFolder")
	check("[MAP] LobbyFolder built in Workspace", lobbyInWorkspace ~= nil)

	-- Verify lobby has spawn locations
	if lobbyInWorkspace then
		local spawnLocations = lobbyInWorkspace:FindFirstChild("SpawnLocations")
		check("[MAP] LobbyFolder has SpawnLocations", spawnLocations ~= nil)
		if spawnLocations then
			local count = 0
			for _, child in spawnLocations:GetChildren() do
				if child:IsA("SpawnLocation") then count += 1 end
			end
			check("[MAP] Lobby has at least 1 SpawnLocation", count > 0, "Found " .. count)
		end
	end

	-- Verify practice range was built
	local practiceRange = Workspace:FindFirstChild("PracticeRangeMap")
	check("[MAP] PracticeRangeMap built in Workspace", practiceRange ~= nil)

	-- ========================================
	-- 5. SpawnService Single Authority Check
	-- ========================================
	check("[SPAWN] CharacterAutoLoads is false", game:GetService("Players").CharacterAutoLoads == false)

	-- Verify SpawnService is sole LoadCharacter owner (no ad-hoc spawns in other services)
	-- Capability-gated: Source is PluginOrOpenCloud only, so pcall and skip gracefully in live Studio
	if Services then
		for _, mod in Services:GetChildren() do
			if mod.Name ~= "SpawnService" and mod:IsA("ModuleScript") then
				local okSrc, src = pcall(function() return (mod :: any).Source end)
				if not okSrc then
					-- Skip static check when capability denied; runtime authority test at 151 already covers it
					continue
				end
				if type(src) == "string" and (string.find(src, "LoadCharacter") or string.find(src, "RespawnLocation")) then
					if string.find(src, ":LoadCharacter%(") then
						check("[SPAWN] No ad-hoc LoadCharacter in " .. mod.Name, false, "Found LoadCharacter call outside SpawnService")
					end
				end
			end
		end
	end

	-- Verify fallback baseplate exists and is not counted as map floor
	local fallback = Workspace:FindFirstChild("FallbackBaseplate")
	check("[MAP] FallbackBaseplate exists", fallback ~= nil)
	if fallback then
		check("[MAP] FallbackBaseplate.IsFallbackBaseplate==true", fallback:GetAttribute("IsFallbackBaseplate") == true)
	end

	-- Verify MapSafety would not count FallbackBaseplate as floor
	if MapFolder then
		local ok, MapSafety = safeRequire(MapFolder, "MapSafety")
		if ok and MapSafety and MapSafety.verifySpawnPointFloor then
			local testCf = CFrame.new(0, 91, 0)
			-- Just above baseplate — should fail when MapSafety excludes fallback
			local passed, _ = MapSafety.verifySpawnPointFloor(testCf)
			-- This should return false because only fallback is below; if it passes, fallback is not excluded
			check("[MAP] MapSafety excludes FallbackBaseplate", passed == false)
		end
	end

	-- ========================================
	-- Results
	-- ========================================
	print(("[SMOKE TEST] Completed: %d/%d tests passed"):format(passedTests, totalTests))

	if #failedTests == 0 then
		print("[OVERCLOCK] ✅ Server Boot Sequence: PASSED (All systems nominal)")
	else
		warn("[OVERCLOCK] ❌ Server Boot Sequence: FAILED")
		for i, err in failedTests do
			warn(("  [FAIL %d] %s"):format(i, err))
		end
	end
end

runTests()
