--!strict
--[[
	OVERCLOCK: FPSMovementKernel
	Place at ReplicatedStorage.Physics.FPSMovementKernel.

	Pure movement math. This module does not access services, instances, remotes,
	or network time, so it can be unit-tested independently of Roblox physics.
--]]

local Config = require(script.Parent:WaitForChild("FPSMovementConfig") :: ModuleScript)

local FPSMovementKernel = {}

export type MovementState = Config.MovementState

export type InputFrame = {
	moveDirection: Vector3,
	sprintHeld: boolean,
	crouchHeld: boolean,
	crouchPressed: boolean,
	jumpPressed: boolean,
	jumpHeld: boolean,
	locked: boolean,
}

export type GroundInfo = {
	grounded: boolean,
	normal: Vector3,
}

export type RuntimeState = {
	movementState: MovementState,
	horizontalVelocity: Vector3,
	stamina: number,
	lastGroundedAt: number,
	lastJumpAt: number,
	jumpBufferUntil: number,
	slideUntil: number,
	slideCooldownUntil: number,
	slideDirection: Vector3,
	wasJumpHeld: boolean,
}

export type StepResult = {
	movementState: MovementState,
	horizontalVelocity: Vector3,
	targetWalkSpeed: number,
	moveDirection: Vector3,
	stamina: number,
	jumpVelocity: number?,
	applyJumpCut: boolean,
	isCrouching: boolean,
	isSprinting: boolean,
	isSliding: boolean,
	-- FTUE assist telemetry
	didCoyoteJump: boolean,
	didBufferedJump: boolean,
	slideAttempted: boolean,
	slideSucceeded: boolean,
}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function safeUnit(vector: Vector3): Vector3
	local magnitude = vector.Magnitude
	if magnitude < 1e-4 then
		return Vector3.zero
	end
	return vector / magnitude
end

local function approach(current: number, target: number, maxDelta: number): number
	if current < target then
		return math.min(current + maxDelta, target)
	end
	return math.max(current - maxDelta, target)
end

local function approachVector(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance < 1e-4 then
		return target
	end
	return current + delta / distance * maxDelta
end

local function isWalkable(normal: Vector3): boolean
	local minimumY = math.cos(math.rad(Config.MaxWalkableSlopeDegrees))
	return normal.Y >= minimumY
end

local function projectOnPlane(direction: Vector3, normal: Vector3): Vector3
	return direction - normal * direction:Dot(normal)
end

local function downhillDirection(normal: Vector3): Vector3
	return safeUnit(projectOnPlane(Vector3.new(0, -1, 0), normal))
end

function FPSMovementKernel.New(): RuntimeState
	return {
		movementState = "Idle",
		horizontalVelocity = Vector3.zero,
		stamina = Config.MaxStamina,
		lastGroundedAt = -math.huge,
		lastJumpAt = -math.huge,
		jumpBufferUntil = -math.huge,
		slideUntil = -math.huge,
		slideCooldownUntil = -math.huge,
		slideDirection = Vector3.zero,
		wasJumpHeld = false,
	}
end

function FPSMovementKernel.Reset(state: RuntimeState)
	state.movementState = "Idle"
	state.horizontalVelocity = Vector3.zero
	state.stamina = Config.MaxStamina
	state.lastGroundedAt = -math.huge
	state.lastJumpAt = -math.huge
	state.jumpBufferUntil = -math.huge
	state.slideUntil = -math.huge
	state.slideCooldownUntil = -math.huge
	state.slideDirection = Vector3.zero
	state.wasJumpHeld = false
end

function FPSMovementKernel.Step(
	state: RuntimeState,
	now: number,
	dt: number,
	input: InputFrame,
	ground: GroundInfo,
	observedHorizontalVelocity: Vector3,
	gravity: number
): StepResult
	local clampedDt = math.clamp(dt, 0, Config.FixedStep * 2)
	local currentHorizontal = horizontal(observedHorizontalVelocity)
	state.horizontalVelocity = currentHorizontal

	if input.jumpPressed then
		state.jumpBufferUntil = now + Config.JumpBufferSeconds
	end

	if input.locked then
		state.movementState = "Disabled"
		state.horizontalVelocity = approachVector(currentHorizontal, Vector3.zero, Config.GroundFriction * clampedDt)
		state.wasJumpHeld = input.jumpHeld
		return {
			movementState = "Disabled",
			horizontalVelocity = state.horizontalVelocity,
			targetWalkSpeed = 0,
			moveDirection = Vector3.zero,
			stamina = state.stamina,
			applyJumpCut = false,
			isCrouching = false,
			isSprinting = false,
			isSliding = false,
			didCoyoteJump = false,
			didBufferedJump = false,
			slideAttempted = false,
			slideSucceeded = false,
		}
	end

	local normal = if ground.normal.Magnitude > 0.9 then ground.normal.Unit else Vector3.yAxis
	local grounded = ground.grounded and isWalkable(normal)
	if grounded then
		state.lastGroundedAt = now
	end

	local desiredDirection = safeUnit(horizontal(input.moveDirection))
	if grounded then
		desiredDirection = safeUnit(projectOnPlane(desiredDirection, normal))
	end

	local hasMoveInput = desiredDirection.Magnitude >= Config.SlideInputThreshold
	local canUseCoyote = now - state.lastGroundedAt <= Config.CoyoteSeconds
	local canJump = now <= state.jumpBufferUntil and canUseCoyote and now - state.lastJumpAt >= Config.JumpCooldownSeconds

	local groundedBeforeJump = grounded
	local wasJumpPressedNow = input.jumpPressed
	local jumpVelocity: number? = nil
	local didCoyoteJump = false
	local didBufferedJump = false
	if canJump and not input.locked then
		jumpVelocity = Config.JumpSpeed
		state.lastJumpAt = now
		state.jumpBufferUntil = -math.huge
		state.movementState = "Air"
		grounded = false
		-- Telemetry: coyote when jump occurred while not grounded before (used coyote window), buffer when input not pressed this frame
		didCoyoteJump = not groundedBeforeJump
		didBufferedJump = not wasJumpPressedNow
	end

	local slideAttempted = input.crouchPressed and input.sprintHeld and hasMoveInput
	local slideSucceeded = false
	local wantsSlide = grounded
		and input.crouchPressed
		and input.sprintHeld
		and hasMoveInput
		and currentHorizontal.Magnitude >= Config.MinSlideEntrySpeed
		and now >= state.slideCooldownUntil

	if wantsSlide and state.movementState ~= "Slide" then
		state.movementState = "Slide"
		state.slideUntil = now + Config.SlideDuration
		state.slideCooldownUntil = now + Config.SlideCooldownSeconds
		state.slideDirection = safeUnit(currentHorizontal)
		if state.slideDirection.Magnitude < 0.1 then
			state.slideDirection = desiredDirection
		end
		slideSucceeded = true
	end

	local applyJumpCut = false
	if state.wasJumpHeld and not input.jumpHeld and not grounded then
		applyJumpCut = true
	end
	state.wasJumpHeld = input.jumpHeld

	local targetSpeed = Config.RunSpeed
	local outputState: MovementState
	local isSliding = false
	local isSprinting = false
	local isCrouching = false
	local targetVelocity = Vector3.zero

	if not grounded then
		outputState = "Air"
		local airTargetSpeed = math.min(Config.AirMaxControlSpeed, Config.RunSpeed)
		targetVelocity = desiredDirection * airTargetSpeed
		state.horizontalVelocity = approachVector(currentHorizontal, targetVelocity, Config.AirAcceleration * clampedDt)
		state.horizontalVelocity = approachVector(state.horizontalVelocity, Vector3.zero, Config.AirDrag * clampedDt)
		targetSpeed = 0
	elseif state.movementState == "Slide" then
		local slideExpired = now >= state.slideUntil or currentHorizontal.Magnitude < Config.MinSlideSpeed
		if slideExpired then
			state.movementState = if input.crouchHeld then "Crouch" else "Run"
		else
			outputState = "Slide"
			isSliding = true
			isCrouching = true
			local steer = desiredDirection * math.min(currentHorizontal.Magnitude, Config.MaxSlideSpeed)
			local steered = approachVector(currentHorizontal, steer, Config.SlideSteerAcceleration * clampedDt)
			local slowed = approachVector(steered, Vector3.zero, Config.SlideFriction * clampedDt)
			local downhill = downhillDirection(normal)
			local safeGravity = if gravity > 0 and gravity == gravity then gravity else 196.2
			local slopeBoost = downhill * (Config.SlopeGravityScale * safeGravity * math.max(0, 1 - normal.Y))
			state.horizontalVelocity = slowed + slopeBoost * clampedDt
			if state.horizontalVelocity.Magnitude > Config.MaxSlideSpeed then
				state.horizontalVelocity = state.horizontalVelocity.Unit * Config.MaxSlideSpeed
			end
			targetSpeed = 0
			return {
				movementState = outputState,
				horizontalVelocity = state.horizontalVelocity,
				targetWalkSpeed = targetSpeed,
				moveDirection = safeUnit(state.horizontalVelocity),
				stamina = state.stamina,
				jumpVelocity = jumpVelocity,
				applyJumpCut = applyJumpCut,
				isCrouching = isCrouching,
				isSprinting = false,
				isSliding = isSliding,
				didCoyoteJump = didCoyoteJump,
				didBufferedJump = didBufferedJump,
				slideAttempted = slideAttempted,
				slideSucceeded = slideSucceeded,
			}
		end
	end

	if grounded then
		local canSprint = input.sprintHeld
			and hasMoveInput
			and not input.crouchHeld
			and state.stamina >= Config.MinStaminaToStartSprint

		if input.crouchHeld then
			outputState = "Crouch"
			isCrouching = true
			targetSpeed = Config.CrouchSpeed
		elseif canSprint then
			outputState = "Sprint"
			isSprinting = true
			targetSpeed = Config.SprintSpeed
			state.stamina = math.max(0, state.stamina - Config.SprintDrainPerSecond * clampedDt)
		else
			outputState = if hasMoveInput then "Run" else "Idle"
			targetSpeed = if hasMoveInput then Config.RunSpeed else 0
			state.stamina = math.min(Config.MaxStamina, state.stamina + Config.SprintRecoveryPerSecond * clampedDt)
		end

		targetVelocity = desiredDirection * targetSpeed
		local rate = if hasMoveInput then Config.GroundAcceleration else Config.GroundDeceleration
		state.horizontalVelocity = approachVector(currentHorizontal, targetVelocity, rate * clampedDt)
		if not hasMoveInput then
			state.horizontalVelocity = approachVector(state.horizontalVelocity, Vector3.zero, Config.GroundFriction * clampedDt)
		end
	else
		outputState = "Air"
	end

	state.movementState = outputState
	return {
		movementState = outputState,
		horizontalVelocity = state.horizontalVelocity,
		targetWalkSpeed = targetSpeed,
		moveDirection = desiredDirection,
		stamina = state.stamina,
		jumpVelocity = jumpVelocity,
		applyJumpCut = applyJumpCut,
		isCrouching = isCrouching,
		isSprinting = isSprinting,
		isSliding = isSliding,
		didCoyoteJump = didCoyoteJump,
		didBufferedJump = didBufferedJump,
		slideAttempted = slideAttempted,
		slideSucceeded = slideSucceeded,
	}
end

return FPSMovementKernel
