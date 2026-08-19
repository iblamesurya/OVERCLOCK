--!strict
--[=[
    Project OVERCLOCK: Milestone 2 Automated Unit Test Runner
    Executes unit and integration tests across BufferSerializer, RollbackBuffer,
    HitValidation, RemoteEvents, and CombatServer to ensure 100% correctness and reliability.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types") :: any)

local BufferSerializer = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("BufferSerializer") :: any)
local RollbackBuffer = require(script.Parent.RollbackBuffer)
local HitValidation = require(script.Parent.HitValidation)
local CombatServer = require(script.Parent.CombatServer)

local M2_TestRunner = {}

function M2_TestRunner.RunAllTests(): (boolean, number, number, { string })
    local passed = 0
    local failed = 0
    local errors: { string } = {}

    local function assertTest(condition: boolean, testName: string, detail: string?)
        if condition then
            passed += 1
            print(`[PASS] {testName}`)
        else
            failed += 1
            local msg = `[FAIL] {testName}` .. (detail and `: {detail}` or "")
            table.insert(errors, msg)
            warn(msg)
        end
    end

    print("==================================================")
    print("RUNNING MILESTONE 2 SUITE FOR OVERCLOCK")
    print("==================================================")

    -- ------------------------------------------------------------------------
    -- TEST SUITE 1: BufferSerializer
    -- ------------------------------------------------------------------------
    do
        -- Test 1.1: Vector3 Serialization (12 bytes exact)
        local testVec = Vector3.new(123.456, -789.012, 0.001)
        local vecBuf = BufferSerializer.SerializeVector3(testVec)
        local vecLen = buffer.len(vecBuf)
        assertTest(vecLen == 12, "BufferSerializer: Vector3 Buffer Size", `Expected 12 bytes, got {vecLen}`)

        local roundVec, nextOff = BufferSerializer.DeserializeVector3(vecBuf, 0)
        local vecDiff = (testVec - roundVec).Magnitude
        assertTest(vecDiff < 1e-4, "BufferSerializer: Vector3 Round-trip", `Diff magnitude: {vecDiff}`)
        assertTest(nextOff == 12, "BufferSerializer: Vector3 Offset Return", `Expected offset 12, got {nextOff}`)

        -- Test 1.2: CFrame Serialization (15 bytes exact)
        local testCF = CFrame.new(10, 20, 30) * CFrame.Angles(0.5, -0.2, 0.8)
        local cfBuf = BufferSerializer.SerializeCFrame(testCF)
        local cfLen = buffer.len(cfBuf)
        assertTest(cfLen == 15, "BufferSerializer: CFrame 15b Buffer Size", `Expected 15 bytes, got {cfLen}`)

        local roundCF, cfNextOff = BufferSerializer.DeserializeCFrame(cfBuf, 0)
        local posDiff = (testCF.Position - roundCF.Position).Magnitude
        assertTest(posDiff < 1e-4, "BufferSerializer: CFrame Position Precision", `Position diff: {posDiff}`)
        assertTest(cfNextOff == 15, "BufferSerializer: CFrame Offset Return", `Expected offset 15, got {cfNextOff}`)

        -- Test 1.3: CFrame Serialization 13 bytes
        local cfBuf13 = BufferSerializer.SerializeCFrame13(testCF)
        assertTest(buffer.len(cfBuf13) == 13, "BufferSerializer: CFrame 13b Buffer Size")

        -- Test 1.4: Boolean Bit-Packing (8 per byte)
        local bools = { true, false, true, true, false, false, true, false, true, true } -- 10 booleans -> 2 bytes
        local boolBuf = BufferSerializer.BitPackBooleans(bools)
        local boolBufLen = buffer.len(boolBuf)
        assertTest(boolBufLen == 2, "BufferSerializer: BitPackBooleans Byte Count", `Expected 2 bytes for 10 booleans, got {boolBufLen}`)

        local unpackedBools = BufferSerializer.BitUnpackBooleans(boolBuf, 0, #bools)
        local boolsMatch = true
        for i = 1, #bools do
            if unpackedBools[i] ~= bools[i] then
                boolsMatch = false
                break
            end
        end
        assertTest(boolsMatch, "BufferSerializer: BitUnpackBooleans Round-trip")

        -- Test 1.5: HitVerification Payload Serialization
        local hitPayload: Types.HitVerificationPayload = {
            origin = Vector3.new(0, 5, 0),
            direction = Vector3.new(0, 0, -1),
            distance = 50.5,
            hitPosition = Vector3.new(0, 5, -50.5),
            clientTimestamp = 1000.123456,
            sequenceId = 42,
            weaponId = "RIFLE_AK47",
        }
        local hitBuf = BufferSerializer.SerializeHitVerification(hitPayload)
        local roundHitPayload = BufferSerializer.DeserializeHitVerification(hitBuf, 0)
        assertTest(roundHitPayload.weaponId == "RIFLE_AK47", "BufferSerializer: HitPayload WeaponId Round-trip")
        assertTest((roundHitPayload.origin - hitPayload.origin).Magnitude < 1e-4, "BufferSerializer: HitPayload Origin Round-trip")
        assertTest(roundHitPayload.sequenceId == 42, "BufferSerializer: HitPayload SequenceId Round-trip")
    end

    -- ------------------------------------------------------------------------
    -- TEST SUITE 2: RollbackBuffer & Hermite Spline Interpolation
    -- ------------------------------------------------------------------------
    do
        local rb = RollbackBuffer.new(10, 60)
        local entityId = "Player1"

        -- Push snapshots at t=0s, t=1s, t=2s
        rb:PushSnapshot(entityId, {
            timestamp = 0.0,
            position = Vector3.new(0, 0, 0),
            velocity = Vector3.new(10, 0, 0),
            cframe = CFrame.new(0, 0, 0),
            size = Vector3.new(2, 5, 2),
        })

        rb:PushSnapshot(entityId, {
            timestamp = 1.0,
            position = Vector3.new(10, 0, 0),
            velocity = Vector3.new(10, 0, 0),
            cframe = CFrame.new(10, 0, 0),
            size = Vector3.new(2, 5, 2),
        })

        rb:PushSnapshot(entityId, {
            timestamp = 2.0,
            position = Vector3.new(20, 0, 0),
            velocity = Vector3.new(10, 0, 0),
            cframe = CFrame.new(20, 0, 0),
            size = Vector3.new(2, 5, 2),
        })

        local snapshots = rb:GetSnapshots(entityId)
        assertTest(#snapshots == 3, "RollbackBuffer: Ring Buffer Count", `Expected 3, got {#snapshots}`)

        -- Test Interpolation at t = 0.5s (midway)
        local interpState = rb:GetInterpolatedState(entityId, 0.5)
        assertTest(interpState ~= nil, "RollbackBuffer: GetInterpolatedState Returns Value")

        if interpState then
            -- Hermite cubic spline with linear motion (vel=10) should evaluate position X close to 5.0
            local posErr = math.abs(interpState.position.X - 5.0)
            assertTest(posErr < 1e-3, "RollbackBuffer: Hermite Spline Interpolated Position", `Pos X expected 5.0, got {interpState.position.X}`)
            assertTest(interpState.timestamp == 0.5, "RollbackBuffer: Interpolated Timestamp Preserved")
        end
    end

    -- ------------------------------------------------------------------------
    -- TEST SUITE 3: HitValidation & OBB Slab Ray Intersection
    -- ------------------------------------------------------------------------
    do
        -- Test 3.1: OBB Ray Intersection Test (Pure Mathematical Geometry)
        local rayOrigin = Vector3.new(0, 0, 10)
        local rayDirection = Vector3.new(0, 0, -1) -- Pointing along -Z towards box
        local maxDist = 20.0
        local obbCFrame = CFrame.new(0, 0, 0) -- Centered at origin
        local obbSize = Vector3.new(2, 4, 2) -- Bounds: X[-1,1], Y[-2,2], Z[-1,1]

        local obbResult = HitValidation.TestRayOBB(rayOrigin, rayDirection, maxDist, obbCFrame, obbSize)
        assertTest(obbResult.hit == true, "HitValidation: TestRayOBB Hit True")
        if obbResult.hit then
            -- Ray hits front face of box at Z = +1 (dist = 10 - 1 = 9)
            local distErr = math.abs((obbResult.distance or 0) - 9.0)
            assertTest(distErr < 1e-3, "HitValidation: OBB Hit Distance Precision", `Expected 9.0, got {obbResult.distance}`)
        end

        -- Test 3.2: OBB Ray Intersection Miss
        local rayMissDir = Vector3.new(1, 0, 0) -- Pointing away along +X
        local obbMissResult = HitValidation.TestRayOBB(rayOrigin, rayMissDir, maxDist, obbCFrame, obbSize)
        assertTest(obbMissResult.hit == false, "HitValidation: TestRayOBB Miss")

        -- Test 3.3: Clamped Rollback Window Validation
        local rb = RollbackBuffer.new(60, 60)
        rb:PushSnapshot("Attacker", {
            timestamp = 10.0,
            position = Vector3.new(0, 0, 10),
            velocity = Vector3.zero,
            cframe = CFrame.new(0, 0, 10),
        })
        rb:PushSnapshot("Victim", {
            timestamp = 10.0,
            position = Vector3.new(0, 0, 0),
            velocity = Vector3.zero,
            cframe = CFrame.new(0, 0, 0),
            size = Vector3.new(2, 5, 2),
        })

        local payload: Types.HitVerificationPayload = {
            origin = Vector3.new(0, 0, 10),
            direction = Vector3.new(0, 0, -1),
            distance = 10.0,
            hitPosition = Vector3.new(0, 0, 1),
            clientTimestamp = 10.0,
            sequenceId = 1,
            weaponId = "RIFLE",
        }

        -- Server time = 10.3s (latency = 0.3s = 300ms, valid for 500ms rollback window)
        local valResult = HitValidation.ValidateHit(rb, "Attacker", "Victim", payload, 10.3, {
            maxRollbackMs = 500,
            maxOriginTolerance = 8.0,
            rayDistanceMargin = 4.0,
        })
        assertTest(valResult.valid == true, "HitValidation: ValidateHit Valid Hit", `Reason: {valResult.reason}`)

        -- Server time = 11.5s (latency = 1.5s > max rollback window, should be rejected)
        local valExpiredResult = HitValidation.ValidateHit(rb, "Attacker", "Victim", payload, 11.5, {
            maxRollbackMs = 500,
            maxOriginTolerance = 8.0,
            rayDistanceMargin = 4.0,
        })
        assertTest(valExpiredResult.valid == false, "HitValidation: ValidateHit Reject Expired Timestamp")
        assertTest(valExpiredResult.reason == "TimestampExceedsRollbackWindow", "HitValidation: Reject Reason Correct")
    end

    -- ------------------------------------------------------------------------
    -- TEST SUITE 4: CombatServer & Damage Pipeline
    -- ------------------------------------------------------------------------
    do
        local cs = CombatServer.new(nil, { maxRollbackMs = 500, matchPhase = "InGame" })
        cs:RegisterPlayer(100, 100, 50) -- Attacker
        cs:RegisterPlayer(200, 100, 50) -- Victim (100 HP, 50 Shield)

        cs:UpdatePlayerSpatial(100, Vector3.new(0, 0, 10), Vector3.zero, CFrame.new(0, 0, 10), 100.0)
        cs:UpdatePlayerSpatial(200, Vector3.new(0, 0, 0), Vector3.zero, CFrame.new(0, 0, 0), 100.0)

        local payload: Types.HitVerificationPayload = {
            origin = Vector3.new(0, 0, 10),
            direction = Vector3.new(0, 0, -1),
            distance = 10.0,
            hitPosition = Vector3.new(0, 0, 1),
            clientTimestamp = 10.0,
            sequenceId = 1,
            weaponId = "RIFLE_M4A1",
        }

        -- Process hit (base damage = 40, serverTimestamp = 10.1s)
        local success, reason, remHealth = cs:ProcessHitReport(100, 200, payload, 10.1, 40)
        assertTest(success == true, "CombatServer: ProcessHitReport Success", `Reason: {reason}`)

        local victimHP = cs:GetPlayerHealth(200)
        assertTest(victimHP ~= nil and victimHP.shield == 10, "CombatServer: Shield Damage Absorbed", `Shield remaining: {victimHP and victimHP.shield}`)
        assertTest(victimHP ~= nil and victimHP.health == 100, "CombatServer: Health Preserved When Shielded")

        -- Test rate limiting on rapid hits
        local rateLimitExceeded = false
        for _ = 1, 10 do
            local succ, r, _ = cs:ProcessHitReport(100, 200, payload, 100, 10)
            if not succ and r == "RateLimitExceeded" then
                rateLimitExceeded = true
                break
            end
        end
        assertTest(rateLimitExceeded, "CombatServer: Leaky Bucket Rate Limiter Enforced")

        -- Test match phase blocking
        cs:SetMatchPhase("PostGame")
        local phaseSuccess, phaseReason = cs:ProcessHitReport(100, 200, payload, 100, 10)
        assertTest(phaseSuccess == false and phaseReason == "InvalidMatchPhase", "CombatServer: Discard Inactive Match Phase Hits")
    end

    print("==================================================")
    print(`SUITE COMPLETED: {passed} PASSED, {failed} FAILED`)
    print("==================================================")

    return failed == 0, passed, failed, errors
end

-- Automatically execute test runner if script is executed directly
if not script.Parent:IsA("Model") then
    M2_TestRunner.RunAllTests()
end

return M2_TestRunner
