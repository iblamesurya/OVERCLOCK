--!strict
--[=[
    Project OVERCLOCK v2: QueueMatchmakingService
    Server-side service managing 1v1 (2 players) and 2v2 (4 players) matchmaking queues,
    player pairing logic, 5-map voting tallying, spawn point allocation, and match session initialization.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local QueueEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("QueueEvents") :: any)
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)

export type QueueMode = QueueEvents.QueueMode

export type QueueEntry = {
	player: Player,
	userId: number,
	joinTime: number,
	mode: QueueMode,
}

export type MatchPlayer = {
	player: Player,
	userId: number,
	username: string,
	displayName: string,
	teamId: number,
	spawnPosition: Vector3,
}

export type MatchSession = {
	matchId: string,
	mode: QueueMode,
	team1: { MatchPlayer },
	team2: { MatchPlayer },
	allPlayers: { [number]: MatchPlayer },
	votes: { [number]: string }, -- userId -> mapName
	mapTallies: { [string]: number },
	selectedMap: string?,
	status: "Voting" | "Starting" | "InGame" | "Ended",
	votingEndTime: number,
	creationTime: number,
}

local ALLOWED_MAPS: { string } = {
	"GreyboxArena",
	"CyberCity",
	"DesertOutpost",
	"NeonSubway",
	"Hangar18",
}

local VOTING_DURATION_SECONDS = 10
local QUEUE_PROCESS_INTERVAL = 1.0

local queues: { [QueueMode]: { QueueEntry } } = {
	["1v1"] = {},
	["2v2"] = {},
}

local playerQueueState: { [number]: QueueMode } = {}
local playerQueueJoinTime: { [number]: number } = {}
local activeMatchSessions: { [string]: MatchSession } = {}
local playerActiveMatch: { [number]: string } = {}
local processingQueue: { [number]: boolean } = {}

local isInitialized = false

local QueueMatchmakingService = {}

local function isMapAllowed(mapName: string): boolean
	for _, allowed in ipairs(ALLOWED_MAPS) do
		if allowed == mapName then
			return true
		end
	end
	return false
end

local function generateMatchId(mode: QueueMode): string
	return "MATCH_" .. mode .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

local function notifyQueueStatus(player: Player)
	local userId = player.UserId
	local mode = playerQueueState[userId]
	local inQueue = mode ~= nil
	local queueTime = 0
	local queueLen = 0

	if inQueue and mode then
		queueTime = os.time() - (playerQueueJoinTime[userId] or os.time())
		queueLen = #queues[mode]
	end

	local statusEvent = QueueEvents.GetRemoteEvent("QueueStatusUpdate")
	local payload: QueueEvents.QueueStatusData = {
		inQueue = inQueue,
		mode = mode,
		queueTimeSeconds = queueTime,
		playersInQueue = queueLen,
	}
	statusEvent:FireClient(player, payload)
end

--- Adds a player to the specified queue mode (1v1 or 2v2).
function QueueMatchmakingService.EnterQueue(player: Player, mode: QueueMode): (boolean, string)
	local userId = player.UserId

	if processingQueue[userId] then return false, "Processing" end
	processingQueue[userId] = true

	if mode ~= "1v1" and mode ~= "2v2" then
		processingQueue[userId] = nil
		return false, "Invalid queue mode specified"
	end

	if playerActiveMatch[userId] then
		processingQueue[userId] = nil
		return false, "Player is currently in an active match"
	end

	if playerQueueState[userId] then
		if playerQueueState[userId] == mode then
			processingQueue[userId] = nil
			return false, "Player is already in this queue"
		else
			processingQueue[userId] = nil
			QueueMatchmakingService.LeaveQueue(player)
			processingQueue[userId] = true
		end
	end

	local entry: QueueEntry = {
		player = player,
		userId = userId,
		joinTime = os.time(),
		mode = mode,
	}

	table.insert(queues[mode], entry)
	playerQueueState[userId] = mode
	playerQueueJoinTime[userId] = entry.joinTime

	notifyQueueStatus(player)
	processingQueue[userId] = nil
	return true, "Enqueued successfully"
end

--- Removes a player from their active queue.
function QueueMatchmakingService.LeaveQueue(player: Player): (boolean, string)
	local userId = player.UserId

	if processingQueue[userId] then return false, "Processing" end
	processingQueue[userId] = true

	local mode = playerQueueState[userId]

	if not mode then
		processingQueue[userId] = nil
		return false, "Player is not in any queue"
	end

	local targetQueue = queues[mode]
	if targetQueue then
		for idx, entry in ipairs(targetQueue) do
			if entry.userId == userId then
				table.remove(targetQueue, idx)
				break
			end
		end
	end

	playerQueueState[userId] = nil
	playerQueueJoinTime[userId] = nil

	notifyQueueStatus(player)
	processingQueue[userId] = nil
	return true, "Left queue successfully"
end

local function computeSpawnPosition(teamId: number, memberIndex: number): Vector3
	-- SAFE FALLBACK: must be above arena floor (Y=100). Previous Y=5 dropped players below FallbackBaseplate (Y=90) into void.
	local basePos: Vector3
	if teamId == 1 then
		basePos = Vector3.new(-40, 105, (memberIndex - 1) * 6)
	else
		basePos = Vector3.new(40, 105, (memberIndex - 1) * 6)
	end

	-- 1) Try authoritative map module positions first (world-space, already offset by MAP_OFFSET=0,100,0)
	pcall(function()
		local mapFolder = ReplicatedStorage:FindFirstChild("Map")
		if mapFolder then
			local greyMod = mapFolder:FindFirstChild("GreyboxArenaMap")
			if greyMod then
				local ok, mod = pcall(require, greyMod :: any)
				if ok and mod and mod.GetSpawnPoints then
					local teamName = if teamId == 1 then "Red" else "Blue"
					local ok2, pts = pcall(function()
						return (mod :: any).GetSpawnPoints(teamName)
					end)
					if ok2 and pts and #pts >= memberIndex then
						local p = pts[memberIndex]
						if typeof(p) == "Vector3" then
							basePos = p + Vector3.new(0, 3, 0)
							return
						end
					end
					if ok2 and pts and #pts > 0 then
						local p = pts[1]
						if typeof(p) == "Vector3" then
							basePos = p + Vector3.new(0, 3, 0)
						end
					end
				end
			end
		end
	end)

	-- 2) Try workspace arena folders (Greybox uses RedSpawn/BlueSpawn, legacy uses Team1/Team2)
	local arenaCandidates: { Instance? } = {
		Workspace:FindFirstChild("GreyboxArenaMap"),
		Workspace:FindFirstChild("DuelArenaMap"),
		Workspace:FindFirstChild("ClassicGreyboxMap"),
		Workspace:FindFirstChild("DuelArena"),
	}
	for _, arena in arenaCandidates do
		if arena then
			local spawnsFolder = arena:FindFirstChild("Spawns")
			if spawnsFolder then
				local nameVariants: { string } = if teamId == 1
					then { "RedSpawn", "Team1", "Team_1", "Red_Spawn" }
					else { "BlueSpawn", "Team2", "Team_2", "Blue_Spawn" }
				for _, n in nameVariants do
					local teamDir = spawnsFolder:FindFirstChild(n)
					if teamDir then
						local byIndex: BasePart? = nil
						for _, child in teamDir:GetChildren() do
							if child:IsA("BasePart") then
								local idx = child:GetAttribute("Index") or child:GetAttribute("SpawnIndex")
								if typeof(idx) == "number" and idx == memberIndex then
									byIndex = child
									break
								end
							end
						end
						if byIndex then
							return byIndex.Position + Vector3.new(0, 3, 0)
						end
						local spawns = teamDir:GetChildren()
						if #spawns >= memberIndex then
							local targetSpawn = spawns[memberIndex]
							if targetSpawn:IsA("BasePart") then
								return targetSpawn.Position + Vector3.new(0, 3, 0)
							end
						end
						for _, child in teamDir:GetChildren() do
							if child:IsA("BasePart") then
								return child.Position + Vector3.new(0, 3, 0)
							end
						end
					end
				end
			end
		end
	end

	-- 3) Legacy generic folders at Workspace root
	local genericFolder = Workspace:FindFirstChild("Spawns") or Workspace:FindFirstChild("SpawnLocations")
	if genericFolder then
		local variants: { string } = if teamId == 1
			then { "Team1", "RedSpawn", "Team_1" }
			else { "Team2", "BlueSpawn", "Team_2" }
		for _, teamFolderName in variants do
			local teamSpawnDir = genericFolder:FindFirstChild(teamFolderName)
			if teamSpawnDir then
				local spawns = teamSpawnDir:GetChildren()
				if #spawns >= memberIndex then
					local targetSpawn = spawns[memberIndex]
					if targetSpawn:IsA("BasePart") then
						return targetSpawn.Position + Vector3.new(0, 3, 0)
					end
				end
				for _, child in teamSpawnDir:GetChildren() do
					if child:IsA("BasePart") then
						return child.Position + Vector3.new(0, 3, 0)
					end
				end
			end
		end
	end

	return basePos
end

local function finalizeMapVoting(matchId: string)
	local session = activeMatchSessions[matchId]
	if not session or session.status ~= "Voting" then
		return
	end

	session.status = "Starting"

	local highestVotes = -1
	local winningMap = ALLOWED_MAPS[1]
	local candidateMaps: { string } = {}

	for _, mapName in ipairs(ALLOWED_MAPS) do
		local count = session.mapTallies[mapName] or 0
		if count > highestVotes then
			highestVotes = count
			candidateMaps = { mapName }
		elseif count == highestVotes then
			table.insert(candidateMaps, mapName)
		end
	end

	if #candidateMaps > 0 then
		winningMap = candidateMaps[math.random(1, #candidateMaps)]
	end

	session.selectedMap = winningMap

	local voteUpdateRemote = QueueEvents.GetRemoteEvent("MapVoteUpdate")
	local voteResult: QueueEvents.MapVoteResult = {
		matchId = matchId,
		mapVotes = session.mapTallies,
		winningMap = winningMap,
		votingEnded = true,
	}

	for _, matchPlayer in pairs(session.allPlayers) do
		if matchPlayer.player and matchPlayer.player:IsDescendantOf(Players) then
			voteUpdateRemote:FireClient(matchPlayer.player, voteResult)
		end
	end

	task.delay(2.0, function()
		QueueMatchmakingService.StartMatchSession(matchId)
	end)
end

--- Submits a vote for a map during the match session voting phase.
function QueueMatchmakingService.SubmitMapVote(player: Player, matchId: string, mapName: string): (boolean, string)
	local userId = player.UserId
	local session = activeMatchSessions[matchId]

	if not session then
		return false, "Match session not found"
	end

	if session.status ~= "Voting" then
		return false, "Map voting is no longer active for this match"
	end

	if not session.allPlayers[userId] then
		return false, "Player is not part of this match session"
	end

	if not isMapAllowed(mapName) then
		return false, "Invalid map name specified"
	end

	local previousVote = session.votes[userId]
	if previousVote then
		if session.mapTallies[previousVote] then
			session.mapTallies[previousVote] = math.max(0, session.mapTallies[previousVote] - 1)
		end
	end

	session.votes[userId] = mapName
	session.mapTallies[mapName] = (session.mapTallies[mapName] or 0) + 1

	local voteUpdateRemote = QueueEvents.GetRemoteEvent("MapVoteUpdate")
	local voteResult: QueueEvents.MapVoteResult = {
		matchId = matchId,
		mapVotes = session.mapTallies,
		winningMap = nil,
		votingEnded = false,
	}

	for _, matchPlayer in pairs(session.allPlayers) do
		if matchPlayer.player and matchPlayer.player:IsDescendantOf(Players) then
			voteUpdateRemote:FireClient(matchPlayer.player, voteResult)
		end
	end

	local totalVotes = 0
	for _, _ in pairs(session.votes) do
		totalVotes += 1
	end

	local requiredVotes = 0
	for _, _ in pairs(session.allPlayers) do
		requiredVotes += 1
	end

	if totalVotes >= requiredVotes then
		finalizeMapVoting(matchId)
	end

	return true, "Vote recorded successfully"
end

local function initializeMatchSession(mode: QueueMode, matchedEntries: { QueueEntry })
	local matchId = generateMatchId(mode)
	local team1: { MatchPlayer } = {}
	local team2: { MatchPlayer } = {}
	local allPlayers: { [number]: MatchPlayer } = {}

	local halfCount = math.floor(#matchedEntries / 2)

	for idx, entry in ipairs(matchedEntries) do
		local teamId = idx <= halfCount and 1 or 2
		local memberIdx = teamId == 1 and idx or (idx - halfCount)
		local spawnPos = computeSpawnPosition(teamId, memberIdx)

		local matchPlayer: MatchPlayer = {
			player = entry.player,
			userId = entry.userId,
			username = entry.player.Name,
			displayName = entry.player.DisplayName,
			teamId = teamId,
			spawnPosition = spawnPos,
		}

		if teamId == 1 then
			table.insert(team1, matchPlayer)
		else
			table.insert(team2, matchPlayer)
		end

		allPlayers[entry.userId] = matchPlayer
		playerActiveMatch[entry.userId] = matchId
		playerQueueState[entry.userId] = nil
		playerQueueJoinTime[entry.userId] = nil
	end

	local initialTallies: { [string]: number } = {}
	for _, mapName in ipairs(ALLOWED_MAPS) do
		initialTallies[mapName] = 0
	end

	local session: MatchSession = {
		matchId = matchId,
		mode = mode,
		team1 = team1,
		team2 = team2,
		allPlayers = allPlayers,
		votes = {},
		mapTallies = initialTallies,
		selectedMap = nil,
		status = "Voting",
		votingEndTime = os.time() + VOTING_DURATION_SECONDS,
		creationTime = os.time(),
	}

	activeMatchSessions[matchId] = session

	local matchFoundRemote = QueueEvents.GetRemoteEvent("QueueMatchFound")

	for _, matchPlayer in pairs(allPlayers) do
		local teammatesInfo: { QueueEvents.PlayerInfo } = {}
		local opponentsInfo: { QueueEvents.PlayerInfo } = {}

		local myTeam = matchPlayer.teamId == 1 and team1 or team2
		local oppTeam = matchPlayer.teamId == 1 and team2 or team1

		for _, tm in ipairs(myTeam) do
			table.insert(teammatesInfo, {
				userId = tm.userId,
				username = tm.username,
				displayName = tm.displayName,
			})
		end

		for _, op in ipairs(oppTeam) do
			table.insert(opponentsInfo, {
				userId = op.userId,
				username = op.username,
				displayName = op.displayName,
			})
		end

		local matchPayload: QueueEvents.MatchFoundData = {
			matchId = matchId,
			mode = mode,
			teamId = matchPlayer.teamId,
			teammates = teammatesInfo,
			opponents = opponentsInfo,
			votingDurationSeconds = VOTING_DURATION_SECONDS,
			availableMaps = ALLOWED_MAPS,
		}

		if matchPlayer.player and matchPlayer.player:IsDescendantOf(Players) then
			matchFoundRemote:FireClient(matchPlayer.player, matchPayload)
		end
	end

	task.delay(VOTING_DURATION_SECONDS, function()
		if activeMatchSessions[matchId] and activeMatchSessions[matchId].status == "Voting" then
			finalizeMapVoting(matchId)
		end
	end)
end

--- Teleports match participants to arena spawn positions and initializes match play.
function QueueMatchmakingService.StartMatchSession(matchId: string)
	local session = activeMatchSessions[matchId]
	if not session then
		return
	end

	session.status = "InGame"

	local team1Players: { Player } = {}
	local team2Players: { Player } = {}

	for _, mp in ipairs(session.team1) do
		if mp.player and mp.player:IsDescendantOf(Players) then
			table.insert(team1Players, mp.player)
		end
	end
	for _, mp in ipairs(session.team2) do
		if mp.player and mp.player:IsDescendantOf(Players) then
			table.insert(team2Players, mp.player)
		end
	end

	for _, matchPlayer in pairs(session.allPlayers) do
		local player = matchPlayer.player
		if player and player:IsDescendantOf(Players) then
			local spawnCFrame = CFrame.new(matchPlayer.spawnPosition)
			-- Authoritative spawn: handles LoadCharacter + PivotTo retries + void rescue. Previous TeleportCharacter-only path left dead/missing characters in void.
			local ok = pcall(function()
				return SpawnService.SpawnPlayer(player, "Match", spawnCFrame)
			end)
			if not ok then
				pcall(function()
					if SpawnService.TeleportCharacter(player, spawnCFrame) then
						SpawnService.SetPlayerLocation(player, "Match")
					end
				end)
			end
		end
	end

	-- Initialize state machine via RoundService
	local servicesFolder = ServerScriptService:FindFirstChild("Services")
	if servicesFolder then
		local rsMod = servicesFolder:FindFirstChild("RoundService")
		if rsMod then
			local RoundService = require(rsMod :: any)
			RoundService.StartMatch(matchId, session.mode, team1Players, team2Players)
		end
	end
end

local function processQueuePairings()
	-- 1v1 Queue: requires 2 players
	local queue1v1 = queues["1v1"]
	while #queue1v1 >= 2 do
		local candidate1 = table.remove(queue1v1, 1)
		local candidate2 = table.remove(queue1v1, 1)

		if candidate1 and candidate2 and candidate1.player:IsDescendantOf(Players) and candidate2.player:IsDescendantOf(Players) then
			initializeMatchSession("1v1", { candidate1, candidate2 })
		else
			if candidate1 and candidate1.player:IsDescendantOf(Players) then
				table.insert(queue1v1, 1, candidate1)
			end
			if candidate2 and candidate2.player:IsDescendantOf(Players) then
				table.insert(queue1v1, 1, candidate2)
			end
			break
		end
	end

	-- 2v2 Queue: requires 4 players
	local queue2v2 = queues["2v2"]
	while #queue2v2 >= 4 do
		local validGroup: { QueueEntry } = {}
		local removeIndices: { number } = {}

		for idx, entry in ipairs(queue2v2) do
			if entry.player:IsDescendantOf(Players) then
				table.insert(validGroup, entry)
				table.insert(removeIndices, idx)
				if #validGroup == 4 then
					break
				end
			end
		end

		if #validGroup == 4 then
			for i = #removeIndices, 1, -1 do
				table.remove(queue2v2, removeIndices[i])
			end
			initializeMatchSession("2v2", validGroup)
		else
			break
		end
	end

	-- Periodically update queue timer status for all players in queue
	for modeName, modeQueue in pairs(queues) do
		for _, entry in ipairs(modeQueue) do
			if entry.player and entry.player:IsDescendantOf(Players) then
				notifyQueueStatus(entry.player)
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId

	QueueMatchmakingService.LeaveQueue(player)

	local matchId = playerActiveMatch[userId]
	if matchId then
		playerActiveMatch[userId] = nil
		local session = activeMatchSessions[matchId]
		if session then
			session.allPlayers[userId] = nil

			local remainingCount = 0
			for _, _ in pairs(session.allPlayers) do
				remainingCount += 1
			end

			if remainingCount == 0 then
				activeMatchSessions[matchId] = nil
			else
				if session.status == "Voting" then
					local totalVotes = 0
					for _, _ in pairs(session.votes) do
						totalVotes += 1
					end
					if totalVotes >= remainingCount then
						finalizeMapVoting(matchId)
					end
				end
			end
		end
	end
end

--- Initializes QueueMatchmakingService, binding Remote Functions & Events.
function QueueMatchmakingService.Initialize()
	if isInitialized then
		return
	end
	isInitialized = true

	QueueEvents.Initialize()

	local enterFn = QueueEvents.GetRemoteFunction("QueueEnter")
	enterFn.OnServerInvoke = function(player: Player, mode: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return false, "Invalid player"
		end
		if typeof(mode) ~= "string" or (mode ~= "1v1" and mode ~= "2v2") then
			return false, "Invalid queue mode specified"
		end
		if playerActiveMatch[player.UserId] ~= nil then
			return false, "Player is currently in an active match"
		end
		return QueueMatchmakingService.EnterQueue(player, mode :: QueueMode)
	end

	local leaveFn = QueueEvents.GetRemoteFunction("QueueLeave")
	leaveFn.OnServerInvoke = function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return false, "Invalid player"
		end
		return QueueMatchmakingService.LeaveQueue(player)
	end

	local voteFn = QueueEvents.GetRemoteFunction("MapVoteSubmit")
	voteFn.OnServerInvoke = function(player: Player, matchId: any, mapName: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return false, "Invalid player"
		end
		if typeof(matchId) ~= "string" or #matchId == 0 or #matchId > 100 then
			return false, "Invalid match ID"
		end
		if typeof(mapName) ~= "string" or not isMapAllowed(mapName) then
			return false, "Invalid map name specified"
		end

		local session = activeMatchSessions[matchId]
		if not session or session.status ~= "Voting" then
			return false, "Map voting is no longer active for this match"
		end
		if not session.allPlayers[player.UserId] then
			return false, "Player is not part of this match session"
		end

		return QueueMatchmakingService.SubmitMapVote(player, matchId, mapName)
	end

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(QUEUE_PROCESS_INTERVAL)
			processQueuePairings()
		end
	end)
end

function QueueMatchmakingService.GetQueueLength(mode: QueueMode): number
	return #queues[mode]
end

function QueueMatchmakingService.GetActiveSessions(): { [string]: MatchSession }
	return activeMatchSessions
end

return QueueMatchmakingService
