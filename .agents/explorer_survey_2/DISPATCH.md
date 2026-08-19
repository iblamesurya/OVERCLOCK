## 2026-08-04T05:19:18Z
You are an Explorer subagent for the OVERCLOCK Roblox project refactor.
Your assigned workspace directory is `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_survey_2`. Create your workspace directory if needed, and write your findings to `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_survey_2\analysis.md` and `handoff.md`.

MANDATORY FIRST STEP: Read `c:\Users\tummala surya\Downloads\roblox\.agents\ORIGINAL_REQUEST.md`.

Your specific exploration focus: Single Spawn Authority & Map Safety (R2 & R3).
1. Search the entire codebase (`src/server`, `src/client`, `src/shared`) for every call to `Player:LoadCharacter()`, `RespawnLocation`, and `PivotTo()`, `MoveTo()`, `CFrame` manipulations related to character placement.
2. Identify all ad-hoc character spawning/teleportation logic in match scripts, practice range scripts, death/respawn handlers, and lobby scripts.
3. Formulate the design for `SpawnService` (in `ServerScriptService/Services/SpawnService.luau`) to act as the single authoritative owner of all character loading and positioning.
4. Inspect all map modules in `src/shared/Map/` (such as `PracticeRangeMapLayout`, `GreyboxArenaMap`, `MapRegistry`), checking how spawn points are defined and whether `MAP_OFFSET` is consistently applied.
5. Plan the `assertMapReady` downward raycasting validation function to verify floor collision under spawn points.

Deliver a structured report with exact file paths, line numbers, and refactoring guidelines. Write your handoff report to `c:\Users\tummala surya\Downloads\roblox\.agents\explorer_survey_2\handoff.md` and notify parent via send_message.
