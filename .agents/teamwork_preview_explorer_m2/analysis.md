# Milestone 2 (M2_Round_Economy) Technical Specification & Implementation Guide

## Executive Summary
This document provides the concrete file implementation specification for Worker 2 to build `src/server/Services/RoundService.luau` and `src/server/Services/EconomyService.luau`, alongside necessary integration hooks in `src/server/ServerMain.server.luau`, `src/shared/Network/RemoteEvents.luau`, and `src/server/Combat/CombatServer.luau`.

---

## 1. System Architecture & Component Interaction

```
                        +----------------------------+
                        | QueueMatchmakingService /  |
                        |  DirectChallengeService    |
                        +-------------+--------------+
                                      | Starts Match
                                      v
                        +-------------+--------------+
                        |        RoundService        |
                        |   (Round State Machine)    |
                        +------+--------------+------+
                               |              |
              Updates Phase &  |              | Manages Round Reset &
            Round Transitions  |              | Character Spawns
                               v              v
+------------------+    +------+--------------+------+    +-------------------+
|  RemoteEvents    |<---|    EconomyService          |--->|   CombatServer    |
| (RoundState,     |    | (Credit & Buy Authority)   |    | (Health/Armor &   |
| PurchaseResult)  |    +----------------------------+    | Hit Processing)   |
+------------------+                                      +-------------------+
```

---

## 2. Specification: `src/server/Services/RoundService.luau`

### Purpose
Manages round-based match state machine (1v1 & 2v2 modes), phase timers, team scores, sudden-death round handling (6-6 tie), spectate on death, character position/health resets, and match lifecycle integration.

### File Location
`src/server/Services/RoundService.luau`

### Data Types & Interface Contracts
```luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

export type RoundPhase = "Buy" | "Live" | "RoundEnd" | "Intermission" | "Ended"
export type QueueMode = "1v1" | "2v2"
export type TeamId = 1 | 2

export type RoundPlayerData = {
	player: Player,
	userId: number,
	teamId: TeamId,
	isAlive: boolean,
}

export type MatchState = {
	matchId: string,
	mode: QueueMode,
	currentRound: number,
	team1Score: number,
	team2Score: number,
	team1LossStreak: number,
	team2LossStreak: number,
	phase: RoundPhase,
	timeRemaining: number,
	isSuddenDeath: boolean,
	team1Players: { [number]: RoundPlayerData },
	team2Players: { [number]: RoundPlayerData },
	allPlayers: { [number]: RoundPlayerData },
	activeThread: thread?,
}
```

### Key Constants
- `BUY_PHASE_DURATION = 15` (seconds)
- `LIVE_PHASE_DURATION = 60` (seconds)
- `ROUND_END_DURATION = 5` (seconds)
- `INTERMISSION_DURATION = 3` (seconds)
- `TARGET_SCORE = 7` (First to 7 rounds wins)
- `SUDDEN_DEATH_TIE_SCORE = 6` (6-6 tie triggers sudden death round 13)

### Required Functions & Implementation Details

#### `RoundService.StartMatch(matchId: string, mode: QueueMode, team1: { Player }, team2: { Player })`
1. Creates a `MatchState` object initialized with `currentRound = 1`, `team1Score = 0`, `team2Score = 0`, `team1LossStreak = 0`, `team2LossStreak = 0`, `isSuddenDeath = false`.
2. Registers all players with `EconomyService.InitializePlayer(player, 800)` for Round 1 Pistol Round starting credits.
3. Sets player statuses via `DirectChallengeService.SetPlayerStatus(player, "In Match")` and sets `CombatServer` match phase to `"InGame"`.
4. Spawns `task.spawn` main round loop for the match and begins `Round 1` by calling `RoundService.StartRound(matchId)`.

#### `RoundService.StartRound(matchId: string)`
1. Checks if current round is a Sudden Death round (`team1Score == 6` and `team2Score == 6`):
   - If true: Set `isSuddenDeath = true`, call `EconomyService.SetSuddenDeathCredits(player)` (5000 credits for each player).
2. Performs **Round Reset**:
   - Iterates through all match players: resurrects character models if dead, restores `Humanoid.Health = 100`, sets `CombatServer` player health/shield state (100 HP, 0/25/50 Shield depending on purchased armor).
   - Teleports Team 1 players to Team 1 map spawn points (`computeSpawnPosition(1, index)`).
   - Teleports Team 2 players to Team 2 map spawn points (`computeSpawnPosition(2, index)`).
   - Clears temporary status effects (movement speed buffs/debuffs, stun states).
   - Sets `isAlive = true` for all players in `MatchState`.
3. Transitions phase to `"Buy"`:
   - Phase duration = 15s.
   - Broadcasts `RoundStateChanged` remote event to all clients in match.

#### `RoundService.TransitionToPhase(matchId: string, newPhase: RoundPhase)`
1. Updates `match.phase = newPhase`.
2. Sets timer duration based on phase:
   - `"Buy"` -> 15s
   - `"Live"` -> 60s
   - `"RoundEnd"` -> 5s
   - `"Intermission"` -> 3s
3. Fires `RoundStateChanged` remote event to clients with payload:
   ```luau
   {
       matchId = matchId,
       phase = newPhase,
       timeRemaining = duration,
       currentRound = match.currentRound,
       team1Score = match.team1Score,
       team2Score = match.team2Score,
       isSuddenDeath = match.isSuddenDeath,
   }
   ```
4. Phase specific actions:
   - **Buy Phase**: Weapon firing and damage processing are disabled or restricted to buy bounds. `EconomyService` accepts purchases.
   - **Live Phase**: Purchases rejected by `EconomyService`. Firing and combat damage enabled in `CombatServer`.
   - **RoundEnd Phase**: Determines round winner (if not already determined by elimination). Calls `EconomyService.ProcessRoundEnd(winningTeam, losingTeam)`.
   - **Intermission Phase**: Prepares next round or ends match if `team1Score == 7` or `team2Score == 7`.

#### `RoundService.OnPlayerDied(victimPlayer: Player, killerPlayer: Player?)`
1. Marks `RoundPlayerData.isAlive = false` for `victimPlayer`.
2. Suppresses mid-round auto-respawning (character remains dead on ground, client UI transitions to spectate view).
3. If `killerPlayer` is valid and on opposing team:
   - Invokes `EconomyService.AwardKillReward(killerPlayer)` (+200 Credits).
4. Checks team elimination:
   - Count alive players in Team 1 and Team 2.
   - If Team 1 alive count == 0: Team 2 wins the round immediately!
   - If Team 2 alive count == 0: Team 1 wins the round immediately!
   - If a team is eliminated during `"Live"` phase, immediately interrupt phase timer and transition to `"RoundEnd"`.

#### `RoundService.EvaluateRoundEnd(matchId: string, winningTeam: TeamId?)`
1. Determine winner:
   - If explicit `winningTeam` passed (due to elimination), use `winningTeam`.
   - If live phase timer expired: team with higher total combined health remaining wins. If equal, Team 1 wins by default.
2. Update score & loss streaks:
   - If Team 1 wins: `team1Score += 1`, `team1LossStreak = 0`, `team2LossStreak += 1`.
   - If Team 2 wins: `team2Score += 1`, `team2LossStreak = 0`, `team1LossStreak += 1`.
3. Call `EconomyService.ProcessRoundEnd(winningTeamPlayers, losingTeamPlayers, losingTeamStreak)`.
4. Check Match Completion:
   - If `team1Score >= 7` or `team2Score >= 7`:
     - Match ends! Transition phase to `"Ended"`.
     - Fire post-match summary event, transition players back to lobby after 5 seconds.
   - Else:
     - Increment `currentRound += 1`.
     - Transition phase to `"Intermission"` (3s) -> Then start next round (`"Buy"` phase).

---

## 3. Specification: `src/server/Services/EconomyService.luau`

### Purpose
Server-authoritative currency system managing PvP credit balances, initial round credits, sudden-death credit allocations, win/loss bonuses, loss streak scaling, kill rewards, and strict buy-phase validation.

### File Location
`src/server/Services/EconomyService.luau`

### Key Constants & Economy Formulas
- `PISTOL_ROUND_CREDITS = 800` (Round 1)
- `SUDDEN_DEATH_CREDITS = 5000` (Round 13 / Sudden Death)
- `WIN_BONUS = 3000` (Credits awarded to each round-winning player)
- `LOSS_STREAK_TIER_1 = 1900` (1st loss)
- `LOSS_STREAK_TIER_2 = 2400` (2nd consecutive loss)
- `LOSS_STREAK_TIER_MAX = 2900` (3+ consecutive losses)
- `KILL_REWARD = 200` (Credits awarded per kill)

### Item Price Catalog Table (`SHOP_CATALOG`)
```luau
local SHOP_CATALOG: { [string]: { price: number, category: string, armorValue: number? } } = {
	["Pistol"] = { price = 0, category = "Weapon" },
	["LightSMG"] = { price = 1000, category = "Weapon" },
	["HeavySMG"] = { price = 1500, category = "Weapon" },
	["AssaultRifle"] = { price = 2900, category = "Weapon" },
	["Carbine"] = { price = 2500, category = "Weapon" },
	["BurstRifle"] = { price = 2500, category = "Weapon" },
	["Shotgun"] = { price = 1800, category = "Weapon" },
	["SniperRifle"] = { price = 4500, category = "Weapon" },
	["LightArmor"] = { price = 400, category = "Armor", armorValue = 25 },
	["HeavyArmor"] = { price = 1000, category = "Armor", armorValue = 50 },
}
```

### Data Storage
- `playerBalances: { [number]: number }` (UserId -> Credit Balance)

### Required Functions & Implementation Details

#### `EconomyService.InitializePlayer(player: Player, startingCredits: number?)`
- Initializes `playerBalances[player.UserId] = startingCredits or 800`.
- Syncs credit balance to client via `ProfileSync` or credit remote event.

#### `EconomyService.GetCredits(player: Player): number`
- Returns `playerBalances[player.UserId] or 0`.

#### `EconomyService.SetCredits(player: Player, amount: number)`
- Sets `playerBalances[player.UserId] = math.max(0, amount)`.
- Fires remote update to client.

#### `EconomyService.AwardKillReward(killerPlayer: Player)`
- `playerBalances[killerPlayer.UserId] = (playerBalances[killerPlayer.UserId] or 0) + KILL_REWARD`.
- Fires `KillRewardNotice` client event with `+200 Credits` notification and updated balance.

#### `EconomyService.ProcessRoundEnd(winners: { Player }, losers: { Player }, loserLossStreak: number)`
1. **Winners**:
   - Add `WIN_BONUS` (+3000 Credits) to each winning player's balance.
2. **Losers**:
   - Determine loss streak bonus based on `loserLossStreak`:
     - Streak == 1: `+1900`
     - Streak == 2: `+2400`
     - Streak >= 3: `+2900`
   - Add calculated loss bonus to each losing player's balance.
3. Sync updated balances to all match participants.

#### `EconomyService.SetSuddenDeathCredits(players: { Player })`
- Sets `playerBalances[p.UserId] = 5000` for every player in `players`.

#### `EconomyService.ProcessPurchaseRequest(player: Player, itemId: string): (boolean, string, number)`
1. Check Mode:
   - If player is in Practice Range: return `true, "PracticeRangeFreeAccess", playerBalances[player.UserId] or 0`. (Practice Range bypasses economy entirely).
2. Check Round Phase:
   - Fetch active match from `RoundService`.
   - If match phase is NOT `"Buy"`: return `false, "NotInBuyPhase", currentBalance`.
3. Check Item Catalog:
   - If `SHOP_CATALOG[itemId]` is nil: return `false, "InvalidItem", currentBalance`.
4. Check Balance:
   - Cost = `SHOP_CATALOG[itemId].price`.
   - If `currentBalance < cost`: return `false, "InsufficientCredits", currentBalance`.
5. Execute Purchase:
   - Deduct `cost` from `playerBalances[player.UserId]`.
   - Apply item:
     - If category is `"Armor"`: set player's shield in `CombatServer` to `armorValue` (25 for Light Armor, 50 for Heavy Armor).
     - If category is `"Weapon"`: grant/equip weapon to player's character.
   - Return `true, "PurchaseSuccess", newBalance`.

#### `EconomyService.Initialize()`
- Binds Remote Event / Remote Function `RequestPurchase` server handler:
  ```luau
  local purchaseRemote = RemoteEvents.GetReliable("ItemPurchase")
  purchaseRemote.OnServerEvent:Connect(function(player: Player, itemId: any)
      if type(itemId) ~= "string" then return end
      local success, reason, newBalance = EconomyService.ProcessPurchaseRequest(player, itemId)
      -- Fire response back to player
  end)
  ```

---

## 4. Required Modifications to Existing Files

### 1. `src/shared/Network/RemoteEvents.luau`
Add new reliable remote event names:
```luau
export type ReliableEventName =
    "DamageDealt"
    | "PlayerDeath"
    | "ItemPurchase"
    | "MatchPhaseTransition"
    | "ProfileSync"
    | "ReliableCombat"
    | "RoundStateChanged"   -- NEW: Round state & phase timer sync
    | "RequestPurchase"     -- NEW: Buy phase purchase request
    | "PurchaseResult"      -- NEW: Purchase approval/rejection feedback
    | "KillRewardNotice"    -- NEW: +200 Credits kill notification
```

### 2. `src/server/ServerMain.server.luau`
Update `onCharacterAdded` death handler to suppress mid-round respawning when in match:
```luau
-- Auto-respawn on death (back to lobby IF in lobby, otherwise notify RoundService)
local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
if humanoid then
	humanoid.Died:Connect(function()
		local status = DirectChallengeService.GetPlayerStatus(player)
		if status == "In Match" then
			-- In round-based match: do NOT auto-respawn mid-round!
			-- RoundService handles spectate mode and next round reset.
			RoundService.OnPlayerDied(player)
		else
			-- In Lobby: auto-respawn after 3 seconds
			task.wait(3)
			if player.Parent then
				setPlayerRespawnToLobby(player)
				DirectChallengeService.SetPlayerStatus(player, "In Lobby")
				player:LoadCharacter()
			end
		end
	end)
end
```

### 3. `src/server/Combat/CombatServer.luau`
In `ProcessHitReport`, detect player kill and trigger `EconomyService` + `RoundService` callbacks:
```luau
-- Check if hit killed victim player
if victimState and victimState.health == 0 and previousHealth > 0 then
    local victimPlayer = Players:GetPlayerByUserId(victimUserId)
    local attackerPlayer = Players:GetPlayerByUserId(attackerUserId)
    if victimPlayer then
        RoundService.OnPlayerDied(victimPlayer, attackerPlayer)
    end
end
```

---

## 5. Verification & Test Plan

1. **Automated Unit & Integration Verification Script**:
   - Create `src/server/Tests/M2_RoundEconomyTest.server.luau` to validate:
     - State machine transition sequence (`Buy` -> `Live` -> `RoundEnd` -> `Intermission`).
     - Sudden-death round initialization at 6-6 tie (5000 credits).
     - Win bonus (+3000) and scaling loss streak arithmetic (+1900, +2400, +2900).
     - Kill reward credit addition (+200).
     - Server validation rejection of purchases outside Buy Phase or exceeding credit balance.
     - Free access in Practice Range mode.

2. **Rojo Build & Studio Verification**:
   - Run `.\rojo.exe build default.project.json -o Verification.rbxl` to confirm zero compilation errors.
