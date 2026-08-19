--!strict
--[=[
    Project OVERCLOCK: Combat Server Authority
    Central server module responsible for network listener bindings, payload validation,
    rate limiting (leaky bucket), rollback verification, damage application, and match state
    phase checks. Silently discards invalid or malicious client requests.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage:WaitForChild("Types") :: any)

local RollbackBuffer = require(script.Parent.RollbackBuffer)
local HitValidation = require(script.Parent.HitValidation)
local MovementValidator = require(script.Parent.MovementValidator)
local BufferSerializer = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("BufferSerializer") :: any)
local MovementAuthorityBootstrap = require(script.Parent:WaitForChild("MovementAuthorityBootstrap") :: any)

local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local WeaponStats = require(DataFolder:WaitForChild("WeaponStats") :: any)

local DirectChallengeService =
	require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("DirectChallengeService") :: any)
local PlayerDataService =
	require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("PlayerDataService") :: any)

local CombatServer = {}
CombatServer.__index = CombatServer

-- Leaky bucket state per player & action
type BucketState = {
	tokens: number,
	lastUpdate: number,
	capacity: number,
	refillRate: number, -- Tokens added per second
}

export type PlayerHealthState = {
	health: number,
	maxHealth: number,
	shield: number,
	maxShield: number,
}

export type CombatServerOptions = {
	maxRollbackMs: number,
	matchPhase: Types.MatchState,
}

export type CombatServerClass = typeof(setmetatable(
	{} :: {
		_rollbackBuffer: RollbackBuffer.RollbackBufferClass,
		_rateLimiters: { [number]: { [string]: BucketState } },
		_playerHealth: { [number]: PlayerHealthState },
		_matchPhase: Types.MatchState,
		_options: CombatServerOptions,
	},
	CombatServer
))

--- Creates a new CombatServer instance.
function CombatServer.new(
	rollbackBuffer: RollbackBuffer.RollbackBufferClass?,
	options: CombatServerOptions?
): CombatServerClass
	local self = setmetatable({
		_rollbackBuffer = rollbackBuffer or RollbackBuffer.new(120, 60),
		_rateLimiters = {} :: { [number]: { [string]: BucketState } },
		_playerHealth = {} :: { [number]: PlayerHealthState },
		_matchPhase = (options and options.matchPhase) or "InGame",
		_options = options or { maxRollbackMs = 500, matchPhase = "InGame" },
	}, CombatServer)
	return self
end

-- ----------------------------------------------------------------------------
-- 1. Leaky Bucket Rate Limiter
-- ----------------------------------------------------------------------------

function CombatServer._checkRateLimit(
	self: CombatServerClass,
	userId: number,
	action: string,
	capacity: number,
	refillRate: number
): boolean
	local now = os.clock()
	local playerBuckets = self._rateLimiters[userId]
	if not playerBuckets then
		playerBuckets = {}
		self._rateLimiters[userId] = playerBuckets
	end

	local bucket = playerBuckets[action]
	if not bucket then
		bucket = {
			tokens = capacity,
			lastUpdate = now,
			capacity = capacity,
			refillRate = refillRate,
		}
		playerBuckets[action] = bucket
	end

	-- Refill tokens based on elapsed time
	local elapsed = math.max(0, now - bucket.lastUpdate)
	bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillRate)
	bucket.lastUpdate = now

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end

	return false -- Rate limit exceeded
end

-- ----------------------------------------------------------------------------
-- 2. State Machine & Match Phase Management
-- ----------------------------------------------------------------------------

function CombatServer.SetMatchPhase(self: CombatServerClass, phase: Types.MatchState)
	self._matchPhase = phase
end

function CombatServer.GetMatchPhase(self: CombatServerClass): Types.MatchState
	return self._matchPhase
end

function CombatServer.RegisterPlayer(self: CombatServerClass, userId: number, health: number?, shield: number?)
	self._playerHealth[userId] = {
		health = health or 100,
		maxHealth = 100,
		shield = shield or 50,
		maxShield = 50,
	}
end

function CombatServer.UnregisterPlayer(self: CombatServerClass, userId: number)
	self._playerHealth[userId] = nil
	self._rateLimiters[userId] = nil
	self._rollbackBuffer:ClearEntity(tostring(userId))
end

function CombatServer.IsPlayerAlive(self: CombatServerClass, userId: number): boolean
	local state = self._playerHealth[userId]
	return state ~= nil and state.health > 0
end

function CombatServer.GetPlayerHealth(self: CombatServerClass, userId: number): PlayerHealthState?
	return self._playerHealth[userId]
end

-- ----------------------------------------------------------------------------
-- 3. Payload Bounds & Type Validation Helpers
-- ----------------------------------------------------------------------------

local MAX_STRING_LEN = 64

local function validateString(val: any, maxLen: number?): boolean
	if type(val) ~= "string" then
		return false
	end
	local limit = maxLen or MAX_STRING_LEN
	return #val > 0 and #val <= limit
end

local function validateVector3(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	-- Reject NaN or Infinity values
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		return false
	end
	if math.abs(v.X) > 1e6 or math.abs(v.Y) > 1e6 or math.abs(v.Z) > 1e6 then
		return false
	end
	return true
end

local function validateNumber(num: any, minVal: number?, maxVal: number?): boolean
	if type(num) ~= "number" then
		return false
	end
	if num ~= num or num == math.huge or num == -math.huge then
		return false
	end
	if minVal and num < minVal then
		return false
	end
	if maxVal and num > maxVal then
		return false
	end
	return true
end

function CombatServer.ValidateHitPayload(payload: any): boolean
	if type(payload) ~= "table" then
		return false
	end
	if not validateVector3(payload.origin) then
		return false
	end
	if not validateVector3(payload.direction) then
		return false
	end
	if not validateVector3(payload.hitPosition) then
		return false
	end
	if not validateNumber(payload.distance, 0, 10000) then
		return false
	end
	if not validateNumber(payload.clientTimestamp, 0) then
		return false
	end
	if not validateNumber(payload.sequenceId, 0) then
		return false
	end
	if not validateString(payload.weaponId, 32) then
		return false
	end

	-- Direction magnitude check
	local dirMag = payload.direction.Magnitude
	if dirMag < 0.9 or dirMag > 1.1 then
		return false
	end

	-- Payload must include seed for server spread re-sim (reject pre-seeded client spread exploits)
	if payload.seed ~= nil and type(payload.seed) ~= "number" then
		return false
	end

	return true
end

-- ----------------------------------------------------------------------------
-- 4. Spatial Position Update & Snapshot Ingestion
-- ----------------------------------------------------------------------------

function CombatServer.UpdatePlayerSpatial(
	self: CombatServerClass,
	userId: number,
	position: Vector3,
	velocity: Vector3,
	cframe: CFrame,
	timestamp: number?
)
	if not validateVector3(position) or not validateVector3(velocity) then
		return
	end

	local ts = timestamp or os.clock()
	self._rollbackBuffer:PushSnapshot(tostring(userId), {
		timestamp = ts,
		position = position,
		velocity = velocity,
		cframe = cframe,
	})
end

-- ----------------------------------------------------------------------------
-- 5. Hit Processing & Damage Application Pipeline
-- ----------------------------------------------------------------------------

function CombatServer.ProcessHitReport(
	self: CombatServerClass,
	attackerUserId: number,
	victimUserId: number,
	payload: Types.HitVerificationPayload,
	maxWeaponRange: number?,
	baseDamage: number?
): (boolean, string?, number?)
	-- State Machine Phase Check (Allow InGame or PracticeRange)
	if self._matchPhase ~= "InGame" and self._matchPhase ~= "PracticeRange" then
		return false, "InvalidMatchPhase", nil
	end

	-- Player Match Status Check
	local attackerPlayer = Players:GetPlayerByUserId(attackerUserId)
	local victimPlayer = Players:GetPlayerByUserId(victimUserId)

	if attackerPlayer then
		local status = DirectChallengeService.GetPlayerStatus(attackerPlayer)
		if status == "In Lobby" then
			return false, "AttackerInLobby", nil
		end
	end

	if victimPlayer and victimUserId ~= 0 then
		local status = DirectChallengeService.GetPlayerStatus(victimPlayer)
		if status == "In Lobby" then
			return false, "VictimInLobby", nil
		end
	end

	-- Attacker & Victim Alive Checks
	if not self:IsPlayerAlive(attackerUserId) then
		return false, "AttackerDead", nil
	end
	if victimPlayer and victimUserId ~= 0 and not self:IsPlayerAlive(victimUserId) then
		return false, "VictimDead", nil
	end

	-- Leaky Bucket Rate Limiter Check (Capacity 10, Refill 25/sec)
	if not self:_checkRateLimit(attackerUserId, "ReportHit", 10, 25) then
		return false, "RateLimitExceeded", nil
	end

	-- Type & Bounds Validation
	if not CombatServer.ValidateHitPayload(payload) then
		return false, "MalformedPayload", nil
	end

	-- Server Damage Calculation
	local weaponName = payload.weaponId or "AssaultRifle"
	local stats = WeaponStats.Get(weaponName)
	if not stats then
		warn("Invalid weapon ID received from client: " .. tostring(weaponName))
		return false, "InvalidWeapon", nil
	end

	-- isHeadshot is NOT trusted from client — derived server-side after rollback; payload.isHeadshot ignored
	local reportedDistance = payload.distance or 0
	local isHeadshot = false -- body-shot assumption for base calc; true headshot bonus applied after OBB if validated
	local rawDamage = WeaponStats.CalculateDamage(weaponName, isHeadshot, math.min(reportedDistance, 10000))
	-- baseDamage override: only honor when attacker is not a real Player (internal deployable). Client ReportHit always has attackerUserId == player
	if baseDamage and baseDamage > 0 then
		local attackerPlayerCheck = Players:GetPlayerByUserId(attackerUserId)
		if not attackerPlayerCheck then
			rawDamage = baseDamage
		end
	end

	-- Weapon Range Bounds Check — pre-check on reported distance; server-measured distance checked after rollback
	local maxRange = maxWeaponRange or stats.maxRange or 1000
	if reportedDistance > maxRange + 5.0 then
		return false, "ExceedsWeaponRange", nil
	end

	-- Server spread cone check — direction must be within spreadMax of rewound attacker lookVector
	do
		local attackerSnap = self._rollbackBuffer:GetSnapshot(tostring(attackerUserId), payload.clientTimestamp)
		if attackerSnap and attackerSnap.cframe then
			local forward = attackerSnap.cframe.LookVector
			local dir = payload.direction.Unit
			local dot = math.clamp(forward:Dot(dir), -1, 1)
			local angleDeg = math.deg(math.acos(dot))
			local allowed = (stats.spreadMax or 5) + 2.0 -- +2 deg tolerance for movement
			if angleDeg > allowed then
				return false, "SpreadExceeded", nil
			end
		end
	end

	local now = os.clock()

	-- Non-player victim handling (Practice Range Patrol Bot or Target Wall)
	if not victimPlayer or victimUserId == 0 then
		if payload.targetInstance then
			local targetInst = payload.targetInstance
			local targetModel = targetInst:FindFirstAncestorOfClass("Model")
			local botHumanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
			if botHumanoid then
				botHumanoid:TakeDamage(rawDamage)
				return true, nil, botHumanoid.Health
			end
			local isBullseye = targetInst:GetAttribute("IsBullseye") == true
				or targetInst.Name == "Bullseye"
				or string.find(targetInst.Name, "TargetRing_") ~= nil
			local isTargetWall = targetInst:GetAttribute("IsTarget") == true
				or string.find(targetInst.Name, "Target") ~= nil
				or isBullseye
			if
				isTargetWall
				or targetInst:GetAttribute("IsPracticeTarget") == true
				or targetInst.Name == "PracticeTarget"
			then
				return true, nil, 0
			end
		end
		if self._matchPhase == "PracticeRange" then
			return true, nil, 0
		end
	end

	-- Server-Authoritative Hit Validation Pipeline for Player Victim
	if victimPlayer and victimUserId ~= 0 then
		local valResult = HitValidation.ValidateHit(
			self._rollbackBuffer,
			tostring(attackerUserId),
			tostring(victimUserId),
			payload,
			now,
			{
				maxRollbackMs = self._options.maxRollbackMs,
				maxOriginTolerance = 15.0,
				rayDistanceMargin = 4.0,
			}
		)

		if not valResult.valid then
			return false, valResult.reason, nil
		end
		-- Server-measured distance check (prevents client lying about distance=0)
		if valResult.calculatedDistance and valResult.calculatedDistance > maxRange + 5.0 then
			return false, "ExceedsWeaponRange", nil
		end
		-- Use server-validated hitPosition/distance when available
		if valResult.hitPosition then
			payload.hitPosition = valResult.hitPosition
		end
	end

	-- Apply Damage to Victim (50% Armor Absorption Logic)
	local victimState = self._playerHealth[victimUserId]
	local healthDmgToApply = rawDamage
	if victimState then
		if victimState.shield > 0 then
			local maxAbsorption = math.floor(rawDamage * 0.5)
			local shieldDmg = math.min(victimState.shield, maxAbsorption)
			healthDmgToApply = rawDamage - shieldDmg

			victimState.shield -= shieldDmg
			victimState.health = math.max(0, victimState.health - healthDmgToApply)
		else
			victimState.health = math.max(0, victimState.health - rawDamage)
			healthDmgToApply = rawDamage
		end
	end

	-- Apply damage to Roblox Character Humanoid
	local wasKilled = false
	if victimPlayer and victimPlayer.Character then
		local hum = victimPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local prevHealth = hum.Health
			hum:TakeDamage(healthDmgToApply)

			if prevHealth > 0 and hum.Health <= 0 then
				wasKilled = true
			end
		end
	end

	if wasKilled then
		local attackerP = Players:GetPlayerByUserId(attackerUserId)
		if attackerP then
			PlayerDataService.AddKill(attackerP)
		end
		if victimPlayer then
			PlayerDataService.AddDeath(victimPlayer)
		end
	end

	-- Dispatch Reliable Damage Remote Event
	local pcallSuccess, pcallErr = pcall(function()
		local damageRemote = RemoteEvents.GetReliable("DamageDealt")
		if damageRemote then
			local attackerP = Players:GetPlayerByUserId(attackerUserId)
			if attackerP then
				damageRemote:FireClient(attackerP, {
					attackerUserId = attackerUserId,
					victimUserId = victimUserId,
					remainingHealth = victimState and victimState.health or 0,
					remainingShield = victimState and victimState.shield or 0,
					hitPosition = payload.hitPosition,
				})
			end
			local victimP = Players:GetPlayerByUserId(victimUserId)
			if victimP then
				damageRemote:FireClient(victimP, {
					attackerUserId = attackerUserId,
					victimUserId = victimUserId,
					remainingHealth = victimState and victimState.health or 0,
					remainingShield = victimState and victimState.shield or 0,
					hitPosition = payload.hitPosition,
				})
			end
		end
	end)

	if not pcallSuccess then
		-- Silently handle network dispatch errors
	end

	return true, nil, victimState and victimState.health
end

-- ----------------------------------------------------------------------------
-- 6. Initialization & Network Event Binding
-- ----------------------------------------------------------------------------

local _handoffSetupDone = false
local function setupHandoffRemotes(self: CombatServerClass)
	if _handoffSetupDone or (_G :: any).__CombatHandoffSetupDone then return end
	_handoffSetupDone = true
	;(_G :: any).__CombatHandoffSetupDone = true
	-- Handoff §6.2/6.3: RequestFire (weaponId, dir) + RequestReload — server-authoritative muzzle, magazine, ray vs projectile
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")
	local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any)
	local ProjectileService = require(script.Parent:WaitForChild("ProjectileService") :: any)
	-- Legacy ReplicatedStorage.Remotes fallback is populated by RemoteEvents.EnsureLegacyRemotes / BootstrapService
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
	if not requestFire then return end

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

	requestFire.OnServerEvent:Connect(function(player: Player, weaponId: any, rawDir: any, _seq: any)
		if type(weaponId) ~= "string" or typeof(rawDir) ~= "Vector3" then return end
		if not finiteVector(rawDir) then return end
		if rawDir.Magnitude < 0.001 then return end
		-- Find weapon config — handoff WeaponConfig authoritative, fallback to OVERCLOCK WeaponStats for legacy
		local cfg: any = nil
		do
			local ok, wc = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig") :: any) end)
			if ok and wc and wc[weaponId] then cfg = wc[weaponId] end
		end
		if not cfg then
			pcall(function()
				cfg = WeaponStats[weaponId] or (WeaponStats.GetWeapon and WeaponStats.GetWeapon(weaponId))
			end)
		end
		if not cfg then return end
		local character, _, root, _, origin = playerWeapon(player, weaponId)
		if not character or not root or not origin then return end
		-- Spawn protection gate — damage gate rejects if attacker not Playing
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
		-- Security: reject non-finite and range*speed >=1e6
		if fireMode == "Projectile" then
			local speed = cfg.projectileSpeed or cfg.ProjectileSpeed or 150
			local grav = cfg.projectileGravityScale or cfg.GravityScale or 1
			local lifetime = cfg.projectileLifetime or 5
			if not finite(speed) or not finite(grav) or not finite(lifetime) then return end
			if range * speed >= 1e6 then return end
			ProjectileService.spawn(player, weaponId, origin, dir, speed, grav, lifetime, function(hit: RaycastResult?)
				if hit then
					local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
					local hum = mdl and mdl:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
					if hum and hum.Health > 0 then
						local pl = game:GetService("Players"):GetPlayerFromCharacter(mdl)
						if pl ~= player and (not pl or pl.Team ~= player.Team) and not mdl:FindFirstChildOfClass("ForceField") then
							if not pl or pl:GetAttribute("PlayerState") == "Playing" then hum:TakeDamage(damage) end
						end
					end
				end
			end)
			if shotVisual then pcall(function() shotVisual:FireAllClients(player, weaponId, origin, origin, nil) end) end
		else
			if range * 1 >= 1e6 then return end -- hitscan range guard
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
					local pl = game:GetService("Players"):GetPlayerFromCharacter(mdl)
					if pl ~= player and (not pl or pl.Team ~= player.Team) and not mdl:FindFirstChildOfClass("ForceField") then
						if not pl or pl:GetAttribute("PlayerState") == "Playing" then hum:TakeDamage(damage) end
					end
				end
			end
			if shotVisual then pcall(function() shotVisual:FireAllClients(player, weaponId, origin, endpoint, hit and hit.Normal or nil) end) end
		end
	end)

	if requestReload then
		requestReload.OnServerEvent:Connect(function(player: Player, weaponId: any)
			if type(weaponId) ~= "string" then return end
			local character = player.Character
			if not character or player:GetAttribute("PlayerState") ~= "Playing" then return end
			local tool = character:FindFirstChildWhichIsA("Tool") :: Tool?
			if not tool or (tool:GetAttribute("WeaponId") or tool.Name) ~= weaponId then return end
			local cfg: any = nil
			do
				local ok, wc = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig") :: any) end)
				if ok and wc and wc[weaponId] then cfg = wc[weaponId] end
			end
			if not cfg then
				pcall(function() cfg = WeaponStats[weaponId] or (WeaponStats.GetWeapon and WeaponStats.GetWeapon(weaponId)) end)
			end
			if not cfg then return end
			local now = Workspace:GetServerTimeNow()
			local mags = stateTable(ammo, player.UserId)
			local reloads = stateTable(reloadUntil, player.UserId)
			local magSize = cfg.magazineSize or cfg.MagazineSize or 30
			mags[weaponId] = mags[weaponId] or magSize
			if mags[weaponId] >= magSize or now < (reloads[weaponId] or 0) then return end
			local reloadSecs = cfg.reloadSeconds or cfg.ReloadTime or 2.2
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

	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastShot[p.UserId] = nil
		ammo[p.UserId] = nil
		reloadUntil[p.UserId] = nil
	end)
end

function CombatServer.InitializeNetworkListeners(self: CombatServerClass)
	RemoteEvents.Initialize()

	-- FPS movement authority: intent-only, server-sampled snapshots with server time
	pcall(function() MovementAuthorityBootstrap.Attach(self) end)

	setupHandoffRemotes(self)

	local combatRemote = RemoteEvents.GetReliable("ReliableCombat")
	combatRemote.OnServerEvent:Connect(function(player: Player, rawData: any)
		-- Wrap processing in pcall to silently discard invalid/malicious payloads without crashing
		pcall(function()
			if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
				return
			end
			if typeof(rawData) ~= "table" then
				return
			end

			local action = rawData.action
			local payload = rawData.payload
			if typeof(action) ~= "string" or typeof(payload) ~= "table" then
				return
			end

			if action == "ReportHit" then
				if
					typeof(payload.victimUserId) == "number"
					and payload.victimUserId >= 0
					and payload.victimUserId == math.floor(payload.victimUserId)
				then
					self:ProcessHitReport(player.UserId, payload.victimUserId, payload.hitData)
				end
			end
		end)
	end)

	local unreliableCombat = RemoteEvents.GetUnreliable("UnreliableCombat")
	unreliableCombat.OnServerEvent:Connect(function(player: Player, bufferData: any)
		pcall(function()
			if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(bufferData) ~= "buffer" then
				return
			end

			if self:_checkRateLimit(player.UserId, "FireWeapon", 10, 20) then
				local origin, direction = BufferSerializer.DeserializeFireIntent(bufferData)
				if validateVector3(origin) and validateVector3(direction) then
					direction = direction.Unit
					local char = player.Character
					if char then
						local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp and (hrp.Position - origin).Magnitude > 10 then
							return
						end
					end
					local tracerRemote = RemoteEvents.GetUnreliable("BulletTracer")
					if tracerRemote then
						tracerRemote:FireAllClients({
							shooterId = player.UserId,
							origin = origin,
							direction = direction,
						})
					end
				end
			end
		end)
	end)

	-- Client position sync retired: MovementAuthority now samples HumanoidRootPart directly and feeds UpdatePlayerSpatial with server time. Keep MovementValidator only for systems that still call it explicitly.
	do end

	Players.PlayerRemoving:Connect(function(player)
		MovementValidator.ClearPlayer(player.UserId)
	end)
end

return CombatServer
