--!strict
--[=[
    Unit Tests for SocialInviteService
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local SocialInviteService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("SocialInviteService"))

local function runTests()
	SocialInviteService.ResetState()
	SocialInviteService.SetTestMode(true)

	-- 1. Test Launch Data Encoding & Decoding
	local testPayload = {
		inv = 12345678,
		t = 1722600000,
		src = "viral_invite_test",
	}

	local encodedStr = SocialInviteService.EncodeLaunchData(testPayload)
	assert(typeof(encodedStr) == "string", "Encoded launch data must be string")
	assert(#encodedStr <= 200, "Encoded launch data must be <= 200 chars, got: " .. tostring(#encodedStr))

	local decodedPayload = SocialInviteService.DecodeLaunchData(encodedStr)
	assert(decodedPayload ~= nil, "Decoded payload must not be nil")
	assert(decodedPayload and decodedPayload.inv == 12345678, "Inviter UserId mismatch")
	assert(decodedPayload and decodedPayload.src == "viral_invite_test", "Source mismatch")

	-- 2. Test Player Join Intercept & Reward Referral
	local mockJoiningPlayer = Instance.new("Player")
	mockJoiningPlayer.Name = "InvitedPlayer"

	SocialInviteService.InjectMockJoinData(mockJoiningPlayer, encodedStr)

	local rewardAwarded = false
	local awardedInviterId = 0
	local awardedJoiningId = 0

	SocialInviteService.SetReferralRewardCallback(function(inviterId, joiningId, amount)
		rewardAwarded = true
		awardedInviterId = inviterId
		awardedJoiningId = joiningId
		assert(amount == 100, "Expected reward amount 100")
	end)

	local joinProcessed = SocialInviteService.ProcessPlayerJoin(mockJoiningPlayer)
	assert(joinProcessed, "ProcessPlayerJoin should succeed for valid LaunchData")
	assert(rewardAwarded, "Referral reward callback should have been invoked")
	assert(awardedInviterId == 12345678, "Awarded inviter ID mismatch")
	assert(SocialInviteService.GetProcessedCount() == 1, "Processed count should be 1")

	-- 3. Test Duplicate Referral Prevention
	local duplicateProcessed = SocialInviteService.ProcessPlayerJoin(mockJoiningPlayer)
	assert(not duplicateProcessed, "Duplicate referral processing should be rejected")
	assert(SocialInviteService.GetProcessedCount() == 1, "Processed count should remain 1")

	mockJoiningPlayer:Destroy()
	SocialInviteService.ResetState()
	print("[SocialInviteService.spec] All tests passed!")
end

runTests()
return true
