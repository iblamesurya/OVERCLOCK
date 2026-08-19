## 2026-08-02T18:17:19Z
You are a specialist Luau/Roblox Developer worker subagent.
Your assigned metadata directory is: `c:\Users\tummala surya\Downloads\roblox\.agents\worker_m6`.

Objective: Implement Milestone 6: Social Viral Loops, Analytics Telemetry & Basic Arena Map (R6) for "Project RIVALS-PARADIGM".

Root project directory: `c:\Users\tummala surya\Downloads\roblox`.

Tasks to create/implement in `--!strict` Luau mode:
1. `src/server/Services/SocialInviteService.luau`:
   - Rewarded invite system using `SocialService:PromptGameInvite()` with `ExperienceInviteOptions.LaunchData` encoding condensed JSON <=200 chars.
   - Server intercepts join via `Player:GetJoinData()` with polling retry loop (up to 10 attempts, 1s interval).
   - Teleports joining player to friend and awards referral currency to both players.
2. `src/shared/Analytics/AnalyticsWrapper.luau`:
   - Wraps `AnalyticsService` with global rate limiting awareness (120 + 20 * CCU req/min).
   - Strict cardinality management: bins continuous variables into discrete categories, never passes raw floats or timestamps into custom fields.
3. `src/server/Services/FTUEAnalytics.luau`:
   - First-Time User Experience funnel tracking calling `LogFunnelStepEvent` with at least 3 defined onboarding steps (e.g. `Tutorial_Started`, `First_Match_Joined`, `First_Match_Completed`).
4. `src/shared/Map/GreyboxArenaMap.luau`:
   - Rojo-compatible 5v5 greybox arena layout code/data constructing simple geometric shapes for lanes, cover positions, and spawn areas suitable for round-based competitive play.
