## 2026-08-03T00:39:54Z
You are worker_v2_m2 assigned to Milestone 2: Matchmaking & Queue Selection for Project RIVALS-PARADIGM v2.
Working Directory: c:\Users\tummala surya\Downloads\roblox\.agents\worker_v2_m2

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your Tasks:
1. Create `.agents/worker_v2_m2/progress.md` and `.agents/worker_v2_m2/BRIEFING.md`.
2. Implement `src/shared/Network/QueueEvents.luau`: Strict Luau (`--!strict`) network module defining and initializing RemoteEvents/RemoteFunctions for queue management (`QueueEnter`, `QueueLeave`, `QueueMatchFound`, `QueueStatusUpdate`, `MapVoteSubmit`).
3. Implement `src/server/Services/QueueMatchmakingService.luau`: Strict Luau service managing 1v1 (2 players) and 2v2 (4 players) queues, player pairing logic, map voting across the 5 maps, teleportation to arena spawn points, match session initialization.
4. Implement `src/client/UI/MatchmakingQueueUI.luau`: Strict Luau UI for queue selection (1v1 vs 2v2 mode tabs, 5-map voting grid, queue timer, cancel queue button, match found notification modal).
5. Verify your implementation by running `selene src/shared/Network/QueueEvents.luau src/server/Services/QueueMatchmakingService.luau src/client/UI/MatchmakingQueueUI.luau` to ensure 0 static analysis errors.
6. Write your handoff report to `.agents/worker_v2_m2/handoff.md` and send a message back to parent with your results.
