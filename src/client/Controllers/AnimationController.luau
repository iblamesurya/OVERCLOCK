--!strict
--[=[
    Project OVERCLOCK: Procedural Animation & Camera Controller
    Manages procedural camera recoil, weapon mouse sway, movement walk bobbing,
    and Aim-Down-Sights (ADS) camera FOV & viewmodel transitions using damped spring physics
    and exponential decay Lerp math.
]=]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Spring = require(game:GetService("ReplicatedStorage"):WaitForChild("Physics"):WaitForChild("Spring"))

export type AnimationState = {
    isAiming: boolean,
    targetFov: number,
    currentFov: number,
    baseFov: number,
    adsAlpha: number, -- 0.0 (Hipfire) to 1.0 (ADS)
    walkSpeed: number,
    isGrounded: boolean,
}

local AnimationController = {}

local isInitialized = false

local loadedTracks: { [string]: AnimationTrack } = {}

-- Springs
local recoilSpring = Spring.new(0.2, 90.0, 12.0)
local cameraRollSpring = Spring.new(0.2, 90.0, 12.0)
local swaySpring = Spring.new(0.2, 140.0, 14.0)
local bobbingSpring = Spring.new(0.25, 120.0, 12.0)

-- State
local state: AnimationState = {
    isAiming = false,
    targetFov = 70.0,
    currentFov = 70.0,
    baseFov = 70.0,
    adsAlpha = 0.0,
    walkSpeed = 0.0,
    isGrounded = true,
}

local bobPhase = 0.0

--[=[
    Exponential Decay Lerp utility function:
    current = Lerp(current, target, 1 - math.exp(-lambda * dt))
]=]
local function ExpDecayLerpNumber(current: number, target: number, lambda: number, dt: number): number
    local alpha = 1.0 - math.exp(-lambda * dt)
    return current + (target - current) * alpha
end

function AnimationController.Init(baseFov: number?): ()
    if isInitialized then
        return
    end

    local fov = baseFov or 70.0
    state.baseFov = fov
    state.targetFov = fov
    state.currentFov = fov
    state.adsAlpha = 0.0

    recoilSpring:Reset()
    swaySpring:Reset()
    bobbingSpring:Reset()

    local localPlayer = game:GetService("Players").LocalPlayer
    if localPlayer then
        localPlayer.CharacterAdded:Connect(function()
            AnimationController.ClearTracks()
        end)
    end

    isInitialized = true
end

function AnimationController.LoadTrack(humanoid: Humanoid, animationId: string, name: string): AnimationTrack?
    if loadedTracks[name] then
        return loadedTracks[name]
    end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    
    local anim = Instance.new("Animation")
    anim.AnimationId = animationId
    local track = animator:LoadAnimation(anim)
    loadedTracks[name] = track
    return track
end

function AnimationController.PlayTrack(name: string)
    local track = loadedTracks[name]
    if track and not track.IsPlaying then
        track:Play()
    end
end

function AnimationController.StopTrack(name: string)
    local track = loadedTracks[name]
    if track and track.IsPlaying then
        track:Stop()
    end
end

function AnimationController.ClearTracks()
    for _, track in loadedTracks do
        track:Stop()
        track:Destroy()
    end
    table.clear(loadedTracks)
end

--[=[
    Triggers visual camera and viewmodel recoil impulse.
    compounds directly with existing momentum via Spring:Impulse.
]=]
function AnimationController.AddRecoil(impulse: Vector3): ()
    recoilSpring:Impulse(impulse)
end

function AnimationController.AddCameraRoll(roll: number): ()
    cameraRollSpring:Impulse(Vector3.new(0, 0, roll))
end

--[=[
    Sets Aim-Down-Sights state and target FOV.
]=]
function AnimationController.SetADS(isAiming: boolean, targetAdsFov: number?): ()
    state.isAiming = isAiming
    state.targetFov = if isAiming then (targetAdsFov or 55.0) else state.baseFov
end

--[=[
    Updates movement status for procedural walk bobbing calculations.
]=]
function AnimationController.UpdateMovementState(humanoid: Humanoid): ()
    if not humanoid then return end
    state.walkSpeed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
    state.isGrounded = humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
end

--[=[
    Performs frame physics update for procedural springs, sway, bobbing, and camera transitions.
]=]
function AnimationController.Update(dt: number): ()
    if not isInitialized then
        AnimationController.Init()
    end

    -- 1. Mouse Sway Update
    local mouseDelta = UserInputService:GetMouseDelta()
    if mouseDelta.Magnitude > 0 then
        local swayMultiplier = if state.isAiming then 0.0003 else 0.001
        local swayImpulse = Vector3.new(
            -mouseDelta.Y * swayMultiplier,
            -mouseDelta.X * swayMultiplier,
            -mouseDelta.X * swayMultiplier * 0.5
        )
        swaySpring:Impulse(swayImpulse)
    end

    -- 2. Walk Bobbing Update
    if state.isGrounded and state.walkSpeed > 1.0 then
        local isSprinting = state.walkSpeed > 18.0
        local bobFrequency = if isSprinting then 12 else 8
        local bobAmplitudeX = if isSprinting then 0.02 else 0.012
        local bobAmplitudeY = if isSprinting then 0.015 else 0.008
        local bobTime = os.clock() * bobFrequency
        local targetBobX = math.sin(bobTime) * bobAmplitudeX
        local targetBobY = math.abs(math.cos(bobTime)) * bobAmplitudeY
        bobbingSpring:SetTarget(Vector3.new(targetBobX, targetBobY, 0))
    else
        bobbingSpring:SetTarget(Vector3.zero)
    end

    -- Update all springs
    recoilSpring:Update(dt)
    cameraRollSpring:Update(dt)
    swaySpring:Update(dt)
    bobbingSpring:Update(dt)

    -- 3. Exponential Decay Lerp for ADS transitions
    local adsLambda = 14.0
    state.currentFov = ExpDecayLerpNumber(state.currentFov, state.targetFov, adsLambda, dt)

    local targetAdsAlpha = if state.isAiming then 1.0 else 0.0
    state.adsAlpha = ExpDecayLerpNumber(state.adsAlpha, targetAdsAlpha, adsLambda, dt)

    -- 4. Apply FOV to Current Camera
    local camera = Workspace.CurrentCamera
    if camera then
        camera.FieldOfView = state.currentFov
    end
end

--[=[
    Returns the procedural camera offset CFrame (recoil pitch/yaw/roll + camera bobbing).
]=]
function AnimationController.GetCameraOffset(): CFrame
    local recoilPos = recoilSpring.Position
    local bobPos = bobbingSpring.Position

    local rollPos = cameraRollSpring.Position

    return CFrame.Angles(recoilPos.X, recoilPos.Y, rollPos.Z)
        * CFrame.new(bobPos.X * 0.3, bobPos.Y * 0.3, 0)
end

--[=[
    Returns procedural viewmodel offset CFrame combining sway, bobbing, recoil kick, and ADS lerp.
]=]
function AnimationController.GetViewmodelOffset(): CFrame
    local recoilPos = recoilSpring.Position
    local swayPos = swaySpring.Position
    local bobPos = bobbingSpring.Position

    -- Viewmodel kickback from Z recoil
    local kickCFrame = CFrame.new(0, 0, recoilPos.Z * 0.5)
    local swayCFrame = CFrame.Angles(swayPos.X, swayPos.Y, swayPos.Z) * CFrame.new(swayPos.Y * 0.2, -swayPos.X * 0.2, 0)
    local bobbingCFrame = CFrame.new(bobPos.X, bobPos.Y, 0)

    -- Combine hipfire procedural offsets
    local combinedHipfire = swayCFrame * bobbingCFrame * kickCFrame

    -- Lerp towards ADS centered CFrame (reduced sway and bobbing in ADS)
    local adsReducedHipfire = CFrame.new():Lerp(combinedHipfire, 1.0 - state.adsAlpha * 0.7)

    return adsReducedHipfire
end

function AnimationController.GetADSAlpha(): number
    return state.adsAlpha
end

function AnimationController.GetState(): AnimationState
    return state
end

return AnimationController
