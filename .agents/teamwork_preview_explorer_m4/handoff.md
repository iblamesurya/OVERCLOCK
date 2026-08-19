# Milestone 4 (M4_Practice_Range_Bots) — Handoff Report

## 1. Observation

Direct file observations from investigation:
- **`src/shared/Map/PracticeRangeMapLayout.luau`**:
  - Defines `MAP_FOLDER_NAME = "PracticeRangeMap"`.
  - Stationary Target Wall Section (Lines 201–243): Creates `TargetWallSection` folder, `TargetWallBackboard`, and `Target_Stationary_1` .. `Target_Stationary_6` with attributes `IsTarget = true`, `TargetType = "Stationary"`, `TargetId = 1..6`. Each target has a child disc `Bullseye` with `IsBullseye = true`, `TargetId = 1..6`, `CanCollide = false`.
  - Patrol Bot Arena Section (Lines 244–266): Creates `PatrolBotSection` folder and `Waypoints` folder containing `Waypoints_Bot_1` .. `Waypoints_Bot_8` with attribute `WaypointIndex = 1..8`.
  - Player Spawn Section (Lines 267–323): Creates `Spawns.PlayerSpawn` containing `Spawn_Player_1` .. `3`.
  - API Helpers: `GetStationaryTargets()`, `GetBotWaypoints()`, `GetSpawnPoints()`.
- **`src/server/Combat/CombatServer.luau`**:
  - `ProcessHitReport` (Lines 254–404): Checks `self._matchPhase` (supports `"InGame"` and `"PracticeRange"`).
  - Lines 319–335 handle non-player victims:
    ```luau
    if not victimPlayer or victimUserId == 0 then
        if payload.targetInstance then
            local targetModel = payload.targetInstance:FindFirstAncestorOfClass("Model")
            local botHumanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
            if botHumanoid then
                botHumanoid:TakeDamage(rawDamage)
                return true, nil, botHumanoid.Health
            end
            if payload.targetInstance:GetAttribute("IsPracticeTarget") == true or payload.targetInstance.Name == "PracticeTarget" or payload.targetInstance.Name == "Target" then
                return true, nil, 0
            end
        end
        if self._matchPhase == "PracticeRange" then
            return true, nil, 0
        end
    end
    ```
- **`src/client/Controllers/WeaponController.luau`**:
  - Lines 205–237: Fires `ReliableCombat` with `FireWeapon` action on shot fire and `ReportHit` action on hit detection.
- **`src/shared/Network/RemoteEvents.luau`**:
  - Manages reliable and unreliable RemoteEvent channels. `ResetRangeStats` and `RangeStatsUpdated` can be registered in `reliableNames`.

---

## 2. Logic Chain

1. **Stationary Target Wall Integration**:
   - `PracticeRangeMapLayout` builds 6 stationary targets (`Target_Stationary_1..6`) with explicit `TargetId` attributes and `Bullseye` child parts.
   - When hit via `CombatServer.ProcessHitReport`, `BotService.ProcessTargetHit` will play a CFrame tilt animation (tilt -15 degrees and restore over 0.25s) and hit audio, increment the hit counter, and pass stats to the live accuracy tracker.
2. **Patrol Bot AI Lifecycle & Spawning**:
   - `PatrolBotSection` provides 8 3D waypoints (`Waypoints_Bot_1..8`).
   - `BotService.SpawnPatrolBots(5)` will instantiate 5 humanoid models (`PatrolBot_1..5`) with `Humanoid` (`MaxHealth = 100`, `Health = 100`, `WalkSpeed = 12`), `Head` (`Name = "Head"`, `IsHead = true`), `HumanoidRootPart`, and `BillboardGui`.
   - Each bot's patrol thread calls `Humanoid:MoveTo(waypointPos)` with a 8.0s timeout to prevent getting stuck, followed by a 0.5s–1.5s idle wait before moving to the next waypoint.
3. **Bot Combat & Respawn Mechanics**:
   - `CombatServer.ProcessHitReport` already handles non-player humanoids via `botHumanoid:TakeDamage(rawDamage)`.
   - When `humanoid.Died` fires (`HP <= 0`), `BotService` handles death state, cancels movement, schedules a 3.0s delay (`task.delay(3.0, ...)`), teleports the bot back to its origin spawn pad, restores health to 100 HP, and resumes the patrol loop.
4. **Live Accuracy Stats Tracker & Replication**:
   - Tracks `totalShotsFired`, `totalHits`, `totalHeadshots` per session per player.
   - Calculates `accuracyPercent` (`hits / shots * 100`) and `headshotPercent` (`headshots / hits * 100`), rounded to 1 decimal place.
   - Replicates updated stats to client HUD via `RangeStatsUpdated` RemoteEvent and handles `ResetRangeStats` remote request to clear stats to 0.

---

## 3. Caveats

- **Network Bandwidth Optimization**: Waypoint movement is driven server-side using `Humanoid:MoveTo()`. Standard Roblox Humanoid replication automatically synchronizes position smoothly to clients.
- **Rojo Build Prerequisites**: Ensure `Rojo` is available or executed via `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl`.
- **Client HUD Sub-Controller**: `HUDController.luau` or a dedicated `PracticeRangeHUDController.luau` must bind to `RangeStatsUpdated` to display the accuracy metrics on screen.

---

## 4. Conclusion

Worker 4 must implement `src/server/Services/BotService.luau` and its spec `src/server/Services/BotService.spec.luau` according to the detailed technical specification in `analysis.md`. The service must manage stationary target wall hit animations/sounds, patrol bot humanoid lifecycle and 3s respawn, shared combat damage integration, and live accuracy stats tracking/replication.

---

## 5. Verification Method

### 5.1 Automated Unit Spec Test (`src/server/Services/BotService.spec.luau`)
Worker 4 will execute the unit test suite which verifies:
1. Building `PracticeRangeMapLayout` and initializing `BotService`.
2. Target wall hit detection, animation triggering, and hit counter increment.
3. Patrol bot spawning (5 bots), model hierarchy validation (`Humanoid`, `Head`, `HumanoidRootPart`, `BillboardGui`).
4. Bot damage application, death state, 3-second respawn timer, and health restoration to 100 HP.
5. Live accuracy stats arithmetic (`accuracyPercent`, `headshotPercent`) and stat reset capability (`ResetPlayerStats`).
6. Clean teardown (`BotService.Destroy()`, `PracticeRangeMapLayout.DestroyMap()`).

### 5.2 Build Verification
Execute Rojo build command from project root:
```powershell
.\rojo.exe build default.project.json -o RivalsParadigm.rbxl
```
Build must finish with **0 errors**.
