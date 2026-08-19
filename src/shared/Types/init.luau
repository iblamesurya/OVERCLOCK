--!strict
--[=[
    Project OVERCLOCK: Core Type Definitions
    Provides strict Luau type definitions for combat snapshots, spatial vectors,
    player profiles, weapon configurations, and remote network payloads.
]=]

-- ==========================================
-- 1. VECTOR & SPATIAL TYPES
-- ==========================================

export type Vector3Data = {
    x: number,
    y: number,
    z: number,
}

export type CFrameData = {
    position: Vector3Data,
    rotation: { number },
}

export type RaycastResultSnapshot = {
    distance: number,
    instance: Instance?,
    normal: Vector3Data,
    position: Vector3Data,
    material: Enum.Material?,
}

-- ==========================================
-- 2. COMBAT SNAPSHOT TYPES
-- ==========================================

export type TargetHitboxType =
    "Head"
    | "Torso"
    | "LeftArm"
    | "RightArm"
    | "LeftLeg"
    | "RightLeg"
    | "Environment"
    | "Shield"

export type HitSnapshot = {
    hitId: string,
    attackerUserId: number,
    victimUserId: number?,
    victimInstance: Instance?,
    hitPosition: Vector3,
    hitNormal: Vector3,
    hitboxType: TargetHitboxType,
    damageDealt: number,
    isHeadshot: boolean,
    isCritical: boolean,
    originPosition: Vector3,
    weaponId: string,
    serverTimestamp: number,
    clientTimestamp: number,
    distance: number,
}

export type CombatStateSnapshot = {
    timestamp: number,
    sequenceNumber: number,
    playerPosition: Vector3,
    playerVelocity: Vector3,
    lookVector: Vector3,
    health: number,
    maxHealth: number,
    shield: number,
    maxShield: number,
    isStunned: boolean,
    isReloading: boolean,
    isAiming: boolean,
    activeWeaponId: string?,
    activeBuffs: { [string]: number },
}

export type HitVerificationPayload = {
    origin: Vector3,
    direction: Vector3,
    distance: number,
    targetInstance: Instance?,
    hitPosition: Vector3,
    clientTimestamp: number,
    sequenceId: number,
    weaponId: string,
}

-- ==========================================
-- 3. PLAYER PROFILE & PROGRESSION TYPES
-- ==========================================

export type PlayerCurrency = {
    credits: number,
    gems: number,
    eventTokens: number,
}

export type PlayerStats = {
    kills: number,
    deaths: number,
    assists: number,
    wins: number,
    losses: number,
    headshots: number,
    totalDamageDealt: number,
    playtimeSeconds: number,
    matchesPlayed: number,
    accuracyRatio: number,
}

export type PlayerLoadout = {
    primaryWeaponId: string,
    secondaryWeaponId: string,
    meleeWeaponId: string,
    tacticalGadgetId: string,
    lethalGadgetId: string,
    perkIds: { string },
    weaponSkins: { [string]: string },
}

export type PlayerSettings = {
    mouseSensitivity: number,
    fov: number,
    crosshairColor: string,
    soundVolume: number,
    musicVolume: number,
}

export type PlayerProfile = {
    userId: number,
    username: string,
    level: number,
    experience: number,
    rankRating: number,
    rankTier: string,
    currencies: PlayerCurrency,
    stats: PlayerStats,
    equippedLoadout: PlayerLoadout,
    inventory: { [string]: boolean },
    unlockedClasses: { string },
    settings: PlayerSettings,
    schemaVersion: number,
    lastLoginTimestamp: number,
}

-- ==========================================
-- 4. WEAPON CONFIGURATION TYPES
-- ==========================================

export type FireMode = "Auto" | "Semi" | "Burst" | "Single"
export type AmmoType = "Light" | "Medium" | "Heavy" | "Energy" | "Shotgun" | "Explosive"
export type WeaponCategory = "Primary" | "Secondary" | "Melee" | "Special"
export type WeaponRarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RecoilPoint = {
    x: number,
    y: number,
}

export type WeaponStatConfig = {
    baseDamage: number,
    headshotMultiplier: number,
    fireRateRPM: number,
    fireModes: { FireMode },
    ammoType: AmmoType,
    magazineCapacity: number,
    reserveCapacity: number,
    reloadTimeSeconds: number,
    tacticalReloadTimeSeconds: number,
    maxRangeUnits: number,
    effectiveRangeUnits: number,
    damageFalloffMin: number,
    bulletVelocity: number,
    spreadDegrees: number,
    aimingSpreadMultiplier: number,
    recoilPattern: { RecoilPoint },
    equipTimeSeconds: number,
    weightSpeedMultiplier: number,
}

export type WeaponAudioVisual = {
    fireSoundId: string,
    reloadSoundId: string,
    emptySoundId: string,
    tracerEffectId: string?,
    muzzleFlashEffectId: string?,
    impactParticleId: string?,
    iconAssetId: string,
    modelAssetId: string,
}

export type WeaponConfiguration = {
    weaponId: string,
    displayName: string,
    category: WeaponCategory,
    rarity: WeaponRarity,
    stats: WeaponStatConfig,
    assets: WeaponAudioVisual,
    allowedAttachments: { string },
}

-- ==========================================
-- 5. REMOTE PAYLOAD & NETWORK TYPES
-- ==========================================

export type RemoteActionType =
    "FireWeapon"
    | "ReloadWeapon"
    | "EquipWeapon"
    | "ReportHit"
    | "PlayerAbilityUse"
    | "SyncProfile"
    | "MatchStateChange"
    | "PingCheck"

export type RemotePayloadHeader = {
    action: RemoteActionType,
    timestamp: number,
    sequence: number,
}

export type FireWeaponPayload = {
    header: RemotePayloadHeader,
    weaponId: string,
    origin: Vector3,
    direction: Vector3,
    seed: number,
}

export type ReportHitPayload = {
    header: RemotePayloadHeader,
    hitData: HitVerificationPayload,
}

export type ReloadWeaponPayload = {
    header: RemotePayloadHeader,
    weaponId: string,
    isTactical: boolean,
}

export type MatchState = "Waiting" | "Warmup" | "InGame" | "PostGame" | "Ended"

export type MatchSyncPayload = {
    matchId: string,
    matchState: MatchState,
    timeRemainingSeconds: number,
    redTeamScore: number,
    blueTeamScore: number,
    snapshots: { [number]: CombatStateSnapshot },
}

export type ClientToServerPayload = {
    action: RemoteActionType,
    payload: FireWeaponPayload | ReportHitPayload | ReloadWeaponPayload | { [string]: any },
}

export type ServerToClientPayload = {
    action: RemoteActionType,
    success: boolean,
    errorMessage: string?,
    payload: MatchSyncPayload | PlayerProfile | { [string]: any },
}

return {}
