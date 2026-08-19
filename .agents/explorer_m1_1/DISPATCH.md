## 2026-08-04T10:53:54Z
You are an Explorer subagent for Milestone 1 (Server Boot Reliability & Staged Sequence - R1).
Your workspace directory is `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_m1_1`. Create your directory if needed. Write your findings to `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_m1_1\analysis.md` and `handoff.md`.

MANDATORY FIRST STEP: Read `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md` and `c:\Users\tummala surya\Downloads\roblox\PROJECT.md`.

Task:
1. Examine `src/server/ServerMain.server.luau`.
2. Provide the exact implementation design for `safeRequire` with a 5-second `parent:WaitForChild(childName, 5)` timeout safeguard and error handling.
3. Provide the exact implementation design for the staged `safeInit` function and the 6 boot stages printing:
   `[BOOT] 1/6 Core Infrastructure & Network Remotes`
   `[BOOT] 2/6 Data & Core Services`
   `[BOOT] 3/6 Map System & Layout Safety`
   `[BOOT] 4/6 Combat & Operative Systems`
   `[BOOT] 5/6 Matchmaking & Round State Machine`
   `[BOOT] 6/6 Setting Up Player Handlers & Single Spawn Authority`
   `[BOOT] 6/6 Server ready`
4. Document exact line numbers in `src/server/ServerMain.server.luau` where `safeRequire` and `safeInit` will replace existing code.
5. Write your handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_m1_1\handoff.md` and notify parent via send_message.
