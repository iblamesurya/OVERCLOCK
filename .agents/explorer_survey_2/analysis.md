# Exploration Analysis: Single Spawn Authority & Map Safety (R2 & R3)

**Project:** OVERCLOCK Roblox Tactical Shooter  
**Agent:** Explorer Subagent (`explorer_survey_2`)  
**Target Scope:** Single Spawn Authority (`SpawnService`) & Map Safety (`assertMapReady`, `MAP_OFFSET` validation)  
**Date:** 2026-08-04  

---

## 1. Audit of Existing Character Spawning & Positioning Logic

A comprehensive scan of `src/server/`, `src/client/`, and `src/shared/` was performed to identify all calls to `Player:LoadCharacter()`, `RespawnLocation`, `Model:PivotTo()`, `HumanoidRootPart.CFrame`, and character position manipulations.

### Summary Table of Spawning & Positioning Operations

| File Path | Line(s) | Code Snippet / Operation | Context / Problem |
|---|---|---|---|
| `src/server/ServerMain.server.luau` | 183 | `player.RespawnLocation = spawn` | Sets lobby `RespawnLocation` ad-hoc in helper. |
| `src/server/ServerMain.server.luau` | 247, 250 | `character:PivotTo(destination)` | Teleports character in `moveCharacterToDestination`. |
| `src/server/ServerMain.server.luau` | 273 | `player.RespawnLocation = nil` | Clears `RespawnLocation` when teleporting to Practice Range. |
| `src/server/ServerMain.server.luau` | 275 | `player:LoadCharacter()` | Loads player character in `loadAtDestination`. |
| `src/server/ServerMain.server.luau` | 299 | `character:PivotTo(getDestinationCFrame(player))` | Void rescue system teleportation at Y < -200. |
| `src/server/ServerMain.server.luau` | 553 | `p:LoadCharacter()` | Initial player join character load fallback loop. |
| `src/server/Services/RoundService.luau` | 164 | `player:LoadCharacter()` | Bypasses central spawn system to reload dead/missing players during round reset. |
| `src/server/Services/RoundService.luau` | 177 | `root.CFrame = CFrame.new(spawnPos)` | Directly sets HRP CFrame for round spawn reset. |
| `src/server/Services/DirectChallengeService.luau` | 146, 155 | `hrp.CFrame = redCFrame` / `blueCFrame` | Directly positions 1v1 challenger/target. |
| `src/server/Services/DirectChallengeService.luau` | 148, 157 | `challengerChar:PivotTo(redCFrame)` | Ad-hoc fallback positioning for 1v1 duels. |
| `src/server/Services/QueueMatchmakingService.luau` | 433 | `character:PivotTo(CFrame.new(matchPlayer.spawnPosition))` | Directly teleports matched players to match spawns. |
| `src/server/Services/SocialInviteService.luau` | 148, 150 | `joiningRoot.CFrame = inviterRoot.CFrame * CFrame.new(3,0,3)` | Direct teleportation to friend's position. |
| `src/server/Services/BotService.luau` | 335, 339 | `botData.humanoid:MoveTo(targetPos)` | NPC Bot pathfinding movement (valid non-player use case). |
| `src/client/UI/LoadoutInspectorUI.luau` | 749 | `previewWeaponModel:PivotTo(...)` | Client 3D ViewportFrame weapon rotation (valid non-character use case). |

### Key Issues Identified in Current Spawning Architecture:
1. **Multiple Callers of `Player:LoadCharacter()`**: Both `ServerMain.server.luau` and `RoundService.luau` call `Player:LoadCharacter()`.
2. **Scattered `PivotTo` / `CFrame` Teleports**: `QueueMatchmakingService`, `DirectChallengeService`, `SocialInviteService`, `RoundService`, and `ServerMain` all manipulate `HumanoidRootPart.CFrame` or call `Model:PivotTo()` directly.
3. **Hardcoded Fallback CFrames**: `ServerMain.server.luau` defines hardcoded constants:
   - `local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 106, 0)`
   - `local PRACTICE_CFRAME = CFrame.new(500, 105, 60)`
   instead of querying map modules or `MapRegistry`.
4. **Duplicate Spawn Semaphore**: `ServerMain` uses a local `spawnInProgress` table, but because callers directly invoke `LoadCharacter` or `PivotTo` in other services, race conditions can occur.

---

## 2. Audit of Map Modules & `MAP_OFFSET` Consistency

All map modules located in `src/shared/Map/` were inspected to assess spawn point definitions, world space offsets, and safety validation.

### Map Audit Findings

| Map Module | Build Base Location | Spawn Points Defined | `MAP_OFFSET` Usage | Status / Observations |
|---|---|---|---|---|
| `LobbyFolder.luau` | `LOBBY_CENTER = (0, 100, 0)` | 6 `SpawnLocation` objects in `SpawnLocations` folder | Built at absolute center `(0, 100, 0)` | Spawns are placed at Y = 101.5 on top of a solid 300x300 floor at Y = 98..100. |
| `PracticeRangeMapLayout.luau` | `MAP_OFFSET = (500, 100, 0)` | 3 player spawn nodes (`Spawn_Player_1..3`) | `MAP_OFFSET` correctly added to all parts and accessor methods | `GetSpawnPoints()` returns `{ (500, 102, 60), (490, 102, 60), (510, 102, 60) }`. However, `ServerMain` bypassed this API and hardcoded `(500, 105, 60)`. |
| `GreyboxArenaMap.luau` | Origin `(0, 0, 0)` | 5 Red spawns `(-12..12, 2, -100)`, 5 Blue spawns `(-12..12, 2, 100)` | Built around origin (Y = 0) | Returns spawn positions relative to arena origin. |
| `DuelArenaMap.luau` | Origin `(0, 0, 0)` | 4 Red spawns `(-12..12, 2, -60)`, 4 Blue spawns `(-12..12, 2, 60)` | Built around origin (Y = 0) | Returns spawn positions relative to arena origin. |
| `UrbanWarehouseMap.luau` | Origin `(0, 0, 0)` | 5 Red spawns `(-14..14, 2, -105)`, 5 Blue spawns `(-14..14, 2, 105)` | Built around origin (Y = 0) | Returns spawn positions relative to arena origin. |
| `MapRegistry.luau` | Central Registry | Standardized `GetSpawnPoints(teamName)` interface | Dispatches to registered map modules | Exposes map loading and metadata retrieval for all 9 maps. |

### Floor Validation Gaps Identified:
1. `ServerMain.server.luau` contains a `verifyLobbyFloor()` function (lines 73-88) that only validates Lobby spawn points.
2. No automated downward raycast validation currently exists for:
   - Practice Range spawn points.
   - Competitive match spawn points (`GreyboxArenaMap`, `DuelArenaMap`, `UrbanWarehouseMap`).
3. Requirement R3 demands an authoritative `assertMapReady` validation step that raycasts downward from all spawn points immediately after map construction to guarantee collidable floor existence.

---

## 3. Design Formulation: `SpawnService` (Single Spawn Authority)

To fulfill Requirement R2, `SpawnService` will be created in `src/server/Services/SpawnService.luau` (mapped to `ServerScriptService/Services/SpawnService.luau`).

### Key Design Principles:
1. **Absolute Ownership**: `SpawnService` is the **ONLY** file permitted to call `Player:LoadCharacter()`, set `player.RespawnLocation`, or call `character:PivotTo()`.
2. **Centralized Location State**: `SpawnService` tracks player location (`"Lobby" | "PracticeRange" | "Match"`).
3. **Concurrency Locking**: Prevents double-spawning via a mutex/debounce per player.
4. **Void Safety Net**: Integrated heartbeat checking for falling players (Y < -200), auto-rescuing them back to their authoritative spawn CFrame.

### Proposed `SpawnService` Module Interface:

```luau
--!strict
--[=[
    Project OVERCLOCK: SpawnService
    Single authoritative owner of character loading, respawning, and teleportation.
]=]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpawnService = {}

type PlayerLocation = "Lobby" | "PracticeRange" | "Match"

local _playerLocation: { [number]: PlayerLocation } = {}
local _spawnInProgress: { [number]: boolean } = {}
local _combatServerRef: any = nil

function SpawnService.Init(combatServer: any?)
    _combatServerRef = combatServer
    Players.CharacterAutoLoads = false
    
    Players.PlayerAdded:Connect(function(player)
        SpawnService.OnPlayerAdded(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        SpawnService.OnPlayerRemoving(player)
    end)
    
    -- Start Void Rescue loop
    SpawnService.StartVoidRescueMonitor()
    print("[SPAWN] SpawnService initialized cleanly.")
end

--- Authoritative function to load or position a player at a target destination.
function SpawnService.SpawnPlayer(player: Player, destination: PlayerLocation, targetCFrame: CFrame?): boolean
    if not player or not player.Parent then return false end
    local userId = player.UserId
    
    if _spawnInProgress[userId] then
        warn("[SPAWN] Blocked concurrent spawn request for " .. player.Name)
        return false
    end
    _spawnInProgress[userId] = true
    _playerLocation[userId] = destination
    
    local resolvedCFrame = targetCFrame or SpawnService.GetDestinationCFrame(player, destination)
    
    if destination == "Lobby" then
        local lobbySpawns = SpawnService.GetLobbySpawns()
        if #lobbySpawns > 0 then
            player.RespawnLocation = lobbySpawns[((math.abs(userId) - 1) % #lobbySpawns) + 1]
        end
    else
        player.RespawnLocation = nil
    end
    
    player:LoadCharacter()
    
    -- Positioning on CharacterAdded
    local char = player.Character or player.CharacterAdded:Wait()
    if char then
        local hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
        if hrp then
            char:PivotTo(resolvedCFrame)
        end
    end
    
    task.delay(1.5, function()
        _spawnInProgress[userId] = nil
    end)
    
    print(("[SPAWN] Player %s -> %s"):format(player.Name, destination))
    return true
end

--- Teleports an existing character to a target CFrame without reloading the character model.
function SpawnService.TeleportCharacter(player: Player, targetCFrame: CFrame): boolean
    if not player or not player.Character then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if hrp then
        player.Character:PivotTo(targetCFrame)
        return true
    end
    return false
end

function SpawnService.GetDestinationCFrame(player: Player, destination: PlayerLocation): CFrame
    if destination == "PracticeRange" then
        local MapFolder = ReplicatedStorage:FindFirstChild("Map")
        if MapFolder then
            local prMod = MapFolder:FindFirstChild("PracticeRangeMapLayout")
            if prMod then
                local layout = require(prMod :: any)
                local spawns = layout.GetSpawnPoints()
                if #spawns > 0 then
                    return CFrame.new(spawns[1] + Vector3.new(0, 3, 0))
                end
            end
        end
        return CFrame.new(500, 105, 60)
    elseif destination == "Lobby" then
        local MapFolder = ReplicatedStorage:FindFirstChild("Map")
        if MapFolder then
            local lobbyMod = MapFolder:FindFirstChild("LobbyFolder")
            if lobbyMod then
                local layout = require(lobbyMod :: any)
                local spawns = layout.GetSpawnLocations()
                if #spawns > 0 then
                    local spawn = spawns[((math.abs(player.UserId) - 1) % #spawns) + 1]
                    return spawn.CFrame + Vector3.new(0, 3, 0)
                end
            end
        end
        return CFrame.new(0, 106, 0)
    end
    return CFrame.new(0, 106, 0)
end

return SpawnService
```

---

## 4. Design Formulation: `assertMapReady` & Raycast Safety

To fulfill Requirement R3, map verification will be standardized via an `assertMapReady` function.

### Downward Raycast Mechanics:
1. **Ray Origin**: `spawnPosition + Vector3.new(0, 10, 0)` (10 studs above designated spawn point).
2. **Ray Direction**: `Vector3.new(0, -30, 0)` (30 studs downward).
3. **RaycastParams**:
   - `IgnoreWater = true`
   - `RespectCanCollide = true`
   - `CollisionGroup = "Default"`
4. **Validation Criteria**:
   - Raycast hit must return a valid `RaycastResult`.
   - `hit.Instance.CanCollide` must be `true`.
   - Distance from spawn point to hit point must be <= 12 studs.
5. **Console Logging Requirement**:
   - Output must explicitly log: `[MAP] Every spawn has collidable floor`.

### Implementation Outline (`src/shared/Map/MapSafety.luau` or embedded helper):

```luau
--!strict
local Workspace = game:GetService("Workspace")

local MapSafety = {}

function MapSafety.assertMapReady(mapName: string, spawnPositions: { Vector3 }): boolean
    local params = RaycastParams.new()
    params.IgnoreWater = true
    params.RespectCanCollide = true
    params.FilterType = Enum.RaycastFilterType.Exclude

    print(("[MAP] Validating %d spawn points for %s..."):format(#spawnPositions, mapName))

    for index, pos in ipairs(spawnPositions) do
        local origin = pos + Vector3.new(0, 10, 0)
        local direction = Vector3.new(0, -30, 0)
        local result = Workspace:Raycast(origin, direction, params)

        if not result then
            error(("[MAP ERROR] Spawn %d at %s has NO floor beneath it!"):format(index, tostring(pos)))
        end

        if not result.Instance.CanCollide then
            error(("[MAP ERROR] Spawn %d floor %s is not collidable!"):format(index, result.Instance:GetFullName()))
        end
    end

    print("[MAP] Every spawn has collidable floor")
    return true
end

return MapSafety
```

---

## 5. Refactoring Plan & Action Items for Implementer

1. **Create `SpawnService.luau`**:
   - Place in `src/server/Services/SpawnService.luau`.
   - Implement single spawn authority, `SpawnPlayer`, `TeleportCharacter`, `GetDestinationCFrame`, and void safety net.
2. **Refactor `ServerMain.server.luau`**:
   - Remove ad-hoc `player:LoadCharacter()`, `setPlayerRespawnToLobby`, `moveCharacterToDestination`, `loadAtDestination`, `attachVoidRescue`.
   - Delegate all player joins, practice range transitions, lobby returns, and death handling to `SpawnService`.
3. **Refactor Other Server Services**:
   - `RoundService.luau`: Replace direct `player:LoadCharacter()` and `root.CFrame = CFrame.new(spawnPos)` calls with `SpawnService.TeleportCharacter` or `SpawnService.SpawnPlayer`.
   - `DirectChallengeService.luau`: Replace manual `PivotTo` calls with `SpawnService.TeleportCharacter`.
   - `QueueMatchmakingService.luau`: Replace manual `PivotTo` calls with `SpawnService.TeleportCharacter`.
   - `SocialInviteService.luau`: Replace manual `PivotTo` calls with `SpawnService.TeleportCharacter`.
4. **Implement Map Raycast Safety Validation**:
   - Add `assertMapReady` in `src/shared/Map/MapSafety.luau` or `MapRegistry.luau`.
   - Execute `assertMapReady` after building Lobby, Practice Range, Greybox Arena, Duel Arena, and Urban Warehouse maps during server boot.
