# Orchestration Context

## Workspace
- Root: `c:\Users\tummala surya\Downloads\roblox`
- Source Root: `c:\Users\tummala surya\Downloads\roblox\src`
- Project file: `default.project.json`

## Requirements Mapping
- R1: Server Boot Reliability -> `src/server/ServerMain.server.luau`
- R2: Single Spawn Authority -> `src/server/Services/SpawnService.luau` & refactoring callers
- R3: Map Validation & Layout Safety -> `src/shared/Map/`, `PracticeRangeMapLayout.luau`, `GreyboxArenaMap.luau`
- R4: Network Security & Remotes -> `src/shared/Network/`, `ReplicatedStorage/Network/Remotes`
- R5: Structural Reorganization -> `src/shared/`, `src/server/`, `src/client/`
- R6: Startup Smoke Test -> `src/server/Tests/StartupSmokeTest.luau`

## Subagent Allocations & Directories
- All agent workspaces created under `.agents/<type>_<milestone>`
