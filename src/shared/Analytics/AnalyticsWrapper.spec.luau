--!strict
--[=[
    Unit Tests for AnalyticsWrapper
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsWrapper = require(ReplicatedStorage:WaitForChild("Analytics"):WaitForChild("AnalyticsWrapper"))

local function runTests()
	AnalyticsWrapper.ResetState()
	AnalyticsWrapper.SetTestMode(true)

	-- 1. Test Binning Functions
	local pingBin = AnalyticsWrapper.BinPing(15)
	assert(pingBin == "<25ms", "Expected <25ms, got: " .. tostring(pingBin))

	local pingBin2 = AnalyticsWrapper.BinPing(150)
	assert(pingBin2 == "100-199ms", "Expected 100-199ms, got: " .. tostring(pingBin2))

	local playtimeBin = AnalyticsWrapper.BinPlaytime(1200)
	assert(playtimeBin == "15-30m", "Expected 15-30m, got: " .. tostring(playtimeBin))

	local kdBin = AnalyticsWrapper.BinKDRatio(1.8)
	assert(kdBin == "1.50-2.49", "Expected 1.50-2.49, got: " .. tostring(kdBin))

	local damageBin = AnalyticsWrapper.BinDamage(750)
	assert(damageBin == "500-999", "Expected 500-999, got: " .. tostring(damageBin))

	local currencyBin = AnalyticsWrapper.BinCurrency(250)
	assert(currencyBin == "200-999", "Expected 200-999, got: " .. tostring(currencyBin))

	-- 2. Test Custom Data Sanitization & Cardinality
	local rawData = {
		rawFloat = "123.456",
		epochTime = "1722600000",
		category = "Competitive",
	}
	local sanitized = AnalyticsWrapper.SanitizeCustomData(rawData)
	assert(sanitized.category == "Competitive", "Expected 'Competitive', got: " .. tostring(sanitized.category))
	assert(sanitized.rawFloat ~= "123.456", "Raw float should have been binned into discrete category")
	assert(sanitized.epochTime == "Timestamp_Binned", "Epoch timestamp should be binned")

	-- 3. Test Rate Limiting Budget
	local budget = AnalyticsWrapper.GetRateLimitBudget()
	assert(budget >= 140, "Expected budget >= 140, got: " .. tostring(budget))

	AnalyticsWrapper.ResetState()
	print("[AnalyticsWrapper.spec] All tests passed!")
end

runTests()
return true
