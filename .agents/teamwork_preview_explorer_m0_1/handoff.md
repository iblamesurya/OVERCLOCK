# Handoff Report — Explorer 1 (Milestone 0)

## 1. Observation
Direct observations gathered during analysis of client UI scripts (`src/client/UI/` and `src/client/Controllers/`):

1. **`LobbyUIController.luau`**:
   - Lines 30–55: `CAMERA_PRESETS` defined for states `"Main"`, `"Play"`, `"Challenge"`, `"Loadout"`, `"Settings"`, `"Hidden"`.
   - Lines 97 & 408: `camera.CameraType = Enum.CameraType.Scriptable` used when tweening camera in `SetCameraTarget`.
   - Lines 271–276: `TAB` key bound to `LobbyUIController.ToggleFreeRoam()`. `ESC` key is **not bound anywhere**.
   - Lines 380–397: `backBtn` ("BACK") connected to `SetState("Main")`.
   - Lines 489–494: `SetState("Play")` attempts to call `MatchmakingQueueUI.ShowQueuePanel()` and `MatchmakingQueueUI.HideQueuePanel()`.
   - Lines 509–526: `ToggleFreeRoam()` switches state between `"Main"` and `"Hidden"`, restoring `camera.CameraType = Enum.CameraType.Custom` when `"Hidden"`.
   - Lines 440–507: Character movement speed/jumping is **never modified or disabled** when opening lobby menus.

2. **`MatchmakingQueueUI.luau`**:
   - Lines 646–658: Exported public table contains `Initialize`, `UpdateVoteResults`, `VoteForMap`, `ShowMatchFound`, `CancelQueue`, `StartQueue`.
   - `MatchmakingQueueUI.luau` **does NOT export or define** `ShowQueuePanel()` or `HideQueuePanel()`.
   - `QueuePanel` has no `BACK` or `✕` close button.

3. **`LoadoutInspectorUI.luau`**:
   - Lines 651–674: `closeBtn` ("✕") connected to `LoadoutInspectorUI.Hide()` and `LobbyUIController.ShowMainLobbyMenu()`.
   - Lines 680–708: Exports `Show()`, `Hide()`, `IsVisible()`.

4. **`PlayerListChallengeUI.luau`**:
   - Lines 170–177 & 218–239: Minimize button ("—") connected to `ToggleVisibility()`.
   - Operates independently of `LobbyUIController` modal state.

5. **`ChallengeInviteModal.luau`**:
   - Lines 31–51 & 54–112: `Hide()` and `ShowInvite()` handle incoming duel requests with 15s timer.

6. **`LobbyTransitionController.luau`**:
   - Lines 90–166 & 168–235: `TransitionToMatch()` and `TransitionToLobby()` manage full screen fade and blur (Size 28 to 0/12).

7. **`ClientMain.client.luau`**:
   - Lines 69–74: Initializes all UI controllers.
   - Lines 81–83: Calls `HUDController.SetHUDMode("Lobby")` and `LobbyUIController.ShowMainLobbyMenu()`.

---

## 2. Logic Chain

1. **Missing Method Bug**:
   - *Observation*: `LobbyUIController.luau` calls `MatchmakingQueueUI.ShowQueuePanel()` and `MatchmakingQueueUI.HideQueuePanel()` at lines 489–494. `MatchmakingQueueUI.luau` exports only `Initialize`, `UpdateVoteResults`, `VoteForMap`, `ShowMatchFound`, `CancelQueue`, `StartQueue` (lines 646–658).
   - *Reasoning*: Because `ShowQueuePanel` and `HideQueuePanel` do not exist on `MatchmakingQueueUI`, calling `LobbyUIController.SetState("Play")` fails silently inside the `pcall` block. The matchmaking UI panel is never revealed upon clicking "▶ PLAY MATCH".

2. **Keybind & Navigation Void**:
   - *Observation*: `TAB` key is handled in `LobbyUIController.luau` (lines 271–276), but `ESC` key is missing from all UI files. `MatchmakingQueueUI` lacks a Close button.
   - *Reasoning*: Without an `ESC` listener or Close button on `MatchmakingQueueUI`, players who enter sub-windows cannot close them using standard Roblox FPS keybind conventions. `ESC` instead defaults to Roblox system pause menu over open custom modals.

3. **Background Character Movement**:
   - *Observation*: `LobbyUIController.luau` sets `CameraType = Scriptable` (line 97, 408) but does not alter `Humanoid.WalkSpeed` or disable player controls during menu states.
   - *Reasoning*: Players using WASD keys while navigating lobby UI menus walk their character around in the 3D space out of view, causing character misalignment when switching to Free Roam mode.

4. **Lack of Single-Active Modal Enforcement**:
   - *Observation*: `LoadoutInspectorUI`, `PlayerListChallengeUI`, and `MatchmakingQueueUI` each manage their own ScreenGui visibility independently without mutual exclusion checks.
   - *Reasoning*: If `LoadoutInspectorUI` is opened while `PlayerListChallengeUI` or `MatchmakingQueueUI` is active, windows overlap on screen without hiding lower-priority UI.

---

## 3. Caveats

- **Server-side validation**: This analysis focused strictly on client UI and transition controllers. Server-side queueing (`QueueMatchmakingService.luau`) and 1v1 duel handling (`DirectChallengeService.luau`) were not analyzed in depth as they are out of scope for client UI state machine design.
- **Assumptions**: Assumed standard Roblox `Humanoid.WalkSpeed` (16) and `JumpPower` (50) for free-roam movement toggle.

---

## 4. Conclusion

The current client UI framework contains solid visual presets and 3D preview rendering, but is hindered by three major flaws:
1. **Broken `Play` navigation** caused by missing `ShowQueuePanel`/`HideQueuePanel` methods in `MatchmakingQueueUI.luau`.
2. **Missing `ESC` keybind router** and lack of Close button on `MatchmakingQueueUI`.
3. **Unrestricted background character movement** during menu camera modes.

Implementing a **Single-Active-Modal State Machine** in `LobbyUIController.luau` alongside standardized `.Show()`, `.Hide()`, and `.IsVisible()` APIs across all UI modules will eliminate UI stacking, enable smooth `BACK`/`✕`/`ESC` navigation, and seamlessly integrate UI collapse with free-roam camera and movement mechanics.

---

## 5. Verification Method

1. **Code Inspection**:
   - Inspect `src/client/UI/LobbyUIController.luau` (lines 485–507) using `view_file` to confirm `ShowQueuePanel` and `HideQueuePanel` calls.
   - Inspect `src/client/UI/MatchmakingQueueUI.luau` (lines 646–658) using `view_file` to verify exported methods.
2. **Keybind Audit**:
   - Check `src/client/UI/` files for `Enum.KeyCode.Escape` using `view_file` to confirm absence of `ESC` key handling.
3. **Invalidation Conditions**:
   - If `MatchmakingQueueUI` already exported `ShowQueuePanel` or if `ESC` key handling was present in another controller, this finding would be invalidated. `view_file` confirmed both are missing.

