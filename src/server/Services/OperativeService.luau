--!strict
--[=[
    Project OVERCLOCK: OperativeService
    Server-authoritative engine for Operative selection, ultimate accumulation math,
    cooldown management, credit cost validation, status debuffs, deployable entity management,
    Practice Range sandbox overrides, and remote state replication.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local OperativeStats = require(DataFolder:WaitForChild("OperativeStats") :: any)

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

type AbilitySlot = OperativeStats.AbilitySlot
type OperativeData = OperativeStats.OperativeData
type AbilityData = OperativeStats.AbilityData

export type PlayerOperativeState = {
	selectedOperative: string,
	ultCharge: number, -- 0 to 100
	cooldownEndTimestamps: {
		Basic: number,
		Paid: number,
		Ultimate: number,
	},
	silencedUntil: number,
	overshield: number,
	overshieldExpire: number,
	damageReduction: number,
	damageReductionExpire: number,
	hyperdriveExpire: number,
	siegeTurretExpire: number,
}

export type DeployableEntity = {
	id: string,
	owner: Player,
	opId: string,
	abilityId: string,
	deployableType: string,
	instance: Instance,
	hp: number,
	maxHp: number,
	position: Vector3,
	radius: number,
	durationEnd: number,
	lastTick: number,
}

local OperativeService = {}

-- Internal Player State Tracking (UserId -> PlayerOperativeState)
local playerStates: { [number]: PlayerOperativeState } = {}

-- Internal Deployable Entities (deployableId -> DeployableEntity)
local activeDeployables: { [string]: DeployableEntity } = {}
local deployableCounter = 0

-- External Service References
local _combatServerRef: any = nil
local _roundServiceRef: any = nil
local _economyServiceRef: any = nil
local _directChallengeServiceRef: any = nil
local _spawnServiceRef: any = nil

local function getSpawnService(): any
	if not _spawnServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local ssMod = servicesFolder:FindFirstChild("SpawnService")
			if ssMod then
				_spawnServiceRef = require(ssMod :: any)
			end
		end
	end
	return _spawnServiceRef
end

local function getDirectChallengeService()
	if not _directChallengeServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local dcs = servicesFolder:FindFirstChild("DirectChallengeService")
			if dcs then
				_directChallengeServiceRef = require(dcs :: any)
			end
		end
	end
	return _directChallengeServiceRef
end

local function getEconomyService()
	if not _economyServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local es = servicesFolder:FindFirstChild("EconomyService")
			if es then
				_economyServiceRef = require(es :: any)
			end
		end
	end
	return _economyServiceRef
end

local function getRoundService()
	if not _roundServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local rs = servicesFolder:FindFirstChild("RoundService")
			if rs then
				_roundServiceRef = require(rs :: any)
			end
		end
	end
	return _roundServiceRef
end

--- Returns default state for a player
local function createDefaultState(opId: string?): PlayerOperativeState
	return {
		selectedOperative = opId or "Vex",
		ultCharge = 0,
		cooldownEndTimestamps = {
			Basic = 0,
			Paid = 0,
			Ultimate = 0,
		},
		silencedUntil = 0,
		overshield = 0,
		overshieldExpire = 0,
		damageReduction = 0,
		damageReductionExpire = 0,
		hyperdriveExpire = 0,
		siegeTurretExpire = 0,
	}
end

--- Gets or creates player state
function OperativeService.GetPlayerState(player: Player): PlayerOperativeState
	local st = playerStates[player.UserId]
	if not st then
		st = createDefaultState("Vex")
		playerStates[player.UserId] = st
	end
	return st
end

--- Sets CombatServer reference
function OperativeService.SetCombatServer(combatServer: any)
	_combatServerRef = combatServer
end

--- Sets RoundService reference
function OperativeService.SetRoundService(roundService: any)
	_roundServiceRef = roundService
end

--- Checks if player is in Practice Range mode
function OperativeService.IsPracticeRange(player: Player): boolean
	local dcs = getDirectChallengeService()
	if dcs then
		local status = dcs.GetPlayerStatus(player)
		if status == "Practice Range" then
			return true
		end
	end
	if player:GetAttribute("IsPracticeRange") == true then
		return true
	end
	if _combatServerRef and _combatServerRef:GetMatchPhase() == "PracticeRange" then
		return true
	end
	return false
end

--- Syncs state to client via RemoteEvent
function OperativeService.NotifyStateSync(player: Player)
	local st = OperativeService.GetPlayerState(player)
	local isRange = OperativeService.IsPracticeRange(player)

	pcall(function()
		local syncRemote = RemoteEvents.GetReliable("OperativeStateSync" :: any)
		if syncRemote then
			syncRemote:FireClient(player, {
				selectedOperative = st.selectedOperative,
				ultCharge = if isRange then 100 else st.ultCharge,
				cooldowns = {
					Basic = if isRange then 0 else math.max(0, st.cooldownEndTimestamps.Basic - os.clock()),
					Paid = if isRange then 0 else math.max(0, st.cooldownEndTimestamps.Paid - os.clock()),
					Ultimate = if isRange then 0 else math.max(0, st.cooldownEndTimestamps.Ultimate - os.clock()),
				},
				isSilenced = os.clock() < st.silencedUntil,
				overshield = if os.clock() < st.overshieldExpire then st.overshield else 0,
				damageReduction = if os.clock() < st.damageReductionExpire then st.damageReduction else 0,
			})
		end
	end)
end

--- Selects an operative for a player
function OperativeService.SelectOperative(player: Player, opId: string): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
		return false, "InvalidPlayer"
	end
	if typeof(opId) ~= "string" or #opId == 0 or #opId > 50 then
		return false, "InvalidOperative"
	end

	local opData = OperativeStats.Get(opId)
	if not opData then
		return false, "InvalidOperative"
	end

	local isRange = OperativeService.IsPracticeRange(player)
	local rs = getRoundService()
	if rs and not isRange then
		local match = rs.GetPlayerMatch(player)
		if match and match.phase == "Live" then
			return false, "CannotSwitchMidRound"
		end
	end

	local st = OperativeService.GetPlayerState(player)
	st.selectedOperative = opId

	-- Apply default character visuals/attributes if needed
	local char = player.Character
	if char then
		char:SetAttribute("OperativeId", opId)
	end

	OperativeService.NotifyStateSync(player)
	print("[OperativeService] Player " .. player.Name .. " selected Operative: " .. opId)
	return true, "Success"
end

--- Ultimate Accumulation Math
--- 100 damage dealt = +10% ult charge (0.1% per 1 damage)
--- 1 kill = +20% ult charge
function OperativeService.AddUltCharge(player: Player, amount: number): number
	local st = OperativeService.GetPlayerState(player)
	local oldCharge = st.ultCharge
	st.ultCharge = math.clamp(st.ultCharge + amount, 0, 100)
	if st.ultCharge ~= oldCharge then
		OperativeService.NotifyStateSync(player)
	end
	return st.ultCharge
end

function OperativeService.OnDamageDealt(attackerPlayer: Player, damageAmount: number)
	if damageAmount > 0 then
		local chargeGain = damageAmount * 0.1 -- 100 dmg = 10%
		OperativeService.AddUltCharge(attackerPlayer, chargeGain)
	end
end

function OperativeService.OnKill(killerPlayer: Player)
	OperativeService.AddUltCharge(killerPlayer, 20) -- 1 kill = 20%
end

--- Round Cooldown Resets
function OperativeService.ResetRoundCooldowns(player: Player)
	local st = OperativeService.GetPlayerState(player)
	st.cooldownEndTimestamps.Basic = 0
	st.cooldownEndTimestamps.Paid = 0
	st.silencedUntil = 0
	st.overshield = 0
	st.damageReduction = 0

	local char = player.Character
	if char then
		char:SetAttribute("Silenced", nil)
		char:SetAttribute("SpeedMultiplier", nil)
		char:SetAttribute("CCImmune", nil)
		char:SetAttribute("SiegeTurret", nil)
	end

	OperativeService.NotifyStateSync(player)
end

function OperativeService.ResetAllMatchCooldowns(players: { Player })
	for _, p in players do
		if p and p.Parent then
			OperativeService.ResetRoundCooldowns(p)
		end
	end
end

--- Active Deployables Registry Access
function OperativeService.GetActiveDeployables(): { [string]: DeployableEntity }
	return activeDeployables
end

function OperativeService.DestroyDeployable(deployableId: string)
	local dep = activeDeployables[deployableId]
	if dep then
		if dep.instance and dep.instance.Parent then
			dep.instance:Destroy()
		end
		activeDeployables[deployableId] = nil
	end
end

function OperativeService.ClearAllDeployables()
	for id, _ in activeDeployables do
		OperativeService.DestroyDeployable(id)
	end
end

--- Spawns deployable helper
local function createDeployableInstance(
	owner: Player,
	opId: string,
	abilityId: string,
	deployableType: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	hp: number,
	duration: number,
	radius: number
): DeployableEntity
	deployableCounter += 1
	local id = "Deployable_" .. tostring(deployableCounter)

	local part = Instance.new("Part")
	part.Name = deployableType .. "_" .. id
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = (deployableType == "EnergyWall")
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = if deployableType == "EnergyWall" then 0.3 else 0.5
	part.Parent = Workspace

	part:SetAttribute("DeployableId", id)
	part:SetAttribute("OwnerUserId", owner.UserId)
	part:SetAttribute("DeployableType", deployableType)
	part:SetAttribute("Health", hp)

	local entity: DeployableEntity = {
		id = id,
		owner = owner,
		opId = opId,
		abilityId = abilityId,
		deployableType = deployableType,
		instance = part,
		hp = hp,
		maxHp = hp,
		position = cframe.Position,
		radius = radius,
		durationEnd = os.clock() + duration,
		lastTick = os.clock(),
	}

	activeDeployables[id] = entity
	return entity
end

--- Main Ability Execution Engine
function OperativeService.UseAbility(player: Player, slot: AbilitySlot, targetData: any): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
		return false, "InvalidPlayer"
	end
	if typeof(slot) ~= "string" or (slot ~= "Basic" and slot ~= "Paid" and slot ~= "Ultimate") then
		return false, "InvalidSlot"
	end

	local st = OperativeService.GetPlayerState(player)
	local now = os.clock()

	-- 1. Check Silence status
	if now < st.silencedUntil then
		return false, "Silenced"
	end

	-- 2. Check Player Alive status
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or (char.Humanoid :: Humanoid).Health <= 0 then
		return false, "PlayerDead"
	end
	if _combatServerRef and not _combatServerRef:IsPlayerAlive(player.UserId) then
		return false, "PlayerDead"
	end

	-- 3. Fetch Operative and Ability Data
	local opData = OperativeStats.Get(st.selectedOperative)
	if not opData then
		return false, "InvalidOperative"
	end
	local abilityData = OperativeStats.GetAbility(st.selectedOperative, slot)
	if not abilityData then
		return false, "InvalidAbility"
	end

	local isRange = OperativeService.IsPracticeRange(player)

	-- 4. Cooldown Check
	if not isRange and now < (st.cooldownEndTimestamps[slot] or 0) then
		return false, "OnCooldown"
	end

	-- 5. Economy Check (Paid Slot)
	local es = getEconomyService()
	if slot == "Paid" and not isRange then
		local cost = abilityData.creditCost
		local balance = es and es.GetCredits(player) or 0
		if balance < cost then
			return false, "InsufficientCredits"
		end
	end

	-- 6. Ultimate Charge Check (Ultimate Slot)
	if slot == "Ultimate" and not isRange then
		if st.ultCharge < 100 then
			return false, "UltNotReady"
		end
	end

	-- 7. Deduct Costs & Update Cooldowns
	if slot == "Paid" and not isRange and es then
		local balance = es.GetCredits(player)
		es.SetCredits(player, balance - abilityData.creditCost)
	end

	if slot == "Ultimate" and not isRange then
		st.ultCharge = 0
	end

	if not isRange then
		st.cooldownEndTimestamps[slot] = now + abilityData.cooldown
	end

	-- Decode target position / CFrame — validate bounds to prevent teleport exploit
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local originCFrame = if rootPart then rootPart.CFrame else CFrame.new(0, 100, 0)
	local targetCFrame = originCFrame

	local function isValidCFrame(cf: CFrame): boolean
		local p = cf.Position
		return p.X == p.X
			and p.Y == p.Y
			and p.Z == p.Z
			and math.abs(p.X) < 1e4
			and math.abs(p.Y) < 1e4
			and math.abs(p.Z) < 1e4
	end
	if typeof(targetData) == "CFrame" and isValidCFrame(targetData) then
		targetCFrame = targetData
	elseif typeof(targetData) == "Vector3" and targetData.X == targetData.X and math.abs(targetData.X) < 1e4 then
		targetCFrame = CFrame.new(targetData)
	elseif
		typeof(targetData) == "table"
		and typeof(targetData.cframe) == "CFrame"
		and isValidCFrame(targetData.cframe)
	then
		targetCFrame = targetData.cframe
	elseif
		typeof(targetData) == "table"
		and typeof(targetData.position) == "Vector3"
		and targetData.position.X == targetData.position.X
	then
		targetCFrame = CFrame.new(targetData.position)
	end
	-- Clamp target to within ability range of origin (prevents client sending far coords)
	local dist = (targetCFrame.Position - originCFrame.Position).Magnitude
	local maxDist = (abilityData.range or 50) + 10
	if dist > maxDist then
		targetCFrame = originCFrame
	end

	-- 8. Execute Operative Ability Logic (18 functional abilities)
	local abilityId = abilityData.id

	if abilityId == "Vex_Dart" then
		-- Tracking Dart: Raycast forward 200 studs, reveal hit target for 5s
		local direction = targetCFrame.LookVector * (abilityData.range or 200)
		local rayParams = RaycastParams.new()
		rayParams.FilterAncestorsCasesPrune = { char }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = Workspace:Raycast(originCFrame.Position, direction, rayParams)
		if result and result.Instance then
			local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
			if targetModel then
				local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
				local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
				if targetPlayer or targetHum then
					pcall(function()
						local revealRemote = RemoteEvents.GetReliable("EnemyRevealed" :: any)
						if revealRemote then
							revealRemote:FireClient(player, {
								targetCharacter = targetModel,
								duration = abilityData.duration or 5,
								outlineColor = Color3.fromRGB(255, 50, 50),
							})
						end
					end)
				end
			end
		end
	elseif abilityId == "Vex_Trap" then
		-- Shock Trap: Proximity trap (8-stud radius). 40 dmg & 40% slow (SpeedMultiplier = 0.6) for 3s
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"ShockTrap",
			targetCFrame,
			Vector3.new(2, 0.4, 2),
			Color3.fromRGB(255, 170, 0),
			50,
			20,
			abilityData.radius or 8
		)
	elseif abilityId == "Vex_EMP" then
		-- Null Void EMP: 35-stud shockwave. Destroys active deployables & silences enemies for 8s
		local empPos = originCFrame.Position
		local empRadius = abilityData.radius or 35
		local empDuration = abilityData.duration or 8

		-- Destroy enemy deployables within EMP radius
		for depId, dep in activeDeployables do
			if dep.owner ~= player and (dep.position - empPos).Magnitude <= empRadius then
				OperativeService.DestroyDeployable(depId)
			end
		end

		-- Silence enemy players & bots within EMP radius
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player then
				local otherChar = otherPlayer.Character
				if otherChar and otherChar:FindFirstChild("HumanoidRootPart") then
					local dist = ((otherChar.HumanoidRootPart :: BasePart).Position - empPos).Magnitude
					if dist <= empRadius then
						local otherSt = OperativeService.GetPlayerState(otherPlayer)
						otherSt.silencedUntil = now + empDuration
						otherChar:SetAttribute("Silenced", true)
						task.delay(empDuration, function()
							if otherChar.Parent and os.clock() >= otherSt.silencedUntil then
								otherChar:SetAttribute("Silenced", nil)
							end
						end)
						OperativeService.NotifyStateSync(otherPlayer)
					end
				end
			end
		end
	elseif abilityId == "Warden_Wall" then
		-- Energy Wall: Deploys 12x8x1 wall (300 HP, 10s) blocking bullets & sightlines
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"EnergyWall",
			targetCFrame,
			Vector3.new(12, 8, 1),
			Color3.fromRGB(0, 170, 255),
			300,
			abilityData.duration or 10,
			6
		)
	elseif abilityId == "Warden_Fortify" then
		-- Fortify Barrier: Repairs nearby friendly EnergyWall or grants +30 Overshield for 8s
		local repairedWall = false
		for _, dep in activeDeployables do
			if
				dep.owner == player
				and dep.deployableType == "EnergyWall"
				and (dep.position - originCFrame.Position).Magnitude <= 20
			then
				dep.hp = dep.maxHp
				dep.durationEnd += 5
				if dep.instance then
					dep.instance:SetAttribute("Health", dep.hp)
				end
				repairedWall = true
				break
			end
		end

		if not repairedWall then
			st.overshield = 30
			st.overshieldExpire = now + (abilityData.duration or 8)
			char:SetAttribute("Overshield", 30)
		end
	elseif abilityId == "Warden_Shield" then
		-- Aegis Shield: Personal 50% damage reduction + CC immunity for 8s
		st.damageReduction = 0.5
		st.damageReductionExpire = now + (abilityData.duration or 8)
		char:SetAttribute("DamageReduction", 0.5)
		char:SetAttribute("CCImmune", true)

		task.delay(abilityData.duration or 8, function()
			if char.Parent and os.clock() >= st.damageReductionExpire then
				char:SetAttribute("DamageReduction", nil)
				char:SetAttribute("CCImmune", nil)
			end
		end)
	elseif abilityId == "Fray_Blink" then
		-- Blink Dash: Blinks 25 studs forward (raycast obstacle check)
		local blinkDist = abilityData.range or 25
		local lookDir = originCFrame.LookVector
		local rayParams = RaycastParams.new()
		rayParams.FilterAncestorsCasesPrune = { char }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = Workspace:Raycast(originCFrame.Position, lookDir * blinkDist, rayParams)
		local finalPos = if result
			then result.Position - (lookDir * 2)
			else originCFrame.Position + (lookDir * blinkDist)
		local targetCFrame = CFrame.new(finalPos, finalPos + lookDir)

		local ss = getSpawnService()
		if ss then
			ss.TeleportCharacter(player, targetCFrame)
		elseif rootPart then
			rootPart.CFrame = targetCFrame
		end
	elseif abilityId == "Fray_Smoke" then
		-- Smoke Screen: 15-stud volumetric smoke sphere lasting 10s
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"SmokeScreen",
			targetCFrame,
			Vector3.new(30, 30, 30),
			Color3.fromRGB(150, 150, 160),
			1000,
			abilityData.duration or 10,
			abilityData.radius or 15
		)
	elseif abilityId == "Fray_Hyperdrive" then
		-- Hyperdrive: +30% fire rate, +50% reload speed, +20% move speed for 10s
		st.hyperdriveExpire = now + (abilityData.duration or 10)
		char:SetAttribute("FireRateMultiplier", 1.3)
		char:SetAttribute("ReloadSpeedMultiplier", 0.5)
		char:SetAttribute("SpeedMultiplier", 1.2)

		task.delay(abilityData.duration or 10, function()
			if char.Parent and os.clock() >= st.hyperdriveExpire then
				char:SetAttribute("FireRateMultiplier", nil)
				char:SetAttribute("ReloadSpeedMultiplier", nil)
				char:SetAttribute("SpeedMultiplier", nil)
			end
		end)
	elseif abilityId == "Choke_Static" then
		-- Static Field Grenade: 12-stud static field for 7s obscuring vision & HUD
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"StaticField",
			targetCFrame,
			Vector3.new(24, 12, 24),
			Color3.fromRGB(180, 100, 255),
			1000,
			abilityData.duration or 7,
			abilityData.radius or 12
		)
	elseif abilityId == "Choke_Incendiary" then
		-- Incendiary: 10-stud fire pool for 6s dealing 15 DPS (7.5 dmg per 0.5s tick)
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"Incendiary",
			targetCFrame,
			Vector3.new(20, 1, 20),
			Color3.fromRGB(255, 60, 0),
			1000,
			abilityData.duration or 6,
			abilityData.radius or 10
		)
	elseif abilityId == "Choke_Zero" then
		-- Absolute Zero: 30-stud cryogenic zone for 8s (-60% speed, -30% fire rate, 5 DPS freeze)
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"AbsoluteZero",
			targetCFrame,
			Vector3.new(60, 15, 60),
			Color3.fromRGB(100, 220, 255),
			1000,
			abilityData.duration or 8,
			abilityData.radius or 30
		)
	elseif abilityId == "Pulse_Sonar" then
		-- Sonar Pulse: 40-stud sonar wave revealing moving enemies for 4s
		local sonarPos = originCFrame.Position
		local sonarRadius = abilityData.radius or 40
		local sonarDuration = abilityData.duration or 4

		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player then
				local otherChar = otherPlayer.Character
				if otherChar and otherChar:FindFirstChild("HumanoidRootPart") then
					local dist = ((otherChar.HumanoidRootPart :: BasePart).Position - sonarPos).Magnitude
					if dist <= sonarRadius then
						pcall(function()
							local revealRemote = RemoteEvents.GetReliable("EnemyRevealed" :: any)
							if revealRemote then
								revealRemote:FireClient(player, {
									targetCharacter = otherChar,
									duration = sonarDuration,
									outlineColor = Color3.fromRGB(255, 50, 50),
								})
							end
						end)
					end
				end
			end
		end
	elseif abilityId == "Pulse_Beacon" then
		-- Sensor Beacon: 50 HP sticky beacon (20-stud radius), highlights enemies red for 3s
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"SensorBeacon",
			targetCFrame,
			Vector3.new(1.5, 1.5, 1.5),
			Color3.fromRGB(255, 220, 0),
			50,
			60,
			abilityData.radius or 20
		)
	elseif abilityId == "Pulse_Scan" then
		-- Global Scan: 3 map-wide radar pulses at 1.5s intervals highlighting enemies for 3s per wave
		task.spawn(function()
			for wave = 1, 3 do
				for _, otherPlayer in Players:GetPlayers() do
					if otherPlayer ~= player then
						local otherChar = otherPlayer.Character
						if otherChar then
							pcall(function()
								local revealRemote = RemoteEvents.GetReliable("EnemyRevealed" :: any)
								if revealRemote then
									revealRemote:FireClient(player, {
										targetCharacter = otherChar,
										duration = 3,
										outlineColor = Color3.fromRGB(255, 0, 0),
									})
								end
							end)
						end
					end
				end
				if wave < 3 then
					task.wait(1.5)
				end
			end
		end)
	elseif abilityId == "Bastion_Turret" then
		-- Auto-Turret: 150 HP mini-turret (40-stud range, 300 RPM, 8 dmg/shot) lasting 20s
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"AutoTurret",
			targetCFrame,
			Vector3.new(3, 4, 3),
			Color3.fromRGB(220, 50, 50),
			150,
			abilityData.duration or 20,
			abilityData.range or 40
		)
	elseif abilityId == "Bastion_Mine" then
		-- Repulsor Mine: 25 dmg & 50 studs/sec outward knockback impulse in 6-stud blast
		createDeployableInstance(
			player,
			st.selectedOperative,
			abilityId,
			"RepulsorMine",
			targetCFrame,
			Vector3.new(1.5, 0.4, 1.5),
			Color3.fromRGB(255, 100, 0),
			50,
			30,
			abilityData.radius or 6
		)
	elseif abilityId == "Bastion_Siege" then
		-- Siege Turret: Transform Bastion into stationary Siege Turret for 12s (+100 shield, minigun state)
		st.siegeTurretExpire = now + (abilityData.duration or 12)
		char:SetAttribute("SiegeTurret", true)
		if _combatServerRef then
			local stHealth = _combatServerRef:GetPlayerHealth(player.UserId)
			if stHealth then
				_combatServerRef:RegisterPlayer(player.UserId, stHealth.health, stHealth.shield + 100)
			end
		end

		task.delay(abilityData.duration or 12, function()
			if char.Parent and os.clock() >= st.siegeTurretExpire then
				char:SetAttribute("SiegeTurret", nil)
			end
		end)
	end

	-- 9. Replicate Visual Effects to Clients
	pcall(function()
		local repRemote = RemoteEvents.GetReliable("AbilityReplicated" :: any)
		if repRemote then
			repRemote:FireAllClients({
				player = player,
				userId = player.UserId,
				opId = st.selectedOperative,
				slot = slot,
				abilityId = abilityId,
				targetCFrame = targetCFrame,
			})
		end
	end)

	OperativeService.NotifyStateSync(player)
	return true, "Success"
end

--- Heartbeat loop to manage active deployables and periodic ability ticking
RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()

	for depId, dep in activeDeployables do
		-- Expiry check
		if now >= dep.durationEnd or not dep.instance or not dep.instance.Parent then
			OperativeService.DestroyDeployable(depId)
			continue
		end

		-- Periodic tick processing (every 0.5 seconds)
		if now - dep.lastTick >= 0.5 then
			dep.lastTick = now

			if dep.deployableType == "Incendiary" then
				-- Deal 7.5 dmg to enemies standing inside 10-stud radius
				for _, enemyPlayer in Players:GetPlayers() do
					if enemyPlayer ~= dep.owner then
						local enemyChar = enemyPlayer.Character
						if enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") then
							local dist = ((enemyChar.HumanoidRootPart :: BasePart).Position - dep.position).Magnitude
							if dist <= dep.radius then
								if _combatServerRef then
									_combatServerRef:ProcessHitReport(dep.owner.UserId, enemyPlayer.UserId, {
										origin = dep.position,
										direction = Vector3.new(0, -1, 0),
										hitPosition = (enemyChar.HumanoidRootPart :: BasePart).Position,
										distance = dist,
										clientTimestamp = now,
										sequenceId = 1,
										weaponId = "Ability_Incendiary",
									}, 100, 7.5)
								end
							end
						end
					end
				end
			elseif dep.deployableType == "AbsoluteZero" then
				-- Apply slow (SpeedMultiplier = 0.4) and 2.5 damage per 0.5s tick to enemies inside 30-stud radius
				for _, enemyPlayer in Players:GetPlayers() do
					if enemyPlayer ~= dep.owner then
						local enemyChar = enemyPlayer.Character
						if enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") then
							local dist = ((enemyChar.HumanoidRootPart :: BasePart).Position - dep.position).Magnitude
							if dist <= dep.radius then
								enemyChar:SetAttribute("SpeedMultiplier", 0.4)
								if _combatServerRef then
									_combatServerRef:ProcessHitReport(dep.owner.UserId, enemyPlayer.UserId, {
										origin = dep.position,
										direction = Vector3.new(0, -1, 0),
										hitPosition = (enemyChar.HumanoidRootPart :: BasePart).Position,
										distance = dist,
										clientTimestamp = now,
										sequenceId = 1,
										weaponId = "Ability_AbsoluteZero",
									}, 100, 2.5)
								end
							end
						end
					end
				end
			elseif dep.deployableType == "ShockTrap" then
				-- Proximity check (8-stud radius): 40 damage + 40% slow for 3s, then destroy trap
				for _, enemyPlayer in Players:GetPlayers() do
					if enemyPlayer ~= dep.owner then
						local enemyChar = enemyPlayer.Character
						if enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") then
							local dist = ((enemyChar.HumanoidRootPart :: BasePart).Position - dep.position).Magnitude
							if dist <= dep.radius then
								enemyChar:SetAttribute("SpeedMultiplier", 0.6)
								task.delay(3, function()
									if enemyChar.Parent then
										enemyChar:SetAttribute("SpeedMultiplier", nil)
									end
								end)
								if _combatServerRef then
									_combatServerRef:ProcessHitReport(dep.owner.UserId, enemyPlayer.UserId, {
										origin = dep.position,
										direction = Vector3.new(0, -1, 0),
										hitPosition = (enemyChar.HumanoidRootPart :: BasePart).Position,
										distance = dist,
										clientTimestamp = now,
										sequenceId = 1,
										weaponId = "Ability_ShockTrap",
									}, 100, 40)
								end
								OperativeService.DestroyDeployable(depId)
								break
							end
						end
					end
				end
			elseif dep.deployableType == "RepulsorMine" then
				-- Proximity check (6-stud radius): 25 damage + 50 studs/sec knockback impulse
				for _, enemyPlayer in Players:GetPlayers() do
					if enemyPlayer ~= dep.owner then
						local enemyChar = enemyPlayer.Character
						local root = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root then
							local diff = root.Position - dep.position
							if diff.Magnitude <= dep.radius then
								local knockDir = if diff.Magnitude > 0.1 then diff.Unit else Vector3.new(0, 1, 0)
								root.AssemblyLinearVelocity = knockDir * 50
								if _combatServerRef then
									_combatServerRef:ProcessHitReport(dep.owner.UserId, enemyPlayer.UserId, {
										origin = dep.position,
										direction = knockDir,
										hitPosition = root.Position,
										distance = diff.Magnitude,
										clientTimestamp = now,
										sequenceId = 1,
										weaponId = "Ability_RepulsorMine",
									}, 100, 25)
								end
								OperativeService.DestroyDeployable(depId)
								break
							end
						end
					end
				end
			elseif dep.deployableType == "AutoTurret" then
				-- Auto-Turret targeting: scans nearest enemy within 40 studs and fires
				for _, enemyPlayer in Players:GetPlayers() do
					if enemyPlayer ~= dep.owner then
						local enemyChar = enemyPlayer.Character
						local root = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root then
							local dist = (root.Position - dep.position).Magnitude
							if dist <= dep.radius then
								if _combatServerRef then
									_combatServerRef:ProcessHitReport(dep.owner.UserId, enemyPlayer.UserId, {
										origin = dep.position,
										direction = (root.Position - dep.position).Unit,
										hitPosition = root.Position,
										distance = dist,
										clientTimestamp = now,
										sequenceId = 1,
										weaponId = "Ability_AutoTurret",
									}, 100, 8)
								end
								break
							end
						end
					end
				end
			end
		end
	end
end)

--- Player Lifecycle Listeners
function OperativeService.Init(combatServerRef: any?)
	if combatServerRef then
		_combatServerRef = combatServerRef
	end

	Players.PlayerAdded:Connect(function(player)
		playerStates[player.UserId] = createDefaultState("Vex")
		OperativeService.NotifyStateSync(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player.UserId] = nil
		-- Clean up active deployables owned by leaving player
		for depId, dep in activeDeployables do
			if dep.owner == player then
				OperativeService.DestroyDeployable(depId)
			end
		end
	end)

	-- NOTE: UseAbility and SelectAgent remotes are handled exclusively by ServerMain to avoid duplicate handlers.

	print("[OperativeService] Initialized successfully.")
end

return OperativeService
