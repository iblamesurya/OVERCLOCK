# Handoff Report — Explorer Survey 3 (Network Security & Startup Smoke Test)

## 1. Observation

### Exact File Locations & Key Code Sections
1. **Remote Definitions**:
   - `src/shared/Network/RemoteEvents.luau` (lines 9–21): Defines `reliableNames` (26 events) and `unreliableNames` (5 events). Creates folder `NetworkRemotes` in `ReplicatedStorage`.
   - `src/shared/Network/QueueEvents.luau` (lines 56–66): Defines `RELIABLE_EVENT_NAMES` (3 events) and `REMOTE_FUNCTION_NAMES` (3 functions). Creates folder `QueueRemotes` in `ReplicatedStorage`.
   - `src/shared/Network/ChallengeEvents.luau` (lines 62–68): Defines `RELIABLE_EVENT_NAMES` (5 events). Creates folder `ChallengeRemotes` in `ReplicatedStorage`.
2. **Server Boot & Remote Initialization**:
   - `src/server/ServerMain.server.luau` (lines 50–53):
     ```luau
     RemoteEvents.Initialize()
     QueueEvents.Initialize()
     ChallengeEvents.Initialize()
     ```
     This initialization occurs *after* map files (`GreyboxArenaMap`, `LobbyFolder`, `MapRegistry`, `DuelArenaMap`, `PracticeRangeMapLayout`) are required at top of file (lines 19–24).
3. **Client Remote Imports & Race Conditions**:
   - `src/client/ClientMain.client.luau` (lines 31–33):
     ```luau
     local QueueEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("QueueEvents") :: any)
     local ChallengeEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("ChallengeEvents") :: any)
     local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)
     ```
   - Client scripts call `getOrCreateFolder()` which executes `ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)`. If the server is delayed loading map modules, client boot hits 10-second `WaitForChild` timeout or errors (`NetworkRemotes folder not found`).
4. **Server Listener Audit Observations**:
   - `src/server/Combat/CombatServer.luau` (line 424): `ReliableCombat` validates payload table, action, rate limits `FireWeapon` (10/20s), vector types, origin distance (<=50 studs), and calls `HitValidation.ValidateHit`.
   - `src/server/Services/BotService.luau` (line 532): Also listens to `ReliableCombat` and accesses `payload.hitData.targetInstance` directly without checking `typeof(targetInst) == "Instance"`.
   - `src/server/Services/QueueMatchmakingService.luau` (lines 549, 557, 562): Handles `QueueEnter`, `QueueLeave`, `MapVoteSubmit`.
   - `src/server/Services/DirectChallengeService.luau` (lines 346, 357, 365): Handles `ChallengeSend`, `ChallengeRespond`, `ChallengeCancel`. `ChallengeSend` does not check `targetUserId ~= player.UserId` or apply rate limits.
   - `src/server/ServerMain.server.luau` (lines 399–535): Handles 10 listeners (`PlayerDeath`, `MatchPhaseTransition`, `EnterPracticeRange`, `LeavePracticeRange`, `SelectAgent`, `UseAbility`, `SwitchWeapon`, `SwitchOperative`, `RequestPurchase`, `ResetRangeStats`). `EnterPracticeRange` lacks player match state check; `UseAbility` lacks slot string enum check and server cooldown enforcement; `SelectAgent` lacks registry validation against `OperativeStats`.
5. **Existing Test Files Observed**:
   - `src/server/Tests/OverclockVerificationSuite.luau` (146 lines): Master test runner for stats and economy constants.
   - `src/server/Tests/M1_DamageTest.luau` (131 lines): Damage falloff, headshot multiplier, and 50% armor absorption test suite.
   - `src/server/Tests/M3_OperativeTest.luau`: Operative ability verification.
   - `src/server/Combat/M2_TestRunner.luau`: Lag compensation & rollback buffer test suite.
   - 15 unit spec files (`src/server/Services/*.spec.luau`, `src/shared/Map/*.spec.luau`).

---

## 2. Logic Chain

1. **Observation 1 & 3**: Network remotes are currently created across 3 separate folders (`NetworkRemotes`, `QueueRemotes`, `ChallengeRemotes`) in `ReplicatedStorage`.
2. **Observation 2**: Requirement R4 mandates unifying all remotes under `ReplicatedStorage/Network/Remotes` and ensuring server initialization happens before client UI `WaitForChild`.
3. **Logic Step**: Because client UI controllers load immediately upon player join, any delay in server map loading causes client `WaitForChild("NetworkRemotes", 10)` to timeout. Moving remote initialization to Stage `[BOOT] 1/6` of `ServerMain` and unifying under `ReplicatedStorage/Network/Remotes` guarantees remotes exist before clients attempt to connect.
4. **Observation 4**: Server listener audit revealed:
   - `BotService.luau:532` accesses `payload.hitData.targetInstance` without `typeof` checking, creating a crash vector.
   - `DirectChallengeService.luau:346` permits self-challenges (`targetUserId == player.UserId`) and lacks rate limiting.
   - `ServerMain.server.luau:417` permits `EnterPracticeRange` without checking if player is currently in a 1v1/2v2 match.
   - `ServerMain.server.luau:478` permits `UseAbility` without validating `data.slot` ("Basic", "Paid", "Ultimate") or target position.
5. **Logic Step**: Strengthening server-side listeners with strict type guards, state checks, rate limits, and bounds checks fulfills requirement R4 ("Add robust server-side validation to all RemoteEvent.OnServerEvent listeners").
6. **Observation 5 & Requirement R6**: The existing test suite provides unit specs and verification scripts, but lacks an automated boot smoke test.
7. **Logic Step**: Implementing `StartupSmokeTest` in `ServerScriptService/Tests/StartupSmokeTest.luau` to validate services, remote availability, map folder existence, and raycast floor collision satisfies requirement R6.

---

## 3. Caveats

- **No Code Modifications Made**: As an Explorer subagent, no project code files in `src/` were edited; all proposed designs and test scripts are documented in `analysis.md` and `handoff.md`.
- **Live Client Context**: Remote event network latency under real Roblox network conditions cannot be measured offline; verification relies on static analysis and local Studio test suites.

---

## 4. Conclusion

- The OVERCLOCK codebase features 42 total network channels (34 reliable RemoteEvents, 5 UnreliableRemoteEvents, 3 RemoteFunctions).
- Remotes must be unified into `ReplicatedStorage/Network/Remotes` and created in Stage `[BOOT] 1/6` to eliminate client `WaitForChild` race conditions.
- Four critical listener vulnerabilities were identified (`BotService` unvalidated instance access, `DirectChallengeService` self-challenge/rate-limit gap, `EnterPracticeRange` mid-match escape, `UseAbility` unvalidated payload/cooldown).
- Complete design of `StartupSmokeTest.luau` is delivered to validate network remotes (`[NETWORK] All required remotes available`), map floor collision (`[MAP] Every spawn has collidable floor`), and spawn authority (`[SPAWN] Player -> Lobby`).

---

## 5. Verification Method

1. **Verify Network Folder Structure**:
   - Inspect `ReplicatedStorage/Network/Remotes` after server boot.
   - Confirm 34 RemoteEvents, 5 UnreliableRemoteEvents, and 3 RemoteFunctions are present under `ReplicatedStorage.Network.Remotes`.
2. **Verify Server Boot Output**:
   - Boot server in Roblox Studio.
   - Confirm output displays:
     - `[BOOT] 1/6 Network remotes initialized`
     - `[NETWORK] All required remotes available`
     - `[MAP] Every spawn has collidable floor`
     - `[SPAWN] Player -> Lobby`
     - `[BOOT] 6/6 Server ready`
3. **Run Test Suites**:
   - Execute `require(game:GetService("ServerScriptService").Tests.StartupSmokeTest).Run()` in Roblox Studio command bar. Confirm 100% pass result.
   - Execute `require(game:GetService("ServerScriptService").Tests.OverclockVerificationSuite)` and `M1_DamageTest`.
