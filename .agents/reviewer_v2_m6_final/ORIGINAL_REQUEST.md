## 2026-08-03T13:47:14Z
You are reviewer_v2_m6_final working in c:\Users\tummala surya\Downloads\roblox\.agents\reviewer_v2_m6_final.
Your task is to conduct code review and static analysis verification for Project RIVALS-PARADIGM v2:
1. Execute `selene src/` using run_command to verify 0 static analysis errors.
2. Execute `.\rojo.exe build default.project.json -o RivalsParadigm.rbxl` using run_command to verify 0 build errors and place file generation.
3. Inspect all Luau source files in `src/` to ensure full compliance with requirements R1-R5:
   - R1: Dedicated Main Lobby, spawn Y=100, safety baseplate Y=95, ProfileServiceWrapper fallback, CoreGui disable retry loop, valid Roblox fonts (`Gotham`/`GothamBold`).
   - R2: Matchmaking & Queue Selection (1v1 / 2v2), 5-map voting phase, match teleportation.
   - R3: Direct player 1v1 challenge leaderboard UI, modal accept/decline, 15s timer, duel arena teleportation.
   - R4: 5 distinct structured maps with environment props/foliage (Forest Outpost, Urban Warehouse, Desert Ruins, Cyber Arena, Classic Greybox FPS), and all arena map spawn locations have `Enabled = false` while in lobby.
   - R5: Combat & UI Integration, `HUDController` Lobby vs Match HUD state isolation.
4. Document all findings and test/build commands & results in `c:\Users\tummala surya\Downloads\roblox\.agents\reviewer_v2_m6_final\handoff.md`.
5. Send a message to parent with your verdict and findings.
