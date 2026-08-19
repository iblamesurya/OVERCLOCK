# Handoff Report: Explorer 2 (Milestone 0)

**Task**: Analyze Armory 3D Weapon Models & Dynamic Stats System  
**Working Directory**: `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m0_2`  
**Target Files Analyzed**:
- `src/shared/Data/WeaponStats.luau`
- `src/client/UI/LoadoutInspectorUI.luau`
- `src/client/Controllers/WeaponController.luau`
- `src/client/UI/LobbyUIController.luau`
- `src/client/ClientMain.client.luau`
- `src/shared/Types/init.luau`

---

## 1. Observation

### 1.1 Weapon Stats Registry (`src/shared/Data/WeaponStats.luau`)
- Line 35–126: `WeaponRegistry` table defines 4 weapon classes (`AssaultRifle`, `SMG`, `SniperRifle`, `BurstRifle`).
- Base stats:
  - `AssaultRifle`: Damage 32, Headshot 2.0x, RPM 600, Spread 0.4–3.2, Recoil `(0.035, 0.015, 0.06)`, Mobility 0.95, MaxRange 1000.
  - `SMG`: Damage 19, Headshot 1.5x, RPM 900, Spread 0.8–4.8, Recoil `(0.022, 0.018, 0.035)`, Mobility 1.00, MaxRange 600.
  - `SniperRifle`: Damage 105, Headshot 2.5x, RPM 45, Spread 0.05–8.0, Recoil `(0.16, 0.04, 0.22)`, Mobility 0.82, MaxRange 2500.
  - `BurstRifle`: Damage 27, Headshot 1.85x, RPM 750, Spread 0.25–2.8, Recoil `(0.028, 0.010, 0.045)`, Mobility 0.93, MaxRange 1200.

### 1.2 ViewportFrame Setup & Rendering (`src/client/UI/LoadoutInspectorUI.luau`)
- Lines 394–418: ViewportFrame `WeaponViewport` (Size 1x300px) created with `Camera` (FOV 50) and `WorldModel` (`ViewportWorldModel`).
- Lines 231: Fixed camera offset `viewportCamera.CFrame = CFrame.new(Vector3.new(2.8, 1.2, 3.8), Vector3.new(0, 0, 0))`.
- Lines 691–696: RenderStepped loop updates model rotation: `previewWeaponModel:PivotTo(CFrame.Angles(0, math.rad(currentRotation), 0))`.
- ViewportFrame lighting properties (`LightColor`, `LightDirection`) are not configured.

### 1.3 Attachment & UI State Handling (`src/client/UI/LoadoutInspectorUI.luau`)
- Lines 28–36: Global state variables `currentWeaponId`, `currentSkinId`, and `currentAttachments` store active choices singletons.
- Lines 449–452: `SelectWeapon(wId)` changes `currentWeaponId` and re-renders, but DOES NOT reset or load per-weapon attachments/skins, nor updates cycle button text.
- Lines 527–648: UI only builds `SkinRow`, `OpticRow`, and `MuzzleRow`. No UI elements exist for `underbarrel` or `magazine` slots.
- Lines 201–212: Only `currentAttachments.optic ~= "Stock Sights"` generates visual 3D parts (`OpticOverlay`, `lens`). `muzzle`, `underbarrel`, and `magazine` attachments produce no 3D geometry on the weapon model.

---

## 2. Logic Chain

1. **Observed**: Global attachment state variables `currentAttachments` in `LoadoutInspectorUI.luau:31-36` are modified when attachment buttons are clicked.
   - **Reasoning**: When a user selects attachments on one weapon (e.g. `Scope 4x` on `AssaultRifle`) and clicks the `SMG` tab button, `SelectWeapon("SMG")` is invoked. Because `currentAttachments` is shared globally and not indexed per weapon, the SMG inherits `Scope 4x`. Furthermore, because button text is only updated in `MouseButton1Click` handlers (lines 605, 646), button text shows "Stock Sights" while `calculateModifiedStats()` uses "Scope 4x".
   - **Conclusion**: There is a clear state leak across weapon tab switches and a UI text desynchronization bug.

2. **Observed**: `ATTACHMENT_OPTIONS` defines `optic`, `muzzle`, `underbarrel`, and `magazine` options and stat multipliers (lines 82–103). However, lines 527–648 in `Init()` only create UI rows for `Skin`, `Optic`, and `Muzzle`.
   - **Reasoning**: The underlying stat modifier math (`calculateModifiedStats`) handles underbarrel and magazine multipliers, but because no UI buttons exist for them, players cannot select them.
   - **Conclusion**: The UI layout is incomplete, missing 2 of the 4 attachment slots.

3. **Observed**: In `build3DWeaponPreviewModel()` (lines 145–215), 3D parts are created for weapon receivers, barrels, stocks, grips, and optics. No code exists for rendering `Suppressor`, `Compensator`, `Vertical Grip`, `Tac Laser`, or `Extended Mag` parts.
   - **Reasoning**: Non-optic attachment selections affect stats mathematically but are completely invisible on the 3D model in the ViewportFrame.
   - **Conclusion**: Procedural 3D model rendering needs to be extended so that every attachment choice renders visible geometry.

4. **Observed**: Fixed camera CFrame `Vector3.new(2.8, 1.2, 3.8)` is applied regardless of weapon dimensions.
   - **Reasoning**: Model bounding boxes range from Z=2.3 studs (`SMG`) to Z=8.1 studs (`SniperRifle`). A static camera distance causes large weapons to clip past the frame edges and small weapons to appear un-centered.
   - **Conclusion**: Dynamic camera distance calculation using `Model:GetBoundingBox()` is required for proper framing.

---

## 3. Caveats

- **No Caveats**: All relevant files (`WeaponStats.luau`, `LoadoutInspectorUI.luau`, `WeaponController.luau`, `LobbyUIController.luau`, `ClientMain.client.luau`) were directly inspected and verified.
- Implementation of code changes is reserved for Milestone 4; no code outside `.agents/` was modified during this Milestone 0 investigation.

---

## 4. Conclusion

The current Armory 3D Weapon Models & Dynamic Stats System provides a solid foundation with clean base stats in `WeaponStats.luau` and procedural 3D model rendering in `LoadoutInspectorUI.luau`. However, it suffers from 5 critical bugs/deficiencies:
1. Global attachment state leaks between weapon tab switches and button text desync.
2. Incomplete UI missing `underbarrel` and `magazine` slot selector rows.
3. Lack of 3D visual geometry for muzzle, underbarrel, and magazine attachments.
4. Static camera framing causing viewport clipping on large weapons.
5. Absence of ViewportFrame ambient lighting configuration.

Implementing the recommended modular architecture (isolated per-weapon loadout data, 4-slot 3D visual attachment rendering, dynamic camera distance, ambient lighting, and `WeaponController` integration) in Milestone 4 will fully resolve these issues.

---

## 5. Verification Method

To independently verify the observations and findings documented in this report:

1. **Inspect Code Locations**:
   - View `src/shared/Data/WeaponStats.luau` lines 35–126 to verify base stats and weapon classes.
   - View `src/client/UI/LoadoutInspectorUI.luau` lines 28–36 to verify global state singletons.
   - View `src/client/UI/LoadoutInspectorUI.luau` lines 527–648 to verify missing UI rows for underbarrel and magazine.
   - View `src/client/UI/LoadoutInspectorUI.luau` lines 201–212 to verify that only `optic` attachments have visual 3D model overlays.
   - View `src/client/UI/LoadoutInspectorUI.luau` lines 231 to confirm fixed camera position `Vector3.new(2.8, 1.2, 3.8)`.

2. **UI State Leak & Desync Invalidation Test**:
   - Launch client loadout menu -> select `Scope 4x` on `AssaultRifle` -> switch tab to `SMG`. Observe that `currentAttachments` retains `Scope 4x` while button text displays `Stock Sights`.

3. **Detailed Analysis File**:
   - Comprehensive documentation is available at `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m0_2\analysis.md`.
