## 2026-08-03T00:45:41Z
You are worker_v2_m5 assigned to Milestone 5: Complete Combat & UI Integration for Project RIVALS-PARADIGM v2.
Working Directory: c:\Users\tummala surya\Downloads\roblox\.agents\worker_v2_m5

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your Tasks:
1. Create `.agents/worker_v2_m5/progress.md` and `.agents/worker_v2_m5/BRIEFING.md`.
2. Update/implement `src/server/ServerMain.server.luau`: Strict Luau (`--!strict`) main server entry point initializing `ProfileServiceWrapper`, `MatchmakingCoordinator`, `QueueMatchmakingService`, `DirectChallengeService`, `MapRegistry`, `CombatServer`, and `LobbyFolder`. Handles player join lifecycle (spawning into Lobby), match session state events, and match-end cleanup & return to lobby.
3. Update/implement `src/client/ClientMain.client.luau`: Strict Luau (`--!strict`) main client entry point initializing `LobbyUIController`, `MatchmakingQueueUI`, `PlayerListChallengeUI`, `ChallengeInviteModal`, `LoadoutInspectorUI`, `WeaponController`, `CrosshairController`, `HUDController`, `MobileControlsController`, and `LobbyTransitionController`.
4. Update `src/client/UI/HUDController.luau`: Update HUD state machine to toggle between Lobby mode (Lobby UI & Player List visible, combat HUD hidden) and Match mode (Lobby UI hidden, health, ammo, dynamic crosshair, killfeed, round scoreboard visible).
5. Update `src/server/Combat/CombatServer.luau`: Wire hit validation to check player match status (only process damage in active match sessions, reject hits in Lobby).
6. Verify your implementation by running static analysis (`selene src/`) across all updated entry points, server main, client main, and controllers to ensure 0 errors.
7. Write your handoff report to `.agents/worker_v2_m5/handoff.md` and send a message back to parent with your results.
