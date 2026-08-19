# Technical Analysis & Implementation Specification: Milestone 1 (M1_Combat_Arsenal)

## Executive Summary
Milestone 1 (M1_Combat_Arsenal) establishes the core combat foundation for Project OVERCLOCK. This report provides a concrete, file-by-file specification for Worker 1 to extend the weapon registry, implement server-authoritative damage and armor absorption in `CombatServer.luau`, and update client weapon controllers and UI for 7+ weapons across all weapon classes.

---

## 1. File Specifications & Architecture Plan

### 1.1 `src/shared/Data/WeaponStats.luau`
**Current Limitations**:
- Contains only 4 weapons (`AssaultRifle`, `SMG`, `SniperRifle`, `BurstRifle`).
- Uses legacy "Paradigm" display names (`AR-15 Paradigm`, `Vector-9 Paradigm`, etc.).
- Missing Armor specifications (`LightArmor` and `HeavyArmor`).
- Missing 7+ weapon spectrum (Sidearm, SMG Tiers 1/2, Rifle Tiers 1/2, Sniper, Shotgun).

**Required Changes for Worker 1**:
1. Export an `ArmorData` type:
   ```luau
   export type ArmorData = {
       id: string,
       displayName: string,
       shield: number,
       cost: number,
   }
   ```
2. Define `ArmorRegistry`:
   ```luau
   local ArmorRegistry: { [string]: ArmorData } = {
       LightArmor = {
           id = "LightArmor",
           displayName = "Light Armor",
           shield = 25,
           cost = 400,
       },
       HeavyArmor = {
           id = "HeavyArmor",
           displayName = "Heavy Armor",
           shield = 50,
           cost = 1000,
       },
   }
   ```
3. Add helper functions: `WeaponStats.GetArmor(armorId: string): ArmorData?` and `WeaponStats.GetAllArmor(): { [string]: ArmorData }`.
4. Extend `WeaponRegistry` to 8 total weapons with OVERCLOCK display names and headshot multipliers (2.0x - 2.5x):

| Weapon ID | Class | Display Name | Damage | HS Mult | RPM | Fire Mode | Mag/Res | Vel | Max Range | Spread Min/Max | Recoil (Vector3) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `Pistol` | Sidearm | OC-P9 Sidearm | 24 | 2.0x | 450 | Semi | 12 / 60 | 2000 | 500 | 0.3 / 2.5 | (0.025, 0.010, 0.030) |
| `LightSMG` | SMG Tier 1 | OC-Vector Light SMG | 17 | 2.0x | 950 | Auto | 30 / 120 | 1800 | 550 | 0.7 / 4.2 | (0.020, 0.015, 0.030) |
| `HeavySMG` | SMG Tier 2 | OC-Marauder Heavy SMG | 22 | 2.0x | 800 | Auto | 35 / 140 | 2000 | 650 | 0.6 / 3.8 | (0.026, 0.018, 0.040) |
| `Carbine` | Rifle Tier 1 | OC-Phantom Carbine | 28 | 2.25x | 700 | Auto | 25 / 100 | 2400 | 900 | 0.35 / 2.8 | (0.030, 0.012, 0.050) |
| `AssaultRifle` | Rifle Tier 2 | OC-Vanguard AR | 32 | 2.5x | 600 | Auto | 30 / 120 | 2600 | 1000 | 0.3 / 3.0 | (0.035, 0.015, 0.060) |
| `SniperRifle` | Sniper Rifle | OC-Apex Sniper | 105 | 2.5x | 45 | Semi | 5 / 25 | 4000 | 2500 | 0.05 / 8.0 | (0.160, 0.040, 0.220) |
| `Shotgun` | Shotgun | OC-Enforcer Shotgun | 80 | 2.0x | 100 | Semi | 6 / 24 | 1500 | 350 | 1.5 / 6.0 | (0.120, 0.050, 0.150) |
| `BurstRifle` | Rifle Tier 1 (Burst) | OC-BR3 Burst Rifle | 27 | 2.25x | 750 | Burst | 30 / 120 | 2800 | 1200 | 0.25 / 2.8 | (0.028, 0.010, 0.045) |

5. Verify & refine `WeaponStats.CalculateDamage`:
   ```luau
   function WeaponStats.CalculateDamage(weaponId: string, isHeadshot: boolean, distance: number): number
       local stats = WeaponRegistry[weaponId]
       if not stats then
           return 0
       end

       local baseDamage = stats.damage
       local mult = isHeadshot and stats.headshotMultiplier or 1.0

       -- Distance falloff (linear dropoff past 50% maxRange, max 60% reduction)
       local falloffStart = stats.maxRange * 0.5
       local damageScale = 1.0

       if distance > falloffStart then
           local excess = distance - falloffStart
           local falloffRange = stats.maxRange - falloffStart
           if falloffRange <= 0 then
               return math.floor(baseDamage * mult + 0.5)
           end
           local falloffPercent = math.clamp(excess / falloffRange, 0, 0.6)
           damageScale = 1.0 - falloffPercent
       end

       return math.floor(baseDamage * mult * damageScale + 0.5)
   end
   ```

---

### 1.2 `src/server/Combat/CombatServer.luau`
**Current Limitations**:
- Hardcoded base damage (`local dmg = baseDamage or 25` at line 326).
- Full 100% shield absorption before touching health (`victimState.shield -= shieldDmg`).
- Rigid player status rejection (`status == "In Lobby" or status ~= "In Match"` at line 270 & 277).
- Lacks handling for Practice Range mode, stationary targets, and patrol bot humanoids.

**Required Changes for Worker 1**:
1. **Dynamic Damage Calculation**:
   Replace legacy damage application in `ProcessHitReport` with `WeaponStats.CalculateDamage()`:
   ```luau
   local isHeadshot = payload.targetInstance and payload.targetInstance.Name == "Head" or false
   local rawDamage = WeaponStats.CalculateDamage(payload.weaponId, isHeadshot, payload.distance)
   ```

2. **50% Armor Damage Absorption Logic**:
   Update health and shield reduction calculations to enforce "Armor absorbs 50% damage until depleted":
   ```luau
   if victimState then
       if victimState.shield > 0 then
           local maxAbsorption = math.floor(rawDamage * 0.5)
           local shieldDmg = math.min(victimState.shield, maxAbsorption)
           local healthDmg = rawDamage - shieldDmg
           
           victimState.shield -= shieldDmg
           victimState.health = math.max(0, victimState.health - healthDmg)
       else
           victimState.health = math.max(0, victimState.health - rawDamage)
       end
   end
   ```

3. **Practice Range & Patrol Bot Hit Permissibility**:
   - Update match phase check: Allow `self._matchPhase == "InGame"` OR `self._matchPhase == "PracticeRange"`.
   - Update attacker status check: Allow `status == "In Match"` OR `status == "In Practice Range"`.
   - Handle non-player victims (Practice Range target wall parts or patrol bot humanoids where `victimPlayer` is `nil`):
     ```luau
     if not victimPlayer then
         -- Non-player victim (Patrol Bot or Practice Range Target)
         if payload.targetInstance then
             local targetModel = payload.targetInstance:FindFirstAncestorOfClass("Model")
             local botHumanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
             if botHumanoid then
                 botHumanoid:TakeDamage(rawDamage)
                 return true, nil, botHumanoid.Health
             end
             -- Practice target hit trigger
             if payload.targetInstance:GetAttribute("IsPracticeTarget") == true or payload.targetInstance.Name == "PracticeTarget" then
                 return true, nil, 0
             end
         end
     end
     ```

---

### 1.3 `src/client/Controllers/WeaponController.luau` & `CrosshairController.luau`
**Current Limitations**:
- `WeaponController.luau` only equips `"AssaultRifle"` by default and has hardcoded parameters.
- `CrosshairController.luau` needs smooth reticle scaling for higher spread weapons like Shotgun.
- `LoadoutInspectorUI.luau` only displays 4 weapons in selection tabs.

**Required Changes for Worker 1**:
1. `WeaponController.luau`:
   - Extend `EquipWeapon(weaponId)` to validate and equip any of the 8 weapons in `WeaponRegistry`.
   - In `FireShot()`, ensure `hitInstance` check handles headshots (`hitInstance.Name == "Head"`) and sends `weaponId`, `hitPosition`, `distance`, and `targetInstance` to server hit report payload.
2. `CrosshairController.luau`:
   - Verify `CalculateSpreadPixelOffset` gracefully handles higher spread bounds (e.g. Shotgun `spreadMax = 6.0` degrees).
3. `LoadoutInspectorUI.luau`:
   - Expand `weapons` array in UI tabs from `{"AssaultRifle", "SMG", "SniperRifle", "BurstRifle"}` to include all 8 weapons (`Pistol`, `LightSMG`, `HeavySMG`, `Carbine`, `AssaultRifle`, `SniperRifle`, `Shotgun`, `BurstRifle`).
   - Add 3D preview model geometry builders for `Pistol`, `LightSMG`, `HeavySMG`, `Carbine`, and `Shotgun`.

---

## 2. Verification Protocol for Worker 1
After implementation, Worker 1 must execute:
1. **Rojo Build Verification**:
   Run `.\rojo.exe build default.project.json -o test_build.rbxl` to verify 0 syntax or compilation errors.
2. **Damage Calculation Test Script**:
   Create a test script `src/server/Tests/M1_DamageTest.server.luau` validating:
   - `WeaponStats.CalculateDamage("AssaultRifle", false, 100)` equals base damage 32.
   - `WeaponStats.CalculateDamage("AssaultRifle", true, 100)` equals headshot damage 80 (2.5x).
   - Distance falloff past `maxRange * 0.5` reduces damage linearly.
   - Armor absorption (100 raw damage against 25 shield results in 25 shield absorbed, 75 health damage).
3. **Practice Range Hit Validation**:
   Confirm hits on non-player models (patrol bots/targets) do not return `"VictimInLobby"` or `"AttackerInLobby"` errors.
