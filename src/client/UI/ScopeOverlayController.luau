--!strict
--[=[
    Project OVERCLOCK: Scope Overlay Controller
    Handles the isolated 2D ScreenGui overlay for optical magnification (ADS),
    ensuring it does not invalidate the caching of the primary HUD.
]=]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ScopeOverlayController = {}

local scopeGui: ScreenGui?
local scopeImage: ImageLabel?
local leftLetterbox: Frame?
local rightLetterbox: Frame?

local function initializeScopeUI()
    if scopeGui then return end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    scopeGui = Instance.new("ScreenGui")
    scopeGui.Name = "ScopeUIOverlay"
    scopeGui.ResetOnSpawn = false
    scopeGui.IgnoreGuiInset = true
    scopeGui.Enabled = false
    scopeGui.Parent = playerGui

    -- Central Optic Image
    scopeImage = Instance.new("ImageLabel")
    scopeImage.Name = "ScopeOptic"
    scopeImage.AnchorPoint = Vector2.new(0.5, 0.5)
    scopeImage.Position = UDim2.fromScale(0.5, 0.5)
    scopeImage.Size = UDim2.fromScale(1, 1)
    scopeImage.BackgroundTransparency = 1
    scopeImage.Parent = scopeGui

    local aspectConstraint = Instance.new("UIAspectRatioConstraint")
    aspectConstraint.AspectType = Enum.AspectType.FitWithinMaxSize
    aspectConstraint.AspectRatio = 1.0
    aspectConstraint.Parent = scopeImage

    -- Peripheral Occlusion (Letterboxing)
    leftLetterbox = Instance.new("Frame")
    leftLetterbox.Name = "LeftLetterbox"
    leftLetterbox.BackgroundColor3 = Color3.new(0, 0, 0)
    leftLetterbox.BorderSizePixel = 0
    leftLetterbox.AnchorPoint = Vector2.new(1, 0)
    leftLetterbox.Position = UDim2.fromScale(0, 0)
    leftLetterbox.Size = UDim2.fromScale(1, 1) -- Will be scaled via layout
    leftLetterbox.Parent = scopeGui

    rightLetterbox = Instance.new("Frame")
    rightLetterbox.Name = "RightLetterbox"
    rightLetterbox.BackgroundColor3 = Color3.new(0, 0, 0)
    rightLetterbox.BorderSizePixel = 0
    rightLetterbox.AnchorPoint = Vector2.new(0, 0)
    rightLetterbox.Position = UDim2.fromScale(1, 0)
    rightLetterbox.Size = UDim2.fromScale(1, 1) -- Will be scaled via layout
    rightLetterbox.Parent = scopeGui

    -- Dynamic layout constraint to snap letterboxing to the optic
    local function updateLetterboxing()
        if not scopeImage or not leftLetterbox or not rightLetterbox then return end
        local scopeBounds = scopeImage.AbsoluteSize
        local scopePos = scopeImage.AbsolutePosition
        
        -- Left letterbox spans from left edge of screen to left edge of scope image
        leftLetterbox.Size = UDim2.new(0, scopePos.X, 1, 0)
        leftLetterbox.Position = UDim2.new(0, scopePos.X, 0, 0)

        -- Right letterbox spans from right edge of scope image to right edge of screen
        rightLetterbox.Size = UDim2.new(0, scopeGui.AbsoluteSize.X - (scopePos.X + scopeBounds.X), 1, 0)
        rightLetterbox.Position = UDim2.new(0, scopePos.X + scopeBounds.X, 0, 0)
    end

    scopeImage:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLetterboxing)
    scopeGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLetterboxing)
end

function ScopeOverlayController.EnableOverlay(imageId: string)
    initializeScopeUI()
    if scopeGui and scopeImage then
        scopeImage.Image = imageId
        scopeGui.Enabled = true
        
        -- Hide default crosshair when scope is up
        local HUDController = require(script.Parent:WaitForChild("HUDController") :: any)
        if HUDController and HUDController.SetCrosshairVisible then
            HUDController.SetCrosshairVisible(false)
        end
    end
end

function ScopeOverlayController.DisableOverlay()
    if scopeGui then
        scopeGui.Enabled = false
        
        local HUDController = require(script.Parent:WaitForChild("HUDController") :: any)
        if HUDController and HUDController.SetCrosshairVisible then
            HUDController.SetCrosshairVisible(true)
        end
    end
end

return ScopeOverlayController
