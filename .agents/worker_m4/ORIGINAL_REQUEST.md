## 2026-08-02T18:17:19Z
You are a specialist Luau/Roblox Developer worker subagent.
Your assigned metadata directory is: `c:\Users\tummala surya\Downloads\roblox\.agents\worker_m4`.

Objective: Implement Milestone 4: Client Weapon Systems, Spring Physics & Procedural Animation (R4) for "Project RIVALS-PARADIGM".

Root project directory: `c:\Users\tummala surya\Downloads\roblox`.

Tasks to create/implement in `--!strict` Luau mode:
1. `src/shared/Physics/Spring.luau`:
   - Damped harmonic oscillator Spring physics module.
   - Must expose an `Impulse(velocity)` method compounding with existing momentum.
2. `src/shared/Data/WeaponStats.luau`:
   - Centralized weapon stats data module defining at least 3 distinct weapons (e.g. AssaultRifle, SMG, SniperRifle).
   - Stats include: damage, headshot multiplier, fire rate, spread min/max, recoil impulse vectors, mobility speed, reload duration, fire mode ("Semi", "Auto", "Burst").
3. `src/client/Controllers/WeaponController.luau`:
   - Instant local prediction (visual recoil, muzzle flash, tracer rendering) before server validation.
   - Physics update loop on `RunService.RenderStepped` using a **fixed time-step accumulator pattern** (e.g. 1/60s fixed dt) guaranteeing identical physics from 30 FPS to 240+ FPS.
   - Lerp transitions using exponential decay formula: `current = Lerp(current, target, 1 - math.exp(-lambda * dt))`.
4. `src/client/Controllers/CrosshairController.luau`:
   - Dynamic crosshair translating mathematical spread value into 2D pixel offset on screen.
   - 2D offset accurately maps to 3D unit direction vector used for projectile raycasting.
5. `src/client/Controllers/AnimationController.luau`:
   - Procedural camera recoil, weapon sway, walk bobbing, and aim-down-sights (ADS) camera transitions using the Spring module and exponential decay Lerp.
