--!strict
--[=[
    Project OVERCLOCK: Buffer Serialization Module
    Provides high-performance binary buffer serialization/deserialization
    using Luau buffer datatype and bit32 operations.
]=]

local Types = require(script.Parent.Parent.Types)

local BufferSerializer = {}

-- ----------------------------------------------------------------------------
-- 1. Vector3 Serialization (Exactly 12 Bytes)
-- ----------------------------------------------------------------------------

--- Serializes a Vector3 into a new 12-byte buffer (3 x 32-bit floats).
function BufferSerializer.SerializeVector3(v: Vector3): buffer
    local buf = buffer.create(12)
    buffer.writef32(buf, 0, v.X)
    buffer.writef32(buf, 4, v.Y)
    buffer.writef32(buf, 8, v.Z)
    return buf
end

--- Writes a Vector3 into an existing buffer at the specified byte offset. Returns new offset.
function BufferSerializer.WriteVector3(buf: buffer, offset: number, v: Vector3): number
    buffer.writef32(buf, offset, v.X)
    buffer.writef32(buf, offset + 4, v.Y)
    buffer.writef32(buf, offset + 8, v.Z)
    return offset + 12
end

--- Deserializes a Vector3 from a buffer starting at offset. Returns Vector3 and new offset.
function BufferSerializer.DeserializeVector3(buf: buffer, offset: number?): (Vector3, number)
    local off = offset or 0
    local x = buffer.readf32(buf, off)
    local y = buffer.readf32(buf, off + 4)
    local z = buffer.readf32(buf, off + 8)
    return Vector3.new(x, y, z), off + 12
end

-- ----------------------------------------------------------------------------
-- 2. CFrame Serialization (13 to 15 Bytes)
-- Position: 12 bytes (3 x f32)
-- Rotation: 1-3 bytes (Compressed Euler YXZ / Yaw representation)
-- Default SerializeCFrame produces 15 bytes (12b pos + 3b Euler YXZ u8)
-- ----------------------------------------------------------------------------

--- Angle conversion helper: maps [-pi, pi] to [0, 255] u8
local function angleToU8(angle: number): number
    local norm = (angle + math.pi) / (2 * math.pi)
    norm = norm - math.floor(norm)
    return math.clamp(math.floor(norm * 256), 0, 255)
end

--- Angle conversion helper: maps [0, 255] u8 to [-pi, pi]
local function u8ToAngle(u: number): number
    return (u / 256) * (2 * math.pi) - math.pi
end

--- Writes a CFrame into a buffer starting at offset using 15 bytes (12b pos + 3b Euler YXZ).
function BufferSerializer.WriteCFrame(buf: buffer, offset: number, cf: CFrame): number
    local pos = cf.Position
    buffer.writef32(buf, offset, pos.X)
    buffer.writef32(buf, offset + 4, pos.Y)
    buffer.writef32(buf, offset + 8, pos.Z)

    local rx, ry, rz = cf:ToEulerAnglesYXZ()
    buffer.writeu8(buf, offset + 12, angleToU8(rx))
    buffer.writeu8(buf, offset + 13, angleToU8(ry))
    buffer.writeu8(buf, offset + 14, angleToU8(rz))

    return offset + 15
end

--- Serializes a CFrame into a new 15-byte buffer (12b position + 3b compressed rotation).
function BufferSerializer.SerializeCFrame(cf: CFrame): buffer
    local buf = buffer.create(15)
    BufferSerializer.WriteCFrame(buf, 0, cf)
    return buf
end

--- Deserializes a 15-byte CFrame from buffer starting at offset.
function BufferSerializer.DeserializeCFrame(buf: buffer, offset: number?): (CFrame, number)
    local off = offset or 0
    local px = buffer.readf32(buf, off)
    local py = buffer.readf32(buf, off + 4)
    local pz = buffer.readf32(buf, off + 8)

    local bx = buffer.readu8(buf, off + 12)
    local by = buffer.readu8(buf, off + 13)
    local bz = buffer.readu8(buf, off + 14)

    local pos = Vector3.new(px, py, pz)
    local rot = CFrame.fromEulerAnglesYXZ(u8ToAngle(bx), u8ToAngle(by), u8ToAngle(bz))

    return CFrame.new(pos) * rot, off + 15
end

--- Serializes a CFrame into a 13-byte buffer (12b position + 1b compressed Yaw index).
function BufferSerializer.SerializeCFrame13(cf: CFrame): buffer
    local buf = buffer.create(13)
    local pos = cf.Position
    buffer.writef32(buf, 0, pos.X)
    buffer.writef32(buf, 4, pos.Y)
    buffer.writef32(buf, 8, pos.Z)

    local _, yaw, _ = cf:ToEulerAnglesYXZ()
    buffer.writeu8(buf, 12, angleToU8(yaw))
    return buf
end

--- Deserializes a 13-byte CFrame (12b pos + 1b Yaw) from buffer.
function BufferSerializer.DeserializeCFrame13(buf: buffer, offset: number?): (CFrame, number)
    local off = offset or 0
    local px = buffer.readf32(buf, off)
    local py = buffer.readf32(buf, off + 4)
    local pz = buffer.readf32(buf, off + 8)
    local by = buffer.readu8(buf, off + 12)

    local yaw = u8ToAngle(by)
    return CFrame.new(px, py, pz) * CFrame.Angles(0, yaw, 0), off + 13
end

-- ----------------------------------------------------------------------------
-- 3. Boolean Array Bit-Packing (8 Booleans per Byte)
-- ----------------------------------------------------------------------------

--- Bit-packs an array of booleans into a buffer at 8 booleans per byte.
function BufferSerializer.BitPackBooleans(bools: { boolean }): buffer
    local count = #bools
    local numBytes = math.max(1, math.ceil(count / 8))
    local buf = buffer.create(numBytes)

    for i = 1, count do
        if bools[i] then
            local byteIdx = math.floor((i - 1) / 8)
            local bitPos = (i - 1) % 8
            local currentByte = buffer.readu8(buf, byteIdx)
            local newByte = bit32.bor(currentByte, bit32.lshift(1, bitPos))
            buffer.writeu8(buf, byteIdx, newByte)
        end
    end

    return buf
end

--- Unpacks count booleans from a bit-packed buffer starting at offset.
function BufferSerializer.BitUnpackBooleans(buf: buffer, offset: number?, count: number): { boolean }
    local off = offset or 0
    local result: { boolean } = table.create(count)

    for i = 1, count do
        local byteIdx = math.floor((i - 1) / 8)
        local bitPos = (i - 1) % 8
        local byteVal = buffer.readu8(buf, off + byteIdx)
        local isSet = bit32.band(byteVal, bit32.lshift(1, bitPos)) ~= 0
        result[i] = isSet
    end

    return result
end

-- ----------------------------------------------------------------------------
-- 4. High-Level Struct Serialization (Hit Verification Payload)
-- ----------------------------------------------------------------------------

--- Serializes a HitVerificationPayload into a packed binary buffer.
function BufferSerializer.SerializeHitVerification(payload: Types.HitVerificationPayload): buffer
    local wId = payload.weaponId or ""
    local wLen = math.min(#wId, 255)
    local bufSize = 53 + wLen
    local buf = buffer.create(bufSize)

    local off = 0
    off = BufferSerializer.WriteVector3(buf, off, payload.origin)
    off = BufferSerializer.WriteVector3(buf, off, payload.direction)
    buffer.writef32(buf, off, payload.distance)
    off = off + 4
    off = BufferSerializer.WriteVector3(buf, off, payload.hitPosition)
    buffer.writef64(buf, off, payload.clientTimestamp)
    off = off + 8
    buffer.writeu32(buf, off, payload.sequenceId)
    off = off + 4

    buffer.writeu8(buf, off, wLen)
    off = off + 1
    buffer.writestring(buf, off, wId, wLen)

    return buf
end

--- Deserializes a HitVerificationPayload from a binary buffer.
function BufferSerializer.DeserializeHitVerification(buf: buffer, offset: number?): (Types.HitVerificationPayload, number)
    local off = offset or 0
    local origin, off1 = BufferSerializer.DeserializeVector3(buf, off)
    local direction, off2 = BufferSerializer.DeserializeVector3(buf, off1)
    local distance = buffer.readf32(buf, off2)
    off2 = off2 + 4
    local hitPosition, off3 = BufferSerializer.DeserializeVector3(buf, off2)
    local clientTimestamp = buffer.readf64(buf, off3)
    off3 = off3 + 8
    local sequenceId = buffer.readu32(buf, off3)
    off3 = off3 + 4

    local wLen = buffer.readu8(buf, off3)
    off3 = off3 + 1
    local weaponId = buffer.readstring(buf, off3, wLen)
    off3 = off3 + wLen

    local payload: Types.HitVerificationPayload = {
        origin = origin,
        direction = direction,
        distance = distance,
        hitPosition = hitPosition,
        clientTimestamp = clientTimestamp,
        sequenceId = sequenceId,
        weaponId = weaponId,
        targetInstance = nil,
    }

    return payload, off3
end

-- ----------------------------------------------------------------------------
-- 5. Fire Intent Serialization (24 bytes)
-- ----------------------------------------------------------------------------

--- Serializes a Fire Intent into a 24-byte buffer (origin + direction).
function BufferSerializer.SerializeFireIntent(origin: Vector3, direction: Vector3): buffer
    local buf = buffer.create(24)
    local off = BufferSerializer.WriteVector3(buf, 0, origin)
    BufferSerializer.WriteVector3(buf, off, direction)
    return buf
end

--- Deserializes a Fire Intent buffer back into origin and direction vectors.
function BufferSerializer.DeserializeFireIntent(buf: buffer): (Vector3, Vector3)
    local origin, off = BufferSerializer.DeserializeVector3(buf, 0)
    local direction = BufferSerializer.DeserializeVector3(buf, off)
	return origin, direction
end

-- ----------------------------------------------------------------------------
-- 6. Legacy Movement Sync (RETIRED)
-- MovementAuthority now samples HumanoidRootPart directly at 20 Hz.
-- Buffer helpers retained as no-ops for backwards compatibility
-- but should not be used by new code. New movement uses MovementIntent only.
-- ----------------------------------------------------------------------------

function BufferSerializer.SerializeSpatialState(_timestamp: number, _position: Vector3, _velocity: Vector3): buffer
    error("[BufferSerializer] SerializeSpatialState retired — use MovementIntent")
end

function BufferSerializer.DeserializeSpatialState(_buf: buffer): (number, Vector3, Vector3)
    error("[BufferSerializer] DeserializeSpatialState retired — use MovementIntent")
end

return BufferSerializer
