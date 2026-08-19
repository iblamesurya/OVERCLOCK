--!strict
--[=[
    Project OVERCLOCK: BotService
    Server-authoritative Practice Range bot AI, stationary target wall manager,
    and live accuracy stats tracker.

    Features:
    1. Stationary Target Wall Manager:
       - Detects hits on Target_Stationary_1..6 bullseye target parts.
       - Plays hit CFrame tilt animation & sound effect.
       - Tracks per-target and total hit counters.
       - Supports remote reset.
    2. Patrol Bot AI Lifecycle:
       - Spawns 4-6 moving bot humanoids in PatrolBotSection.
       - Continuous 3D waypoint navigation (Waypoints_Bot_1..8) with 8.0s stuck protection.
    3. Bot Combat Integration:
       - Bots take damage via shared CombatServer raycast code path.
       - HP <= 0 triggers death handling, visual/audio effects, and automatic 3.0s respawn.
    4. Live Accuracy Stats Tracker:
       - Tracks totalShotsFired, totalHits, totalHeadshots, accuracyPercent, headshotPercent per session.
       - Replicates live stats to client HUD via RangeStatsUpdated RemoteEvent.
       - Handles ResetRangeStats remote requests.
]=]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local PracticeRangeMapLayout = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("PracticeRangeMapLayout") :: any)
local BehaviorTree = require(script.Parent.Parent:WaitForChild("AI"):WaitForChild("BehaviorTree") :: any)
local BotActions = require(script.Parent.Parent:WaitForChild("AI"):WaitForChild("BotActions") :: any)

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

export type PracticeRangeStats = {
	totalShotsFired: number,
	totalHits: number,
	totalHeadshots: number,
	accuracyPercent: number,
	headshotPercent: number,
}

export type BotData = {
	botId: number,
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	headPart: BasePart,
	billboardGui: BillboardGui,
	healthBarFill: Frame,
	healthText: TextLabel,
	originSpawnPos: Vector3,
	currentWaypointIndex: number,
	isAlive: boolean,
	moveThread: thread?,
	ammo: number,
	lastAttackTime: number,
	behaviorTree: BehaviorTree.Node?,
	btContext: any,
	btConnection: RBXScriptConnection?,
	character: Model?,
}

export type TargetState = {
	id: number,
	targetPart: BasePart,
	bullseyePart: BasePart?,
	hitCount: number,
	originalCFrame: CFrame,
	originalColor: Color3,
	isAnimating: boolean,
}

local BotService = {}

local _targetStates: { [number]: TargetState } = {}
local _patrolBots: { [number]: BotData } = {}
local _playerStats: { [number]: PracticeRangeStats } = {}
local _initialized: boolean = false
local _activeMapFolder: Folder? = nil
local _connections: { [string]: RBXScriptConnection } = {}

-- ----------------------------------------------------------------------------
-- 1. Helper Functions
-- ----------------------------------------------------------------------------

local function calculateAccuracy(hits: number, shots: number): number
	if shots <= 0 then
		return 0.0
	end
	return math.floor((hits / shots) * 1000 + 0.5) / 10
end

local function calculateHeadshotRatio(headshots: number, hits: number): number
	if hits <= 0 then
		return 0.0
	end
	return math.floor((headshots / hits) * 1000 + 0.5) / 10
end

local function createDefaultStats(): PracticeRangeStats
	return {
		totalShotsFired = 0,
		totalHits = 0,
		totalHeadshots = 0,
		accuracyPercent = 0.0,
		headshotPercent = 0.0,
	}
end

-- ----------------------------------------------------------------------------
-- 2. Stationary Target Wall Manager
-- ----------------------------------------------------------------------------

function BotService.InitTargetWall(mapFolder: Folder)
	_targetStates = {}
	local targetWallSection = mapFolder:FindFirstChild("TargetWallSection")
	if not targetWallSection then
		return
	end

	local index = 1
	for _, child in targetWallSection:GetDescendants() do
		if child:IsA("BasePart") and (child:GetAttribute("IsTarget") == true or string.find(child.Name, "Target_Stationary_") or string.find(child.Name, "Target_Moving_")) then
			local targetId = child:GetAttribute("TargetId") or index
			local bullseye = child:FindFirstChild("Bullseye") :: BasePart?

			local state: TargetState = {
				id = typeof(targetId) == "number" and targetId or index,
				targetPart = child,
				bullseyePart = bullseye,
				hitCount = 0,
				originalCFrame = child.CFrame,
				originalColor = child.Color,
				isAnimating = false,
			}
			_targetStates[state.id] = state
			index += 1
		end
	end
end

function BotService.ProcessTargetHit(player: Player?, targetPart: BasePart, isBullseye: boolean?): boolean
	local matchedState: TargetState? = nil
	for _, state in _targetStates do
		if state.targetPart == targetPart or state.bullseyePart == targetPart or targetPart.Parent == state.targetPart then
			matchedState = state
			break
		end
	end

	if not matchedState then
		-- Fallback: check target attributes directly if state table lookup missed
		local targetId = targetPart:GetAttribute("TargetId")
		if typeof(targetId) == "number" and _targetStates[targetId] then
			matchedState = _targetStates[targetId]
		end
	end

	if not matchedState then
		return false
	end

	matchedState.hitCount += 1

	-- Audio Feedback
	local sound = Instance.new("Sound")
	sound.Name = "TargetHitSound"
	sound.SoundId = "rbxassetid://9114223178"
	sound.Volume = 0.5
	sound.Pitch = if isBullseye then 1.2 else 1.0
	sound.Parent = matchedState.targetPart
	sound:Play()
	Debris:AddItem(sound, 1.5)

	-- Visual CFrame Tilt & Flash Animation
	if not matchedState.isAnimating then
		matchedState.isAnimating = true
		local tiltCFrame = matchedState.originalCFrame * CFrame.Angles(math.rad(-15), 0, 0)
		local highlightColor = Color3.fromRGB(255, 230, 80)

		local tweenInfoIn = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tweenInfoOut = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local tweenIn = TweenService:Create(matchedState.targetPart, tweenInfoIn, {
			CFrame = tiltCFrame,
			Color = highlightColor,
		})
		local tweenOut = TweenService:Create(matchedState.targetPart, tweenInfoOut, {
			CFrame = matchedState.originalCFrame,
			Color = matchedState.originalColor,
		})

		tweenIn.Completed:Connect(function()
			tweenOut:Play()
		end)
		tweenOut.Completed:Connect(function()
			matchedState.isAnimating = false
			matchedState.targetPart.CFrame = matchedState.originalCFrame
			matchedState.targetPart.Color = matchedState.originalColor
		end)

		tweenIn:Play()
	end

	-- Record hit for player stats if provided
	if player then
		BotService.RecordHit(player, isBullseye == true)
	end

	return true
end

function BotService.ResetTargets()
	for _, state in _targetStates do
		state.hitCount = 0
		state.isAnimating = false
		state.targetPart.CFrame = state.originalCFrame
		state.targetPart.Color = state.originalColor
	end
end

function BotService.GetTargetStates(): { [number]: TargetState }
	return _targetStates
end

-- ----------------------------------------------------------------------------
-- 3. Patrol Bot AI Lifecycle
-- ----------------------------------------------------------------------------

local function createPatrolBotModel(botId: number, spawnPos: Vector3): (Model, Humanoid, BasePart, BasePart, BillboardGui, Frame, TextLabel)
	local model = Instance.new("Model")
	model.Name = "PatrolBot_" .. botId
	model:SetAttribute("IsPatrolBot", true)
	model:SetAttribute("BotId", botId)

	local diffs = {"Easy", "Medium", "Hard"}
	local chosenDiff = diffs[math.random(1, 3)]
	model:SetAttribute("BotDifficulty", chosenDiff)

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 3, 0))
	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Color = Color3.fromRGB(60, 65, 75)
	rootPart.Parent = model

	model.PrimaryPart = rootPart

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = rootPart.CFrame
	torso.Anchored = false
	torso.CanCollide = false
	torso.Material = Enum.Material.SmoothPlastic
	torso.Color = Color3.fromRGB(60, 65, 75)
	torso.Parent = model

	local torsoWeld = Instance.new("WeldConstraint")
	torsoWeld.Part0 = rootPart
	torsoWeld.Part1 = torso
	torsoWeld.Parent = rootPart

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = rootPart.CFrame * CFrame.new(0, 1.6, 0)
	head.Anchored = false
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(220, 50, 50)
	head:SetAttribute("IsHead", true)
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = rootPart
	headWeld.Part1 = head
	headWeld.Parent = rootPart

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 12
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	-- Overhead Health BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OverheadGui"
	billboard.Size = UDim2.new(0, 100, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "PATROL BOT #" .. botId
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.Parent = billboard

	local healthBarBg = Instance.new("Frame")
	healthBarBg.Name = "HealthBarBg"
	healthBarBg.Size = UDim2.new(1, 0, 0, 8)
	healthBarBg.Position = UDim2.new(0, 0, 0, 20)
	healthBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBarBg.BorderSizePixel = 0
	healthBarBg.Parent = billboard

	local healthBarFill = Instance.new("Frame")
	healthBarFill.Name = "HealthBarFill"
	healthBarFill.Size = UDim2.new(1, 0, 1, 0)
	healthBarFill.BackgroundColor3 = Color3.fromRGB(0, 220, 100)
	healthBarFill.BorderSizePixel = 0
	healthBarFill.Parent = healthBarBg

	return model, humanoid, rootPart, head, billboard, healthBarFill, nameLabel
end

function BotService.StartBotPatrol(botData: BotData)
	if botData.btConnection then
		botData.btConnection:Disconnect()
		botData.btConnection = nil
	end

	local waypoints = PracticeRangeMapLayout.GetBotWaypoints()
	if #waypoints == 0 then return end

	-- Construct Behavior Tree for Bot
	botData.behaviorTree = BehaviorTree.Selector({
		-- Priority 1: Take Cover if health is low
		BotActions.ActionTakeCover(),
		
		-- Priority 2: Engage Enemy if visible
		BehaviorTree.Sequence({
			BotActions.ActionFindTarget(),
			BehaviorTree.Selector({
				BotActions.ActionReload(),
				BotActions.ActionEngageTarget(),
			})
		}),
		
		-- Priority 3: Default Patrol
		BotActions.ActionPatrol(waypoints)
	})

	botData.btConnection = RunService.Heartbeat:Connect(function()
		if not botData.isAlive or not botData.model.Parent then
			if botData.btConnection then botData.btConnection:Disconnect() end
			return
		end
		-- Tick the tree
		if botData.behaviorTree then
			botData.behaviorTree:Tick(botData.btContext)
		end
	end)
end

function BotService.OnBotDied(botData: BotData, killerPlayer: Player?)
	if not botData.isAlive then return end
	botData.isAlive = false

	if botData.btConnection then
		botData.btConnection:Disconnect()
		botData.btConnection = nil
	end

	-- Death visual & health bar update
	botData.healthBarFill.Size = UDim2.new(0, 0, 1, 0)
	for _, child in botData.model:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = 0.8
			child.CanCollide = false
		end
	end

	-- Automatic 3.0s Respawn Lifecycle
	task.delay(3.0, function()
		if botData.model then botData.model:Destroy() end

		-- Fully regenerate the model to guarantee stable physics/joints
		local newModel, newHum, newRoot, newHead, newGui, newFill, newText = createPatrolBotModel(botData.botId, botData.originSpawnPos)
		newModel.Parent = _activeMapFolder or Workspace

		botData.model = newModel
		botData.character = newModel
		botData.humanoid = newHum
		botData.rootPart = newRoot
		botData.headPart = newHead
		botData.billboardGui = newGui
		botData.healthBarFill = newFill
		botData.healthText = newText
		
		-- Reset BT context pointers
		botData.btContext.model = newModel
		botData.btContext.humanoid = newHum
		botData.btContext.rootPart = newRoot
		botData.btContext.headPart = newHead
		botData.btContext.ammo = 30
		
		botData.isAlive = true

		newHum.HealthChanged:Connect(function(newHealth)
			local ratio = math.clamp(newHealth / newHum.MaxHealth, 0, 1)
			botData.healthBarFill.Size = UDim2.new(ratio, 0, 1, 0)
			if newHealth <= 0 and botData.isAlive then
				BotService.OnBotDied(botData, nil)
			end
		end)

		BotService.StartBotPatrol(botData)
	end)
end

function BotService.SpawnPatrolBots(count: number?, mapFolder: Folder?): { BotData }
	local numBots = count or 5
	local targetFolder = mapFolder or _activeMapFolder or Workspace:FindFirstChild("PracticeRangeMap")
	local patrolSection = if targetFolder then targetFolder:FindFirstChild("PatrolBotSection") else nil
	local container = patrolSection or targetFolder or Workspace

	local waypoints = PracticeRangeMapLayout.GetBotWaypoints()

	for i = 1, numBots do
		local wpIndex = ((i - 1) % math.max(1, #waypoints)) + 1
		local spawnPos = if #waypoints > 0 then waypoints[wpIndex] else Vector3.new((i - 3) * 10, 2, -20)

		local model, humanoid, rootPart, headPart, billboard, healthBarFill, healthText = createPatrolBotModel(i, spawnPos)
		model.Parent = container

		local botData: BotData = {
			botId = i,
			model = model,
			humanoid = humanoid,
			rootPart = rootPart,
			headPart = headPart,
			billboardGui = billboard,
			healthBarFill = healthBarFill,
			healthText = healthText,
			originSpawnPos = spawnPos,
			currentWaypointIndex = wpIndex,
			isAlive = true,
			moveThread = nil,
			ammo = 30,
			lastAttackTime = 0,
			behaviorTree = nil,
			btContext = {},
			btConnection = nil,
			character = model,
		}

		-- Setup context dictionary for BT reference
		botData.btContext.botId = botData.botId
		botData.btContext.model = botData.model
		botData.btContext.humanoid = botData.humanoid
		botData.btContext.rootPart = botData.rootPart
		botData.btContext.headPart = botData.headPart
		botData.btContext.currentWaypointIndex = botData.currentWaypointIndex
		botData.btContext.ammo = botData.ammo
		botData.btContext.lastAttackTime = botData.lastAttackTime

		_patrolBots[i] = botData

		humanoid.HealthChanged:Connect(function(newHealth)
			local ratio = math.clamp(newHealth / humanoid.MaxHealth, 0, 1)
			botData.healthBarFill.Size = UDim2.new(ratio, 0, 1, 0)

			if newHealth <= 0 and botData.isAlive then
				BotService.OnBotDied(botData, nil)
			end
		end)

		BotService.StartBotPatrol(botData)
	end

	return _patrolBots
end

function BotService.IsPracticeRange(player: Player): boolean
	return player:GetAttribute("IsPracticeRange") == true
end

function BotService.GetBots(): { [number]: BotData }
	return _patrolBots
end

-- ----------------------------------------------------------------------------
-- 4. Practice Range Live Accuracy Stats Tracker
-- ----------------------------------------------------------------------------

function BotService.GetPlayerStats(player: Player): PracticeRangeStats
	local stats = _playerStats[player.UserId]
	if not stats then
		stats = createDefaultStats()
		_playerStats[player.UserId] = stats
	end
	return stats
end

function BotService.RecordShot(player: Player)
	local stats = BotService.GetPlayerStats(player)
	stats.totalShotsFired += 1
	stats.accuracyPercent = calculateAccuracy(stats.totalHits, stats.totalShotsFired)
	BotService.ReplicateStats(player)
end

function BotService.RecordHit(player: Player, isHeadshot: boolean)
	local stats = BotService.GetPlayerStats(player)
	stats.totalHits += 1
	if isHeadshot then
		stats.totalHeadshots += 1
	end
	stats.accuracyPercent = calculateAccuracy(stats.totalHits, stats.totalShotsFired)
	stats.headshotPercent = calculateHeadshotRatio(stats.totalHeadshots, stats.totalHits)
	BotService.ReplicateStats(player)
end

function BotService.ResetPlayerStats(player: Player)
	local stats = createDefaultStats()
	_playerStats[player.UserId] = stats
	BotService.ResetTargets()
	BotService.ReplicateStats(player)
end

function BotService.ReplicateStats(player: Player)
	local stats = BotService.GetPlayerStats(player)
	local statsRemote = RemoteEvents.GetReliable("RangeStatsUpdated")
	if statsRemote then
		statsRemote:FireClient(player, {
			totalShotsFired = stats.totalShotsFired,
			totalHits = stats.totalHits,
			totalHeadshots = stats.totalHeadshots,
			accuracyPercent = stats.accuracyPercent,
			headshotPercent = stats.headshotPercent,
		})
	end
end

-- ----------------------------------------------------------------------------
-- 5. Network Listeners & Service Initialization
-- ----------------------------------------------------------------------------

function BotService.Init(mapFolder: Folder?)
	if _initialized then
		return
	end
	_initialized = true

	local rangeMap = mapFolder or Workspace:FindFirstChild("PracticeRangeMap")
	if not rangeMap then
		rangeMap = PracticeRangeMapLayout.BuildMap(Workspace)
	end
	_activeMapFolder = rangeMap

	if rangeMap then
		BotService.InitTargetWall(rangeMap)
		BotService.SpawnPatrolBots(5, rangeMap)
	end

	-- NOTE: ResetRangeStats remote is handled exclusively by ServerMain to avoid duplicate handlers.

	-- Hook combat events to record shots & hits
	local combatRemote = RemoteEvents.GetReliable("ReliableCombat")
	if combatRemote then
		_connections["ReliableCombat"] = combatRemote.OnServerEvent:Connect(function(player: Player, rawData: any)
			if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
				return
			end
			if typeof(rawData) ~= "table" then
				return
			end
			local action = rawData.action
			local payload = rawData.payload
			if typeof(action) ~= "string" then
				return
			end

			-- Practice Range mode state check
			local inRange = player:GetAttribute("IsPracticeRange") == true
			if not inRange then
				return
			end

			if action == "ReportHit" then
				if typeof(payload) == "table" and typeof(payload.hitData) == "table" then
					local targetInst = payload.hitData.targetInstance
					if typeof(targetInst) == "Instance" and targetInst:IsA("BasePart") then
						local isBullseye = targetInst:GetAttribute("IsBullseye") == true or targetInst.Name == "Bullseye" or string.find(targetInst.Name, "TargetRing_") ~= nil
						local isTargetWall = targetInst:GetAttribute("IsTarget") == true or string.find(targetInst.Name, "Target") ~= nil or isBullseye
						if isTargetWall then
							BotService.ProcessTargetHit(player, targetInst, isBullseye)
						else
							local isHeadshot = payload.hitData.isHeadshot == true or (targetInst.Name == "Head")
							BotService.RecordHit(player, isHeadshot)
						end
					end
				end
			end
		end)
	end

	local unreliableCombat = RemoteEvents.GetUnreliable("UnreliableCombat")
	if unreliableCombat then
		_connections["UnreliableCombat"] = unreliableCombat.OnServerEvent:Connect(function(player: Player, bufferData: any)
			if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(bufferData) ~= "buffer" then return end
			
			local inRange = player:GetAttribute("IsPracticeRange") == true
			if not inRange then return end

			BotService.RecordShot(player)
		end)
	end
end

function BotService.RemoveAllBots()
	for _, botData in _patrolBots do
		if botData.moveThread then
			task.cancel(botData.moveThread)
			botData.moveThread = nil
		end
		if botData.btConnection then
			botData.btConnection:Disconnect()
			botData.btConnection = nil
		end
		if botData.model then
			botData.model:Destroy()
		end
	end
	table.clear(_patrolBots)
end

function BotService.Destroy()
	for key, conn in _connections do
		conn:Disconnect()
	end
	_connections = {}

	BotService.RemoveAllBots()

	BotService.ResetTargets()
	_targetStates = {}
	_playerStats = {}
	_initialized = false
	_activeMapFolder = nil
end

return BotService
