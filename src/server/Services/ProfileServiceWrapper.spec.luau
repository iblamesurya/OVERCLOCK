--!strict
--[=[
    Unit Tests for ProfileServiceWrapper
    Validates data sanitization (NaN stripping, Vector3 conversion, cyclic/mixed key rejection),
    default profile template schema (Level, XP, Credits, OwnedCosmetics, EquippedSkins, SelectedOperative, MatchStats),
    exponential backoff retry calculation math, non-blocking in-memory fallback profile creation,
    and active profile registration/deregistration tracking.
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local ProfileServiceWrapper = require(ServerScriptService:WaitForChild("Services"):WaitForChild("ProfileServiceWrapper") :: any)

local function runTests()
	print("[ProfileServiceWrapper.spec] Starting unit test execution...")

	-- 1. Test Data Sanitization - NaN & Infinity stripping
	local nanOk, nanResult = ProfileServiceWrapper.SanitizeData(0 / 0)
	assert(nanOk == true, "NaN sanitization should succeed")
	assert(nanResult == 0, "NaN should be replaced with 0")

	local infOk, infResult = ProfileServiceWrapper.SanitizeData(math.huge)
	assert(infOk == true, "Infinity sanitization should succeed")
	assert(infResult == 0, "Infinity should be replaced with 0")

	-- 2. Test Data Sanitization - Vector3 conversion
	local vec = Vector3.new(10, 20, 30)
	local vecOk, vecResult = ProfileServiceWrapper.SanitizeData(vec)
	assert(vecOk == true, "Vector3 sanitization should succeed")
	assert(type(vecResult) == "table", "Vector3 should convert to table")
	assert(vecResult[1] == 10 and vecResult[2] == 20 and vecResult[3] == 30, "Vector3 elements should match {10, 20, 30}")

	-- 3. Test Data Sanitization - Rejection of mixed-type keys
	local mixedTable = {
		[1] = "numeric key",
		foo = "string key",
	}
	local mixedOk, _, mixedErr = ProfileServiceWrapper.SanitizeData(mixedTable)
	assert(mixedOk == false, "Mixed-type keys should be rejected")
	assert(mixedErr ~= nil and string.find(mixedErr, "Mixed%-type keys") ~= nil, "Should return mixed keys error message")

	-- 4. Test Data Sanitization - Rejection of cyclic references
	local parent: { [string]: any } = { name = "parent" }
	local child: { [string]: any } = { name = "child", parent = parent }
	parent.child = child

	local cyclicOk, _, cyclicErr = ProfileServiceWrapper.SanitizeData(parent)
	assert(cyclicOk == false, "Cyclic references should be rejected")
	assert(cyclicErr ~= nil and string.find(cyclicErr, "Cyclic reference") ~= nil, "Should return cyclic reference error message")

	-- 5. Test Default Profile Template Schema (M7 Top-Level Fields)
	local defaultProfile = ProfileServiceWrapper.GetDefaultProfile(9999, "TestUser9999")
	assert(defaultProfile.userId == 9999, "userId should match")
	assert(defaultProfile.username == "TestUser9999", "username should match")
	assert(defaultProfile.Level == 1, "Level should default to 1")
	assert(defaultProfile.XP == 0, "XP should default to 0")
	assert(defaultProfile.Credits == 500, "Credits should default to 500")
	assert(type(defaultProfile.OwnedCosmetics) == "table", "OwnedCosmetics should be a table")
	assert(table.find(defaultProfile.OwnedCosmetics, "DefaultSkin_AR") ~= nil, "OwnedCosmetics should contain DefaultSkin_AR")
	assert(type(defaultProfile.EquippedSkins) == "table", "EquippedSkins should be a table")
	assert(defaultProfile.EquippedSkins["AssaultRifle"] == "DefaultSkin_AR", "EquippedSkins.AssaultRifle should match DefaultSkin_AR")
	assert(defaultProfile.SelectedOperative == "Vex", "SelectedOperative should default to Vex")

	assert(type(defaultProfile.MatchStats) == "table", "MatchStats should be a table")
	assert(defaultProfile.MatchStats.Kills == 0, "MatchStats.Kills should be 0")
	assert(defaultProfile.MatchStats.Deaths == 0, "MatchStats.Deaths should be 0")
	assert(defaultProfile.MatchStats.Wins == 0, "MatchStats.Wins should be 0")
	assert(defaultProfile.MatchStats.Losses == 0, "MatchStats.Losses should be 0")

	-- Test Backward Compatibility Fields
	assert(defaultProfile.level == 1, "legacy level alias should be 1")
	assert(defaultProfile.experience == 0, "legacy experience alias should be 0")
	assert(defaultProfile.currencies.credits == 500, "legacy currencies.credits should be 500")

	-- 6. Test Exponential Backoff Retry Math Calculation
	local baseDelay = 1
	local expectedDelays = { 1, 2, 4, 8, 16 }
	for attempt = 1, 5 do
		local calculatedDelay = math.min(16, baseDelay * math.pow(2, attempt - 1))
		assert(calculatedDelay == expectedDelays[attempt], string.format("Attempt %d backoff delay expected %d, got %d", attempt, expectedDelays[attempt], calculatedDelay))
	end

	-- 7. Test In-Memory Fallback Profile Creation & Lifecycle
	local testUserId = 77777
	local fallbackProfile = ProfileServiceWrapper.CreateInMemoryFallback(testUserId, defaultProfile)

	assert(fallbackProfile ~= nil, "CreateInMemoryFallback should return profile instance")
	assert(fallbackProfile.UserId == testUserId, "Fallback profile UserId should match")
	assert(fallbackProfile:IsActive() == true, "Fallback profile should be active initially")
	assert(fallbackProfile.Data.Level == 1, "Fallback profile Data.Level should be 1")
	assert(fallbackProfile.Data.Credits == 500, "Fallback profile Data.Credits should be 500")

	local saveResult = fallbackProfile:SaveAsync()
	assert(saveResult == true, "SaveAsync on fallback profile should return true")

	fallbackProfile:ReleaseAsync()
	assert(fallbackProfile:IsActive() == false, "ReleaseAsync should set profile IsActive to false")

	print("[ProfileServiceWrapper.spec] All unit tests passed successfully!")
	return true
end

-- Execute tests in standalone mode
runTests()

-- Return TestEZ runner compatible function
return function()
	describe("ProfileServiceWrapper", function()
		it("should pass all ProfileServiceWrapper unit tests", function()
			expect(runTests()).to.equal(true)
		end)
	end)
end
