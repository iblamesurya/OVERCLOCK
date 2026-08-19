## 2026-08-03T15:10:00Z
You are Worker 4 for Milestone 4 (M4_Practice_Range_Bots) in Project OVERCLOCK.
Your working directory is `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m4`.

MANDATORY READS:
- `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md`
- `c:\Users\tummala surya\Downloads\roblox\PROJECT.md`
- `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m4\analysis.md`
- `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m4\handoff.md`

EXCLUSIVE FILE WRITE OWNERSHIP:
- `src/server/Services/BotService.luau`
- `src/server/Services/BotService.spec.luau`

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

YOUR TASK:
Implement Milestone 4 following the Explorer specifications:
1. Create `src/server/Services/BotService.luau`:
   - Stationary Target Wall Manager: detects hits on `Target_Stationary_1..6` bullseye target parts, plays hit tilt animation & sound effect, updates running hit counter, supports remote reset.
   - Patrol Bot AI Lifecycle: spawns 4-6 moving bot humanoids in `PatrolBotSection`, navigates them between 3D waypoints (`Waypoints_Bot_1..8`) using `Humanoid:MoveTo()` with stuck protection.
   - Bot Combat Integration: bots take damage via shared `CombatServer` raycast code path, die when HP <= 0, and automatically respawn at their origin spawn pad after a 3.0s delay.
   - Practice Range Live Accuracy Stats Tracker: tracks total shots fired, hits, headshots, accuracy %, headshot % per session; replicates live stats to client HUD and handles reset request (`ResetRangeStats`).
2. Create unit test spec file `BotService.spec.luau` validating target wall hit detection, bot spawning/respawn, and accuracy stat arithmetic.

Execute the changes, run code verification, write your handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m4\handoff.md`, and send a completion message when done.
