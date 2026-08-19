# Milestone 7 Analysis & Implementation Specification: DataStore Safety & Server Security

## 1. Overview & Executive Summary

This report establishes the technical investigation and concrete file implementation specification for **Worker 7 (Implementer)** to complete **Milestone 7 (M7_DataStore_Safety)** in Project OVERCLOCK. 

The primary objectives of Milestone 7 are:
1. Enforce robust Roblox DataStore persistence in `ProfileServiceWrapper.luau` with session locking, exponential backoff retries, periodic 60s autosaving, and shutdown saving (`BindToClose`).
2. Fix the Requirement R6 violation in `ServerMain.server.luau` where players are kicked on DataStore load failures, replacing it with a non-blocking in-memory fallback profile assignment so players join cleanly.
3. Validate server-side security across all RemoteEvents and RemoteFunctions (economy purchases, cosmetic skin equips, operative abilities, queue matchmaking, and combat hit reporting).

---

## 2. Current State Analysis

### 2.1 `ProfileServiceWrapper.luau` Analysis
- **Profile Data Template**:
  - Existing `GetDefaultProfile` returns legacy fields (`level`, `experience`, `rankRating`, `currencies`, `stats`, `equippedLoadout`, `inventory`, `unlockedClasses`, `settings`).
  - **Defect**: Missing direct top-level fields explicitly required by OVERCLOCK M7: `Level`, `XP`, `Credits`, `OwnedCosmetics`, `EquippedSkins`, `SelectedOperative`, `MatchStats` (Kills, Deaths, Wins, Losses).
- **DataStore & Retry Logic**:
  - Uses fixed 2-second retry delays (`RETRY_DELAY_SECONDS = 2`) up to `MAX_RETRY_ATTEMPTS = 5`.
  - **Defect**: Contains `if RunService:IsStudio() then break end` which prematurely terminates retry loops in Roblox Studio, skipping exponential backoff and jumping straight to unmanaged fallbacks without consistent structure.
- **Session Locking & Heartbeat**:
  - Implements session envelope (`SessionLock` with `JobId`, `SessionId`, `Timestamp`) and 30-minute deadlock lease resolution.
  - Spawns a 60s heartbeat loop (`HEARTBEAT_INTERVAL_SECONDS = 60`) to touch timestamps and save data.
- **Shutdown Persistence (`BindToClose`)**:
  - **Defect**: Lacks a `game:BindToClose` handler or global profile registration tracking to guarantee that active profiles save and release session locks synchronously before server process termination.

### 2.2 `ServerMain.server.luau` Analysis
- **Player Lifecycle & DataStore Load**:
  - Lines 166-175:
    ```luau
    local profile = ProfileServiceWrapper.LoadProfileAsync(player.UserId)
    if profile then
        playerProfiles[player.UserId] = profile
    else
        player:Kick("Failed to load your data. Please rejoin.") -- CRITICAL VIOLATION!
    end
    ```
  - **Defect (R6 Violation)**: Kicking players on DataStore failure directly violates Requirement R6 ("DataStore failures must never block player join"). Players must be assigned an in-memory fallback profile and allowed into the lobby cleanly.

### 2.3 RemoteEvents & RemoteFunctions Security Analysis
- `EconomyService.luau` handles `RequestPurchase` with credit checks and buy-phase checks, but needs explicit input sanitization (`typeof(itemId) == "string"`).
- Operative abilities, agent selection, and cosmetic skin equipping require clear server-side validation contracts to prevent client-side spoofing, negative credit balance exploits, or invalid state mutations.
- `CombatServer.luau` and `HitValidation.luau` correctly calculate damage server-side with rollback verification, but spatial input vectors (`origin`, `direction`) need strict `NaN` and `Inf` checking.

---

## 3. Implementation Specification for Worker 7

Worker 7 must modify `src/server/Services/ProfileServiceWrapper.luau` and `src/server/ServerMain.server.luau`, as specified below.

---

### Task 1: Update `src/server/Services/ProfileServiceWrapper.luau`

#### A. Expand Profile Data Template
Update `ProfileServiceWrapper.GetDefaultProfile(userId, username)` to provide all required M7 top-level fields alongside backward-compatible aliases:

```luau
function ProfileServiceWrapper.GetDefaultProfile(userId: number, username: string?): Types.PlayerProfile
    return {
        userId = userId,
        username = username or ("Player_" .. tostring(userId)),
        
        -- M7 Required Top-Level Schema Fields
        Level = 1,
        XP = 0,
        Credits = 500,
        OwnedCosmetics = { "DefaultSkin_AR", "DefaultSkin_Pistol" },
        EquippedSkins = {
            ["AssaultRifle"] = "DefaultSkin_AR",
            ["Sidearm"] = "DefaultSkin_Pistol",
        },
        SelectedOperative = "Vex",
        MatchStats = {
            Kills = 0,
            Deaths = 0,
            Wins = 0,
            Losses = 0,
            Assists = 0,
            Headshots = 0,
            MatchesPlayed = 0,
        },

        -- Supplementary / Backward Compatibility Fields
        level = 1,
        experience = 0,
        rankRating = 1000,
        rankTier = "Bronze I",
        currencies = {
            credits = 500,
            gems = 0,
            eventTokens = 0,
        },
        stats = {
            kills = 0,
            deaths = 0,
            assists = 0,
            wins = 0,
            losses = 0,
            headshots = 0,
            totalDamageDealt = 0,
            playtimeSeconds = 0,
            matchesPlayed = 0,
            accuracyRatio = 0,
        },
        equippedLoadout = {
            primaryWeaponId = "Rifle_Assault_01",
            secondaryWeaponId = "Pistol_Standard_01",
            meleeWeaponId = "Knife_Tactical_01",
            tacticalGadgetId = "Smoke_Grenade",
            lethalGadgetId = "Frag_Grenade",
            perkIds = {},
            weaponSkins = {},
        },
        inventory = {
            ["Rifle_Assault_01"] = true,
            ["Pistol_Standard_01"] = true,
            ["Knife_Tactical_01"] = true,
        },
        unlockedClasses = { "Assault", "Recon" },
        settings = {
            mouseSensitivity = 1.0,
            fov = 90,
            crosshairColor = "#FFFFFF",
            soundVolume = 1.0,
            musicVolume = 0.8,
        },
        schemaVersion = 1,
        lastLoginTimestamp = os.time(),
    }
end
```

#### B. Exponential Backoff Retry Logic
In `LoadProfileAsync`, replace fixed delay loops and Studio short-circuits with an exponential backoff loop wrapped in `pcall`:

```luau
local BASE_RETRY_DELAY_SECONDS = 1
local MAX_RETRY_ATTEMPTS = 5

-- Inside LoadProfileAsync loop:
for attempt = 1, MAX_RETRY_ATTEMPTS do
    local success, resultErr = pcall(function()
        -- DataStore UpdateAsync with session locking
    end)

    if success and verifyLock() then
        loadedEnvelope = verifyEnvelope
        break
    else
        local delay = math.min(16, BASE_RETRY_DELAY_SECONDS * math.pow(2, attempt - 1))
        warn(string.format("[ProfileServiceWrapper] Attempt %d/%d failed for userId %d: %s. Retrying in %ds...", 
            attempt, MAX_RETRY_ATTEMPTS, userId, tostring(resultErr), delay))
        task.wait(delay)
    end
end
```

If all `MAX_RETRY_ATTEMPTS` fail, return an active in-memory profile initialized with default data:
```luau
if not loadedEnvelope then
    warn("[ProfileServiceWrapper] DataStore unavailable or session lock failed for userId " .. tostring(userId) .. ". Utilizing in-memory fallback profile.")
    loadedEnvelope = {
        Data = defaultData or ProfileServiceWrapper.GetDefaultProfile(userId),
        Lock = {
            JobId = currentJobId,
            SessionId = sessionId,
            Timestamp = os.time(),
        },
        SchemaVersion = 1,
        LastSaved = os.time(),
    }
end
```

#### C. Session Locking & 60s Periodic Autosave
Maintain active profiles table `activeProfiles[userId] = profile`.
In the 60-second background thread (`HEARTBEAT_INTERVAL_SECONDS = 60`), automatically invoke `SaveProfileData(profile)` to flush mutated profile data (`Level`, `XP`, `Credits`, `MatchStats`, etc.) to Roblox DataStore wrapped in `pcall`.

#### D. Save on `PlayerRemoving` and `BindToClose`
Register a module-level `game:BindToClose` handler in `ProfileServiceWrapper.luau`:

```luau
local activeProfiles: { [number]: Profile } = {}

-- Track active profiles upon load
function ProfileServiceWrapper.RegisterActiveProfile(userId: number, profile: Profile)
    activeProfiles[userId] = profile
end

function ProfileServiceWrapper.UnregisterActiveProfile(userId: number)
    activeProfiles[userId] = nil
end

-- BindToClose shutdown flush handler
game:BindToClose(function()
    print("[ProfileServiceWrapper] Server shutting down. Saving all active player profiles...")
    local threads = {}
    for userId, profile in pairs(activeProfiles) do
        table.insert(threads, task.spawn(function()
            pcall(function()
                profile:SaveAsync()
                profile:ReleaseAsync()
            end)
        end))
    end
    
    local start = os.clock()
    while next(activeProfiles) ~= nil and (os.clock() - start < 10) do
        task.wait(0.1)
    end
    print("[ProfileServiceWrapper] Shutdown save complete.")
end)
```

---

### Task 2: Update `src/server/ServerMain.server.luau`

#### Non-Blocking DataStore Join Handling (Fix R6 Violation)
Update `onPlayerAdded` in `ServerMain.server.luau` to guarantee that players are never kicked on DataStore load failure:

```luau
local function onPlayerAdded(player: Player)
    DirectChallengeService.SetPlayerStatus(player, "In Lobby")
    setPlayerRespawnToLobby(player)

    task.spawn(function()
        local profile = ProfileServiceWrapper.LoadProfileAsync(player.UserId)
        if not profile then
            warn("[ServerMain] Profile load returned nil for " .. player.Name .. " (" .. tostring(player.UserId) .. "). Constructing in-memory fallback profile.")
            local defaultData = ProfileServiceWrapper.GetDefaultProfile(player.UserId, player.Name)
            profile = ProfileServiceWrapper.CreateInMemoryFallback(player.UserId, defaultData)
        end

        playerProfiles[player.UserId] = profile
        ProfileServiceWrapper.RegisterActiveProfile(player.UserId, profile)
        print("[ServerMain] Profile initialized cleanly for player " .. player.Name .. " (" .. tostring(player.UserId) .. ")")
    end)

    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)

    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end
```

On `onPlayerRemoving`:
```luau
local function onPlayerRemoving(player: Player)
    combatServerInstance:UnregisterPlayer(player.UserId)

    local profile = playerProfiles[player.UserId]
    if profile then
        pcall(function()
            profile:SaveAsync()
            profile:ReleaseAsync()
        end)
        ProfileServiceWrapper.UnregisterActiveProfile(player.UserId)
        playerProfiles[player.UserId] = nil
        print("[ServerMain] Saved and released profile for player " .. player.Name)
    end
end
```

---

### Task 3: Server-Side Remote Security Validation Specification

Worker 7 must verify and enforce strict server-side validation rules across all RemoteEvent / RemoteFunction handlers:

1. **Credits & Shop Purchases (`RequestPurchase`)**:
   - **Type Enforcement**: Check `typeof(itemId) == "string"`.
   - **Mode Enforcement**: Practice Range mode bypasses economy (all items free).
   - **Phase Enforcement**: In PvP, purchases are strictly rejected if `RoundService.GetPlayerPhase(player) ~= "Buy"`.
   - **Catalog Check**: Validate `itemId` exists in `EconomyService.SHOP_CATALOG`. Rejects unknown items with `"InvalidItem"`.
   - **Balance Validation**: Check `playerBalances[player.UserId] >= item.price`. Rejects purchases if balance is insufficient (`"InsufficientCredits"`).
   - **State Mutation**: Server deducts credits and assigns item attribute before notifying client (`PurchaseResult`).

2. **Cosmetic Skins & Purchases (`PurchaseCosmetic` / `EquipSkin`)**:
   - **Type Enforcement**: Validate `typeof(skinId) == "string"` and `typeof(weaponCategory) == "string"`.
   - **Ownership Validation**: For equip requests, verify `table.find(profile.Data.OwnedCosmetics, skinId) ~= nil`. Reject unowned skin equips.
   - **Purchase Validation**: Verify `profile.Data.Credits >= skinPrice` before adding `skinId` to `OwnedCosmetics`.

3. **Operative Abilities (`UseAbility`)**:
   - **Type Enforcement**: Check `typeof(abilitySlot) == "number"` (slot 1, 2, or 3).
   - **Alive Check**: Validate player character exists and `Humanoid.Health > 0`.
   - **Vector Sanitization**: Check `targetPosition` for `NaN`/`Inf` and range bounds (<= 100 studs).
   - **Cooldown Validation**: Verify `os.clock() - lastAbilityTime >= cooldownSeconds` for non-Practice Range modes.
   - **Paid Ability Validation (Slot 2)**: Deduct credit cost if in PvP match; reject if insufficient credits.
   - **Ultimate Ability Validation (Slot 3)**: Verify `ultCharge >= 100%`; reset ult charge to 0 on execution.

4. **Combat Hit Reporting (`ReportHit` / `ReliableCombat`)**:
   - **Input Sanitization**: Check raycast origin, direction, and distance for `NaN` and `Inf`.
   - **Server Calculation**: Client NEVER sends damage values. Server computes damage using `WeaponStats` base damage, range falloff, headshot multiplier (2.0x–2.5x), and target armor absorption.
   - **Rollback History Validation**: Validate client timestamp against `RollbackBuffer` spatial history to prevent lag manipulation and teleport hits.

---

## 4. Verification & Testing Protocol

Worker 7 should verify the changes using the following methods:

1. **Unit Test Execution**:
   Run `ProfileServiceWrapper.spec.luau` to confirm data sanitization, NaN stripping, and structure integrity.
2. **DataStore Retries & Fallback Verification**:
   Simulate DataStore error / offline mode in Roblox Studio. Confirm player joins cleanly, receives in-memory default profile, and is **NEVER** kicked.
3. **Save & BindToClose Verification**:
   Trigger server shutdown in Studio (`game:BindToClose`). Verify all active player profiles execute `SaveAsync` and `ReleaseAsync` cleanly without memory leaks or missing lock releases.
