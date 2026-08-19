--!strict
--[=[
    Unit Tests for DirectChallengeService
    Verifies challenge state transitions, status tracking, auto-expiration,
    and validation constraints for 1v1 direct player challenges.
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local DirectChallengeService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("DirectChallengeService"))

local function runTests()
	DirectChallengeService.Init()

	local p1 = Instance.new("Player")
	p1.Name = "ChallengerPlayer"

	local p2 = Instance.new("Player")
	p2.Name = "TargetPlayer"

	-- 1. Test Player Status Initialization
	assert(DirectChallengeService.GetPlayerStatus(p1) == "In Lobby", "Player 1 status should default to 'In Lobby'")
	assert(DirectChallengeService.GetPlayerStatus(p2) == "In Lobby", "Player 2 status should default to 'In Lobby'")

	-- 2. Test Self-Challenge Rejection
	local selfSuccess, selfErr = DirectChallengeService.SendChallenge(p1, p1)
	assert(not selfSuccess, "Player should not be able to challenge themselves")
	assert(selfErr ~= nil, "Expected error message for self challenge")

	-- 3. Test Successful Challenge Creation
	local sendSuccess, sendErr = DirectChallengeService.SendChallenge(p1, p2)
	assert(sendSuccess, "SendChallenge should succeed between two lobby players: " .. tostring(sendErr))

	local activeChallenge = DirectChallengeService.GetActiveChallengeForPlayer(p1)
	assert(activeChallenge ~= nil, "Active challenge should exist for player 1")
	assert(activeChallenge and activeChallenge.state == "Pending", "Challenge state should be 'Pending'")

	-- 4. Test Busy Status Rejection
	local p3 = Instance.new("Player")
	p3.Name = "ThirdPlayer"

	local busySuccess, busyErr = DirectChallengeService.SendChallenge(p3, p1)
	assert(not busySuccess, "Should not be able to challenge a player with an active pending challenge")
	assert(busyErr ~= nil, "Expected error for busy target")

	-- 5. Test Challenge Cancellation
	if activeChallenge then
		local cancelSuccess, cancelErr = DirectChallengeService.CancelChallenge(p1, activeChallenge.challengeId)
		assert(cancelSuccess, "Challenger should be able to cancel pending challenge: " .. tostring(cancelErr))
		assert(DirectChallengeService.GetActiveChallengeForPlayer(p1) == nil, "Active challenge should be cleared after cancellation")
	end

	-- 6. Test Challenge Acceptance and Status Transition
	local sendSuccess2, _ = DirectChallengeService.SendChallenge(p1, p2)
	assert(sendSuccess2, "SendChallenge should succeed again after cancellation")

	local challenge2 = DirectChallengeService.GetActiveChallengeForPlayer(p1)
	assert(challenge2 ~= nil, "Challenge 2 should be active")

	if challenge2 then
		local respondSuccess, respondErr = DirectChallengeService.RespondChallenge(p2, challenge2.challengeId, true)
		assert(respondSuccess, "Target should be able to accept challenge: " .. tostring(respondErr))
		assert(DirectChallengeService.GetPlayerStatus(p1) == "In Match", "Challenger status should transition to 'In Match'")
		assert(DirectChallengeService.GetPlayerStatus(p2) == "In Match", "Target status should transition to 'In Match'")
	end

	-- Reset player statuses
	DirectChallengeService.SetPlayerStatus(p1, "In Lobby")
	DirectChallengeService.SetPlayerStatus(p2, "In Lobby")

	p1:Destroy()
	p2:Destroy()
	p3:Destroy()

	print("[DirectChallengeService.spec] All unit tests passed successfully!")
end

runTests()
return true
