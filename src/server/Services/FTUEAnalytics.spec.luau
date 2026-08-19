--!strict
--[=[
    Unit Tests for FTUEAnalytics
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FTUEAnalytics = require(ServerScriptService:WaitForChild("Services"):WaitForChild("FTUEAnalytics"))
local AnalyticsWrapper = require(ReplicatedStorage:WaitForChild("Analytics"):WaitForChild("AnalyticsWrapper"))

local function runTests()
	AnalyticsWrapper.SetTestMode(true)

	-- Mock Player Instance for testing
	local mockPlayer = Instance.new("Player")
	mockPlayer.Name = "TestFTUEPlayer"

	-- 1. Test Step Numbers
	assert(FTUEAnalytics.GetStepNumber("Tutorial_Started") == 1, "Tutorial_Started step number must be 1")
	assert(FTUEAnalytics.GetStepNumber("First_Match_Joined") == 3, "First_Match_Joined step number must be 3")
	assert(FTUEAnalytics.GetStepNumber("Invalid_Step") == 0, "Invalid step should return 0")

	-- 2. Test Step Tracking
	local success, err = FTUEAnalytics.TrackStep(mockPlayer, FTUEAnalytics.Steps.TUTORIAL_STARTED)
	assert(success, "TrackStep failed: " .. tostring(err))
	assert(FTUEAnalytics.GetPlayerStep(mockPlayer) == 1, "Player step should be 1")
	assert(FTUEAnalytics.HasCompletedStep(mockPlayer, FTUEAnalytics.Steps.TUTORIAL_STARTED), "Player should have completed Tutorial_Started")

	local success2, _ = FTUEAnalytics.TrackStep(mockPlayer, FTUEAnalytics.Steps.FIRST_MATCH_COMPLETED)
	assert(success2, "TrackStep for Step 4 failed")
	assert(FTUEAnalytics.GetPlayerStep(mockPlayer) == 4, "Player highest step should be 4")

	-- 3. Test Progress Reset
	FTUEAnalytics.ResetPlayerProgress(mockPlayer)
	assert(FTUEAnalytics.GetPlayerStep(mockPlayer) == 0, "Player step after reset should be 0")
	assert(not FTUEAnalytics.HasCompletedStep(mockPlayer, FTUEAnalytics.Steps.TUTORIAL_STARTED), "Completed step should be false after reset")

	mockPlayer:Destroy()
	print("[FTUEAnalytics.spec] All tests passed!")
end

runTests()
return true
