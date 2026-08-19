--!strict
--[=[
    Project OVERCLOCK: AnalyticsWrapper
    Wraps AnalyticsService with global rate limiting awareness (120 + 20 * CCU req/min)
    and strict cardinality management (binning continuous variables into discrete categories).
]=]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local AnalyticsWrapper = {}

local _requestTimestamps: { number } = {}
local _isTestMode: boolean = false
local _loggedEventsCount: number = 0

-- Rate limit configuration constants
local BASE_RATE_LIMIT_PER_MIN = 120
local CCU_RATE_LIMIT_MULTIPLIER = 20
local SLIDING_WINDOW_SECONDS = 60

local PING_THRESHOLDS = { 25, 50, 100, 200 }
local PING_LABELS = { "<25ms", "25-49ms", "50-99ms", "100-199ms", "200ms+" }

local PLAYTIME_THRESHOLDS = { 60, 300, 900, 1800 }
local PLAYTIME_LABELS = { "<1m", "1-5m", "5-15m", "15-30m", "30m+" }

local KD_THRESHOLDS = { 0.5, 1.0, 1.5, 2.5 }
local KD_LABELS = { "<0.50", "0.50-0.99", "1.00-1.49", "1.50-2.49", "2.50+" }

local DAMAGE_THRESHOLDS = { 100, 500, 1000, 2500 }
local DAMAGE_LABELS = { "0-99", "100-499", "500-999", "1000-2499", "2500+" }

local CURRENCY_THRESHOLDS = { 50, 200, 1000, 5000 }
local CURRENCY_LABELS = { "1-49", "50-199", "200-999", "1000-4999", "5000+" }

local function pruneOldTimestamps(now: number)
	local cutoff = now - SLIDING_WINDOW_SECONDS
	local writeIdx = 1
	for readIdx = 1, #_requestTimestamps do
		if _requestTimestamps[readIdx] >= cutoff then
			_requestTimestamps[writeIdx] = _requestTimestamps[readIdx]
			writeIdx += 1
		end
	end
	for i = #_requestTimestamps, writeIdx, -1 do
		_requestTimestamps[i] = nil
	end
end

function AnalyticsWrapper.GetRateLimitBudget(): number
	local playerList = Players:GetPlayers()
	local ccu = math.max(1, #playerList)
	return BASE_RATE_LIMIT_PER_MIN + (CCU_RATE_LIMIT_MULTIPLIER * ccu)
end

local function checkAndConsumeRateLimit(): boolean
	local now = os.clock()
	pruneOldTimestamps(now)

	local maxBudget = AnalyticsWrapper.GetRateLimitBudget()
	if #_requestTimestamps >= maxBudget then
		return false
	end

	table.insert(_requestTimestamps, now)
	return true
end

function AnalyticsWrapper.BinValue(value: number, thresholds: { number }, labels: { string }): string
	for i, threshold in thresholds do
		if value < threshold then
			return labels[i]
		end
	end
	return labels[#labels]
end

function AnalyticsWrapper.BinPing(pingMs: number): string
	return AnalyticsWrapper.BinValue(pingMs, PING_THRESHOLDS, PING_LABELS)
end

function AnalyticsWrapper.BinPlaytime(seconds: number): string
	return AnalyticsWrapper.BinValue(seconds, PLAYTIME_THRESHOLDS, PLAYTIME_LABELS)
end

function AnalyticsWrapper.BinKDRatio(kd: number): string
	return AnalyticsWrapper.BinValue(kd, KD_THRESHOLDS, KD_LABELS)
end

function AnalyticsWrapper.BinDamage(damage: number): string
	return AnalyticsWrapper.BinValue(damage, DAMAGE_THRESHOLDS, DAMAGE_LABELS)
end

function AnalyticsWrapper.BinCurrency(amount: number): string
	return AnalyticsWrapper.BinValue(amount, CURRENCY_THRESHOLDS, CURRENCY_LABELS)
end

function AnalyticsWrapper.SanitizeCustomData(customData: { [string]: string }?): { [string]: string }
	local sanitized: { [string]: string } = {}
	if not customData then
		return sanitized
	end

	local count = 0
	for key, val in customData do
		if count >= 10 then
			break
		end

		local cleanKey = string.sub(tostring(key), 1, 32)
		local valStr = tostring(val)

		-- Strict cardinality management: convert raw floats or timestamps into discrete binned categories
		local numVal = tonumber(valStr)
		if numVal then
			if string.find(valStr, "%.") or numVal > 1000000000 then
				-- Raw float or epoch timestamp detected -> bin into discrete string
				if numVal > 1000000000 then
					valStr = "Timestamp_Binned"
				else
					valStr = AnalyticsWrapper.BinValue(numVal, { 1, 10, 50, 100, 500 }, { "<1", "1-9", "10-49", "50-99", "100-499", "500+" })
				end
			end
		end

		sanitized[cleanKey] = string.sub(valStr, 1, 64)
		count += 1
	end

	return sanitized
end

function AnalyticsWrapper.LogCustomEvent(
	player: Player,
	eventName: string,
	value: number?,
	customData: { [string]: string }?
): (boolean, string?)
	if not checkAndConsumeRateLimit() then
		warn("[AnalyticsWrapper] Rate limit exceeded for event: " .. eventName)
		return false, "Rate limit exceeded"
	end

	local sanitizedCustom = AnalyticsWrapper.SanitizeCustomData(customData)
	_loggedEventsCount += 1

	if _isTestMode then
		return true, nil
	end

	local success, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, sanitizedCustom)
	end)

	if not success then
		warn("[AnalyticsWrapper] LogCustomEvent failed: " .. tostring(err))
		return false, tostring(err)
	end

	return true, nil
end

function AnalyticsWrapper.LogEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyName: string,
	amount: number,
	itemSKU: string,
	customData: { [string]: string }?
): (boolean, string?)
	if not checkAndConsumeRateLimit() then
		warn("[AnalyticsWrapper] Rate limit exceeded for economy event: " .. currencyName)
		return false, "Rate limit exceeded"
	end

	local sanitizedCustom = AnalyticsWrapper.SanitizeCustomData(customData)
	-- Ensure currency amount is integer
	local discreteAmount = math.floor(math.abs(amount))
	_loggedEventsCount += 1

	if _isTestMode then
		return true, nil
	end

	local success, err = pcall(function()
		AnalyticsService:LogEconomyEvent(player, flowType, currencyName, discreteAmount, 0, Enum.AnalyticsEconomyTransactionType.Default, itemSKU, sanitizedCustom)
	end)

	if not success then
		warn("[AnalyticsWrapper] LogEconomyEvent failed: " .. tostring(err))
		return false, tostring(err)
	end

	return true, nil
end

function AnalyticsWrapper.LogFunnelStepEvent(
	player: Player,
	funnelName: string,
	stepNumber: number,
	stepName: string,
	customData: { [string]: string }?
): (boolean, string?)
	if not checkAndConsumeRateLimit() then
		warn("[AnalyticsWrapper] Rate limit exceeded for funnel step: " .. stepName)
		return false, "Rate limit exceeded"
	end

	local sanitizedCustom = AnalyticsWrapper.SanitizeCustomData(customData)
	_loggedEventsCount += 1

	if _isTestMode then
		return true, nil
	end

	local success, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, stepNumber, stepName, sanitizedCustom)
	end)

	if not success then
		warn("[AnalyticsWrapper] LogFunnelStepEvent failed: " .. tostring(err))
		return false, tostring(err)
	end

	return true, nil
end

function AnalyticsWrapper.SetTestMode(enabled: boolean)
	_isTestMode = enabled
end

function AnalyticsWrapper.GetLoggedEventsCount(): number
	return _loggedEventsCount
end

function AnalyticsWrapper.ResetState()
	table.clear(_requestTimestamps)
	_loggedEventsCount = 0
	_isTestMode = false
end

return AnalyticsWrapper
