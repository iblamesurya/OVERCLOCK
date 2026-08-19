---
name: overclock-movement-stack
description: Humanoid-compatible 60Hz FPS movement with server-authoritative validation for OVERCLOCK.
---

# OVERCLOCK Movement Stack

Use when touching `MovementController.luau`, `FPSMovementController.luau`, `FPSMovementConfig.luau`, `FPSMovementKernel.luau`, `FPSMovementInput.luau`, `MovementAuthority.luau`, `MovementAuthorityBootstrap.luau`, `CombatServer.luau` movement path, `SpawnService.luau` teleports, or `MobileControlsController.luau` sprint/crouch/slide.

## State model (kernel `FPSMovementKernel.luau`)

`Idle | Run | Sprint | Crouch | Slide | Air | Disabled` + `Jump`. Kernel is pure (no services/remotes/task). Client owns presentation, server owns truth.

## Authority boundary

**Client may send** `MovementIntent` unreliable only: `{sequence:int, moveX:[-1,1], moveZ:[-1,1], sprint:bool, crouch:bool, slide:bool, jump:bool}` at 10 Hz heartbeat + state edge, rate-limited 16/s. Never position/velocity/CFrame/timestamp/damage/range.

**Server owns** `MovementAuthority.luau` sampling `HumanoidRootPart` at 20 Hz via single `Heartbeat`, owns `ServerMovementState/ServerIsSprinting` etc, corrects via `lastSafeCFrame`, uses `Workspace:GetServerTimeNow()` for snapshots → `CombatServer:UpdatePlayerSpatial(userId, position, velocity, cframe, timestamp)`.

## Client integration

1. Config `ReplicatedStorage/Physics/FPSMovementConfig.luau` — single tuning: Run 16 / Sprint 24 / Crouch 8, GroundAccel 95 / AirAccel 24, Friction 42 / SlideFriction 7.5, JumpSpeed 52 cut 0.48, buffer 0.12s coyote 0.10s, slide thr 18 dur 0.82s, max slope 46°.
2. Kernel `ReplicatedStorage/Physics/FPSMovementKernel.luau` — `New/Reset/Step(state,now,dt,input,ground,observedVel,gravity)` returns `movementState/horizontalVelocity/targetWalkSpeed/stamina/jumpVelocity/applyJumpCut/isCrouching/isSprinting/isSliding`.
3. Input `FPSMovementInput.luau` — Sprint LeftShift/ButtonL3, Crouch C/Ctrl/ButtonB toggle, Jump Space/ButtonA; `SetExternalAction("Sprint|Crouch|Jump")`, `SetCrouch(active)`.
4. Controller `FPSMovementController.luau` — one `RenderStepped`, capped 60 Hz accumulator (`FixedStep 1/60 MaxCatchUp 4`), one raycast `GroundProbeDistance 4.35` per fixed step, `HipHeight*0.58` + `CameraOffset` crouch, `MovementIntent` unreliable bounded intent only, retire `SpatialStateSync`.

## Server integration

1. Unreliable `MovementIntent` via `RemoteEvents.Initialize()` allow-list.
2. `MovementAuthorityBootstrap.Attach(combatServer)` in `CombatServer.InitializeNetworkListeners` after `RemoteEvents.Initialize()` — creates authority, `SetSnapshotSink(UpdatePlayerSpatial)`, `Register` on `CharacterAdded`, `Start()` shared heartbeat.
3. Remove old `SpatialStateSync` listener (client pos/vel/`os.clock`).
4. Teleports: `SpawnService.luau` / void rescue `PivotTo` → `require(ServerScriptService.Combat.MovementAuthority).NotifyActiveTeleport(player)` (not `MovementValidator`). Grants `1.25s` grace.
5. Keep `MovementValidator` only if other callers need it; not source of snapshots.

## Mobile

`MobileControlsController.BindCombatActions({onSprint→SetMobileAction("Sprint"), onCrouch→SetMobileAction("Crouch"), onJump→SetMobileAction("Jump")})`. Crouch press while sprint+fast = slide attempt.

## Verification

* One controller writes `Humanoid:Move/WalkSpeed` — not both.
* Buffered/coyote jump once, no double jump; slide needs 18 speed, ends timer/low speed, slope adds `SlopeGravityScale 0.28`.
* Teleport/void rescue no false correction.
* Flood `MovementIntent` with NaN/oversize/stale sequence/>16/s → ignored.
* `muse skills validate .agents/skills/overclock-movement-stack --json` passes.
