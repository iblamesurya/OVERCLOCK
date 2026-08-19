# BRIEFING — 2026-08-03T20:44:47Z

## Mission
Implement Milestone 7 (M7_DataStore_Safety) for Project OVERCLOCK: robust DataStore safety, exponential backoff retries, session locking, periodic autosave, non-blocking join fallback, and unit tests.

## 🔒 My Identity
- Archetype: implementer / qa / specialist
- Roles: implementer, qa, specialist
- Working directory: c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_worker_m7
- Original parent: 31a40667-b235-4c14-8cc2-fdb367edac3a
- Milestone: M7_DataStore_Safety

## 🔒 Key Constraints
- Exclusive file write ownership:
  - `src/server/Services/ProfileServiceWrapper.luau`
  - `src/server/Services/ProfileServiceWrapper.spec.luau`
  - `src/server/ServerMain.server.luau` (DataStore failure non-blocking join fallback logic)
- Integrity Mandate: Genuine implementation, no hardcoding, no cheating.
- Non-blocking DataStore failure handling (Requirement R6 fix): DO NOT kick player on DataStore failure, fallback to default profile in-memory.
- Data template structure with required keys: `Level`, `XP`, `Credits`, `OwnedCosmetics`, `EquippedSkins`, `SelectedOperative`, `MatchStats` (Kills, Deaths, Wins, Losses).
- Exponential backoff retry logic: `math.pow(2, attempt - 1)`.
- Session locking & 60s periodic autosave interval.
- Save on `PlayerRemoving` and global `game:BindToClose` shutdown handler.

## Current Parent
- Conversation ID: 31a40667-b235-4c14-8cc2-fdb367edac3a
- Updated: 2026-08-03T20:44:47Z

## Task Summary
- **What to build**: Full DataStore safety system in ProfileServiceWrapper, non-blocking player join in ServerMain, and comprehensive test suite in ProfileServiceWrapper.spec.luau.
- **Success criteria**: All specs pass, Selene passes with zero warnings, Rojo build succeeds, player joins cleanly on DataStore failure with default profile in-memory.
- **Interface contracts**: PROJECT.md and explorer analysis.md
- **Code layout**: src/server/Services/ProfileServiceWrapper.luau, src/server/Services/ProfileServiceWrapper.spec.luau, src/server/ServerMain.server.luau

## Change Tracker
- **Files modified**: [TBD]
- **Build status**: [TBD]
- **Pending issues**: None

## Quality Status
- **Build/test result**: [TBD]
- **Lint status**: [TBD]
- **Tests added/modified**: [TBD]

## Loaded Skills
- None loaded yet.

## Key Decisions Made
- Initializing briefing and workspace setup.

## Artifact Index
- `.agents/teamwork_preview_worker_m7/DISPATCH.md` — Dispatch task instructions
- `.agents/teamwork_preview_worker_m7/BRIEFING.md` — Working state & memory
