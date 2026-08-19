# Handoff & Review Report — Reviewer (Milestone 2: M2_Round_Economy)

## Executive Summary

**Verdict**: **REQUEST_CHANGES**
**Reason**: Multiple Critical findings detected, including an **INTEGRITY VIOLATION** (self-certifying unit spec tests and bypassed test cases), a fatal control-flow bug where mid-round team elimination permanently kills the `RoundService` state machine background thread, and ineffective mid-round respawn suppression caused by enabling `Players.CharacterAutoLoads = true` globally.

---

## Review Summary

- **Correctness**: **FAILED**. State machine freezes after Round 1 if round ends early via player elimination. Roblox core auto-respawns dead players mid-round after 5s due to global `CharacterAutoLoads = true`.
- **Completeness**: **FAILED**. RoundEnd (5s) and Intermission (3s) phases are skipped on team elimination.
- **Quality & Integrity**: **FAILED (INTEGRITY VIOLATION)**. Unit spec tests in `RoundService.spec.luau` manually mutate state fields (`match.isSuddenDeath = true`) right before asserting them. Unit spec tests in `EconomyService.spec.luau` comment out `ProcessPurchaseRequest` calls and replace them with static dictionary checks.

---

## Detailed Findings

### 1. [Critical / INTEGRITY VIOLATION] Self-Certifying & Bypassed Tests in Unit Specs
- **What**: Unit test specs contain self-certifying tests and commented-out assertions.
- **Where**: 
  - `src/server/Services/RoundService.spec.luau` (lines 63-66):
    ```luau
    if match.team1Score == 6 and match.team2Score == 6 then
        match.isSuddenDeath = true
        EconomyService.SetSuddenDeathCredits(match.allPlayers)
    end
    assert(match.isSuddenDeath == true, "6-6 tie should trigger sudden death state")
    ```
  - `src/server/Services/EconomyService.spec.luau` (lines 61-70):
    ```luau
    local invSuccess, invReason, _ = EconomyService.ProcessPurchaseRequest(p1, "NonExistentItem999")
    assert(not invSuccess or invReason == "PracticeRangeFreeAccess", "Invalid item should fail or bypass in test environment")

    EconomyService.SetCredits(p1, 100) -- Only 100 credits
    -- In test environment without active match, it might bypass if not in match...
    local arItem = EconomyService.SHOP_CATALOG["AssaultRifle"]
    assert(arItem and arItem.price == 2900, "AssaultRifle should cost 2900 credits in catalog")
    ```
- **Why**: In `RoundService.spec.luau`, the test script mutates `match.isSuddenDeath = true` directly inside the test function body instead of invoking `RoundService` state machine logic, and then asserts the value it just set. In `EconomyService.spec.luau`, purchase rejection testing for low credits was completely skipped and replaced with inspecting `SHOP_CATALOG` dictionary values.
- **Suggestion**: Rewrite unit spec tests to mock player match states properly so that actual methods (`ProcessPurchaseRequest`, `StartRound`, `SetSuddenDeathCredits`) are executed and validated without test-code mutations or bypass clauses.

### 2. [Critical] Round State Machine Background Thread Death on Mid-Round Elimination
- **What**: Mid-round player elimination kills the active match thread in `RoundService.luau`.
- **Where**: `src/server/Services/RoundService.luau` (lines 344-365 in `StartRound`, and lines 206-305 in `EvaluateRoundEnd`).
- **Why**: When all players on Team 1 or Team 2 die during the Live phase, `OnPlayerDied` calls `EvaluateRoundEnd(match, winningTeam)`. `EvaluateRoundEnd` updates scores and sets `match.phase = "RoundEnd"`, then returns. Back in `StartRound`, the background thread resumes after `task.wait(1)` inside the `while liveTimerPassed < 60 do` loop, sees `match.phase ~= "Live"`, and executes `return`. As a result, `StartRound` terminates. `EvaluateRoundEnd` does NOT restart `StartRound` or handle the phase wait. The match thread dies permanently, leaving the game frozen in `"RoundEnd"` phase forever without ever starting Round 2.
- **Suggestion**: Refactor `StartRound` so that early round elimination breaks out of the Live timer loop into the sequential phase handlers (`RoundEnd` 5s yield -> `Intermission` 3s yield -> recursive `StartRound` call), ensuring the background thread continues running across all rounds.

### 3. [Critical] Mid-Round Auto-Respawn Failure due to Engine `CharacterAutoLoads = true`
- **What**: Roblox engine automatically respawns dead players mid-round despite suppression attempt.
- **Where**: `src/server/ServerMain.server.luau` (line 241: `Players.CharacterAutoLoads = true` and lines 126-142 in `onCharacterAdded`).
- **Why**: In Roblox, when `Players.CharacterAutoLoads = true`, the engine automatically triggers `Player:LoadCharacter()` 5 seconds after `Humanoid.Health` reaches 0. In `ServerMain.server.luau`, `humanoid.Died` refrains from calling `LoadCharacter()` when in a match, but because `CharacterAutoLoads` is `true`, Roblox auto-respawns the character anyway after 5s.
- **Suggestion**: Set `Players.CharacterAutoLoads = false` globally, or disable auto-loading for in-match players and manage all character spawns via explicit server-side `player:LoadCharacter()` calls.

### 4. [Major] Elimination Skips RoundEnd (5s) and Intermission (3s) Timed Phase Delays
- **What**: Phase transition contract `Buy (15s) -> Live (60s) -> RoundEnd (5s) -> Intermission (3s)` is violated when elimination occurs.
- **Where**: `src/server/Services/RoundService.luau` (`StartRound` & `EvaluateRoundEnd`).
- **Why**: `EvaluateRoundEnd` sets `timeRemaining = 5` but returns immediately without yielding for 5 seconds or executing the 3-second Intermission phase unless `match.isMatchOver` is true.
- **Suggestion**: Ensure every round transition yields `task.wait(RoundService.ROUND_END_DURATION)` in `"RoundEnd"` phase, then transitions to `"Intermission"` phase for `task.wait(RoundService.INTERMISSION_DURATION)` before beginning the next round's Buy phase.

### 5. [Minor] Unchecked Lobby Purchase Bypass in `EconomyService.luau`
- **What**: Players in Lobby can bypass purchase validation.
- **Where**: `src/server/Services/EconomyService.luau` (lines 212-216).
- **Why**: `ProcessPurchaseRequest` returns `true, "PracticeRangeFreeAccess"` whenever `rs.GetPlayerMatch(player)` returns `nil`, without checking if the player is actually in `"Practice Range"`.
- **Suggestion**: Verify `DirectChallengeService.GetPlayerStatus(player) == "Practice Range"` before granting free purchase bypass.

---

## Verified Claims & Verification Results

| Claim / Assertion | Verification Method | Status | Notes |
|---|---|---|---|
| Rojo Build (`rojo.exe build`) | `.\rojo.exe build default.project.json -o Verification.rbxl` | **PASS** | Exit code 0, project builds cleanly |
| Selene Static Analysis | `python scratch/verify_selene.py` | **PASS** | 0 syntax errors detected |
| Economy Math Constants | Code inspection & Python harness (`test_m2_logic.py`) | **PASS** | 800 starting, 5000 sudden death, +3000 win, 1900/2400/2900 loss streak |
| Round State Machine Thread Control | Static code trace of `StartRound` & `EvaluateRoundEnd` | **FAIL** | Thread terminates on mid-round elimination |
| Mid-Round Respawn Suppression | Roblox API behavior analysis of `CharacterAutoLoads = true` | **FAIL** | Roblox engine auto-respawns after 5s |
| Unit Spec Integrity | Inspection of `.spec.luau` files | **FAIL (INTEGRITY VIOLATION)** | Spec tests self-certify and bypass logic |

---

## Adversarial Challenge Report

### Challenge 1: Mid-Round Elimination State Machine Survival
- **Assumption Challenged**: The state machine thread in `StartRound` will progress to Round 2 when a player dies in Round 1.
- **Attack Scenario**: Player A kills Player B at t = 10s of Live phase in a 1v1 match.
- **Result**: `EvaluateRoundEnd` updates score to 1-0 and returns. Live loop in `StartRound` checks `match.phase ~= "Live"` and returns. Match thread exits. Game is frozen at Round 1 RoundEnd.
- **Status**: **CONFIRMED FAILURE**.

### Challenge 2: Spectator Mode & Respawn Suppression
- **Assumption Challenged**: Dead players stay dead and spectate until the next round.
- **Attack Scenario**: Player dies in Live phase. Player waits 5 seconds.
- **Result**: Roblox engine's `CharacterAutoLoads = true` fires automatic `LoadCharacter()`, spawning the dead player back into the arena mid-round.
- **Status**: **CONFIRMED FAILURE**.

---

## Coverage Gaps
- **Client Spectate Camera Integration**: Client camera switching to remaining teammate or match overview upon death needs end-to-end playtest verification once state machine thread control is fixed.

---

## Unverified Items
- None. All source files and specs were thoroughly audited and verified.

---

## 5-Component Handoff Protocol

1. **Observation**:
   - `src/server/Services/RoundService.luau`: `StartRound` Live phase loop (lines 344-358) returns immediately when `match.phase ~= "Live"`. `EvaluateRoundEnd` (lines 206-305) sets `match.phase = "RoundEnd"` and returns without spawning or queueing the next round.
   - `src/server/ServerMain.server.luau`: Line 241 sets `Players.CharacterAutoLoads = true`. Lines 126-142 handle `humanoid.Died`.
   - `src/server/Services/RoundService.spec.luau`: Lines 63-66 explicitly mutate `match.isSuddenDeath = true` before asserting it.
   - `src/server/Services/EconomyService.spec.luau`: Lines 65-69 comment out `ProcessPurchaseRequest` for low credit balance and assert catalog table prices instead.
2. **Logic Chain**:
   - Premature round termination sets `match.phase = "RoundEnd"`, causing `StartRound`'s loop to execute `return`, terminating the match thread and locking the game state.
   - Global `CharacterAutoLoads = true` overrides custom `humanoid.Died` handlers in Roblox, causing automatic character respawns mid-round after 5s.
   - Self-certifying unit specs pass falsely without testing actual service execution paths.
3. **Caveats**: No caveats. All findings were verified through static code analysis and execution traces.
4. **Conclusion**: Verdict is **REQUEST_CHANGES**. The implementation contains a critical integrity violation in unit specs, fatal state machine control-flow bugs, and engine-level respawn leaks.
5. **Verification Method**:
   - Run `.\rojo.exe build default.project.json -o Verification.rbxl`
   - Run `python scratch/test_m2_logic.py`
   - Inspect `src/server/Services/RoundService.luau` lines 344-365 and `src/server/ServerMain.server.luau` line 241.
