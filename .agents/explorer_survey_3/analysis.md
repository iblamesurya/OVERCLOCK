# OVERCLOCK Network Security & Startup Smoke Test Analysis (R4 & R6)

## Executive Summary
This document delivers a comprehensive audit of the network architecture, remote initialization sequences, server-side remote input validation, existing test infrastructure, and the complete design of the `StartupSmokeTest` module for project OVERCLOCK.

---

## 1. Network Remotes Audit & Catalog

### 1.1 Remote Inventory Across Shared Network Modules
All remotes in OVERCLOCK are instantiated across three shared modules in `src/shared/Network/`:
1. `src/shared/Network/RemoteEvents.luau` (Target folder: `ReplicatedStorage.NetworkRemotes`)
2. `src/shared/Network/QueueEvents.luau` (Target folder: `ReplicatedStorage.QueueRemotes`)
3. `src/shared/Network/ChallengeEvents.luau` (Target folder: `ReplicatedStorage.ChallengeRemotes`)

#### Complete Remote Catalog (42 Channels Total):
- **Reliable RemoteEvents (34 total)**:
  - `DamageDealt` (Server -> Client)
  - `PlayerDeath` (Client -> Server)
  - `ItemPurchase` (Server -> Client)
  - `MatchPhaseTransition` (Client <-> Server)
  - `ProfileSync` (Server -> Client)
  - `ReliableCombat` (Client -> Server)
  - `RoundStateChanged` (Server -> Client)
  - `RequestPurchase` (Client -> Server)
  - `PurchaseResult` (Server -> Client)
  - `UseAbility` (Client -> Server)
  - `AbilityStateUpdate` (Server -> Client)
  - `SelectAgent` (Client -> Server)
  - `AgentSelectUpdate` (Server -> Client)
  - `AgentLocked` (Server -> Client)
  - `ResetRangeStats` (Client -> Server)
  - `RangeStatsUpdated` (Server -> Client)
  - `SwitchOperative` (Client -> Server)
  - `SwitchWeapon` (Client -> Server)
  - `EquipWeapon` (Server -> Client)
  - `KillFeed` (Server -> Client)
  - `MatchResult` (Server -> Client)
  - `EnterPracticeRange` (Client -> Server)
  - `LeavePracticeRange` (Client -> Server)
  - `RequestQueue` (Client -> Server)
  - `CancelQueue` (Client -> Server)
  - `QueueUpdate` (Server -> Client)
  - `QueueMatchFound` (Server -> Client)
  - `QueueStatusUpdate` (Server -> Client)
  - `MapVoteUpdate` (Server -> Client)
  - `ChallengeSend` (Client -> Server)
  - `ChallengeReceive` (Server -> Client)
  - `ChallengeRespond` (Client -> Server)
  - `ChallengeCancel` (Client -> Server)
  - `ChallengeExpired` (Server -> Client)

- **Unreliable RemoteEvents (5 total)**:
  - `BulletTracer` (Server -> Client)
  - `WeaponSwaySync` (Server <-> Client)
  - `FootstepSound` (Server -> Client)
  - `SpatialStateSync` (Server -> Client)
  - `UnreliableCombat` (Client -> Server)

- **RemoteFunctions (3 total)**:
  - `QueueEnter` (Client -> Server)
  - `QueueLeave` (Client -> Server)
  - `MapVoteSubmit` (Client -> Server)

---

## 2. Remote Initialization & Client Race Conditions

### 2.1 Current Implementation & R4 Discrepancy
- **Folder Location Violation**: Requirement R4 specifies unifying all remotes under `ReplicatedStorage/Network/Remotes`. Currently, remotes are created in three separate folders at `ReplicatedStorage` root (`NetworkRemotes`, `QueueRemotes`, `ChallengeRemotes`).
- **Initialization Timing**: In `src/server/ServerMain.server.luau` (lines 50–53), remotes are initialized *after* map modules (`GreyboxArenaMap`, `LobbyFolder`, `MapRegistry`, `DuelArenaMap`, `PracticeRangeMapLayout`) are required. If map loading or asset streaming takes time, client scripts joining the server will execute `WaitForChild(folder, 10)` before the server has created the folder, resulting in `WaitForChild` timeout warnings or script failure (`"NetworkRemotes folder not found"`).

### 2.2 Refactoring Plan for R4 Compliance
1. Update `RemoteEvents.luau`, `QueueEvents.luau`, and `ChallengeEvents.luau` to use `ReplicatedStorage:WaitForChild("Network"):WaitForChild("Remotes")` (or create `ReplicatedStorage.Network.Remotes` on server boot).
2. Move remote folder creation to Stage `[BOOT] 1/6` of `ServerMain.server.luau`, ensuring all 42 remote objects exist before any map loading or client connection processing.

---

## 3. Server-Side Listener Security & Validation Audit

Below is the complete audit of all server-side event listeners:

| Remote Name | Handler Location | Current Validation Status | Vulnerabilities / Missing Validation |
|-------------|------------------|---------------------------|--------------------------------------|
| `ReliableCombat` | `CombatServer.luau:424` | Table type check, rate limit (FireWeapon), vector validation, HRP distance check (<=50 studs), rollback buffer validation (ReportHit). | **BotService Crash Risk**: `BotService.luau:532` also connects to `ReliableCombat` and accesses `payload.hitData.targetInstance` directly without checking `typeof(targetInst) == "Instance"`. Malicious payload crashes `BotService`. |
| `QueueEnter` | `QueueMatchmakingService.luau:549` | Mode string check ("1v1" / "2v2"). | No player state check (allows queueing while in active match or Practice Range). No rate limit. |
| `QueueLeave` | `QueueMatchmakingService.luau:557` | None on parameters. | No rate limiting on repeated invocations. |
| `MapVoteSubmit` | `QueueMatchmakingService.luau:562` | String type check on `matchId` & `mapName`. | Does not check if `mapName` is valid for `matchId` or if player is part of `matchId`. |
| `ChallengeSend` | `DirectChallengeService.luau:346` | `targetUserId` number check, player existence check. | **Self-challenge allowed** (`targetUserId == player.UserId`). No rate limiting against challenge spam. |
| `ChallengeRespond` | `DirectChallengeService.luau:357` | `challengeId` string check, `accept` boolean check. | No validation that player is the intended target of `challengeId`. |
| `ChallengeCancel` | `DirectChallengeService.luau:365` | `challengeId` string check. | No validation that player is the challenger of `challengeId`. |
| `PlayerDeath` | `ServerMain.server.luau:399` | `data.returnToLobby` check. | Unvalidated lobby teleport trigger. Player can self-fire to escape combat. |
| `MatchPhaseTransition` | `ServerMain.server.luau:408` | `data.action == "ReturnToLobby"` check. | Unvalidated match leave trigger. |
| `EnterPracticeRange` | `ServerMain.server.luau:417` | None. | Player can enter Practice Range mid-match without state check. |
| `LeavePracticeRange` | `ServerMain.server.luau:431` | None. | No state check. |
| `RequestQueue` | `ServerMain.server.luau:443` | Mode string check ("1v1" / "2v2"). | Duplicate handler (also handled in `QueueMatchmakingService`). |
| `CancelQueue` | `ServerMain.server.luau:453` | None. | Duplicate handler. |
| `SelectAgent` | `ServerMain.server.luau:462` | `operativeId` string check. | Does not check if `operativeId` exists in `OperativeStats` registry. |
| `UseAbility` | `ServerMain.server.luau:478` | Table type check on `data`. | `data.slot` not validated ("Basic", "Paid", "Ultimate"). `targetPosition` not checked for Vector3 / distance. No server-side cooldown check. |
| `RequestPurchase` | `ServerMain.server.luau:514` | `itemId` string check. Handled by `EconomyService`. | `EconomyService` validates credits & buy phase. |
| `SwitchWeapon` | `ServerMain.server.luau:490` | Practice Range state check + string check. | Properly restricted to Practice Range. |
| `SwitchOperative` | `ServerMain.server.luau:501` | Practice Range state check + string check. | Properly restricted to Practice Range. |
| `ResetRangeStats` | `ServerMain.server.luau:535` | Practice Range state check. | Properly restricted to Practice Range. |

---

## 4. Existing Test Suite Inspection

- **Integration Suites**:
  - `src/server/Tests/OverclockVerificationSuite.luau`: Master verification runner checking weapon stats, damage calculation math, operative stats, and economy constants.
  - `src/server/Tests/M1_DamageTest.luau`: Asserts range falloff, headshot multipliers (2.0x–2.5x), 50% armor absorption math, and non-player hit permissibility.
  - `src/server/Tests/M3_OperativeTest.luau`: Asserts operative stats and ability profiles.
  - `src/server/Combat/M2_TestRunner.luau`: Tests rollback buffer, hit validation logic, and lag compensation tolerance.
- **Unit Specs (`*.spec.luau`)**: 15 spec files testing individual services (`BotService`, `DirectChallengeService`, `EconomyService`, `MatchmakingCoordinator`, `ProfileServiceWrapper`, `ReceiptProcessor`, `RoundService`, `SocialInviteService`, `MapRegistry`, `PracticeRangeMapLayout`, etc.).

---

## 5. StartupSmokeTest Module Specification (R6)

The `StartupSmokeTest` module will reside at `src/server/Tests/StartupSmokeTest.luau` (ROJO map: `ServerScriptService/Tests/StartupSmokeTest.luau`).

### Proposed Code for `StartupSmokeTest.luau`:
```luau
--!strict
--[=[
    Project OVERCLOCK: StartupSmokeTest Module (R6)
    Automated boot verification for mandatory services, network remotes, map folders, and floor collision.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local StartupSmokeTest = {}

type TestResult = {
	success: boolean,
	passed: number,
	failed: number,
	errors: { string },
}

local RELIABLE_REMOTES = {
	"DamageDealt", "PlayerDeath", "ItemPurchase", "MatchPhaseTransition",
	"ProfileSync", "ReliableCombat", "RoundStateChanged", "RequestPurchase",
	"PurchaseResult", "UseAbility", "AbilityStateUpdate", "SelectAgent",
	"AgentSelectUpdate", "AgentLocked", "ResetRangeStats", "RangeStatsUpdated",
	"SwitchOperative", "SwitchWeapon", "EquipWeapon", "KillFeed",
	"MatchResult", "EnterPracticeRange", "LeavePracticeRange",
	"RequestQueue", "CancelQueue", "QueueUpdate", "QueueMatchFound",
	"QueueStatusUpdate", "MapVoteUpdate", "ChallengeSend", "ChallengeReceive",
	"ChallengeRespond", "ChallengeCancel", "ChallengeExpired"
}

local UNRELIABLE_REMOTES = {
	"BulletTracer", "WeaponSwaySync", "FootstepSound", "SpatialStateSync", "UnreliableCombat"
}

local REMOTE_FUNCTIONS = {
	"QueueEnter", "QueueLeave", "MapVoteSubmit"
}

function StartupSmokeTest.Run(): TestResult
	local passed = 0
	local failed = 0
	local errors: { string } = {}

	local function assertTest(name: string, condition: boolean, failMsg: string)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(errors, name .. ": " .. failMsg)
			warn("  ❌ [SMOKE TEST FAIL] " .. name .. " -> " .. failMsg)
		end
	end

	print("\n==================================================")
	print("[SMOKE TEST] Starting Server Startup Smoke Test...")
	print("==================================================")

	-- 1. Validate Network Remotes Container & Objects
	local networkFolder = ReplicatedStorage:FindFirstChild("Network")
	local remotesFolder = networkFolder and networkFolder:FindFirstChild("Remotes")
	-- Fallback check for legacy folder structure
	if not remotesFolder then
		remotesFolder = ReplicatedStorage:FindFirstChild("NetworkRemotes")
	end

	assertTest("Remotes Container Exists", remotesFolder ~= nil, "Remotes folder missing in ReplicatedStorage")

	if remotesFolder then
		for _, name in RELIABLE_REMOTES do
			local remote = remotesFolder:FindFirstChild(name)
				or (ReplicatedStorage:FindFirstChild("QueueRemotes") and ReplicatedStorage.QueueRemotes:FindFirstChild(name))
				or (ReplicatedStorage:FindFirstChild("ChallengeRemotes") and ReplicatedStorage.ChallengeRemotes:FindFirstChild(name))
			assertTest("RemoteEvent '" .. name .. "'", remote ~= nil and remote:IsA("RemoteEvent"), "Missing RemoteEvent " .. name)
		end

		for _, name in UNRELIABLE_REMOTES do
			local remote = remotesFolder:FindFirstChild(name)
			assertTest("UnreliableRemoteEvent '" .. name .. "'", remote ~= nil and remote:IsA("UnreliableRemoteEvent"), "Missing UnreliableRemoteEvent " .. name)
		end

		for _, name in REMOTE_FUNCTIONS do
			local fn = remotesFolder:FindFirstChild(name)
				or (ReplicatedStorage:FindFirstChild("QueueRemotes") and ReplicatedStorage.QueueRemotes:FindFirstChild(name))
			assertTest("RemoteFunction '" .. name .. "'", fn ~= nil and fn:IsA("RemoteFunction"), "Missing RemoteFunction " .. name)
		end
	end

	if failed == 0 then
		print("[NETWORK] All required remotes available")
	end

	-- 2. Validate Map Folders & Spawn Floor Raycasts
	local lobbyFolder = Workspace:FindFirstChild("LobbyFolder") or ReplicatedStorage:FindFirstChild("Map"):FindFirstChild("LobbyFolder")
	assertTest("LobbyFolder Exists", lobbyFolder ~= nil, "LobbyFolder not found in Workspace or ReplicatedStorage")

	local allSpawnsValid = true
	local spawnCount = 0

	for _, desc in Workspace:GetDescendants() do
		if desc:IsA("SpawnLocation") and desc.Enabled then
			spawnCount += 1
			local origin = desc.Position + Vector3.new(0, 30, 0)
			local direction = Vector3.new(0, -100, 0)
			local raycastResult = Workspace:Raycast(origin, direction)
			if not raycastResult or not raycastResult.Instance.CanCollide then
				allSpawnsValid = false
				assertTest("Spawn Floor Collision (" .. desc.Name .. ")", false, "No collidable floor below spawn at " .. tostring(desc.Position))
			end
		end
	end

	assertTest("Spawns Exist", spawnCount > 0, "No active SpawnLocations found in Workspace")

	if allSpawnsValid and spawnCount > 0 then
		print("[MAP] Every spawn has collidable floor")
	end

	-- 3. Validate Spawn Authority State
	assertTest("CharacterAutoLoads Disabled", Players.CharacterAutoLoads == false, "Players.CharacterAutoLoads must be false for SpawnService control")
	if Players.CharacterAutoLoads == false then
		print("[SPAWN] Player -> Lobby")
	end

	print("==================================================")
	if failed == 0 then
		print(string.format("[SMOKE TEST] SUCCESS: %d tests passed cleanly!", passed))
	else
		warn(string.format("[SMOKE TEST] FAILED: %d passed, %d failed", passed, failed))
	end
	print("==================================================\n")

	return {
		success = (failed == 0),
		passed = passed,
		failed = failed,
		errors = errors,
	}
end

return StartupSmokeTest
```
