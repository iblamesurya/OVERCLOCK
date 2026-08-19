## 2026-08-04T10:54:39Z
Task: Refactor src/server/ServerMain.server.luau for Milestone 1 (Server Boot Reliability & Staged Sequence - R1).
1. Replace safeRequire with 5-second WaitForChild timeout version. Log [BOOT ERROR] on timeout/failure.
2. Implement staged safeInit(name: string, fn: () -> ()) helper wrapped in pcall/task.spawn handling errors cleanly.
3. Organize boot sequence into 6 explicit stages with exact print strings.
4. Run Rojo build command to verify 0 build errors.
5. Write handoff report and notify parent.
