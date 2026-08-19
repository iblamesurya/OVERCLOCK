--!strict
--[=[
    Unit Tests for RoundService
    Validates round state machine phase transitions, match lifecycle (1v1 / 2v2),
    team elimination round end evaluation, loss streak updates, sudden-death handling (6-6 tie),
    and match completion rules (first to 7).
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local RoundService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("RoundService") :: any)
local EconomyService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("EconomyService") :: any)

local function runTests()
	RoundService.Init()
	EconomyService.Init()

	local p1 = Instance.new("Player")
	p1.Name = "RSTestPlayer1"

	local p2 = Instance.new("Player")
	p2.Name = "RSTestPlayer2"

	-- 1. Test Key Phase Duration Constants
	assert(RoundService.BUY_PHASE_DURATION == 15, "BUY_PHASE_DURATION should be 15s")
	assert(RoundService.LIVE_PHASE_DURATION == 60, "LIVE_PHASE_DURATION should be 60s")
	assert(RoundService.ROUND_END_DURATION == 5, "ROUND_END_DURATION should be 5s")
	assert(RoundService.INTERMISSION_DURATION == 3, "INTERMISSION_DURATION should be 3s")
	assert(RoundService.TARGET_SCORE == 7, "TARGET_SCORE should be 7")
	assert(RoundService.SUDDEN_DEATH_TIE_SCORE == 6, "SUDDEN_DEATH_TIE_SCORE should be 6")

	-- 2. Test Match Initialization
	local matchId = "TestMatch_101"
	local match = RoundService.StartMatch(matchId, "1v1", { p1 }, { p2 })

	assert(match ~= nil, "Match object should be created")
	assert(match.matchId == matchId, "Match ID should match")
	assert(match.currentRound == 1, "Match current round should start at 1")
	assert(match.team1Score == 0, "Team 1 score should be 0")
	assert(match.team2Score == 0, "Team 2 score should be 0")
	assert(match.phase == "Buy", "Initial phase should be Buy")
	assert(match.isSuddenDeath == false, "Initial round should not be sudden death")

	-- Check starting credits (Pistol Round = 800)
	assert(EconomyService.GetCredits(p1) == 800, "P1 should start pistol round with 800 credits")
	assert(EconomyService.GetCredits(p2) == 800, "P2 should start pistol round with 800 credits")

	-- 3. Test Mid-Round Player Elimination & Winner Evaluation
	match.phase = "Live"
	RoundService.OnPlayerDied(p2, p1) -- p2 killed by p1

	assert(match.team1Score == 1, "Team 1 score should be incremented to 1")
	assert(match.team2Score == 0, "Team 2 score should remain 0")
	assert(match.team1LossStreak == 0, "Team 1 loss streak should be reset to 0")
	assert(match.team2LossStreak == 1, "Team 2 loss streak should be incremented to 1")
	assert(match.winningTeam == 1, "Winning team should be 1")
	assert(EconomyService.GetCredits(p1) == 800 + 3000 + 200, "P1 should get 800 + 3000 (win) + 200 (kill) = 4000 credits")

	-- 4. Test Sudden Death Initialization via CheckSuddenDeath (6-6 Tie)
	match.team1Score = 6
	match.team2Score = 6
	match.isMatchOver = false
	match.phase = "Buy"

	local isSD = RoundService.CheckSuddenDeath(match)

	assert(isSD == true, "CheckSuddenDeath should return true for 6-6 tie")
	assert(match.isSuddenDeath == true, "6-6 tie should trigger sudden death state")
	assert(EconomyService.GetCredits(p1) == 5000, "Sudden death starting credits for p1 should be 5000")
	assert(EconomyService.GetCredits(p2) == 5000, "Sudden death starting credits for p2 should be 5000")

	-- 5. Test Match Completion (First to 7)
	match.team1Score = 6
	match.team2Score = 5
	match.phase = "Live"

	RoundService.EvaluateRoundEnd(match, 1) -- Team 1 wins 7th round

	assert(match.team1Score == 7, "Team 1 score should reach 7")
	assert(match.isMatchOver == true, "Match should be marked as over when target score reached")

	-- Cleanup
	p1:Destroy()
	p2:Destroy()

	print("[RoundService.spec] All unit tests passed successfully!")
	return true
end

runTests()
return true
