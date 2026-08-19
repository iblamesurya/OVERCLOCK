# Roblox Handoff Assets — Staged from Agent Handoff Package

Source: `C:\Users\tummala surya\Downloads\How to Create a Roblox Game Using Commands Only\Roblox_AI_Agent_Handoff_Package\roblox_agent_handoff`

This folder stages the **verified Creator Store candidates** and **command workflow tools** as local project assets. No external ID is runtime-loaded — each asset is a vetted local template per `roblox-asset-audit`.

## Staged Files (from handoff)

- `ReplicatedStorage/Shared/AssetRegistry.luau` — 8 verified IDs with risk/postInsert
- `ReplicatedStorage/Shared/WeaponConfig.luau` — EnergyRifle hitscan + ArcLauncher projectile
- `ServerScriptService/PlayerLifecycle.server.luau` — Lobby→Protected(3s)→Playing→Dead, Respawn 6s
- `ServerScriptService/Combat/CombatService.server.luau` — server-authoritative fire/reload
- `ServerScriptService/Combat/ProjectileService.luau` — Heartbeat segment-ray gravity simulation
- `StarterPlayerScripts/WeaponClient.local.luau` — input + cosmetic tracer/impact
- `tools/bootstrap_place.luau` — folders/remotes/groups/template (idempotent)
- `tools/build_prototype_arena.luau` — primitive arena (220×160 floor, 8 cover blockers, 3 slots, 2 spawns)
- `tools/audit_asset.luau` — scratch audit report
- `artifacts/community_asset_contact_sheet.png` — saved listing previews
- `artifacts/verified_assets_working.md` + `community_implementation_research.md` — evidence logs

## Verified Asset Catalog (snapshot)

See `verified_assets.json` for machine-readable registry. All 8 entries are **leads** requiring scratch audit before use.

| Key | ID | Risk | PostInsert Rule |
|---|---|---|---|
| LowPolyTree | 10355960847 | Low | Anchor, CanQuery=false unless blocking |
| LowPolyTreePack | 4870769649 | Medium | Audit all 10 MeshParts, strip code |
| LowPolyRocks | 6562523344 | Low | Anchor, CanQuery=false for dressing |
| WoodenBox02 | 430288318 | Low | Pair with BulletBlocker primitive |
| LowPolyBarrel | 4204999283 | Low | Soft cover, configure query |
| SciFiContainer | 13679876057 | Low | Anchor + BulletBlocker |
| EnergyRifleVisual | 443695083 | Medium | Tool-local mesh only |
| TankBotVisual | 7198227425 | High | Visual shell only, screen IP/rights |

## Usage

1. Do not copy these files directly into `Workspace` — follow `roblox-agent-handoff` skill build order.
2. Run `bootstrap_place.luau` → `build_prototype_arena.luau` → create Tool → sync scripts → playtest.
3. For any mesh, use `roblox-asset-audit` pipeline: ScratchAssetAudit → audit → VettedProps → VettedPropSlots.
4. Rojo: `rojo build -o build.rbxlx` or `rojo serve` + Studio plugin. Keep `default.project.json` source-controlled; do not commit cookies/keys.

## References

- Dossier §2–§3 for asset truth table and pipeline
- `artifacts/community_asset_contact_sheet.png` for visual range (nature/cover/weapon/bot)
