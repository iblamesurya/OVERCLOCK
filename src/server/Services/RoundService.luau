--!strict
--[=[
    Project OVERCLOCK: RoundService
    Server state machine for 1v1 and 2v2 competitive PvP matches.
    Phases: Buy Phase (15s) -> Live Phase (60s) -> RoundEnd Phase (5s) -> Intermission Phase (3s).
    Rules: First to 7 rounds wins; sudden-death round at 6-6 tie (5000 credits).
    Features: spectate on death (suppressing mid-round respawn), character reset, team elimination detection.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

local EconomyService = require(script.Parent:WaitForChild("EconomyService") :: any)
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)
local DynamicSpawnService = require(script.Parent:WaitForChild("DynamicSpawnService") :: any)

export type RoundPhase = "Buy" | "Live" | "RoundEnd" | "Intermission" | "Ended"
export type QueueMode = "1v1" | "2v2"
export type TeamId = number

export type RoundPlayerData = {
	player: Player,
	userId: number,
	teamId: TeamId,
	isAlive: boolean,
}

export type MatchState = {
	matchId: string,
	mode: QueueMode,
	currentRound: number,
	team1Score: number,
	team2Score: number,
	team1LossStreak: number,
	team2LossStreak: number,
	phase: RoundPhase,
	timeRemaining: number,
	isSuddenDeath: boolean,
	winningTeam: TeamId?,
	team1Players: { RoundPlayerData },
	team2Players: { RoundPlayerData },
	allPlayers: { Player },
	playerLookup: { [number]: RoundPlayerData },
	activeThread: thread?,
	isMatchOver: boolean,
}

local RoundService = {}

-- Key Constants
RoundService.BUY_PHASE_DURATION = 15
RoundService.LIVE_PHASE_DURATION = 60
RoundService.ROUND_END_DURATION = 5
RoundService.INTERMISSION_DURATION = 3
RoundService.TARGET_SCORE = 7
RoundService.SUDDEN_DEATH_TIE_SCORE = 6

-- Active matches dictionary (matchId -> MatchState)
local activeMatches: { [string]: MatchState } = {}
-- Player to Match mapping (userId -> matchId)
local playerMatchMap: { [number]: string } = {}

-- External references
local _combatServerRef: any = nil
local _directChallengeServiceRef: any = nil

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

--- Sets CombatServer reference
function RoundService.SetCombatServer(combatServer: any)
	_combatServerRef = combatServer
end

--- Gets active match by matchId
function RoundService.GetMatch(matchId: string): MatchState?
	return activeMatches[matchId]
end

--- Gets active match for a given player
function RoundService.GetPlayerMatch(player: Player): MatchState?
	local matchId = playerMatchMap[player.UserId]
	if matchId then
		return activeMatches[matchId]
	end
	return nil
end

--- Gets current phase for a given player
function RoundService.GetPlayerPhase(player: Player): RoundPhase?
	local match = RoundService.GetPlayerMatch(player)
	if match then
		return match.phase
	end
	return nil
end

--- Returns whether player is currently in an active round match
function RoundService.IsPlayerInActiveMatch(player: Player): boolean
	local match = RoundService.GetPlayerMatch(player)
	return match ~= nil and not match.isMatchOver
end

--- Computes dynamic spawn position to prevent spawn-camping
local function computeSpawnPosition(match: MatchState, teamId: TeamId, index: number): Vector3
	local candidateSpawns = {
		CFrame.new(-60 + (index - 1) * 6, 105, (index - 1) * 3),
		CFrame.new(-40, 105, 40),
		CFrame.new(60 + (index - 1) * 6, 105, (index - 1) * 3),
		CFrame.new(40, 105, -40),
		CFrame.new(0, 105, 80),
		CFrame.new(0, 105, -80),
	}

	-- Identify enemies for dynamic spawn avoidance
	local enemies = {}
	for _, pData in pairs(match.team1Players) do
		if pData.teamId ~= teamId and pData.isAlive and pData.player.Character then
			table.insert(enemies, pData.player)
		end
	end
	for _, pData in pairs(match.team2Players) do
		if pData.teamId ~= teamId and pData.isAlive and pData.player.Character then
			table.insert(enemies, pData.player)
		end
	end

	local optimalSpawnCFrame = DynamicSpawnService.GetOptimalSpawn(candidateSpawns, enemies)
	return optimalSpawnCFrame.Position
end

--- Broadcasts round state update to clients in match
function RoundService.BroadcastState(match: MatchState)
	local payload = {
		matchId = match.matchId,
		phase = match.phase,
		timeRemaining = match.timeRemaining,
		currentRound = match.currentRound,
		team1Score = match.team1Score,
		team2Score = match.team2Score,
		isSuddenDeath = match.isSuddenDeath,
		winningTeam = match.winningTeam,
	}

	pcall(function()
		local roundStateRemote = RemoteEvents.GetReliable("RoundStateChanged" :: any)
		if roundStateRemote then
			for _, player in match.allPlayers do
				if player and player.Parent then
					roundStateRemote:FireClient(player, payload)
				end
			end
		end
	end)
end

--- Teleports character to spawn and restores health/armor
local function resetPlayerCharacter(match: MatchState, playerData: RoundPlayerData, index: number)
	local player = playerData.player
	if not player or not player.Parent then
		return
	end

	playerData.isAlive = true

	local spawnPos = computeSpawnPosition(match, playerData.teamId, index)
	local targetCFrame = CFrame.new(spawnPos)

	-- If character is missing or dead, spawn via SpawnService; otherwise teleport safely
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
		SpawnService.SpawnPlayer(player, "Match", targetCFrame)
		char = player.Character
	else
		SpawnService.TeleportCharacter(player, targetCFrame)
		SpawnService.SetPlayerLocation(player, "Match")
	end

	if char then
		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		if hum then
			hum.Health = hum.MaxHealth
		end

		-- Clear temporary debuffs / status attributes
		char:SetAttribute("Stunned", nil)
		char:SetAttribute("SpeedMultiplier", nil)
	end

	-- Sync CombatServer health and shield
	if _combatServerRef then
		local armorVal = 0
		if char then
			armorVal = (char:GetAttribute("Armor") :: number) or 0
		end
		_combatServerRef:RegisterPlayer(player.UserId, 100, armorVal)
	end
end

--- Resets character positions, health, and status for all match players
function RoundService.ResetAllPlayers(match: MatchState)
	for idx, pData in match.team1Players do
		resetPlayerCharacter(match, pData, idx)
	end
	for idx, pData in match.team2Players do
		resetPlayerCharacter(match, pData, idx)
	end
end

--- Evaluates end of round (winner, score update, economy bonus, next round/match end)
function RoundService.EvaluateRoundEnd(match: MatchState, winningTeam: TeamId?)
	if match.phase == "RoundEnd" or match.phase == "Ended" or match.isMatchOver then
		return
	end

	match.phase = "RoundEnd"
	-- Lock in elimination immediately so Live loop breaks promptly
	if _combatServerRef then
		_combatServerRef:SetMatchPhase("Lobby")
	end
	match.timeRemaining = RoundService.ROUND_END_DURATION

	-- Determine winner if not passed explicitly
	if not winningTeam then
		-- Timer expired: compare remaining health
		local t1Health = 0
		local t2Health = 0

		if _combatServerRef then
			for _, pData in match.team1Players do
				if pData.isAlive then
					local st = _combatServerRef:GetPlayerHealth(pData.userId)
					t1Health += (st and st.health) or 100
				end
			end
			for _, pData in match.team2Players do
				if pData.isAlive then
					local st = _combatServerRef:GetPlayerHealth(pData.userId)
					t2Health += (st and st.health) or 100
				end
			end
		else
			for _, pData in match.team1Players do
				if pData.isAlive and pData.player.Character and pData.player.Character:FindFirstChild("Humanoid") then
					t1Health += pData.player.Character.Humanoid.Health
				end
			end
			for _, pData in match.team2Players do
				if pData.isAlive and pData.player.Character and pData.player.Character:FindFirstChild("Humanoid") then
					t2Health += pData.player.Character.Humanoid.Health
				end
			end
		end

		if t1Health >= t2Health then
			winningTeam = 1
		else
			winningTeam = 2
		end
	end

	match.winningTeam = winningTeam

	-- Update Scores & Loss Streaks
	local winnerPlayers: { Player } = {}
	local loserPlayers: { Player } = {}
	local loserStreak = 0

	if winningTeam == 1 then
		match.team1Score += 1
		match.team1LossStreak = 0
		match.team2LossStreak += 1
		loserStreak = match.team2LossStreak

		for _, pData in match.team1Players do
			table.insert(winnerPlayers, pData.player)
		end
		for _, pData in match.team2Players do
			table.insert(loserPlayers, pData.player)
		end
	else
		match.team2Score += 1
		match.team2LossStreak = 0
		match.team1LossStreak += 1
		loserStreak = match.team1LossStreak

		for _, pData in match.team2Players do
			table.insert(winnerPlayers, pData.player)
		end
		for _, pData in match.team1Players do
			table.insert(loserPlayers, pData.player)
		end
	end

	-- Process Economy Round End Bonuses
	EconomyService.ProcessRoundEnd(winnerPlayers, loserPlayers, loserStreak)

	-- Broadcast state update
	RoundService.BroadcastState(match)

	-- Check Match Completion
	if match.team1Score >= RoundService.TARGET_SCORE or match.team2Score >= RoundService.TARGET_SCORE then
		match.isMatchOver = true
		match.phase = "Ended"
		RoundService.BroadcastState(match)

		task.wait(RoundService.ROUND_END_DURATION)
		RoundService.EndMatch(match.matchId, winningTeam)
		return
	end

	-- Prepare for next round
	match.currentRound += 1
end

--- Checks and applies Sudden Death condition (6-6 tie score)
function RoundService.CheckSuddenDeath(match: MatchState): boolean
	if
		match.team1Score == RoundService.SUDDEN_DEATH_TIE_SCORE
		and match.team2Score == RoundService.SUDDEN_DEATH_TIE_SCORE
	then
		match.isSuddenDeath = true
		EconomyService.SetSuddenDeathCredits(match.allPlayers)
		return true
	else
		match.isSuddenDeath = false
		return false
	end
end

--- Starts a round lifecycle flow for a match
function RoundService.StartRound(match: MatchState)
	if match.isMatchOver then
		return
	end

	-- Check Sudden Death condition (6-6 tie score, Round 13)
	RoundService.CheckSuddenDeath(match)

	-- Reset characters, positions, health
	RoundService.ResetAllPlayers(match)

	-- 1. BUY PHASE (15s)
	match.phase = "Buy"
	if _combatServerRef then
		_combatServerRef:SetMatchPhase("Lobby")
	end
	match.timeRemaining = RoundService.BUY_PHASE_DURATION
	match.winningTeam = nil
	RoundService.BroadcastState(match)

	for t = RoundService.BUY_PHASE_DURATION, 1, -1 do
		if match.isMatchOver then
			return
		end
		match.timeRemaining = t
		task.wait(1)
	end

	if match.isMatchOver then
		return
	end

	-- 2. LIVE PHASE (60s)
	match.phase = "Live"
	if _combatServerRef then
		_combatServerRef:SetMatchPhase("InGame")
	end
	match.timeRemaining = RoundService.LIVE_PHASE_DURATION
	RoundService.BroadcastState(match)

	local liveTimerPassed = 0
	while liveTimerPassed < RoundService.LIVE_PHASE_DURATION do
		if match.isMatchOver then
			return
		end
		if match.phase ~= "Live" then
			-- Mid-round elimination occurred!
			break
		end

		task.wait(1)
		liveTimerPassed += 1
		match.timeRemaining = RoundService.LIVE_PHASE_DURATION - liveTimerPassed

		if match.phase == "Live" then
			RoundService.BroadcastState(match)
		else
			break
		end
	end

	if match.isMatchOver then
		return
	end

	-- If Live phase completed without full elimination, evaluate winner by health
	if match.phase == "Live" then
		RoundService.EvaluateRoundEnd(match, nil)
	end

	if match.isMatchOver then
		return
	end

	-- 3. ROUND END PHASE DELAY (5s)
	-- EvaluateRoundEnd set match.phase = "RoundEnd"
	for t = RoundService.ROUND_END_DURATION, 1, -1 do
		if match.isMatchOver then
			return
		end
		match.timeRemaining = t
		RoundService.BroadcastState(match)
		task.wait(1)
	end

	if match.isMatchOver then
		return
	end

	-- 4. INTERMISSION PHASE (3s)
	match.phase = "Intermission"
	if _combatServerRef then
		_combatServerRef:SetMatchPhase("Lobby")
	end
	match.timeRemaining = RoundService.INTERMISSION_DURATION
	RoundService.BroadcastState(match)

	for t = RoundService.INTERMISSION_DURATION, 1, -1 do
		if match.isMatchOver then
			return
		end
		match.timeRemaining = t
		RoundService.BroadcastState(match)
		task.wait(1)
	end

	if match.isMatchOver then
		return
	end

	-- Next Round Loop — spawn new task to avoid stack growth
	if not match.isMatchOver then
		match.activeThread = task.spawn(function()
			RoundService.StartRound(match)
		end)
	end
end

--- Handles mid-round player death
function RoundService.OnPlayerDied(victimPlayer: Player, killerPlayer: Player?)
	local match = RoundService.GetPlayerMatch(victimPlayer)
	if not match or match.isMatchOver then
		return
	end

	-- Only process mid-round elimination during Live phase
	if match.phase ~= "Live" then
		return
	end

	local pData = match.playerLookup[victimPlayer.UserId]
	if pData then
		pData.isAlive = false
	end

	-- Award kill reward if killer is on opposing team
	if killerPlayer and killerPlayer ~= victimPlayer then
		local kData = match.playerLookup[killerPlayer.UserId]
		if kData and kData.teamId ~= (pData and pData.teamId or 0) then
			EconomyService.AwardKillReward(killerPlayer)
		end
	end

	-- Check team elimination
	local t1Alive = 0
	for _, p in match.team1Players do
		if p.isAlive then
			t1Alive += 1
		end
	end

	local t2Alive = 0
	for _, p in match.team2Players do
		if p.isAlive then
			t2Alive += 1
		end
	end

	if t1Alive == 0 and t2Alive > 0 then
		-- Team 2 wins round
		RoundService.EvaluateRoundEnd(match, 2)
	elseif t2Alive == 0 and t1Alive > 0 then
		-- Team 1 wins round
		RoundService.EvaluateRoundEnd(match, 1)
	elseif t1Alive == 0 and t2Alive == 0 then
		-- Draw / Team 1 default
		RoundService.EvaluateRoundEnd(match, 1)
	end
end

--- Initializes and starts a new match
function RoundService.StartMatch(matchId: string, mode: QueueMode, team1: { Player }, team2: { Player }): MatchState
	local team1Players: { RoundPlayerData } = {}
	local team2Players: { RoundPlayerData } = {}
	local allPlayers: { Player } = {}
	local playerLookup: { [number]: RoundPlayerData } = {}

	for _, p in team1 do
		local pData: RoundPlayerData = { player = p, userId = p.UserId, teamId = 1, isAlive = true }
		table.insert(team1Players, pData)
		table.insert(allPlayers, p)
		playerLookup[p.UserId] = pData
		playerMatchMap[p.UserId] = matchId

		EconomyService.InitializePlayer(p, EconomyService.PISTOL_ROUND_CREDITS)

		local dcs = getDirectChallengeService()
		if dcs then
			dcs.SetPlayerStatus(p, "In Match")
		end
	end

	for _, p in team2 do
		local pData: RoundPlayerData = { player = p, userId = p.UserId, teamId = 2, isAlive = true }
		table.insert(team2Players, pData)
		table.insert(allPlayers, p)
		playerLookup[p.UserId] = pData
		playerMatchMap[p.UserId] = matchId

		EconomyService.InitializePlayer(p, EconomyService.PISTOL_ROUND_CREDITS)

		local dcs = getDirectChallengeService()
		if dcs then
			dcs.SetPlayerStatus(p, "In Match")
		end
	end

	local match: MatchState = {
		matchId = matchId,
		mode = mode,
		currentRound = 1,
		team1Score = 0,
		team2Score = 0,
		team1LossStreak = 0,
		team2LossStreak = 0,
		phase = "Buy",
		timeRemaining = RoundService.BUY_PHASE_DURATION,
		isSuddenDeath = false,
		winningTeam = nil,
		team1Players = team1Players,
		team2Players = team2Players,
		allPlayers = allPlayers,
		playerLookup = playerLookup,
		isMatchOver = false,
	}

	activeMatches[matchId] = match

	-- Spawn match thread
	match.activeThread = task.spawn(function()
		RoundService.StartRound(match)
	end)

	return match
end

--- Concludes match and cleans up player statuses
function RoundService.EndMatch(matchId: string, winningTeam: TeamId?)
	local match = activeMatches[matchId]
	if not match then
		return
	end

	match.isMatchOver = true
	match.phase = "Ended"
	match.winningTeam = winningTeam
	RoundService.BroadcastState(match)
	if match.activeThread then
		pcall(task.cancel, match.activeThread)
		match.activeThread = nil
	end

	local dcs = getDirectChallengeService()

	for _, p in match.allPlayers do
		if p and p.Parent then
			playerMatchMap[p.UserId] = nil

			if dcs then
				dcs.SetPlayerStatus(p, "In Lobby")
			end

			-- Teleport back to Lobby — prevents stuck in arena
			pcall(function()
				SpawnService.SpawnPlayer(p, "Lobby")
				p:SetAttribute("IsPracticeRange", nil)
			end)

			pcall(function()
				local matchPhaseRemote = RemoteEvents.GetReliable("MatchPhaseTransition" :: any)
				if matchPhaseRemote then
					matchPhaseRemote:FireClient(p, {
						phase = "Lobby",
						matchId = matchId,
						winningTeam = winningTeam,
					})
				end
			end)
			-- Combat health reset is done by SpawnService + next match InitializePlayer
			if _combatServerRef then
				pcall(function()
					_combatServerRef:RegisterPlayer(p.UserId, 100, 0)
				end)
			end
		end
	end

	activeMatches[matchId] = nil
	print("[RoundService] Match " .. matchId .. " ended. Winner: Team " .. tostring(winningTeam))
end

--- Clean up player match mapping on player leave
function RoundService.OnPlayerRemoving(player: Player)
	local matchId = playerMatchMap[player.UserId]
	if matchId then
		playerMatchMap[player.UserId] = nil
		local match = activeMatches[matchId]
		if match then
			local pData = match.playerLookup[player.UserId]
			if pData and match.mode == "1v1" and not match.isMatchOver then
				local winningTeam = pData.teamId == 1 and 2 or 1
				RoundService.EndMatch(match.matchId, winningTeam)
			else
				RoundService.OnPlayerDied(player, nil)
			end
		end
	end
end

--- Initializes RoundService lifecycle listeners
function RoundService.Init(combatServerRef: any?)
	if combatServerRef then
		_combatServerRef = combatServerRef
	end

	Players.PlayerRemoving:Connect(function(player)
		RoundService.OnPlayerRemoving(player)
	end)

	print("[RoundService] Initialized successfully.")
end

return RoundService
