## 2026-08-03T14:45:38Z
You are assigned to implement Milestone 4: Armory 3D Weapon Models & Dynamic Stats System for Project RIVALS-PARADIGM v2 Roblox FPS Overhaul.

Your Working Directory: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m4
Target Files:
1. `src/shared/Data/WeaponStats.luau`
2. `src/client/UI/LoadoutInspectorUI.luau`
3. `src/client/Controllers/WeaponController.luau`

Requirements for Milestone 4:
1. **Dynamic Weapon Stats Modifiers (`src/shared/Data/WeaponStats.luau`)**:
   - Define attachment multipliers data (Optic, Muzzle, Underbarrel, Magazine) and skins data centrally in `WeaponStats.luau` (or share with `LoadoutInspectorUI.luau`).
   - Attachment categories & options:
     - Optic: `Stock Sights` (1.0x), `Red Dot` (recoil 0.95, range 1.05, mob 0.99), `Holographic` (recoil 0.92, range 1.10, mob 0.98), `Scope 4x` (recoil 0.88, range 1.25, mob 0.94).
     - Muzzle: `Default Muzzle` (1.0x), `Suppressor` (dmg 0.95, recoil 0.85, range 0.95, mob 0.98), `Compensator` (recoil 0.80, mob 0.97).
     - Underbarrel: `None` (1.0x), `Vertical Grip` (recoil 0.75, mob 0.96), `Tac Laser` (recoil 0.95, mob 1.05).
     - Magazine: `Standard` (1.0x), `Extended Mag` (recoil 1.02, mob 0.95).
   - Implement `WeaponStats.GetModifiedStats(weaponId: string, attachments: { optic: string, muzzle: string, underbarrel: string, magazine: string })` returning modified damage, fireRate, maxRange, recoil (magnitude), mobility, recoilImpulse (Vector3 multiplied by recoilMult), recoilImpulseADS.

2. **Per-Weapon Loadout Isolation & State Fixes (`src/client/UI/LoadoutInspectorUI.luau`)**:
   - Implement per-weapon loadout data isolation (`weaponLoadouts[weaponId]`) so each weapon (`AssaultRifle`, `SMG`, `SniperRifle`, `BurstRifle`) maintains its own skin and attachment state independently.
   - Fix cross-weapon attachment state leaks: When switching weapon tabs (`SelectWeapon(weaponId)`), retrieve the saved loadout for that weapon, re-sync ALL UI button text labels (`skinBtn`, `opticBtn`, `muzBtn`, `underbarrelBtn`, `magBtn`), update 3D preview model, and update stat bars.
   - UI Layout: Expand `ConfigBox` layout to support all 4 attachment slots (Optic, Muzzle, Underbarrel, Magazine) plus Finish/Skin slot. Add selector rows for `underbarrel` and `magazine`. Update button click handlers to cycle through options, update `weaponLoadouts[currentWeaponId]`, sync button text, and update preview/stats.
   - Expose `LoadoutInspectorUI.GetLoadoutForWeapon(weaponId: string)` returning `{ skinId: string, attachments: { optic: string, muzzle: string, underbarrel: string, magazine: string } }`.

3. **Render 4 Visually Distinct 3D Procedural Weapon Models (`src/client/UI/LoadoutInspectorUI.luau`)**:
   - Render models in `ViewportFrame` using Roblox primitives (`Part`, `SpecialMesh`, `WeldConstraint`, `Handle` as PrimaryPart) without external asset dependencies (`MeshId` / rbxassetid).
   - 4 Weapon Classes:
     - `AssaultRifle` (AR-15 Paradigm): upper/lower receiver, barrel, M-LOK handguard, stock, curved magazine, top rail.
     - `SMG` (Vector-9 Paradigm): compact receiver, short barrel, folding stock, pistol grip + foregrip, straight stick magazine.
     - `SniperRifle` (Apex-50 Paradigm): heavy bolt-action receiver, long fluted barrel (Cylinder mesh), dual-port muzzle brake, sniper stock with cheek rest, heavy magazine, scope assembly (body + cyan Neon lenses).
     - `BurstRifle` (BR-3 Paradigm): bullpup receiver, rear angled magazine, top carry handle / optic rail riser, quad-rail handguard.
   - Render 3D Visual Attachments on the preview model for ALL 4 slots:
     - Optic: Red Dot (compact sight box + red Neon dot), Holographic (visor hood + lens), Scope 4x (cylinder tube + cyan Neon lenses).
     - Muzzle: Suppressor (dark metallic cylinder at barrel tip), Compensator (slotted nozzle at barrel tip).
     - Underbarrel: Vertical Grip (cylinder under handguard), Tac Laser (laser box under handguard with visible green/red Neon beam).
     - Magazine: Extended Mag (lengthened magazine geometry extending lower from magwell).

4. **Dynamic ViewportFrame Camera Framing & Ambient Lighting**:
   - Set `viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)` and `viewportFrame.LightDirection = Vector3.new(-1, -2, -1)` to prevent dark, unlit preview models.
   - Calculate camera framing dynamically using `model:GetBoundingBox()`: compute model size, max dimension, and required camera distance based on FOV so SMG isn't tiny and Sniper doesn't clip out of frame.

5. **Combat Connection (`src/client/Controllers/WeaponController.luau`)**:
   - Connect `WeaponController` to `LoadoutInspectorUI.GetLoadoutForWeapon(weaponId)`.
   - When equipping or firing a weapon, apply the active loadout's attachment multipliers to `activeStats` (damage, recoil impulses, range, mobility speed), ensuring customized attachments directly impact gameplay calculations.

MANDATORY INTEGRITY WARNING: DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Verification Steps:
1. Execute Rojo build: `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` from workspace root `c:\Users\tummala surya\Downloads\roblox`. Ensure build succeeds without syntax errors.
2. Write a comprehensive `handoff.md` in your working directory (`c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m4\handoff.md`) detailing the implemented changes, files edited, build verification output, and state isolation confirmation.
