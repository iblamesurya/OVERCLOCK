--!strict
--[=[
    Project OVERCLOCK: Milestone 4 Network Security & Parameter Validation Test
    Executes stress testing against all server RemoteEvent and RemoteFunction listeners
    with adversarial edge-case parameters (nil player, negative numbers, ultra-long strings,
    invalid enum strings, table injection, NaN, Infinity, math.huge, wrong types).
    Verifies that all handlers reject/drop requests safely without throwing uncaught exceptions.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)
local QueueEvents = require(NetworkFolder:WaitForChild("QueueEvents") :: any)
local ChallengeEvents = require(NetworkFolder:WaitForChild("ChallengeEvents") :: any)

local CombatServer = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatServer") :: any)

local M4_NetworkSecurityTest = {}

function M4_NetworkSecurityTest.RunAllTests(): (boolean, number, number, { string })
	local passed = 0
	local failed = 0
	local errors: { string } = {}

	local function assertSafe(actionName: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print("[SAFE] " .. actionName)
		else
			failed += 1
			local msg = "[UNCAUGHT EXCEPTION] " .. actionName .. ": " .. tostring(err)
			table.insert(errors, msg)
			warn(msg)
		end
	end

	print("==================================================")
	print("RUNNING MILESTONE 4 NETWORK SECURITY STRESS TESTS")
	print("==================================================")

	-- Mock / Dummy Player for safe call testing
	local dummyPlayer = Instance.new("Folder")
	dummyPlayer.Name = "DummyPlayer"

	local ultraLongString = string.rep("A", 10000)

	-- ------------------------------------------------------------------------
	-- TEST 1: CombatServer.ValidateHitPayload Edge-Cases
	-- ------------------------------------------------------------------------
	assertSafe("ValidateHitPayload: nil", function()
		local res = CombatServer.ValidateHitPayload(nil)
		assert(res == false, "Must return false for nil")
	end)

	assertSafe("ValidateHitPayload: non-table (string)", function()
		local res = CombatServer.ValidateHitPayload("malicious_string")
		assert(res == false, "Must return false for string")
	end)

	assertSafe("ValidateHitPayload: NaN Vector3 origin", function()
		local res = CombatServer.ValidateHitPayload({
			origin = Vector3.new(0/0, 0, 0),
			direction = Vector3.new(0, 0, -1),
			hitPosition = Vector3.new(0, 0, 10),
			distance = 10,
			clientTimestamp = 1.0,
			sequenceId = 1,
			weaponId = "Pistol",
		})
		assert(res == false, "Must reject NaN Vector3")
	end)

	assertSafe("ValidateHitPayload: Infinite Vector3 origin", function()
		local res = CombatServer.ValidateHitPayload({
			origin = Vector3.new(math.huge, 0, 0),
			direction = Vector3.new(0, 0, -1),
			hitPosition = Vector3.new(0, 0, 10),
			distance = 10,
			clientTimestamp = 1.0,
			sequenceId = 1,
			weaponId = "Pistol",
		})
		assert(res == false, "Must reject infinite Vector3")
	end)

	assertSafe("ValidateHitPayload: Negative distance", function()
		local res = CombatServer.ValidateHitPayload({
			origin = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, 0, -1),
			hitPosition = Vector3.new(0, 0, -10),
			distance = -50,
			clientTimestamp = 1.0,
			sequenceId = 1,
			weaponId = "Pistol",
		})
		assert(res == false, "Must reject negative distance")
	end)

	assertSafe("ValidateHitPayload: Ultra-long weaponId string", function()
		local res = CombatServer.ValidateHitPayload({
			origin = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, 0, -1),
			hitPosition = Vector3.new(0, 0, 10),
			distance = 10,
			clientTimestamp = 1.0,
			sequenceId = 1,
			weaponId = ultraLongString,
		})
		assert(res == false, "Must reject weaponId > 32 chars")
	end)

	assertSafe("ValidateHitPayload: Invalid direction magnitude", function()
		local res = CombatServer.ValidateHitPayload({
			origin = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, 0, 500),
			hitPosition = Vector3.new(0, 0, 10),
			distance = 10,
			clientTimestamp = 1.0,
			sequenceId = 1,
			weaponId = "Pistol",
		})
		assert(res == false, "Must reject direction magnitude outside [0.9, 1.1]")
	end)

	-- ------------------------------------------------------------------------
	-- TEST 2: ProcessReceipt Input Validation
	-- ------------------------------------------------------------------------
	local ReceiptProcessor = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("ReceiptProcessor") :: any)

	assertSafe("ProcessReceipt: nil receiptInfo", function()
		local res = ReceiptProcessor.ProcessReceipt(nil)
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must return NotProcessedYet")
	end)

	assertSafe("ProcessReceipt: negative PlayerId", function()
		local res = ReceiptProcessor.ProcessReceipt({
			PlayerId = -100,
			PlaceIdWherePurchased = 1,
			PurchaseId = "P123",
			ProductId = 5,
			CurrencySpent = 100,
			CurrencyType = Enum.CurrencyType.Robux,
		})
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must defer invalid PlayerId")
	end)

	assertSafe("ProcessReceipt: non-integer PlayerId", function()
		local res = ReceiptProcessor.ProcessReceipt({
			PlayerId = 123.456,
			PlaceIdWherePurchased = 1,
			PurchaseId = "P123",
			ProductId = 5,
			CurrencySpent = 100,
			CurrencyType = Enum.CurrencyType.Robux,
		})
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must defer non-integer PlayerId")
	end)

	assertSafe("ProcessReceipt: ultra-long PurchaseId", function()
		local res = ReceiptProcessor.ProcessReceipt({
			PlayerId = 1,
			PlaceIdWherePurchased = 1,
			PurchaseId = ultraLongString,
			ProductId = 5,
			CurrencySpent = 100,
			CurrencyType = Enum.CurrencyType.Robux,
		})
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must defer ultra-long PurchaseId")
	end)

	assertSafe("ProcessReceipt: negative CurrencySpent", function()
		local res = ReceiptProcessor.ProcessReceipt({
			PlayerId = 1,
			PlaceIdWherePurchased = 1,
			PurchaseId = "P123",
			ProductId = 5,
			CurrencySpent = -500,
			CurrencyType = Enum.CurrencyType.Robux,
		})
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must defer negative CurrencySpent")
	end)

	assertSafe("ProcessReceipt: NaN CurrencySpent", function()
		local res = ReceiptProcessor.ProcessReceipt({
			PlayerId = 1,
			PlaceIdWherePurchased = 1,
			PurchaseId = "P123",
			ProductId = 5,
			CurrencySpent = 0/0,
			CurrencyType = Enum.CurrencyType.Robux,
		})
		assert(res == Enum.ProductPurchaseDecision.NotProcessedYet, "Must defer NaN CurrencySpent")
	end)

	-- ------------------------------------------------------------------------
	-- TEST 3: QueueMatchmakingService RemoteFunctions Edge-Cases
	-- ------------------------------------------------------------------------
	local QueueMatchmakingService = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("QueueMatchmakingService") :: any)

	assertSafe("QueueEnter: nil player", function()
		local succ, msg = QueueMatchmakingService.EnterQueue(nil :: any, "1v1")
	end)

	assertSafe("QueueEnter: invalid queue mode string", function()
		local enterFn = QueueEvents.GetRemoteFunction("QueueEnter")
		if enterFn.OnServerInvoke then
			local ok1, msg1 = enterFn.OnServerInvoke(dummyPlayer :: any, "3v3_INVALID_MODE")
			assert(ok1 == false, "Must reject invalid queue mode")

			local ok2, msg2 = enterFn.OnServerInvoke(dummyPlayer :: any, nil)
			assert(ok2 == false, "Must reject nil queue mode")

			local ok3, msg3 = enterFn.OnServerInvoke(dummyPlayer :: any, ultraLongString)
			assert(ok3 == false, "Must reject ultra-long queue mode")
		end
	end)

	assertSafe("MapVoteSubmit: invalid map name and ultra-long matchId", function()
		local voteFn = QueueEvents.GetRemoteFunction("MapVoteSubmit")
		if voteFn.OnServerInvoke then
			local ok1, msg1 = voteFn.OnServerInvoke(dummyPlayer :: any, "MATCH_123", "NonExistentMap_SQL_INJECTION")
			assert(ok1 == false, "Must reject unallowed map name")

			local ok2, msg2 = voteFn.OnServerInvoke(dummyPlayer :: any, ultraLongString, "GreyboxArena")
			assert(ok2 == false, "Must reject ultra-long match ID")
		end
	end)

	-- ------------------------------------------------------------------------
	-- TEST 4: DirectChallengeService Listener Edge-Cases
	-- ------------------------------------------------------------------------
	local DirectChallengeService = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("DirectChallengeService") :: any)

	assertSafe("DirectChallengeService: SendChallenge self-challenge", function()
		local succ, err = DirectChallengeService.SendChallenge(dummyPlayer :: any, dummyPlayer :: any)
		assert(succ == false, "Must reject self-challenge")
	end)

	-- ------------------------------------------------------------------------
	-- TEST 5: OperativeService Listener Edge-Cases
	-- ------------------------------------------------------------------------
	local OperativeService = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("OperativeService") :: any)

	assertSafe("OperativeService.SelectOperative: nil player", function()
		local succ, msg = OperativeService.SelectOperative(nil :: any, "Vex")
		assert(succ == false, "Must reject nil player")
	end)

	assertSafe("OperativeService.SelectOperative: invalid operativeId & ultra-long string", function()
		local succ1, msg1 = OperativeService.SelectOperative(dummyPlayer :: any, "NonExistentOperative_GodMode")
		assert(succ1 == false, "Must reject non-existent operative")

		local succ2, msg2 = OperativeService.SelectOperative(dummyPlayer :: any, ultraLongString)
		assert(succ2 == false, "Must reject ultra-long operative ID")
	end)

	assertSafe("OperativeService.UseAbility: invalid slot", function()
		local succ, msg = OperativeService.UseAbility(dummyPlayer :: any, "SuperUltraSlot" :: any, nil)
		assert(succ == false, "Must reject invalid slot")
	end)

	assertSafe("OperativeService.UseAbility: nil player", function()
		local succ, msg = OperativeService.UseAbility(nil :: any, "Basic", nil)
		assert(succ == false, "Must reject nil player")
	end)

	-- ------------------------------------------------------------------------
	-- TEST 6: EconomyService Edge-Cases
	-- ------------------------------------------------------------------------
	local EconomyService = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("EconomyService") :: any)

	assertSafe("EconomyService.ProcessPurchaseRequest: invalid itemId", function()
		local succ, reason, bal = EconomyService.ProcessPurchaseRequest(dummyPlayer :: any, "Nuke_999999_Credits")
		assert(succ == false and reason == "InvalidItem", "Must reject uncataloged shop item")
	end)

	assertSafe("EconomyService.ProcessPurchaseRequest: ultra-long itemId", function()
		local succ, reason, bal = EconomyService.ProcessPurchaseRequest(dummyPlayer :: any, ultraLongString)
		assert(succ == false and reason == "InvalidItem", "Must reject ultra-long item ID")
	end)

	print("==================================================")
	print(`SUITE COMPLETED: {passed} PASSED, {failed} FAILED`)
	print("==================================================")

	return failed == 0, passed, failed, errors
end

return M4_NetworkSecurityTest
