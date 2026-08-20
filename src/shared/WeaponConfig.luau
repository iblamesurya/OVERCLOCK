-- ReplicatedStorage/Shared/WeaponConfig.luau
-- Shared for UI presentation but authoritative only when read by the server.

export type WeaponConfig = {
    fireMode: "Hitscan" | "Projectile",
    damage: number,
    range: number,
    fireRate: number,
    magazineSize: number,
    reloadSeconds: number,
    spreadDegrees: number,
    projectileSpeed: number?,
    projectileGravityScale: number?,
    projectileLifetime: number?,
}

local config: {[string]: WeaponConfig} = {
    EnergyRifle = {
        fireMode = "Projectile",
        damage = 24,
        range = 650,
        fireRate = 7.5,
        magazineSize = 30,
        reloadSeconds = 2.2,
        spreadDegrees = 0.35,
    },
    ArcLauncher = {
        fireMode = "Projectile",
        damage = 75,
        range = 460,
        fireRate = 1.15,
        magazineSize = 1,
        reloadSeconds = 2.6,
        spreadDegrees = 0.5,
        projectileSpeed = 150,
        projectileGravityScale = 1.0,
        projectileLifetime = 4.0,
    },
}

return table.freeze(config)
