--!strict
--[=[
    Project OVERCLOCK: Milestone 1 Combat & Damage Verification Test Suite
    Validates server-authoritative damage calculation, headshot multipliers,
    range falloff, 8-weapon registry stats, and 50% armor absorption math.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local WeaponStats = require(DataFolder:WaitForChild("WeaponStats") :: any)

local CombatServerModule = script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatServer")
local CombatServer = require(CombatServerModule :: any)

local function runTests()
	print("==================================================")
	print("[M1_DamageTest] Starting M1 Combat & Damage Test Suite...")
	print("==================================================")

	local testsPassed = 0
	local totalTests = 0

	local function assertEqual(testName: string, actual: any, expected: any)
		totalTests += 1
		if actual == expected then
			testsPassed += 1
			print(string.format("  [PASS] %s -> Result: %s", testName, tostring(actual)))
		else
			error(string.format("  [FAIL] %s -> Expected: %s, Got: %s", testName, tostring(expected), tostring(actual)))
		end
	end

	-- Test Case 1: AssaultRifle close range bodyshot (32 base damage)
	local dmg1 = WeaponStats.CalculateDamage("AssaultRifle", false, 100)
	assertEqual("AssaultRifle close bodyshot (100 studs)", dmg1, 32)

	-- Test Case 2: AssaultRifle close range headshot (2.5x multiplier -> 80 damage)
	local dmg2 = WeaponStats.CalculateDamage("AssaultRifle", true, 100)
	assertEqual("AssaultRifle close headshot (100 studs)", dmg2, 80)

	-- Test Case 3: AssaultRifle at falloff distance (750 studs: 50% range dropoff -> 16 damage)
	local dmg3 = WeaponStats.CalculateDamage("AssaultRifle", false, 750)
	assertEqual("AssaultRifle falloff bodyshot (750 studs)", dmg3, 16)

	-- Test Case 4: SniperRifle long range headshot (2.5x multiplier -> 263 damage)
	local dmg4 = WeaponStats.CalculateDamage("SniperRifle", true, 1000)
	assertEqual("SniperRifle long range headshot (1000 studs)", dmg4, 263)

	-- Test Case 5: Pistol mid range bodyshot (375 studs: 50% dropoff -> 12 damage)
	local dmg5 = WeaponStats.CalculateDamage("Pistol", false, 375)
	assertEqual("Pistol mid range bodyshot (375 studs)", dmg5, 12)

	-- Test Case 6: Shotgun close range bodyshot (80 base damage)
	local dmg6 = WeaponStats.CalculateDamage("Shotgun", false, 100)
	assertEqual("Shotgun close range bodyshot (100 studs)", dmg6, 80)

	-- Test Case 7: LightSMG close range headshot (17 base * 2.0x -> 34 damage)
	local dmg7 = WeaponStats.CalculateDamage("LightSMG", true, 50)
	assertEqual("LightSMG close headshot (50 studs)", dmg7, 34)

	-- Test Case 8: HeavySMG close range bodyshot (22 base damage)
	local dmg8 = WeaponStats.CalculateDamage("HeavySMG", false, 100)
	assertEqual("HeavySMG close bodyshot (100 studs)", dmg8, 22)

	-- Test Case 9: Carbine close range headshot (28 base * 2.25x -> 63 damage)
	local dmg9 = WeaponStats.CalculateDamage("Carbine", true, 100)
	assertEqual("Carbine close headshot (100 studs)", dmg9, 63)

	-- Test Case 10: BurstRifle close range bodyshot (27 base damage)
	local dmg10 = WeaponStats.CalculateDamage("BurstRifle", false, 100)
	assertEqual("BurstRifle close bodyshot (100 studs)", dmg10, 27)

	-- Test Case 11: CombatServer 50% Armor Absorption (100 raw damage against 50 Heavy Armor shield)
	local combat = CombatServer.new()
	combat:RegisterPlayer(1001, 100, 50) -- Attacker
	combat:RegisterPlayer(1002, 100, 50) -- Victim with 50 shield & 100 health

	-- Simulate 80 raw damage hit against player 1002
	-- maxAbsorption = math.floor(80 * 0.5) = 40 shield absorbed, 40 health damage
	-- Expected state: 10 shield remaining, 60 health remaining
	local payload = {
		origin = Vector3.new(0, 0, 0),
		direction = Vector3.new(0, 0, -1),
		hitPosition = Vector3.new(0, 0, -50),
		distance = 50,
		clientTimestamp = os.clock(),
		sequenceId = 1,
		weaponId = "Shotgun",
		isHeadshot = false,
	}

	-- Set phase to InGame and call ProcessHitReport
	combat:SetMatchPhase("InGame")
	-- Process hit report with baseDamage override = 80 to verify precise armor absorption formula
	local success, err, remainingHp = combat:ProcessHitReport(1001, 1002, payload, 1000, 80)
	assertEqual("CombatServer ProcessHitReport status", success, true)

	local victimHealthState = combat:GetPlayerHealth(1002)
	if victimHealthState then
		assertEqual("50% Armor Absorption -> Remaining Shield", victimHealthState.shield, 10)
		assertEqual("50% Armor Absorption -> Remaining Health", victimHealthState.health, 60)
	else
		error("Failed to fetch victim health state")
	end

	-- Test Case 12: Practice Range Target Hit Validation
	combat:SetMatchPhase("PracticeRange")
	local practicePayload = {
		origin = Vector3.new(0, 0, 0),
		direction = Vector3.new(0, 0, -1),
		hitPosition = Vector3.new(0, 0, -20),
		distance = 20,
		clientTimestamp = os.clock(),
		sequenceId = 2,
		weaponId = "Pistol",
		isHeadshot = false,
	}
	local pSuccess, pErr, _ = combat:ProcessHitReport(1001, 0, practicePayload, 500)
	assertEqual("Practice Range Non-Player Hit Permissibility", pSuccess, true)

	print("==================================================")
	print(string.format("[M1_DamageTest] SUCCESS: %d/%d test cases passed!", testsPassed, totalTests))
	print("==================================================")
end

-- Run tests immediately when loaded
local ok, err = pcall(runTests)
if not ok then
	warn("[M1_DamageTest] Test suite execution failed: " .. tostring(err))
end
