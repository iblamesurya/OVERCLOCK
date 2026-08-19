# Handoff Report: Single Spawn Authority & Map Safety Exploration (R2 & R3)

**Agent:** Explorer Subagent (`explorer_survey_2`)  
**Workspace:** `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_survey_2`  
**Handoff Type:** Hard (Exploration Complete)  
**Date:** 2026-08-04  

---

## 1. Observation

Direct code observations from inspecting `src/server/`, `src/client/`, and `src/shared/`:

### Character Spawning & Positioning Call Sites:
- **`src/server/ServerMain.server.luau`**:
  - Line 183: `if spawn then player.RespawnLocation = spawn end`
  - Line 247: `character:PivotTo(destination)`
  - Line 250: `character:PivotTo(destination)`
  - Line 273: `player.RespawnLocation = nil`
  - Line 275: `player:LoadCharacter()`
  - Line 299: `character:PivotTo(getDestinationCFrame(player))`
  - Line 553: `p:LoadCharacter()`
  - Hardcoded CFrames: Line 190 (`local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 106, 0)`), Line 191 (`local PRACTICE_CFRAME = CFrame.new(500, 105, 60)`).
- **`src/server/Services/RoundService.luau`**:
  - Line 164: `player:LoadCharacter()`
  - Line 177: `root.CFrame = CFrame.new(spawnPos)`
- **`src/server/Services/DirectChallengeService.luau`**:
  - Line 146: `hrp.CFrame = redCFrame`
  - Line 148: `challengerChar:PivotTo(redCFrame)`
  - Line 155: `targetHrp.CFrame = blueCFrame`
  - Line 157: `targetChar:PivotTo(blueCFrame)`
- **`src/server/Services/QueueMatchmakingService.luau`**:
  - Line 433: `character:PivotTo(CFrame.new(matchPlayer.spawnPosition))`
- **`src/server/Services/SocialInviteService.luau`**:
  - Line 148: `joiningRoot.CFrame = inviterRoot.CFrame * CFrame.new(3, 0, 3)`
  - Line 150: `joiningChar:PivotTo(inviterChar:GetPivot() * CFrame.new(3, 0, 3))`
- **`src/server/Services/BotService.luau`**:
  - Lines 335, 339: `botData.humanoid:MoveTo(targetPos)` (NPC pathfinding - valid non-player usage).
- **`src/client/UI/LoadoutInspectorUI.luau`**:
  - Line 749: `previewWeaponModel:PivotTo(...)` (ViewportFrame model rotation - valid non-character usage).

### Map Modules & Offsets:
- **`src/shared/Map/LobbyFolder.luau`**: Built at `LOBBY_CENTER = (0, 100, 0)`. Spawns located at Y = 101.5 on top of solid floor.
- **`src/shared/Map/PracticeRangeMapLayout.luau`**: Uses `MAP_OFFSET = Vector3.new(500, 100, 0)`. Spawns defined as `PLAYER_SPAWN_POSITIONS`. `GetSpawnPoints()` applies `+ MAP_OFFSET`.
- **`src/shared/Map/GreyboxArenaMap.luau`**, **`DuelArenaMap.luau`**, **`UrbanWarehouseMap.luau`**: Built around origin `(0, 0, 0)` with Red and Blue spawn arrays.
- **Map Floor Raycast Verification**: `ServerMain.server.luau` lines 73-88 (`verifyLobbyFloor`) raycasts under Lobby spawns only. No raycast validation exists for Practice Range or Arena match spawns.

---

## 2. Logic Chain

1. **Premise 1 (Observation 1)**: Calls to `Player:LoadCharacter()`, `player.RespawnLocation`, and `Model:PivotTo()` are fragmented across `ServerMain.server.luau`, `RoundService.luau`, `DirectChallengeService.luau`, `QueueMatchmakingService.luau`, and `SocialInviteService.luau`.
2. **Premise 2 (Observation 1)**: `ServerMain.server.luau` uses local ad-hoc state tables (`playerDestination`, `spawnInProgress`) and hardcoded location CFrames (`PRACTICE_CFRAME`), which creates race conditions when other services load or position characters directly.
3. **Reasoning Step 1**: To achieve Requirement R2 ("Single Spawn Authority"), a single dedicated service (`SpawnService`) must encapsulate all character loading, `RespawnLocation` assignments, and `PivotTo` calls, prohibiting direct calls in all other server scripts.
4. **Premise 3 (Observation 2)**: `PracticeRangeMapLayout.luau` correctly applies `MAP_OFFSET = (500, 100, 0)` in its `GetSpawnPoints()` API, but `ServerMain.server.luau` bypassed this API and hardcoded `(500, 105, 60)`.
5. **Premise 4 (Observation 2)**: Only Lobby spawns are currently raycast-checked during boot (`verifyLobbyFloor`). Practice Range and competitive map spawns are unverified.
6. **Reasoning Step 2**: Requirement R3 ("Map Validation & Layout Safety") requires an authoritative `assertMapReady` function that raycasts downwards from all spawn points across all map layouts (Lobby, Practice Range, Greybox Arena, Duel Arena, Urban Warehouse) immediately after map construction, outputting `[MAP] Every spawn has collidable floor`.

---

## 3. Caveats

- **Client Camera Teleportation**: Client UI controllers (`LobbyTransitionController`, `HUDController`) adjust camera CFrame locally upon phase transition (`MatchPhaseTransition`). The single spawn authority only applies to server-side character loading and positioning.
- **Operative Mobility Abilities**: `OperativeService.luau` (line 571) sets `rootPart.CFrame` during Fray's Dash ability. This is active combat movement, not character loading/teleportation, and should remain handled within `OperativeService`.
- **Bot NPC Movement**: `BotService.luau` handles NPC bot positioning and pathfinding via `Humanoid:MoveTo()`. This is isolated from human player spawn authority.

---

## 4. Conclusion

1. **`SpawnService` Design**:
   - Location: `src/server/Services/SpawnService.luau`
   - Role: Absolute owner of `Player:LoadCharacter()`, `player.RespawnLocation`, `character:PivotTo()`, and player location tracking (`"Lobby" | "PracticeRange" | "Match"`).
   - All other services (`RoundService`, `DirectChallengeService`, `QueueMatchmakingService`, `SocialInviteService`, `ServerMain`) must be refactored to call `SpawnService.SpawnPlayer()` or `SpawnService.TeleportCharacter()`.
2. **`assertMapReady` Raycast Safety**:
   - Location: `src/shared/Map/MapSafety.luau` (or integrated helper in `MapRegistry.luau`).
   - Functionality: Casts rays downward (`Vector3.new(0, -30, 0)`) from `spawnPos + Vector3.new(0, 10, 0)` for every spawn point in any loaded map. Asserts `hit ~= nil` and `hit.Instance.CanCollide == true`.
   - Logging: Prints `[MAP] Every spawn has collidable floor` on complete validation pass.

---

## 5. Verification Method

To independently verify the exploration findings and subsequent implementation:

1. **Source Code Inspection**:
   - Check `src/server/` using PowerShell to ensure `Player:LoadCharacter()`, `RespawnLocation =`, and `PivotTo` appear ONLY in `src/server/Services/SpawnService.luau`.
     ```powershell
     Get-ChildItem -Path "c:\Users\tummala surya\Downloads\roblox\src\server" -Recurse -Include *.luau | Select-String -Pattern "LoadCharacter|RespawnLocation|PivotTo"
     ```
2. **Boot Output Verification**:
   - Execute server boot (or inspect output logs upon startup). Output must display:
     - `[MAP] Every spawn has collidable floor`
     - `[SPAWN] Player -> Lobby`
3. **Gameplay Loop Verification**:
   - Enter Practice Range, reset character 3 times, return to Lobby. Player must spawn at exact designated map spawn points without falling through the floor or spawning at `(0, 0, 0)`.
