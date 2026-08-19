--!strict
-- ServerScriptService/Combat/ProjectileService.luau
-- Server-authoritative segment-ray projectile (handoff §6.3) — no Touched authority

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ProjectileService = {}

export type Projectile = {
	owner: Player,
	weaponId: string,
	position: Vector3,
	velocity: Vector3,
	gravityScale: number,
	expiresAt: number,
	visual: BasePart,
	params: RaycastParams,
	impact: (RaycastResult?) -> (),
}

local active: { Projectile } = {}
local ready = false

local function getProjectileFolder(): Folder
	local f = Workspace:FindFirstChild("Projectiles")
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = "Projectiles"
	f.Parent = Workspace
	return f
end

local function getEffectsFolder(): Folder
	local f = Workspace:FindFirstChild("Effects")
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = "Effects"
	f.Parent = Workspace
	return f
end

local function getTemplate(): BasePart?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local t = templates:FindFirstChild("ProjectileVisual")
	if t and t:IsA("BasePart") then return t end
	return nil
end

function ProjectileService.spawn(
	owner: Player,
	weaponId: string,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravityScale: number,
	lifetime: number,
	impact: (RaycastResult?) -> ()
)
	local character = owner.Character
	if not character or direction.Magnitude < 0.001 then return end
	if not finiteCheck(speed) or not finiteCheck(gravityScale) then return end

	local folder = getProjectileFolder()
	local effects = getEffectsFolder()
	local template = getTemplate()
	if not template then
		warn("[ProjectileService] Missing ServerStorage.Templates.ProjectileVisual")
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder, effects }
	params.CollisionGroup = "ProjectileRay"
	params.IgnoreWater = false
	params.RespectCanCollide = true

	local visual = template:Clone() :: BasePart
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	visual.CFrame = CFrame.lookAt(origin, origin + direction)
	visual.Parent = folder

	table.insert(active, {
		owner = owner,
		weaponId = weaponId,
		position = origin,
		velocity = direction.Unit * speed,
		gravityScale = gravityScale,
		expiresAt = Workspace:GetServerTimeNow() + lifetime,
		visual = visual,
		params = params,
		impact = impact,
	})
end

function finiteCheck(v: number): boolean
	return v == v and math.abs(v) < 1e7
end

local cachedImpactRemote: UnreliableRemoteEvent? = nil
local function getImpactRemote(): UnreliableRemoteEvent?
	if cachedImpactRemote and cachedImpactRemote.Parent then return cachedImpactRemote end
	local function tryFind(): UnreliableRemoteEvent?
		local legacy = ReplicatedStorage:FindFirstChild("Remotes")
		if legacy then
			local r = legacy:FindFirstChild("ImpactVisual")
			if r and r:IsA("UnreliableRemoteEvent") then return r :: UnreliableRemoteEvent end
		end
		local net = ReplicatedStorage:FindFirstChild("Network")
		if net then
			local nr = net:FindFirstChild("Remotes")
			if nr then
				local u = nr:FindFirstChild("Unreliable")
				if u and u:IsA("Folder") then
					local r2 = u:FindFirstChild("ImpactVisual")
					if r2 and r2:IsA("UnreliableRemoteEvent") then return r2 :: UnreliableRemoteEvent end
				end
				local r3 = nr:FindFirstChild("ImpactVisual")
				if r3 and r3:IsA("UnreliableRemoteEvent") then return r3 :: UnreliableRemoteEvent end
			end
		end
		return nil
	end
	cachedImpactRemote = tryFind()
	return cachedImpactRemote
end

local function ensureHeartbeat()
	if ready then return end
	ready = true
	RunService.Heartbeat:Connect(function(deltaTime)
		local dt = math.min(deltaTime, 1 / 30)
		local gravity = Vector3.new(0, -Workspace.Gravity, 0)
		local impactRemote = getImpactRemote()

		for index = #active, 1, -1 do
			local p = active[index]
			local nextVelocity = p.velocity + gravity * p.gravityScale * dt
			local nextPosition = p.position + nextVelocity * dt
			local dir = nextPosition - p.position
			local hit: RaycastResult? = nil
			if dir.Magnitude > 0.001 then
				hit = Workspace:Raycast(p.position, dir, p.params)
			end

			if hit then
				if p.visual.Parent then p.visual:Destroy() end
				pcall(p.impact, hit)
				if impactRemote then
					pcall(function()
						impactRemote:FireAllClients(p.owner, p.weaponId, hit.Position, hit.Normal, hit.Material)
					end)
				end
				table.remove(active, index)
			elseif Workspace:GetServerTimeNow() >= p.expiresAt then
				if p.visual.Parent then p.visual:Destroy() end
				pcall(p.impact, nil)
				table.remove(active, index)
			else
				p.position = nextPosition
				p.velocity = nextVelocity
				if p.visual.Parent then
					p.visual.CFrame = CFrame.lookAt(nextPosition, nextPosition + nextVelocity)
				end
			end
		end
	end)
end

ensureHeartbeat()

return ProjectileService
