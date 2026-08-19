# Implementation Plan - Milestone 5: Matchmaking Queue & 5-Map Voting Integration

## Objectives
1. **Map Harmonization**:
   - Update `MAP_LIST` and `MAP_DESCRIPTIONS` in `src/client/UI/MatchmakingQueueUI.luau` to use the 5 registered map IDs:
     - `GreyboxArena`
     - `CyberArena`
     - `DesertRuins`
     - `ForestOutpost`
     - `UrbanWarehouse`
   - Update `ALLOWED_MAPS` in `src/server/Services/QueueMatchmakingService.luau` to match the exact same 5 registered map IDs.

2. **Matchmaking Queue & UI Integration**:
   - Ensure queue mode selection tabs (1v1 vs 2v2) correctly set `currentMode` and update styles when not in queue.
   - Verify `startQueueTimer()` formats time as `MM:SS`.
   - Update `CancelQueueButton` behavior: invoke `QueueLeave` RemoteFunction, stop queue timer, set `isInQueue = false`, reset queue status label, restore `EnterQueueButton` visibility.
   - In `ShowMatchFound(data)`: update 5 map voting cards using `data.availableMaps`, display team roster (`teammates` vs `opponents`), run countdown timer.
   - `VoteForMap(mapName)`: invoke `MapVoteSubmit` RemoteFunction, update button visual state (`VOTED ✓`), listen to `MapVoteUpdate` events.
   - `UpdateVoteResults(result)`: update vote count labels live. When `result.votingEnded` is true, announce winning map (`WINNING MAP: [NAME]! Teleporting to Arena...`), wait 3 seconds, hide match modal frame, and restore main queue frame cleanly.

3. **Server Map Loading & State Management**:
   - Require `MapRegistry` module in `QueueMatchmakingService.luau`.
   - In `StartMatchSession(matchId)`:
     - Dynamically load voted map geometry into Workspace via `MapRegistry.LoadMapInstance(session.selectedMap)`.
     - Retrieve spawn positions dynamically via `MapRegistry.GetActiveMapLayoutData()`.
     - Assign `layout.redSpawns` for Team 1 players and `layout.blueSpawns` for Team 2 players (with fallback to default offsets).
     - Pivot player character HumanoidRootParts to their spawn positions.
   - Implement `EndMatchSession(matchId)` function to clear player active match tracking, set status to `"Ended"`, and invoke `MapRegistry.UnloadMapInstance()` when a match concludes or is cancelled.

4. **MapRegistry Verification**:
   - Verify auto-registration of 5 maps (`GreyboxArena`, `CyberArena`, `DesertRuins`, `ForestOutpost`, `UrbanWarehouse`).

5. **Build Verification**:
   - Run `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` using `run_command` and confirm 0 errors.
