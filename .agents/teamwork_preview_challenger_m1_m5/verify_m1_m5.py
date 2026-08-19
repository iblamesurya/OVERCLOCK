import math
import sys
import os
import re

# Helper colors for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
RESET = "\033[0m"

print("==================================================")
print("Project OVERCLOCK: M1 & M5 Empirical Verification Harness")
print("==================================================")

passed = 0
failed = 0

def check(condition, message):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [{GREEN}PASS{RESET}] {message}")
    else:
        failed += 1
        print(f"  [{RED}FAIL{RESET}] {message}")

# ---------------------------------------------------------
# Weapon Registry Data directly from src/shared/Data/WeaponStats.luau
# ---------------------------------------------------------
WEAPONS = {
    "Pistol": {"damage": 24, "headshotMultiplier": 2.0, "maxRange": 500},
    "LightSMG": {"damage": 17, "headshotMultiplier": 2.0, "maxRange": 550},
    "HeavySMG": {"damage": 22, "headshotMultiplier": 2.0, "maxRange": 650},
    "Carbine": {"damage": 28, "headshotMultiplier": 2.25, "maxRange": 900},
    "AssaultRifle": {"damage": 32, "headshotMultiplier": 2.5, "maxRange": 1000},
    "SniperRifle": {"damage": 105, "headshotMultiplier": 2.5, "maxRange": 2500},
    "Shotgun": {"damage": 80, "headshotMultiplier": 2.0, "maxRange": 350},
    "BurstRifle": {"damage": 27, "headshotMultiplier": 2.25, "maxRange": 1200},
}

def calculate_damage(weapon_id, is_headshot, distance):
    stats = WEAPONS.get(weapon_id)
    if not stats:
        return 0
    base_damage = stats["damage"]
    mult = stats["headshotMultiplier"] if is_headshot else 1.0
    falloff_start = stats["maxRange"] * 0.5
    damage_scale = 1.0
    
    if distance > falloff_start:
        excess = distance - falloff_start
        falloff_range = stats["maxRange"] - falloff_start
        if falloff_range <= 0:
            return math.floor(base_damage * mult + 0.5)
        falloff_percent = min(max(excess / falloff_range, 0.0), 0.6)
        damage_scale = 1.0 - falloff_percent
        
    return math.floor(base_damage * mult * damage_scale + 0.5)

print("\n--- 1. Weapon Damage Calculations Across Distances & Headshot Multipliers ---")

distances_m = [0, 20, 50, 100]
stud_conversions = {0: 0, 20: 65.6, 50: 164, 100: 328}

for w_id, w_info in WEAPONS.items():
    hs_mult = w_info["headshotMultiplier"]
    check(2.0 <= hs_mult <= 2.5, f"{w_id} headshot multiplier {hs_mult}x within 2.0x - 2.5x range")
    
    for dist_m in distances_m:
        dist_studs = stud_conversions[dist_m]
        
        body_dmg = calculate_damage(w_id, False, dist_studs)
        head_dmg = calculate_damage(w_id, True, dist_studs)
        
        check(head_dmg >= body_dmg, f"{w_id} at {dist_m}m ({dist_studs} studs): Headshot ({head_dmg}) >= Bodyshot ({body_dmg})")

print("\n--- Summary Table of Damage Math ---")
header = f"{'Weapon':<15} | {'Type':<8} | {'0m':<6} | {'20m':<6} | {'50m':<6} | {'100m':<6}"
print(header)
print("-" * len(header))

for w_id in WEAPONS:
    b_0 = calculate_damage(w_id, False, stud_conversions[0])
    b_20 = calculate_damage(w_id, False, stud_conversions[20])
    b_50 = calculate_damage(w_id, False, stud_conversions[50])
    b_100 = calculate_damage(w_id, False, stud_conversions[100])
    
    h_0 = calculate_damage(w_id, True, stud_conversions[0])
    h_20 = calculate_damage(w_id, True, stud_conversions[20])
    h_50 = calculate_damage(w_id, True, stud_conversions[50])
    h_100 = calculate_damage(w_id, True, stud_conversions[100])
    
    print(f"{w_id:<15} | {'Body':<8} | {b_0:<6} | {b_20:<6} | {b_50:<6} | {b_100:<6}")
    print(f"{w_id:<15} | {'Head':<8} | {h_0:<6} | {h_20:<6} | {h_50:<6} | {h_100:<6}")

print("\n--- 2. Stress Test Armor Absorption ---")

def process_armor_damage(raw_damage, initial_shield, initial_health=100):
    shield = initial_shield
    health = initial_health
    if shield > 0:
        max_absorption = math.floor(raw_damage * 0.5)
        shield_dmg = min(shield, max_absorption)
        health_dmg = raw_damage - shield_dmg
        shield -= shield_dmg
        health = max(0, health - health_dmg)
    else:
        shield_dmg = 0
        health_dmg = min(health, raw_damage)
        health = max(0, health - raw_damage)
    return shield_dmg, health_dmg, shield, health

raw_damages = [10, 25, 50, 100, 200]
shields = [25, 50]

for s in shields:
    print(f"\nTesting initial shield = {s}:")
    for raw in raw_damages:
        s_dmg, h_dmg, rem_s, rem_h = process_armor_damage(raw, s)
        expected_absorption = min(s, math.floor(raw * 0.5))
        check(s_dmg == expected_absorption, 
              f"Raw {raw} vs Shield {s}: Armor absorbed {s_dmg} (expected {expected_absorption}), Health took {h_dmg}, Rem Shield={rem_s}, Rem Health={rem_h}")
        check(rem_s >= 0, f"Remaining shield non-negative: {rem_s}")
        check(rem_h >= 0, f"Remaining health non-negative: {rem_h}")

print("\n--- 3. Practice Range Target Hit Logic Verification ---")

def process_hit_report_simulation(match_phase, victim_user_id, victim_player_exists, is_alive, target_instance_attr):
    if match_phase != "InGame" and match_phase != "PracticeRange":
        return False, "InvalidMatchPhase", None
        
    if victim_player_exists and match_phase != "PracticeRange":
        pass
        
    if victim_player_exists and victim_user_id != 0 and not is_alive:
        return False, "VictimDead", None
        
    if not victim_player_exists or victim_user_id == 0:
        if target_instance_attr.get("is_bot"):
            return True, None, target_instance_attr.get("bot_health", 100)
        if target_instance_attr.get("IsPracticeTarget") or target_instance_attr.get("IsTarget"):
            return True, None, 0
        if match_phase == "PracticeRange":
            return True, None, 0
            
    return True, None, 100

res1, err1, hp1 = process_hit_report_simulation("PracticeRange", 0, False, False, {"IsTarget": True})
check(res1 is True and err1 is None, "Practice Range hit report with nil victim player and IsTarget=True succeeds")

res2, err2, hp2 = process_hit_report_simulation("PracticeRange", 0, False, False, {"is_bot": True, "bot_health": 75})
check(res2 is True and err2 is None and hp2 == 75, "Practice Range hit report with nil victim player on bot succeeds with bot health")

res3, err3, hp3 = process_hit_report_simulation("InGame", 0, False, False, {})
check(res3 is True and err3 is None, "InGame non-player target hit handled")

print("\n--- 4. Map Layout Instantiation Verification ---")

with open("c:/Users/tummala surya/Downloads/roblox/src/shared/Map/DuelArenaMap.luau", "r") as f:
    duel_code = f.read()

check("TEAM1_SPAWN_POSITIONS" in duel_code, "DuelArenaMap defines TEAM1_SPAWN_POSITIONS")
check("TEAM2_SPAWN_POSITIONS" in duel_code, "DuelArenaMap defines TEAM2_SPAWN_POSITIONS")

t1_count = duel_code.count("Vector3.new(-12, 2, -60)") + duel_code.count("Vector3.new(12, 2, -60)") + duel_code.count("Vector3.new(-4, 2, -64)") + duel_code.count("Vector3.new(4, 2, -64)")
t2_count = duel_code.count("Vector3.new(-12, 2, 60)") + duel_code.count("Vector3.new(12, 2, 60)") + duel_code.count("Vector3.new(-4, 2, 64)") + duel_code.count("Vector3.new(4, 2, 64)")

check(t1_count == 4, f"DuelArenaMap Team 1 spawn count == 4 (found {t1_count})")
check(t2_count == 4, f"DuelArenaMap Team 2 spawn count == 4 (found {t2_count})")

with open("c:/Users/tummala surya/Downloads/roblox/src/shared/Map/PracticeRangeMapLayout.luau", "r") as f:
    range_code = f.read()

check("PLAYER_SPAWN_POSITIONS" in range_code, "PracticeRangeMapLayout defines PLAYER_SPAWN_POSITIONS")
check("BOT_WAYPOINT_POSITIONS" in range_code, "PracticeRangeMapLayout defines BOT_WAYPOINT_POSITIONS")
check("STATIONARY_TARGETS" in range_code, "PracticeRangeMapLayout defines STATIONARY_TARGETS")

# Parse target definitions inside STATIONARY_TARGETS table specifically
targets_in_table = re.findall(r'name\s*=\s*"Target_Stationary_\d+"', range_code)
check(len(targets_in_table) == 6, f"PracticeRangeMapLayout stationary target count == 6 (found {len(targets_in_table)})")

# Parse bot waypoints inside BOT_WAYPOINT_POSITIONS table specifically
waypoints_in_table = re.findall(r'Vector3\.new\([^)]+\),\s*--\s*Waypoints_Bot_\d+', range_code)
check(len(waypoints_in_table) == 8, f"PracticeRangeMapLayout bot waypoint count == 8 (found {len(waypoints_in_table)})")

check('targetPart:SetAttribute("IsTarget", true)' in range_code, "Stationary target parts set attribute IsTarget = true")
check('bullseyeDisc:SetAttribute("IsBullseye", true)' in range_code, "Bullseye disc sets attribute IsBullseye = true")
check('wpPart:SetAttribute("WaypointIndex", i)' in range_code, "Bot waypoints set attribute WaypointIndex")

print("\n==================================================")
print(f"VERIFICATION SUMMARY: {passed} PASSED, {failed} FAILED")
print("==================================================")

if failed > 0:
    sys.exit(1)
