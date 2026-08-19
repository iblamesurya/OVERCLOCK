# Armory 3D Weapon Models & Dynamic Stats System Analysis

**Project**: RIVALS-PARADIGM v2 Roblox FPS Overhaul  
**Milestone**: Milestone 0 — Explorer 2 Report  
**Target Files**: 
- `src/shared/Data/WeaponStats.luau`
- `src/client/UI/LoadoutInspectorUI.luau`
- `src/client/Controllers/WeaponController.luau`
- `src/client/UI/LobbyUIController.luau`
- `src/client/ClientMain.client.luau`

---

## Executive Summary

This report presents an in-depth audit of the Armory 3D Weapon Models and Dynamic Stats System for Project RIVALS-PARADIGM v2. The objective is to evaluate the existing UI implementation, weapon registry data structure, ViewportFrame 3D rendering pipeline, procedural mesh construction, and attachment/skin slot customization.

Key findings include:
1. **Weapon Stats Handling**: The current `WeaponStats.luau` module cleanly defines 4 weapon classes (`AssaultRifle`, `SMG`, `SniperRifle`, `BurstRifle`) with base parameters for damage, fire rate (RPM), range, recoil vectors, and mobility speed. Attachment multipliers alter damage, recoil, range, and mobility.
2. **ViewportFrame & 3D Rendering**: 3D previews are rendered inside a `ViewportFrame` using a `WorldModel` and a dedicated `Camera`. However, lighting parameters (`LightColor`, `LightDirection`) are absent, and camera framing is fixed, causing clipping on larger models (Sniper) and under-scaled rendering on smaller ones (SMG).
3. **Procedural Model Architecture**: Weapon models are procedurally constructed using `Instance.new("Part")`. While currently limited to basic block parts anchored at runtime, they can be significantly upgraded using `SpecialMesh` (Cylinders, Wedges, Primitive meshes), `WeldConstraint` hierarchies with a `Handle` root, and dynamic attachment mounts without any external mesh asset dependencies.
4. **UI Bugs & State Leaks**: Crucial state leaks and UI bugs were discovered when switching weapon tabs:
   - Attachment state persists across weapon tab switches, contaminating other weapons.
   - UI button text desynchronizes from actual state upon switching tabs.
   - `underbarrel` and `magazine` attachment rows are missing from the inspector UI layout entirely.
   - Only `optic` attachments produce visual 3D overlays on the preview model; `muzzle`, `underbarrel`, and `magazine` attachments are visually invisible.
5. **Milestone 4 Implementation Plan**: A concrete, modular architecture is outlined to solve these issues, establishing per-weapon loadout data isolation, full 4-slot 3D visual attachment rendering, dynamic camera framing, lighting setup, and sync with `WeaponController.luau`.

---

## 1. Audit of Current Weapon Stats System

### 1.1 Base Weapon Registry Analysis (`src/shared/Data/WeaponStats.luau`)

The registry defines 4 weapon classes with distinct gameplay roles:

| Weapon Class | Display Name | Base Damage | Headshot Multiplier | Fire Rate (RPM) | Bullet Velocity (studs/s) | Max Range (studs) | Recoil Impulse Vector | Mobility Speed | Reload Duration (s) | Fire Mode |
|---|---|---|---|---|---|---|---|---|---|---|
| **AssaultRifle** | AR-15 Paradigm | 32 | 2.0x | 600 | 2500 | 1000 | `(0.035, 0.015, 0.060)` | 0.95 (95%) | 2.2 | Auto |
| **SMG** | Vector-9 Paradigm | 19 | 1.5x | 900 | 1800 | 600 | `(0.022, 0.018, 0.035)` | 1.00 (100%) | 1.6 | Auto |
| **SniperRifle** | Apex-50 Paradigm | 105 | 2.5x | 45 | 4000 | 2500 | `(0.160, 0.040, 0.220)` | 0.82 (82%) | 3.5 | Semi |
| **BurstRifle** | BR-3 Paradigm | 27 | 1.85x | 750 | 2800 | 1200 | `(0.028, 0.010, 0.045)` | 0.93 (93%) | 2.4 | Burst (3-rnd) |

### 1.2 Dynamic Stat Modifiers (`LoadoutInspectorUI.luau`, lines 81–130)

Attachments modify four core stats via compound multiplication:
$$\text{Stat}_{\text{final}} = \text{Stat}_{\text{base}} \times \prod \text{Mult}_{\text{optic}} \times \text{Mult}_{\text{muzzle}} \times \text{Mult}_{\text{underbarrel}} \times \text{Mult}_{\text{magazine}}$$

- **Damage**: `math.round(base.damage * dMult)`
- **Fire Rate**: `base.fireRate` (raw RPM; currently un-modified by attachments)
- **Range**: `math.round(base.maxRange * rngMult)`
- **Recoil**: `math.round(base.recoilImpulse.Magnitude * 1000 * rMult)`
- **Mobility**: `math.round(base.mobilitySpeed * 100 * mobMult)`

### 1.3 Stat Bar UI Visualization (`LoadoutInspectorUI.luau`, lines 240–276)

Stat values are mapped to visual progress bars using maximum reference scale caps (`maxRef`):

| Stat | Formula | Recoil / Value Example (AssaultRifle Base) | Max Reference Cap (`maxRef`) | Bar Ratio Calculation |
|---|---|---|---|---|
| **Damage** | `stats.damage` | 32 | 120 | $32 / 120 = 26.7\%$ |
| **FireRate** | `stats.fireRate` | 600 RPM | 1000 | $600 / 1000 = 60.0\%$ |
| **Range** | `stats.maxRange` | 1000 studs | 2500 | $1000 / 2500 = 40.0\%$ |
| **Recoil** | `recoilImpulse.Magnitude * 1000` | ~71 | 250 | $71 / 250 = 28.4\%$ |
| **Mobility** | `mobilitySpeed * 100` | 95% | 110 | $95 / 110 = 86.4\%$ |

#### Recoil Stat Bar Insight:
For **SniperRifle**, `recoilImpulse = Vector3.new(0.16, 0.04, 0.22)`.
$$\text{Magnitude} = \sqrt{0.16^2 + 0.04^2 + 0.22^2} = \sqrt{0.0256 + 0.0016 + 0.0484} = \sqrt{0.0756} \approx 0.274955$$
$$\text{Recoil Value} = 0.274955 \times 1000 \approx 275$$
Since `maxRef.Recoil = 250`, $275 / 250 = 1.10$, which clamps to $1.0$ ($100\%$ bar fill). Higher fill currently represents **higher recoil magnitude** (more kick). In standard FPS interfaces, players expect higher bars to represent better control or lower recoil.

---

## 2. Examination of ViewportFrame Rendering System

### 2.1 ViewportFrame Configuration (`LoadoutInspectorUI.luau`, lines 393–420)

```luau
local vp = Instance.new("ViewportFrame")
vp.Name = "WeaponViewport"
vp.Size = UDim2.new(1, 0, 0, 300)
vp.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
vp.BackgroundTransparency = 0.3

local vpCamera = Instance.new("Camera")
vpCamera.FieldOfView = 50
vp.CurrentCamera = vpCamera

local wm = Instance.new("WorldModel")
wm.Parent = vp
```

### 2.2 Model Creation & Camera Positioning (`LoadoutInspectorUI.luau`, lines 217–232)

- Models are created procedurally by `build3DWeaponPreviewModel(weaponId, skinId)`.
- Parented to `WorldModel` (`wm`).
- Camera position is fixed: `viewportCamera.CFrame = CFrame.new(Vector3.new(2.8, 1.2, 3.8), Vector3.new(0, 0, 0))`.

### 2.3 Rotation Render Loop (`LoadoutInspectorUI.luau`, lines 690–697)

```luau
renderConnection = RunService.RenderStepped:Connect(function(dt: number)
    currentRotation = (currentRotation + dt * 40) % 360
    if previewWeaponModel and previewWeaponModel.PrimaryPart then
        previewWeaponModel:PivotTo(CFrame.Angles(0, math.rad(currentRotation), 0))
    end
end)
```

### 2.4 Rendering Deficiencies Identified:
1. **Missing Ambient Lighting**: Roblox ViewportFrames require explicit `LightColor` and `LightDirection` properties or internal light sources. Without them, models look flat, dim, and unrendered.
2. **Fixed Static Camera Offset**: SMG models (length ~2.3 studs) appear small and distant, whereas Sniper Rifle models (length ~8.1 studs) clip outside the camera viewport framing.
3. **No Weld Constraints for Dynamically Manipulated Parts**: Parts are created anchored with absolute initial CFrames. While `PivotTo` works on anchored models, unanchored viewmodels or weapon drops require a proper weld hierarchy.

---

## 3. Procedural 3D Weapon Model Hierarchy (No External Assets)

To eliminate external asset dependencies (`MeshId` / RBX Asset IDs), weapon models must be procedurally assembled using Roblox primitives (`Instance.new("Part")`), `SpecialMesh` (Cylinder, Wedge, Block), `WeldConstraint`, and material/color configurations.

### 3.1 Base Assembly Hierarchy Schema

```
Model (Preview_<WeaponId>)
 ├── PrimaryPart / Handle (Base Receiver Core)
 ├── WeldConstraint (Receiver -> Barrel)
 ├── WeldConstraint (Receiver -> Stock)
 ├── WeldConstraint (Receiver -> Grip)
 ├── WeldConstraint (Receiver -> Magazine)
 ├── WeldConstraint (Receiver -> Handguard/Rails)
 ├── AttachmentMount_Optic (AttachmentPoint)
 ├── AttachmentMount_Muzzle (AttachmentPoint)
 ├── AttachmentMount_Underbarrel (AttachmentPoint)
 └── AttachmentMount_Magazine (AttachmentPoint)
```

### 3.2 Detailed Visual Specifications by Weapon Class

#### 1. Assault Rifle (`AssaultRifle` — AR-15 Paradigm)
- **Receiver**: Upper and lower receiver box (`Vector3.new(0.5, 0.7, 2.2)`).
- **Barrel**: Cylindrical mesh (`SpecialMesh.MeshType = Enum.MeshType.Cylinder`, `Size = Vector3.new(0.2, 2.0, 0.2)`).
- **Handguard**: M-LOK / Quad-rail shroud enclosing the barrel (`Vector3.new(0.45, 0.5, 1.6)`).
- **Stock**: Adjustable tactical stock (`Vector3.new(0.35, 0.6, 1.4)`).
- **Magazine**: Curved STANAG 30-round magazine using angled CFrame (`Angles(rad(15), 0, 0)`).
- **Top Rail**: Picatinny optics rail (`Vector3.new(0.3, 0.15, 1.8)`).

#### 2. SMG (`SMG` — Vector-9 Paradigm)
- **Receiver**: Compact, low-profile receiver (`Vector3.new(0.45, 0.6, 1.4)`).
- **Barrel**: Short cylindrical barrel stub (`Vector3.new(0.18, 1.0, 0.18)`).
- **Stock**: Wireframe folding stock assembly (`Vector3.new(0.25, 0.3, 1.0)`).
- **Grip & Foregrip**: Ergonomic pistol grip plus integrated vertical foregrip.
- **Magazine**: Vertical straight stick magazine (`Vector3.new(0.22, 1.4, 0.3)`).

#### 3. Sniper Rifle (`SniperRifle` — Apex-50 Paradigm)
- **Receiver**: Heavy-duty bolt-action receiver (`Vector3.new(0.65, 0.85, 2.8)`).
- **Barrel**: Long fluted bull barrel (`Vector3.new(0.3, 4.5, 0.3)` with Cylinder mesh).
- **Muzzle Brake**: Large dual-port muzzle brake at barrel tip (`Vector3.new(0.45, 0.45, 0.6)`).
- **Stock & Cheek Rest**: Heavy sniper stock with elevated padded cheek rest (`Vector3.new(0.4, 0.3, 0.8)`).
- **Scope Assembly**: High-power optical scope tube with front/rear cyan Neon glass lenses.
- **Bipod Mount**: Folded bipod legs attached to forend rail.

#### 4. Burst Rifle (`BurstRifle` — BR-3 Paradigm)
- **Receiver**: Sleek bullpup layout (`Vector3.new(0.55, 0.75, 2.4)`).
- **Magazine**: Rear-mounted angled magwell behind the pistol grip (`Angles(rad(15), 0, 0)` at rear).
- **Integrated Carrying Rail**: Full-length top carry handle / optic rail riser (`Vector3.new(0.35, 0.4, 2.0)`).
- **Handguard**: Tactical quad-rail front end.

---

## 4. Skin & Attachment Slot Modification Support, UI Bugs & State Leaks

### 4.1 Skin Configuration Audit

Skins alter part colors and materials dynamically:

```luau
local SKINS_DATA = {
    Default = { primaryColor = RGB(45, 50, 60), secondaryColor = RGB(20, 22, 28), material = SmoothPlastic },
    CarbonFiber = { primaryColor = RGB(25, 25, 25), secondaryColor = RGB(10, 10, 10), material = Fabric },
    NeonCyber = { primaryColor = RGB(10, 30, 50), secondaryColor = RGB(0, 220, 255), material = Neon },
    GoldParadigm = { primaryColor = RGB(220, 175, 40), secondaryColor = RGB(40, 35, 20), material = Metal },
}
```

### 4.2 Detailed UI Bugs & State Leaks Identified

#### 🐛 Bug 1: Cross-Weapon Attachment State Leak & Button Text Desynchronization
- **Issue**: `currentAttachments` and `currentSkinId` are global variables in `LoadoutInspectorUI.luau` (lines 30–36).
- **Reproduction**:
  1. Open Loadout Inspector for `AssaultRifle`.
  2. Select Optic: `Scope 4x` and Muzzle: `Suppressor`.
  3. Click `SMG` tab button.
- **Result**: `currentAttachments` remains `{ optic = "Scope 4x", muzzle = "Suppressor", ... }`. However, `opticBtn.Text` and `muzBtn.Text` were NOT updated because text updates only occur in `MouseButton1Click` callbacks! As a result, the 3D model shows the attachments from the previous weapon while the UI buttons display default text, creating severe state desynchronization.

#### 🐛 Bug 2: Missing UI Selector Rows for Underbarrel & Magazine Slots
- **Issue**: In `LoadoutInspectorUI.luau` (lines 502–648), only `SkinRow`, `OpticRow`, and `MuzzleRow` are constructed in `Init()`.
- **Impact**: `underbarrel` (Vertical Grip, Tac Laser) and `magazine` (Extended Mag) attachment multipliers exist in data and stat math, but players have **no UI controls** to equip or cycle them.

#### 🐛 Bug 3: Invisible Attachment Models for Muzzle, Underbarrel & Magazine
- **Issue**: `build3DWeaponPreviewModel()` (lines 201–212) only contains rendering logic for `optic` attachments (`OpticOverlay` / `lens`).
- **Impact**: Equipping a `Suppressor`, `Compensator`, `Vertical Grip`, `Tac Laser`, or `Extended Mag` modifies numbers on the stat bars, but renders **zero 3D visual geometry** on the weapon in the ViewportFrame.

#### 🐛 Bug 4: Viewport Camera Clipping & Dynamic Bounds Deficiency
- **Issue**: Viewport camera CFrame is fixed at `Vector3.new(2.8, 1.2, 3.8)` for all weapons.
- **Impact**: `SniperRifle` (total length > 8 studs) extends past the viewport border and gets clipped. `SMG` (length ~2.3 studs) appears small and distant.

#### 🐛 Bug 5: Dark / Unlit Viewport Rendering
- **Issue**: `ViewportFrame` lacks explicit `LightColor` and `LightDirection` settings.
- **Impact**: Weapon preview models look flat and dark depending on client graphics settings.

---

## 5. Milestone 4 Implementation Strategy & Recommendations

To deliver a production-grade Armory 3D Weapon Models & Dynamic Stats System in Milestone 4, the following concrete architectural upgrades are recommended:

### 5.1 Architecture & Modular Design

```
src/client/
 ├── UI/
 │    └── LoadoutInspectorUI.luau    -- Refactored UI layout, tabs, 4-slot selectors
 ├── Controllers/
 │    └── WeaponController.luau     -- Equipped weapon loadout integration
 └── Renderers/
      └── ProceduralWeaponFactory.luau -- Modular 3D model builder (Parts, Meshes, Welds, Attachments)
```

### 5.2 Specific Code Modification Plan

#### 1. Per-Weapon Loadout Data Isolation (`LoadoutInspectorUI.luau`)
Replace global `currentAttachments` with a per-weapon state dictionary:

```luau
type WeaponLoadoutState = {
    skinId: string,
    attachments: {
        optic: string,
        muzzle: string,
        underbarrel: string,
        magazine: string,
    }
}

local weaponLoadouts: { [string]: WeaponLoadoutState } = {
    AssaultRifle = { skinId = "Default", attachments = { optic = "Stock Sights", muzzle = "Default Muzzle", underbarrel = "None", magazine = "Standard" } },
    SMG          = { skinId = "Default", attachments = { optic = "Stock Sights", muzzle = "Default Muzzle", underbarrel = "None", magazine = "Standard" } },
    SniperRifle  = { skinId = "Default", attachments = { optic = "Stock Sights", muzzle = "Default Muzzle", underbarrel = "None", magazine = "Standard" } },
    BurstRifle   = { skinId = "Default", attachments = { optic = "Stock Sights", muzzle = "Default Muzzle", underbarrel = "None", magazine = "Standard" } },
}
```
When switching weapon tabs (`SelectWeapon(weaponId)`), retrieve the saved loadout for that weapon and explicitly update all 5 selector button text labels (`skinBtn`, `opticBtn`, `muzBtn`, `underbarrelBtn`, `magBtn`).

#### 2. Complete UI Layout with 4 Attachment Slots
Add `UnderbarrelRow` and `MagazineRow` to `ConfigBox`, resizing `ConfigBox` from `height = 235` to `height = 310` to cleanly accommodate all 5 configuration rows (Finish, Optic, Muzzle, Underbarrel, Magazine).

#### 3. Visual 3D Attachment Models for All 4 Slots
Expand procedural model rendering to support visual models for every slot:
- **Optic**:
  - `Red Dot`: Compact box with square frame and red Neon dot center.
  - `Holographic`: Angled visor hood with holographic lens.
  - `Scope 4x`: Cylinder body with dual lenses and turret knobs.
- **Muzzle**:
  - `Suppressor`: Extended dark metallic cylinder (`SpecialMesh.MeshType = Cylinder`).
  - `Compensator`: Dual-slotted flash hider nozzle at barrel end.
- **Underbarrel**:
  - `Vertical Grip`: Ergonomic vertical cylinder/block under handguard.
  - `Tac Laser`: Rail-mounted laser box with visible green/red Neon beam emitter.
- **Magazine**:
  - `Extended Mag`: Lengthened magazine geometry extending lower from magwell.

#### 4. Dynamic Viewport Camera Framing & Lighting
Update `updateViewportPreview()` to calculate camera position dynamically based on model size:

```luau
local function updateViewportPreview()
    -- ... build model ...
    local modelCFrame, modelSize = model:GetBoundingBox()
    local maxDim = math.max(modelSize.X, modelSize.Y, modelSize.Z)
    local fov = viewportCamera.FieldOfView
    local distance = (maxDim / 2) / math.tan(math.rad(fov / 2)) * 1.35
    
    viewportCamera.CFrame = CFrame.new(modelCFrame.Position + Vector3.new(distance * 0.6, distance * 0.35, distance * 0.8), modelCFrame.Position)
    viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
    viewportFrame.LightDirection = Vector3.new(-1, -2, -1)
end
```

#### 5. Recoil Stat Representation Improvement
Rename UI stat label from `RECOIL` to `RECOIL CONTROL` or invert the percentage display ($100\% - \text{Ratio}$) so that higher stat bars consistently indicate better performance across all stats.

#### 6. Integration with Combat Execution (`WeaponController.luau`)
Expose `LoadoutInspectorUI.GetLoadoutForWeapon(weaponId)` so that when `WeaponController.EquipWeapon(weaponId)` is called during matches, the local viewmodel/weapon applies the player's customized attachments and skin multipliers directly to combat recoil, damage falloff, and range.

---
*End of Analysis Report*
