# Original User Request

## Initial Request — 2026-08-03T20:15:00+05:30

You are the Sub-Orchestrator for Milestone 4 (Armory 3D Weapon Models & Dynamic Stats System) of RIVALS-PARADIGM v2 Roblox FPS Overhaul.
Your working directory is: c:\Users\tummala surya\Downloads\roblox\.agents\sub_orch_m4
Your scope document is: c:\Users\tummala surya\Downloads\roblox\PROJECT.md
Explorer 2 Analysis: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m0_2\analysis.md

Your Objective:
Implement Milestone 4: Complete Armory & 4 Visually Distinct 3D Weapon Models with Dynamic Stats System.

Requirements for M4:
1. Loadout Inspector must accurately reflect dynamic weapon stats (Damage, Fire Rate / RPM, Range, Recoil, Mobility) per weapon class (`AssaultRifle`, `SMG`, `SniperRifle`, `BurstRifle`).
2. Render 4 visually distinct procedural 3D weapon models in ViewportFrame for `AssaultRifle` (AR-15 Paradigm), `SMG` (Vector-9 Paradigm), `SniperRifle` (Apex-50 Paradigm), and `BurstRifle` (BR-3 Paradigm) using Roblox primitives (`Part`, `SpecialMesh`, `WeldConstraint`, `Handle`) without external asset dependencies.
3. Fix cross-weapon attachment state leaks by implementing per-weapon loadout data isolation (`weaponLoadouts[weaponId]`). Switching weapon tabs must re-sync UI buttons and 3D models cleanly.
4. Support 4 attachment slots (Optic, Muzzle, Underbarrel, Magazine) plus Finish/Skin slot. Add `underbarrel` and `magazine` UI selector rows. Render visual 3D parts on the weapon for ALL 4 attachment slots in ViewportFrame.
5. Dynamic ViewportFrame camera framing (auto-distance calculation based on model bounding box) and ambient lighting (`LightColor`, `LightDirection`) to prevent clipping and dark models.
6. Connect loadout selections to combat execution (`WeaponController.luau`).

Execution Protocol:
- Spawn Worker subagents (`teamwork_preview_worker`) to implement changes in `src/client/UI/LoadoutInspectorUI.luau`, `src/shared/Data/WeaponStats.luau`, and `src/client/Controllers/WeaponController.luau`.
- MANDATORY INTEGRITY WARNING to Workers: DO NOT CHEAT. All implementations must be genuine.
- Verify with Reviewer (`teamwork_preview_reviewer`) and Challenger (`teamwork_preview_challenger`).
- Run Rojo build verification (`.\rojo.exe build default.project.json -o RivalsParadigm.rbxl`).
- Update `progress.md` and send report to parent upon completion.
