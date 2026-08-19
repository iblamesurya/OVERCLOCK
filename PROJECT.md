# Project: OVERCLOCK Tactical Shooter Server-Authoritative Refactor

## Architecture
- **Shared (`ReplicatedStorage`):** Types, Constants, WeaponStats, Network/Remotes, Map layouts.
- **Server (`ServerScriptService`):** ServerMain, BootstrapService, SpawnService, MatchService, RoundService, QueueService, ProfileService, CombatService, Tests.
- **Client (`StarterPlayerScripts`):** ClientMain, Controllers, UI controllers.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Server Boot Reliability | `safeInit` wrapper with pcall & task.spawn logging `[BOOT] 1/6` to `[BOOT] 6/6 Server ready` | M1 | R1 |
| 2 | safeRequire Timeout | 5s timeout on `WaitForChild` inside `safeRequire` to prevent infinite hangs | M1 | R1 |
| 3 | Single Spawn Authority | `SpawnService.luau` sole owner of `LoadCharacter()`, `RespawnLocation`, `PivotTo()` | M2 | R2 |
| 4 | Remove Ad-Hoc Spawns | Refactor 6 server scripts to use `SpawnService` methods exclusively | M2 | R2 |
| 5 | Map Raycast Floor Validation | `assertMapReady` downward raycasts for spawn points, printing `[MAP] Every spawn has collidable floor` | M3 | R3 |
| 6 | Map Offset Consistency | Ensure map layout APIs apply `MAP_OFFSET` consistently without hardcoded offsets in `ServerMain` | M3 | R3 |
| 7 | Unified Remotes Directory | ReplicatedStorage/Network/Remotes containing all RemoteEvents/Functions initialized in Stage 1/6 | M4 | R4 |
| 8 | Listener Input Validation | Add strict type, bounds, rate limit, and match state checks to server `OnServerEvent` listeners | M4 | R4 |
| 9 | Structural Reorganization | Enforce clean separation across Shared (`src/shared`), Server (`src/server`), Client (`src/client`) | M5 | R5 |
| 10 | Startup Smoke Test | `ServerScriptService/Tests/StartupSmokeTest.luau` validating mandatory systems, remotes, map folders | M6 | R6 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Server Boot Reliability & Staged Sequence | Refactor `ServerMain.server.luau` with 5s timeout on `safeRequire` and 6-stage `safeInit` logging | none | DONE |
| 2 | M2: Single Spawn Authority (SpawnService) | Create src/server/Services/SpawnService.luau & refactor ad-hoc spawn/pivot calls in server scripts | M1 | DONE |
| 3 | M3: Map Validation & Layout Safety | Implement `assertMapReady` downward raycasts & enforce `MAP_OFFSET` in layout APIs | M1 | DONE |
| 4 | M4: Network Security & Unified Remotes | Relocate remotes to `ReplicatedStorage/Network/Remotes`, initialize in Stage 1/6, secure listeners | M1 | DONE |
| 5 | M5: Structural Reorganization & Directory Cleanliness | Verify & maintain clean folder boundaries (`src/shared`, `src/server`, `src/client`) | M1 | DONE |
| 6 | M6: Startup Smoke Test & E2E Integration | Create `src/server/Tests/StartupSmokeTest.luau` and perform E2E verification | M1, M2, M3, M4, M5 | DONE |

## Interface Contracts

### SpawnService API
- `SpawnService.SpawnPlayer(player: Player, destinationType: "Lobby" | "PracticeRange" | "Match", customCFrame: CFrame?): Model`
- `SpawnService.TeleportCharacter(player: Player, cframe: CFrame): boolean`
- `SpawnService.SetPlayerLocation(player: Player, location: "Lobby" | "PracticeRange" | "Match")`
- `SpawnService.GetPlayerLocation(player: Player): "Lobby" | "PracticeRange" | "Match"`
- `SpawnService.HandleCharacterRespawn(player: Player): ()`

### Map Safety API
- `MapSafety.assertMapReady(mapFolder: Instance, spawnPoints: {CFrame}): boolean`
- `MapSafety.verifySpawnPointFloor(spawnCFrame: CFrame): (boolean, string?)`

### Network Remotes API
- Path: `ReplicatedStorage.Network.Remotes`
- Subfolders: `Reliable` (RemoteEvents), `Unreliable` (UnreliableRemoteEvents), `Functions` (RemoteFunctions)
- Server initialization function: `RemoteEvents.Initialize()`

### Startup Smoke Test API
- Path: `ServerScriptService.Tests.StartupSmokeTest`
- Function: `StartupSmokeTest.Run(): (boolean, {string})`

## Code Layout
- `src/shared/Network/RemoteEvents.luau` -> `ReplicatedStorage.Network.RemoteEvents`
- `src/shared/Network/QueueEvents.luau` -> `ReplicatedStorage.Network.QueueEvents`
- `src/shared/Network/ChallengeEvents.luau` -> `ReplicatedStorage.Network.ChallengeEvents`
- `src/shared/Map/MapSafety.luau` -> `ReplicatedStorage.Map.MapSafety`
- `src/server/ServerMain.server.luau` -> `ServerScriptService.ServerMain`
- `src/server/Services/SpawnService.luau` -> `ServerScriptService.Services.SpawnService`
- `src/server/Tests/StartupSmokeTest.luau` -> `ServerScriptService.Tests.StartupSmokeTest`
