## 2026-08-02T18:17:19Z
You are a specialist Luau/Roblox Developer worker subagent.
Your assigned metadata directory is: `c:\Users\tummala surya\Downloads\roblox\.agents\worker_m3`.

Objective: Implement Milestone 3: Backend Persistence, Matchmaking & Economy (R3) for "Project RIVALS-PARADIGM".

Root project directory: `c:\Users\tummala surya\Downloads\roblox`.

Tasks to create/implement in `--!strict` Luau mode:
1. `src/server/Services/ProfileServiceWrapper.luau`:
   - Session-locking wrapper around DataStoreService (ProfileService pattern).
   - Atomic `UpdateAsync` transactions.
   - `JobId`-based session locking with 60-second heartbeat refresh loop.
   - 30-minute lease timer deadlock resolution logic.
   - Data sanitization stripping `NaN`, converting `Vector3` to plain array `{x, y, z}`, rejecting mixed-type keys or cyclic references.
2. `src/server/Services/MatchmakingCoordinator.luau`:
   - `MemoryStoreService` `SortedMap` matchmaking structures.
   - Coordinator server election protocol via atomic write to a control key. Only coordinator executes complex sorting/teleportation.
   - Deterministic sharding logic to distribute player queue across parallel maps when volume exceeds partition limits.
3. `src/server/Services/ReceiptProcessor.luau`:
   - Global `MarketplaceService.ProcessReceipt` callback handler.
   - Player presence verification.
   - Idempotency via `UserId_PurchaseId` hash checked against dedicated DataStore using `UpdateAsync`.
   - Correct `Enum.ProductPurchaseDecision.NotProcessedYet` and `Enum.ProductPurchaseDecision.PurchaseGranted` return values.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

When finished:
1. Write a comprehensive report to `c:\Users\tummala surya\Downloads\roblox\.agents\worker_m3\handoff.md`.
2. Send a message to the caller (parent) with a summary of work completed and the handoff file path.
