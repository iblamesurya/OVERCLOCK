# Technical Analysis: Matchmaking Queue, 5-Map Voting Integration, & Build Infrastructure

**Explorer ID**: Explorer 3 (Milestone 0)  
**Target Project**: RIVALS-PARADIGM v2 Roblox FPS Overhaul  
**Date**: August 3, 2026  

---

## 1. Executive Summary

This report provides a detailed analysis of the matchmaking queue system, 5-map voting integration, and build compilation pipeline in **RIVALS-PARADIGM v2**.

Key discoveries include:
1. **Queue Architecture Dual-System**: The repository currently contains two matchmaking services:
   - `QueueMatchmakingService.luau`: Active local in-memory service for 1v1 (2 players) and 2v2 (4 players) with built-in map voting and local spawn teleportation.
   - `MatchmakingCoordinator.luau`: Distributed MemoryStore-based matchmaking coordinator designed for 5v5 cross-server queueing, coordinator leader election, and private server reservation.
2. **Map List Discrepancy**:
   - `MatchmakingQueueUI.luau` and `QueueMatchmakingService.luau` hardcode placeholder map names: `{"GreyboxArena", "CyberCity", "DesertOutpost", "NeonSubway", "Hangar18"}`.
   - The actual `src/shared/Map/` directory and `MapRegistry.luau` define 6 implemented map modules: `GreyboxArenaMap`, `ClassicGreyboxMap`, `CyberArenaMap`, `DesertRuinsMap`, `ForestOutpostMap`, and `UrbanWarehouseMap`.
   - `CyberCity`, `DesertOutpost`, `NeonSubway`, and `Hangar18` do not match the registered map modules in `MapRegistry` (except `GreyboxArena`).
3. **Build & Lint Verification**:
   - `rojo.exe build default.project.json -o RivalsParadigm.rbxl` executes cleanly without errors.
   - `selene` static analysis checks across all 51 Luau source files in `src/` passed with **0 errors**.

---

## 2. Core Service & UI Analysis

### 2.1 `src/client/UI/MatchmakingQueueUI.luau`

`MatchmakingQueueUI.luau` manages all client-side UI interactions for matchmaking mode selection, live timer display, queue status, match found overlay, and map voting.

* **State Variables** (lines 34–58):
  - `currentMode`: Holds active tab selection (`"1v1"` or `"2v2"`).
  - `isInQueue`: Boolean tracking active queue status.
  - `queueStartTime`: Timestamp when queue was entered.
  - `timerThread`: Coroutine thread driving the queue timer readout.
  - `activeMatchId`, `userVotedMap`: Tracks active voting match session and user selection.
  - `mapCards`: Dictionary mapping map names to UI card components (`cardFrame`, `voteButton`, `voteCountLabel`).
* **Queue Mode Selection (1v1 vs 2v2)** (lines 72–83, 408–420):
  - Mode selection tabs `Tab1v1` and `Tab2v2` toggle `currentMode`.
  - Switching modes is locked while `isInQueue` is true (`if not isInQueue then currentMode = ... end`).
* **Timer & Status Displays** (lines 85–107, 436–457):
  - `startQueueTimer()` spawns a task loop incrementing elapsed time (`os.time() - queueStartTime`) every second, formatted via `formatTimer()` as `MM:SS`.
  - `QueueStatusUpdate` RemoteEvent updates `queueStatusLabel` text (e.g. `"Searching for 1v1 Match (2 in queue)..."`).
* **CANCEL QUEUE Functionality** (lines 428–432, 493–512):
  - `CancelQueueButton` invokes `QueueLeave` RemoteFunction.
  - On success, sets `isInQueue = false`, calls `stopQueueTimer()`, resets status label, and swaps visibility from `CancelQueueButton` back to `EnterQueueButton`.
* **5-Map Voting Grid & Match Found Overlay** (lines 244–397, 515–644):
  - `MatchFoundModal` is popped open using `TweenService` (Back easing).
  - Renders team roster (`teammates` vs `opponents`).
  - Displays a 5-card grid (`MapVotingGrid`) with `UIGridLayout` (cell size 128x145).
  - Card click triggers `MatchmakingQueueUI.VoteForMap(mapName)`, invoking `MapVoteSubmit` RemoteFunction.
  - Listens to `MapVoteUpdate` RemoteEvent to update vote tallies and display `WINNING MAP: [NAME]!`.

### 2.2 `src/server/Services/QueueMatchmakingService.luau`

`QueueMatchmakingService.luau` is the primary server-side matchmaking service handling 1v1 and 2v2 player queues.

* **In-Memory Queue Structures** (lines 57–65):
  - `queues["1v1"]`: Array of `QueueEntry` requiring 2 players to pop.
  - `queues["2v2"]`: Array of `QueueEntry` requiring 4 players to pop.
* **Matchmaking Loop** (lines 425–479, 547–552):
  - Runs every `1.0` seconds (`QUEUE_PROCESS_INTERVAL`).
  - Pops valid player pairs/groups, initializes `MatchSession`, and broadcasts `QueueMatchFound` to clients.
* **Map Voting & Tally Engine** (lines 193–300, 397–402):
  - `SubmitMapVote()` updates `session.votes[userId]` and re-tallies `session.mapTallies`.
  - Fires `MapVoteUpdate` RemoteEvent to all match participants.
  - `finalizeMapVoting()` triggers on timer expiry (`VOTING_DURATION_SECONDS = 10`) or when all players have voted.
  - Resolves ties randomly among maps with equal highest votes (`math.random(1, #candidateMaps)`).
* **Spawn Allocation & Teleportation** (lines 167–191, 405–423):
  - `computeSpawnPosition()` calculates team spawn offsets or queries `Workspace.Spawns`.
  - `StartMatchSession()` pivots player characters to assigned spawn positions when voting concludes.

### 2.3 `src/server/Services/MatchmakingCoordinator.luau`

`MatchmakingCoordinator.luau` is an enterprise distributed matchmaking system designed for multi-server Roblox environments.

* **Deterministic Sharding** (lines 15–20, 60–71, 85–118):
  - Uses `MemoryStoreService:GetSortedMap()` with 4 shards (`MMQueue_Shard_0` .. `3`).
  - Routes tickets based on `userId % 4`.
* **Coordinator Election Protocol** (lines 145–202):
  - Atomic control key write on `MMControlMap` (`CoordinatorLeader`).
  - Leader lease TTL = 15 seconds; heartbeat every 5 seconds.
  - Only the elected leader queries sharded maps (`CollectAllQueueTicketsAsync`) and forms 5v5 lobbies (`FormLobbies`).
* **Private Server Reservation & MessagingService** (lines 290–351, 361–383):
  - Calls `TeleportService:ReserveServer(TARGET_PLACE_ID)`.
  - Publishes `MatchAssignment` via `MessagingService` so remote servers teleport their queued players into the reserved private server.

---

## 3. Map System Inventory & Discrepancies

### 3.1 Implemented Map Modules in `src/shared/Map/`

An audit of `src/shared/Map/` reveals 6 fully functional map generator modules registered via `MapRegistry.luau`:

| Map Module Name | Registered Map ID | Theme | Spawns (Red / Blue) | Site A / Site B |
|---|---|---|---|---|
| `GreyboxArenaMap.luau` | `GreyboxArena` | Symmetrical Greybox | 5 / 5 | Yes |
| `ClassicGreyboxMap.luau` | `ClassicGreybox` | Classic Greybox | 5 / 5 | Yes |
| `CyberArenaMap.luau` | `CyberArena` | Sci-Fi Cyberpunk | 5 / 5 | Yes |
| `DesertRuinsMap.luau` | `DesertRuins` | Arid Desert Ruins | 5 / 5 | Yes |
| `ForestOutpostMap.luau` | `ForestOutpost` | Forest Military Outpost | 5 / 5 | Yes |
| `UrbanWarehouseMap.luau` | `UrbanWarehouse` | Industrial Urban | 5 / 5 | Yes |

### 3.2 Key Discrepancy

* **UI & Service Map List**:
  `MAP_LIST` in `MatchmakingQueueUI.luau` and `ALLOWED_MAPS` in `QueueMatchmakingService.luau` contain:
  `{"GreyboxArena", "CyberCity", "DesertOutpost", "NeonSubway", "Hangar18"}`
* **Actual Registered Maps**:
  `{"GreyboxArena", "ClassicGreybox", "CyberArena", "DesertRuins", "ForestOutpost", "UrbanWarehouse"}`

**Impact**: If a user votes for `CyberCity`, `DesertOutpost`, `NeonSubway`, or `Hangar18`, `MapRegistry.LoadMapInstance(mapId)` will fail because those map IDs do not match registered map modules (`CyberArena`, `DesertRuins`, `ForestOutpost`, `UrbanWarehouse`).

---

## 4. Build Infrastructure Verification

### 4.1 Rojo Configuration (`default.project.json`)
* **Project Name**: `RIVALS-PARADIGM`
* **Mappings**:
  - `ServerScriptService` $\rightarrow$ `src/server`
  - `StarterPlayer.StarterPlayerScripts` $\rightarrow$ `src/client`
  - `ReplicatedStorage` $\rightarrow$ `src/shared`
  - `Workspace` $\rightarrow$ DataModel defaults (Gravity: 196.2, FallenPartsDestroyHeight: -500)
  - `StarterGui` $\rightarrow$ ShowDevelopmentGui: false

### 4.2 Rojo Build Command Execution
Command: `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl`  
Result:
```
Building project 'RIVALS-PARADIGM'
Built project to RivalsParadigm.rbxl
```
Status: **PASSED** (0 compilation errors).

### 4.3 Static Analysis (Selene)
Command: `python scratch/verify_selene_all.py`  
Result:
```
Linting 51 Luau files in src/...
============================================================
SUCCESS: 0 selene static analysis errors across all 51 files in src/
```
Status: **PASSED** (0 lint errors across all 51 Luau files).

---

## 5. Concrete Recommendations for Milestone 5

To achieve complete integration of the Matchmaking Queue and 5-Map Voting System in Milestone 5, the following implementation strategy is recommended:

### Recommendation 1: Map Name & Registry Harmonization
* Refactor `ALLOWED_MAPS` in `QueueMatchmakingService.luau` and `MAP_LIST` / `MAP_DESCRIPTIONS` in `MatchmakingQueueUI.luau` to directly integrate with `MapRegistry.luau`.
* Recommended 5-Map Pool:
  1. `GreyboxArena`
  2. `CyberArena`
  3. `DesertRuins`
  4. `ForestOutpost`
  5. `UrbanWarehouse`
* Provide metadata mapping in `src/shared/Map/MapRegistry.luau` so UI can fetch map display names and descriptions dynamically.

### Recommendation 2: Dynamic Map Generation & Cleanup
* In `QueueMatchmakingService.StartMatchSession(matchId)`:
  - Call `MapRegistry.LoadMapInstance(session.selectedMap)` to dynamically instantiate the voted map's geometry into `Workspace`.
  - Retrieve spawn points dynamically via `MapRegistry.GetActiveMapLayoutData()` or `mapModule.GetSpawnPoints(teamName)`.
  - When a match ends, call `MapRegistry.UnloadMapInstance()` to clean up map instances before returning to lobby.

### Recommendation 3: UI Grid Dynamic Scaling & Visual Enhancements
* Update `MatchmakingQueueUI.luau` map card generation to loop over `data.availableMaps` (received in `QueueMatchFound` payload) instead of hardcoding layout loop `MAP_LIST`.
* Add visual indicators for map preview thumbnails or theme-colored borders on map selection cards.

### Recommendation 4: Queue Service Integration Strategy
* Decide on clear operational boundaries between `QueueMatchmakingService.luau` (in-place 1v1 and 2v2 sessions) and `MatchmakingCoordinator.luau` (cross-place MemoryStore 5v5 sessions).
* Ensure `QueueEvents.luau` shared remotes handle both modes seamlessly.
