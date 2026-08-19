--!strict
--[=[
    Unit Tests for EconomyService
    Validates starting credit initialization, win/loss streak scaling arithmetic,
    kill rewards, sudden-death credit allocations, and server buy validation logic.
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local EconomyService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("EconomyService") :: any)

local function runTests()
	EconomyService.Init()

	local p1 = Instance.new("Player")
	p1.Name = "TestPlayer1"

	local p2 = Instance.new("Player")
	p2.Name = "TestPlayer2"

	-- 1. Test Starting Credit Initialization (Pistol Round = 800)
	local initBal1 = EconomyService.InitializePlayer(p1)
	assert(initBal1 == 800, "Pistol round starting credits should be 800, got: " .. tostring(initBal1))
	assert(EconomyService.GetCredits(p1) == 800, "GetCredits should return 800")

	-- 2. Test Direct Credit Manipulation
	EconomyService.SetCredits(p1, 1500)
	assert(EconomyService.GetCredits(p1) == 1500, "SetCredits should update balance to 1500")

	-- 3. Test Kill Reward (+200)
	local afterKill = EconomyService.AwardKillReward(p1)
	assert(afterKill == 1700, "Kill reward should add 200, expected 1700, got: " .. tostring(afterKill))

	-- 4. Test Sudden Death Credits Allocation (5000)
	EconomyService.SetSuddenDeathCredits({ p1, p2 })
	assert(EconomyService.GetCredits(p1) == 5000, "Sudden death credits for p1 should be 5000")
	assert(EconomyService.GetCredits(p2) == 5000, "Sudden death credits for p2 should be 5000")

	-- 5. Test Loss Streak Scaling Arithmetic
	assert(EconomyService.CalculateLossBonus(1) == 1900, "1st loss streak bonus should be 1900")
	assert(EconomyService.CalculateLossBonus(2) == 2400, "2nd loss streak bonus should be 2400")
	assert(EconomyService.CalculateLossBonus(3) == 2900, "3rd loss streak bonus should be 2900")
	assert(EconomyService.CalculateLossBonus(5) == 2900, "5th loss streak bonus should cap at 2900")

	-- 6. Test ProcessRoundEnd Credit Distribution
	EconomyService.SetCredits(p1, 100)
	EconomyService.SetCredits(p2, 100)

	-- p1 wins (+3000), p2 loses with lossStreak = 2 (+2400)
	local endResult = EconomyService.ProcessRoundEnd({ p1 }, { p2 }, 2)
	assert(endResult.winnerBonus == 3000, "Winner bonus should be 3000")
	assert(endResult.loserBonus == 2400, "Loser bonus should be 2400")

	assert(EconomyService.GetCredits(p1) == 3100, "Winner balance should be 100 + 3000 = 3100")
	assert(EconomyService.GetCredits(p2) == 2500, "Loser balance should be 100 + 2400 = 2500")

	-- 7. Test Buy Validation: Invalid Item Rejection
	EconomyService.SetCredits(p1, 5000)
	local invSuccess, invReason, _ = EconomyService.ProcessPurchaseRequest(p1, "NonExistentItem999")
	assert(invSuccess == false, "Invalid item purchase should fail, got success=" .. tostring(invSuccess))
	assert(invReason == "InvalidItem", "Invalid item reason should be 'InvalidItem', got: " .. tostring(invReason))

	-- 8. Test Buy Validation: Insufficient Credits Rejection
	EconomyService.SetCredits(p1, 100) -- Only 100 credits
	local lowSuccess, lowReason, lowBal = EconomyService.ProcessPurchaseRequest(p1, "AssaultRifle")
	assert(lowSuccess == false, "Insufficient credits purchase should fail, got success=" .. tostring(lowSuccess))
	assert(lowReason == "InsufficientCredits", "Failure reason should be 'InsufficientCredits', got: " .. tostring(lowReason))
	assert(lowBal == 100, "Balance should remain 100 after failed purchase, got: " .. tostring(lowBal))

	-- 9. Test Buy Validation: Successful Purchase Execution
	EconomyService.SetCredits(p1, 3000)
	local buySuccess, buyReason, buyBal = EconomyService.ProcessPurchaseRequest(p1, "AssaultRifle")
	assert(buySuccess == true, "Purchase with sufficient credits should succeed, got success=" .. tostring(buySuccess))
	assert(buyReason == "PurchaseSuccess", "Reason should be 'PurchaseSuccess', got: " .. tostring(buyReason))
	assert(buyBal == 100, "Balance should be 3000 - 2900 = 100, got: " .. tostring(buyBal))
	assert(EconomyService.GetCredits(p1) == 100, "GetCredits(p1) should be 100 after purchase")

	p1:Destroy()
	p2:Destroy()

	print("[EconomyService.spec] All unit tests passed successfully!")
	return true
end

runTests()
return true
