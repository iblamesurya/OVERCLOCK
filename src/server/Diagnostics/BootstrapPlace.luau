-- tools/bootstrap_place.luau
-- Run via Studio MCP execute_luau, Command Bar, or Studio CLI RunScript.
-- It only creates missing structures and is safe to execute repeatedly.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local function folder(parent: Instance, name: string): Folder
    local current = parent:FindFirstChild(name)
    if current then
        assert(current:IsA("Folder"), (`Expected Folder at {current:GetFullName()}`))
        return current
    end
    local created = Instance.new("Folder")
    created.Name = name
    created.Parent = parent
    return created
end

local function remote(className: string, parent: Instance, name: string): Instance
    local current = parent:FindFirstChild(name)
    if current then
        assert(current.ClassName == className, (`Expected {className} at {current:GetFullName()}`))
        return current
    end
    local created = Instance.new(className)
    created.Name = name
    created.Parent = parent
    return created
end

local function collisionGroup(name: string)
    for _, item in PhysicsService:GetRegisteredCollisionGroups() do
        if item.name == name then return end
    end
    PhysicsService:RegisterCollisionGroup(name)
end

local remotes = folder(ReplicatedStorage, "Remotes")
folder(ReplicatedStorage, "Shared")
local templates = folder(ServerStorage, "Templates")
local vettedProps = folder(templates, "VettedProps")
if vettedProps:GetAttribute("Pipeline") == nil then
    vettedProps:SetAttribute("Pipeline", "ScratchAssetAudit -> audit_asset.luau -> VettedProps -> VettedPropSlots")
end
folder(Workspace, "Map")
folder(Workspace, "Spawns")
folder(Workspace, "Projectiles")
folder(Workspace, "Effects")
-- Workspace.ScratchAssetAudit is the ONLY insertion point for Store IDs — never Workspace.Map/StarterPack
local scratch = folder(Workspace, "ScratchAssetAudit")
scratch:SetAttribute("Pipeline", "Insert ONE Model/MeshPart here -> run audit_asset.luau")

for _, name in {"Characters", "Projectiles", "Map", "Decoration", "Triggers", "WeaponRay", "ProjectileRay"} do
    collisionGroup(name)
end
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Characters", false)
PhysicsService:CollisionGroupSetCollidable("WeaponRay", "Projectiles", false)
PhysicsService:CollisionGroupSetCollidable("WeaponRay", "Decoration", false)
PhysicsService:CollisionGroupSetCollidable("ProjectileRay", "Projectiles", false)

remote("RemoteEvent", remotes, "RequestFire")
remote("RemoteEvent", remotes, "RequestReload")
remote("RemoteEvent", remotes, "GameStateChanged")
remote("UnreliableRemoteEvent", remotes, "ShotVisual")
remote("UnreliableRemoteEvent", remotes, "ImpactVisual")

-- Map tags are data labels, not security. The server still validates all behavior.
for _, tag in {"MapProp", "BulletBlocker", "SpawnPoint", "Damageable", "VettedAsset"} do
    assert(type(tag) == "string")
end

-- A single anchored projectile visual template; gameplay collision is segment raycasting.
local templates = ServerStorage.Templates
if not templates:FindFirstChild("ProjectileVisual") then
    local projectile = Instance.new("Part")
    projectile.Name = "ProjectileVisual"
    projectile.Shape = Enum.PartType.Ball
    projectile.Size = Vector3.new(0.35, 0.35, 0.35)
    projectile.Material = Enum.Material.Neon
    projectile.Color = Color3.fromRGB(100, 210, 255)
    projectile.Anchored = true
    projectile.CanCollide = false
    projectile.CanTouch = false
    projectile.CanQuery = false
    projectile.Parent = templates
end

print("Roblox agent handoff bootstrap complete")
