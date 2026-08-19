--!strict
-- ServerScriptService/Combat/CombatService.server.luau
-- Server-authoritative fire/reload per roblox-combat-authority handoff §6.2/6.3
-- Validates weaponId, finiteVector dir, Tool WeaponId, state Playing, origin Muzzle/Handle/HRP,
-- rate-limit GetServerTimeNow, dot > -0.25, magazine, raycast WeaponRay Exclude character/Projectiles/Effects,
-- TakeDamage server only, ShotVisual/ImpactVisual cosmetic.

if (_G :: any).__CombatHandoffSetupDone then return end
;(_G :: any).__CombatHandoffSetupDone = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)
local ProjectileService = require(script.Parent:WaitForChild("ProjectileService") :: any)

-- Resolve WeaponConfig authoritative
local function getWeaponConfig(weaponId: string): any
	local ok, wc = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig") :: any) end)
	if ok and wc and wc[weaponId] then return wc[weaponId] end
	-- Fallback to OVERCLOCK WeaponStats for legacy compatibility
	local ok2, ws = pcall(function() return require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any) end)
	if ok2 and ws then
		local data: any = (ws :: any)[weaponId]
		if not data and (ws :: any).GetWeapon then data = (ws :: any).GetWeapon(weaponId) end
		if data then return data end
	end
	return nil
end

local lastShot: { [number]: { [string]: number } } = {}
local ammo: { [number]: { [string]: number } } = {}
local reloadUntil: { [number]: { [string]: number } } = {}

local function stateTable(root: { [number]: { [string]: number } }, uid: number): { [string]: number }
	local v = root[uid]
	if not v then
		v = {}
		root[uid] = v
	end
	return v
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge and math.abs(n) < 1e7
end

local function finiteVector(v: Vector3): boolean
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function playerWeapon(player: Player, weaponId: string): (Model?, Humanoid?, BasePart?, Tool?, Vector3?)
	local character = player.Character
	if not character or player:GetAttribute("PlayerState") ~= "Playing" then return nil end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tool = character:FindFirstChildWhichIsA("Tool") :: Tool?
	if not humanoid or humanoid.Health <= 0 or not root or not tool then return nil end
	if (tool:GetAttribute("WeaponId") or tool.Name) ~= weaponId then return nil end
	local muzzle = tool:FindFirstChild("Muzzle", true)
	local origin = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else nil
	if not origin then
		local handle = tool:FindFirstChild("Handle")
		origin = if handle and handle:IsA("BasePart") then (handle :: BasePart).Position else root.Position
	end
	return character, humanoid, root, tool, origin
end

-- Ensure legacy remotes exist via RemoteEvents
pcall(function() RemoteEvents.Initialize() end)
pcall(function() RemoteEvents.EnsureLegacyRemotes() end)

local legacyRemotes = ReplicatedStorage:FindFirstChild("Remotes")
local requestFire: RemoteEvent? = nil
local requestReload: RemoteEvent? = nil
local shotVisual: UnreliableRemoteEvent? = nil
pcall(function()
	requestFire = (legacyRemotes and legacyRemotes:FindFirstChild("RequestFire") :: RemoteEvent?) or RemoteEvents.GetReliable("RequestFire")
end)
pcall(function()
	requestReload = (legacyRemotes and legacyRemotes:FindFirstChild("RequestReload") :: RemoteEvent?) or RemoteEvents.GetReliable("RequestReload")
end)
pcall(function()
	shotVisual = (legacyRemotes and legacyRemotes:FindFirstChild("ShotVisual") :: UnreliableRemoteEvent?) or RemoteEvents.GetUnreliable("ShotVisual")
end)

if requestFire then
	requestFire.OnServerEvent:Connect(function(player: Player, weaponId: any, rawDir: any, _seq: any)
		if type(weaponId) ~= "string" or typeof(rawDir) ~= "Vector3" then return end
		if not finiteVector(rawDir) then return end
		if rawDir.Magnitude < 0.001 then return end
		local cfg: any = getWeaponConfig(weaponId)
		if not cfg then return end
		local character, _, root, _, origin = playerWeapon(player, weaponId)
		if not character or not root or not origin then return end
		if character:FindFirstChild("SpawnProtection") or character:FindFirstChildOfClass("ForceField") then return end
		if player:GetAttribute("PlayerState") == "SpawnProtected" then return end
		local now = Workspace:GetServerTimeNow()
		if not finite(now) then return end
		local shots = stateTable(lastShot, player.UserId)
		local mags = stateTable(ammo, player.UserId)
		local reloads = stateTable(reloadUntil, player.UserId)
		if now < (reloads[weaponId] or 0) then return end
		local fireRate = cfg.fireRate or cfg.FireRate or 7.5
		if not finite(fireRate) or fireRate <= 0 then return end
		if now - (shots[weaponId] or -math.huge) < 1 / fireRate then return end
		local dir = (rawDir :: Vector3).Unit
		if not finiteVector(dir) then return end
		if dir:Dot(root.CFrame.LookVector) < -0.25 then return end
		local magSize = cfg.magazineSize or cfg.MagazineSize or cfg.magSize or 30
		if not finite(magSize) then return end
		mags[weaponId] = mags[weaponId] or magSize
		if mags[weaponId] <= 0 then return end
		shots[weaponId] = now
		mags[weaponId] -= 1

		local fireMode = cfg.fireMode or cfg.FireMode or "Hitscan"
		local range = cfg.range or cfg.Range or 650
		local damage = cfg.damage or cfg.Damage or 24
		if not finite(range) or not finite(damage) then return end
		if fireMode == "Projectile" then
			local speed = cfg.projectileSpeed or cfg.ProjectileSpeed or 150
			local grav = cfg.projectileGravityScale or cfg.GravityScale or 1.0
			local lifetime = cfg.projectileLifetime or 4.0
			if not finite(speed) or not finite(grav) or not finite(lifetime) then return end
			if range * speed >= 1e6 then return end
			ProjectileService.spawn(player, weaponId, origin, dir, speed, grav, lifetime, function(hit: RaycastResult?)
				if hit then
					local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
					local hum = mdl and mdl:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
					if hum and hum.Health > 0 then
						local pl = Players:GetPlayerFromCharacter(mdl)
						if pl ~= player and (not pl or pl.Team ~= player.Team) and not mdl:FindFirstChildOfClass("ForceField") then
							if not pl or pl:GetAttribute("PlayerState") == "Playing" then
								hum:TakeDamage(damage)
							end
						end
					end
				end
			end)
			if shotVisual then pcall(function() shotVisual:FireAllClients(player, weaponId, origin, origin, nil) end) end
		else
			if range >= 1e6 then return end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local projFolder = Workspace:FindFirstChild("Projectiles")
			local effFolder = Workspace:FindFirstChild("Effects")
			local filter: { Instance } = { character }
			if projFolder then table.insert(filter, projFolder) end
			if effFolder then table.insert(filter, effFolder) end
			params.FilterDescendantsInstances = filter
			params.CollisionGroup = "WeaponRay"
			params.IgnoreWater = false
			params.RespectCanCollide = true
			local hit = Workspace:Raycast(origin, dir * range, params)
			local endpoint = if hit then hit.Position else origin + dir * range
			if hit then
				local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
				local hum = mdl and mdl:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
				if hum and hum.Health > 0 then
					local pl = Players:GetPlayerFromCharacter(mdl)
					if pl ~= player and (not pl or pl.Team ~= player.Team) and not mdl:FindFirstChildOfClass("ForceField") then
						if not pl or pl:GetAttribute("PlayerState") == "Playing" then hum:TakeDamage(damage) end
					end
				end
			end
			if shotVisual then pcall(function() shotVisual:FireAllClients(player, weaponId, origin, endpoint, hit and hit.Normal or nil) end) end
		end
	end)
end

if requestReload then
	requestReload.OnServerEvent:Connect(function(player: Player, weaponId: any)
		if type(weaponId) ~= "string" then return end
		local character = player.Character
		if not character or player:GetAttribute("PlayerState") ~= "Playing" then return end
		local tool = character:FindFirstChildWhichIsA("Tool") :: Tool?
		if not tool or (tool:GetAttribute("WeaponId") or tool.Name) ~= weaponId then return end
		local cfg: any = getWeaponConfig(weaponId)
		if not cfg then return end
		local now = Workspace:GetServerTimeNow()
		if not finite(now) then return end
		local mags = stateTable(ammo, player.UserId)
		local reloads = stateTable(reloadUntil, player.UserId)
		local magSize = cfg.magazineSize or cfg.MagazineSize or 30
		if not finite(magSize) then return end
		mags[weaponId] = mags[weaponId] or magSize
		if mags[weaponId] >= magSize or now < (reloads[weaponId] or 0) then return end
		local reloadSecs = cfg.reloadSeconds or cfg.ReloadTime or 2.2
		if not finite(reloadSecs) then return end
		local finishes = now + reloadSecs
		reloads[weaponId] = finishes
		task.delay(reloadSecs, function()
			if player.Parent and reloads[weaponId] == finishes then
				mags[weaponId] = magSize
				reloads[weaponId] = nil
			end
		end)
	end)
end

Players.PlayerRemoving:Connect(function(p)
	lastShot[p.UserId] = nil
	ammo[p.UserId] = nil
	reloadUntil[p.UserId] = nil
end)

print("[CombatService.server] Authoritative combat listeners bound")
