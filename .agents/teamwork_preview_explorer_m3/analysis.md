# Milestone 3 (M3_Operatives_Abilities) — Analysis & Implementation Specifications

## 1. Overview & Scope

Milestone 3 defines the complete Operative and Ability System for **Project OVERCLOCK**, featuring 6 distinct Operatives and 18 functional abilities, alongside ultimate accumulation math, round cooldown reset mechanics, and Practice Range sandbox behavior.

This document serves as the implementation specification for **Worker 3** to build:
1. `src/shared/Data/OperativeStats.luau` — Centralized data registry for all 6 Operatives and 18 abilities.
2. `src/server/Services/OperativeService.luau` — Server-authoritative engine handling ability execution, ultimate charge tracking, credit validation, cooldown timers, status effects, and replication.
3. `src/client/Controllers/OperativeController.luau` — Client controller managing keybinds (`E`, `C`, `X`), placement previews, instant Practice Range switching, visual FX replication, and HUD sync.

---

## 2. Operative Roster & 18 Functional Abilities

| Operative | Role | Slot | Ability Name | Cooldown (PvP) | Credit Cost (PvP) | Gameplay Mechanism |
|---|---|---|---|---|---|---|
| **Vex** | Intel | Basic | Tracking Dart | 20s | 0 | Fires projectile dart along aim vector. On hit, applies wallhack highlight outline to target for 5s visible to team. |
| | | Paid | Shock Trap | 15s | 300 | Deploys proximity trap (8-stud radius). Triggers on enemy entry, dealing 40 damage and 40% slow (`SpeedMultiplier = 0.6`) for 3s. |
| | | Ultimate | Null Void EMP | Ult (100%) | 0 | Emits 35-stud EMP shockwave. Destroys active deployables and silences enemy abilities for 8s (`Silenced = true`). |
| **Warden** | Defense | Basic | Energy Wall | 25s | 0 | Spawns deployable 12x8x1 energy wall (300 HP, 10s duration) blocking bullets and sightlines. |
| | | Paid | Fortify Barrier | 18s | 400 | Grants Warden +30 temporary Overshield for 8s OR repairs targeted active Energy Wall to 100% HP + 5s duration. |
| | | Ultimate | Aegis Shield | Ult (100%) | 0 | Activates personal damage reduction shield for 8s, reducing incoming damage by 50% (`DamageReduction = 0.5`) with crowd control immunity. |
| **Fray** | Mobility | Basic | Blink Dash | 12s | 0 | Instantly dashes Fray 25 studs in look/movement direction with particle trail (raycast obstacle check). |
| | | Paid | Smoke Screen | 15s | 250 | Throws smoke canister creating 15-stud dense volumetric smoke sphere lasting 10s, blocking vision and raycasts. |
| | | Ultimate | Hyperdrive | Ult (100%) | 0 | 10s self-buff granting +30% weapon fire rate (`FireRateMultiplier = 1.3`), +50% reload speed (`ReloadSpeedMultiplier = 0.5`), and +20% move speed. |
| **Choke** | Area Denial | Basic | Static Field Grenade | 18s | 0 | Throws grenade spawning 12-stud static field for 7s. Obscures vision and applies HUD blur to enemies inside. |
| | | Paid | Incendiary | 20s | 300 | Throws canister creating 10-stud fire pool for 6s. Deals 15 DPS (7.5 damage per 0.5s tick) to enemies standing inside. |
| | | Ultimate | Absolute Zero | Ult (100%) | 0 | Spawns 30-stud cryogenic zone for 8s. Enemies inside are slowed by 60% (`SpeedMultiplier = 0.4`), fire rate reduced by 30%, and take 5 DPS freeze damage. |
| **Pulse** | Intel | Basic | Sonar Pulse | 16s | 0 | Emits expanding 40-stud sonar wave. Detects enemy movement and displays minimap/HUD blips for 4s. |
| | | Paid | Sensor Beacon | 20s | 300 | Deploys 50 HP wall/floor beacon (20-stud detection radius). Highlights enemies red for 3s when they enter range. Lasts until destroyed or round ends. |
| | | Ultimate | Global Scan | Ult (100%) | 0 | Emits 3 map-wide radar pulses at 1.5s intervals. Highlights all line-of-sight enemies with red outlines for 3s per wave. |
| **Bastion** | Defense | Basic | Auto-Turret | 25s | 0 | Deploys 150 HP automated mini-turret (40-stud detection, 360° rotation, 300 RPM, 8 damage/shot) lasting 20s or until destroyed. |
| | | Paid | Repulsor Mine | 15s | 250 | Places remote/proximity mine (6-stud blast radius). Detonates for 25 damage and 50 studs/sec outward knockback impulse. |
| | | Ultimate | Siege Turret | Ult (100%) | 0 | Transforms Bastion into stationary Siege Turret for 12s (or untoggle). Grants +100 shield, heavy rotary minigun (45 damage/shot, 800 RPM, infinite ammo, zero recoil). |

---

## 3. Data Specification: `src/shared/Data/OperativeStats.luau`

```luau
--!strict
--[=[
    Project OVERCLOCK: Operative Statistics Registry
    Centralized data module defining Operative rosters, roles, ability stats,
    cooldowns, credit costs, and visual assets.
]=]

export type OperativeRole = "Intel" | "Defense" | "Mobility" | "Area Denial"
export type AbilitySlot = "Basic" | "Paid" | "Ultimate"

export type AbilityData = {
	id: string,
	name: string,
	slot: AbilitySlot,
	description: string,
	cooldown: number, -- PvP cooldown in seconds
	creditCost: number, -- PvP credit cost (0 for Basic & Ult)
	iconAsset: string?,
	range: number?, -- Effective range in studs
	duration: number?, -- Active duration in seconds
	damage: number?, -- Base damage if applicable
	radius: number?, -- Area radius in studs
}

export type OperativeData = {
	id: string,
	name: string,
	role: OperativeRole,
	description: string,
	portraitAsset: string?,
	abilities: {
		Basic: AbilityData,
		Paid: AbilityData,
		Ultimate: AbilityData,
	},
}

local OperativeRegistry: { [string]: OperativeData } = {
	Vex = {
		id = "Vex",
		name = "Vex",
		role = "Intel",
		description = "Intel specialist capable of tagging targets through walls and disabling enemy technology.",
		abilities = {
			Basic = {
				id = "Vex_Dart",
				name = "Tracking Dart",
				slot = "Basic",
				description = "Fires a high-velocity dart that tags hit enemies, revealing their outline through walls for 5s.",
				cooldown = 20,
				creditCost = 0,
				range = 200,
				duration = 5,
			},
			Paid = {
				id = "Vex_Trap",
				name = "Shock Trap",
				slot = "Paid",
				description = "Places a proximity trap that shocks entering enemies for 40 damage and slows movement by 40% for 3s.",
				cooldown = 15,
				creditCost = 300,
				damage = 40,
				radius = 8,
				duration = 3,
			},
			Ultimate = {
				id = "Vex_EMP",
				name = "Null Void EMP",
				slot = "Ultimate",
				description = "Emits a 35-stud EMP shockwave that silences enemy abilities for 8s and destroys active deployables.",
				cooldown = 0,
				creditCost = 0,
				radius = 35,
				duration = 8,
			},
		},
	},

	Warden = {
		id = "Warden",
		name = "Warden",
		role = "Defense",
		description = "Defensive anchor skilled at fortifying sightlines and shielding allies.",
		abilities = {
			Basic = {
				id = "Warden_Wall",
				name = "Energy Wall",
				slot = "Basic",
				description = "Deploys a transparent energy barrier (300 HP, 10s) blocking bullets and vision.",
				cooldown = 25,
				creditCost = 0,
				duration = 10,
			},
			Paid = {
				id = "Warden_Fortify",
				name = "Fortify Barrier",
				slot = "Paid",
				description = "Grants +30 temporary Overshield for 8s or fully repairs a deployed Energy Wall (+5s duration).",
				cooldown = 18,
				creditCost = 400,
				duration = 8,
			},
			Ultimate = {
				id = "Warden_Shield",
				name = "Aegis Shield",
				slot = "Ultimate",
				description = "Activates personal Aegis Shield for 8s, reducing all incoming damage by 50% with CC immunity.",
				cooldown = 0,
				creditCost = 0,
				duration = 8,
			},
		},
	},

	Fray = {
		id = "Fray",
		name = "Fray",
		role = "Mobility",
		description = "High-mobility duelist designed for aggressive entry frags and swift disengages.",
		abilities = {
			Basic = {
				id = "Fray_Blink",
				name = "Blink Dash",
				slot = "Basic",
				description = "Instantly blinks 25 studs in look direction.",
				cooldown = 12,
				creditCost = 0,
				range = 25,
			},
			Paid = {
				id = "Fray_Smoke",
				name = "Smoke Screen",
				slot = "Paid",
				description = "Throws a smoke canister creating a 15-stud volumetric smoke sphere lasting 10s.",
				cooldown = 15,
				creditCost = 250,
				radius = 15,
				duration = 10,
			},
			Ultimate = {
				id = "Fray_Hyperdrive",
				name = "Hyperdrive",
				slot = "Ultimate",
				description = "Boosts weapon fire rate (+30%), reload speed (+50%), and move speed (+20%) for 10s.",
				cooldown = 0,
				creditCost = 0,
				duration = 10,
			},
		},
	},

	Choke = {
		id = "Choke",
		name = "Choke",
		role = "Area Denial",
		description = "Area denial expert who controls chokepoints with static field disruptions and incendiary flames.",
		abilities = {
			Basic = {
				id = "Choke_Static",
				name = "Static Field Grenade",
				slot = "Basic",
				description = "Spawns a 12-stud static field for 7s that obscures enemy vision and blurs enemy HUD.",
				cooldown = 18,
				creditCost = 0,
				radius = 12,
				duration = 7,
			},
			Paid = {
				id = "Choke_Incendiary",
				name = "Incendiary",
				slot = "Paid",
				description = "Creates a 10-stud fire pool for 6s dealing 15 DPS (7.5 dmg per 0.5s tick).",
				cooldown = 20,
				creditCost = 300,
				damage = 15,
				radius = 10,
				duration = 6,
			},
			Ultimate = {
				id = "Choke_Zero",
				name = "Absolute Zero",
				slot = "Ultimate",
				description = "Creates a 30-stud cryogenic zone for 8s slowing enemies by 60% and dealing 5 DPS freeze damage.",
				cooldown = 0,
				creditCost = 0,
				damage = 5,
				radius = 30,
				duration = 8,
			},
		},
	},

	Pulse = {
		id = "Pulse",
		name = "Pulse",
		role = "Intel",
		description = "Recon operative specializing in radar sweeps, sonar detection, and map-wide vision.",
		abilities = {
			Basic = {
				id = "Pulse_Sonar",
				name = "Sonar Pulse",
				slot = "Basic",
				description = "Emits a 40-stud sonar wave displaying moving enemy positions on minimap/HUD for 4s.",
				cooldown = 16,
				creditCost = 0,
				radius = 40,
				duration = 4,
			},
			Paid = {
				id = "Pulse_Beacon",
				name = "Sensor Beacon",
				slot = "Paid",
				description = "Places a 50 HP sticky beacon (20-stud detection radius) that highlights enemies red for 3s.",
				cooldown = 20,
				creditCost = 300,
				radius = 20,
				duration = 3,
			},
			Ultimate = {
				id = "Pulse_Scan",
				name = "Global Scan",
				slot = "Ultimate",
				description = "Fires 3 map-wide radar waves at 1.5s intervals, highlighting line-of-sight enemies for 3s per wave.",
				cooldown = 0,
				creditCost = 0,
				duration = 6,
			},
		},
	},

	Bastion = {
		id = "Bastion",
		name = "Bastion",
		role = "Defense",
		description = "Heavy defensive specialist armed with deployable auto-turrets and repulsor shock mines.",
		abilities = {
			Basic = {
				id = "Bastion_Turret",
				name = "Auto-Turret",
				slot = "Basic",
				description = "Deploys a 150 HP mini-turret (40-stud range, 300 RPM, 8 dmg/shot) lasting 20s.",
				cooldown = 25,
				creditCost = 0,
				range = 40,
				damage = 8,
				duration = 20,
			},
			Paid = {
				id = "Bastion_Mine",
				name = "Repulsor Mine",
				slot = "Paid",
				description = "Deploys proximity mine dealing 25 damage and 50 studs/sec knockback impulse in 6-stud blast.",
				cooldown = 15,
				creditCost = 250,
				damage = 25,
				radius = 6,
			},
			Ultimate = {
				id = "Bastion_Siege",
				name = "Siege Turret",
				slot = "Ultimate",
				description = "Transforms into stationary Siege Turret for 12s (+100 shield, minigun 45 dmg/shot, 800 RPM).",
				cooldown = 0,
				creditCost = 0,
				damage = 45,
				duration = 12,
			},
		},
	},
}

local OperativeStats = {}

function OperativeStats.Get(id: string): OperativeData?
	return OperativeRegistry[id]
end

function OperativeStats.GetAll(): { [string]: OperativeData }
	return OperativeRegistry
end

function OperativeStats.GetAbility(id: string, slot: AbilitySlot): AbilityData?
	local op = OperativeRegistry[id]
	if not op then
		return nil
	end
	return op.abilities[slot]
end

return OperativeStats
```

---

## 4. Server Service Specification: `src/server/Services/OperativeService.luau`

### Key Responsibilities
1. **Player Session State Tracking**:
   - `selectedOperative`: string (e.g. `"Vex"`)
   - `ultCharge`: number (0 to 100)
   - `cooldownEndTimestamps`: `{ Basic: number, Paid: number, Ultimate: number }`
   - `silencedUntil`: number (timestamp when Null Void EMP silence ends)
2. **Ultimate Accumulation Math**:
   - `100 damage dealt = +10% ult charge` (0.1% per 1 damage).
   - `1 kill = +20% ult charge`.
   - Max charge capped at `100%`.
   - Accumulates across rounds in PvP!
3. **Round Reset Mechanics**:
   - On round start (`RoundService.StartRound`), reset `cooldownEndTimestamps` to `0` for Basic & Paid abilities.
   - Ult charge is **retained** across rounds in PvP.
4. **Practice Range Sandbox Rules**:
   - When player status is `"Practice Range"` (`DirectChallengeService.GetPlayerStatus(player) == "Practice Range"`):
     - Cooldowns are `0s`.
     - Credit cost is `0`.
     - Ult charge is instantly `100%` (or recharges instantly).
     - Players can call `SelectOperative` at any time to switch Operatives instantly.
5. **Server Validation Rules (`UseAbility`)**:
   - Check if player is alive in `CombatServer`.
   - Check if silenced (`os.clock() < silencedUntil`).
   - If PvP:
     - Check cooldown (`os.clock() >= cooldownEndTimestamps[slot]`).
     - If `slot == "Paid"`: verify credit balance via `EconomyService.GetCredits(player) >= creditCost`.
     - If `slot == "Ultimate"`: verify `ultCharge == 100`.
   - Action execution:
     - Deduct credit cost (if Paid in PvP via `EconomyService.SetCredits`).
     - Reset `ultCharge` to 0 (if Ultimate in PvP).
     - Set cooldown end timestamp: `cooldownEndTimestamps[slot] = os.clock() + abilityData.cooldown`.
     - Execute ability server handler (spawn wall/turret/mine/zone, apply status effect, reveal target).
     - Sync state to client (`OperativeStateSync`) and broadcast visual FX (`AbilityReplicated`).

---

## 5. Client Controller Specification: `src/client/Controllers/OperativeController.luau`

### Key Responsibilities
1. **Input Bindings**:
   - `E` -> Basic Ability (`UseAbility("Basic", aimCFrame)`)
   - `C` -> Paid Ability (`UseAbility("Paid", aimCFrame)`)
   - `X` -> Ultimate Ability (`UseAbility("Ultimate", aimCFrame)`)
2. **Placement Preview & Aiming Gizmos**:
   - For deployables (`Energy Wall`, `Auto-Turret`, `Sensor Beacon`, `Shock Trap`), render a translucent CFrame preview part on ground aligned with raycast.
   - Left click to confirm placement, Right click to cancel preview.
3. **Practice Range Operative Switcher**:
   - Listens to UI requests from Practice Range HUD / Menu to select Operative via `SelectAgent` remote.
4. **Replication & Visual Effects**:
   - Listens to `AbilityReplicated` to spawn client-side particle effects, sound effects, smoke clouds, static fields, and EMP shockwaves.
   - Listens to `EnemyRevealed` to attach temporary `Highlight` instances (Red for enemies, Blue for teammates) on revealed characters through walls.
5. **HUD Interface**:
   - Provides getter methods for `HUDController`:
     - `OperativeController.GetSelectedOperative(): OperativeData?`
     - `OperativeController.GetUltCharge(): number`
     - `OperativeController.GetCooldownRemaining(slot: AbilitySlot): number`

---

## 6. Verification Plan & Test Strategy for Worker 3

1. **Automated Verification Script (`src/server/Tests/M3_OperativeTest.server.luau`)**:
   - Test 1: `OperativeStats.Get("Vex")` returns 3 valid abilities.
   - Test 2: `OperativeService.AddUltCharge` increases ult from 0% to 10% on 100 damage dealt, and 20% on kill. Caps at 100%.
   - Test 3: `OperativeService.UseAbility` validates credit cost for Paid abilities in PvP and rejects if insufficient credits.
   - Test 4: `OperativeService.ResetRoundCooldowns` resets Basic/Paid cooldowns while preserving Ult charge.
   - Test 5: In Practice Range, abilities execute with zero cooldown and 0 credit cost.

2. **Rojo Build Verification**:
   - Execute `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` and verify 0 syntax/compilation errors.
