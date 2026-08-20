--!strict
--[[
	OVERCLOCK: FPSMovementConfig
	Place at ReplicatedStorage.Physics.FPSMovementConfig.

	This is the single tuning surface for both client presentation and server
	validation. Values are velocities/accelerations in Roblox studs and seconds.
--]]

local FPSMovementConfig = {}

export type MovementState = "Disabled" | "Idle" | "Run" | "Sprint" | "Crouch" | "Slide" | "Air"

FPSMovementConfig.FixedStep = 1 / 60
FPSMovementConfig.MaxCatchUpSteps = 4
FPSMovementConfig.IntentHeartbeatSeconds = 0.10
FPSMovementConfig.IntentRateLimitPerSecond = 16
FPSMovementConfig.ServerSampleHz = 20

FPSMovementConfig.RunSpeed = 16.0
FPSMovementConfig.SprintSpeed = 24.0
FPSMovementConfig.CrouchSpeed = 8.0
FPSMovementConfig.MinSlideEntrySpeed = 18.0
FPSMovementConfig.MaxSlideSpeed = 27.0
FPSMovementConfig.MinSlideSpeed = 10.0

FPSMovementConfig.GroundAcceleration = 95.0
FPSMovementConfig.GroundDeceleration = 70.0
FPSMovementConfig.GroundFriction = 42.0
FPSMovementConfig.AirAcceleration = 24.0
FPSMovementConfig.AirMaxControlSpeed = 18.0
FPSMovementConfig.AirDrag = 1.2
FPSMovementConfig.SlideFriction = 7.5
FPSMovementConfig.SlideSteerAcceleration = 11.0
FPSMovementConfig.SlopeGravityScale = 0.28
FPSMovementConfig.MaxWalkableSlopeDegrees = 46.0
FPSMovementConfig.GroundProbeDistance = 4.35
FPSMovementConfig.GroundProbeOriginLift = 1.2

FPSMovementConfig.JumpSpeed = 52.0
FPSMovementConfig.JumpBufferSeconds = 0.12
FPSMovementConfig.CoyoteSeconds = 0.10
FPSMovementConfig.JumpCutMultiplier = 0.48
FPSMovementConfig.JumpCooldownSeconds = 0.10

FPSMovementConfig.SprintDrainPerSecond = 22.0
FPSMovementConfig.SprintRecoveryPerSecond = 17.0
FPSMovementConfig.MaxStamina = 100.0
FPSMovementConfig.MinStaminaToStartSprint = 8.0

FPSMovementConfig.SlideDuration = 0.82
FPSMovementConfig.SlideCooldownSeconds = 0.55
FPSMovementConfig.SlideInputThreshold = 0.40

FPSMovementConfig.CrouchHipHeightFactor = 0.58
FPSMovementConfig.CrouchCameraOffset = Vector3.new(0, -0.72, 0)
FPSMovementConfig.StandClearanceHeight = 3.0

-- Server-side guardrails. These include network and physical tolerance but are
-- intentionally narrower than the old client-position-based validator.
FPSMovementConfig.ServerBaseSpeedTolerance = 5.0
FPSMovementConfig.ServerSpeedToleranceMultiplier = 1.35
FPSMovementConfig.ServerTeleportDistance = 26.0
FPSMovementConfig.ServerMaxUpwardVelocity = 82.0
FPSMovementConfig.ServerViolationLimit = 3
FPSMovementConfig.ServerViolationDecaySeconds = 2.0
FPSMovementConfig.ServerAuthorizedTeleportGraceSeconds = 1.25

FPSMovementConfig.States = {
	Disabled = "Disabled" :: MovementState,
	Idle = "Idle" :: MovementState,
	Run = "Run" :: MovementState,
	Sprint = "Sprint" :: MovementState,
	Crouch = "Crouch" :: MovementState,
	Slide = "Slide" :: MovementState,
	Air = "Air" :: MovementState,
}

function FPSMovementConfig.GetMaxLegalHorizontalSpeed(isSprinting: boolean, isCrouching: boolean, isSliding: boolean): number
	if isSliding then
		return FPSMovementConfig.MaxSlideSpeed
	end
	if isCrouching then
		return FPSMovementConfig.CrouchSpeed
	end
	if isSprinting then
		return FPSMovementConfig.SprintSpeed
	end
	return FPSMovementConfig.RunSpeed
end

return FPSMovementConfig
