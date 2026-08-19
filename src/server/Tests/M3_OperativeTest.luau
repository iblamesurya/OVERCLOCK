--!strict
--[=[
    Project OVERCLOCK: Milestone 3 Automated Verification Test Suite
    Validates 6 Operatives, 18 functional abilities, ultimate charge math,
    PvP credit cost validation, round cooldown resets, and Practice Range sandbox overrides.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local OperativeStats = require(DataFolder:WaitForChild("OperativeStats") :: any)

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local OperativeService = require(ServicesFolder:WaitForChild("OperativeService") :: any)
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService") :: any)

print("==================================================")
print("[M3_TEST] Starting Milestone 3 Operatives & Abilities Verification Suite...")
print("==================================================")

local testsPassed = 0
local totalTests = 0

local function assertTest(condition: boolean, message: string)
	totalTests += 1
	if condition then
		testsPassed += 1
		print(string.format("  [PASS] Test %d: %s", totalTests, message))
	else
		error(string.format("  [FAIL] Test %d: %s", totalTests, message))
	end
end

-- Setup Mock Player Object for Testing
local mockPlayer = Instance.new("Player")
mockPlayer.Name = "M3_TestOperativePlayer"

local mockCharacter = Instance.new("Model")
mockCharacter.Name = "M3_TestCharacter"
local mockHumanoid = Instance.new("Humanoid")
mockHumanoid.Health = 100
mockHumanoid.MaxHealth = 100
mockHumanoid.Parent = mockCharacter
local mockRoot = Instance.new("Part")
mockRoot.Name = "HumanoidRootPart"
mockRoot.Position = Vector3.new(0, 100, 0)
mockRoot.Parent = mockCharacter
mockCharacter.Parent = workspace
mockPlayer.Character = mockCharacter

-- Initialize Services
OperativeService.Init()
EconomyService.Init()

-- ----------------------------------------------------------------------------
-- Test Suite 1: Operative Data Registry Verification (6 Operatives, 18 Abilities)
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 1: Operative Data Registry ---")

local expectedOperatives = { "Vex", "Warden", "Fray", "Choke", "Pulse", "Bastion" }
local allOps = OperativeStats.GetAll()

assertTest(allOps ~= nil, "OperativeStats.GetAll() returns valid table")

local opCount = 0
for opId, opData in allOps do
	opCount += 1
	assertTest(opData.id == opId, string.format("Operative '%s' has matching ID", opId))
	assertTest(opData.name ~= nil and #opData.name > 0, string.format("Operative '%s' has non-empty name", opId))
	assertTest(opData.role ~= nil, string.format("Operative '%s' has assigned role: %s", opId, tostring(opData.role)))

	local basic = opData.abilities.Basic
	local paid = opData.abilities.Paid
	local ult = opData.abilities.Ultimate

	assertTest(basic ~= nil and basic.slot == "Basic", string.format("Operative '%s' has Basic ability: %s", opId, basic and basic.name or "N/A"))
	assertTest(paid ~= nil and paid.slot == "Paid", string.format("Operative '%s' has Paid ability: %s", opId, paid and paid.name or "N/A"))
	assertTest(ult ~= nil and ult.slot == "Ultimate", string.format("Operative '%s' has Ultimate ability: %s", opId, ult and ult.name or "N/A"))
end

assertTest(opCount == 6, string.format("Exactly 6 Operatives registered in database (Found: %d)", opCount))

for _, id in expectedOperatives do
	local fetched = OperativeStats.Get(id)
	assertTest(fetched ~= nil and fetched.id == id, string.format("OperativeStats.Get('%s') succeeds", id))

	local basicAb = OperativeStats.GetAbility(id, "Basic")
	local paidAb = OperativeStats.GetAbility(id, "Paid")
	local ultAb = OperativeStats.GetAbility(id, "Ultimate")

	assertTest(basicAb ~= nil and basicAb.cooldown > 0, string.format("Ability '%s' has valid PvP cooldown (%ds)", basicAb and basicAb.name or "", basicAb and basicAb.cooldown or 0))
	assertTest(paidAb ~= nil and paidAb.creditCost > 0, string.format("Ability '%s' has valid PvP credit cost (%d credits)", paidAb and paidAb.name or "", paidAb and paidAb.creditCost or 0))
	assertTest(ultAb ~= nil and ultAb.slot == "Ultimate", string.format("Ability '%s' correctly assigned to Ultimate slot", ultAb and ultAb.name or ""))
end

-- ----------------------------------------------------------------------------
-- Test Suite 2: Operative Selection & Player State Management
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 2: Selection & State Management ---")

local selOk, selReason = OperativeService.SelectOperative(mockPlayer, "Warden")
assertTest(selOk and selReason == "Success", "OperativeService.SelectOperative('Warden') succeeds")

local st = OperativeService.GetPlayerState(mockPlayer)
assertTest(st.selectedOperative == "Warden", "Player state reflects selected Operative 'Warden'")

local getSel = OperativeService.GetPlayerState(mockPlayer).selectedOperative
assertTest(getSel == "Warden", "GetPlayerState returns correct selected operative ID")

-- ----------------------------------------------------------------------------
-- Test Suite 3: Ultimate Accumulation Math
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 3: Ultimate Accumulation Math ---")

st.ultCharge = 0
assertTest(st.ultCharge == 0, "Initial ultimate charge is 0%")

-- 100 damage dealt = +10% ult charge
OperativeService.OnDamageDealt(mockPlayer, 100)
assertTest(math.abs(st.ultCharge - 10) < 0.01, string.format("100 damage dealt grants +10%% ult charge (Current: %.1f%%)", st.ultCharge))

-- 500 damage dealt = +50% ult charge
OperativeService.OnDamageDealt(mockPlayer, 500)
assertTest(math.abs(st.ultCharge - 60) < 0.01, string.format("500 additional damage dealt increases ult charge to 60%% (Current: %.1f%%)", st.ultCharge))

-- 1 kill = +20% ult charge
OperativeService.OnKill(mockPlayer)
assertTest(math.abs(st.ultCharge - 80) < 0.01, string.format("1 kill grants +20%% ult charge (Current: %.1f%%)", st.ultCharge))

-- Capped at 100%
OperativeService.OnKill(mockPlayer)
assertTest(st.ultCharge == 100, string.format("Second kill caps ult charge at 100%% (Current: %.1f%%)", st.ultCharge))

OperativeService.OnDamageDealt(mockPlayer, 1000)
assertTest(st.ultCharge == 100, "Excess damage dealth does not exceed 100% cap")

-- ----------------------------------------------------------------------------
-- Test Suite 4: Credit Cost Validation for Paid Abilities in PvP
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 4: Credit Cost Validation ---")

OperativeService.SelectOperative(mockPlayer, "Vex") -- Paid ability Shock Trap costs 300 credits
EconomyService.SetCredits(mockPlayer, 100) -- Only 100 credits available

local paidOk, paidErr = OperativeService.UseAbility(mockPlayer, "Paid", CFrame.new(0, 100, 0))
assertTest(not paidOk and paidErr == "InsufficientCredits", string.format("Paid ability rejected with 'InsufficientCredits' when balance (100) < cost (300)"))

EconomyService.SetCredits(mockPlayer, 500) -- Give 500 credits
paidOk, paidErr = OperativeService.UseAbility(mockPlayer, "Paid", CFrame.new(0, 100, 0))
assertTest(paidOk and paidErr == "Success", string.format("Paid ability executed successfully when balance (500) >= cost (300)"))

local remainingCredits = EconomyService.GetCredits(mockPlayer)
assertTest(remainingCredits == 200, string.format("Credit balance correctly updated after purchase (500 - 300 = %d)", remainingCredits))

-- ----------------------------------------------------------------------------
-- Test Suite 5: Round Cooldown Resets & Ult Preservation
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 5: Round Cooldown Resets ---")

st.cooldownEndTimestamps.Basic = os.clock() + 20
st.cooldownEndTimestamps.Paid = os.clock() + 15
st.ultCharge = 75

OperativeService.ResetRoundCooldowns(mockPlayer)

assertTest(st.cooldownEndTimestamps.Basic <= os.clock(), "Basic ability cooldown reset to 0 on round start")
assertTest(st.cooldownEndTimestamps.Paid <= os.clock(), "Paid ability cooldown reset to 0 on round start")
assertTest(st.ultCharge == 75, string.format("Ultimate charge retained across round reset (75%%)"))

-- ----------------------------------------------------------------------------
-- Test Suite 6: Practice Range Sandbox Overrides
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 6: Practice Range Sandbox Overrides ---")

mockPlayer:SetAttribute("IsPracticeRange", true)
assertTest(OperativeService.IsPracticeRange(mockPlayer) == true, "Player correctly detected in Practice Range sandbox mode")

EconomyService.SetCredits(mockPlayer, 0) -- 0 credits
st.cooldownEndTimestamps.Paid = os.clock() + 999 -- Forced cooldown

-- In Practice Range, abilities execute with 0 cooldown and 0 credit cost!
local rangeOk, rangeErr = OperativeService.UseAbility(mockPlayer, "Paid", CFrame.new(0, 100, 0))
assertTest(rangeOk and rangeErr == "Success", "Paid ability succeeds in Practice Range with 0 credits and 0s cooldown")

-- Instant agent switching in Practice Range
local rangeSelOk, _ = OperativeService.SelectOperative(mockPlayer, "Bastion")
assertTest(rangeSelOk and st.selectedOperative == "Bastion", "Operative instantly switched to Bastion in Practice Range sandbox")

mockPlayer:SetAttribute("IsPracticeRange", nil)

-- ----------------------------------------------------------------------------
-- Test Suite 7: Status Debuffs & EMP Silence
-- ----------------------------------------------------------------------------
print("\n--- Test Suite 7: Status Debuffs & EMP Silence ---")

st.silencedUntil = os.clock() + 5 -- Silenced for 5s
local silOk, silErr = OperativeService.UseAbility(mockPlayer, "Basic", CFrame.new(0, 100, 0))
assertTest(not silOk and silErr == "Silenced", "Ability execution blocked when player is silenced by EMP")

st.silencedUntil = 0 -- Clear silence
local clearOk, clearErr = OperativeService.UseAbility(mockPlayer, "Basic", CFrame.new(0, 100, 0))
assertTest(clearOk and clearErr == "Success", "Ability execution succeeds after silence expires")

-- Clean up test instances
mockCharacter:Destroy()
mockPlayer:Destroy()

print("\n==================================================")
print(string.format("[M3_TEST] SUCCESS! Passed %d/%d assertions in Milestone 3 Test Suite.", testsPassed, totalTests))
print("==================================================")
