--!strict
--[=[
    Project OVERCLOCK: Server Hit Validation Engine
    Validates weapon fire and hit reports against server-authoritative rewind history.
    Enforces clamped temporal rollback windows (250-1000ms threshold), origin distance checks,
    and mathematical Oriented Bounding Box (OBB) ray intersection without moving workspace parts.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Types") :: any)

local RollbackBuffer = require(script.Parent.RollbackBuffer)

export type HitValidationOptions = {
    maxRollbackMs: number, -- Max latency compensation window in ms (clamped 250-1000ms)
    maxOriginTolerance: number, -- Max allowed distance between claimed origin and rewound position
    rayDistanceMargin: number, -- Margin allowed for max ray distance checks
}

export type OBBHitResult = {
    hit: boolean,
    distance: number?,
    hitPosition: Vector3?,
    hitNormal: Vector3?,
}

export type HitValidationResult = {
    valid: boolean,
    reason: string?,
    attackerState: RollbackBuffer.SpatialSnapshot?,
    victimState: RollbackBuffer.SpatialSnapshot?,
    hitPosition: Vector3?,
    calculatedDistance: number?,
}

local HitValidation = {}

local DEFAULT_OPTIONS: HitValidationOptions = {
    maxRollbackMs = 500, -- Default 500ms (clamped between 250ms and 1000ms)
    maxOriginTolerance = 15.0, -- Increased to 15.0 to account for FirstPerson camera offset from HRP
    rayDistanceMargin = 4.0, -- 4 Roblox units distance tolerance
}

-- ----------------------------------------------------------------------------
-- 1. Mathematical Oriented Bounding Box (OBB) Ray Intersection Test
-- Slab test performed in local OBB object frame. No physical parts are moved.
-- ----------------------------------------------------------------------------

--- Tests a ray against an Oriented Bounding Box (OBB) in pure mathematical space.
function HitValidation.TestRayOBB(
    rayOrigin: Vector3,
    rayDirection: Vector3,
    maxDistance: number,
    obbCFrame: CFrame,
    obbSize: Vector3
): OBBHitResult
    local dirMag = rayDirection.Magnitude
    if dirMag < 1e-6 then
        return { hit = false }
    end
    local normDir = rayDirection / dirMag

    -- Transform ray to OBB local object frame
    local localOrigin = obbCFrame:PointToObjectSpace(rayOrigin)
    local localDir = obbCFrame:VectorToObjectSpace(normDir)

    -- Half extents of box
    local halfSize = obbSize * 0.5

    local tMin = 0.0
    local tMax = maxDistance

    local hitAxis = 0
    local hitSign = 1

    local localOrigArr = { localOrigin.X, localOrigin.Y, localOrigin.Z }
    local localDirArr = { localDir.X, localDir.Y, localDir.Z }
    local halfSizeArr = { halfSize.X, halfSize.Y, halfSize.Z }

    for i = 1, 3 do
        local dirComponent = localDirArr[i]
        local origComponent = localOrigArr[i]
        local halfExtent = halfSizeArr[i]

        if math.abs(dirComponent) < 1e-7 then
            -- Ray is parallel to slab; check if origin is outside slab bounds
            if origComponent < -halfExtent or origComponent > halfExtent then
                return { hit = false }
            end
        else
            local t1 = (-halfExtent - origComponent) / dirComponent
            local t2 = (halfExtent - origComponent) / dirComponent

            local sign1 = -1
            local sign2 = 1

            if t1 > t2 then
                t1, t2 = t2, t1
                sign1, sign2 = sign2, sign1
            end

            if t1 > tMin then
                tMin = t1
                hitAxis = i
                hitSign = sign1
            end

            if t2 < tMax then
                tMax = t2
            end

            if tMin > tMax then
                return { hit = false }
            end
        end
    end

    if tMin < 0 or tMin > maxDistance then
        return { hit = false }
    end

    -- World-space hit position & surface normal calculation
    local localHitPos = localOrigin + localDir * tMin
    local worldHitPos = obbCFrame:PointToWorldSpace(localHitPos)

    local localNormal = Vector3.zero
    if hitAxis == 0 then
        localNormal = if localDir.Magnitude > 0 then -localDir.Unit else Vector3.new(0, 1, 0)
    elseif hitAxis == 1 then
        localNormal = Vector3.new(hitSign, 0, 0)
    elseif hitAxis == 2 then
        localNormal = Vector3.new(0, hitSign, 0)
    elseif hitAxis == 3 then
        localNormal = Vector3.new(0, 0, hitSign)
    end

    local worldNormal = obbCFrame:VectorToWorldSpace(localNormal)

    return {
        hit = true,
        distance = tMin,
        hitPosition = worldHitPos,
        hitNormal = worldNormal,
    }
end

-- ----------------------------------------------------------------------------
-- 2. Full Server Hit Validation Pipeline
-- ----------------------------------------------------------------------------

--- Validates a client hit report against server-authoritative rollback history.
function HitValidation.ValidateHit(
    rollbackBuffer: RollbackBuffer.RollbackBufferClass,
    attackerId: string,
    victimId: string,
    payload: Types.HitVerificationPayload,
    serverTimeNow: number,
    customOptions: HitValidationOptions?,
    victimObbSize: Vector3?
): HitValidationResult
    local options = customOptions or DEFAULT_OPTIONS
    options.maxOriginTolerance = math.clamp(options.maxOriginTolerance or 15, 0, 50)
    options.rayDistanceMargin = math.clamp(options.rayDistanceMargin or 5, 0, 50)

    -- Clamped temporal rollback threshold (strictly enforced between 250ms and 1000ms)
    local rawThresholdMs = options.maxRollbackMs
    local clampedMs = math.clamp(rawThresholdMs, 250, 1000)
    local maxRollbackSec = clampedMs / 1000

    -- Step 1: Temporal Rollback Window Validation
    local clientTimestamp = payload.clientTimestamp
    local latency = serverTimeNow - clientTimestamp

    -- Reject timestamps in far future (> 50ms drift tolerance) or older than maxRollbackSec
    if latency < -0.05 then
        return { valid = false, reason = "TimestampInFuture" }
    end
    if latency > maxRollbackSec then
        return { valid = false, reason = "TimestampExceedsRollbackWindow" }
    end

    -- Step 2: Retrieve Rewound Spatial Snapshots via Hermite Spline Interpolation
    local attackerState = rollbackBuffer:GetInterpolatedState(attackerId, clientTimestamp)
    local victimState = rollbackBuffer:GetInterpolatedState(victimId, clientTimestamp)

    if not attackerState then
        return { valid = false, reason = "AttackerHistoryNotFound" }
    end
    if not victimState then
        return { valid = false, reason = "VictimHistoryNotFound" }
    end

    -- Step 3: Origin Distance Validation against Attacker's Rewound Position
    local originDist = (payload.origin - attackerState.position).Magnitude
    if originDist > options.maxOriginTolerance then
        return { valid = false, reason = "OriginDistanceExceeded" }
    end

    -- Step 4: Distance Sanity Check
    if payload.distance < 0 or payload.distance > 10000 then
        return { valid = false, reason = "InvalidHitDistance" }
    end

    -- Step 5: Oriented Bounding Box (OBB) Mathematical Ray Intersection Test
    local boxSize = victimObbSize or victimState.size or Vector3.new(4, 6, 4)
    local obbResult = HitValidation.TestRayOBB(
        payload.origin,
        payload.direction,
        payload.distance + options.rayDistanceMargin,
        victimState.cframe,
        boxSize
    )

    if not obbResult.hit then
        return { valid = false, reason = "OBBIntersectionFailed" }
    end

    -- Step 6: Raycast Wall-penetration Block (Line of Sight)
    -- Perform a physical raycast on the server to ensure no static walls block the shot.
    -- (We ignore character models because they have moved; we only check static environment)
    if obbResult.hitPosition then
        local losDir = obbResult.hitPosition - payload.origin
        local losDist = losDir.Magnitude
        if losDist > 0.1 then
            local rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            -- Filter out ALL character models to avoid false positives from current real-time positions
            local chars = {}
            for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                if p.Character then table.insert(chars, p.Character) end
            end
            rayParams.FilterDescendantsInstances = chars
            rayParams.IgnoreWater = true

            local losResult = Workspace:Raycast(payload.origin, losDir.Unit * losDist, rayParams)
            if losResult then
                local hitModel = losResult.Instance:FindFirstAncestorOfClass("Model")
                local isTarget = false
                if hitModel then
                    if hitModel.Name == victimId or tostring(hitModel:GetAttribute("BotId")) == victimId then
                        isTarget = true
                    end
                end

                if not isTarget then
                    return { valid = false, reason = "WallPenetrationDetected" }
                end
            end
        end
    end

    return {
        valid = true,
        attackerState = attackerState,
        victimState = victimState,
        hitPosition = obbResult.hitPosition,
        calculatedDistance = obbResult.distance,
    }
end

return HitValidation
