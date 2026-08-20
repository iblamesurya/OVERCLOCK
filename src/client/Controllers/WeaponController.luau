--!strict
--[=[
    Project OVERCLOCK: Client Weapon Controller
    Handles local weapon prediction, high-frequency fixed time-step physics accumulation,
    exponential decay stat transitions, instant visual recoil, muzzle flash, raycast tracer
    rendering, and client-server combat network synchronization.
]=]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local PhysicsFolder = ReplicatedStorage:WaitForChild("Physics")
local DataFolder = ReplicatedStorage:WaitForChild("Data")

local WeaponStats = require(DataFolder:WaitForChild("WeaponStats") :: any)
local ObjectPool = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("ObjectPool"))
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents"))
local BufferSerializer = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("BufferSerializer") :: any)
local BallisticPhysics = require(ReplicatedStorage:WaitForChild("Physics"):WaitForChild("BallisticPhysics") :: any)

local ControllersFolder = script.Parent
local CrosshairController = require(ControllersFolder:WaitForChild("CrosshairController") :: any)
local AnimationController = require(ControllersFolder:WaitForChild("AnimationController") :: any)
local HUDController = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("HUDController") :: any)
local ScopeOverlayController = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ScopeOverlayController") :: any)
local PremiumWeaponPresentation = require(ControllersFolder:WaitForChild("PremiumWeaponPresentation") :: ModuleScript)

export type WeaponState = {
    weaponId: string,
    currentAmmo: number,
    reserveAmmo: number,
    isReloading: boolean,
    isFiring: boolean,
    isAiming: boolean,
    currentSpread: number,
    lastFireTimestamp: number,
    burstShotsRemaining: number,
}

local WeaponController = {}

local isInitialized = false
local currentWeaponState: WeaponState? = nil
local activeStats: WeaponStats.WeaponData? = nil
local savedFOV = 70
local originalSensitivity = 1.0
local currentWeaponModel: Model? = nil
local isCombatPhase = false

local localLoadout = {
    Primary = "AssaultRifle",
    Secondary = "Pistol",
    Grenade = "Grenade"
}
local shotSequenceId = 0
local rng = Random.new()

-- Fixed time-step accumulator state
local dtAccumulator = 0.0
local FIXED_DT = 1.0 / 60.0 -- 60 Hz fixed physics tick

-- Network remote references (optional connection for server validation)
local remoteEvent: RemoteEvent? = nil

-- Raycast filter parameters
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

--[=[
    Exponential Decay Lerp Helper function:
    current = Lerp(current, target, 1 - math.exp(-lambda * dt))
]=]
local function ExpDecayLerpNumber(current: number, target: number, lambda: number, dt: number): number
    local alpha = 1.0 - math.exp(-lambda * dt)
    return current + (target - current) * alpha
end

local muzzleFlashPool: any = nil
local tracerPool: any = nil
local impactPool: any = nil
local tracerBeamTemplate: Beam? = nil
local impactTemplateRef: Part? = nil
local attachmentPool: any = nil
local effectsFolder: Folder? = nil

local function getEffectsFolder(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local found = Workspace:FindFirstChild("Effects")
	if found and found:IsA("Folder") then
		effectsFolder = found
		return found
	end
	local f = Instance.new("Folder")
	f.Name = "Effects"
	f.Parent = Workspace
	effectsFolder = f
	return f
end

local function initPools()
    -- Premium muzzle — correct emissive, no purple/blue aurora
    local flashTemplate = Instance.new("Part")
    flashTemplate.Size = Vector3.new(0.14, 0.14, 0.14)
    flashTemplate.Material = Enum.Material.Neon
    flashTemplate.Color = Color3.fromRGB(255, 210, 120) -- warm brass emissive, not purple/indigo
    flashTemplate.Anchored = true
    flashTemplate.CanCollide = false
    flashTemplate.CanQuery = false
    flashTemplate.Transparency = 0.2
    flashTemplate.Shape = Enum.PartType.Ball
    local light = Instance.new("PointLight")
    light.Brightness = 1.2
    light.Range = 4
    light.Shadows = false
    light.Color = Color3.fromRGB(255, 210, 120)
    light.Parent = flashTemplate
    muzzleFlashPool = ObjectPool.new(flashTemplate, 12)

    -- Tracer — community best-practice: Neon head sphere (kept sized) + Beam tail (slightly big, visible) — refs: WeaponKit/ACS Beam tracer + Particle impact
    local tracerHeadTemplate = Instance.new("Part")
    tracerHeadTemplate.Name = "TracerHead"
    tracerHeadTemplate.Shape = Enum.PartType.Ball
    tracerHeadTemplate.Size = Vector3.new(0.28, 0.28, 0.28)
    tracerHeadTemplate.Material = Enum.Material.Neon
    tracerHeadTemplate.Color = Color3.fromRGB(255, 240, 180)
    tracerHeadTemplate.Anchored = true
    tracerHeadTemplate.CanCollide = false
    tracerHeadTemplate.CanQuery = false
    tracerHeadTemplate.CanTouch = false
    tracerHeadTemplate.Transparency = 0.05

    -- Beam tail template (cloned per shot): community standard for visible hitscan tail - FaceCamera + slightly big width
    local beamTemplate = Instance.new("Beam")
    beamTemplate.Name = "TracerBeam"
    beamTemplate.Color = ColorSequence.new(Color3.fromRGB(255, 238, 140))
    beamTemplate.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.15)})
    beamTemplate.Width0 = 0.38
    beamTemplate.Width1 = 0.22
    beamTemplate.LightEmission = 0.85
    beamTemplate.LightInfluence = 0
    beamTemplate.FaceCamera = true
    beamTemplate.Segments = 1
    beamTemplate.Attachment0 = Instance.new("Attachment")
    beamTemplate.Attachment1 = Instance.new("Attachment")

    -- Impact burst template (sphere + PointLight + ParticleEmitter)
    local impactTemplate = Instance.new("Part")
    impactTemplate.Name = "ImpactBurst"
    impactTemplate.Shape = Enum.PartType.Ball
    impactTemplate.Size = Vector3.new(0.45, 0.45, 0.45)
    impactTemplate.Material = Enum.Material.Neon
    impactTemplate.Color = Color3.fromRGB(255, 230, 90)
    impactTemplate.Anchored = true
    impactTemplate.CanCollide = false
    impactTemplate.CanQuery = false
    impactTemplate.CanTouch = false
    impactTemplate.Transparency = 0.1
    local impactLight = Instance.new("PointLight")
    impactLight.Color = Color3.fromRGB(255, 235, 120)
    impactLight.Range = 8
    impactLight.Brightness = 2.5
    impactLight.Shadows = false
    impactLight.Parent = impactTemplate
    local spark = Instance.new("ParticleEmitter")
    spark.Name = "ImpactSpark"
    spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    spark.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160))
    spark.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
    spark.Lifetime = NumberRange.new(0.12, 0.18)
    spark.Rate = 0
    spark.Speed = NumberRange.new(12, 18)
    spark.SpreadAngle = Vector2.new(180, 180)
    spark.LockedToPart = false
    spark.Parent = impactTemplate

    tracerPool = ObjectPool.new(tracerHeadTemplate, 24)
    tracerBeamTemplate = beamTemplate
    impactTemplateRef = impactTemplate

    -- Detach temp templates (pooled clones will be parented to Effects)
    tracerHeadTemplate.Parent = nil
    beamTemplate.Parent = nil
    impactTemplate.Parent = nil

    -- Impact burst pooled via ObjectPool (Neon head + PointLight + ParticleEmitter)
    impactPool = ObjectPool.new({
        template = function(): Instance
            local clone = (impactTemplateRef :: Part):Clone()
            return clone
        end,
        initialSize = 16,
        container = getEffectsFolder(),
        resetHandler = function(inst: Instance)
            if inst:IsA("BasePart") then
                local p = inst :: Part
                p.Transparency = 1
                p.CFrame = CFrame.new(0, -9999, 0)
                p.Anchored = true
            end
        end,
        getHandler = function(inst: Instance)
            if inst:IsA("BasePart") then
                local p = inst :: Part
                p.Transparency = 0.1
            end
        end,
    })

    -- Attachment pooling for Beam endpoints (reduce Instance.new GC on 600 RPM)
    attachmentPool = ObjectPool.new({
        template = function(): Instance
            return Instance.new("Attachment")
        end,
        initialSize = 32,
        container = getEffectsFolder(),
        resetHandler = function(inst: Instance)
            inst.Parent = getEffectsFolder()
        end,
        getHandler = function(inst: Instance)
        end,
    })
end

--[=[
    Renders an instant local muzzle flash effect at the specified origin.
]=]
local function RenderMuzzleFlash(originCFrame: CFrame): ()
    local flashPart = muzzleFlashPool:Get()
    flashPart.CFrame = originCFrame
    flashPart.Parent = Workspace

    task.delay(0.03, function()
        if flashPart and flashPart.Parent then
            flashPart.Parent = nil
        end
        muzzleFlashPool:Return(flashPart)
    end)
end

--[=[
    Renders a moving local bullet tracer projectile from muzzle origin to target hit position (Evostrike style).
]=]
local function RenderTracer(originPos: Vector3, targetPos: Vector3): ()
    local distance = (targetPos - originPos).Magnitude
    if distance < 1 then return end

    local effects = getEffectsFolder()
    -- Head sphere (kept sized 0.28) + slightly big Beam tail 0.38->0.22 FaceCamera true — community Beam+Particle pattern
    local head = tracerPool:Get()
    head.CFrame = CFrame.new(originPos)
    head.Transparency = 0.05
    head.Parent = effects

    -- Tail beam: two pooled attachments + cloned Beam (Width0 0.38 Width1 0.22 FaceCamera true)
    local a0: Instance = if attachmentPool then attachmentPool:Get() else Instance.new("Attachment")
    ;(a0 :: Attachment).WorldPosition = originPos
    a0.Parent = effects
    local a1: Instance = if attachmentPool then attachmentPool:Get() else Instance.new("Attachment")
    ;(a1 :: Attachment).WorldPosition = targetPos
    a1.Parent = effects
    local beam: Beam
    if tracerBeamTemplate then
        beam = (tracerBeamTemplate :: Beam):Clone()
        beam.Width0 = 0.38
        beam.Width1 = 0.22
        beam.FaceCamera = true
    else
        beam = Instance.new("Beam")
        beam.Width0 = 0.38
        beam.Width1 = 0.22
        beam.FaceCamera = true
        beam.Color = ColorSequence.new(Color3.fromRGB(255, 238, 140))
        beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.15)})
        beam.LightEmission = 0.85
    end
    beam.Attachment0 = a0 :: Attachment
    beam.Attachment1 = a1 :: Attachment
    beam.Enabled = true
    beam.Parent = effects

    -- Instant hitscan tracer: use near-instant travel to fix "very very slow" ray. Keep ball sized but tail slightly big.
    local baseSpeed = if activeStats then activeStats.bulletVelocity else 2600
    local speed = math.max(8500, baseSpeed * 3.2)
    local travelTime = math.clamp(distance / speed, 0.018, 0.075)
    -- Animate head travelling, beam follows via attachment
    local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(head, tweenInfo, {CFrame = CFrame.new(targetPos)})
    tween.Completed:Connect(function()
        -- Impact burst at hit point (visible hit) — pooled ObjectPool
        local impact: Instance = if impactPool then impactPool:Get() else ((impactTemplateRef :: Part):Clone() :: Instance)
        local impactPart = impact :: Part
        impactPart.CFrame = CFrame.new(targetPos)
        impactPart.Size = Vector3.new(0.45, 0.45, 0.45)
        impactPart.Transparency = 0.1
        impactPart.Parent = effects
        local emitter = impact:FindFirstChild("ImpactSpark") :: ParticleEmitter?
        if emitter then emitter:Emit(14) end
        -- Light fade + shrink then return to pool
        task.spawn(function()
            for i=1,6 do
                if impactPart.Parent then
                    impactPart.Transparency = 0.1 + i*0.15
                    impactPart.Size = Vector3.new(0.45,0.45,0.45) * (1 + i*0.18)
                end
                task.wait(0.015)
            end
            if impactPool then
                impactPool:Return(impact)
            else
                impact:Destroy()
            end
        end)
        -- Cleanup beam/attachments/head
        beam:Destroy()
        if attachmentPool then
            attachmentPool:Return(a0)
            attachmentPool:Return(a1)
        else
            a0:Destroy()
            a1:Destroy()
        end
        ;(head :: Instance).Parent = nil
        tracerPool:Return(head)
    end)
    tween:Play()
    -- Fade beam quickly after travel
    task.delay(travelTime + 0.04, function()
        if beam and beam.Parent then
            for i=1,4 do
                if beam.Parent then
                    beam.Transparency = NumberSequence.new(0.25*i)
                end
                task.wait(0.012)
            end
        end
    end)
end

local function RenderImpactOnly(pos: Vector3): ()
    local effects = getEffectsFolder()
    local impact: Instance = if impactPool then impactPool:Get() else ((impactTemplateRef :: Part):Clone() :: Instance)
    local impactPart = impact :: Part
    impactPart.CFrame = CFrame.new(pos)
    impactPart.Size = Vector3.new(0.45, 0.45, 0.45)
    impactPart.Transparency = 0.1
    impactPart.Parent = effects
    local emitter = impact:FindFirstChild("ImpactSpark") :: ParticleEmitter?
    if emitter then emitter:Emit(12) end
    task.delay(0.09, function()
        if impactPool and impact.Parent then
            impactPool:Return(impact)
        elseif impact.Parent then
            impact:Destroy()
        end
    end)
end

local function updateRaycastFilter(): ()
	local filterList = {}
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.Character then
		table.insert(filterList, localPlayer.Character)
	end
	if currentWeaponModel then
		table.insert(filterList, currentWeaponModel)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(filterList, camera)
	end
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterList
end

-- Camera-relative muzzle offsets per weapon class (first-person fallback).
-- Right +X, Down -Y, Forward -Z in camera local space.
local MUZZLE_OFFSETS: { [string]: Vector3 } = {
	Pistol       = Vector3.new(0.35, -0.30, -0.5),
	AssaultRifle = Vector3.new(0.40, -0.35, -0.8),
	SniperRifle  = Vector3.new(0.40, -0.35, -1.0),
	Shotgun      = Vector3.new(0.40, -0.35, -0.8),
}
local DEFAULT_MUZZLE_OFFSET = Vector3.new(0.35, -0.30, -0.6)

-- Threshold: if camera is within this many studs of the head, treat as first-person.
local FIRST_PERSON_THRESHOLD = 2.0

local function getMuzzleOrigin(camCFrame: CFrame): Vector3
	if currentWeaponModel then
		local firePoint = currentWeaponModel:FindFirstChild("FirePoint", true)
		if firePoint and firePoint:IsA("Attachment") then
			return firePoint.WorldPosition
		end
	end
	
	-- Fallback
	local weaponId = if currentWeaponState then currentWeaponState.weaponId else nil
	local offset = if weaponId then (MUZZLE_OFFSETS[weaponId] or DEFAULT_MUZZLE_OFFSET) else DEFAULT_MUZZLE_OFFSET
	return (camCFrame * CFrame.new(offset)).Position
end

--[=[
    Executes instant local prediction for firing a weapon shot.
]=]
local function FireShot(isAccumulated: boolean?): ()
	if not currentWeaponState or not activeStats then return end

	local now = os.clock()
	local fireInterval = 60.0 / activeStats.fireRate
	if not isAccumulated then
		if now - currentWeaponState.lastFireTimestamp < fireInterval then
			return
		end
		currentWeaponState.lastFireTimestamp = now
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	if currentWeaponState.currentAmmo <= 0 then
		WeaponController.ReloadWeapon()
		return
	end

	currentWeaponState.currentAmmo -= 1

	local isAiming = currentWeaponState.isAiming
	local spreadDeg = currentWeaponState.currentSpread * (if isAiming then 0.5 else 1.0)
	local camCFrame = camera.CFrame
	local rayDirection = CrosshairController.GetSpreadDirection(camCFrame, spreadDeg)

	currentWeaponState.currentSpread = math.min(
		activeStats.spreadMax,
		currentWeaponState.currentSpread + activeStats.spreadIncreasePerShot
	)

	updateRaycastFilter()

	local aimOrigin = camCFrame.Position

	-- Visual muzzle origin
	local muzzleOrigin = getMuzzleOrigin(camCFrame)
	local targetHitPos: Vector3

	-- INSTANT HITSCAN: server remains authoritative (CombatService raycasts WeaponRay), client does instant visual ray.
	-- Only Grenade uses BallisticPhysics projectile; all others are hitscan to fix "very very slow" ray.
	if activeStats.id == "Grenade" then
		local velocityMod = activeStats.bulletVelocity or 800
		BallisticPhysics.FireProjectile({
			shooterId = Players.LocalPlayer.UserId,
			weaponId = activeStats.id,
			origin = aimOrigin,
			direction = rayDirection,
			velocityMod = velocityMod,
			gravityMult = 1.0,
			maxRange = activeStats.maxRange,
			damage = activeStats.damage,
			raycastParams = raycastParams,
			onHit = function(hitResult, proj)
				local hitInstance = hitResult.Instance
				local hitPos = hitResult.Position
				local isHeadshot = false
				if hitInstance and hitInstance.Name == "Head" then isHeadshot = true end
				local character = hitInstance and hitInstance:FindFirstAncestorOfClass("Model")
				if character and character:FindFirstChildOfClass("Humanoid") then
					CrosshairController.ShowHitmarker(isHeadshot)
				elseif hitInstance and (hitInstance:GetAttribute("IsTarget") == true or string.find(hitInstance.Name, "Target") ~= nil or hitInstance.Name == "Bullseye" or string.find(hitInstance.Name, "TargetRing_") ~= nil) then
					CrosshairController.ShowHitmarker(false)
				end
				local combatRemote = RemoteEvents.GetReliable("ReliableCombat")
				if combatRemote and hitInstance then
					local targetModel = hitInstance:FindFirstAncestorOfClass("Model")
					local victimPlayer = if targetModel then Players:GetPlayerFromCharacter(targetModel) else nil
					combatRemote:FireServer({
						action = "ReportHit",
						payload = {
							victimUserId = if victimPlayer then victimPlayer.UserId else 0,
							hitData = {
								origin = proj.origin,
								direction = proj.velocity.Unit,
								hitPosition = hitPos,
								distance = (hitPos - proj.origin).Magnitude,
								clientTimestamp = os.clock(),
								sequenceId = shotSequenceId,
								weaponId = activeStats.id,
								targetInstance = hitInstance,
							}
						}
					})
				end
			end,
		})
		targetHitPos = aimOrigin + rayDirection * activeStats.maxRange
		shotSequenceId += 1
		local unreliableCombat = RemoteEvents.GetUnreliable("UnreliableCombat")
		if unreliableCombat then
			local bufferData = BufferSerializer.SerializeFireIntent(aimOrigin, rayDirection)
			unreliableCombat:FireServer(bufferData)
		end
	else
		local rayResult = Workspace:Raycast(aimOrigin, rayDirection * activeStats.maxRange, raycastParams)
		if rayResult then
			targetHitPos = rayResult.Position
			local hitInstance: Instance? = rayResult.Instance
			local hitPos = rayResult.Position
			local isHeadshot = false
			if hitInstance and hitInstance.Name == "Head" then isHeadshot = true end
			local character = hitInstance and hitInstance:FindFirstAncestorOfClass("Model")
			if character and character:FindFirstChildOfClass("Humanoid") then
				CrosshairController.ShowHitmarker(isHeadshot)
			elseif hitInstance and (hitInstance:GetAttribute("IsTarget") == true or string.find(hitInstance.Name, "Target") ~= nil or hitInstance.Name == "Bullseye" or string.find(hitInstance.Name, "TargetRing_") ~= nil) then
				CrosshairController.ShowHitmarker(false)
			end
			local combatRemote = RemoteEvents.GetReliable("ReliableCombat")
			if combatRemote and hitInstance then
				local targetModel = hitInstance:FindFirstAncestorOfClass("Model")
				local victimPlayer = if targetModel then Players:GetPlayerFromCharacter(targetModel) else nil
				shotSequenceId += 1
				combatRemote:FireServer({
					action = "ReportHit",
					payload = {
						victimUserId = if victimPlayer then victimPlayer.UserId else 0,
						hitData = {
							origin = aimOrigin,
							direction = rayDirection,
							hitPosition = hitPos,
							distance = (hitPos - aimOrigin).Magnitude,
							clientTimestamp = os.clock(),
							sequenceId = shotSequenceId,
							weaponId = activeStats.id,
							targetInstance = hitInstance,
						}
					}
				})
			else
				shotSequenceId += 1
			end
		else
			targetHitPos = aimOrigin + rayDirection * activeStats.maxRange
			shotSequenceId += 1
		end
		local unreliableCombat = RemoteEvents.GetUnreliable("UnreliableCombat")
		if unreliableCombat then
			local bufferData = BufferSerializer.SerializeFireIntent(aimOrigin, rayDirection)
			unreliableCombat:FireServer(bufferData)
		end
	end

	local baseRecoil = if isAiming then activeStats.recoilImpulseADS else activeStats.recoilImpulse
	local yawVariation = rng:NextNumber(-0.35, 0.35) * baseRecoil.Y
	AnimationController.AddRecoil(Vector3.new(baseRecoil.X * 0.85, yawVariation, baseRecoil.Z * 0.85))

	RenderMuzzleFlash(CFrame.lookAt(muzzleOrigin, targetHitPos))
	RenderTracer(muzzleOrigin, targetHitPos)
end

--[=[
    Fixed time-step physics update logic (executed at exact 60Hz intervals).
    Guarantees deterministic physics execution regardless of client FPS (30 FPS to 240+ FPS).
]=]
function WeaponController.FixedUpdate(fixedDt: number): ()
    if not currentWeaponState or not activeStats then
        return
    end

    -- Spread recovery logic using exponential decay towards min spread
    local targetSpread = activeStats.spreadMin
    currentWeaponState.currentSpread = ExpDecayLerpNumber(
        currentWeaponState.currentSpread,
        targetSpread,
        activeStats.spreadRecoveryRate,
        fixedDt
    )
end

--[=[
    Render frame update logic (runs every frame on RenderStepped).
    Handles fixed timestep accumulator polling and smooth exponential decay lerping.
]=]
function WeaponController.RenderUpdate(dt: number): ()
    if not currentWeaponState or not activeStats then
        return
    end

    -- 1. Fixed Time-Step Accumulator Pattern (60Hz capped, maxCatchUp 4)
    local frameTime = math.min(dt, 0.1)
    dtAccumulator += frameTime

    local steps = 0
    local maxCatchUp = 4
    while dtAccumulator >= FIXED_DT and steps < maxCatchUp do
        WeaponController.FixedUpdate(FIXED_DT)
        dtAccumulator -= FIXED_DT
        steps += 1
    end
    if steps == maxCatchUp then
        dtAccumulator = 0
    end

    -- Auto-Shoot removed: firing is now only via explicit player input (MouseButton1/Trigger) to prevent spawn auto-fire in practice range

    -- 2. Automatic Fire Loop Handler
    local now = os.clock()
    local fireInterval = 60.0 / activeStats.fireRate

    if currentWeaponState.isFiring and not currentWeaponState.isReloading then
        if now - currentWeaponState.lastFireTimestamp > fireInterval * 3 then
            currentWeaponState.lastFireTimestamp = now - fireInterval
        end
        while currentWeaponState.isFiring and not currentWeaponState.isReloading and (now - currentWeaponState.lastFireTimestamp) >= fireInterval do
            currentWeaponState.lastFireTimestamp += fireInterval
            FireShot(true)
            if activeStats.fireMode == "Semi" then
                currentWeaponState.isFiring = false
                break
            elseif activeStats.fireMode == "Burst" then
                currentWeaponState.burstShotsRemaining -= 1
                if currentWeaponState.burstShotsRemaining <= 0 then
                    currentWeaponState.isFiring = false
                    break
                end
            end
        end
    end

    -- 3. Update Sub-Controllers
    CrosshairController.Update(dt, currentWeaponState.currentSpread)
    AnimationController.Update(dt)

    if currentWeaponModel and currentWeaponModel.PrimaryPart then
        local camera = Workspace.CurrentCamera
        if camera then
            local weaponId = currentWeaponState.weaponId
            local offset = MUZZLE_OFFSETS[weaponId] or DEFAULT_MUZZLE_OFFSET
            
            -- Calculate hipfire vs ADS position
            local adsAlpha = AnimationController.GetADSAlpha and AnimationController.GetADSAlpha() or (currentWeaponState.isAiming and 1 or 0)
            local hipfireOffset = CFrame.new(offset.X + 0.65, offset.Y - 0.7, offset.Z - 1.0)
            local adsOffset = CFrame.new(0, offset.Y - 0.35, offset.Z - 0.5)
            local baseOffset = hipfireOffset:Lerp(adsOffset, adsAlpha)
            
            -- Scope Integration: Hide viewmodel when fully aimed with 2D optic
            if activeStats and activeStats.scopeConfig and activeStats.scopeConfig.ScopeImageId then
                if adsAlpha > 0.8 then
                    baseOffset = CFrame.new(0, -100, 0)
                end
            end

            local animOffset = AnimationController.GetViewmodelOffset()
            currentWeaponModel:PivotTo(camera.CFrame * animOffset * baseOffset)
        end
    end
end

local function build3DWeaponModel(weaponId: string): Model
	local player = Players.LocalPlayer
	local selectedSkin = if player then player:GetAttribute("EquippedSkin_" .. weaponId) else nil
	local model = PremiumWeaponPresentation.BuildViewmodel(weaponId, selectedSkin)
	assert(model, "No premium viewmodel for weapon: " .. weaponId)
	return model
end

local function attachWeaponToCharacter(weaponId: string)
	if currentWeaponModel then
		currentWeaponModel:Destroy()
		currentWeaponModel = nil
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local model = build3DWeaponModel(weaponId)
	model.Parent = Workspace.CurrentCamera
	currentWeaponModel = model

	updateRaycastFilter()
end

function WeaponController.UnequipWeapon()
    WeaponController.CancelADS()
    if currentWeaponState then currentWeaponState.isReloading = false end
    if currentWeaponModel then
        currentWeaponModel:Destroy()
        currentWeaponModel = nil
    end
    currentWeaponState = nil
    HUDController.SetScopeVisible(false)
end

function WeaponController.EquipWeapon(weaponId: string): ()
    if not isCombatPhase then return end
    
    WeaponController.CancelADS()
    if currentWeaponState then currentWeaponState.isReloading = false end

    local stats = WeaponStats.Get(weaponId)
    if not stats then
        warn("[WeaponController] Failed to equip invalid weaponId: " .. tostring(weaponId))
        return
    end

    activeStats = stats
	
    -- Update local loadout tracker if it's a primary/secondary
    if weaponId == "AssaultRifle" or weaponId == "SniperRifle" or weaponId == "Shotgun" then
        localLoadout.Primary = weaponId
    elseif weaponId == "Pistol" then
        localLoadout.Secondary = weaponId
    elseif weaponId == "Grenade" then
        localLoadout.Grenade = weaponId
    end
    currentWeaponState = {
        weaponId = weaponId,
        currentAmmo = stats.magazineCapacity,
        reserveAmmo = stats.reserveCapacity,
        isReloading = false,
        isFiring = false,
        isAiming = false,
        currentSpread = stats.spreadMin,
        lastFireTimestamp = 0,
        burstShotsRemaining = 0,
    }

    updateRaycastFilter()

    task.spawn(function()
        attachWeaponToCharacter(weaponId)
    end)
end

function WeaponController.ApplySkin(skinId: string): ()
	if not currentWeaponModel or not currentWeaponState then
		return
	end
	if not PremiumWeaponPresentation.ApplySkin(currentWeaponModel, currentWeaponState.weaponId, skinId) then
		warn("[WeaponController] Rejected invalid premium skin", skinId)
	end
end

function WeaponController.GetCurrentSkin(): string?
    return (currentWeaponModel and currentWeaponModel:GetAttribute("AppliedSkin") :: string?) or nil
end

function WeaponController.ResupplyAmmo(): ()
	if not currentWeaponState or not activeStats then return end
	currentWeaponState.currentAmmo = activeStats.magazineCapacity
	currentWeaponState.reserveAmmo = activeStats.reserveCapacity
	currentWeaponState.isReloading = false
end

function WeaponController.StartFiring(): ()
	if not currentWeaponState or not activeStats or currentWeaponState.isReloading then
		return
	end
	currentWeaponState.isFiring = true

	if activeStats.fireMode == "Burst" then
		currentWeaponState.burstShotsRemaining = activeStats.burstCount or 3
	end

	local now = os.clock()
	local fireInterval = 60.0 / activeStats.fireRate
	if now - currentWeaponState.lastFireTimestamp >= fireInterval then
		currentWeaponState.lastFireTimestamp = now
		FireShot(true)
	end

	if activeStats.fireMode == "Semi" then
		currentWeaponState.isFiring = false
	end
end

function WeaponController.StopFiring(): ()
    if currentWeaponState then
        currentWeaponState.isFiring = false
        currentWeaponState.burstShotsRemaining = 0
    end
end

function WeaponController.CancelADS()
    if currentWeaponState then currentWeaponState.isReloading = false end
    if currentWeaponState and currentWeaponState.isAiming then
        WeaponController.SetAiming(false)
    end
end

function WeaponController.SetAiming(isAiming: boolean): ()
    if not currentWeaponState or not activeStats then return end
    if currentWeaponState.isReloading then return end -- Cannot aim while reloading

    currentWeaponState.isAiming = isAiming
    AnimationController.SetADS(isAiming, activeStats.adsFov)
    
    local camera = Workspace.CurrentCamera
    if isAiming then
        savedFOV = camera.FieldOfView
        originalSensitivity = UserInputService.MouseDeltaSensitivity
    end
    local dofEffect = camera:FindFirstChild("ScopeDoF") :: DepthOfFieldEffect
    if not dofEffect then
        dofEffect = Instance.new("DepthOfFieldEffect")
        dofEffect.Name = "ScopeDoF"
        dofEffect.Parent = camera
    end

    if isAiming then
        -- Apply Advanced ADS Logic if configured
        if activeStats.scopeConfig then
            local config = activeStats.scopeConfig
            
            -- FOV Tween
            local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
            TweenService:Create(camera, tweenInfo, {FieldOfView = config.FieldOfView}):Play()
            
            -- Sensitivity Scaling
            UserInputService.MouseDeltaSensitivity = config.SensitivityScalar
            
            -- Post-Processing DoF
            dofEffect.Enabled = true
            dofEffect.FocusDistance = config.FocusDistance
            dofEffect.InFocusRadius = 15
            dofEffect.NearIntensity = 0.1
            dofEffect.FarIntensity = 0.8
            
            -- UI Overlay
            if config.ScopeImageId then
                ScopeOverlayController.EnableOverlay(config.ScopeImageId)
            end
        else
            -- Legacy Iron Sights
            local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
            TweenService:Create(camera, tweenInfo, {FieldOfView = activeStats.adsFov}):Play()
        end
    else
        -- Revert ALL ADS State
        local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        TweenService:Create(camera, tweenInfo, {FieldOfView = savedFOV}):Play()
        
        -- Prevent Memory Leaks on Sensitivity
        UserInputService.MouseDeltaSensitivity = originalSensitivity
        
        dofEffect.Enabled = false
        ScopeOverlayController.DisableOverlay()
    end
end

local function handleAimInput(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
    if inputState == Enum.UserInputState.Begin then
        WeaponController.SetAiming(true)
    elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
        WeaponController.SetAiming(false)
    end
    return Enum.ContextActionResult.Pass
end

function WeaponController.ReloadWeapon(): ()
    if not currentWeaponState or not activeStats or currentWeaponState.isReloading then
        return
    end

    if currentWeaponState.currentAmmo >= activeStats.magazineCapacity or currentWeaponState.reserveAmmo <= 0 then
        return
    end

    currentWeaponState.isReloading = true
    currentWeaponState.isFiring = false

    local reloadWeaponId = currentWeaponState.weaponId
    task.delay(activeStats.reloadDuration, function()
        if currentWeaponState and activeStats and currentWeaponState.isReloading and currentWeaponState.weaponId == reloadWeaponId then
            local needed = activeStats.magazineCapacity - currentWeaponState.currentAmmo
            local reloadedAmount = math.min(needed, currentWeaponState.reserveAmmo)

            currentWeaponState.currentAmmo += reloadedAmount
            currentWeaponState.reserveAmmo -= reloadedAmount
            currentWeaponState.isReloading = false
        end
    end)
end

function WeaponController.Init(): ()
    if isInitialized then
        return
    end

    initPools()

    CrosshairController.Init()
    AnimationController.Init()
    BallisticPhysics.Initialize()

    local lastCameraOffset = CFrame.identity
    -- Bind RenderStepped loop using BindToRenderStep for Camera priority
    RunService:BindToRenderStep("WeaponControllerUpdate", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
        local camera = Workspace.CurrentCamera
        if camera then
            -- Apply camera recoil (delta approach)
            local currentCameraOffset = AnimationController.GetCameraOffset()
            local delta = lastCameraOffset:Inverse() * currentCameraOffset
            camera.CFrame = camera.CFrame * delta
            lastCameraOffset = currentCameraOffset
        end
        WeaponController.RenderUpdate(dt)
    end)

    local localPlayer = Players.LocalPlayer
    if localPlayer then
        localPlayer.CharacterAdded:Connect(function(char)
            -- Reset firing on respawn/teleport to prevent auto-fire carryover
            if currentWeaponState then
                currentWeaponState.isFiring = false
                currentWeaponState.burstShotsRemaining = 0
                currentWeaponState.lastFireTimestamp = os.clock()
            end
            task.wait(0.2)
            if currentWeaponState then
                attachWeaponToCharacter(currentWeaponState.weaponId)
            else
                attachWeaponToCharacter(localLoadout.Primary)
            end
        end)
    end

    -- Bind ADS cross-platform
    ContextActionService:BindAction("AimWeaponAction", handleAimInput, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
    
    -- Cleanup on death
    local function onCharacterAdded(char)
        local hum = char:WaitForChild("Humanoid") :: Humanoid
        hum.Died:Connect(function()
            WeaponController.CancelADS()
    if currentWeaponState then currentWeaponState.isReloading = false end
        end)
    end
    
    if Players.LocalPlayer.Character then
        onCharacterAdded(Players.LocalPlayer.Character)
    end
    Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

    local phaseTransitionRemote = RemoteEvents.GetReliable("MatchPhaseTransition")
    if phaseTransitionRemote then
        phaseTransitionRemote.OnClientEvent:Connect(function(payload)
            local phase = payload.phase
            if phase == "Combat" or phase == "Starting" or phase == "Buy" or phase == "PracticeRange" then
                isCombatPhase = true
                if not currentWeaponState then
                    WeaponController.EquipWeapon(localLoadout.Primary)
                end
            else
                isCombatPhase = false
                WeaponController.UnequipWeapon()
            end
        end)
    end

    -- Premium skin results — apply only after server validates ownership/compatibility/rate
    pcall(function()
        local skinRemote = RemoteEvents.GetReliable("WeaponSkinRequest")
        PremiumWeaponPresentation.BindSkinResults(skinRemote, function(weaponId, skinId)
            WeaponController.ApplySkin(skinId)
        end)
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or not isCombatPhase then return end
        if input.KeyCode == Enum.KeyCode.One then
            WeaponController.EquipWeapon(localLoadout.Primary)
        elseif input.KeyCode == Enum.KeyCode.Two then
            WeaponController.EquipWeapon(localLoadout.Secondary)
        elseif input.KeyCode == Enum.KeyCode.Three then
            WeaponController.EquipWeapon(localLoadout.Grenade)
        end
    end)

    isInitialized = true
end

function WeaponController.RenderExternalTracer(origin: Vector3, direction: Vector3): ()
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	local maxDistance = 300
	local targetPos = origin + direction * maxDistance

	updateRaycastFilter()
	local result = Workspace:Raycast(origin, direction * maxDistance, raycastParams)
	if result then
		targetPos = result.Position
	end

	RenderMuzzleFlash(CFrame.lookAt(origin, targetPos))
	RenderTracer(origin, targetPos)
end

function WeaponController.GetState(): WeaponState?
    return currentWeaponState
end

function WeaponController.GetActiveStats(): WeaponStats.WeaponData?
    return activeStats
end

return WeaponController
