# Milestone 4 (M4_Practice_Range_Bots) — Technical Analysis & Implementation Specification

## Executive Summary
This document provides a concrete, file-by-file implementation specification for **Worker 4** to build **Milestone 4: Practice Range Bots & Live Accuracy Stats** in Project OVERCLOCK. 

Milestone 4 introduces:
1. **`src/server/Services/BotService.luau`**:
   - **Stationary Target Wall Manager**: Hit detection, visual/audio hit feedback (CFrame tilt tween, hit pop/ding audio), per-target and total hit counters, and remote reset capability.
   - **Patrol Bot AI Lifecycle**: Spawning 4–6 moving bot humanoids in `PatrolBotSection`, continuous waypoint navigation (`Waypoints_Bot_1..8`) using `Humanoid:MoveTo()`, 8-second stuck protection timeouts, and 1-second waypoint pause delays.
   - **Bot Combat Integration**: Seamless hit validation and damage application via the shared `CombatServer` raycast code path, headshot detection on `"Head"` parts, death handling on `HP <= 0`, and automatic 3-second respawn at origin spawn pads.
2. **Practice Range Live Accuracy Stats Tracker**:
   - Per-session accuracy metrics: total shots fired, total hits, headshots, accuracy %, headshot %.
   - Server-side shot/hit ingestion hooked to `CombatServer` network events.
   - Real-time client replication (`RangeStatsUpdated` RemoteEvent) and `ResetRangeStats` remote handling.
3. **Unit Test Suite (`src/server/Services/BotService.spec.luau`)**:
   - Complete automated test script validating map binding, bot spawning, waypoint navigation, target hits, damage/death/respawn cycles, stat math calculations, and reset routines.

---

## 1. Codebase Architecture & Code Examination Findings

### 1.1 `src/shared/Map/PracticeRangeMapLayout.luau`
- **Folder Structure**: Spawns `PracticeRangeMap` folder in `Workspace`.
- **Target Wall Section (`TargetWallSection`)**:
  - Backboard at `Z = -82`.
  - Target parts `Target_Stationary_1` through `Target_Stationary_6` positioned between `X = -30` and `X = 30`, `Y = 6` to `14`, `Z = -80`.
  - Target part attributes: `IsTarget = true`, `TargetType = "Stationary"`, `TargetId = 1..6`.
  - Child part `Bullseye`: Size `(X*0.4, Y*0.4, Z+0.1)`, `IsBullseye = true`, `TargetId = 1..6`, `CanCollide = false`.
- **Patrol Bot Arena (`PatrolBotSection`)**:
  - Folder `Waypoints` containing `Waypoints_Bot_1` through `Waypoints_Bot_8`.
  - Waypoint positions: `(-35, 2, -20)`, `(-15, 2, -40)`, `(15, 2, -40)`, `(35, 2, -20)`, `(35, 2, 10)`, `(15, 2, 20)`, `(-15, 2, 20)`, `(-35, 2, 10)`.
  - Helper functions: `PracticeRangeMapLayout.GetStationaryTargets()`, `PracticeRangeMapLayout.GetBotWaypoints()`, `PracticeRangeMapLayout.GetSpawnPoints()`.
- **Player Spawns (`Spawns.PlayerSpawn`)**:
  - `Spawn_Player_1` .. `3` at `Z = 60`, `Y = 2`.

### 1.2 `src/server/Combat/CombatServer.luau`
- **Match Phase Support**: `ProcessHitReport` permits hits when `self._matchPhase == "InGame"` or `self._matchPhase == "PracticeRange"`.
- **Non-Player / Bot Victim Handling (Lines 319–335)**:
  - When `victimUserId == 0` or victim player is nil:
  - Resolves `targetModel = payload.targetInstance:FindFirstAncestorOfClass("Model")`.
  - If `botHumanoid = targetModel:FindFirstChildOfClass("Humanoid")` exists: calls `botHumanoid:TakeDamage(rawDamage)` and returns `true, nil, botHumanoid.Health`.
  - If `targetInstance` is a target part (`IsPracticeTarget`, `Target_Stationary_N`, etc.): returns `true, nil, 0`.
- **Headshot Multiplier & Damage**:
  - `isHeadshot = payload.isHeadshot or (payload.targetInstance.Name == "Head")`.
  - Calls `WeaponStats.CalculateDamage(weaponId, isHeadshot, distance)`.

### 1.3 `src/server/ServerMain.server.luau`
- Handles player join/leave lifecycle, DataStore profile loading, and match state management.
- Requires registration and initialization of `BotService` during server startup or when loading the Practice Range map layout.

---

## 2. Implementation Specification for Worker 4

### 2.1 File Location: `src/server/Services/BotService.luau`

#### Module Contract & Data Types
```luau
--!strict
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapFolder = ReplicatedStorage:WaitForChild("Map")
local PracticeRangeMapLayout = require(MapFolder:WaitForChild("PracticeRangeMapLayout") :: any)

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

export type PracticeRangeStats = {
    totalShotsFired: number,
    totalHits: number,
    totalHeadshots: number,
    accuracyPercent: number,
    headshotPercent: number,
}

export type BotData = {
    botId: number,
    model: Model,
    humanoid: Humanoid,
    originSpawnPos: Vector3,
    currentWaypointIndex: number,
    isAlive: boolean,
    moveThread: thread?,
}

export type TargetState = {
    id: number,
    targetPart: BasePart,
    bullseyePart: BasePart?,
    hitCount: number,
    originalCFrame: CFrame,
    originalColor: Color3,
    isAnimating: boolean,
}

local BotService = {}
```

#### Component Details

1. **Stationary Target Wall Manager**:
   - `BotService.InitTargetWall(mapFolder: Folder)`:
     - Scans `TargetWallSection` in `mapFolder`.
     - Initializes `TargetState` map for `Target_Stationary_1` .. `Target_Stationary_6`.
     - Stores original CFrame and Color for reset/animation routines.
   - `BotService.ProcessTargetHit(player: Player?, targetPart: BasePart, isBullseye: boolean)`:
     - Finds target state matching `targetPart` or `targetPart.Parent`.
     - Increments target `hitCount += 1`.
     - Plays hit audio: Creates a transient `Sound` instance (`SoundId = "rbxassetid://9114223178"`, `Volume = 0.5`, `Pitch = isBullseye and 1.2 or 1.0`) attached to `targetPart`, plays it, and cleans up via `Debris:AddItem(sound, 1.5)`.
     - Plays visual tilt animation: Tweens target `Color3` to bright highlight `Color3.fromRGB(255, 230, 80)` and tilts CFrame by -15 degrees (`originalCFrame * CFrame.Angles(math.rad(-15), 0, 0)`) over `0.1s`, then back to `originalCFrame` and `originalColor` over `0.15s`.
     - Calls `BotService.RecordHit(player, isBullseye)`.
   - `BotService.ResetTargets()`:
     - Resets all target `hitCount = 0`.
     - Cancels active tweens and restores original CFrames and Colors.

2. **Patrol Bot AI Lifecycle**:
   - `BotService.SpawnPatrolBots(count: number?, mapFolder: Folder?)`:
     - Spawns `count` (default: 5) procedural bot models inside `PatrolBotSection`.
     - Model setup:
       - `Model` named `PatrolBot_<id>`.
       - `Humanoid` (`MaxHealth = 100`, `Health = 100`, `WalkSpeed = 12`).
       - `HumanoidRootPart` (Size 2,2,1, Anchored false, CanCollide true, set as `PrimaryPart`).
       - `Head` (Size 1.2,1.2,1.2, Color `Color3.fromRGB(220, 50, 50)`, Name `"Head"`, set attribute `IsHead = true`).
       - `Torso` (Size 2,2,1, Color `Color3.fromRGB(60, 65, 75)`).
       - Joints (Motor6D or WeldConstraint) connecting RootPart, Torso, and Head.
       - `BillboardGui` attached to Head displaying `"PATROL BOT #<id>"` and a health bar.
       - Set attributes: `IsPatrolBot = true`, `BotId = id`.
     - Waypoint Assignment:
       - Spawn position set to waypoint index `(id % #waypoints) + 1`.
   - `BotService.StartBotPatrol(botData: BotData)`:
     - Spawns a coroutine loop for continuous movement:
       ```luau
       botData.moveThread = task.spawn(function()
           while botData.isAlive and botData.model.Parent do
               local waypoints = PracticeRangeMapLayout.GetBotWaypoints()
               botData.currentWaypointIndex = (botData.currentWaypointIndex % #waypoints) + 1
               local targetPos = waypoints[botData.currentWaypointIndex]
               
               botData.humanoid:MoveTo(targetPos)
               
               -- Race condition wait between MoveToFinished and 8s timeout
               local reached = false
               local conn
               conn = botData.humanoid.MoveToFinished:Connect(function()
                   reached = true
               end)
               
               local startTime = os.clock()
               while not reached and (os.clock() - startTime < 8.0) and botData.isAlive do
                   task.wait(0.1)
               end
               if conn then conn:Disconnect() end
               
               if botData.isAlive then
                   task.wait(math.random(5, 15) / 10) -- 0.5s - 1.5s idle wait
               end
           end
       end)
       ```
   - `BotService.OnBotDied(botData: BotData, killerPlayer: Player?)`:
     - Sets `botData.isAlive = false`.
     - Clears `moveThread`.
     - Plays death sound / visual transparency effect (`0.8` transparency).
     - Calls `task.delay(3.0, function() ... end)` to execute respawn:
       - Teleports `HumanoidRootPart.CFrame` to `botData.originSpawnPos`.
       - Resets `Humanoid.Health = 100` and model transparency to `0`.
       - Sets `botData.isAlive = true`.
       - Calls `BotService.StartBotPatrol(botData)`.

3. **Practice Range Live Accuracy Stats Tracker**:
   - `playerStats: { [number]: PracticeRangeStats }` indexed by `Player.UserId`.
   - Math helpers:
     - `accuracyPercent = if stats.totalShotsFired == 0 then 0.0 else math.floor((stats.totalHits / stats.totalShotsFired) * 1000 + 0.5) / 10`
     - `headshotPercent = if stats.totalHits == 0 then 0.0 else math.floor((stats.totalHeadshots / stats.totalHits) * 1000 + 0.5) / 10`
   - `BotService.RecordShot(player: Player)`:
     - Increments `stats.totalShotsFired += 1`.
     - Triggers `BotService.ReplicateStats(player)`.
   - `BotService.RecordHit(player: Player, isHeadshot: boolean)`:
     - Increments `stats.totalHits += 1`.
     - If `isHeadshot` then `stats.totalHeadshots += 1`.
     - Triggers `BotService.ReplicateStats(player)`.
   - `BotService.ResetPlayerStats(player: Player)`:
     - Sets `totalShotsFired = 0`, `totalHits = 0`, `totalHeadshots = 0`.
     - Calls `BotService.ResetTargets()`.
     - Triggers `BotService.ReplicateStats(player)`.
   - `BotService.ReplicateStats(player: Player)`:
     - Calculates `accuracyPercent` and `headshotPercent`.
     - Fires `RangeStatsUpdated` RemoteEvent to `player` with payload:
       ```luau
       {
           totalShotsFired = stats.totalShotsFired,
           totalHits = stats.totalHits,
           totalHeadshots = stats.totalHeadshots,
           accuracyPercent = accuracyPercent,
           headshotPercent = headshotPercent,
       }
       ```

---

## 3. Unit Test Specifications: `src/server/Services/BotService.spec.luau`

Worker 4 must provide `src/server/Services/BotService.spec.luau` containing the following tests:

1. **Map & Target Wall Initialization Test**:
   - Call `PracticeRangeMapLayout.BuildMap(Workspace)`.
   - Call `BotService.Init()`.
   - Verify 6 stationary targets tracked in target manager state.
2. **Target Hit & Animation Test**:
   - Call `BotService.ProcessTargetHit(testPlayer, targetPart, true)`.
   - Assert target hit count equals 1.
   - Assert `RecordHit` updated `totalHits` to 1 and `totalHeadshots` to 1.
3. **Patrol Bot Spawn & Lifecycle Test**:
   - Call `BotService.SpawnPatrolBots(5)`.
   - Assert 5 bot models present under `PatrolBotSection`.
   - Verify each bot has a valid `Humanoid`, `Head`, `HumanoidRootPart`, and `BillboardGui`.
   - Assert `Humanoid.Health == 100` and `WalkSpeed == 12`.
4. **Bot Damage, Death & 3-Second Respawn Test**:
   - Fetch bot 1 humanoid, call `humanoid:TakeDamage(100)`.
   - Assert `humanoid.Health == 0` and bot `isAlive` status becomes false.
   - Fast-forward / wait 3.1 seconds (`task.wait(3.1)`).
   - Assert bot humanoid health is restored to 100 HP, `isAlive` becomes true, and position is reset to origin spawn position.
5. **Accuracy Stats Arithmetic & Formatting Test**:
   - Call `RecordShot` 10 times.
   - Call `RecordHit` 4 times (2 headshots).
   - Assert `accuracyPercent == 40.0`.
   - Assert `headshotPercent == 50.0`.
   - Call `ResetPlayerStats(testPlayer)`.
   - Assert `totalShotsFired == 0`, `totalHits == 0`, `accuracyPercent == 0.0`, `headshotPercent == 0.0`.
6. **Teardown**:
   - Call `BotService.Destroy()` and `PracticeRangeMapLayout.DestroyMap()`.

---

## 4. System Integration Plan for ServerMain & CombatServer

1. **`ServerMain.server.luau` Integration**:
   - Add requirement: `local BotService = require(ServicesFolder:WaitForChild("BotService") :: any)`
   - Call `BotService.Init(mapInstance)` right after map building when `PracticeRangeMap` is active.
2. **`CombatServer.luau` Integration**:
   - In `CombatServer.ProcessHitReport`:
     - When a shot lands on a target part or patrol bot:
     - Invoke `BotService.RecordShot(attackerPlayer)` and `BotService.RecordHit(attackerPlayer, isHeadshot)`.
3. **`RemoteEvents.luau` Addition**:
   - Add `"RangeStatsUpdated"` and `"ResetRangeStats"` to `reliableNames` in `RemoteEvents.luau`.
