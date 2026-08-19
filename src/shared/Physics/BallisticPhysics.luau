--!strict
--[=[
    Project OVERCLOCK: Ballistic Physics Engine
    A highly optimized, custom projectile physics module utilizing swept raycasts 
    (Continuous Collision Detection / CCD) to simulate bullet drop, travel time, 
    and penetration without relying on Roblox's native physics engine.
]=]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BallisticPhysics = {}

export type ProjectileData = {
    id: string,
    shooterId: number,
    weaponId: string,
    origin: Vector3,
    position: Vector3,
    velocity: Vector3,
    acceleration: Vector3,
    gravityMultiplier: number,
    distanceTraveled: number,
    maxRange: number,
    damage: number,
    isHeadshotCapable: boolean,
    raycastParams: RaycastParams,
    startTime: number,
    onHitCallback: ((hitResult: RaycastResult, projectile: ProjectileData) -> ())?,
    onExpireCallback: ((projectile: ProjectileData) -> ())?,
}

local activeProjectiles: { [string]: ProjectileData } = {}
local GLOBAL_GRAVITY = Vector3.new(0, -Workspace.Gravity, 0)
local HttpService = game:GetService("HttpService")

-- Steps a projectile forward by DeltaTime using kinematic equations:
-- pos = pos + vel * dt + 0.5 * a * dt^2
-- vel = vel + a * dt
local function stepProjectile(proj: ProjectileData, dt: number)
    local oldPos = proj.position
    
    local accel = proj.acceleration + (GLOBAL_GRAVITY * proj.gravityMultiplier)
    local stepDisplacement = (proj.velocity * dt) + (0.5 * accel * dt * dt)
    local newPos = oldPos + stepDisplacement
    
    local stepVelocity = proj.velocity + (accel * dt)
    
    -- Swept Raycast for Continuous Collision Detection (CCD)
    local dir = stepDisplacement
    local dist = dir.Magnitude
    
    if dist > 0.001 then
        local hitResult = Workspace:Raycast(oldPos, dir, proj.raycastParams)
        
        if hitResult then
            if proj.onHitCallback then
                proj.onHitCallback(hitResult, proj)
            end
            return true -- Projectile consumed
        end
    end
    
    proj.position = newPos
    proj.velocity = stepVelocity
    proj.distanceTraveled += dist
    
    if proj.distanceTraveled >= proj.maxRange then
        if proj.onExpireCallback then
            proj.onExpireCallback(proj)
        end
        return true -- Expired
    end
    
    return false -- Still active
end

-- Hook into physics step for Server, or RenderStepped for Client
local stepConnection: RBXScriptConnection? = nil

local function onStep(dt: number)
    for id, proj in pairs(activeProjectiles) do
        local consumed = stepProjectile(proj, dt)
        if consumed then
            activeProjectiles[id] = nil
        end
    end
end

function BallisticPhysics.Initialize()
    if stepConnection then return end
    
    if RunService:IsServer() then
        stepConnection = RunService.Heartbeat:Connect(onStep)
    else
        stepConnection = RunService.RenderStepped:Connect(onStep)
    end
end

function BallisticPhysics.FireProjectile(config: {
    shooterId: number,
    weaponId: string,
    origin: Vector3,
    direction: Vector3,
    velocityMod: number,
    gravityMult: number,
    maxRange: number,
    damage: number,
    raycastParams: RaycastParams,
    onHit: ((hitResult: RaycastResult, proj: ProjectileData) -> ())?,
    onExpire: ((proj: ProjectileData) -> ())?
}): string
    local id = HttpService:GenerateGUID(false)
    
    local proj: ProjectileData = {
        id = id,
        shooterId = config.shooterId,
        weaponId = config.weaponId,
        origin = config.origin,
        position = config.origin,
        velocity = config.direction.Unit * config.velocityMod,
        acceleration = Vector3.zero,
        gravityMultiplier = config.gravityMult,
        distanceTraveled = 0,
        maxRange = config.maxRange,
        damage = config.damage,
        isHeadshotCapable = true,
        raycastParams = config.raycastParams,
        startTime = os.clock(),
        onHitCallback = config.onHit,
        onExpireCallback = config.onExpire,
    }
    
    activeProjectiles[id] = proj
    return id
end

function BallisticPhysics.ClearProjectiles()
    table.clear(activeProjectiles)
end

return BallisticPhysics
