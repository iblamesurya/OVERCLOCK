# Handoff Report: Single Spawn Authority (`SpawnService` Design & Caller Refactoring - M2 / R2)

**Agent:** Explorer Subagent (`explorer_m2_1`)  
**Workspace:** `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_m2_1`  
**Handoff Type:** Hard (Design & Specification Complete)  
**Date:** 2026-08-04  

---

## 1. Observation

Direct code observations from inspecting `src/server/`, `src/client/`, and `src/shared/`:

### Ad-hoc Spawning & Character Positioning Call Sites:
1. **`src/server/ServerMain.server.luau`**:
   - Line 34: `Players.CharacterAutoLoads = false`
   - Line 183: `if spawn then player.RespawnLocation = spawn end`
   - Line 247: `character:PivotTo(destination)`
   - Line 250: `character:PivotTo(destination)`
   - Line 273: `player.RespawnLocation = nil`
   - Line 275: `player:LoadCharacter()`
   - Line 299: `character:PivotTo(getDestinationCFrame(player))`
   - Line 553: `p:LoadCharacter()`
   - Line 587: `p:LoadCharacter()`
   - Local state tables & hardcoded CFrames: `playerDestination`, `spawnInProgress`, `rescueCooldown`, `LOBBY_FALLBACK_CFRAME = CFrame.new(0, 106, 0)`, `PRACTICE_CFRAME = CFrame.new(500, 105, 60)`.
2. **`src/server/Services/RoundService.luau`**:
   - Line 164: `player:LoadCharacter()` inside `resetPlayerCharacter`
   - Line 177: `root.CFrame = CFrame.new(spawnPos)` inside `resetPlayerCharacter`
3. **`src/server/Services/DirectChallengeService.luau`**:
   - Line 146: `hrp.CFrame = redCFrame`
   - Line 148: `challengerChar:PivotTo(redCFrame)`
   - Line 155: `targetHrp.CFrame = blueCFrame`
   - Line 157: `targetChar:PivotTo(blueCFrame)`
4. **`src/server/Services/QueueMatchmakingService.luau`**:
   - Line 433: `character:PivotTo(CFrame.new(matchPlayer.spawnPosition))` inside `StartMatchSession`
5. **`src/server/Services/SocialInviteService.luau`**:
   - Line 148: `joiningRoot.CFrame = inviterRoot.CFrame * CFrame.new(3, 0, 3)`
   - Line 150: `joiningChar:PivotTo(inviterChar:GetPivot() * CFrame.new(3, 0, 3))`
6. **`src/server/Services/OperativeService.luau`**:
   - Line 570: `rootPart.CFrame = CFrame.new(finalPos, finalPos + lookDir)` inside `Fray_Blink` dash

---

## 2. Logic Chain

1. **Observation 1**: Calls to `Player:LoadCharacter()`, `player.RespawnLocation`, and character positioning (`PivotTo`, `RootPart.CFrame`) are scattered across 6 distinct server scripts.
2. **Observation 2**: Multiple services (`ServerMain`, `RoundService`, `DirectChallengeService`, `QueueMatchmakingService`) attempt to position or reload characters independently without mutual locking or synchronized location state tracking.
3. **Reasoning Step 1**: Requirement **R2 (Single Spawn Authority)** demands that `SpawnService.luau` be the **absolute only** script allowed to call `Player:LoadCharacter()`, set `player.RespawnLocation`, or use `PivotTo()` / `CFrame` assignments for character spawning/teleporting.
4. **Reasoning Step 2**: Creating `SpawnService.luau` with a single-flight mutex (`spawnLocks`), location tracking (`playerLocations`), void rescue monitoring (`AttachVoidRescue`), and safe character reloading (`SpawnPlayer`) provides complete concurrency safety and eliminates void falling.
5. **Reasoning Step 3**: All 6 caller scripts must be refactored to delegate spawning and character relocation to `SpawnService.SpawnPlayer()` or `SpawnService.TeleportCharacter()`.

---

## 3. Caveats

- **Bot NPC Spawning & Pathfinding**: `src/server/Services/BotService.luau` handles NPC bot positioning via `Humanoid:MoveTo()`. These are server-controlled dummy/bot models, not Roblox `Player` objects, and fall outside `SpawnService` player authority.
- **Client Viewport Models**: `src/client/UI/LoadoutInspectorUI.luau` uses `weaponModel:PivotTo()` inside UI ViewportFrames. This is local client render-tree positioning, not server character physics, and remains in the UI controller.
- **Fray Mobility Ability**: In `OperativeService.luau`, Fray's Blink dash repositions the player mid-combat. Routing this through `SpawnService.TeleportCharacter(player, targetCFrame)` maintains centralized authority without affecting combat responsiveness.

---

## 4. Conclusion

1. **New Module**: The Worker must create `src/server/Services/SpawnService.luau` using the complete implementation provided in `analysis.md` (Section 2.2).
2. **Key API Exports**:
   - `SpawnService.Init()`
   - `SpawnService.SpawnPlayer(player: Player, destinationType: "Lobby" | "PracticeRange" | "Match", customCFrame: CFrame?): Model?`
   - `SpawnService.TeleportCharacter(player: Player, cframe: CFrame): boolean`
   - `SpawnService.SetPlayerLocation(player: Player, location: "Lobby" | "PracticeRange" | "Match")`
   - `SpawnService.GetPlayerLocation(player: Player): "Lobby" | "PracticeRange" | "Match"`
   - `SpawnService.HandleCharacterRespawn(player: Player)`
3. **Refactoring Target Scripts**:
   - `src/server/ServerMain.server.luau`: Delegate player lifecycle & spawns to `SpawnService`. Remove local state tables & duplicate load loops.
   - `src/server/Services/RoundService.luau`: Replace direct `LoadCharacter()` and `root.CFrame = ...` in `resetPlayerCharacter` with `SpawnService.SpawnPlayer` / `TeleportCharacter`.
   - `src/server/Services/DirectChallengeService.luau`: Replace CFrame assignments in `spawnDuelArenaAndTeleport` with `SpawnService.TeleportCharacter`.
   - `src/server/Services/QueueMatchmakingService.luau`: Replace `character:PivotTo` in `StartMatchSession` with `SpawnService.TeleportCharacter`.
   - `src/server/Services/SocialInviteService.luau`: Replace direct CFrame assignments in `teleportToInviter` with `SpawnService.TeleportCharacter`.
   - `src/server/Services/OperativeService.luau`: Replace `rootPart.CFrame = ...` in `Fray_Blink` with `SpawnService.TeleportCharacter`.

---

## 5. Verification Method

To independently verify that the implementation satisfies Requirement R2:

1. **Source Code Inspection (Single Authority Check)**:
   Inspect `src/server` using `grep_search` or PowerShell to confirm `Player:LoadCharacter()`, `RespawnLocation =`, and character positioning appear **ONLY** in `src/server/Services/SpawnService.luau`:
   ```powershell
   Get-ChildItem -Path "c:\Users\tummala surya\Downloads\roblox\src\server" -Recurse -Include *.luau | Select-String -Pattern "LoadCharacter|RespawnLocation"
   ```
   *Expected Output:* Matches occur strictly within `src/server/Services/SpawnService.luau`.

2. **Boot Output Verification**:
   When launching the server, inspect the boot logs. The output must display:
   - `[BOOT] 6/6 Setting Up Player Handlers & Single Spawn Authority`
   - `[SpawnService] Initialized as Single Spawn Authority.`
   - `[SPAWN] Player -> Lobby`

3. **Gameplay Spawning Smoke Test**:
   - Enter Practice Range -> Verify `[SPAWN] Player -> PracticeRange` is logged.
   - Reset character 3 times -> Verify player respawns cleanly at Practice Range spawn coordinates.
   - Return to Lobby -> Verify `[SPAWN] Player -> Lobby` is logged and player lands on Lobby floor without void falling.
