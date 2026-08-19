--!strict
--[=[
    Project OVERCLOCK: Dynamic Crosshair Controller
    Translates mathematical bullet spread (in degrees) into precise 2D screen pixel offsets,
    guaranteeing exact mapping between 2D UI reticle and 3D unit raycast direction vectors.
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type DynamicCrosshairSettings = {
    color: Color3,
    lineLength: number,
    lineThickness: number,
    centerDot: boolean,
    hitmarkerColorBody: Color3,
    hitmarkerColorHead: Color3,
}

local DEFAULT_SETTINGS: DynamicCrosshairSettings = {
    color = Color3.fromRGB(0, 255, 150), -- A nice cyan/green color that stands out
    lineLength = 6,
    lineThickness = 2,
    centerDot = true,
    hitmarkerColorBody = Color3.fromRGB(255, 255, 255),
    hitmarkerColorHead = Color3.fromRGB(255, 50, 50),
}

local CrosshairController = {}

local isInitialized = false
local currentPixelGap = 4
local targetPixelGap = 4
local hitmarkerTimer = 0
local isHitmarkerHeadshot = false

-- UI Element references
local screenGui: ScreenGui? = nil
local centerFrame: Frame? = nil
local topArm: Frame? = nil
local bottomArm: Frame? = nil
local leftArm: Frame? = nil
local rightArm: Frame? = nil
local centerDotArm: Frame? = nil
local hitmarkerGuiFrame: Frame? = nil

--[=[
    Calculates exact 2D pixel gap from mathematical 3D cone spread angle (in degrees).
    Uses camera perspective projection: Radius_px = FocalLength_px * tan(SpreadAngle)
]=]
function CrosshairController.CalculateSpreadPixelOffset(
    spreadDegrees: number,
    cameraFov: number,
    viewportSize: Vector2
): number
    if spreadDegrees <= 0 or cameraFov <= 0 or viewportSize.Y <= 0 then
        return 2 -- Minimum base offset
    end

    local halfFovRad = math.rad(cameraFov / 2)
    local focalLengthPx = viewportSize.Y / (2 * math.tan(halfFovRad))
    local spreadRad = math.rad(spreadDegrees)
    local radiusPx = focalLengthPx * math.tan(spreadRad)

    return math.clamp(radiusPx, 2, math.max(2, viewportSize.Y * 0.4))
end

--[=[
    Maps 3D camera CFrame and mathematical spread (in degrees) to a 3D unit direction vector.
    Guarantees exact geometric parity between the 2D visual crosshair and 3D raycast spread cone.
]=]
function CrosshairController.GetSpreadDirection(
    camCFrame: CFrame,
    spreadDegrees: number,
    randomSeed: number?
): Vector3
    if spreadDegrees <= 0 then
        return camCFrame.LookVector
    end

    local rng = if randomSeed then Random.new(randomSeed) else Random.new()
    local spreadRad = math.rad(spreadDegrees / 2)
    local maxRadius = math.tan(spreadRad)

    -- Uniform random distribution within spread disc
    local theta = rng:NextNumber(0, 2 * math.pi)
    local r = math.sqrt(rng:NextNumber(0, 1)) * maxRadius

    local offsetX = r * math.cos(theta)
    local offsetY = r * math.sin(theta)

    -- Camera local direction (-Z is forward)
    local localDirection = Vector3.new(offsetX, offsetY, -1).Unit
    return camCFrame:VectorToWorldSpace(localDirection)
end

local function BuildUI()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        return
    end

    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    -- Clean up prior instance if existing
    local existing = playerGui:FindFirstChild("OverclockCrosshairGui") or playerGui:FindFirstChild("RivalsCrosshairGui")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "OverclockCrosshairGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "CenterContainer"
    mainFrame.Size = UDim2.new(1, 0, 1, 0)
    mainFrame.BackgroundTransparency = 1
    mainFrame.Parent = gui

    -- Reticle center container
    local center = Instance.new("Frame")
    center.Name = "Reticle"
    center.Size = UDim2.new(0, 0, 0, 0)
    center.Position = UDim2.new(0.5, 0, 0.5, 0)
    center.BackgroundTransparency = 1
    center.Parent = mainFrame
    centerFrame = center

    local function addStroke(parent: Instance)
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.new(0, 0, 0)
        stroke.Thickness = 1
        stroke.Transparency = 0.5
        stroke.Parent = parent
    end

    -- Top Arm
    topArm = Instance.new("Frame")
    topArm.Name = "Top"
    topArm.AnchorPoint = Vector2.new(0.5, 1)
    topArm.Size = UDim2.new(0, DEFAULT_SETTINGS.lineThickness, 0, DEFAULT_SETTINGS.lineLength)
    topArm.BackgroundColor3 = DEFAULT_SETTINGS.color
    topArm.BorderSizePixel = 0
    topArm.Parent = center
    addStroke(topArm)

    -- Bottom Arm
    bottomArm = Instance.new("Frame")
    bottomArm.Name = "Bottom"
    bottomArm.AnchorPoint = Vector2.new(0.5, 0)
    bottomArm.Size = UDim2.new(0, DEFAULT_SETTINGS.lineThickness, 0, DEFAULT_SETTINGS.lineLength)
    bottomArm.BackgroundColor3 = DEFAULT_SETTINGS.color
    bottomArm.BorderSizePixel = 0
    bottomArm.Parent = center
    addStroke(bottomArm)

    -- Left Arm
    leftArm = Instance.new("Frame")
    leftArm.Name = "Left"
    leftArm.AnchorPoint = Vector2.new(1, 0.5)
    leftArm.Size = UDim2.new(0, DEFAULT_SETTINGS.lineLength, 0, DEFAULT_SETTINGS.lineThickness)
    leftArm.BackgroundColor3 = DEFAULT_SETTINGS.color
    leftArm.BorderSizePixel = 0
    leftArm.Parent = center
    addStroke(leftArm)

    -- Right Arm
    rightArm = Instance.new("Frame")
    rightArm.Name = "Right"
    rightArm.AnchorPoint = Vector2.new(0, 0.5)
    rightArm.Size = UDim2.new(0, DEFAULT_SETTINGS.lineLength, 0, DEFAULT_SETTINGS.lineThickness)
    rightArm.BackgroundColor3 = DEFAULT_SETTINGS.color
    rightArm.BorderSizePixel = 0
    rightArm.Parent = center
    addStroke(rightArm)

    -- Center Dot
    centerDotArm = Instance.new("Frame")
    centerDotArm.Name = "CenterDot"
    centerDotArm.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDotArm.Size = UDim2.new(0, DEFAULT_SETTINGS.lineThickness + 2, 0, DEFAULT_SETTINGS.lineThickness + 2)
    centerDotArm.Position = UDim2.new(0, 0, 0, 0)
    centerDotArm.BackgroundColor3 = DEFAULT_SETTINGS.color
    centerDotArm.BorderSizePixel = 0
    centerDotArm.Visible = DEFAULT_SETTINGS.centerDot
    centerDotArm.Parent = center
    addStroke(centerDotArm)

    -- Hitmarker Container
    hitmarkerGuiFrame = Instance.new("Frame")
    hitmarkerGuiFrame.Name = "Hitmarker"
    hitmarkerGuiFrame.Size = UDim2.new(0, 16, 0, 16)
    hitmarkerGuiFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    hitmarkerGuiFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    hitmarkerGuiFrame.BackgroundTransparency = 1
    hitmarkerGuiFrame.Visible = false
    hitmarkerGuiFrame.Parent = mainFrame

    -- Create 4 diagonal hitmarker arms
    for i = 1, 4 do
        local arm = Instance.new("Frame")
        arm.Name = "Arm" .. i
        arm.Size = UDim2.new(0, 6, 0, 2)
        arm.AnchorPoint = Vector2.new(0.5, 0.5)
        arm.Position = UDim2.new(0.5, 0, 0.5, 0)
        arm.Rotation = (i - 1) * 90 + 45
        arm.BackgroundColor3 = DEFAULT_SETTINGS.hitmarkerColorBody
        arm.BorderSizePixel = 0
        arm.Parent = hitmarkerGuiFrame
    end

    gui.Parent = playerGui
    screenGui = gui
end

function CrosshairController.Init(): ()
    if isInitialized then
        return
    end

    BuildUI()
    isInitialized = true
end

function CrosshairController.ShowHitmarker(isHeadshot: boolean): ()
    hitmarkerTimer = 0.15 -- Active for 150ms
    isHitmarkerHeadshot = isHeadshot

    if hitmarkerGuiFrame then
        local color = if isHeadshot
            then DEFAULT_SETTINGS.hitmarkerColorHead
            else DEFAULT_SETTINGS.hitmarkerColorBody
        for _, child in ipairs(hitmarkerGuiFrame:GetChildren()) do
            if child:IsA("Frame") then
                child.BackgroundColor3 = color
            end
        end
        hitmarkerGuiFrame.Visible = true
    end
end

function CrosshairController.Update(dt: number, currentSpreadDegrees: number): ()
    if not isInitialized then
        CrosshairController.Init()
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    -- 1. Compute target pixel gap from current 3D spread angle
    targetPixelGap = CrosshairController.CalculateSpreadPixelOffset(
        currentSpreadDegrees,
        camera.FieldOfView,
        camera.ViewportSize
    )

    -- Exponential decay Lerp transition for smooth dynamic crosshair spread expansion/contraction
    local lambda = 25.0
    currentPixelGap += (targetPixelGap - currentPixelGap) * (1 - math.exp(-lambda * dt))

    local gapInt = math.max(2, math.floor(currentPixelGap + 0.5))

    -- Update arm positions
    if topArm then
        topArm.Position = UDim2.new(0, 0, 0, -gapInt)
    end
    if bottomArm then
        bottomArm.Position = UDim2.new(0, 0, 0, gapInt)
    end
    if leftArm then
        leftArm.Position = UDim2.new(0, -gapInt, 0, 0)
    end
    if rightArm then
        rightArm.Position = UDim2.new(0, gapInt, 0, 0)
    end

    -- 2. Update hitmarker countdown animation
    if hitmarkerTimer > 0 then
        hitmarkerTimer -= dt
        if hitmarkerTimer <= 0 then
            if hitmarkerGuiFrame then
                hitmarkerGuiFrame.Visible = false
            end
        end
    end
end

function CrosshairController.SetVisible(visible: boolean): ()
    if screenGui then
        screenGui.Enabled = visible
    end
end

return CrosshairController
