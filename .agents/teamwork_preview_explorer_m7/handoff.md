# Handoff Report: Milestone 7 (M7_DataStore_Safety) Explorer Analysis

## 1. Observation
- **`src/server/Services/ProfileServiceWrapper.luau`**:
  - `GetDefaultProfile` (lines 67–117): Provides `level`, `experience`, `rankRating`, `rankTier`, `currencies`, `stats`, `equippedLoadout`, `inventory`, `unlockedClasses`, `settings`. Missing explicit top-level M7 required schema keys: `Level`, `XP`, `Credits`, `OwnedCosmetics`, `EquippedSkins`, `SelectedOperative`, `MatchStats` (Kills, Deaths, Wins, Losses).
  - `LoadProfileAsync` (lines 207–309): Contains retry loop up to `MAX_RETRY_ATTEMPTS = 5` with fixed `task.wait(2)` (line 294) and early Studio break `if RunService:IsStudio() then break end` (line 289–291), bypassing exponential backoff retry logic.
  - Periodic autosave loop (lines 357–406): Spawns 60-second heartbeat thread updating session lock timestamp and saving profile envelope.
  - Shutdown persistence: Lacks global `game:BindToClose` registration to flush active profiles on server termination.
- **`src/server/ServerMain.server.luau`**:
  - `onPlayerAdded` DataStore load handling (lines 166–175):
    ```luau
    local profile = ProfileServiceWrapper.LoadProfileAsync(player.UserId)
    if profile then
        playerProfiles[player.UserId] = profile
        print("[ServerMain] Profile loaded for player " .. player.Name .. " (" .. tostring(player.UserId) .. ")")
    else
        warn("[ServerMain] Failed to load profile for player " .. player.Name .. " (" .. tostring(player.UserId) .. ")")
        player:Kick("Failed to load your data. Please rejoin.")
    end
    ```
    Directly violates Requirement R6 ("DataStore failures must never block player join").
- **Remote Security in Services**:
  - `src/server/Services/EconomyService.luau` (lines 285–300): Validates `itemId` type and balance, but needs explicit input sanitization and verification of Buy phase state.
  - Remotes in `QueueEvents.luau`, `ChallengeEvents.luau`, `RemoteEvents.luau`, and `CombatServer.luau`: Remote calls require explicit type checks and NaN vector sanitization.

---

## 2. Logic Chain
1. **Observation 1** shows that `GetDefaultProfile` in `ProfileServiceWrapper.luau` lacks top-level fields (`Level`, `XP`, `Credits`, `OwnedCosmetics`, `EquippedSkins`, `SelectedOperative`, `MatchStats`). Adding these fields directly to the default profile template guarantees full compatibility with M7 requirements and shop/operative services.
2. **Observation 2** shows that `ProfileServiceWrapper.luau` lacks true exponential backoff retries and early-breaks in Studio. Implementing `math.pow(2, attempt - 1)` backoff delay without Studio short-circuiting ensures robust retry behavior before falling back to in-memory defaults.
3. **Observation 3** shows that `ServerMain.server.luau:173` kicks players when DataStore loading fails. Removing `player:Kick` and assigning a default in-memory profile ensures compliance with Requirement R6, allowing clean player joins even during DataStore outages.
4. **Observation 4** shows that adding a `game:BindToClose` callback in `ProfileServiceWrapper.luau` guarantees all active player profiles save and release session locks before server shutdown.
5. **Observation 5** shows that network remote listeners across economy, cosmetic skin equips, operative abilities, and combat hit reporting require server-authoritative validation (type checks, phase checks, balance checks, cooldown tracking, and vector sanitization) to prevent client spoofing.

---

## 3. Caveats
- DataStore API calls in local Roblox Studio require "Enable Studio Access to API Services" to hit live DataStores; in-memory fallback will automatically kick in if disabled, which is expected behavior for offline testing.
- No other caveats.

---

## 4. Conclusion
Worker 7 can execute Milestone 7 implementation by updating `src/server/Services/ProfileServiceWrapper.luau` (template schema, exponential backoff retries, `BindToClose` handler) and `src/server/ServerMain.server.luau` (non-blocking fallback join), and enforcing server-side validation rules on network remotes as specified in `analysis.md`.

---

## 5. Verification Method
1. **Source Code Inspection**:
   Inspect `src/server/Services/ProfileServiceWrapper.luau` and `src/server/ServerMain.server.luau` to confirm top-level schema keys, exponential backoff retry math, `BindToClose` implementation, and removal of `player:Kick`.
2. **Offline DataStore Fallback Verification**:
   Boot server with DataStore API disabled. Confirm player joins cleanly, receives default in-memory profile, and is not kicked.
3. **Automated Test Verification**:
   Execute `rojo build default.project.json -o RivalsParadigm.rbxl` and run test suite `src/server/Services/ProfileServiceWrapper.spec.luau`.
