# Original User Request

## Initial Request — 2026-08-03T20:14:59+05:30

You are the Sub-Orchestrator for Milestones 2 & 3 (UI Collapse & Single-Active Modal State Machine) of RIVALS-PARADIGM v2 Roblox FPS Overhaul.
Your working directory is: c:\Users\tummala surya\Downloads\roblox\.agents\sub_orch_m2_m3
Your scope document is: c:\Users\tummala surya\Downloads\roblox\PROJECT.md
Explorer 1 Analysis: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m0_1\analysis.md

Your Objective:
Implement Milestone 2 (UI Collapse & Free Roam Camera) and Milestone 3 (Single-Active Modal State Machine).

Requirements for M2 & M3:
1. Every UI panel (Matchmaking Queue, Armory Loadout Inspector, Settings, Challenge List, Sidebar) must have explicit, highly visible Close/Back buttons (`BACK` / `✕`) and key shortcuts (`TAB` / `ESC`).
2. Pressing `TAB` toggles seamlessly between Main Lobby HQ sidebar menu and Free Roam mode (`CameraType = Custom`).
3. Pressing `ESC` returns open sub-windows (`Play`, `Loadout`, `Challenge`, `Settings`) to the Main Lobby HQ sidebar menu, or from Main Lobby to Free Roam.
4. Restoring Free Roam mode restores full player movement controls (`CameraType = Custom`, `Humanoid` WalkSpeed/JumpPower enabled) and displays top-bar prompt `[PRESS TAB FOR MENU]`.
5. When menu is active, player character movement (`WalkSpeed`/`JumpPower`) is locked/disabled so characters don't walk around in background.
6. Enforce Single-Active-Modal management across `LobbyUIController.luau`, `MatchmakingQueueUI.luau`, `LoadoutInspectorUI.luau`, and `PlayerListChallengeUI.luau`. Opening any modal auto-hides all other open windows.
7. Fix missing methods on `MatchmakingQueueUI.luau` (`ShowQueuePanel()`, `HideQueuePanel()`, `IsVisible()`) so clicking "▶ PLAY MATCH" works seamlessly.

Execution Protocol:
- Spawn Worker subagents (`teamwork_preview_worker`) to implement changes in `src/client/UI/` and `src/client/Controllers/`.
- MANDATORY INTEGRITY WARNING to Workers: DO NOT CHEAT. All implementations must be genuine.
- Verify with Reviewer (`teamwork_preview_reviewer`) and Challenger (`teamwork_preview_challenger`).
- Run Rojo build verification (`.\rojo.exe build default.project.json -o RivalsParadigm.rbxl`).
- Update `progress.md` and send report to parent upon completion.
