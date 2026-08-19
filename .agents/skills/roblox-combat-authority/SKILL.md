---
name: roblox-combat-authority
description: Server-authoritative hitscan, projectile, and spawn rules for the arena prototype with client input validation.
---

# Roblox Combat Authority — Server Owns Damage

Use when touching `CombatService.server.luau`, `ProjectileService.luau`, `WeaponClient.local.luau`, `WeaponConfig.luau`, `PlayerLifecycle.server.luau`, or any firing/damage path.

## Authority boundary

**Server owns:** player state (`Lobby/SpawnProtected/Playing/Dead`), spawn/ForceField, Tool ownership, magazine, reload timer, cooldown, range, muzzle origin, aim sanity, raycast, projectile integration, gravity, damage (`TakeDamage`), score, round state.

**Client may send:** `weaponId: string`, `rawDirection: Vector3`, `sequence: number`. Client **never** sends target, hit part, damage, muzzle, range, ammo, cooldown, score, or projectile result. Client predicts only visuals.

## Spawn and respawn (PlayerLifecycle.server.luau)

`Players.RespawnTime = 6`. On `CharacterAdded`: set `Humanoid.MaxHealth=100`, `BreakJointsOnDeath=false`, add `ForceField SpawnProtection` (Visible=false), `SetAttribute PlayerState=SpawnProtected`, after 3s if same character and alive → destroy ForceField and `Playing`. On `Humanoid.Died` → `Dead`. Damage gate rejects if attacker or target not `Playing`.

## Hitscan (CombatService.server.luau)

Client → `RequestFire:FireServer(weaponId, camera.CFrame.LookVector, sequence)`. Server:

1. Validate `type weaponId==string`, `finiteVector(dir)`, `dir.Magnitude>=0.001`, `WeaponConfig[weaponId]` exists.
2. Resolve `playerWeapon(player, weaponId)`: character exists, `PlayerState=="Playing"`, Tool exists, `(Tool:GetAttribute(WeaponId) or Tool.Name)==weaponId`, `Humanoid.Health>0`; origin = `Muzzle.WorldPosition` or `Handle.Position` or `HumanoidRootPart.Position`.
3. Rate-limit: `now=Workspace:GetServerTimeNow()`, check `reloadUntil[weaponId]`, `lastShot[weaponId]` with `1/fireRate`, `finite` checks, throttle `inputThrottleUntil` is client-only.
4. Sanity: `direction.Unit`, reject if `direction:Dot(root.CFrame.LookVector) < -0.25` (sideways shot).
5. Magazine: `ammo[player][weaponId] or magazineSize`, reject if `<=0`, then `ammo--`, `lastShot=now`.
6. Raycast: `RaycastParams Filter Exclude {character, Workspace.Projectiles, Workspace.Effects}, CollisionGroup=WeaponRay, RespectCanCollide=true`.
7. Hit: `Raycast(origin, direction*range)` → `endpoint` or max range, `applyHit` checks `targetFromInstance` (ancestor Model + Humanoid), `validDamage` (not self, not same Team, not ForceField, target `Playing`, `Health>0`) then `humanoid:TakeDamage(damage)`.
8. Broadcast: `ShotVisual:FireAllClients(player, weaponId, origin, endpoint, normal)` — cosmetic only.

Projectile path (`ArcLauncher`): same validation then `ProjectileService.spawn(player, weaponId, origin, direction, speed, gravityScale, lifetime, impactCallback)` and fire launch visual `shotVisual(origin,origin)`.

## Reload

Client → `RequestReload:FireServer(weaponId)`. Server validates weapon, `Playing`, Tool ownership, not already full, not reloading, then `reloadUntil=now+reloadSeconds`, `task.delay(reloadSeconds)` sets `ammo=magazineSize` if still same `finishes` token.

Clean up on `PlayerRemoving`: clear `lastShot/ammo/reloadUntil`.

## Projectiles (ProjectileService.luau)

`spawn(owner, weaponId, origin, dir, speed, gravityScale, lifetime, impact)` creates `RaycastParams Exclude {character, projectileFolder, Effects}, CollisionGroup=ProjectileRay`, clones `ServerStorage.Templates.ProjectileVisual` (Anchored/CanCollide/CanTouch/CanQuery false) to `Workspace.Projectiles`, pushes `{position=origin, velocity=dir.Unit*speed, gravityScale, expiresAt=now+lifetime, impact}`.

Each `Heartbeat`:
```
dt = min(deltaTime, 1/30)
gravity = (0, -Workspace.Gravity, 0)  -- default 196.2
v_next = v + gravity*gravityScale*dt
p_next = p + v_next*dt
hit = Raycast(p, p_next-p)
if hit then destroy visual, impact(hit), ImpactVisual:FireAllClients; elseif expired then destroy+impact(nil); else p=p_next; v=v_next; visual CFrame = lookAt(p_next, p_next+v)
```
Never use `Touched` for authority.

## Weapon tuning (WeaponConfig.luau)

- `EnergyRifle` hitscan: damage 24, range 650, fireRate 7.5, mag 30, reload 2.2s, spread 0.35°
- `ArcLauncher` projectile: damage 75, range 460, fireRate 1.15, mag 1, reload 2.6s, speed 150, gravityScale 1.0, lifetime 4.0 — test gravityScale 0.25/1.0/2.0 without changing `Workspace.Gravity`.

## Client visuals (WeaponClient.local.luau)

`ContextActionService` binds `AgentFire` (MouseButton1/ButtonR2) and `AgentReload` (R/ButtonX). Throttle `os.clock` 0.04s is UI only. Fire sends `(weaponId, camera.LookVector, sequence)`; reload sends `weaponId`. On `ShotVisual`/`ImpactVisual` → spawn `CosmeticTracer` (Neon 110,215,255, 0.06s) and `CosmeticImpact` (ball 0.25, Neon 255,230,120, 0.15s) under `Workspace.Effects` — never apply damage.

## Security checks to preserve

- Reject non-finite vectors and `range*speed` < 1e6.
- Normalize direction server-side; ignore client-provided origin/damage/range/ammo.
- Use `WeaponRay` vs `Decoration` and `BulletBlocker` primitives for cover — meshes are dressing unless explicitly tested.
- Segment-ray length is `|p_next-p|` — do not substitute single-frame `Touched`.
