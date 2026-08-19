--!strict
--[=[
    Project OVERCLOCK: BootstrapService
    Server bootstrap service encapsulation module.
]=]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BootstrapService = {}

local function folder(parent: Instance, name: string): Folder
	local cur = parent:FindFirstChild(name)
	if cur then
		assert(cur:IsA("Folder"), `Expected Folder at {cur:GetFullName()}`)
		return cur :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function remote(className: string, parent: Instance, name: string): Instance
	local cur = parent:FindFirstChild(name)
	if cur then
		assert(cur.ClassName == className, `Expected {className} at {cur:GetFullName()}`)
		return cur
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

function BootstrapService.EnsureWorld()
	-- Idempotent world bootstrap (handoff §4 + OVERCLOCK unified + vetted pipeline §3)
	folder(ReplicatedStorage, "Shared")
	local templates = folder(ServerStorage, "Templates")
	local vettedProps = folder(templates, "VettedProps")
	-- Workspace.ScratchAssetAudit is the ONLY allowed insertion point for Store IDs (§3.1)
	local scratch = folder(Workspace, "ScratchAssetAudit")
	-- Ensure scratch is empty at boot (clean audit state) but do not delete user-placed candidate if present for audit
	if scratch:GetAttribute("AutoCreated") == nil then
		scratch:SetAttribute("AutoCreated", true)
	end
	folder(Workspace, "Map")
	folder(Workspace, "Spawns")
	folder(Workspace, "Projectiles")
	folder(Workspace, "Effects")

	for _, name in { "Characters", "Projectiles", "Map", "Decoration", "Triggers", "WeaponRay", "ProjectileRay" } do
		collisionGroup(name)
	end
	-- Collidable matrix per handoff §6.4
	pcall(function() PhysicsService:CollisionGroupSetCollidable("Projectiles", "Characters", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable("WeaponRay", "Projectiles", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable("WeaponRay", "Decoration", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable("ProjectileRay", "Projectiles", false) end)

	-- Shared/Network already handled by RemoteEvents; also ensure legacy ReplicatedStorage.Remotes for handoff clients
	local networkFolder = folder(ReplicatedStorage, "Network")
	local remotes = folder(networkFolder, "Remotes")
	folder(remotes, "Reliable")
	folder(remotes, "Unreliable")
	folder(remotes, "Functions")
	-- Legacy shim for handoff RequestFire etc. (also in RemoteEvents.EnsureLegacyRemotes)
	local legacyRemotes = ReplicatedStorage:FindFirstChild("Remotes") or folder(ReplicatedStorage, "Remotes")
	remote("RemoteEvent", legacyRemotes, "RequestFire")
	remote("RemoteEvent", legacyRemotes, "RequestReload")
	remote("RemoteEvent", legacyRemotes, "GameStateChanged")
	remote("UnreliableRemoteEvent", legacyRemotes, "ShotVisual")
	remote("UnreliableRemoteEvent", legacyRemotes, "ImpactVisual")

	for _, tag in { "MapProp", "BulletBlocker", "SpawnPoint", "Damageable", "VettedAsset" } do
		assert(type(tag) == "string")
	end

	-- Ensure VettedProps placeholder attributes are documented (pipeline §3)
	-- Game must run with zero external art — VettedProps may be empty and maps still build via primitive fallback
	if vettedProps:GetAttribute("Pipeline") == nil then
		vettedProps:SetAttribute("Pipeline", "ScratchAssetAudit -> audit_asset.luau -> VettedProps -> VettedPropSlots")
	end

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

	print("[BootstrapService] World bootstrap complete (folders, collision groups, remotes, ProjectileVisual)")
end

function BootstrapService.Init()
	BootstrapService.EnsureWorld()
	print("[BootstrapService] Server bootstrap service initialized.")
end

return BootstrapService
