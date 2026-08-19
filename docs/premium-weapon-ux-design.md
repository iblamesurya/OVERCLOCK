# Premium Weapon UX — Design Review & Enhancement Proposal

**Status:** Read-only analysis (no code change)  
**Date:** 2026-08-14  
**Scope:** `PremiumWeaponCatalog`, `PremiumWeaponViewmodel`, `PremiumWeaponPresentation`, `PremiumWeaponSkinService`, `RemoteEvents :: WeaponSkinRequest`, `WeaponController` (tracer + recoil)  
**Constraint:** No game-balance change. Skins affect only presentation (`Color3`/`Material`/VFX tint). No damage, fire-rate, ammo, spread, mobility modifier.

---

## 1. Inventory & Current Behavior

### 1.1 `src/shared/Data/PremiumWeaponCatalog.luau`
- **Catalog size:** 4 `WeaponId`s (`AssaultRifle`, `Shotgun`, `SniperRifle`, `Pistol`), 5 `SkinSpec`s in fixed `SKIN_ORDER`.
- **SkinSpec schema:** `id`, `displayName`, `rarity: Epic|Legendary`, 4 `Color3`s (`primaryColor`, `secondaryColor`, `accentColor`, `opticColor`), 3 `Material`s (`primaryMaterial`, `secondaryMaterial`, `accentMaterial`). Correctly isolated from `WeaponStats`.
- **Ordering:** `WEAPON_ORDER` and `SKIN_ORDER` simple arrays; getters return `table.clone` (safe). `GetDefaultSkinId() == "ObsidianVector"` (free starter).
- **Compatibility:** `IsCompatible` = `IsWeaponId and IsSkinId` — universal compatibility (any skin on any weapon). Intentional for v1, allows future per-weapon restrictions without breaking callers.
- **Palette note:** 4/5 skins share `Metal + SmoothPlastic + Neon` for accent. Only `GlacierSignal` uses `DiamondPlate` for `secondaryMaterial`. Accent `Neon` dominates optic/muzzle visibility; warm brass not used here (reserved for muzzle flash).

### 1.2 `src/shared/Data/PremiumWeaponViewmodel.luau`
- Pure presentation builder. No damage/ammo/remotes. Each `Part` tagged via `SkinRole` attribute.
- **Builder helpers:** `configureViewmodelPart` (`Anchored`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false`). `cylinder` constructs barrel via X-axis rotation. `addRail`, `addStock`, `addHoloOptic`, `addAccentStripe`, `addFirePoint` (`FirePoint` attachment at `muzzle.Size.X * 0.5` on +X).
- **Geometry:** 4 bespoke models:
  - AssaultRifle: receiver, handguard, barrel 1.18, muzzle 0.18, optic housing + lens + mounts, stock, rail 1.35, accent stripes.
  - Shotgun: vent rib, pump, 2.05 barrel + tube magazine, iron sights using `Optic` role.
  - SniperRifle: 2.25 precision barrel + suppressor 0.46, scope body/tube + mounts, bipod legs.
  - Pistol: slide + serrations, trigger guard, micro optic.
  - Shared `Handle` primary part for `PivotTo`.
- **`ApplySkin(model, skinId): boolean`:** iterates `GetDescendants()`, switches on `SkinRole`:
  ```lua
  Primary           -> primaryColor + primaryMaterial
  Secondary | Grip  -> secondaryColor + secondaryMaterial
  Optic             -> opticColor + accentMaterial
  else (Accent/Muzzle) -> accentColor + accentMaterial
  ```
  Sets `AppliedSkin` + `SkinRarity` attributes. Returns `false` if unknown skin.
- **`Build(weaponId, skinId?): Model`:** asserts `IsWeaponId`/`IsSkinId`, defaults to `GetDefaultSkinId()`, tags `WeaponId`, `ViewmodelOnly=true`, assigns `PrimaryPart`, calls builder then `ApplySkin`.

### 1.3 `src/client/Controllers/PremiumWeaponPresentation.luau`
- Thin client adapter over Catalog + Viewmodel.
- `BuildViewmodel(weaponId, skinId?)` → `Viewmodel.Build`.
- `ApplySkin(model, weaponId, skinId)` guards `IsCompatible` before delegating; avoids client-side crash on bad data.
- `RequestSkin(remote, weaponId, skinId)` validates `typeof` + length 1..32, silently `return`s on bad input, then `remote:FireServer({weaponId, skinId})`.
- `BindSkinResults(remote, callback)` filters `kind=="WeaponSkinResult" and success==true and IsCompatible` before invoking `callback(weaponId, skinId)`. **Failures are swallowed** (`success~=true → return`). No pending/idempotency token.

### 1.4 `src/server/Services/PremiumWeaponSkinService.luau`
- **Construction:** `new(ownsSkin?, persist?)` with `fallbackOwnership` (only default skin) and optional `PersistSelection`. In-memory `_equipped: [userId] → { [weaponId]=skinId }`, `_lastRequestAt`.
- **`SetEquipped(player, weaponId, skinId): (boolean, string)`:** validates string+len 1..32 + `IsCompatible` → ownership → persist → store + `player:SetAttribute("EquippedSkin_"..weaponId, skinId)` (replicated to client). Error strings: `"Invalid weapon id"`, `"Invalid skin id"`, `"Unknown cosmetic"`, `"Skin is not owned"`, `"Could not save selection"`.
- **`GetEquipped`:** returns stored or `GetDefaultSkinId()`.
- **`Bind(remote)`:** asserts `RemoteEvent`, connects `OnServerEvent`. Cooldown `0.35s` per user via `os.clock()`. Silently drops throttled or non-table payloads. Replies `FireClient(player, {kind="WeaponSkinResult", success=ok, weaponId=..., skinId=if ok then result else "", reason=if ok then nil else result})`. `Destroy` clears maps and disconnects.
- **Wiring (`ServerMain.server.luau:322-335`):** `ownsSkin` hard-codes `skinId=="ObsidianVector"` pending `PlayerDataService` integration. Bound to `WeaponSkinRequest` via `RemoteEvents.GetReliable`.

### 1.5 `src/shared/Network/RemoteEvents.luau :: WeaponSkinRequest`
- Declared in `reliableNames` (correct: ownership change must not drop). Stored under `Network/Remotes/Reliable/WeaponSkinRequest` via `Initialize()`. No legacy shim needed (shim only mirrors `RequestFire`/`ShotVisual`).
- Client calls `GetReliable("WeaponSkinRequest")`; server binds same. Cache layer handles lazy `getOrCreateFolders`.

### 1.6 `src/client/Controllers/WeaponController.luau` — tracer + recoil
- **Pools (`initPools`):** `muzzleFlashPool` (Neon ball `0.14` + `PointLight` 1.2/4, warm brass `255,210,120` — not purple). `tracerPool` (Neon ball `0.28` head, Transparency 0.05) + global Beam template (`Width0=0.38 Width1=0.22 LightEmission 0.85 FaceCamera true`) + impact template (Neon ball 0.45 + `PointLight` 2.5/8 + `ParticleEmitter` sparkles, Emit 14).
- **Tracer pipeline (`RenderTracer(origin, target)`):** pools head, creates 2 `Attachment`s on `Workspace.Terrain`, clones `Beam`, animates head via `TweenService` at `speed=1100 studs/s` (`travelTime = dist/1100`), beam fades via `Transparency` tween. Impact burst clones `ImpactTemplate`, grows transparency over 6 frames, emits particles, returns head to pool. Early-returns if `dist<1`.
- **Muzzle origin:** `getMuzzleOrigin(camCFrame)` prefers `FirePoint` attachment world pos; fallback to `MUZZLE_OFFSETS` per weapon.
- **Fire path (`FireShot`):** `BallisticPhysics.FireProjectile` with sampled `rayDirection` from `CrosshairController.GetSpreadDirection`, `onHit` shows crosshair hitmarker + `ReliableCombat:ReportHit`, then `AnimationController.AddRecoil(Vector3.new(baseRecoil.X*0.85, yaw±0.35*Y, baseRecoil.Z*0.85))` + `RenderMuzzleFlash(CFrame.lookAt(muzzleOrigin, target))` + `RenderTracer(muzzleOrigin, target)`. `target` is always `aimOrigin + rayDir * maxRange` (not hit pos) — tracer flies to max range, not impact point, unless terrain hit via `RenderExternalTracer`.
- **Recoil presentation:** `AnimationController` spring (`recoilSpring` 0.2/90/12) drives `camera CFrame` delta + `viewmodel kick Z*0.5`, sway/bob dampened in ADS (`adsAlpha*0.7`). Spread recovery via `ExpDecayLerpNumber` at `spreadRecoveryRate` (60 Hz fixed accumulator).

---

## 2. UX Gap Analysis

### 2.1 Skin Selection (pre-equip & catalog)

| Finding | Severity | Detail |
|---|---|---|
| No ownership signal in catalog | High | `PremiumWeaponCatalog` has no `cost`, `currency`, `owned` API. Ownership lives only in `PremiumWeaponSkinService._ownsSkin` (server) and is never surfaced to skin picker. Picker cannot distinguish owned vs locked vs affordable. |
| No metadata for picker | Medium | Missing `iconId`, `description/flavorText`, `releaseTag`, `sortWeight`. `displayName` alone insufficient for merchandising. `rarity` only 2 values with no color mapping exposed (`Epic`/`Legendary` → expected accent but hard-coded per `ShopUIController`). |
| Global compatibility hides per-weapon preview | Low | `IsCompatible` true for all combos is correct for v1 but picker cannot preview weapon-specific differences (e.g., sniper scope lens tint vs shotgun iron sight). Palette applied uniformly without per-weapon role weights. |
| `SKIN_ORDER` static | Low | Order is authoring order, not merchandising order. No `featured` or `new` flag, so UI cannot pin Legendary first without reordering code. |
| Duplicate source of truth | High | `WeaponStats.SKINS_DATA` (12 skins, `Color3+Material` pair) coexists with `PremiumWeaponCatalog` (5 skins, 4-color+3-material). `ShopUIController` reads `WeaponStats`, while premium flow reads `PremiumWeaponCatalog`. Skins diverge → picker shows skins the viewmodel cannot render. |
| No equip state persistence story | High | `ServerMain` fallback `_ownsSkin` allows only `ObsidianVector`; `ProfileServiceWrapper.GetDefaultProfile` stores `EquippedSkins["AssaultRifle"]="DefaultSkin_AR"` (different id space). No mapping layer, so rejoin resets to default for every real premium skin. |

### 2.2 Viewmodel Presentation

| Finding | Severity | Detail |
|---|---|---|
| Optic lens uses `Neon` | Medium | `ApplySkin` maps `Optic → opticColor + accentMaterial(Neon)`. Lens should be `SmoothPlastic` or `Glass` with `Transparency`, not emissive Neon — bloom competes with tracer/impact glow and hurts sight-picture at 0.5m. |
| Grip collapsed into Secondary | Medium | `Grip → secondaryColor + secondaryMaterial` loses ergonomic differentiation (e.g., GlacierSignal grip same as secondary DiamondPlate). Intentional material contrast (fabric/rubber) would read better in first-person. |
| Accent+Muzzle aliasing | Low | `else` branch treats `Muzzle` as `accentColor+Neon`, coupling muzzle brake glow to accent. Worthwhile to keep but sniper suppressor should not glow as bright as striker accent. |
| All Neons share same `accentColor` | Low | No bloom intensity variation per rarity. Legendary skins ("AuroraCircuit", "GildedProtocol") could have subtler emissive pulse vs Epic's static Neon. |
| No preview affordance | Medium | `Build` constructs full model with `ViewmodelOnly=true` but no thumbnail/viewport helper, rotation, or ADS preview. `ShopUIController.create3DPreview` builds its own dummy `Part` instead of reusing `PremiumWeaponViewmodel.Build` — preview and equip diverge. |
| Silent build contract | High | `Viewmodel.Build` asserts on bad `weaponId`/`skinId`; `PremiumWeaponPresentation.BuildViewmodel` passes `weaponId :: any` without validating `skinId` fallback `nil → default`. `WeaponController.build3DWeaponModel` reads `player:GetAttribute("EquippedSkin_"..weaponId)` which may hold `"DefaultSkin_AR"` from profile (not in premium catalog) → assert fires and equip breaks. |
| No transition animation | Low | `ApplySkin` snaps `Color`/`Material` instantly. Legendary equip deserves a 150-250ms dissolve/emissive flash rather than pop. |
| Third-person ghost | Info | `ViewmodelOnly=true` is correct (no replication). Other clients never see premium skin on world model — intentional, but high-value buyers expect others to see it. Backlog decision needed. |

### 2.3 Ownership Feedback (request → result loop)

| Finding | Severity | Detail |
|---|---|---|
| Failures invisible | High | `PremiumWeaponSkinService:Bind` emits `reason` on `success==false`, but `PremiumWeaponPresentation.BindSkinResults` early-returns on `payload.success ~= true`, so the client never learns *why* (`"Skin is not owned"`, `"Unknown cosmetic"`, rate-limited silence). UI cannot toast error. |
| Rate-limit silent | Medium | 0.35s cooldown silently drops requests (`return` before `SetEquipped`). User double-clicks equip → second click dropped with no debounce feedback, feels broken. |
| Request validation silent | Medium | `RequestSkin` silently returns on bad `typeof`/len. Good anti-spam but no dev warning. Wrapper should warn in `RunService:IsStudio()` / return bool. |
| No pending/optimistic state | High | No `pendingWeaponId→skinId` ledger. Rapid weapon switch + skin request can apply to wrong model (`WeaponController.ApplySkin` uses `currentWeaponState.weaponId` at result time, which may have changed since request). |
| Attribute race on rejoin | Medium | `SetAttribute("EquippedSkin_"..weaponId)` replicates eventually, but `WeaponController.build3DWeaponModel` reads at `attachWeaponToCharacter` time (task.spawn). If attribute hasn't replicated yet, starter skin shown until next swap. No `GetAttributeChangedSignal`. |
| No persistence error surfacing | Low | `persist` hook returns false → `"Could not save selection"` reason emitted but dropped client-side. Player thinks equip succeeded after rejoin because UI updated optimistically (if it had). |
| PlayerRemoving not cleaning throttle | Low | `_lastRequestAt[player.UserId]` persists after disconnect until `Destroy()`. Not bounded; low leak. |
| `IsBuy` vs `IsEquip` ambiguous | Medium | `ShopUIController` button toggles between `"PURCHASE / EQUIP"` and `"EQUIPPED"` with only local state; no marketplace/ownership check, so premium skins appear purchasable without owning. |

### 2.4 Tracer & Hit Clarity

| Finding | Severity | Detail |
|---|---|---|
| Tracer decoupled from hit position | High | Local `FireShot` tints `targetHitPos = aimOrigin + rayDir*maxRange` and draws tracer to maxRange even when `BallisticPhysics` hits earlier. Actual hit is async via Ballistic CCD; tracer/impact appear disconnected (ghost tracer past wall). `RenderExternalTracer` correctly uses raycast, but `FireShot` path doesn't. |
| Beam attachments parented to `Workspace.Terrain` | Medium | Leaks attachments on `Terrain` if tween cancelled / player dies mid-flight. Better: parent to ephemeral folder `Workspace.Effects` or head part. Also uses global `_G` to stash templates — breaks encapsulation and testability. |
| Fixed warm tracer for all skins | Medium | Tracer is always `255,240,180` head + `255,238,140` beam + impact `255,230,90`, regardless of skin accent. Premium expectation is subtle tint (e.g., CrimsonRelay rose tail) without signaling rarity to avoid pay-to-notice. Currently misses a premium moment; fix must keep hit visibility ≥ neutral (no advantage). |
| Muzzle flash not skin-aware | Low | `RenderMuzzleFlash` always brass. Same tradeoff as tracer: skin-tinted flash delights but must stay readable. Current neutral is correct for balance; optional subtle `accentColor:lerp(brass, accent, 0.15)` is safe range. |
| Recoil visual distinct but untelegraphed | Info | Recoil impulse correctly reduced in ADS (`*0.85` + yaw) and spread increase `+spreadIncreasePerShot` tied to `CrosshairController`. No viewmodel-unique recoil animation per weapon weight — works but sniper vs pistol feel identical beyond scalar. |
| Impact readability mix | Medium | Impact burst uses same Neon+particle palette as tracer head on all surfaces. No surface-tier differentiation (flesh vs metal vs terrain) and no headshot-specific flourish. Hitmarker (`white vs red`) carries the distinction, but world impact is generic. |
| Beam width not distance-scaled | Low | `Width0 0.38` at 5m is huge; at 800m thin. Constant width hurts near-muzzle reads. Lerp width by distance clamped keeps close clarity. |
| No reduced-visual-motion path | Medium | Tracer beam + impact glow + particles is flash-heavy. No `ReducedMotion` or photosensitivity guard (e.g., debounce on autofire streak). |
| `RenderTracer` no pooling for beams | Low | Head pooled, but `Attachment` + `Beam` are `Instance.new` per shot (GC pressure on 600 RPM auto: ~10/sec). Should pool attachments or parent to head. |

---

## 3. Design Goals & Guardrails

**Do:**
- Surface ownership clearly, keep optimistic feel under 100ms, authoritative correction under 300ms.
- Make premium viewmodel preview identical to equipped render (single source of truth).
- Add hit clarity that helps learning (impact confirms registration) without revealing hidden-info or changing time-to-kill.
- Tint cosmetics subtly; never encode performance tier in VFX brightness/width that would give advantage.
- Keep `PremiumWeaponCatalog` authoritative; eliminate divergence with `WeaponStats.SKINS_DATA`.

**Don't:**
- Put damage/FireRate/spread inside `SkinSpec`.
- Auto-create remotes or change `RemoteEvents.Initialize` contract.
- Replicate target/damage from client.
- Use `require(assetId)` or blind asset load.

---

## 4. Proposed UX Improvements (no balance change)

### 4.1 Skin Selection — Catalog & Picker

**A. Unify source of truth (P0).**
- Decision: `PremiumWeaponCatalog` is the canonical skin DB. Deprecate `WeaponStats.SKINS_DATA` for presentation (keep `WeaponStats` only for ballistics). Add adapter `PremiumWeaponCatalog.ToLegacySkinSpec?` if `ShopUIController` still needs legacy shape short-term, then migrate picker to read `GetSkinOrder()` + `GetSkin()` directly.
- Migration: map `WeaponStats.Spec.materal: single Material → secondaryMaterial` conversion note: default `primaryMaterial=Metal`, preserve old single material for secondary.

**B. Enrich `SkinSpec` non-balance metadata (P0 — purely presentational).**
```lua
export type SkinSpec = {
  id: string,
  displayName: string,
  description: string,         -- new: 6-12 word flavor
  rarity: "Epic" | "Legendary",
  tierColor: Color3,           -- new: rarity chip (Epic #7A5CFF, Legendary #FFB82E)
  thumbnailId: string?,        -- new: rbxassetid for inventory row (optional)
  sortWeight: number,          -- new: Legendary 100, Epic 80; featured +20
  releaseTag: "Starter"|"Season1"|"Event"?,
  primaryColor: Color3,
  secondaryColor: Color3,
  accentColor: Color3,
  opticColor: Color3,
  primaryMaterial: Enum.Material,
  secondaryMaterial: Enum.Material,
  accentMaterial: Enum.Material,
  previewOrbit: number?,       -- new: ViewportFrame yaw speed multiplier
}
```
- Add helper `GetSkinsByRarity(rarity)` and `GetFeaturedOrder()` (sort by `sortWeight` desc then `SKIN_ORDER` stable) without changing serialization. Cost/ownership intentionally *not* in catalog — lives in entitlements.

**C. Picker IA (P0 — `ShopUIController` + new `SkinPickerController`).**
- Layout: left weapon tabs (`GetWeaponOrder()` order), center grid (4-5 skins), right preview. Weapon tabs reuse `WeaponStats.Get(displayName)` for friendly name + icon.
- Card states (4): **Locked** (dim 0.55 + lock glyph + price), **Owned** (`Equip`), **Equipped** (gold stroke + check), **Pending** (spinner). Drive from async `OwnedSet = fetchOwnedAsync()` (see 4.3).
- Grid item: rarity chip (`tierColor`), thumbnail/Viewport, name, short description on hover. Legendary card gets subtle `UIGradient` shimmer on hover only (not persistent, no motion default).
- Picker subscribes to `WeaponSkinRequest` result (see 4.3) rather than local optimistic only.

**D. Correct preview (P0).**
- Replace `create3DPreview(dummyPart)` with `PremiumWeaponViewmodel.Build(weaponId, skinId)` inside `ViewportFrame`. Use actual `ViewmodelOnly` model, clone without parenting to Camera. Reuse `ApplySkin` for live swatch changes (no rebuild). Orbit speed from `SkinSpec.previewOrbit`.
- Viewport camera: sniper zoomed slightly out to show scope; pistol closer. Cache per `weaponId+skinId` Viewport model to avoid rebuild on tab switch.
- Add ADS toggle button in preview (lerps `adsAlpha` locally): shows scope lens tint.

**E. Catalog hygiene.**
- Expose `GetRarityColor(rarity)` utility to avoid scatter. Add `IsSkinOwned` *client helper* that consults local `OwnedSet` (not Catalog) — keep Catalog pure.
- Add validation alias: treat legacy `DefaultSkin_AR` mapping → `ObsidianVector` via `CanonicalizeSkinId(raw)` so old profile data doesn't hit assert.

### 4.2 Viewmodel Presentation

**A. Role/material pass (P1).**
- Keep tag set `{Primary, Secondary, Accent, Optic, Muzzle, Grip}` but refine mapping:
  ```lua
  Primary   -> primaryColor + primaryMaterial
  Secondary -> secondaryColor + secondaryMaterial
  Grip      -> gripColor = secondaryColor:Lerp(primaryColor, 0.12), material = Rubber|Fabric (introduce per-skin gripMaterial? keep secondary for v1, tune Grip brightness -10%)
  Accent    -> accentColor + accentMaterial (Neon)
  Muzzle    -> muzzleColor = accentColor, material = Neon but Brightness 0.6×Accent
  Optic     -> opticColor + Glass (not Neon), Transparency 0.12, Reflectance 0.18
  ```
  Practically: change `ApplySkin` Optic branch to `Material.Glass` + `Transparency` set. Add helper `setLensTransparency(part, 0.12)` — only presentation.
- Add `SkinRole` opacities in `configureViewmodelPart`: optic lens initial `Transparency` stored and restored on `ApplySkin`.

**B. Equip animation (P1 — purely cosmetic).**
- On `ApplySkin` success: 180ms `TweenService` pulse: emissive parts `Neon.Brightness` proxy via `Color:Lerp(white,1.08)` and `Accent` parts scale `0.02` outward then back. Skip during rapid swaps (`if now - lastApply < 0.25 then instant`).
- ADS preview hides viewmodel at `adsAlpha>0.8` currently — keep but fade via `GroupTransparency` instead of teleport to y=-100 so transition doesn't pop.

**C. Robust build contract (P0).**
- Change `Viewmodel.Build` fallback: `selectedSkin = Catalog.IsSkinId(skinId) and skinId or Catalog.GetDefaultSkinId()` with `warnOnce` instead of assert on skin. Keep assert on `weaponId`.
- Add `TryBuild(weaponId, skinId): (Model?, string?)` safe API for picker thumbnails.
- `PremiumWeaponPresentation.BuildViewmodel` should `pcall` internally and return `nil` on bad weaponId, letting caller show placeholder instead of crashing equip.

**D. World-visibility backlog decision (P2 — explicit non-action for now).**
- Document that `ViewmodelOnly=true` remains. If PM later wants world-visible skins, add separate `WorldWeaponCosmetics` clone parented to character `Tool` handle, replicated via `ReplicatedStorage.CosmeticManifest` — not in this UX pass.

### 4.3 Ownership Feedback (request → result loop)

**A. Dual-channel result (P0).**
- Server already emits `{success, reason}`. Expose it: change `PremiumWeaponPresentation.BindSkinResults` signature to
  ```lua
  BindSkinResults(remote, onSuccess: (wId,sId)->(), onError: (wId,sId,reason)->()?)
  ```
  or single callback `(wId, sId, success, reason)`. Keep backward compat: if `onError` nil, still swallow as before but log studio warning.
- `PremiumWeaponSkinService` cooldown should emit `success=false, reason="RateLimited"` instead of silent drop so client can debounce visibly. Minimal diff: replace early `return` on cooldown with `FireClient(... success=false reason="RateLimited")`.

**B. Request UX state machine (P0 — new `SkinOwnershipController`).**
```
Idle → Requesting (spinner on card, tabs disabled) →
  Success: Equipped (check, toast "Equipped {displayName} for {WeaponName}"), update player:GetAttribute
  Owned-failure: toast "You don't own {displayName}" + CTA "View in Shop"
  Unknown-cosmetic: toast "Unknown cosmetic"
  RateLimited: toast "Please wait…" + 0.35s disable
  Persist-failure: toast "Couldn't save — retrying" (retry once)
```
- Optimistic local stroke moves instantly; rollback on `success==false`.
- Store `pendingByWeapon: { [weaponId] = {skinId, sentAt} }` to disambiguate weapon switches between request and response. On result, only apply if `pending[weaponId]==skinId`.

**C. Attribute-driven sync (P0).**
- `WeaponController` listens to `LocalPlayer:GetAttributeChangedSignal("EquippedSkin_"..weaponId)` and re-applies skin if model still shows old `AppliedSkin`. Catches initial replication race and external changes (admin grants).
- On rejoin: profile load should hydrate `player:SetAttribute("EquippedSkin_"..weaponId, resolvedCanonicalId)` before `MatchPhaseTransition=Combat` so first `attachWeaponToCharacter` sees correct attribute. `ServerMain` to call `PremiumWeaponSkinService:HydrateFromProfile(player, profile.EquippedSkins)`.

**D. Service hygiene (P1).**
- Add `PlayerRemoving:Connect` cleanup for `_lastRequestAt`.
- Add server accessor `GetOwnershipSnapshot(player): { [skinId]=true }` for a future `RequestInventory` RemoteFunction (not required for this pass; picker can start with fallback `Owned={ObsidianVector}` then enhance).
- Ensure `PlayerDataService` resolver is wired: replace `ServerMain` hard-coded `ownsSkin` with `profile.OwnedCosmetics` set lookup (canonicalized).

**E. Copy & affordance.**
- Button text tiers: `Locked → "UNLOCK"`, `Owned+notEquipped → "EQUIP"`, `Equipped → "EQUIPPED ✓"` (no purchase in premium picker; shop handles purchase separately). Keep premium picker commerce-free to avoid duplicating `ShopUIController`.
- Toast uses `HUDController:ShowToast(kind)` if available else lightweight `TextLabel` fade. Success sound `Accent` chime at 0.4 vol; failure thud lower.

### 4.4 Tracer & Hit Clarity (no balance change)

**Principle:** tracers/impacts are cosmetic learning aids. Must remain within 10% luminance variance of neutral and not encode damage tier or rarity intensity that would reveal hidden power.

**A. Hit-coupled tracer (P0 — correctness).**
- Change `FireShot` to tracer-couple to CCD result:
  1. Keep immediate `RenderMuzzleFlash` (cheap, frame-0).
  2. Defer `RenderTracer` until Ballistic `onHit` fires OR short timeout (`maxRange / velocityMod`). On `onHit(hitResult)`, call `RenderTracer(muzzleOrigin, hitResult.Position)` + `ShowImpact(hitResult, isHeadshot)` (see C). On `onExpire`, tracer to predicted `aimOrigin + dir*maxRange`.
  3. Fallback if Ballistic callback never fires (defense): `task.delay(0.08, if not traced then RenderTracer(muzzleOrigin, predicted))`.
- This fixes ghost-past-wall tracers. Already correct in `RenderExternalTracer` (used for other clients' shots) — unify.

**B. Skin-tinted but neutral-safe tracer (P1 — delighted but balanced).**
- New helper `getTracerTint(skinId): Color3`:
  ```lua
  local skin = Catalog.GetSkin(skinId)
  local accent = skin and skin.accentColor or neutral
  return neutral:Lerp(accent, 0.14) -- 14% blend, luminance preserved
  ```
  Apply to: `tracerHead.Color = tint`, `beam.Color = ColorSequence.new(tint)`, `beam.Width` unchanged, `muzzle flash PointLight.Color = tint:Lerp(brass, 0.5)`. Keep `LightEmission 0.85` neutral.
- Clamp tint luminance: convert to HSV, clamp V to [0.82, 0.96] so Legendary gold doesn't wash vs Epic cyan. Verify contrast against NeonSubway dark corridors (screenshot test).
- Setting: `ReducedMotion` disables tint pulse; `PhotosensitivitySafe` option collapses beam width -15% and halves particle emit.

**C. Surface & headshot impact tiers (P1).**
- Extend `onHit` to pass `hitResult.Material` + `isHeadshot` (already computed via `hitInstance.Name=="Head"`). Choose impact variant:
  - **Flesh headshot:** impact ball `0.52` + `PointLight Brightness 3.0 Range 10` (90ms) + sparkle `Emit 18`, hitmarker red pulse.
  - **Flesh body:** ball `0.45` + `2.5/8` + `Emit 14`.
  - **Hard surface (Metal/Concrete):** Neon ring decal (optional) + smaller ball `0.38` + particle burst `Emit 9` + sound thud (if available). Keeps learning: flesh hit glows bigger.
- Duration: flesh 140ms fade, hard 110ms. No damage number changes.
- Keep impact pooling: reuse `ImpactTemplate` clones; avoid per-shot `Instance.new(Attachment)` storm by pooling attachments or parenting beam attachments to head/part rather than `Workspace.Terrain`.

**D. Recoil/hitmarker polish for clarity (P1, still not balance).**
- Add `hitstop` micro-freeze: `task.delay(0, camera jerk scale 1.03 for 18ms on headshot only)` — presentation-only, no fire-rate change.
- Recoil already spring-based; add subtle `camera roll = yaw * 0.08` on tracer start to telegraph shot without moving crosshair logic. No spread/recoil scalar changes.
- Crosshair hitmarker currently 150ms; bump headshot to 190ms and body 150ms, thickness +1px on headshot. Already color-distinct (`white vs red`) — keep.

**E. Pool & parenting hygiene (P1 — perf).**
- Move pooled containers to `Workspace:FindFirstChild("Effects") or Instance.new(Folder, Workspace)` with name `Effects`. Parent `TracerHead`, `ImpactBurst`, `Beam` attachments there, not `Terrain`.
- Replace `_G.__TracerBeamTemplate` with module-local upvalue `tracerBeamTemplate` / `impactTemplate`. If `WeaponController` must share with tests, expose via `WeaponController._TestTemplates` table, not globals.
- Pool attachments: preallocate 32 `Attachment`s; beam `Attachment0/1` borrowed from pool instead of `Instance.new`.

**F. Accessibility & perf guards (P2).**
- Autostreak suppression: if fire interval < 90ms and `shotSequenceId % 6 ~= 0`, skip impact particles beyond `Emit 6` to reduce seizure risk on full-auto spray.
- Beam `Width0/Width1` distance-scaled: `scale = clamp(dist/300, 0.7, 1.0)` so pistol 12m beam not comically thick.
- Budget: ≤ 40 live tracer heads, ≤ 20 impacts, ≤ 700 instances total; `Debris` unused (pool handles). Validate `RunService:RenderStepped` dt min 0.1 clamp already correct.

---

## 5. API / Contract Changes (minimal, additive)

### `PremiumWeaponCatalog` (additive, no break)
```lua
function GetRarityColor(rarity): Color3
function GetSkinsByRarity(rarity): { string }
function GetFeaturedOrder(): { string }          -- sortWeight
function CanonicalizeSkinId(raw: string): string -- maps legacy DefaultSkin_AR→ObsidianVector
-- enriched SkinSpec fields: description, tierColor, thumbnailId?, sortWeight, releaseTag?, previewOrbit?
```

### `PremiumWeaponViewmodel` (additive)
```lua
function TryBuild(weaponId, skinId?): (Model?, string?) -- pcall wrapper, returns err
-- ApplySkin: Optic→Glass+Transparency, Grip brightness, Muzzle dim factor; adds Tween pulse (opt-in bool)
```

### `PremiumWeaponPresentation` (breaking only if caller ignored second arg — safe)
```lua
BindSkinResults(
  remote: RemoteEvent,
  onSuccess: (weaponId, skinId) -> (),
  onError: ((weaponId, skinId, reason: string) -> ())? -- new optional
)
RequestSkin(...): boolean -- return bool in Studio mode (was void)
```

### `PremiumWeaponSkinService` (additive, behavior tidy)
```lua
function HydrateFromProfile(player, equippedSkins: {[string]:string}) -- sets attributes from profile at join
-- Bind cooldown: emits RateLimited reason instead of silent drop
-- PlayerRemoving cleanup
```

### `RemoteEvents` (no change)
- Keep `WeaponSkinRequest` reliable. No new remote required for v1. Future optional `InventorySnapshot` RemoteFunction can be added via `RemoteEvents.GetRemoteFunction("InventorySync")` without touching existing flow.

### `WeaponController` (internal, no external break)
- `RenderTracer` now internal hit-coupled; external entry `RenderExternalTracer` unchanged. Expose `GetCurrentSkin()` already exists — picker reads `CurrentSkin` for active card highlight.

---

## 6. UX Flow Specs

### 6.1 Equip Flow (happy path)
1. Picker opens → tabs `AssaultRifle` selected → grid shows 5 skins in `GetFeaturedOrder()`, with owned set (initial `ObsidianVector` only) → `ObsidianVector` card `EQUIPPED ✓`.
2. User clicks `AuroraCircuit` (locked) → toast `You don't own Aurora Circuit — View in Shop` (shop button).
3. Grants ownership (marketplace or admin) → ownership snapshot refreshes → card state flips `Locked→Owned Equip`.
4. Click `Equip` → `RequestSkin` fires, card enters `Pending` (spinner), tabs disabled.
5. Server `SetEquipped` validates → `FireClient success` → `onSuccess` clears pending, moves gold stroke to new card, picker toasts success, `WeaponController.ApplySkin` tween-pulses viewmodel (if weapon active) else `EquippedSkin_` attribute queued for next equip.
6. Other clients unaffacted (viewmodelOnly). Player rejoins → `HydrateFromProfile` restores `EquippedSkin_`.

### 6.2 Failure Flows
- **Not owned:** card shake 80ms + toast + error chime.
- **RateLimited:** spinner stays, toast `Please wait` and button disabled until 350ms.
- **Unknown cosmetic / legacy id:** `CanonicalizeSkinId` maps before request; if still unknown, `onError` toast `Unknown cosmetic` (dev warn in Studio).
- **Persist failure:** retry once after 400ms; on second failure toast `Couldn't save — will retry next join` (no blocking).

### 6.3 Tracer/Hit Perception Flow
- Single shot: click → muzzle flash (frame 0) → tracer head leaves muzzle, beam stretches → at CCD hit (~2 frames at 60Hz) → impact burst + light flash + particles at exact hit pos → crosshair hitmarker 150/190ms.
- Wall blocked: tracer stops at wall impact (not through), small hard-surface impact.
- Full-auto spray: every 6th shot impacts full particles, intermediates reduced, beam stays crisp. No epilepsy trigger: luminance constant.

---

## 7. Visual & Motion Guidance

- **Rarity chips:** Epic `Color3.fromRGB(122,92,255)` pill 12px; Legendary gold `fromRGB(255,184,46)` pill with subtle shimmer on hover only.
- **Card strokes:** `Epic` stroke 1.5px `Border`, `Legendary` 2px `AccentDark` with outer glow 6px `Color3:lerp(accent, white, 0.4)` at 0.6 transparency.
- **Toast:** 280×44 `PanelSoft` with accent left bar 4px; success `Success` dot, error `Danger`. Auto-dismiss 2.2s.
- **Tracer tint blend:** `lerp(neutral, accent, 0.14)` preserves readability; sRGB luminance within 4% of neutral (verified via Rec.709 luma).
- **No new font/kit:** reuse `UITheme` (`GothamBold`, `CornerRadius 6`, brass accent). Avoid rounding everything `rounded-2xl` — follow `UITheme` existing `4/6/12` mix.

---

## 8. Performance & Safety Budget

- Tracer pool 24 → bump to 32 for 600 RPM streak (worst 10 shots/s × 0.9s hang = 9 live). Beam attachments 32 pooled.
- Impact pool not pooled yet — add `impactPool: ObjectPool` size 16 to avoid `Instance.new` per hit.
- Viewmodel clone per weapon+skin — cache 20 entries, evict LRU. Each model ~45-60 parts → clone 0.3ms budget.
- No `Workspace.Gravity` mutation. Tracer speed 1100 unchanged (no balance effect).
- All VFX under `Workspace.Effects` folder for bulk cull if perf degrades.

---

## 9. Implementation Phases

**Phase 0 — Consolidate (0.5d)**
- Add `CanonicalizeSkinId`, enrich `SkinSpec`, add `GetRarityColor`/`GetFeaturedOrder`. Deprecate `WeaponStats.SKINS_DATA` read in `ShopUIController` (adapter).
- Fix `Viewmodel.Build` skin fallback (warn, not assert) + `TryBuild`.

**Phase 1 — Ownership feedback (0.5d)**
- `PremiumWeaponSkinService` cooldown reason + PlayerRemoving cleanup + `HydrateFromProfile`.
- `PremiumWeaponPresentation.BindSkinResults` dual callback; wire `onError` to `SkinOwnershipController` toast + pending ledger.
- `WeaponController` `GetAttributeChangedSignal` listener.

**Phase 2 — Viewmodel & picker (1d)**
- `ShopUIController` refactor to `PremiumWeaponViewmodel.Build` viewports.
- Optic Glass fix + Grip/Muzzle tuning + equip tween.
- New picker controller + toast.

**Phase 3 — Tracer hit-coupling & tint (0.5d)**
- Hit-coupled tracer, beam pooling under `Effects`, skin tint 14% lerp, luminance clamp, distance-scaled width, impact tiers.

**Phase 4 — Polish & perf (0.25d)**
- ReducedMotion toggle, autostreak suppression, attachment pooling, VRAM check on 4K Beam.

---

## 10. Validation Checklist (read-only → implement then verify)

- [ ] `table.clone` getters still isolated after adding new SkinSpec fields.
- [ ] No `PremiumWeaponCatalog` entry contains gameplay numbers.
- [ ] `WeaponController.BuildViewmodel` with legacy `"DefaultSkin_AR"` correctly canonicalizes to default without assert.
- [ ] Picker `Build` uses same model as equip (pixel diff < 2%).
- [ ] `WeaponSkinRequest` failure reasons surfaced for each error string; rate-limit toast appears on double-click.
- [ ] Weapon switch mid-request applies skin to correct weapon only.
- [ ] Rejoin restores equipped skin before `Combat` equip.
- [ ] Tracer stops at wall (ray length = segment ray, not maxRange) on 50ms latency sim.
- [ ] Tracer tint luminance within 4% of neutral; headshot impact 1.2× body brightness but same hue family — not advantage.
- [ ] 600 RPM autofire 10s does not leak `Beam`/`Attachment` instances (pool in-use count ≤ 32).
- [ ] ReducedMotion halves particles and no Epilepsy flash > 3Hz.

---

## 11. Out of Scope / Explicit Non-Goals

- Changing damage, spread, recoil magnitude, magazine, or mobility per skin.
- Adding a new Reliable/Unreliable remote — reuse `WeaponSkinRequest`.
- Replicating premium skins to world/third-person — requires separate manifest, listed as backlog.
- Monetization or `MarketplaceService` purchase flow — picker delegates to existing shop.

---

## 12. Files Referenced

- [PremiumWeaponCatalog.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/shared/Data/PremiumWeaponCatalog.luau)
- [PremiumWeaponViewmodel.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/shared/Data/PremiumWeaponViewmodel.luau)
- [PremiumWeaponPresentation.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/client/Controllers/PremiumWeaponPresentation.luau)
- [PremiumWeaponSkinService.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/server/Services/PremiumWeaponSkinService.luau)
- [RemoteEvents.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/shared/Network/RemoteEvents.luau) (`WeaponSkinRequest`)
- [WeaponController.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/client/Controllers/WeaponController.luau) (`tracer+recoil`)
- [WeaponStats.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/shared/Data/WeaponStats.luau) (divergent legacy skins)
- [ShopUIController.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/client/UI/ShopUIController.luau) (current picker dummy preview)
- [CrosshairController.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/client/Controllers/CrosshairController.luau) and [AnimationController.luau](/mnt/c/Users/tummala surya/Downloads/roblox/src/client/Controllers/AnimationController.luau) (recoil/spread presentation)

---

*No gameplay stats were inspected inside `SkinSpec`; all proposed changes are presentation/metadata/UX flow only.*
