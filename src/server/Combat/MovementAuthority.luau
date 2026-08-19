--!strict
--[[
	OVERCLOCK: MovementAuthority
	Place at ServerScriptService.Combat.MovementAuthority.

	The client submits bounded movement intent only. This service samples the real
	HumanoidRootPart on the server, applies a movement-state envelope, corrects
	impossible physics, and emits server-time rollback snapshots. It never accepts
	client positions, velocities, CFrames, or client clocks as authoritative.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Physics"):WaitForChild("FPSMovementConfig") :: ModuleScript)

-- FTUE movement assists wiring (server-authoritative slide telemetry)
local FTUEAnalytics: any = nil
pcall(function()
	local ServerScriptService = game:GetService("ServerScriptService")
	local services = ServerScriptService:FindFirstChild("Services")
	if services then
		local mod = services:FindFirstChild("FTUEAnalytics")
		if mod then
			FTUEAnalytics = require(mod :: any)
		end
	end
end)

export type SnapshotSink = (userId: number, position: Vector3, velocity: Vector3, cframe: CFrame, timestamp: number) -> ()

export type Intent = {
	sequence: number,
	moveX: number,
	moveZ: number,
	sprint: boolean,
	crouch: boolean,
	slide: boolean,
	jump: boolean,
}

type PlayerAuthorityState = {
	lastPosition: Vector3,
	lastVelocity: Vector3,
	lastSafeCFrame: CFrame,
	lastSampleAt: number,
	lastIntentAt: number,
	lastSequence: number,
	stamina: number,
	slideUntil: number,
	slideCooldownUntil: number,
	teleportGraceUntil: number,
	violations: number,
	lastViolationAt: number,
	intent: Intent,
	registered: boolean,
}

export type MovementAuthorityClass = {
	_states: { [number]: PlayerAuthorityState },
	_snapshotSink: SnapshotSink?,
	_connection: RBXScriptConnection?,
	_accumulator: number,
	Register: (self: MovementAuthorityClass, player: Player) -> (),
	Remove: (self: MovementAuthorityClass, player: Player) -> (),
	SetIntent: (self: MovementAuthorityClass, player: Player, payload: any) -> boolean,
	NotifyTeleport: (self: MovementAuthorityClass, player: Player) -> (),
	SetSnapshotSink: (self: MovementAuthorityClass, sink: SnapshotSink?) -> (),
	Start: (self: MovementAuthorityClass) -> (),
	Stop: (self: MovementAuthorityClass) -> (),
	Step: (self: MovementAuthorityClass, now: number) -> (),
	_correct: (self: MovementAuthorityClass, player: Player, state: PlayerAuthorityState, root: BasePart) -> (),
	_samplePlayer: (self: MovementAuthorityClass, player: Player, state: PlayerAuthorityState, now: number) -> (),
}

local MovementAuthority = {}
MovementAuthority.__index = MovementAuthority

local activeAuthority: MovementAuthorityClass? = nil

local EMPTY_INTENT: Intent = {
	sequence = 0,
	moveX = 0,
	moveZ = 0,
	sprint = false,
	crouch = false,
	slide = false,
	jump = false,
}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function finiteVector(vector: Vector3): boolean
	return vector.X == vector.X
		and vector.Y == vector.Y
		and vector.Z == vector.Z
		and math.abs(vector.X) < 1e6
		and math.abs(vector.Y) < 1e6
		and math.abs(vector.Z) < 1e6
end

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
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

local function makeState(root: BasePart, now: number): PlayerAuthorityState
	return {
		lastPosition = root.Position,
		lastVelocity = root.AssemblyLinearVelocity,
		lastSafeCFrame = root.CFrame,
		lastSampleAt = now,
		lastIntentAt = -math.huge,
		lastSequence = -1,
		stamina = Config.MaxStamina,
		slideUntil = -math.huge,
		slideCooldownUntil = -math.huge,
		teleportGraceUntil = now + Config.ServerAuthorizedTeleportGraceSeconds,
		violations = 0,
		lastViolationAt = -math.huge,
		intent = table.clone(EMPTY_INTENT),
		registered = true,
	}
end

local function normalizedInputMagnitude(intent: Intent): number
	return math.min(1, math.sqrt(intent.moveX * intent.moveX + intent.moveZ * intent.moveZ))
end

local function updateServerMovementState(player: Player, state: PlayerAuthorityState, horizontalSpeed: number, dt: number, now: number): (boolean, boolean, boolean, number)
	local intent = state.intent
	local hasInput = normalizedInputMagnitude(intent) >= Config.SlideInputThreshold
	local sliding = now < state.slideUntil

	-- FTUE slide attempt tracking: any press of slide intent while sprinting with input counts as attempt
	local slideAttempted = intent.slide and hasInput and intent.sprint
	if slideAttempted and FTUEAnalytics and FTUEAnalytics.TrackSlideAttempt then
		pcall(function()
			FTUEAnalytics.TrackSlideAttempt(player)
		end)
	end

	if intent.slide
		and not sliding
		and now >= state.slideCooldownUntil
		and horizontalSpeed >= Config.MinSlideEntrySpeed
		and hasInput
		and intent.sprint
	then
		state.slideUntil = now + Config.SlideDuration
		state.slideCooldownUntil = now + Config.SlideCooldownSeconds
		sliding = true
		if FTUEAnalytics and FTUEAnalytics.TrackSlideSuccess then
			pcall(function()
				FTUEAnalytics.TrackSlideSuccess(player)
			end)
		end
	end

	if sliding and (horizontalSpeed < Config.MinSlideSpeed or now >= state.slideUntil) then
		state.slideUntil = -math.huge
		sliding = false
	end

	local sprinting = intent.sprint
		and hasInput
		and not intent.crouch
		and not sliding
		and state.stamina >= Config.MinStaminaToStartSprint

	if sprinting then
		state.stamina = math.max(0, state.stamina - Config.SprintDrainPerSecond * dt)
	else
		state.stamina = math.min(Config.MaxStamina, state.stamina + Config.SprintRecoveryPerSecond * dt)
	end

	local crouching = intent.crouch or sliding
	local legalSpeed = Config.GetMaxLegalHorizontalSpeed(sprinting, crouching, sliding)

	player:SetAttribute("ServerMovementState", if sliding then "Slide" elseif crouching then "Crouch" elseif sprinting then "Sprint" elseif hasInput then "Run" else "Idle")
	player:SetAttribute("ServerMovementStamina", math.round(state.stamina * 10) / 10)
	player:SetAttribute("ServerIsSprinting", sprinting)
	player:SetAttribute("ServerIsSliding", sliding)
	player:SetAttribute("ServerIsCrouching", crouching)
	return sprinting, crouching, sliding, legalSpeed
end

local function maximumDistance(legalSpeed: number, dt: number): number
	return (legalSpeed * Config.ServerSpeedToleranceMultiplier + Config.ServerBaseSpeedTolerance) * dt + 1.2
end

function MovementAuthority.new(): MovementAuthorityClass
	local self = setmetatable({
		_states = {} :: { [number]: PlayerAuthorityState },
		_snapshotSink = nil :: SnapshotSink?,
		_connection = nil :: RBXScriptConnection?,
		_accumulator = 0,
	}, MovementAuthority)
	activeAuthority = self :: any
	return self :: any
end

-- Compatibility bridge for server-side spawn/void-rescue systems. It is not
-- exposed to clients and does not accept a client-supplied destination.
function MovementAuthority.NotifyActiveTeleport(player: Player)
	if activeAuthority then
		activeAuthority:NotifyTeleport(player)
	end
end

function MovementAuthority:Register(player: Player)
	local _, humanoid, root = getCharacterParts(player)
	if not humanoid or not root then
		return
	end
	local now = Workspace:GetServerTimeNow()
	self._states[player.UserId] = makeState(root, now)
	player:SetAttribute("ServerMovementState", "Idle")
	player:SetAttribute("ServerMovementStamina", Config.MaxStamina)
end

function MovementAuthority:Remove(player: Player)
	self._states[player.UserId] = nil
end

function MovementAuthority:SetSnapshotSink(sink: SnapshotSink?)
	self._snapshotSink = sink
end

function MovementAuthority:NotifyTeleport(player: Player)
	local _, _, root = getCharacterParts(player)
	if not root then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local state = self._states[player.UserId]
	if not state then
		self._states[player.UserId] = makeState(root, now)
		return
	end
	state.lastPosition = root.Position
	state.lastVelocity = root.AssemblyLinearVelocity
	state.lastSafeCFrame = root.CFrame
	state.lastSampleAt = now
	state.teleportGraceUntil = now + Config.ServerAuthorizedTeleportGraceSeconds
	state.violations = 0
end

function MovementAuthority:SetIntent(player: Player, payload: any): boolean
	if type(payload) ~= "table" then
		return false
	end
	local sequence = payload.sequence
	local moveX = payload.moveX
	local moveZ = payload.moveZ
	if not finiteNumber(sequence) or sequence ~= math.floor(sequence) or sequence < 0 then
		return false
	end
	if not finiteNumber(moveX) or not finiteNumber(moveZ) or math.abs(moveX) > 1.05 or math.abs(moveZ) > 1.05 then
		return false
	end
	if type(payload.sprint) ~= "boolean" or type(payload.crouch) ~= "boolean" or type(payload.slide) ~= "boolean" or type(payload.jump) ~= "boolean" then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local state = self._states[player.UserId]
	if not state then
		self:Register(player)
		state = self._states[player.UserId]
	end
	if not state then
		return false
	end

	local minimumInterval = 1 / Config.IntentRateLimitPerSecond
	if now - state.lastIntentAt < minimumInterval then
		return false
	end
	if sequence <= state.lastSequence then
		return false
	end

	state.lastIntentAt = now
	state.lastSequence = sequence
	state.intent = {
		sequence = sequence,
		moveX = math.clamp(moveX, -1, 1),
		moveZ = math.clamp(moveZ, -1, 1),
		sprint = payload.sprint,
		crouch = payload.crouch,
		slide = payload.slide,
		jump = payload.jump,
	}
	return true
end

function MovementAuthority:_correct(player: Player, state: PlayerAuthorityState, root: BasePart)
	root.CFrame = state.lastSafeCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	state.lastPosition = root.Position
	state.lastVelocity = Vector3.zero
	state.teleportGraceUntil = Workspace:GetServerTimeNow() + 0.35
end

function MovementAuthority:_samplePlayer(player: Player, state: PlayerAuthorityState, now: number)
	local _, humanoid, root = getCharacterParts(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local playerState = player:GetAttribute("PlayerState")
	if playerState ~= nil and playerState ~= "Playing" and playerState ~= "PracticeRange" then
		state.lastPosition = root.Position
		state.lastVelocity = root.AssemblyLinearVelocity
		state.lastSafeCFrame = root.CFrame
		state.lastSampleAt = now
		return
	end

	local dt = math.clamp(now - state.lastSampleAt, 1 / 120, 0.25)
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	if not finiteVector(position) or not finiteVector(velocity) then
		self:_correct(player, state, root)
		return
	end

	if now <= state.teleportGraceUntil then
		state.lastPosition = position
		state.lastVelocity = velocity
		state.lastSafeCFrame = root.CFrame
		state.lastSampleAt = now
		if self._snapshotSink then
			self._snapshotSink(player.UserId, position, velocity, root.CFrame, now)
		end
		return
	end

	local horizontalVelocity = horizontal(velocity)
	local horizontalSpeed = horizontalVelocity.Magnitude
	local sprinting, crouching, sliding, legalSpeed = updateServerMovementState(player, state, horizontalSpeed, dt, now)
	local displacement = horizontal(position - state.lastPosition).Magnitude
	local totalDisplacement = (position - state.lastPosition).Magnitude
	local speedLimit = legalSpeed * Config.ServerSpeedToleranceMultiplier + Config.ServerBaseSpeedTolerance
	local positionLimit = maximumDistance(legalSpeed, dt)
	local exceedsVerticalEnvelope = velocity.Y > Config.ServerMaxUpwardVelocity
	local isLargeTeleport = totalDisplacement > Config.ServerTeleportDistance

	local violation = horizontalSpeed > speedLimit
		or displacement > positionLimit
		or exceedsVerticalEnvelope
		or isLargeTeleport
	if violation then
		if now - state.lastViolationAt > Config.ServerViolationDecaySeconds then
			state.violations = 0
		end
		state.violations += 1
		state.lastViolationAt = now
		if state.violations >= Config.ServerViolationLimit then
			self:_correct(player, state, root)
			state.violations = 0
		end
	else
		if now - state.lastViolationAt > Config.ServerViolationDecaySeconds then
			state.violations = math.max(0, state.violations - 1)
		end
		state.lastSafeCFrame = root.CFrame
		state.lastPosition = position
		state.lastVelocity = velocity
	end

	-- Server keeps the normal Humanoid envelope aligned with its state. The client
	-- may present acceleration more frequently, but cannot permanently set a faster
	-- legal state than this server envelope.
	humanoid.WalkSpeed = if sliding then 0 else Config.GetMaxLegalHorizontalSpeed(sprinting, crouching, false)
	state.lastSampleAt = now

	if self._snapshotSink then
		self._snapshotSink(player.UserId, root.Position, root.AssemblyLinearVelocity, root.CFrame, now)
	end
end

function MovementAuthority:Step(now: number)
	for userId, state in self._states do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:_samplePlayer(player, state, now)
		else
			self._states[userId] = nil
		end
	end
end

function MovementAuthority:Start()
	if self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(dt: number)
		self._accumulator += math.min(dt, 0.25)
		local interval = 1 / Config.ServerSampleHz
		if self._accumulator < interval then
			return
		end
		self._accumulator %= interval
		self:Step(Workspace:GetServerTimeNow())
	end)
end

function MovementAuthority:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	table.clear(self._states)
	self._accumulator = 0
	if activeAuthority == self then
		activeAuthority = nil
	end
end

return MovementAuthority
