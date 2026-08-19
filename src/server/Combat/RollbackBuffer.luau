--!strict
--[=[
    Project OVERCLOCK: Rollback Spatial Ring Buffer
    Circular ring buffer storing per-entity spatial snapshots at ~60Hz with configurable capacity.
    Provides Hermite cubic spline state interpolation between snapshots for lag compensation.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types") :: any)

export type SpatialSnapshot = {
    timestamp: number,
    position: Vector3,
    velocity: Vector3,
    cframe: CFrame,
    size: Vector3?,
}

type EntityRingBuffer = {
    capacity: number,
    count: number,
    head: number, -- 1-based write index
    snapshots: { SpatialSnapshot },
}

local RollbackBuffer = {}
RollbackBuffer.__index = RollbackBuffer

export type RollbackBufferClass = typeof(setmetatable({} :: {
    _defaultCapacity: number,
    _sampleRateHz: number,
    _buffers: { [string]: EntityRingBuffer },
}, RollbackBuffer))

--- Creates a new RollbackBuffer manager.
-- Default capacity is 120 (2 seconds at 60Hz tick rate).
function RollbackBuffer.new(capacity: number?, sampleRateHz: number?): RollbackBufferClass
    local self = setmetatable({
        _defaultCapacity = capacity or 120,
        _sampleRateHz = sampleRateHz or 60,
        _buffers = {} :: { [string]: EntityRingBuffer },
    }, RollbackBuffer)
    return self
end

function RollbackBuffer._getOrCreateBuffer(self: RollbackBufferClass, entityId: string): EntityRingBuffer
    local buf = self._buffers[entityId]
    if not buf then
        buf = {
            capacity = self._defaultCapacity,
            count = 0,
            head = 1,
            snapshots = table.create(self._defaultCapacity) :: { SpatialSnapshot },
        }
        self._buffers[entityId] = buf
    end
    return buf
end

--- Pushes a spatial snapshot into the circular ring buffer for entityId.
function RollbackBuffer.PushSnapshot(self: RollbackBufferClass, entityId: string, snapshot: SpatialSnapshot)
    local buf = self._getOrCreateBuffer(self, entityId)
    buf.snapshots[buf.head] = snapshot
    buf.head = (buf.head % buf.capacity) + 1
    if buf.count < buf.capacity then
        buf.count += 1
    end
end

--- Returns all valid stored snapshots for an entity, ordered by timestamp ascending.
function RollbackBuffer.GetSnapshots(self: RollbackBufferClass, entityId: string): { SpatialSnapshot }
    local buf = self._buffers[entityId]
    if not buf or buf.count == 0 then
        return {}
    end

    local result: { SpatialSnapshot } = table.create(buf.count)
    local startIdx = 1
    if buf.count == buf.capacity then
        startIdx = buf.head -- Oldest snapshot is at head when ring buffer is full
    end

    for i = 1, buf.count do
        local idx = ((startIdx + i - 2) % buf.capacity) + 1
        result[i] = buf.snapshots[idx]
    end

    return result
end

--- Calculates Hermite cubic spline interpolated spatial state at the requested timestamp.
-- Interpolates position and velocity via Hermite basis functions and orientation via Slerp.
function RollbackBuffer.GetInterpolatedState(self: RollbackBufferClass, entityId: string, timestamp: number): SpatialSnapshot?
    local snapshots = self:GetSnapshots(entityId)
    local count = #snapshots
    if count == 0 then
        return nil
    end

    -- Edge boundary cases
    if timestamp <= snapshots[1].timestamp then
        return snapshots[1]
    end
    if timestamp >= snapshots[count].timestamp then
        return snapshots[count]
    end

    -- Binary search for surrounding snapshots s0 (<= timestamp) and s1 (>= timestamp)
    local low = 1
    local high = count
    local i0 = 1

    while low <= high do
        local mid = math.floor((low + high) / 2)
        if snapshots[mid].timestamp <= timestamp then
            i0 = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end

    local i1 = math.min(i0 + 1, count)
    local s0 = snapshots[i0]
    local s1 = snapshots[i1]

    if i0 == i1 or math.abs(s1.timestamp - s0.timestamp) < 1e-6 then
        return s0
    end

    -- Hermite cubic spline interpolation calculations
    local dt = s1.timestamp - s0.timestamp
    local u = (timestamp - s0.timestamp) / dt
    local u2 = u * u
    local u3 = u2 * u

    -- Hermite basis functions
    local h00 = 2 * u3 - 3 * u2 + 1
    local h10 = u3 - 2 * u2 + u
    local h01 = -2 * u3 + 3 * u2
    local h11 = u3 - u2

    -- Tangents scaled by interval duration dt
    local m0 = s0.velocity * dt
    local m1 = s1.velocity * dt

    -- Interpolated position P(u)
    local interpPos = s0.position * h00 + m0 * h10 + s1.position * h01 + m1 * h11

    -- Hermite basis function derivatives for velocity tangent V(u) = dP/dt
    local dh00 = 6 * u2 - 6 * u
    local dh10 = 3 * u2 - 4 * u + 1
    local dh01 = -6 * u2 + 6 * u
    local dh11 = 3 * u2 - 2 * u

    local dPdu = s0.position * dh00 + m0 * dh10 + s1.position * dh01 + m1 * dh11
    local interpVel = dPdu / dt

    -- Orientation interpolation (Slerp via CFrame Lerp on rotation)
    local rot0 = s0.cframe.Rotation
    local rot1 = s1.cframe.Rotation
    local interpRot = rot0:Lerp(rot1, u)
    local interpCFrame = CFrame.new(interpPos) * interpRot

    -- Size interpolation if present
    local interpSize: Vector3? = nil
    if s0.size and s1.size then
        interpSize = s0.size:Lerp(s1.size, u)
    elseif s0.size then
        interpSize = s0.size
    elseif s1.size then
        interpSize = s1.size
    end

    return {
        timestamp = timestamp,
        position = interpPos,
        velocity = interpVel,
        cframe = interpCFrame,
        size = interpSize,
    }
end

--- Clears stored snapshot buffer for an entity.
function RollbackBuffer.ClearEntity(self: RollbackBufferClass, entityId: string)
    self._buffers[entityId] = nil
end

--- Clears all entity snapshot buffers.
function RollbackBuffer.ClearAll(self: RollbackBufferClass)
    table.clear(self._buffers)
end

return RollbackBuffer
