---
name: roblox-asset-audit
description: Vetted Creator Store asset pipeline with scratch audit, sanitized templates, and blocker-paired placement.
---

# Roblox Asset Audit — Vetted Props Pipeline

Use when importing any Creator Store mesh/model into the arena prototype. Implements the only acceptable pipeline from `ROBLOX_AI_AGENT_DOSSIER.md §3`.

## Catalog truth (from AssetRegistry.luau)

Every entry is a **lead**, not an approval. Retain `id, url, creator, kind, observed, visual, risk, postInsert`.

| Key | ID | Creator | Kind | Role | Risk |
|---|---|---|---|---|---|
| LowPolyTree | 10355960847 | @Geremenek | MeshPart | Decoration | Low |
| LowPolyTreePack | 4870769649 | @FloydVeith | Model (10 MeshParts, 804tris) | Decoration | Medium |
| LowPolyRocks | 6562523344 | @GYPLA6 | MeshPart | Decoration | Low |
| WoodenBox02 | 430288318 | @The_Sink | MeshPart | HardCover | Low |
| LowPolyBarrel | 4204999283 | @Digitalscape | MeshPart | HardCover | Low |
| SciFiContainer | 13679876057 | @Jezza19870 | MeshPart | HardCover | Low |
| EnergyRifleVisual | 443695083 | @XenoSynthesis | MeshPart | WeaponVisual | Medium |
| TankBotVisual | 7198227425 | @fajnygosciu1234 | MeshPart | EnemyVisual | High |

Preview sheet: `artifacts/community_asset_contact_sheet.png`. Do not claim scale/collision/license from preview alone.

## The only acceptable pipeline

Search → inspect listing → permission check → insert into `Workspace.ScratchAssetAudit` → `tools/audit_asset.luau` → reject or sanitize → `ServerStorage.Templates.VettedProps` → clone into `VettedPropSlots`.

### Step-by-step

1. **Propose** one ID with preview, creator, URL, risk, role, and exact map placement. Wait for explicit approval — never bulk import.
2. **Insert** candidate *only* into `Workspace.ScratchAssetAudit` (single Model/MeshPart). Never insert directly into `Workspace.Map`, `StarterPack`, or live Tool.
3. **Execute** `tools/audit_asset.luau` (edit context). It reports `totals{parts,scripts,remotes,constraints}`, lists `code`, `remotes`, `constraints`, and per-part `anchored/canCollide/canTouch/canQuery/collisionGroup/size`.
4. **Decide:**

| Audit result | Action |
|---|---|
| Any Script/LocalScript/ModuleScript/RemoteEvent/RemoteFunction/Bindable | **Reject by default** — delete candidate, record rejection |
| Any unexpected Tool/HopperBin/force/BodyMover/Constraint | Reject unless owner explicitly requires it |
| MeshPart with sane scale, no behavior | Configure anchor/collision/query, preserve creator/ID/source, stage internal template |
| Model with no executable descendants | Keep only reviewed static MeshParts, simplify, do not rely on original hierarchy |
| Fails to insert / restricted / unclear rights | Do not workaround — use primitive arena, owned upload, or another candidate |

5. **Sanitize** approved art: anchor, set `CanQuery=false` for decoration or `CanQuery=true` + pair with invisible primitive `BulletBlocker` for hard cover, assign `CollisionGroup` (Decoration/Map), strip scripts/remotes, preserve `VettedAsset` tag.
6. **Template** sanitized copy to `ServerStorage.Templates.VettedProps` with attributes `SourceAssetId`, `SourceUrl`, `Creator`, `VettedDate`, `AuditReport`.
7. **Clone** template into the relevant `VettedPropSlot` in `Workspace.Map.GeneratedPrototype.VettedPropSlots` — never mutate the template in place.

## Hard-cover pairing rule

Stylized meshes have irregular hulls. For competitive hitscan, keep the mesh as visual and place an invisible primitive `Part` with `BulletBlocker` tag + `CollisionGroup=Map` + `CanQuery=true` for the actual ray hit. Test with `WeaponRay` vs `ProjectileRay`.

## Report fields for every asset attempt
`AssetId`, `URL`, `Creator`, `Kind`, `Audit JSON`, `Decision (reject/sanitize)`, `Local template path`, `Slot placement`, `Permission/rights status`.
