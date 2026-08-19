# OVERCLOCK Project Refactor: Explorer Survey Report (R1 & R5)

**Author:** Explorer Subagent  
**Date:** 2026-08-04  
**Target:** Server Boot Sequence & Structural Separation (R1 & R5)  
**Workspace:** `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_survey_1`

---

## Executive Summary

This report provides a comprehensive analysis of the Roblox OVERCLOCK tactical shooter codebase focusing on **Server Boot Reliability (R1)** and **Structural Separation (R5)**. Based on static inspection of `src/server/ServerMain.server.luau`, `src/server/Services/`, `src/server/Combat/`, `src/shared/`, `src/client/`, and `default.project.json`, we have identified critical infinite yield vulnerabilities, unhandled requiring bugs, un-staged boot logic, and structural gaps. A 6-stage boot architecture with an enhanced `safeInit()` wrapper and `safeRequire()` helper is proposed, along with a complete directory tree reorganization audit.

---

## Section 1: Server Initialization Logic Audit

### 1.1 Core Boot Architecture (`src/server/ServerMain.server.luau`)
Current entry point location: `src/server/ServerMain.server.luau` (558 lines).

The current server initialization flow follows this order:
1. **Module Requiring (Lines 9–45)**:
   - Uses `safeRequire(parent, childName)` helper:
     ```luau
     local function safeRequire(parent: Instance, childName: string): any
         local child = parent:WaitForChild(childName)
         local success, result = pcall(require, child)
         if not success then
             warn("[BOOT ERROR] Failed to require " .. childName .. ": " .. tostring(result))
             return nil
         end
         return result
     end
     ```
   - Requires Map modules from `ReplicatedStorage.Map`: `GreyboxArenaMap`, `LobbyFolder`, `MapRegistry`, `DuelArenaMap`, `PracticeRangeMapLayout`.
   - Requires `CombatServer` from `ServerScriptService.Combat`.
   - Requires Service modules from `ServerScriptService.Services`: `ProfileServiceWrapper`, `ReceiptProcessor`, `SocialInviteService`, `MatchmakingCoordinator`, `QueueMatchmakingService`, `DirectChallengeService`, `RoundService`, `EconomyService`, `OperativeService`, `BotService`.
   - Requires Network modules from `ReplicatedStorage.Network`: `RemoteEvents`, `QueueEvents`, `ChallengeEvents`.

2. **Network Remotes Setup (Lines 50–53)**:
   - Executes `RemoteEvents.Initialize()`, `QueueEvents.Initialize()`, `ChallengeEvents.Initialize()`.

3. **Map Construction & Floor Verification (Lines 55–104)**:
   - Executes `MapRegistry.AutoRegisterDefaultMaps()`.
   - Builds `GreyboxArenaMap` and `LobbyFolder`.
   - Runs inline `verifyLobbyFloor()` helper (casting raycasts downwards from lobby spawns).
   - Attempts `DuelArenaMap.BuildMap` and `PracticeRangeMapLayout.BuildMap` inside `pcall`.

4. **Baseplate & Catch Floor Fallbacks (Lines 113–136)**:
   - Instantiates `FallbackBaseplate` (Y=95, size 3000x4x3000).
   - Instantiates `DIAGNOSTIC_LOBBY_CATCH_FLOOR` (Y=80, size 4000x10x4000).

5. **Combat & Service Initialization (Lines 138–169)**:
   - Creates `combatServerInstance = CombatServer.new()`.
   - Calls `safeInit(name, fn)` for:
     - `ReceiptProcessor.Init()`
     - `SocialInviteService.Init()`
     - `MatchmakingCoordinator.StartService()`
     - `QueueMatchmakingService.Initialize()`
     - `DirectChallengeService.Init()`
     - `EconomyService.Init(RoundService, combatServerInstance)`
     - `RoundService.Init(combatServerInstance)`
     - `OperativeService.Init()`
     - `BotService.Init()`
   - Note on current `safeInit` implementation (Lines 143–152):
     ```luau
     local function safeInit(name: string, fn: () -> ())
         task.spawn(function()
             local ok, err = pcall(fn)
             if ok then
                 print("[ServerMain] " .. name .. " initialized.")
             else
                 warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
             end
         end)
     end
     ```
     *Problem:* Fires background tasks asynchronously without staging, synchronization, sequence tracking, or logging steps `[BOOT] 1/6` .. `[BOOT] 6/6 Server ready`.

6. **Player Spawning & Remote Handlers (Lines 170–557)**:
   - Inline definitions for `getLobbySpawn`, `setPlayerRespawnToLobby`, `moveCharacterToDestination`, `loadAtDestination`, `attachVoidRescue`.
   - RemoteEvent listener wiring for `PlayerDeath`, `MatchPhaseTransition`, `EnterPracticeRange`, `LeavePracticeRange`, `RequestQueue`, `CancelQueue`, `SelectAgent`, `UseAbility`, `SwitchWeapon`, `SwitchOperative`, `RequestPurchase`, `ResetRangeStats`.
   - Connecting `Players.PlayerAdded` and `Players.PlayerRemoving`.

---

## Section 2: Potential Causes of Silent Infinite Yields & Crashes

### 2.1 Missing Timeout on `parent:WaitForChild(childName)` in `safeRequire`
- **Location:** `src/server/ServerMain.server.luau:10`
- **Vulnerability:** `parent:WaitForChild(childName)` has no timeout argument (e.g., `WaitForChild(childName, 5)`). If any required module or folder is missing, misspelled, or renamed, Roblox engine yields the thread indefinitely without raising a Lua runtime error.
- **Impact:** Server boot silently halts at top-level require before reaching any initialization steps.

### 2.2 Top-Level `WaitForChild` in Service Modules
- **Location:** `src/server/Services/RoundService.luau:14-17`, `src/server/Services/EconomyService.luau:14-15`, `src/server/Services/BotService.luau:31-35`, `src/server/Services/OperativeService.luau:15-19`.
- **Vulnerability:** Modules contain top-level statements like:
  `local NetworkFolder = ReplicatedStorage:WaitForChild("Network")`
  `local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)`
  When `ServerMain.server.luau` requires these service modules at lines 30–39 (BEFORE `RemoteEvents.Initialize()` runs at line 51), if any instance in `ReplicatedStorage` is delayed or missing, `require` yields forever at top-level module load time.
- **Impact:** Complete server hang during `require()` before `safeInit` or `RemoteEvents.Initialize()` can execute.

### 2.3 Hardcoded Folder Name Mismatch for Network Remotes
- **Location:** `src/shared/Network/RemoteEvents.luau:7`, `src/shared/Network/RemoteEvents.luau:29`
- **Vulnerability:** `RemoteEvents.luau` sets `local FOLDER_NAME = "NetworkRemotes"` and creates `ReplicatedStorage.NetworkRemotes`. However, requirement R4 specifies that all remotes must reside in `ReplicatedStorage/Network/Remotes`. Furthermore, client UI controllers expect remotes under `ReplicatedStorage:WaitForChild("Network"):WaitForChild("Remotes")`.
- **Impact:** Client UI calls `WaitForChild("NetworkRemotes")` or `WaitForChild("Remotes")` and yields infinitely for 15+ seconds, leading to broken client UI initialization.

### 2.4 Lack of Staged Sequence & Error Propagation in `safeInit`
- **Location:** `src/server/ServerMain.server.luau:143-152`
- **Vulnerability:** Services are initialized asynchronously with un-staged `task.spawn`. If `EconomyService` or `RoundService` fails, the error is logged as a warning, but subsequent stages carry on with uninitialized or half-baked service state, causing downstream `attempt to index nil with 'GetMatch'` crashes during gameplay.
- **Impact:** Unpredictable service dependency failures and silent state corruption.

### 2.5 Ad-hoc Spawning Inline in `ServerMain`
- **Location:** `src/server/ServerMain.server.luau:186-280`
- **Vulnerability:** Character load authority (`Player:LoadCharacter()`, `PivotTo()`, `RespawnLocation`) is directly embedded inside `ServerMain.server.luau` and duplicated in match scripts instead of being centralized in a single `SpawnService` (Requirement R2).
- **Impact:** Race conditions between round resets, practice range entries, and initial lobby spawns leading to players falling into the void.

---

## Section 3: Safe Initialization & Staged Boot Sequence Plan (R1)

### 3.1 Refactoring `safeRequire` with Explicit Timeouts
Replace the un-timed `safeRequire` with a timed, pcall-wrapped helper:

```luau
local function safeRequire(parent: Instance, childName: string, timeoutSeconds: number?): any
    local timeout = timeoutSeconds or 5
    local child = parent:WaitForChild(childName, timeout)
    if not child then
        warn(string.format("[BOOT ERROR] Timeout (%ds) waiting for child '%s' in %s", timeout, childName, parent:GetFullName()))
        return nil
    end
    local success, result = pcall(require, child)
    if not success then
        warn(string.format("[BOOT ERROR] Failed to require '%s': %s", childName, tostring(result)))
        return nil
    end
    return result
end
```

### 3.2 Refactoring `safeInit` Helper for Staged Booting
Implement a synchronous/timed `safeInit` helper that logs explicit step indicators `[BOOT] X/6` and enforces timeouts:

```luau
local function safeInit(stageName: string, stepNum: number, totalSteps: number, fn: () -> ()): boolean
    local stepHeader = string.format("[BOOT] %d/%d %s", stepNum, totalSteps, stageName)
    print(stepHeader)
    
    local completed = false
    local success = false
    local err = nil
    
    task.spawn(function()
        success, err = pcall(fn)
        completed = true
    end)
    
    local startTime = os.clock()
    while not completed and (os.clock() - startTime) < 5.0 do
        task.wait()
    end
    
    if not completed then
        warn(string.format("[BOOT ERROR] Stage %d/%d (%s) TIMED OUT after 5s!", stepNum, totalSteps, stageName))
        return false
    elseif not success then
        warn(string.format("[BOOT ERROR] Stage %d/%d (%s) FAILED: %s", stepNum, totalSteps, stageName, tostring(err)))
        return false
    else
        print(string.format("[BOOT OK] Stage %d/%d (%s) completed successfully.", stepNum, totalSteps, stageName))
        return true
    end
end
```

### 3.3 The 6-Stage Staged Boot Sequence Plan

| Stage | Name | Key Operations | Expected Console Output |
|---|---|---|---|
| **1/6** | Core Infrastructure & Network Remotes | Initialize `RemoteEvents`, `QueueEvents`, `ChallengeEvents`. Verify all remotes in `ReplicatedStorage.Network.Remotes`. | `[BOOT] 1/6 Core Infrastructure & Network Remotes`<br>`[NETWORK] All required remotes available` |
| **2/6** | Data & Core Services | Prepare `ProfileServiceWrapper`, `ReceiptProcessor.Init()`, `SocialInviteService.Init()`. | `[BOOT] 2/6 Data & Core Services`<br>`[BOOT OK] Stage 2/6 completed` |
| **3/6** | Map System & Layout Safety | Auto-register maps (`MapRegistry`), build `GreyboxArenaMap` & `LobbyFolder`, run raycast floor assertion (`verifyLobbyFloor`), build `DuelArenaMap` & `PracticeRangeMapLayout`, instantiate fallback baseplates. | `[BOOT] 3/6 Map System & Layout Safety`<br>`[MAP] Every spawn has collidable floor` |
| **4/6** | Combat & Operative Systems | Instantiate `CombatServer`, initialize `EconomyService`, `OperativeService`, `BotService`. | `[BOOT] 4/6 Combat & Operative Systems`<br>`[BOOT OK] Stage 4/6 completed` |
| **5/6** | Matchmaking & Round State Machine | Initialize `RoundService`, `MatchmakingCoordinator`, `QueueMatchmakingService`, `DirectChallengeService`. | `[BOOT] 5/6 Matchmaking & Round State Machine`<br>`[BOOT OK] Stage 5/6 completed` |
| **6/6** | Player Lifecycle & Server Ready | Connect `SpawnService` (or single spawn authority), hook `PlayerAdded`/`PlayerRemoving` handlers, connect RemoteEvent listeners, run `StartupSmokeTest`. | `[BOOT] 6/6 Server ready`<br>`[SPAWN] Player -> Lobby` |

---

## Section 4: Audit of Directory Tree against R5 & `default.project.json` Reorganization

### 4.1 `default.project.json` Analysis
File path: `default.project.json`

```json
{
  "name": "OVERCLOCK",
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "$path": "src/server"
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "$properties": {
        "CharacterWalkSpeed": 16,
        "CameraMode": "Classic"
      },
      "StarterPlayerScripts": {
        "$path": "src/client"
      }
    },
    "ReplicatedStorage": {
      "$path": "src/shared"
    },
    "Workspace": {
      "$className": "Workspace",
      "$properties": {
        "FallenPartsDestroyHeight": -500,
        "Gravity": 196.2
      }
    },
    "StarterGui": {
      "$className": "StarterGui",
      "$properties": {
        "ShowDevelopmentGui": false
      }
    }
  }
}
```

#### Evaluation against R5:
- **Server Mapping (`src/server` -> `ServerScriptService`)**: Correct.
- **Client Mapping (`src/client` -> `StarterPlayerScripts`)**: Correct.
- **Shared Mapping (`src/shared` -> `ReplicatedStorage`)**: Correct.

### 4.2 Reorganization & File Inventory Audit

#### 1. Server (`ServerScriptService` / `src/server/`)
- **Existing Files:**
  - `ServerMain.server.luau`
  - `Combat/`: `CombatServer.luau`, `HitValidation.luau`, `M2_TestRunner.luau`, `RollbackBuffer.luau`
  - `Services/`: `BotService.luau`, `DirectChallengeService.luau`, `EconomyService.luau`, `FTUEAnalytics.luau`, `MatchmakingCoordinator.luau`, `OperativeService.luau`, `ProfileServiceWrapper.luau`, `QueueMatchmakingService.luau`, `ReceiptProcessor.luau`, `RoundService.luau`, `SocialInviteService.luau` (plus unit `.spec.luau` files)
  - `Tests/`: `M1_DamageTest.luau`, `M3_OperativeTest.luau`, `OverclockVerificationSuite.luau`
- **Missing / Required Additions under R2 & R6:**
  - `src/server/Services/SpawnService.luau` (R2: Central single spawn authority).
  - `src/server/Tests/StartupSmokeTest.luau` (R6: Automated boot smoke test).

#### 2. Shared (`ReplicatedStorage` / `src/shared/`)
- **Existing Folders & Files:**
  - `Analytics/`: `AnalyticsWrapper.luau`
  - `Data/`: `OperativeStats.luau`, `WeaponStats.luau`
  - `Map/`: `ClassicGreyboxMap.luau`, `CyberArenaMap.luau`, `DesertRuinsMap.luau`, `DuelArenaMap.luau`, `ForestOutpostMap.luau`, `GreyboxArenaMap.luau`, `LobbyFolder.luau`, `MapRegistry.luau`, `PracticeRangeMapLayout.luau`, `UrbanWarehouseMap.luau` (plus `.spec.luau` files)
  - `Network/`: `BufferSerializer.luau`, `ChallengeEvents.luau`, `QueueEvents.luau`, `RemoteEvents.luau`
  - `Physics/`: `Spring.luau`
  - `Types/`: `init.luau`
  - `Utils/`: `ObjectPool.luau`
- **Required Reorganization for Remotes (R4):**
  - Update `src/shared/Network/RemoteEvents.luau` to create and maintain remotes inside `ReplicatedStorage.Network.Remotes` folder (`src/shared/Network/Remotes/` in project layout).

#### 3. Client (`StarterPlayerScripts` / `src/client/`)
- **Existing Files:**
  - `ClientMain.client.luau`
  - `Controllers/`: `AnimationController.luau`, `CrosshairController.luau`, `LobbyTransitionController.luau`, `MobileControlsController.luau`, `OperativeController.luau`, `WeaponController.luau`
  - `UI/`: `AgentSelectUI.luau`, `BuyMenuController.luau`, `ChallengeInviteModal.luau`, `HUDController.luau`, `LoadoutInspectorUI.luau`, `LobbyUIController.luau`, `MatchmakingQueueUI.luau`, `PlayerListChallengeUI.luau`, `PostMatchSummaryUI.luau`, `PracticeRangeHUD.luau`, `SettingsUIController.luau`, `ShopUIController.luau`, `UITheme.luau`

---

## Section 5: Recommendations for Implementation

1. **Refactor `ServerMain.server.luau`**:
   - Replace un-timed `safeRequire` with 5-second timeout safeguard.
   - Implement the staged `safeInit()` function and construct stages 1/6 through 6/6.
   - Move character loading logic into `SpawnService`.
2. **Standardize Remote Event Folder**:
   - Update `RemoteEvents.luau` to instantiate remotes under `ReplicatedStorage.Network.Remotes` instead of `ReplicatedStorage.NetworkRemotes`.
3. **Lazy-Load Remotes & Services inside Module Methods**:
   - Eliminate top-level `WaitForChild` calls in service modules to prevent module requiring freezes.
4. **Create `SpawnService.luau` and `StartupSmokeTest.luau`**:
   - Implement single-point spawn authority in `src/server/Services/SpawnService.luau`.
   - Implement smoke test assertions in `src/server/Tests/StartupSmokeTest.luau`.

---
