--!strict
--[=[
    Project OVERCLOCK: FTUEAnalytics
    First-Time User Experience (FTUE) funnel tracking module.
    Logs onboarding milestones using AnalyticsWrapper.LogFunnelStepEvent.
    Also wires movement assists (coyote time, jump buffer, slide) for FTUE
    conversion and mechanic onboarding telemetry.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsWrapper = require(ReplicatedStorage:WaitForChild("Analytics"):WaitForChild("AnalyticsWrapper"))

local FTUEAnalytics = {}

export type StepInfo = {
	stepNumber: number,
	stepName: string,
}

local FUNNEL_NAME = "FTUE_Onboarding_Funnel"

FTUEAnalytics.Steps = {
	TUTORIAL_STARTED = "Tutorial_Started",
	TUTORIAL_COMPLETED = "Tutorial_Completed",
	FIRST_MATCH_JOINED = "First_Match_Joined",
	FIRST_MATCH_COMPLETED = "First_Match_Completed",
	FIRST_VICTORY = "First_Victory",
}

local STEP_DEFINITIONS: { [string]: number } = {
	[FTUEAnalytics.Steps.TUTORIAL_STARTED] = 1,
	[FTUEAnalytics.Steps.TUTORIAL_COMPLETED] = 2,
	[FTUEAnalytics.Steps.FIRST_MATCH_JOINED] = 3,
	[FTUEAnalytics.Steps.FIRST_MATCH_COMPLETED] = 4,
	[FTUEAnalytics.Steps.FIRST_VICTORY] = 5,
}

local _playerHighestStep: { [Player]: number } = {}
local _playerCompletedSteps: { [Player]: { [string]: boolean } } = {}

-- ── Movement assists telemetry (coyote / buffer / slide) ─────────────────────
export type MovementAssistType = "Coyote" | "Buffer" | "SlideAttempt" | "SlideSuccess"

FTUEAnalytics.Assists = {
	COYOTE = "Coyote" :: MovementAssistType,
	BUFFER = "Buffer" :: MovementAssistType,
	SLIDE_ATTEMPT = "SlideAttempt" :: MovementAssistType,
	SLIDE_SUCCESS = "SlideSuccess" :: MovementAssistType,
}

export type MovementAssistStats = {
	coyoteJumps: number,
	bufferedJumps: number,
	slideAttempts: number,
	slideSuccesses: number,
}

local _playerAssists: { [Player]: MovementAssistStats } = {}
local _globalSlideAttempts: number = 0
local _globalSlideSuccesses: number = 0

local function getOrCreateAssistStats(player: Player): MovementAssistStats
	local stats = _playerAssists[player]
	if not stats then
		stats = {
			coyoteJumps = 0,
			bufferedJumps = 0,
			slideAttempts = 0,
			slideSuccesses = 0,
		}
		_playerAssists[player] = stats
	end
	return stats
end

function FTUEAnalytics.GetStepNumber(stepName: string): number
	return STEP_DEFINITIONS[stepName] or 0
end

function FTUEAnalytics.GetPlayerStep(player: Player): number
	return _playerHighestStep[player] or 0
end

function FTUEAnalytics.HasCompletedStep(player: Player, stepName: string): boolean
	local completed = _playerCompletedSteps[player]
	if not completed then
		return false
	end
	return completed[stepName] == true
end

function FTUEAnalytics.TrackStep(
	player: Player,
	stepName: string,
	customData: { [string]: string }?
): (boolean, string?)
	local stepNumber = FTUEAnalytics.GetStepNumber(stepName)
	if stepNumber == 0 then
		warn("[FTUEAnalytics] Unknown step name: " .. tostring(stepName))
		return false, "Unknown step name"
	end

	if not _playerCompletedSteps[player] then
		_playerCompletedSteps[player] = {}
	end

	-- Track highest step reached
	local currentHighest = _playerHighestStep[player] or 0
	if stepNumber > currentHighest then
		_playerHighestStep[player] = stepNumber
	end

	_playerCompletedSteps[player][stepName] = true

	local success, err = AnalyticsWrapper.LogFunnelStepEvent(
		player,
		FUNNEL_NAME,
		stepNumber,
		stepName,
		customData
	)

	-- Basic integration point: when completing a step, also store it in the player's profile data
	-- (via a reference to ProfileServiceWrapper) so steps aren't re-triggered on rejoin.
	-- local ProfileServiceWrapper = require(script.Parent:WaitForChild("ProfileServiceWrapper"))
	-- local profile = ProfileServiceWrapper.GetProfile(player.UserId) -- Requires a getter in ProfileServiceWrapper
	-- if profile and profile.Data.FTUE then
	--     profile.Data.FTUE[stepName] = true
	-- end

	return success, err
end

function FTUEAnalytics.ResetPlayerProgress(player: Player)
	_playerHighestStep[player] = nil
	_playerCompletedSteps[player] = nil
	-- Also clear movement assists and adjust global slide counters
	local stats = _playerAssists[player]
	if stats then
		_globalSlideAttempts = math.max(0, _globalSlideAttempts - stats.slideAttempts)
		_globalSlideSuccesses = math.max(0, _globalSlideSuccesses - stats.slideSuccesses)
	end
	_playerAssists[player] = nil
end

-- ── Movement assists wiring ────────────────────────────────────────────────

function FTUEAnalytics.TrackMovementAssist(
	player: Player,
	assistType: string,
	customData: { [string]: string }?
): (boolean, string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if typeof(assistType) ~= "string" then
		return false, "Invalid assist type"
	end
	local stats = getOrCreateAssistStats(player)
	local eventName: string? = nil
	if assistType == FTUEAnalytics.Assists.COYOTE or assistType == "Coyote" or assistType == "CoyoteJump" then
		stats.coyoteJumps += 1
		eventName = "FTUE_CoyoteJump"
	elseif assistType == FTUEAnalytics.Assists.BUFFER or assistType == "Buffer" or assistType == "BufferedJump" then
		stats.bufferedJumps += 1
		eventName = "FTUE_BufferedJump"
	elseif assistType == FTUEAnalytics.Assists.SLIDE_ATTEMPT or assistType == "SlideAttempt" then
		stats.slideAttempts += 1
		_globalSlideAttempts += 1
		eventName = "FTUE_SlideAttempt"
	elseif assistType == FTUEAnalytics.Assists.SLIDE_SUCCESS or assistType == "SlideSuccess" then
		stats.slideSuccesses += 1
		_globalSlideSuccesses += 1
		eventName = "FTUE_SlideSuccess"
	else
		-- Generic slide alias: "Slide" counts as success
		if assistType == "Slide" then
			stats.slideAttempts += 1
			stats.slideSuccesses += 1
			_globalSlideAttempts += 1
			_globalSlideSuccesses += 1
			eventName = "FTUE_SlideSuccess"
		else
			return false, "Unknown assist type"
		end
	end

	-- Log via AnalyticsWrapper as custom event for cardinality-safe telemetry
	local data: { [string]: string } = {}
	if customData then
		for k, v in customData do
			data[k] = v
		end
	end
	data["assistType"] = assistType
	-- Bin counts into categories for analytics cardinality safety via wrapper sanitization
	local ok, err = AnalyticsWrapper.LogCustomEvent(player, eventName :: string, 1, data)
	return ok, err
end

function FTUEAnalytics.TrackCoyoteJump(player: Player, customData: { [string]: string }?): (boolean, string?)
	return FTUEAnalytics.TrackMovementAssist(player, FTUEAnalytics.Assists.COYOTE, customData)
end

function FTUEAnalytics.TrackBufferedJump(player: Player, customData: { [string]: string }?): (boolean, string?)
	return FTUEAnalytics.TrackMovementAssist(player, FTUEAnalytics.Assists.BUFFER, customData)
end

function FTUEAnalytics.TrackSlideAttempt(player: Player, customData: { [string]: string }?): (boolean, string?)
	return FTUEAnalytics.TrackMovementAssist(player, FTUEAnalytics.Assists.SLIDE_ATTEMPT, customData)
end

function FTUEAnalytics.TrackSlideSuccess(player: Player, customData: { [string]: string }?): (boolean, string?)
	return FTUEAnalytics.TrackMovementAssist(player, FTUEAnalytics.Assists.SLIDE_SUCCESS, customData)
end

-- Legacy alias: TrackSlide counts as successful slide (for wiring from kernel when isSliding becomes true)
function FTUEAnalytics.TrackSlide(player: Player, customData: { [string]: string }?): (boolean, string?)
	return FTUEAnalytics.TrackSlideSuccess(player, customData)
end

function FTUEAnalytics.GetMovementAssistStats(player: Player): MovementAssistStats
	local stats = _playerAssists[player]
	if not stats then
		return {
			coyoteJumps = 0,
			bufferedJumps = 0,
			slideAttempts = 0,
			slideSuccesses = 0,
		}
	end
	-- Return copy to prevent external mutation
	return {
		coyoteJumps = stats.coyoteJumps,
		bufferedJumps = stats.bufferedJumps,
		slideAttempts = stats.slideAttempts,
		slideSuccesses = stats.slideSuccesses,
	}
end

function FTUEAnalytics.GetSlideSuccessRate(player: Player): number
	local stats = _playerAssists[player]
	if not stats then
		return 0
	end
	if stats.slideAttempts == 0 then
		return if stats.slideSuccesses > 0 then 1 else 0
	end
	return stats.slideSuccesses / stats.slideAttempts
end

function FTUEAnalytics.GetGlobalSlideSuccessRate(): number
	if _globalSlideAttempts == 0 then
		return if _globalSlideSuccesses > 0 then 1 else 0
	end
	return _globalSlideSuccesses / _globalSlideAttempts
end

function FTUEAnalytics.GetGlobalMovementAssistStats(): { attempts: number, successes: number, rate: number }
	return {
		attempts = _globalSlideAttempts,
		successes = _globalSlideSuccesses,
		rate = FTUEAnalytics.GetGlobalSlideSuccessRate(),
	}
end

function FTUEAnalytics.GetAssistCounts(player: Player): MovementAssistStats
	return FTUEAnalytics.GetMovementAssistStats(player)
end

function FTUEAnalytics.ResetMovementAssists(player: Player)
	-- Adjust global counters when resetting a single player
	local stats = _playerAssists[player]
	if stats then
		_globalSlideAttempts = math.max(0, _globalSlideAttempts - stats.slideAttempts)
		_globalSlideSuccesses = math.max(0, _globalSlideSuccesses - stats.slideSuccesses)
	end
	_playerAssists[player] = nil
end

function FTUEAnalytics.ResetAllMovementAssists()
	table.clear(_playerAssists)
	_globalSlideAttempts = 0
	_globalSlideSuccesses = 0
end

-- Hidden MMR decay metric passthrough (FTUEAnalytics aggregates matchmaking health)
function FTUEAnalytics.GetHiddenMMRDecayMetric(): { totalDecay: number, decayEvents: number, lastDecayAmount: number, averageDecay: number }
	local ok, coord = pcall(function()
		return require(script.Parent:WaitForChild("MatchmakingCoordinator"))
	end)
	if ok and coord and coord.GetHiddenMMRDecayMetric then
		return coord.GetHiddenMMRDecayMetric()
	end
	-- Fallback empty metric if coordinator not available (Studio test)
	return { totalDecay = 0, decayEvents = 0, lastDecayAmount = 0, averageDecay = 0 }
end

function FTUEAnalytics.GetHiddenMMRDecayRate(): number
	local ok, coord = pcall(function()
		return require(script.Parent:WaitForChild("MatchmakingCoordinator"))
	end)
	if ok and coord and coord.GetHiddenMMRDecayPerDay then
		return coord.GetHiddenMMRDecayPerDay()
	end
	return 8
end

-- Clean up on player disconnect
Players.PlayerRemoving:Connect(function(player: Player)
	FTUEAnalytics.ResetPlayerProgress(player)
end)

return FTUEAnalytics
