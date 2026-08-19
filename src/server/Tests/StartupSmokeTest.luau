--!strict
--[=[
    Project OVERCLOCK: StartupSmokeTest
    Milestone 6 (M6) Startup Smoke Test & E2E Integration.
    Validates mandatory systems, network remotes, map folders, shared statistics,
    and server services on boot.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StartupSmokeTest = {}

function StartupSmokeTest.Run(): (boolean, { string })
	local logs: { string } = {}
	local passedCount = 0
	local failedCount = 0

	local function logPass(msg: string)
		passedCount += 1
		local line = "✅ [PASS] " .. msg
		table.insert(logs, line)
		print(line)
	end

	local function logFail(msg: string)
		failedCount += 1
		local line = "❌ [FAIL] " .. msg
		table.insert(logs, line)
		warn(line)
	end

	table.insert(logs, "==================================================")
	table.insert(logs, "   OVERCLOCK STARTUP SMOKE TEST (MILESTONE 6)   ")
	table.insert(logs, "==================================================")
	print("==================================================")
	print("   OVERCLOCK STARTUP SMOKE TEST (MILESTONE 6)   ")
	print("==================================================")

	-- ------------------------------------------------------------------------
	-- CHECK 1: ReplicatedStorage Infrastructure
	-- ------------------------------------------------------------------------
	local networkFolder = ReplicatedStorage:FindFirstChild("Network")
	if networkFolder then
		logPass("ReplicatedStorage.Network directory exists")
		local remotesFolder = networkFolder:FindFirstChild("Remotes")
		if remotesFolder then
			logPass("ReplicatedStorage.Network.Remotes directory exists")
		else
			logFail("ReplicatedStorage.Network.Remotes directory missing")
		end

		local remoteEventsMod = networkFolder:FindFirstChild("RemoteEvents")
		if remoteEventsMod then
			logPass("RemoteEvents module found")
		else
			logFail("RemoteEvents module missing in Network")
		end
	else
		logFail("ReplicatedStorage.Network directory missing")
	end

	-- ------------------------------------------------------------------------
	-- CHECK 2: Shared Data & Statistics Modules
	-- ------------------------------------------------------------------------
	local dataFolder = ReplicatedStorage:FindFirstChild("Data")
	if dataFolder then
		logPass("ReplicatedStorage.Data directory exists")

		local okWep, WeaponStats = pcall(require, dataFolder:WaitForChild("WeaponStats") :: any)
		if okWep and WeaponStats then
			logPass("WeaponStats module required successfully")
			if WeaponStats.Get("AssaultRifle") then
				logPass("WeaponStats.Get('AssaultRifle') verified")
			else
				logFail("WeaponStats.Get('AssaultRifle') returned nil")
			end
		else
			logFail("Failed to require WeaponStats module")
		end

		local okOp, OperativeStats = pcall(require, dataFolder:WaitForChild("OperativeStats") :: any)
		if okOp and OperativeStats then
			logPass("OperativeStats module required successfully")
			if OperativeStats.Get("Vex") then
				logPass("OperativeStats.Get('Vex') verified")
			else
				logFail("OperativeStats.Get('Vex') returned nil")
			end
		else
			logFail("Failed to require OperativeStats module")
		end
	else
		logFail("ReplicatedStorage.Data directory missing")
	end

	-- ------------------------------------------------------------------------
	-- CHECK 3: Map Safety & Verification API
	-- ------------------------------------------------------------------------
	local mapFolder = ReplicatedStorage:FindFirstChild("Map")
	if mapFolder then
		logPass("ReplicatedStorage.Map directory exists")
		local mapSafetyMod = mapFolder:FindFirstChild("MapSafety")
		if mapSafetyMod then
			local okMap, MapSafety = pcall(require, mapSafetyMod :: any)
			if okMap and MapSafety and type(MapSafety.assertMapReady) == "function" then
				logPass("MapSafety.assertMapReady function verified")
			else
				logFail("MapSafety module invalid or missing assertMapReady API")
			end
		else
			logFail("MapSafety module missing in ReplicatedStorage.Map")
		end
	else
		logFail("ReplicatedStorage.Map directory missing")
	end

	-- ------------------------------------------------------------------------
	-- CHECK 4: Server Services & Spawn Authority
	-- ------------------------------------------------------------------------
	local servicesFolder = ServerScriptService:FindFirstChild("Services")
	if servicesFolder then
		logPass("ServerScriptService.Services directory exists")

		local spawnServiceMod = servicesFolder:FindFirstChild("SpawnService")
		if spawnServiceMod then
			local okSpawn, SpawnService = pcall(require, spawnServiceMod :: any)
			if okSpawn and SpawnService then
				logPass("SpawnService module required successfully")
				if type(SpawnService.SpawnPlayer) == "function" then
					logPass("SpawnService.SpawnPlayer API verified")
				else
					logFail("SpawnService missing SpawnPlayer API")
				end
			else
				logFail("Failed to require SpawnService module")
			end
		else
			logFail("SpawnService module missing in ServerScriptService.Services")
		end

		local econServiceMod = servicesFolder:FindFirstChild("EconomyService")
		if econServiceMod then
			local okEcon, EconomyService = pcall(require, econServiceMod :: any)
			if okEcon and EconomyService then
				logPass("EconomyService module required successfully")
			else
				logFail("Failed to require EconomyService module")
			end
		else
			logFail("EconomyService module missing in ServerScriptService.Services")
		end
	else
		logFail("ServerScriptService.Services directory missing")
	end

	-- ------------------------------------------------------------------------
		-- ------------------------------------------------------------------------
	-- CHECK 5: Additional Verification
	-- ------------------------------------------------------------------------
	if Workspace:FindFirstChild("Projectiles") then logPass("Workspace.Projectiles exists") else logFail("Workspace.Projectiles missing") end
	if Workspace:FindFirstChild("Effects") then logPass("Workspace.Effects exists") else logFail("Workspace.Effects missing") end

	local PhysicsService = game:GetService("PhysicsService")
	local cGroups = PhysicsService:GetRegisteredCollisionGroups()
	if #cGroups >= 8 then logPass("At least 8 collision groups exist") else logFail("Less than 8 collision groups exist") end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerStorage = game:GetService("ServerStorage")
	local templates = ServerStorage:FindFirstChild("Templates")
	if templates then
		if templates:FindFirstChild("VettedProps") then logPass("VettedProps exists") else logFail("VettedProps missing") end
		local pVis = templates:FindFirstChild("ProjectileVisual")
		if pVis and pVis:IsA("BasePart") then logPass("ProjectileVisual exists") else logFail("ProjectileVisual missing or invalid") end
	else
		logFail("ServerStorage.Templates missing")
	end

	local MapRegistry = require(ReplicatedStorage.Map.MapRegistry)
	for mapId, mapData in MapRegistry.GetAllMaps() do
		if #mapData.redSpawns >= 2 and #mapData.blueSpawns >= 2 then
			logPass("Map " .. mapId .. " has sufficient spawns")
		else
			logFail("Map " .. mapId .. " lacks sufficient spawns")
		end
	end

	-- SUMMARY
	-- ------------------------------------------------------------------------
	local summaryLine = string.format("SUMMARY: %d PASSED, %d FAILED (TOTAL %d)", passedCount, failedCount, passedCount + failedCount)
	table.insert(logs, summaryLine)
	print(summaryLine)

	local overallSuccess = (failedCount == 0)
	return overallSuccess, logs
end

return StartupSmokeTest
