## 2026-08-03T15:08:46Z
<USER_REQUEST>
You are Explorer for Milestone 4 (M4_Practice_Range_Bots) in Project OVERCLOCK.
Your working directory is `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m4`.

MANDATORY READS:
- `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md`
- `c:\Users\tummala surya\Downloads\roblox\PROJECT.md`

YOUR TASK:
Examine `src/shared/Map/PracticeRangeMapLayout.luau`, `src/server/Combat/CombatServer.luau`, and `src/server/ServerMain.server.luau`.
Formulate a concrete file implementation specification for Worker 4 to build:
1. `src/server/Services/BotService.luau`:
   - Stationary Target Wall Manager: detects hits on `Target_Stationary_1..N` bullseye target parts, plays hit animation/sound effect, updates running hit counter, supports remote reset.
   - Patrol Bot AI Lifecycle: spawns 4-6 moving bot humanoids in `PatrolBotSection`, navigates them between 3D waypoints (`Waypoints_Bot_1..N`) using `Humanoid:MoveTo()`.
   - Bot Combat Integration: bots take damage via shared `CombatServer` raycast hit code path, die when HP <= 0, and automatically respawn at their origin spawn pad after a ~3s delay.
2. Practice Range Live Accuracy Stats Tracker:
   - Tracks total shots fired, hits, headshots, accuracy %, headshot % per session.
   - Replicates live stats to client HUD and handles reset request (`ResetRangeStats`).

Write your report to `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m4\analysis.md` and `handoff.md`. Send a completion message when finished.
</USER_REQUEST>
