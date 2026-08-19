# Architectural Analysis & Design Specification: Single Spawn Authority (`SpawnService`)

**Milestone:** M2 — Single Spawn Authority (SpawnService - R2)  
**Author:** Explorer Subagent (`explorer_m2_1`)  
**Target Path:** `src/server/Services/SpawnService.luau`  
**Date:** 2026-08-04  

---

## 1. Architectural Motivation & System Overview

In the original codebase, character spawning, positioning (`PivotTo`, `RootPart.CFrame`), and respawn location management were fragmented across six separate server scripts:
1. `src/server/ServerMain.server.luau` (Lobby spawn, practice range spawn, void rescue, player lifecycle)
2. `src/server/Services/RoundService.luau` (PvP round start reset & spawn positioning)
3. `src/server/Services/DirectChallengeService.luau` (1v1 duel arena teleportation)
4. `src/server/Services/QueueMatchmakingService.luau` (1v1 / 2v2 match spawn teleportation)
5. `src/server/Services/SocialInviteService.luau` (Teleporting player to inviter friend)
6. `src/server/Services/OperativeService.luau` (Fray's Blink dash repositioning)

This decentralization produced several race conditions:
- Simultaneous calls to `Player:LoadCharacter()` and `Character:PivotTo()` from `ServerMain` and match initialization services caused players to spawn in the void (`Y < -200`) or at the origin `(0, 0, 0)`.
- Ad-hoc state tracking created inconsistent location states when returning from matches or Practice Range.
- Lack of single-flight concurrency locking allowed duplicate character loading calls when network events arrived in quick succession.

To enforce Requirement **R2 (Single Spawn Authority)**:
- `SpawnService.luau` is introduced as the **sole, exclusive owner** of `Player:LoadCharacter()`, `player.RespawnLocation`, `character:PivotTo()`, location state tracking (`"Lobby" | "PracticeRange" | "Match"`), concurrency locking, and falling player void rescue.
- All six target scripts are refactored to delegate spawning and character relocation exclusively to `SpawnService`.

---

## 2. `SpawnService.luau` Comprehensive Design Specification

### 2.1 Interface & Type Definitions
```luau
--!strict
export type LocationType = "Lobby" | "PracticeRange" | "Match"

export type SpawnServiceModule = {
	Init: () -> (),
	SpawnPlayer: (player: Player, destinationType: LocationType, customCFrame: CFrame?) -> Model?,
	TeleportCharacter: (player: Player, cframe: CFrame) -> boolean,
	SetPlayerLocation: (player: Player, location: LocationType) -> (),
	GetPlayerLocation: (player: Player) -> LocationType,
	HandleCharacterRespawn: (player: Player) -> (),
	AttachVoidRescue: (player: Player, character: Model) -> (),
	OnPlayerAdded: (player: Player) -> (),
	OnPlayerRemoving: (player: Player) -> (),
}
```

### 2.2 Complete Implementation Source Code (`src/server/Services/SpawnService.luau`)

```luau
--!strict
--[=[
    Project OVERCLOCK: SpawnService
    Single Spawn Authority (R2).
    Sole authoritative owner of Player:LoadCharacter(), player.RespawnLocation,
    character:PivotTo(), location state tracking ("Lobby" | "PracticeRange" | "Match"),
    concurrency locking, character death handling, and falling player void rescue.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type LocationType = "Lobby" | "PracticeRange" | "Match"

local SpawnService = {}

-- Key Constants
local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 106, 0)
local PRACTICE_RANGE_CFRAME = CFrame.new(500, 105, 60)
local VOID_RESCUE_Y = -200
local LOCK_TIMEOUT_SECONDS = 3

-- Internal State Tracking
local playerLocations: { [number]: LocationType } = {}
local customSpawns: { [number]: CFrame } = {}
local spawnLocks: { [number]: boolean } = {}
local rescueCooldowns: { [number]: boolean } = {}

-- Lazy-required service references
local _lobbyFolderRef: any = nil
local _practiceRangeLayoutRef: any = nil
local _roundServiceRef: any = nil
local _directChallengeServiceRef: any = nil

local function getLobbyFolder(): any
	if not _lobbyFolderRef then
		local mapFolder = ReplicatedStorage:FindFirstChild("Map")
		if mapFolder then
			local lobbyMod = mapFolder:FindFirstChild("LobbyFolder")
			if lobbyMod then
				_lobbyFolderRef = require(lobbyMod :: any)
			end
		end
	end
	return _lobbyFolderRef
end

local function getPracticeRangeLayout(): any
	if not _practiceRangeLayoutRef then
		local mapFolder = ReplicatedStorage:FindFirstChild("Map")
		if mapFolder then
			local prMod = mapFolder:FindFirstChild("PracticeRangeMapLayout")
			if prMod then
				_practiceRangeLayoutRef = require(prMod :: any)
			end
		end
	end
	return _practiceRangeLayoutRef
end

local function getRoundService(): any
	if not _roundServiceRef then
		local services = ServerScriptService:FindFirstChild("Services")
		if services then
			local rsMod = services:FindFirstChild("RoundService")
			if rsMod then
				_roundServiceRef = require(rsMod :: any)
			end
		end
	end
	return _roundServiceRef
end

local function getDirectChallengeService(): any
	if not _directChallengeServiceRef then
		local services = ServerScriptService:FindFirstChild("Services")
		if services then
			local dcsMod = services:FindFirstChild("DirectChallengeService")
			if dcsMod then
				_directChallengeServiceRef = require(dcsMod :: any)
			end
		end
	end
	return _directChallengeServiceRef
end

--- Get Lobby SpawnLocation object for player
local function getLobbySpawnLocation(player: Player): SpawnLocation?
	local lobbyFolder = getLobbyFolder()
	if lobbyFolder and lobbyFolder.GetSpawnLocations then
		local spawnsList = lobbyFolder.GetSpawnLocations()
		if #spawnsList > 0 then
			return spawnsList[((math.abs(player.UserId) - 1) % #spawnsList) + 1]
		end
	end
	return nil
end

--- Get Lobby target CFrame
local function getLobbyCFrame(player: Player): CFrame
	local spawn = getLobbySpawnLocation(player)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 5, 0)
	end
	return LOBBY_FALLBACK_CFRAME
end

--- Get Practice Range target CFrame
local function getPracticeRangeCFrame(player: Player): CFrame
	local prLayout = getPracticeRangeLayout()
	if prLayout and prLayout.GetSpawnPoints then
		local spawns = prLayout.GetSpawnPoints()
		if spawns and #spawns > 0 then
			return spawns[1] + Vector3.new(0, 3, 0)
		end
	end
	return PRACTICE_RANGE_CFRAME
end

--- Determines appropriate CFrame for destination type
local function getDestinationCFrame(player: Player, destinationType: LocationType, customCFrame: CFrame?): CFrame
	if customCFrame then
		return customCFrame
	end
	if destinationType == "Match" then
		return customSpawns[player.UserId] or getLobbyCFrame(player)
	elseif destinationType == "PracticeRange" then
		return getPracticeRangeCFrame(player)
	else
		return getLobbyCFrame(player)
	end
end

--- Updates player's location state
function SpawnService.SetPlayerLocation(player: Player, location: LocationType)
	playerLocations[player.UserId] = location
end

--- Gets player's current location state
function SpawnService.GetPlayerLocation(player: Player): LocationType
	return playerLocations[player.UserId] or "Lobby"
end

--- Teleports existing character model to target CFrame safely
function SpawnService.TeleportCharacter(player: Player, cframe: CFrame): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	character:PivotTo(cframe)
	return true
end

--- Attaches void rescue safety net to player character
function SpawnService.AttachVoidRescue(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then return end

	task.spawn(function()
		while character.Parent and player.Parent == Players do
			if root.Position.Y < VOID_RESCUE_Y and not rescueCooldowns[player.UserId] then
				rescueCooldowns[player.UserId] = true
				local loc = SpawnService.GetPlayerLocation(player)
				local destCFrame = getDestinationCFrame(player, loc, customSpawns[player.UserId])

				warn(("[VOID] Rescuing %s from Y=%.1f to %s at %s"):format(
					player.Name,
					root.Position.Y,
					loc,
					tostring(destCFrame.Position)
				))

				character:PivotTo(destCFrame)
				task.wait(2)
				rescueCooldowns[player.UserId] = nil
			end
			task.wait(0.25)
		end
	end)
end

--- Authoritative character spawn entry point
function SpawnService.SpawnPlayer(player: Player, destinationType: LocationType, customCFrame: CFrame?): Model?
	local userId = player.UserId

	-- Concurrency mutex check
	if spawnLocks[userId] then
		warn("[SPAWN] Blocked concurrent spawn request for", player.Name, destinationType)
		return player.Character
	end
	spawnLocks[userId] = true

	-- Update state tracking
	playerLocations[userId] = destinationType
	if customCFrame then
		customSpawns[userId] = customCFrame
	end

	-- Configure Roblox RespawnLocation
	if destinationType == "Lobby" then
		local spawnObj = getLobbySpawnLocation(player)
		if spawnObj then
			player.RespawnLocation = spawnObj
		end
	else
		player.RespawnLocation = nil
	end

	-- Load character authoritatively
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	local destCFrame = getDestinationCFrame(player, destinationType, customCFrame)

	if root then
		character:PivotTo(destCFrame)
		-- Deferred second pivot to guard against physics initialization frame offsets
		task.defer(function()
			if character.Parent and root.Parent then
				character:PivotTo(destCFrame)
			end
		end)

		print(("[SPAWN] Player %s -> %s at %.1f, %.1f, %.1f"):format(
			player.Name,
			destinationType,
			destCFrame.Position.X,
			destCFrame.Position.Y,
			destCFrame.Position.Z
		))
	end

	SpawnService.AttachVoidRescue(player, character)

	-- Unlock after delay
	task.delay(LOCK_TIMEOUT_SECONDS, function()
		spawnLocks[userId] = nil
	end)

	return character
end

--- Handles character death and respawning rules
function SpawnService.HandleCharacterRespawn(player: Player)
	local dcs = getDirectChallengeService()
	local rs = getRoundService()

	local status = if dcs then dcs.GetPlayerStatus(player) else "In Lobby"
	local inActiveMatch = rs and rs.IsPlayerInActiveMatch and rs.IsPlayerInActiveMatch(player)

	if status == "In Match" or inActiveMatch then
		-- In PvP match: mid-round respawn handled by RoundService (spectate)
		pcall(function()
			if rs and rs.OnPlayerDied then
				rs.OnPlayerDied(player, nil)
			end
		end)
	else
		-- Non-match (Lobby / PracticeRange): auto-respawn after delay
		task.wait(2)
		if player.Parent == Players then
			local currentLocation = SpawnService.GetPlayerLocation(player)
			SpawnService.SpawnPlayer(player, currentLocation)
		end
	end
end

--- Called on PlayerAdded
function SpawnService.OnPlayerAdded(player: Player)
	playerLocations[player.UserId] = "Lobby"

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				SpawnService.HandleCharacterRespawn(player)
			end)
		end
	end)

	SpawnService.SpawnPlayer(player, "Lobby")
end

--- Called on PlayerRemoving
function SpawnService.OnPlayerRemoving(player: Player)
	playerLocations[player.UserId] = nil
	customSpawns[player.UserId] = nil
	spawnLocks[player.UserId] = nil
	rescueCooldowns[player.UserId] = nil
end

--- Initialize SpawnService
function SpawnService.Init()
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		SpawnService.OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SpawnService.OnPlayerRemoving(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			SpawnService.OnPlayerAdded(player)
		end)
	end

	print("[SpawnService] Initialized as Single Spawn Authority.")
end

return SpawnService
```

---

## 3. Codebase Audit of Existing Spawn / Positioning Calls

| File Path | Lines | Original Implementation | Risk / Vulnerability | Required Refactoring |
|---|---|---|---|---|
| `src/server/ServerMain.server.luau` | 183, 247, 250, 273, 275, 299, 553, 587 | Ad-hoc `player:LoadCharacter()`, `player.RespawnLocation`, `character:PivotTo()` in local functions | Duplicate spawns, hardcoded position bypass | Delegate player lifecycle & spawns to `SpawnService.Init()` and `SpawnService.SpawnPlayer()` |
| `src/server/Services/RoundService.luau` | 164, 177 | `player:LoadCharacter()`, `root.CFrame = CFrame.new(spawnPos)` | Bypasses spawn locks & location tracking | Replace with `SpawnService.SpawnPlayer` or `SpawnService.TeleportCharacter` |
| `src/server/Services/DirectChallengeService.luau` | 146-157 | `hrp.CFrame = redCFrame`, `challengerChar:PivotTo(...)` | Unregistered position teleportation | Replace with `SpawnService.TeleportCharacter` & `SetPlayerLocation("Match")` |
| `src/server/Services/QueueMatchmakingService.luau` | 433 | `character:PivotTo(CFrame.new(matchPlayer.spawnPosition))` | Unregistered position teleportation | Replace with `SpawnService.TeleportCharacter` & `SetPlayerLocation("Match")` |
| `src/server/Services/SocialInviteService.luau` | 148-150 | `joiningRoot.CFrame = ...`, `joiningChar:PivotTo(...)` | Direct character relocation | Replace with `SpawnService.TeleportCharacter` |
| `src/server/Services/OperativeService.luau` | 570 | `rootPart.CFrame = CFrame.new(finalPos, finalPos + lookDir)` | Mobility dash bypasses authority | Replace with `SpawnService.TeleportCharacter` |

---

## 4. Step-by-Step Refactoring Guidelines for Callers

### 4.1 Refactoring `src/server/ServerMain.server.luau`

#### Goal:
Remove all ad-hoc character spawn management routines, state tables, and direct `LoadCharacter()` / `PivotTo()` calls.

#### Step 1: Require `SpawnService` in Stage 2
Replace line 56 with:
```luau
local ServicesFolder = script.Parent:WaitForChild("Services", 5)
local ProfileServiceWrapper = ServicesFolder and safeRequire(ServicesFolder, "ProfileServiceWrapper")
local ReceiptProcessor = ServicesFolder and safeRequire(ServicesFolder, "ReceiptProcessor")
local SocialInviteService = ServicesFolder and safeRequire(ServicesFolder, "SocialInviteService")
local SpawnService = ServicesFolder and safeRequire(ServicesFolder, "SpawnService")
```

#### Step 2: Initialize `SpawnService` in Stage 6 & Remove Local Helpers
Replace lines 220-412 (local `playerDestination`, `spawnInProgress`, `getLobbyCFrame`, `getDestinationCFrame`, `traceSpawn`, `moveCharacterToDestination`, `loadAtDestination`, `attachVoidRescue`, `onCharacterAdded`, `onPlayerAdded`, `onPlayerRemoving`) with:
```luau
if SpawnService then
	safeInit("SpawnService", function()
		SpawnService.Init()
	end)
end
```

#### Step 3: Update Transition Functions
Replace lines 414-430 (`returnPlayerToLobby` and `spawnPlayerInPracticeRange`) with:
```luau
local function returnPlayerToLobby(player: Player)
	practiceRangePlayers[player.UserId] = nil
	DirectChallengeService.SetPlayerStatus(player, "In Lobby")
	combatServerInstance:RegisterPlayer(player.UserId)
	if SpawnService then
		SpawnService.SpawnPlayer(player, "Lobby")
	end
	pcall(function()
		RemoteEvents.GetReliable("MatchPhaseTransition"):FireClient(player, {phase = "Lobby"})
	end)
end

local function spawnPlayerInPracticeRange(player: Player)
	practiceRangePlayers[player.UserId] = true
	DirectChallengeService.SetPlayerStatus(player, "Practice Range")
	if SpawnService then
		SpawnService.SpawnPlayer(player, "PracticeRange")
	end
end
```

#### Step 4: Remove Duplicate Boot Load Loop
At bottom of `ServerMain.server.luau` (lines 582-589), delete the manual character loading loop:
```luau
-- DELETE THIS BLOCK:
-- Players.CharacterAutoLoads = false
-- for _, p in Players:GetPlayers() do
-- 	if not p.Character then
-- 		setPlayerRespawnToLobby(p)
-- 		p:LoadCharacter()
-- 	end
-- end
```

---

### 4.2 Refactoring `src/server/Services/RoundService.luau`

#### Goal:
Delegate character reloading and teleportation during PvP match initialization and round resets to `SpawnService`.

#### Step 1: Require `SpawnService`
Add at top (around line 18):
```luau
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)
```

#### Step 2: Replace `resetPlayerCharacter`
Replace lines 151-193 with:
```luau
local function resetPlayerCharacter(playerData: RoundPlayerData, index: number)
	local player = playerData.player
	if not player or not player.Parent then
		return
	end

	playerData.isAlive = true
	local spawnPos = computeSpawnPosition(playerData.teamId, index)
	local targetCFrame = CFrame.new(spawnPos)

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
		char = SpawnService.SpawnPlayer(player, "Match", targetCFrame)
	else
		SpawnService.TeleportCharacter(player, targetCFrame)
		SpawnService.SetPlayerLocation(player, "Match")
	end

	if char then
		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		if hum then
			hum.Health = hum.MaxHealth
		end

		char:SetAttribute("Stunned", nil)
		char:SetAttribute("SpeedMultiplier", nil)
	end

	if _combatServerRef then
		local armorVal = 0
		if char then
			armorVal = (char:GetAttribute("Armor") :: number) or 0
		end
		_combatServerRef:RegisterPlayer(player.UserId, 100, armorVal)
	end
end
```

---

### 4.3 Refactoring `src/server/Services/DirectChallengeService.luau`

#### Goal:
Delegate 1v1 duel arena character teleportation and location state assignment to `SpawnService`.

#### Step 1: Require `SpawnService`
Add at top (around line 17):
```luau
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)
```

#### Step 2: Replace `spawnDuelArenaAndTeleport` Character Teleport Logic
Replace lines 142-159 in `spawnDuelArenaAndTeleport` with:
```luau
	local challengerChar = waitForCharacterWithTimeout(challenger, 10)
	if challengerChar then
		SpawnService.TeleportCharacter(challenger, redCFrame)
		SpawnService.SetPlayerLocation(challenger, "Match")
	end

	local targetChar = waitForCharacterWithTimeout(targetPlayer, 10)
	if targetChar then
		SpawnService.TeleportCharacter(targetPlayer, blueCFrame)
		SpawnService.SetPlayerLocation(targetPlayer, "Match")
	end
```

---

### 4.4 Refactoring `src/server/Services/QueueMatchmakingService.luau`

#### Goal:
Delegate match start teleportation and state tracking to `SpawnService`.

#### Step 1: Require `SpawnService`
Add at top (around line 13):
```luau
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)
```

#### Step 2: Replace `StartMatchSession` Character Positioning Loop
Replace lines 427-436 in `StartMatchSession` with:
```luau
	for _, matchPlayer in pairs(session.allPlayers) do
		local player = matchPlayer.player
		if player and player.Character and player:IsDescendantOf(Players) then
			local spawnCFrame = CFrame.new(matchPlayer.spawnPosition)
			SpawnService.TeleportCharacter(player, spawnCFrame)
			SpawnService.SetPlayerLocation(player, "Match")
		end
	end
```

---

### 4.5 Refactoring `src/server/Services/SocialInviteService.luau`

#### Goal:
Delegate friend teleportation to `SpawnService.TeleportCharacter`.

#### Step 1: Add `getSpawnService` Helper
Add at top (around line 16):
```luau
local function getSpawnService(): any
	local servicesFolder = game:GetService("ServerScriptService"):FindFirstChild("Services")
	if servicesFolder then
		local ssMod = servicesFolder:FindFirstChild("SpawnService")
		if ssMod then
			return require(ssMod :: any)
		end
	end
	return nil
end
```

#### Step 2: Replace `teleportToInviter` Implementation
Replace lines 138-158 with:
```luau
local function teleportToInviter(joiningPlayer: Player, inviterPlayer: Player)
	local function doTeleport()
		local joiningChar = waitForCharacterWithTimeout(joiningPlayer, 10)
		local inviterChar = waitForCharacterWithTimeout(inviterPlayer, 10)

		if joiningChar and inviterChar then
			local inviterRoot = inviterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if inviterRoot then
				local targetCFrame = inviterRoot.CFrame * CFrame.new(3, 0, 3)
				local ss = getSpawnService()
				if ss then
					ss.TeleportCharacter(joiningPlayer, targetCFrame)
				else
					joiningChar:PivotTo(targetCFrame)
				end
			end
		end
	end

	task.spawn(function()
		pcall(doTeleport)
	end)
end
```

---

### 4.6 Refactoring `src/server/Services/OperativeService.luau`

#### Goal:
Route Fray's Blink mobility dash through `SpawnService.TeleportCharacter`.

#### Step 1: Add `getSpawnService` Helper
Add inside `OperativeService.luau` (around line 70):
```luau
local _spawnServiceRef: any = nil
local function getSpawnService(): any
	if not _spawnServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local ssMod = servicesFolder:FindFirstChild("SpawnService")
			if ssMod then
				_spawnServiceRef = require(ssMod :: any)
			end
		end
	end
	return _spawnServiceRef
end
```

#### Step 2: Refactor `Fray_Blink` Execution
Replace lines 564-573 with:
```luau
	elseif abilityId == "Fray_Blink" then
		-- Blink Dash: Blinks 25 studs forward (raycast obstacle check)
		local blinkDist = abilityData.range or 25
		local lookDir = originCFrame.LookVector
		local rayParams = RaycastParams.new()
		rayParams.FilterAncestorsCasesPrune = { char }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = Workspace:Raycast(originCFrame.Position, lookDir * blinkDist, rayParams)
		local finalPos = if result then result.Position - (lookDir * 2) else originCFrame.Position + (lookDir * blinkDist)
		local targetCFrame = CFrame.new(finalPos, finalPos + lookDir)

		local ss = getSpawnService()
		if ss then
			ss.TeleportCharacter(player, targetCFrame)
		elseif rootPart then
			rootPart.CFrame = targetCFrame
		end
```

---

## 5. Verification Matrix & Edge Case Handling

### 5.1 Concurrency Lock Matrix
| Trigger | Lock State | Action |
|---|---|---|
| `PlayerAdded` | `false` | Set lock -> LoadCharacter() -> PivotTo() -> Unlock after 3s |
| Immediate Duplicate Request | `true` | Log warning `[SPAWN] Blocked concurrent spawn request` -> Return existing char |
| Rapid Mode Switching | `true` -> `false` | Second request waits for lock release or gets ignored safely |

### 5.2 Falling Player Void Rescue Flow
```
Heartbeat (0.25s) -> Check RootPart.Position.Y < -200
  │
  ├── Is Rescue Cooldown Active? ── (Yes) ──> Skip
  │
  └── (No) ──> Set Rescue Cooldown = true
               Fetch Current Location State ("Lobby" | "PracticeRange" | "Match")
               PivotTo(Destination CFrame)
               Log: [VOID] Rescuing player from Y=...
               Wait 2.0s -> Clear Cooldown
```
