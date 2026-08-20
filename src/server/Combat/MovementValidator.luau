--!strict
--[=[
    Project OVERCLOCK: Server Movement Validator
    Reconciles client physics buffers against server physics constraints.
    Prevents speed hacking and teleportation by enforcing max Delta V
    and Rubberbanding invalid states.
]=]

local Players = game:GetService("Players")

local MovementValidator = {}

export type PlayerMovementState = {
    lastTimestamp: number,
    lastPosition: Vector3,
    lastVelocity: Vector3,
    violations: number,
    skipNextValidation: boolean?,
    speedMultiplier: number?,
}

local playerStates: { [number]: PlayerMovementState } = {}

-- Constraints based on MovementController max speeds (slightly raised for operative buffs + sprint)
local MAX_WALK_SPEED = 22.0
local MAX_ACCELERATION = 120.0 -- High to account for instant strafing
local MAX_TOLERANCE_MULTIPLIER = 1.4 -- 40% tolerance for network jitter + high ping

function MovementValidator.ValidateClientState(userId: number, timestamp: number, position: Vector3, velocity: Vector3): boolean
    local player = Players:GetPlayerByUserId(userId)
    if not player or not player.Character then return false end

    local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return false end

    local state = playerStates[userId]
    if not state then
        -- First state received, initialize it based on server's truth
        playerStates[userId] = {
            lastTimestamp = timestamp,
            lastPosition = hrp.Position,
            lastVelocity = hrp.AssemblyLinearVelocity,
            violations = 0,
        }
        return true
    end

    local dt = timestamp - state.lastTimestamp
    if dt <= 0 then return false end -- Out of order or duplicate packet

    if state.skipNextValidation then
        state.skipNextValidation = false
        state.lastTimestamp = timestamp
        state.lastPosition = position
        state.lastVelocity = velocity
        return true
    end

    -- 1. Validate Velocity Magnitude (Speed Hack)
    local multiplier = state.speedMultiplier or 1.0
    local horizVel = Vector3.new(velocity.X, 0, velocity.Z)
    if horizVel.Magnitude > MAX_WALK_SPEED * MAX_TOLERANCE_MULTIPLIER * multiplier then
        state.violations += 1
        return false
    end

    -- 2. Validate Acceleration (Instant TP / Speed Hack)
    local dv = (velocity - state.lastVelocity).Magnitude
    local expectedMaxDv = MAX_ACCELERATION * dt * MAX_TOLERANCE_MULTIPLIER
    if dv > expectedMaxDv and velocity.Y >= 0 then -- Ignore downward falling acceleration which can be huge
        state.violations += 1
        return false
    end

    -- 3. Validate Position (Teleportation)
    local dp = (position - state.lastPosition).Magnitude
    -- Max possible distance traveled = max speed * dt
    local expectedMaxDp = (MAX_WALK_SPEED * MAX_TOLERANCE_MULTIPLIER) * dt
    -- Allow some extra tolerance for falling or external physics impulses
    if dp > expectedMaxDp + 5.0 then
        state.violations += 1
        return false
    end

    -- Valid state
    state.lastTimestamp = timestamp
    state.lastPosition = position
    state.lastVelocity = velocity
    
    -- Decay violations
    if state.violations > 0 then
        state.violations = math.max(0, state.violations - 1)
    end
    
    return true
end

function MovementValidator.HandleViolation(userId: number)
    local state = playerStates[userId]
    if not state then return end
    
    -- Rubberband player back to last valid server position
    local player = Players:GetPlayerByUserId(userId)
    if player and player.Character then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if hrp then
            hrp.CFrame = CFrame.new(state.lastPosition)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end
    
    -- Reset state to allow clean reconciliation
    playerStates[userId] = nil
end

function MovementValidator.ClearPlayer(userId: number)
    playerStates[userId] = nil
end

function MovementValidator.NotifyTeleport(player: Player)
    local state = playerStates[player.UserId]
    if state then
        state.skipNextValidation = true
        -- Refresh position to character's current server position so 500-stud jump doesn't trigger dp violation
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then
            state.lastPosition = root.Position
            state.lastVelocity = root.AssemblyLinearVelocity
        end
    else
        -- No state yet (new player or cleared after violation) — seed it to avoid false rubber-band
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then
            playerStates[player.UserId] = {
                lastTimestamp = tick(),
                lastPosition = root.Position,
                lastVelocity = root.AssemblyLinearVelocity,
                violations = 0,
                skipNextValidation = true,
            }
        else
            playerStates[player.UserId] = {
                lastTimestamp = tick(),
                lastPosition = Vector3.zero,
                lastVelocity = Vector3.zero,
                violations = 0,
                skipNextValidation = true,
            }
        end
    end
end

function MovementValidator.ForceTeleport(player: Player, destination: Vector3)
    playerStates[player.UserId] = {
        lastTimestamp = tick(),
        lastPosition = destination,
        lastVelocity = Vector3.zero,
        violations = 0,
        skipNextValidation = true,
    }
end

function MovementValidator.SetSpeedMultiplier(player: Player, multiplier: number)
    local state = playerStates[player.UserId]
    if state then
        state.speedMultiplier = multiplier
    end
end

return MovementValidator
