# Milestone 5 (M5_Maps_Environment) Technical Analysis & Implementation Specification

## Executive Summary
This analysis document specifies the concrete implementation design for **Milestone 5 (M5_Maps_Environment)** in Project OVERCLOCK. It details how Worker 5 will update `MapRegistry.luau` and construct two procedural 3D map generator modules:
1. `src/shared/Map/DuelArenaMap.luau`: A 2-3 lane competitive tactical greybox arena designed for 1v1 and 2v2 PvP matches.
2. `src/shared/Map/PracticeRangeMapLayout.luau`: An open sandbox firing range layout featuring a stationary target wall section (`Target_Stationary_1..N`) and a patrol bot arena section with 3D waypoints (`Waypoints_Bot_1..N`).

---

## 1. Existing Map Infrastructure Investigation

### 1.1 `src/shared/Map/MapRegistry.luau`
- **Current Behavior**: Manages map registration, dynamic loading (`LoadMapInstance`), unloading (`UnloadMapInstance`), and metadata querying.
- **Auto-Registration**: Automatically scans `script.Parent` for modules ending in `Map.luau` or listed in `defaultMapNames`, stripping the `"Map"` suffix to derive `cleanId`.
- **Type Contract**:
  - `MapLayoutData`: `{ mapId: string, mapName: string, theme: string, bounds: MapBounds, redSpawns: { Vector3 }, blueSpawns: { Vector3 }, sites: SitePositions?, coverPositions: { Vector3 }, lanes: { [string]: LaneData } }`
  - `MapModule`: Must implement `BuildMap(parent)`, `DestroyMap()`, `GetSpawnPoints(teamName)`, `GetCoverPositions()`, `GetSitePositions()`, `GetMapBounds()`, and `GetLayoutData()`.
- **Required Modifications**:
  - Update `AutoRegisterDefaultMaps()` to recognize `"DuelArenaMap"` (cleanId `"DuelArena"`) and `"PracticeRangeMapLayout"` (cleanId `"PracticeRangeMap"`).
  - Add null-guards in `GetMapMetadata()` for maps without bomb sites (e.g., Practice Range).

### 1.2 `src/shared/Map/GreyboxArenaMap.luau`
- **Pattern**: Procedurally instantiates Parts and WedgeParts into organized Workspace sub-folders (`Perimeter`, `Spawns`, `Lanes`, `Sites`, `Cover`).
- **Properties Enforced**: Sets `Anchored = true`, `CanCollide`, `Material`, `Color3`, `Size`, `CFrame`, and attributes (`Team`, `Index`, `SiteName`).

### 1.3 `src/shared/Map/LobbyFolder.luau`
- **Lobby Elevation**: Base floor at `Y = 100` (Center `Vector3.new(0, 100, 0)`).
- **Spawn Management**: Contains `SpawnLocations` with attribute `LobbySpawnIndex`.
- **Interactions**: `InteractiveTriggers` with ProximityPrompts for `Play`, `Challenge`, `Loadout`, and `Settings`.

### 1.4 `src/server/ServerMain.server.luau`
- **Bootstrap Flow**:
  1. Calls `MapRegistry.AutoRegisterDefaultMaps()`.
  2. Spawns default map instance and `LobbyFolder`.
  3. Disables all non-lobby `SpawnLocation` instances (`desc:GetAttribute("LobbySpawnIndex") == nil`).
  4. Generates safety baseplate at `Y = 95`.

---

## 2. Worker 5 File Implementation Specifications

### Task 1: `src/shared/Map/MapRegistry.luau` Refactoring
Worker 5 must update `MapRegistry.luau` to:
1. Extend `defaultMapNames` to include `"DuelArenaMap"` and `"PracticeRangeMapLayout"`.
2. Update `AutoRegisterDefaultMaps()` clean ID resolution logic:
   ```luau
   local cleanId = name
   if name == "DuelArenaMap" then
       cleanId = "DuelArena"
   elseif name == "PracticeRangeMapLayout" or name == "PracticeRangeMap" then
       cleanId = "PracticeRangeMap"
   else
       cleanId = name:gsub("Map$", "")
   end
   ```
3. Update `GetMapMetadata()` to safely handle optional sites:
   ```luau
   local sites = layout.sites
   return {
       mapId = layout.mapId or mapId,
       mapName = layout.mapName or mapId,
       theme = layout.theme or "Tactical Greybox",
       bounds = layout.bounds,
       spawnCountRed = layout.redSpawns and #layout.redSpawns or 0,
       spawnCountBlue = layout.blueSpawns and #layout.blueSpawns or 0,
       siteA = sites and sites.siteA or Vector3.zero,
       siteB = sites and sites.siteB or Vector3.zero,
   }
   ```

---

### Task 2A: `src/shared/Map/DuelArenaMap.luau` Generator Specification
Worker 5 must create `src/shared/Map/DuelArenaMap.luau` adhering to the following structure:

#### Map Parameters & Dimensions
- **Dimensions**: Width (X) = 120 studs, Length (Z) = 160 studs, Height (Y) = 30 studs.
- **Folder Name**: `"DuelArenaMap"`.
- **Theme**: Dark Tactical Greybox (`Color3.fromRGB(25, 28, 35)` base floor, `Color3.fromRGB(40, 44, 52)` walls, `Color3.fromRGB(0, 170, 255)` / `Color3.fromRGB(255, 60, 60)` team accents).

#### Spawn Points Specification
- **Team 1 / Red Spawns** (Z = -60):
  - `Spawn_Team1_1`: Position `Vector3.new(-12, 2, -60)`
  - `Spawn_Team1_2`: Position `Vector3.new(12, 2, -60)`
  - `Spawn_Team1_3`: Position `Vector3.new(-4, 2, -64)`
  - `Spawn_Team1_4`: Position `Vector3.new(4, 2, -64)`
- **Team 2 / Blue Spawns** (Z = +60):
  - `Spawn_Team2_1`: Position `Vector3.new(-12, 2, 60)`
  - `Spawn_Team2_2`: Position `Vector3.new(12, 2, 60)`
  - `Spawn_Team2_3`: Position `Vector3.new(-4, 2, 64)`
  - `Spawn_Team2_4`: Position `Vector3.new(4, 2, 64)`
- Each spawn node must be a Part in `Spawns/Team1Spawn` or `Spawns/Team2Spawn` with:
  - `Size = Vector3.new(4, 1, 4)`
  - `Anchored = true`, `CanCollide = false`
  - Attributes: `Team = "Team1"` (or `"Team2"`), `SpawnIndex = i`

#### Layout & Cover Structures (2-3 Lanes)
1. **Main Center Lane**: Center `Vector3.new(0, 0.2, 0)`, Size `Vector3.new(20, 0.4, 120)`. Features central high pillar cover `Pillar_Center` (`Size = Vector3.new(6, 10, 6)`) and low half-walls `LowCover_Mid_1`, `LowCover_Mid_2`.
2. **Left Flank Lane**: Center `Vector3.new(-40, 0.2, 0)`, Size `Vector3.new(18, 0.4, 120)`. Features staggered low cover blocks `LowCover_Left_1`, `LowCover_Left_2`.
3. **Right Flank Lane**: Center `Vector3.new(40, 0.2, 0)`, Size `Vector3.new(18, 0.4, 120)`. Features sniper perch `Perch_Right` (`Vector3.new(40, 6, 0)`) and access ramp.
4. **Cross Connectors**: `Connector_North` (`Z = -30`) and `Connector_South` (`Z = 30`) linking Mid to Flanks.
5. **Perimeter Walls**: Boundary walls enclosing the 120x160 arena with height 30 studs.

#### API Interface Functions
```luau
function DuelArenaMap.BuildMap(parent: Instance?): Folder
function DuelArenaMap.DestroyMap()
function DuelArenaMap.GetSpawnPoints(teamName: string): { Vector3 }
function DuelArenaMap.GetCoverPositions(): { Vector3 }
function DuelArenaMap.GetSitePositions(): { siteA: Vector3, siteB: Vector3 }
function DuelArenaMap.GetMapBounds(): (Vector3, Vector3)
function DuelArenaMap.GetLayoutData(): MapLayoutData
```
`GetSpawnPoints` must resolve both `"Team1"` / `"Red"` and `"Team2"` / `"Blue"`.

---

### Task 2B: `src/shared/Map/PracticeRangeMapLayout.luau` Generator Specification
Worker 5 must create `src/shared/Map/PracticeRangeMapLayout.luau` adhering to the following structure:

#### Map Parameters & Dimensions
- **Dimensions**: Width (X) = 140 studs, Length (Z) = 200 studs, Height (Y) = 35 studs.
- **Folder Name**: `"PracticeRangeMap"`.
- **Theme**: Industrial Firing Range (`Color3.fromRGB(30, 32, 40)` floor, range markers at 10m, 25m, 50m, neon cyan trim).

#### (a) Stationary Target Wall Section
- Located at North wall (`Z = -80`).
- **Backboard**: `TargetWallBackboard` (`Size = Vector3.new(100, 20, 2)`, CFrame `CFrame.new(0, 10, -82)`).
- **Target Parts** (`Target_Stationary_1` to `Target_Stationary_6`):
  - `Target_Stationary_1`: CFrame `CFrame.new(-30, 6, -80)`, Size `Vector3.new(4, 4, 0.5)`
  - `Target_Stationary_2`: CFrame `CFrame.new(-15, 10, -80)`, Size `Vector3.new(3, 3, 0.5)`
  - `Target_Stationary_3`: CFrame `CFrame.new(0, 8, -80)`, Size `Vector3.new(4, 4, 0.5)`
  - `Target_Stationary_4`: CFrame `CFrame.new(15, 12, -80)`, Size `Vector3.new(3, 3, 0.5)`
  - `Target_Stationary_5`: CFrame `CFrame.new(30, 6, -80)`, Size `Vector3.new(4, 4, 0.5)`
  - `Target_Stationary_6`: CFrame `CFrame.new(0, 14, -80)`, Size `Vector3.new(2.5, 2.5, 0.5)`
- **Bullseye Center Discs**: Each target includes a nested cylinder/disc part with attribute `IsBullseye = true` and parent reference.
- Target parts must have attributes: `TargetId = i`, `TargetType = "Stationary"`, `IsTarget = true`.

#### (b) Patrol Bot Arena Section
- Located in open mid-range area (`Z = -40` to `Z = 20`).
- **3D Waypoints** (`Waypoints_Bot_1` to `Waypoints_Bot_8`):
  - `Waypoints_Bot_1`: `Vector3.new(-35, 2, -20)`
  - `Waypoints_Bot_2`: `Vector3.new(-15, 2, -40)`
  - `Waypoints_Bot_3`: `Vector3.new(15, 2, -40)`
  - `Waypoints_Bot_4`: `Vector3.new(35, 2, -20)`
  - `Waypoints_Bot_5`: `Vector3.new(35, 2, 10)`
  - `Waypoints_Bot_6`: `Vector3.new(15, 2, 20)`
  - `Waypoints_Bot_7`: `Vector3.new(-15, 2, 20)`
  - `Waypoints_Bot_8`: `Vector3.new(-35, 2, 10)`
- Waypoints stored in `PatrolBotSection/Waypoints` folder as uncollidable Parts (`Size = Vector3.new(2, 0.2, 2)`, `Transparency = 0.5`, `Neon`, `CanCollide = false`, `Anchored = true`, attribute `WaypointIndex = i`).

#### Player Spawn & Control Deck
- **Firing Deck**: Located at `Z = 60` (`Size = Vector3.new(100, 1, 30)`).
- **Player Spawns**: `Spawn_Player_1` (`Vector3.new(0, 2, 60)`), `Spawn_Player_2` (`Vector3.new(-10, 2, 60)`), `Spawn_Player_3` (`Vector3.new(10, 2, 60)`).
- **Control Pedestals**: Weapon rack and operative selector terminal pads.

#### API Interface Functions
```luau
function PracticeRangeMapLayout.BuildMap(parent: Instance?): Folder
function PracticeRangeMapLayout.DestroyMap()
function PracticeRangeMapLayout.GetSpawnPoints(teamName: string): { Vector3 }
function PracticeRangeMapLayout.GetStationaryTargets(): { BasePart }
function PracticeRangeMapLayout.GetBotWaypoints(): { Vector3 }
function PracticeRangeMapLayout.GetCoverPositions(): { Vector3 }
function PracticeRangeMapLayout.GetSitePositions(): { siteA: Vector3, siteB: Vector3 }
function PracticeRangeMapLayout.GetMapBounds(): (Vector3, Vector3)
function PracticeRangeMapLayout.GetLayoutData(): MapLayoutData
```

---

### Task 3: Unit Tests & Build Verification
Worker 5 must create unit tests for map integrity:
1. `src/shared/Map/DuelArenaMap.spec.luau`: Tests building, folder hierarchy (`Spawns`, `Lanes`, `Cover`, `Perimeter`), team spawn resolution (`Team1`, `Team2`), cover points, layout bounds, and clean teardown.
2. `src/shared/Map/PracticeRangeMapLayout.spec.luau`: Tests building, target wall verification (`Target_Stationary_1..6`), bot waypoints verification (`Waypoints_Bot_1..8`), player spawn points, and teardown.
3. `src/shared/Map/MapRegistry.spec.luau`: Updated to test registration and metadata for `"DuelArena"` and `"PracticeRangeMap"`.

---

## 3. Physical Property & Collision Checklist
Every part created by the map generator modules must strictly follow:
- `Anchored = true` (all architectural parts, cover blocks, walls, targets, spawn pads, waypoints).
- `CanCollide = true` for structural floor, boundary walls, cover blocks, target wall backboards.
- `CanCollide = false` for spawn nodes (`Spawn_Team1_*`, `Spawn_Team2_*`), stationary target center discs (so bullet raycasts can hit the parent target), and bot waypoint markers (`Waypoints_Bot_*`).
- `TopSurface = Enum.SurfaceType.Smooth`, `BottomSurface = Enum.SurfaceType.Smooth`.
- Clear parent assignment to sub-folders before parenting the map folder to `Workspace`.

---

## 4. Verification Method for Worker 5
1. Execute `rojo build default.project.json -o RivalsParadigm.rbxl` to confirm zero compilation or syntax errors.
2. Run test spec files (`DuelArenaMap.spec.luau`, `PracticeRangeMapLayout.spec.luau`, `MapRegistry.spec.luau`) in Roblox Studio command bar or server runner to verify 100% assertions pass.
