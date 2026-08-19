---
name: roblox-agent-handoff
description: Command-driven Roblox arena prototype workflow with server-authoritative combat and audited asset pipeline.
---

# Roblox Agent Handoff — Arena Prototype Workflow

Use this skill when building the `AgentArenaPrototype` multiplayer arena from `Roblox_AI_Agent_Handoff_Package/roblox_agent_handoff` via commands only.

## When to use
- User asks to build, bootstrap, or iterate the handoff prototype.
- Work touches `bootstrap_place.luau`, `build_prototype_arena.luau`, `audit_asset.luau`, `AssetRegistry.luau`, `WeaponConfig.luau`, `PlayerLifecycle`, `CombatService`, `ProjectileService`, or `WeaponClient`.
- Publishing, asset import, or Rojo workflow is requested.

## Non-negotiable rules (from AGENT_EXECUTION_PROMPT.md)

1. Keep all source under Rojo/Script Sync tree — never move authority into `ReplicatedStorage` or client.
2. Server is authoritative for state, spawn, spawn protection (3s), ammo, reload, cooldown, range, hit, projectile gravity, damage, score. `Players.RespawnTime = 6`.
3. Client may send only `(weaponId, aimDirection, sequence)` — never target/hit/damage/range/origin/ammo/cooldown/score.
4. No `require(assetId)`, `loadstring`, or blind `InsertService` runtime loading.
5. Unreviewed Store models go only to `Workspace.ScratchAssetAudit` → `audit_asset.luau` → reject if code/remotes/Tool/forces present.
6. Store IDs are leads; sanitized copy lives at `ServerStorage.Templates.VettedProps`, cloned into `VettedPropSlots`. Game must run with zero external art.
7. Primitive `BulletBlocker` parts own collision; meshes are dressing.
8. Never log cookies/keys. Publish only with explicit approval.

## Exact build order
1. Sync via Script Sync or `rojo build -o build.rbxlx` then open in Studio; live sync via `rojo serve` + plugin.
2. Execute `tools/bootstrap_place.luau` twice — verify no duplicates (folders, remotes `RequestFire/RequestReload/ShotVisual/ImpactVisual/GameStateChanged`, collision groups `Characters/Projectiles/Map/Decoration/Triggers/WeaponRay/ProjectileRay`, `ProjectileVisual` template).
3. Execute `tools/build_prototype_arena.luau` — primitive arena with 2 spawns (North/South), walls, 8 cover blockers, 3 asset slots.
4. Create local Tool `EnergyRifle` (`WeaponId="EnergyRifle"`, `Handle` + `Muzzle` Attachment) — no imported scripts.
5. Sync `PlayerLifecycle.server.luau`, `WeaponConfig.luau`, `ProjectileService.luau`, `CombatService.server.luau`, `WeaponClient.local.luau` to exact services.
6. Two-client playtest: spawn protection, wall block, damage, rate-limit, reload, projectile gravity.
7. Propose one `AssetRegistry` asset with ID/URL/creator/role/risk/placement — wait for approval.
8. On approval: scratch → audit → sanitized `VettedProps` → `VettedPropSlots` → retest rays.

## Source map (from ROBLOX_AI_AGENT_DOSSIER.md §5)
- `tools/bootstrap_place.luau` — idempotent folders/remotes/groups/template.
- `tools/build_prototype_arena.luau` — primitive map with tags `MapProp`, `BulletBlocker`, `SpawnPoint`.
- `tools/audit_asset.luau` — hierarchy report (scripts/remotes/constraints/parts), never auto-approves.
- `Shared/AssetRegistry.luau` — 8 verified IDs (MeshPart except LowPolyTreePack Model) with risk/postInsert rules.
- `Shared/WeaponConfig.luau` — `EnergyRifle` hitscan 24dmg/650range/7.5rps and `ArcLauncher` projectile 75dmg/1.15rps/150speed/g=1.0.
- `Combat/ProjectileService.luau` — Heartbeat `v+g*dt`, `p+v*dt`, segment raycast `p→p_next`, `CollisionGroup ProjectileRay`.
- `Combat/CombatService.server.luau` — validates state, `Tool[WeaponId]`, muzzle origin, `finiteVector`, dot>-0.25, cooldown, magazine, raycast `WeaponRay`.
- `PlayerLifecycle.server.luau` — `Lobby→SpawnProtected(3s)→Playing→Dead→Respawn 6s`, ForceField protection.
- `WeaponClient.local.luau` — input throttle 0.04s, cosmetic tracer/impact only.

## Acceptance tests to run and report (§8)
Idempotent setup, two-client spawn, wall/cover, fake-payload, fire-rate, reload, thin-wall projectile, low-gravity (0.25/1.0/2.0), asset audit, performance. Test with 50–150ms simulated latency.

## Report format after every stage
Changed files | Studio tree changes | Tests (action/result/pass) | Console | Security (authority touched) | Assets (ID/URL/creator/audit/template) | Risks/next stage — and stop before publish/Robux/permission changes.
