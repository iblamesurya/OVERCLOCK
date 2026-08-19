## 2026-08-03T20:44:47Z
You are Worker 7 for Milestone 7 (M7_DataStore_Safety) in Project OVERCLOCK.
Your working directory is `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m7`.

MANDATORY READS:
- `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md`
- `c:\Users\tummala surya\Downloads\roblox\PROJECT.md`
- `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m7\analysis.md`
- `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m7\handoff.md`

EXCLUSIVE FILE WRITE OWNERSHIP:
- `src/server/Services/ProfileServiceWrapper.luau`
- `src/server/Services/ProfileServiceWrapper.spec.luau`
- Updates to `src/server/ServerMain.server.luau` (DataStore failure non-blocking join fallback logic)

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

YOUR TASK:
Implement Milestone 7 following the Explorer specifications:
1. Update `src/server/Services/ProfileServiceWrapper.luau`:
   - Profile data template including top-level keys: `Level`, `XP`, `Credits`, `OwnedCosmetics`, `EquippedSkins`, `SelectedOperative`, `MatchStats` (Kills, Deaths, Wins, Losses).
   - Roblox DataStore implementation wrapped in `pcall` with exponential backoff retry logic (`math.pow(2, attempt - 1)`).
   - Session locking & 60s periodic autosave interval.
   - Save on `PlayerRemoving` and global `game:BindToClose` shutdown handler.
2. Update `src/server/ServerMain.server.luau`:
   - Non-blocking DataStore failure handling: when DataStore read fails on player join, assign default in-memory profile and allow player to join cleanly WITHOUT kicking (Requirement R6 violation fix).
3. Create unit test spec file `ProfileServiceWrapper.spec.luau` validating profile loading, default template fallback, exponential backoff retries, and autosave loop.

Execute the changes, run Rojo build and Selene static analysis, write your handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m7\handoff.md`, and send a completion message when done.
