-- StarterPlayerScripts/WeaponClient.local.luau
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestFire = remotes:WaitForChild("RequestFire") :: RemoteEvent
local requestReload = remotes:WaitForChild("RequestReload") :: RemoteEvent
local shotVisual = remotes:WaitForChild("ShotVisual") :: UnreliableRemoteEvent
local impactVisual = remotes:WaitForChild("ImpactVisual") :: UnreliableRemoteEvent

local localSequence = 0
local inputThrottleUntil = 0

local function equippedWeaponId(): string?
    local character = player.Character
    local tool = character and character:FindFirstChildWhichIsA("Tool")
    if not tool then return nil end
    return tool:GetAttribute("WeaponId") or tool.Name
end

local function fire(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
    if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
    local weaponId = equippedWeaponId()
    local camera = workspace.CurrentCamera
    if not weaponId or not camera or os.clock() < inputThrottleUntil then
        return Enum.ContextActionResult.Sink
    end
    inputThrottleUntil = os.clock() + 0.04 -- UI responsiveness only; server remains authoritative.
    localSequence += 1
    requestFire:FireServer(weaponId, camera.CFrame.LookVector, localSequence)
    return Enum.ContextActionResult.Sink
end

local function reload(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
    if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
    local weaponId = equippedWeaponId()
    if weaponId then requestReload:FireServer(weaponId) end
    return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("AgentFire", fire, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
ContextActionService:BindAction("AgentReload", reload, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

local function tracer(origin: Vector3, endpoint: Vector3)
    if (endpoint - origin).Magnitude < 0.1 then return end
    local part = Instance.new("Part")
    part.Name = "CosmeticTracer"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(110, 215, 255)
    part.Size = Vector3.new(0.08, 0.08, (endpoint - origin).Magnitude)
    part.CFrame = CFrame.lookAt(origin, endpoint) * CFrame.new(0, 0, -part.Size.Z / 2)
    part.Parent = workspace:WaitForChild("Effects")
    Debris:AddItem(part, 0.06)
end

shotVisual.OnClientEvent:Connect(function(_shooter: Player, _weaponId: string, origin: Vector3, endpoint: Vector3)
    tracer(origin, endpoint)
end)

impactVisual.OnClientEvent:Connect(function(_shooter: Player, _weaponId: string, position: Vector3, normal: Vector3)
    local spark = Instance.new("Part")
    spark.Name = "CosmeticImpact"
    spark.Shape = Enum.PartType.Ball
    spark.Size = Vector3.new(0.25, 0.25, 0.25)
    spark.Anchored = true
    spark.CanCollide = false
    spark.CanTouch = false
    spark.CanQuery = false
    spark.Material = Enum.Material.Neon
    spark.Color = Color3.fromRGB(255, 230, 120)
    spark.CFrame = CFrame.lookAt(position + normal * 0.03, position + normal)
    spark.Parent = workspace:WaitForChild("Effects")
    Debris:AddItem(spark, 0.15)
end)
