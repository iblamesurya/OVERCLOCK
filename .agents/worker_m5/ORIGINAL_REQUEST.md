## 2026-08-03T14:45:00Z
You are the Worker subagent for Milestone 5 (Matchmaking Queue & 5-Map Voting Integration) of RIVALS-PARADIGM v2 Roblox FPS Overhaul.

Your Working Directory is: c:\Users\tummala surya\Downloads\roblox\.agents\worker_m5

Your Objective:
Implement Milestone 5: Matchmaking Queue & 5-Map Voting Integration.

Target Files to modify:
1. `src/client/UI/MatchmakingQueueUI.luau`
2. `src/server/Services/QueueMatchmakingService.luau`
3. `src/shared/Map/MapRegistry.luau`

Detailed Implementation Instructions:

1. **Map Harmonization**:
   - In `src/client/UI/MatchmakingQueueUI.luau`, replace placeholder map names (`CyberCity`, `DesertOutpost`, `NeonSubway`, `Hangar18`) with actual registered map IDs in `MAP_LIST` and `MAP_DESCRIPTIONS`:
     - `"GreyboxArena"`: "Standard symmetrical testing arena with balanced sightlines."
     - `"CyberArena"`: "High-tech urban arena featuring holographic combat lanes."
     - `"DesertRuins"`: "Arid desert ruins with open sniper corridors."
     - `"ForestOutpost"`: "Dense forest military outpost with close-quarters chokepoints."
     - `"UrbanWarehouse"`: "Industrial urban warehouse with multi-level container routes."
   - In `src/server/Services/QueueMatchmakingService.luau`, update `ALLOWED_MAPS` to match the exact same 5 registered map IDs: `{"GreyboxArena", "CyberArena", "DesertRuins", "ForestOutpost", "UrbanWarehouse"}`.

2. **Matchmaking Queue & UI Integration**:
   - In `MatchmakingQueueUI.luau`:
     - Operational mode tabs (1v1 vs 2v2) must set `currentMode` and update styles when not in queue.
     - Queue timer must display formatted time (`MM:SS`) using `startQueueTimer()`.
     - `CancelQueueButton` must invoke `QueueLeave` RemoteFunction, stop timer, set `isInQueue = false`, reset queue status label, and restore `EnterQueueButton` visibility.
     - In `ShowMatchFound(data)`: Dynamically render/update 5 map cards using `data.availableMaps` or mapped `mapCards`, display team roster (`teammates` vs `opponents`), and show countdown timer.
     - `VoteForMap(mapName)` must invoke `MapVoteSubmit` RemoteFunction, update button visual state (`VOTED ✓`), and listen to `MapVoteUpdate` events.
     - `UpdateVoteResults(result)` must update vote count labels live. When `result.votingEnded` is true, announce winning map (`WINNING MAP: [NAME]! Teleporting to Arena...`), wait 3 seconds, hide match modal frame, and restore main queue frame cleanly.

3. **Server Map Loading & State Management**:
   - In `src/server/Services/QueueMatchmakingService.luau`:
     - Require `MapRegistry` module (`local MapRegistry = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("MapRegistry"))`).
     - In `StartMatchSession(matchId)`:
       - Dynamically load voted map geometry into Workspace via `MapRegistry.LoadMapInstance(session.selectedMap)`.
       - Retrieve spawn positions dynamically via `MapRegistry.GetActiveMapLayoutData()`.
       - Use `layout.redSpawns` for Team 1 players and `layout.blueSpawns` for Team 2 players (with fallback to default offsets if layout data is missing).
       - Pivot player character HumanoidRootParts to their spawn positions.
     - Implement clean state management & cleanup: Provide `EndMatchSession(matchId)` function to clear player active match entries, set status to `"Ended"`, and invoke `MapRegistry.UnloadMapInstance()` when a match concludes or is cancelled.

4. **MapRegistry Verification**:
   - Ensure `MapRegistry.luau` auto-registers maps properly via `AutoRegisterDefaultMaps()` and clean loading/unloading operations.

5. **Build Verification**:
   - Run `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` using `run_command`.
   - Verify that compilation succeeds with 0 errors.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Upon completion, write a detailed handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\worker_m5\handoff.md` and send a message back.
