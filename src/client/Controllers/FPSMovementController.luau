--!strict
--[[
	OVERCLOCK: FPSMovementController
	Place at StarterPlayerScripts.Controllers.FPSMovementController and replace the
	legacy MovementController bootstrap entry. This is a Humanoid-compatible FPS
	movement layer: collision remains Roblox-owned, while state, acceleration,
	jump assists, sprint, crouch, slide, and intent replication are custom.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PhysicsFolder = ReplicatedStorage:WaitForChild("Physics")
local Config = require(PhysicsFolder:WaitForChild("FPSMovementConfig") :: ModuleScript)
local Kernel = require(PhysicsFolder:WaitForChild("FPSMovementKernel") :: ModuleScript)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: ModuleScript)
local Input = require(script.Parent:WaitForChild("FPSMovementInput") :: ModuleScript)
local AnalyticsWrapper = require(ReplicatedStorage:WaitForChild("Analytics"):WaitForChild("AnalyticsWrapper") :: ModuleScript)
-- Optional FTUEAnalytics forwarding (server service mirrored to ReplicatedStorage if available)
local FTUEAnalytics: any = nil
pcall(function()
	-- Attempt to locate FTUEAnalytics if replicated; client otherwise logs via AnalyticsWrapper directly
	local rs = game:GetService("ReplicatedStorage")
	local analyticsFolder = rs:FindFirstChild("Analytics")
	if analyticsFolder then
		local ftueMod = analyticsFolder:FindFirstChild("FTUEAnalytics")
		if ftueMod then
			FTUEAnalytics = require(ftueMod :: any)
		end
	end
end)

local FPSMovementController = {}

local localPlayer = Players.LocalPlayer
local runtime = Kernel.New()
local renderConnection: RBXScriptConnection? = nil
local characterConnection: RBXScriptConnection? = nil
local accumulator = 0.0
local intentElapsed = math.huge
local intentSequence = 0
local lastIntentSignature = ""
local baseHipHeight: number? = nil
local baseCameraOffset = Vector3.zero
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function getCharacterParts(): (Model?, Humanoid?, BasePart?)
	local character = localPlayer.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return character, nil, nil
	end
	return character, humanoid, root
end

local function updateRaycastFilter(character: Model)
	raycastParams.FilterDescendantsInstances = { character }
end

local function probeGround(root: BasePart): Kernel.GroundInfo
	local origin = root.Position + Vector3.new(0, Config.GroundProbeOriginLift, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -Config.GroundProbeDistance, 0), raycastParams)
	if result then
		return {
			grounded = true,
			normal = result.Normal,
		}
	end
	return {
		grounded = false,
		normal = Vector3.yAxis,
	}
end

local function hasStandingClearance(root: BasePart): boolean
	local origin = root.Position + Vector3.new(0, 1.0, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, Config.StandClearanceHeight, 0), raycastParams)
	return hit == nil
end

local function lerpVector(current: Vector3, target: Vector3, alpha: number): Vector3
	return current + (target - current) * math.clamp(alpha, 0, 1)
end

local function setCrouchPresentation(humanoid: Humanoid, crouching: boolean, dt: number, root: BasePart)
	if baseHipHeight == nil then
		baseHipHeight = humanoid.HipHeight
		baseCameraOffset = humanoid.CameraOffset
	end

	local canStand = hasStandingClearance(root)
	local shouldCrouch = crouching or not canStand
	local targetHip = if shouldCrouch then baseHipHeight * Config.CrouchHipHeightFactor else baseHipHeight
	local targetCamera = if shouldCrouch then baseCameraOffset + Config.CrouchCameraOffset else baseCameraOffset
	local blend = 1 - math.exp(-18 * dt)
	humanoid.HipHeight = humanoid.HipHeight + (targetHip - humanoid.HipHeight) * blend
	humanoid.CameraOffset = lerpVector(humanoid.CameraOffset, targetCamera, blend)
end

local function updatePlayerAttributes(result: Kernel.StepResult)
	localPlayer:SetAttribute("MovementState", result.movementState)
	localPlayer:SetAttribute("IsSprinting", result.isSprinting)
	localPlayer:SetAttribute("IsSliding", result.isSliding)
	localPlayer:SetAttribute("IsCrouching", result.isCrouching)
	localPlayer:SetAttribute("MovementStamina", math.round(result.stamina * 10) / 10)
end

local function getIntentSignature(result: Kernel.StepResult, _: Kernel.InputFrame): string
	-- Direction is refreshed on the low-rate heartbeat. Edge sends are reserved for
	-- movement-state changes so normal mouse/analog steering cannot exceed the
	-- server's bounded intent rate.
	return table.concat({
		result.movementState,
		result.isSprinting and "1" or "0",
		result.isCrouching and "1" or "0",
		result.isSliding and "1" or "0",
	}, ":")
end

local function sendIntentIfNeeded(result: Kernel.StepResult, frame: Kernel.InputFrame)
	intentElapsed += Config.FixedStep
	local signature = getIntentSignature(result, frame)
	if signature == lastIntentSignature and intentElapsed < Config.IntentHeartbeatSeconds then
		return
	end

	local remote = RemoteEvents.GetUnreliable("MovementIntent")
	if not remote then
		return
	end

	intentSequence = (intentSequence + 1) % 2147483647
	remote:FireServer({
		sequence = intentSequence,
		moveX = math.clamp(frame.moveDirection.X, -1, 1),
		moveZ = math.clamp(frame.moveDirection.Z, -1, 1),
		sprint = result.isSprinting,
		crouch = result.isCrouching,
		slide = result.isSliding,
		jump = result.jumpVelocity ~= nil,
	})
	lastIntentSignature = signature
	intentElapsed = 0
end

local function applyMovement(
	humanoid: Humanoid,
	root: BasePart,
	result: Kernel.StepResult,
	dt: number
)
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = result.targetWalkSpeed

	if result.isSliding then
		-- Slide momentum is a client-predicted presentation. The server observes the
		-- physical root and validates its envelope; no client position is transmitted.
		local current = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(result.horizontalVelocity.X, current.Y, result.horizontalVelocity.Z)
		humanoid:Move(Vector3.zero, false)
	elseif result.movementState == "Air" then
		local current = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(result.horizontalVelocity.X, current.Y, result.horizontalVelocity.Z)
		humanoid:Move(result.moveDirection, false)
	else
		humanoid:Move(result.moveDirection, false)
	end

	if result.jumpVelocity then
		local current = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(current.X, result.jumpVelocity, current.Z)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	if result.applyJumpCut then
		local current = root.AssemblyLinearVelocity
		if current.Y > 0 then
			root.AssemblyLinearVelocity = Vector3.new(current.X, current.Y * Config.JumpCutMultiplier, current.Z)
		end
	end

	setCrouchPresentation(humanoid, result.isCrouching or result.isSliding, dt, root)
end

local function canControlCharacter(humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then
		return false
	end
	local playerState = localPlayer:GetAttribute("PlayerState")
	if playerState ~= nil and playerState ~= "Playing" and playerState ~= "PracticeRange" then
		return false
	end
	return true
end

local function fixedUpdate(): boolean
	local character, humanoid, root = getCharacterParts()
	if not character or not humanoid or not root then
		return false
	end
	updateRaycastFilter(character)

	local locked = not canControlCharacter(humanoid) or localPlayer:GetAttribute("BlocksMovement") == true
	local frame = Input.GetFrame(Workspace.CurrentCamera, locked)
	if localPlayer:GetAttribute("BlocksSprint") == true then
		frame.sprintHeld = false
	end

	local ground = probeGround(root)
	local result = Kernel.Step(
		runtime,
		Workspace:GetServerTimeNow(),
		Config.FixedStep,
		frame,
		ground,
		root.AssemblyLinearVelocity,
		Workspace.Gravity
	)
	applyMovement(humanoid, root, result, Config.FixedStep)
	updatePlayerAttributes(result)
	-- ── FTUEAnalytics wiring: movement assists (coyote / buffer / slide) ──
	-- Use FTUEAnalytics if replicated, otherwise fall back to AnalyticsWrapper custom events.
	-- These assists are telemetry only (no gameplay advantage) and are rate-limited by AnalyticsWrapper.
	if result.didCoyoteJump then
		if FTUEAnalytics and FTUEAnalytics.TrackCoyoteJump then
			pcall(function()
				FTUEAnalytics.TrackCoyoteJump(localPlayer)
			end)
		end
		pcall(function()
			AnalyticsWrapper.LogCustomEvent(localPlayer, "FTUE_CoyoteJump", 1, { assistType = "Coyote" })
		end)
	end
	if result.didBufferedJump then
		if FTUEAnalytics and FTUEAnalytics.TrackBufferedJump then
			pcall(function()
				FTUEAnalytics.TrackBufferedJump(localPlayer)
			end)
		end
		pcall(function()
			AnalyticsWrapper.LogCustomEvent(localPlayer, "FTUE_BufferedJump", 1, { assistType = "Buffer" })
		end)
	end
	if result.slideAttempted then
		if FTUEAnalytics and FTUEAnalytics.TrackSlideAttempt then
			pcall(function()
				FTUEAnalytics.TrackSlideAttempt(localPlayer)
			end)
		end
		pcall(function()
			AnalyticsWrapper.LogCustomEvent(localPlayer, "FTUE_SlideAttempt", 1, { assistType = "SlideAttempt" })
		end)
	end
	if result.slideSucceeded then
		if FTUEAnalytics and FTUEAnalytics.TrackSlideSuccess then
			pcall(function()
				FTUEAnalytics.TrackSlideSuccess(localPlayer)
			end)
		end
		pcall(function()
			AnalyticsWrapper.LogCustomEvent(localPlayer, "FTUE_SlideSuccess", 1, { assistType = "SlideSuccess" })
		end)
	end
	sendIntentIfNeeded(result, frame)
	Input.ConsumeFrameEdges()
	return true
end

function FPSMovementController.Init()
	if renderConnection then
		return
	end
	Input.Init()

	characterConnection = localPlayer.CharacterAdded:Connect(function(character: Model)
		Kernel.Reset(runtime)
		accumulator = 0
		intentElapsed = math.huge
		lastIntentSignature = ""
		baseHipHeight = nil
		baseCameraOffset = Vector3.zero
		updateRaycastFilter(character)
	end)

	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		accumulator += math.min(dt, 0.10)
		local steps = 0
		while accumulator >= Config.FixedStep and steps < Config.MaxCatchUpSteps do
			fixedUpdate()
			accumulator -= Config.FixedStep
			steps += 1
		end
		if steps == Config.MaxCatchUpSteps then
			-- Do not carry an unbounded backlog after a hitch; gameplay recovers on the
			-- next simulation frame rather than executing an expensive catch-up burst.
			accumulator = 0
		end
	end)
end

function FPSMovementController.SetMobileAction(actionName: string, inputState: Enum.UserInputState)
	Input.SetExternalAction(actionName, inputState)
end

function FPSMovementController.SetCrouching(active: boolean)
	Input.SetCrouch(active)
end

function FPSMovementController.Destroy()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if characterConnection then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	Input.Destroy()
	Kernel.Reset(runtime)
	accumulator = 0
	intentElapsed = math.huge
	lastIntentSignature = ""
end

return FPSMovementController
