--!strict
--[=[
    Unit Tests for BotService
    Verifies Practice Range bot AI lifecycle, stationary target wall manager,
    hit detection & tilt animations, 3-second bot respawn, and live accuracy stats arithmetic.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ServicesFolder = script.Parent
local BotService = require(ServicesFolder:WaitForChild("BotService") :: any)

local MapFolder = ReplicatedStorage:WaitForChild("Map")
local PracticeRangeMapLayout = require(MapFolder:WaitForChild("PracticeRangeMapLayout") :: any)

local function runTests()
	print("[BotService.spec] Starting BotService unit tests...")

	-- Mock player table for testing stats
	local mockPlayer = {
		UserId = 999123,
		Name = "TestShooter",
		Parent = game:GetService("Players"),
	} :: any

	-- 1. Test Map Building & BotService Initialization
	local mapFolder = PracticeRangeMapLayout.BuildMap(Workspace)
	assert(mapFolder ~= nil, "BuildMap must return a valid Folder instance")

	BotService.Init(mapFolder)

	local targetStates = BotService.GetTargetStates()
	local targetCount = 0
	for _ in targetStates do
		targetCount += 1
	end
	assert(targetCount == 6, "BotService must track 6 stationary target states, got " .. targetCount)

	-- 2. Test Stationary Target Hit Detection & Counter
	local firstTargetState = targetStates[1]
	assert(firstTargetState ~= nil, "Target state 1 must exist")
	assert(firstTargetState.hitCount == 0, "Initial target hit count must be 0")

	local hitSuccess = BotService.ProcessTargetHit(mockPlayer, firstTargetState.targetPart, true)
	assert(hitSuccess == true, "ProcessTargetHit must return true for registered target part")
	assert(firstTargetState.hitCount == 1, "Target hit count must increment to 1")

	local statsAfterFirstHit = BotService.GetPlayerStats(mockPlayer)
	assert(statsAfterFirstHit.totalHits == 1, "Player totalHits must be 1")
	assert(statsAfterFirstHit.totalHeadshots == 1, "Player totalHeadshots must be 1 for bullseye hit")

	-- Hit outer ring of target
	BotService.ProcessTargetHit(mockPlayer, firstTargetState.targetPart, false)
	assert(firstTargetState.hitCount == 2, "Target hit count must increment to 2")

	local statsAfterSecondHit = BotService.GetPlayerStats(mockPlayer)
	assert(statsAfterSecondHit.totalHits == 2, "Player totalHits must increment to 2")
	assert(statsAfterSecondHit.totalHeadshots == 1, "Player totalHeadshots must remain 1")

	-- 3. Test Patrol Bot Spawning & Hierarchy
	local patrolBots = BotService.GetBots()
	local botCount = 0
	for _ in patrolBots do
		botCount += 1
	end
	assert(botCount == 5, "SpawnPatrolBots must spawn 5 bots by default, got " .. botCount)

	for id, botData in patrolBots do
		assert(botData.botId == id, "Bot ID mismatch")
		assert(botData.model ~= nil, "Bot model must exist")
		assert(botData.model.Parent ~= nil, "Bot model must be parented")
		assert(botData.humanoid ~= nil, "Bot humanoid must exist")
		assert(botData.humanoid.Health == 100, "Bot humanoid max health must start at 100")
		assert(botData.humanoid.WalkSpeed == 12, "Bot humanoid walk speed must be 12")
		assert(botData.rootPart ~= nil, "Bot HumanoidRootPart must exist")
		assert(botData.headPart ~= nil, "Bot Head must exist")
		assert(botData.headPart:GetAttribute("IsHead") == true, "Head must have IsHead = true attribute")
		assert(botData.billboardGui ~= nil, "Bot BillboardGui overhead display must exist")
		assert(botData.isAlive == true, "Bot isAlive state must start as true")
	end

	-- 4. Test Bot Damage, Death State & 3-Second Respawn
	local bot1 = patrolBots[1]
	assert(bot1 ~= nil, "Bot 1 must exist")

	-- Kill Bot 1
	bot1.humanoid.Health = 0
	task.wait(0.1) -- Allow HealthChanged signal to process

	assert(bot1.isAlive == false, "Bot 1 isAlive state must become false after death")

	-- Fast-forward / wait for 3.0s respawn timer
	task.wait(3.1)

	assert(bot1.isAlive == true, "Bot 1 isAlive state must become true after 3s respawn")
	assert(bot1.humanoid.Health == 100, "Bot 1 health must be restored to 100 HP after respawn")
	local distFromOrigin = (bot1.rootPart.Position - (bot1.originSpawnPos + Vector3.new(0, 3, 0))).Magnitude
	assert(distFromOrigin < 2.0, "Bot 1 position must reset to origin spawn pad position, got dist " .. distFromOrigin)

	-- 5. Test Live Accuracy Stats Arithmetic & Reset
	BotService.ResetPlayerStats(mockPlayer)

	local resetStats = BotService.GetPlayerStats(mockPlayer)
	assert(resetStats.totalShotsFired == 0, "totalShotsFired must reset to 0")
	assert(resetStats.totalHits == 0, "totalHits must reset to 0")
	assert(resetStats.totalHeadshots == 0, "totalHeadshots must reset to 0")
	assert(resetStats.accuracyPercent == 0.0, "accuracyPercent must reset to 0.0")
	assert(resetStats.headshotPercent == 0.0, "headshotPercent must reset to 0.0")

	-- Simulate 10 shots fired, 4 hits (2 headshots)
	for _ = 1, 10 do
		BotService.RecordShot(mockPlayer)
	end
	BotService.RecordHit(mockPlayer, true) -- Headshot 1
	BotService.RecordHit(mockPlayer, true) -- Headshot 2
	BotService.RecordHit(mockPlayer, false) -- Body hit 1
	BotService.RecordHit(mockPlayer, false) -- Body hit 2

	local calculatedStats = BotService.GetPlayerStats(mockPlayer)
	assert(calculatedStats.totalShotsFired == 10, "totalShotsFired must be 10, got " .. calculatedStats.totalShotsFired)
	assert(calculatedStats.totalHits == 4, "totalHits must be 4, got " .. calculatedStats.totalHits)
	assert(calculatedStats.totalHeadshots == 2, "totalHeadshots must be 2, got " .. calculatedStats.totalHeadshots)
	assert(calculatedStats.accuracyPercent == 40.0, "accuracyPercent must be 40.0 (4/10), got " .. calculatedStats.accuracyPercent)
	assert(calculatedStats.headshotPercent == 50.0, "headshotPercent must be 50.0 (2/4), got " .. calculatedStats.headshotPercent)

	-- 6. Test Teardown
	BotService.Destroy()
	PracticeRangeMapLayout.DestroyMap()

	print("[BotService.spec] All BotService unit tests passed successfully!")
end

runTests()
return true
