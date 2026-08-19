## 2026-08-03T15:08:46Z
You are Explorer for Milestone 2 (M2_Round_Economy) in Project OVERCLOCK.
Your working directory is `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m2`.

MANDATORY READS:
- `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md`
- `c:\Users\tummala surya\Downloads\roblox\PROJECT.md`

YOUR TASK:
Examine `src/server/ServerMain.server.luau`, `src/shared/Network/RemoteEvents.luau`, and `src/server/Combat/CombatServer.luau`.
Formulate a concrete file implementation specification for Worker 2 to build:
1. `src/server/Services/RoundService.luau`:
   - State machine for 1v1 and 2v2 matches: Buy Phase (15s) -> Live Phase (60s) -> RoundEnd Phase (5s) -> Intermission Phase (3s) -> Next Round.
   - Sudden-death round at 6-6 tie (each player starts with 5000 credits). First to 7 rounds wins.
   - Spectate mode on death (suppress mid-round respawning in `ServerMain.server.luau`).
   - Round reset: reset character positions to team spawn locations, restore health/armor, clear temporary effects.
2. `src/server/Services/EconomyService.luau`:
   - Server-authoritative credit balances for PvP matches.
   - Starting credits: 800 for Pistol Round (Round 1), 5000 for Sudden Death.
   - Win bonus: +3000 Credits.
   - Loss streak scaling bonus: +1900 (1st loss), +2400 (2nd consecutive loss), +2900 cap (3+ consecutive losses).
   - Kill reward: +200 Credits.
   - Server validation for buy requests (`RequestPurchase` remote event): only allowed during Buy Phase, rejects purchases exceeding credit balance.
   - Practice Range mode bypasses economy entirely (free access).

Write your report to `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m2\analysis.md` and `handoff.md`. Send a completion message when finished.
