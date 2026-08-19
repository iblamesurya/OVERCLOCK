# Milestone 1: Server Boot Reliability & Staged Sequence — Analysis Report

## Executive Summary
This report analyzes `src/server/ServerMain.server.luau` for Milestone 1 (Server Boot Reliability & Staged Sequence - R1). The analysis addresses two critical boot reliability vulnerabilities:
1. **Silent Infinite Yields on Module Require**: `safeRequire` currently uses `parent:WaitForChild(childName)` with no timeout, causing the server to hang indefinitely without error output if a required module is missing or delayed.
2. **Unstructured Boot Sequence**: Service initializations and module requires are scattered across the top-level script, lacking clear staging or visibility.

To fix these issues, we provide exact implementation designs for:
- An upgraded `safeRequire` function with a 5-second `WaitForChild(childName, 5)` timeout safeguard and robust error handling.
- A staged `safeInit` helper function (`pcall` + `task.spawn` execution).
- A 6-stage boot sequence with explicit `[BOOT] 1/6` through `[BOOT] 6/6 Server ready` logging.

---

## 1. Existing Codebase Audit (`src/server/ServerMain.server.luau`)

### Current `safeRequire` Implementation (Lines 9–17)
```luau
local function safeRequire(parent: Instance, childName: string): any
	local child = parent:WaitForChild(childName)
	local success, result = pcall(require, child)
	if not success then
		warn("[BOOT ERROR] Failed to require " .. childName .. ": " .. tostring(result))
		return nil
	end
	return result
end
```
**Defect Analysis**: Line 10 calls `parent:WaitForChild(childName)` without a timeout parameter. If `childName` does not exist (or hasn't replicated/built yet), Roblox execution halts on this line forever. The `pcall` on line 11 is never reached, resulting in a silent server boot hang.

### Current `safeInit` Implementation (Lines 143–152) & Initialization Flow
```luau
local function safeInit(name: string, fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn)
		if ok then
			print("[ServerMain] " .. name .. " initialized.")
		else
			warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
		end
	end)
end
```
**Defect Analysis**: Requires are executed top-level before `safeInit` is defined (Lines 19–45). `safeInit` is defined at line 143 and only used for service init calls (Lines 154–169). Stage headers like `[BOOT] 1/6` through `[BOOT] 6/6` are completely absent.

---

## 2. Implementation Designs

### 2.1 Implementation Design: Upgraded `safeRequire`
The upgraded `safeRequire` introduces a 5-second timeout on `WaitForChild`. If the child instance is not found within 5 seconds, it emits a loud `[BOOT ERROR]` warning and returns `nil`, preventing thread hang.

```luau
local function safeRequire(parent: Instance, childName: string): any
	local child = parent:WaitForChild(childName, 5)
	if not child then
		warn("[BOOT ERROR] Timeout (5s) waiting for module '" .. childName .. "' in " .. parent:GetFullName())
		return nil
	end
	local success, result = pcall(require, child)
	if not success then
		warn("[BOOT ERROR] Failed to require '" .. childName .. "': " .. tostring(result))
		return nil
	end
	return result
end
```

### 2.2 Implementation Design: Staged `safeInit` Helper
The `safeInit` function wraps service initialization functions inside `task.spawn` and `pcall`. If a service initialization fails, the error is logged loudly without interrupting other services or subsequent boot stages.

```luau
local function safeInit(name: string, fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn)
		if ok then
			print("[BOOT] " .. name .. " initialized.")
		else
			warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
		end
	end)
end
```

### 2.3 Staged 6-Step Boot Sequence Design

The boot sequence in `ServerMain.server.luau` will be structured into 6 clear stages:

| Stage | Header Log | Component Scope | Modules & Operations |
|-------|------------|-----------------|----------------------|
| **1/6** | `[BOOT] 1/6 Core Infrastructure & Network Remotes` | Network Remotes | `RemoteEvents`, `QueueEvents`, `ChallengeEvents` requires & `.Initialize()` calls |
| **2/6** | `[BOOT] 2/6 Data & Core Services` | Core Data & Social | `ProfileServiceWrapper`, `ReceiptProcessor.Init()`, `SocialInviteService.Init()` |
| **3/6** | `[BOOT] 3/6 Map System & Layout Safety` | Map & Layout | `MapRegistry`, `GreyboxArenaMap`, `LobbyFolder`, `DuelArenaMap`, `PracticeRangeMapLayout` build & `verifyLobbyFloor()` raycast validation |
| **4/6** | `[BOOT] 4/6 Combat & Operative Systems` | Combat & Bots | `CombatServer.new()`, `OperativeService.Init()`, `BotService.Init()` |
| **5/6** | `[BOOT] 5/6 Matchmaking & Round State Machine` | Matchmaking & Round | `MatchmakingCoordinator.StartService()`, `QueueMatchmakingService.Initialize()`, `DirectChallengeService.Init()`, `RoundService.Init()`, `EconomyService.Init()` |
| **6/6** | `[BOOT] 6/6 Setting Up Player Handlers & Single Spawn Authority` | Player Handlers & Ready | Remote event server listeners (`PlayerDeath`, `EnterPracticeRange`, `RequestQueue`, etc.), `Players.PlayerAdded` / `PlayerRemoving` connections, concluding with `[BOOT] 6/6 Server ready` |

---

## 3. Exact Line Numbers for Code Replacement

In `src/server/ServerMain.server.luau`:

1. **Replace `safeRequire`**:
   - **Target Lines**: Lines 9–17
   - **Action**: Replace old `safeRequire` with the 5s timeout `safeRequire` implementation.

2. **Replace `safeInit` and Reorganize Top-Level Requires & Inits into Staged Sequence**:
   - **Target Lines**: Lines 19–170
   - **Action**: Replace top-level requires, raw calls, and old `safeInit` definition with the 6-stage structured sequence (Stages 1 through 5, and start of Stage 6).

3. **Replace Boot Conclusion Log**:
   - **Target Lines**: Line 557
   - **Action**: Replace `print("[ServerMain] OVERCLOCK Server initialized successfully!")` with `print("[BOOT] 6/6 Server ready")`.

---

## 4. Full Proposed Code Replacement for `ServerMain.server.luau` Boot Section

```luau
--!strict
--[=[ Project OVERCLOCK: ServerMain - Main server entry point ]=]
warn("[BOOT] ServerMain version SPAWN_FIX_2026_08_04 is running")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Upgraded safeRequire with 5-second WaitForChild timeout safeguard
local function safeRequire(parent: Instance, childName: string): any
	local child = parent:WaitForChild(childName, 5)
	if not child then
		warn("[BOOT ERROR] Timeout (5s) waiting for module '" .. childName .. "' in " .. parent:GetFullName())
		return nil
	end
	local success, result = pcall(require, child)
	if not success then
		warn("[BOOT ERROR] Failed to require '" .. childName .. "': " .. tostring(result))
		return nil
	end
	return result
end

-- Staged safeInit helper wrapped in pcall and task.spawn
local function safeInit(name: string, fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn)
		if ok then
			print("[BOOT] " .. name .. " initialized.")
		else
			warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
		end
	end)
end

Players.CharacterAutoLoads = false

-- ==========================================================
-- STAGE 1: Core Infrastructure & Network Remotes
-- ==========================================================
print("[BOOT] 1/6 Core Infrastructure & Network Remotes")
local NetworkFolder = ReplicatedStorage:WaitForChild("Network", 5)
local RemoteEvents = NetworkFolder and safeRequire(NetworkFolder, "RemoteEvents")
local QueueEvents = NetworkFolder and safeRequire(NetworkFolder, "QueueEvents")
local ChallengeEvents = NetworkFolder and safeRequire(NetworkFolder, "ChallengeEvents")

if RemoteEvents then safeInit("RemoteEvents", function() RemoteEvents.Initialize() end) end
if QueueEvents then safeInit("QueueEvents", function() QueueEvents.Initialize() end) end
if ChallengeEvents then safeInit("ChallengeEvents", function() ChallengeEvents.Initialize() end) end

-- ==========================================================
-- STAGE 2: Data & Core Services
-- ==========================================================
print("[BOOT] 2/6 Data & Core Services")
local ServicesFolder = script.Parent:WaitForChild("Services", 5)
local ProfileServiceWrapper = ServicesFolder and safeRequire(ServicesFolder, "ProfileServiceWrapper")
local ReceiptProcessor = ServicesFolder and safeRequire(ServicesFolder, "ReceiptProcessor")
local SocialInviteService = ServicesFolder and safeRequire(ServicesFolder, "SocialInviteService")

if ReceiptProcessor then safeInit("ReceiptProcessor", function() ReceiptProcessor.Init() end) end
if SocialInviteService then safeInit("SocialInviteService", function() SocialInviteService.Init() end) end

-- ==========================================================
-- STAGE 3: Map System & Layout Safety
-- ==========================================================
print("[BOOT] 3/6 Map System & Layout Safety")
local MapFolder = ReplicatedStorage:WaitForChild("Map", 5)
local MapRegistry = MapFolder and safeRequire(MapFolder, "MapRegistry")
local GreyboxArenaMap = MapFolder and safeRequire(MapFolder, "GreyboxArenaMap")
local LobbyFolder = MapFolder and safeRequire(MapFolder, "LobbyFolder")
local DuelArenaMap = MapFolder and safeRequire(MapFolder, "DuelArenaMap")
local PracticeRangeMapLayout = MapFolder and safeRequire(MapFolder, "PracticeRangeMapLayout")

if MapRegistry then safeInit("MapRegistry", function() MapRegistry.AutoRegisterDefaultMaps() end) end
if GreyboxArenaMap then safeInit("GreyboxArenaMap", function() GreyboxArenaMap.BuildMap(Workspace) end) end
if LobbyFolder then safeInit("LobbyFolder", function() LobbyFolder.BuildLobby(Workspace) end) end

local function verifyLobbyFloor()
	if not LobbyFolder then return end
	local spawns = LobbyFolder.GetSpawnLocations()
	for _, spawn in spawns do
		local origin = spawn.Position + Vector3.new(0, 30, 0)
		local direction = Vector3.new(0, -100, 0)
		local hit = Workspace:Raycast(origin, direction)
		if hit then
			warn(("[FLOOR] %s hits %s at %s"):format(spawn.Name, hit.Instance:GetFullName(), tostring(hit.Position)))
		else
			warn(("[FLOOR] NO COLLIDABLE FLOOR BELOW %s"):format(spawn.Name))
		end
	end
end
verifyLobbyFloor()

if DuelArenaMap then
	safeInit("DuelArenaMap", function()
		if DuelArenaMap.BuildMap then DuelArenaMap.BuildMap(Workspace) end
	end)
end
if PracticeRangeMapLayout then
	safeInit("PracticeRangeMapLayout", function()
		if PracticeRangeMapLayout.BuildMap then PracticeRangeMapLayout.BuildMap(Workspace) end
	end)
end

-- Disable non-lobby spawns
for _, desc in Workspace:GetDescendants() do
	if desc:IsA("SpawnLocation") and not desc:GetAttribute("LobbySpawnIndex") then
		desc.Enabled = false
	end
end

-- Safety Baseplate & Catch Floor
local baseplate = Instance.new("Part")
baseplate.Name = "FallbackBaseplate"
baseplate.Size = Vector3.new(3000, 4, 3000)
baseplate.Position = Vector3.new(0, 95, 0)
baseplate.Anchored = true
baseplate.Material = Enum.Material.SmoothPlastic
baseplate.Color = Color3.fromRGB(35, 40, 50)
baseplate.CanCollide = true
baseplate.Parent = Workspace

local diagnosticFloor = Instance.new("Part")
diagnosticFloor.Name = "DIAGNOSTIC_LOBBY_CATCH_FLOOR"
diagnosticFloor.Anchored = true
diagnosticFloor.CanCollide = true
diagnosticFloor.CanTouch = false
diagnosticFloor.CanQuery = false
diagnosticFloor.Transparency = 0.35
diagnosticFloor.Color = Color3.fromRGB(255, 0, 0)
diagnosticFloor.Material = Enum.Material.Neon
diagnosticFloor.Size = Vector3.new(4000, 10, 4000)
diagnosticFloor.CFrame = CFrame.new(0, 80, 0)
diagnosticFloor.Parent = Workspace

-- ==========================================================
-- STAGE 4: Combat & Operative Systems
-- ==========================================================
print("[BOOT] 4/6 Combat & Operative Systems")
local CombatFolder = script.Parent:WaitForChild("Combat", 5)
local CombatServer = CombatFolder and safeRequire(CombatFolder, "CombatServer")
local OperativeService = ServicesFolder and safeRequire(ServicesFolder, "OperativeService")
local BotService = ServicesFolder and safeRequire(ServicesFolder, "BotService")

local combatServerInstance: any = nil
if CombatServer then
	safeInit("CombatServer", function()
		combatServerInstance = CombatServer.new()
		combatServerInstance:InitializeNetworkListeners()
	end)
end

if OperativeService then safeInit("OperativeService", function() OperativeService.Init() end) end
if BotService then safeInit("BotService", function() BotService.Init() end) end

-- ==========================================================
-- STAGE 5: Matchmaking & Round State Machine
-- ==========================================================
print("[BOOT] 5/6 Matchmaking & Round State Machine")
local MatchmakingCoordinator = ServicesFolder and safeRequire(ServicesFolder, "MatchmakingCoordinator")
local QueueMatchmakingService = ServicesFolder and safeRequire(ServicesFolder, "QueueMatchmakingService")
local DirectChallengeService = ServicesFolder and safeRequire(ServicesFolder, "DirectChallengeService")
local RoundService = ServicesFolder and safeRequire(ServicesFolder, "RoundService")
local EconomyService = ServicesFolder and safeRequire(ServicesFolder, "EconomyService")

if MatchmakingCoordinator then safeInit("MatchmakingCoordinator", function() MatchmakingCoordinator.StartService() end) end
if QueueMatchmakingService then safeInit("QueueMatchmakingService", function() QueueMatchmakingService.Initialize() end) end
if DirectChallengeService then safeInit("DirectChallengeService", function() DirectChallengeService.Init() end) end

if RoundService then
	safeInit("RoundService", function()
		RoundService.Init(combatServerInstance)
		if RoundService.SetCombatServer then RoundService.SetCombatServer(combatServerInstance) end
	end)
end

if EconomyService then
	safeInit("EconomyService", function()
		EconomyService.Init(RoundService, combatServerInstance)
	end)
end

-- ==========================================================
-- STAGE 6: Setting Up Player Handlers & Single Spawn Authority
-- ==========================================================
print("[BOOT] 6/6 Setting Up Player Handlers & Single Spawn Authority")
```
