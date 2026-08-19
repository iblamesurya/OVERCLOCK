--!strict
--[[
	OVERCLOCK: FPSMovementInput
	Place at StarterPlayerScripts.Controllers.FPSMovementInput.

	Normalizes keyboard, gamepad, and external mobile UI into bounded movement
	intent. It never sends positions, velocities, timestamps, or combat data.
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kernel = require(ReplicatedStorage:WaitForChild("Physics"):WaitForChild("FPSMovementKernel") :: ModuleScript)

local FPSMovementInput = {}

local localPlayer = Players.LocalPlayer
local playerModule: any = nil
local initialized = false

local sprintHeld = false
local crouchHeld = false
local crouchPressed = false
local jumpHeld = false
local jumpPressed = false

local ACTION_SPRINT = "OverclockSprint"
local ACTION_CROUCH = "OverclockCrouch"
local ACTION_JUMP = "OverclockJump"

local function setSprint(active: boolean)
	sprintHeld = active
end

local function toggleCrouch()
	crouchHeld = not crouchHeld
	crouchPressed = true
end

local function setJump(active: boolean)
	if active and not jumpHeld then
		jumpPressed = true
	end
	jumpHeld = active
end

local function sprintAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setSprint(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprint(false)
	end
	return Enum.ContextActionResult.Sink
end

local function crouchAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		toggleCrouch()
	end
	return Enum.ContextActionResult.Sink
end

local function jumpAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setJump(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setJump(false)
	end
	return Enum.ContextActionResult.Sink
end

local function getMoveDirection(camera: Camera?): Vector3
	if not playerModule then
		return Vector3.zero
	end
	local controls = playerModule:GetControls()
	if not controls then
		return Vector3.zero
	end

	local raw = controls:GetMoveVector()
	if raw.Magnitude < 0.01 or not camera then
		return Vector3.zero
	end

	local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if forward.Magnitude < 1e-4 or right.Magnitude < 1e-4 then
		return Vector3.zero
	end

	forward = forward.Unit
	right = right.Unit
	local worldDirection = forward * -raw.Z + right * raw.X
	return if worldDirection.Magnitude > 1 then worldDirection.Unit else worldDirection
end

function FPSMovementInput.Init()
	if initialized then
		return
	end
	initialized = true

	task.spawn(function()
		local playerScripts = localPlayer:WaitForChild("PlayerScripts")
		local moduleScript = playerScripts:WaitForChild("PlayerModule")
		playerModule = require(moduleScript)
	end)

	ContextActionService:BindAction(ACTION_SPRINT, sprintAction, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction(ACTION_CROUCH, crouchAction, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction(ACTION_JUMP, jumpAction, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end

function FPSMovementInput.GetFrame(camera: Camera?, locked: boolean): Kernel.InputFrame
	return {
		moveDirection = getMoveDirection(camera),
		sprintHeld = sprintHeld,
		crouchHeld = crouchHeld,
		crouchPressed = crouchPressed,
		jumpPressed = jumpPressed,
		jumpHeld = jumpHeld,
		locked = locked,
	}
end

function FPSMovementInput.ConsumeFrameEdges()
	crouchPressed = false
	jumpPressed = false
end

-- Used by MobileControlsController callbacks. Supported names are "Sprint",
-- "Crouch", and "Jump"; other action names are intentionally ignored.
function FPSMovementInput.SetExternalAction(actionName: string, inputState: Enum.UserInputState)
	if actionName == "Sprint" then
		setSprint(inputState == Enum.UserInputState.Begin)
	elseif actionName == "Crouch" and inputState == Enum.UserInputState.Begin then
		toggleCrouch()
	elseif actionName == "Jump" then
		setJump(inputState == Enum.UserInputState.Begin)
	end
end

function FPSMovementInput.SetCrouch(active: boolean)
	if crouchHeld ~= active then
		crouchHeld = active
		crouchPressed = active
	end
end

function FPSMovementInput.Destroy()
	if not initialized then
		return
	end
	initialized = false
	ContextActionService:UnbindAction(ACTION_SPRINT)
	ContextActionService:UnbindAction(ACTION_CROUCH)
	ContextActionService:UnbindAction(ACTION_JUMP)
	playerModule = nil
	sprintHeld = false
	crouchHeld = false
	crouchPressed = false
	jumpHeld = false
	jumpPressed = false
end

return FPSMovementInput
