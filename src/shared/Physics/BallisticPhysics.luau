--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

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
    penetrationCount: number,
    maxPenetrations: number,
    bounces: number,
    maxBounces: number,
    raycastParams: RaycastParams,
    startTime: number,
    onHitCallback: ((hitResult: RaycastResult, projectile: ProjectileData) -> ())?,
    onExpireCallback: ((projectile: ProjectileData) -> ())?,
}

local activeProjectiles: { [string]: ProjectileData } = {}
local GLOBAL_GRAVITY = Vector3.new(0, -Workspace.Gravity, 0)
local stepConnection: RBXScriptConnection? = nil

local function stepProjectile(proj: ProjectileData, dt: number)
    local oldPos = proj.position
    local accel = proj.acceleration + (GLOBAL_GRAVITY * proj.gravityMultiplier)
    local stepDisplacement = (proj.velocity * dt) + (0.5 * accel * dt * dt)
    local newPos = oldPos + stepDisplacement
    local stepVelocity = proj.velocity + (accel * dt)
    
    local dir = stepDisplacement
    local dist = dir.Magnitude
    
    if dist > 0.001 then
        local hitResult = Workspace:Raycast(oldPos, dir, proj.raycastParams)
        
        if hitResult then
            if proj.onHitCallback then
                proj.onHitCallback(hitResult, proj)
            end

            local normal = hitResult.Normal
            local dot = -proj.velocity.Unit:Dot(normal)

            -- Ricochet logic
            if dot < 0.35 and proj.bounces < proj.maxBounces then
                proj.bounces += 1
                proj.velocity = proj.velocity - (2 * proj.velocity:Dot(normal) * normal)
                proj.velocity = proj.velocity * 0.8
                proj.position = hitResult.Position + normal * 0.1
                return false
            elseif proj.penetrationCount < proj.maxPenetrations then
                proj.penetrationCount += 1
                proj.velocity = proj.velocity * 0.6
                proj.damage = proj.damage * 0.7
                proj.position = hitResult.Position + dir.Unit * 0.1
                local model = hitResult.Instance:FindFirstAncestorOfClass("Model")
                local exclude = model or hitResult.Instance
                local filter = proj.raycastParams.FilterDescendantsInstances
                table.insert(filter, exclude)
                proj.raycastParams.FilterDescendantsInstances = filter
                return false
            end

            return true -- consumed
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

local function onStep(dt: number)
    for id, proj in pairs(activeProjectiles) do
        if stepProjectile(proj, dt) then
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
    maxPenetrations: number?,
    maxBounces: number?,
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
        velocity = (config.direction.Magnitude > 0.001 and config.direction.Unit or Vector3.new(0, 0, -1)) * config.velocityMod,
        acceleration = Vector3.zero,
        gravityMultiplier = config.gravityMult,
        distanceTraveled = 0,
        maxRange = config.maxRange,
        damage = config.damage,
        isHeadshotCapable = true,
        penetrationCount = 0,
        maxPenetrations = config.maxPenetrations or 0,
        bounces = 0,
        maxBounces = config.maxBounces or 0,
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
