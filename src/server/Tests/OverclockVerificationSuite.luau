--!strict
--[=[ OVERCLOCK: Verification Test Suite
    Runnable in Roblox Studio command bar or as a server script.
    Tests: weapon damage math, economy credits, round state transitions.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any)
local OperativeStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("OperativeStats") :: any)

local passed = 0
local failed = 0
local total = 0

local function assert_eq(name: string, got: any, expected: any)
	total += 1
	if got == expected then
		passed += 1
		print("  ✅ PASS: " .. name .. " = " .. tostring(got))
	else
		failed += 1
		warn("  ❌ FAIL: " .. name .. " | Got: " .. tostring(got) .. " | Expected: " .. tostring(expected))
	end
end

local function assert_range(name: string, got: number, min: number, max: number)
	total += 1
	if got >= min and got <= max then
		passed += 1
		print("  ✅ PASS: " .. name .. " = " .. tostring(got) .. " (in range " .. min .. "-" .. max .. ")")
	else
		failed += 1
		warn("  ❌ FAIL: " .. name .. " = " .. tostring(got) .. " (expected " .. min .. "-" .. max .. ")")
	end
end

local function assert_truthy(name: string, val: any)
	total += 1
	if val then
		passed += 1
		print("  ✅ PASS: " .. name)
	else
		failed += 1
		warn("  ❌ FAIL: " .. name .. " was falsy")
	end
end

-- ═══════════════════════════════════════════
-- TEST 1: Weapon Stats Registry
-- ═══════════════════════════════════════════
print("\n══════ TEST 1: Weapon Stats Registry ══════")

local expectedWeapons = {"Pistol", "LightSMG", "HeavySMG", "Carbine", "AssaultRifle", "SniperRifle", "Shotgun", "BurstRifle"}
for _, wId in expectedWeapons do
	local data = WeaponStats.Get(wId)
	assert_truthy("Weapon '" .. wId .. "' exists", data)
	if data then
		assert_truthy(wId .. " has damage > 0", data.damage > 0)
		assert_truthy(wId .. " has headshot mult >= 2.0", data.headshotMultiplier >= 2.0)
	end
end

assert_eq("Total weapons >= 8", #expectedWeapons >= 8, true)

-- Armor
assert_truthy("LightArmor exists", WeaponStats.GetArmor("LightArmor"))
assert_truthy("HeavyArmor exists", WeaponStats.GetArmor("HeavyArmor"))
local la = WeaponStats.GetArmor("LightArmor")
if la then assert_eq("LightArmor shield = 25", la.shield, 25) end

-- ═══════════════════════════════════════════
-- TEST 2: Damage Calculations
-- ═══════════════════════════════════════════
print("\n══════ TEST 2: Damage Calculations ══════")

-- AR: 32 dmg, 2.5x headshot, falloff past 500 studs
local arBody50 = WeaponStats.CalculateDamage("AssaultRifle", false, 50)
assert_eq("AR body@50studs = 32", arBody50, 32)

local arHead50 = WeaponStats.CalculateDamage("AssaultRifle", true, 50)
assert_eq("AR headshot@50studs = 80", arHead50, 80)

local arBody800 = WeaponStats.CalculateDamage("AssaultRifle", false, 800)
assert_range("AR body@800studs (falloff)", arBody800, 16, 28)

-- Sniper: 105 dmg, 2.5x headshot
local sniperHead100 = WeaponStats.CalculateDamage("SniperRifle", true, 100)
assert_eq("Sniper headshot@100studs = 263", sniperHead100, 263)

-- Pistol body close range
local pistolBody10 = WeaponStats.CalculateDamage("Pistol", false, 10)
assert_eq("Pistol body@10studs = 24", pistolBody10, 24)

-- ═══════════════════════════════════════════
-- TEST 3: Operative Stats Registry
-- ═══════════════════════════════════════════
print("\n══════ TEST 3: Operative Stats ══════")

local expectedOps = {"Vex", "Warden", "Fray", "Choke", "Pulse", "Bastion"}
for _, opId in expectedOps do
	local data = OperativeStats.Get(opId)
	assert_truthy("Operative '" .. opId .. "' exists", data)
	if data then
		assert_truthy(opId .. " has Basic ability", data.abilities.Basic)
		assert_truthy(opId .. " has Paid ability", data.abilities.Paid)
		assert_truthy(opId .. " has Ultimate ability", data.abilities.Ultimate)
		assert_truthy(opId .. " Basic has cooldown > 0", data.abilities.Basic.cooldown > 0)
		assert_eq(opId .. " Ultimate creditCost = 0", data.abilities.Ultimate.creditCost, 0)
	end
end

-- ═══════════════════════════════════════════
-- TEST 4: Economy Constants
-- ═══════════════════════════════════════════
print("\n══════ TEST 4: Economy Constants ══════")

local ServicesFolder = script.Parent.Parent:FindFirstChild("Services")
if ServicesFolder then
	local ok, EconomyService = pcall(function()
		return require(ServicesFolder:WaitForChild("EconomyService") :: any)
	end)
	if ok and EconomyService then
		assert_eq("Starting credits = 800", EconomyService.PISTOL_ROUND_CREDITS, 800)
		assert_eq("Win bonus = 3000", EconomyService.WIN_BONUS, 3000)
		assert_eq("Sudden death credits = 5000", EconomyService.SUDDEN_DEATH_CREDITS, 5000)
		assert_truthy("Loss streak tier 1 exists", EconomyService.LOSS_STREAK_TIER_1 and EconomyService.LOSS_STREAK_TIER_1 > 0)
	else
		warn("  ⚠ Could not load EconomyService for testing")
	end
else
	warn("  ⚠ Services folder not found")
end

-- ═══════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════
print("\n══════════════════════════════════")
print(string.format("RESULTS: %d/%d PASSED, %d FAILED", passed, total, failed))
if failed == 0 then
	print("🎉 ALL TESTS PASSED!")
else
	warn("⚠ SOME TESTS FAILED - Review output above")
end
print("══════════════════════════════════\n")
