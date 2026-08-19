## 2026-08-03T14:45:31Z

You are Worker 1 for Milestones 2 & 3 (UI Collapse & Single-Active Modal State Machine) of RIVALS-PARADIGM v2 Roblox FPS Overhaul.
Your working directory is: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m2_m3_1
Your task is to implement the code changes required for Milestone 2 (UI Collapse & Free Roam Camera) and Milestone 3 (Single-Active Modal State Machine).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context & Scope:
- Explorer Analysis Report: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_m0_1\analysis.md
- Scope Document: c:\Users\tummala surya\Downloads\roblox\PROJECT.md

Requirements:
1. Standardize Sub-UI Lifecycle APIs:
   - In `src/client/UI/MatchmakingQueueUI.luau`: Implement missing exported methods `MatchmakingQueueUI.ShowQueuePanel()`, `MatchmakingQueueUI.HideQueuePanel()`, and `MatchmakingQueueUI.IsVisible()`. Ensure clicking "▶ PLAY MATCH" in LobbyUIController calls `ShowQueuePanel()` seamlessly. Add a top-right Close button ("✕") or BACK button to `QueuePanel` returning to `LobbyUIController.SetState("Main")`.
   - In `src/client/UI/LoadoutInspectorUI.luau`: Ensure exported methods `LoadoutInspectorUI.Show()`, `LoadoutInspectorUI.Hide()`, and `LoadoutInspectorUI.IsVisible()` are defined and exported. Ensure explicit Close button ("✕") calls `Hide()` and returns to `LobbyUIController.SetState("Main")`.
   - In `src/client/UI/PlayerListChallengeUI.luau`: Ensure exported methods `PlayerListChallengeUI.Show()`, `PlayerListChallengeUI.Hide()`, and `PlayerListChallengeUI.IsVisible()` are defined and exported. Ensure explicit Close/Back button returns to `LobbyUIController.SetState("Main")`.

2. Single-Active-Modal State Machine in `src/client/UI/LobbyUIController.luau`:
   - Implement Single-Active Modal management inside `SetState(newState)` or `SetActiveModal(modalName)`: opening any modal ("Play", "Loadout", "Challenge", "Settings") must automatically hide all other active sub-windows (`MatchmakingQueueUI`, `LoadoutInspectorUI`, `PlayerListChallengeUI`).
   - Implement `LobbyUIController.SetCharacterMovementEnabled(enabled: boolean)`:
     - When menu state is active (`"Main"`, `"Play"`, `"Loadout"`, `"Challenge"`, `"Settings"`): set `Humanoid.WalkSpeed = 0` and `Humanoid.JumpPower = 0` (or disable controls) so player characters don't walk around in the background.
     - When Free Roam mode (`"Hidden"`) is active: restore `Humanoid.WalkSpeed = 16` and `Humanoid.JumpPower = 50`.

3. Global Input Handler for `TAB` and `ESC`:
   - `TAB` Key: Toggles seamlessly between Main Lobby HQ sidebar menu (`"Main"`) and Free Roam mode (`"Hidden"`, `CameraType = Custom`). Ignore `TAB` when typing in text input boxes (`UserInputService:GetFocusedTextBox() ~= nil`).
   - `ESC` Key:
     - If in a sub-window (`"Play"`, `"Loadout"`, `"Challenge"`, `"Settings"`), pressing `ESC` returns to `"Main"` (Main Lobby HQ sidebar menu).
     - If in `"Main"`, pressing `ESC` returns to `"Hidden"` (Free Roam).
     - If in `"Hidden"`, pressing `ESC` toggles back to `"Main"`.

4. Top-Bar Visual Prompt Banner:
   - Display a lightweight top-bar banner GUI in `LobbyUIController` / `LobbyTransitionController`:
     - Showing contextual keybind prompts: e.g. `[PRESS TAB FOR MENU]` in Free Roam mode, and `[TAB] Free Roam | [ESC] Back` when in menu modes.

5. Verification:
   - Run Rojo build verification command: `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` from project root (`c:\Users\tummala surya\Downloads\roblox`).
   - Document build command output and confirm build succeeds with exit code 0.
   - Write a detailed handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m2_m3_1\handoff.md` and update progress.md in your working directory.
