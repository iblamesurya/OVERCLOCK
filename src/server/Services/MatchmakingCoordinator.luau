--!strict
--[=[
    Project OVERCLOCK: MatchmakingCoordinator
    Implements MemoryStoreService SortedMap matchmaking queues,
    coordinator server election via atomic control key writes,
    and deterministic user ID sharding across parallel queue maps.
]=]

local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")

-- Configuration Constants
local NUM_SHARDS = 4
local CONTROL_MAP_NAME = "MMControlMap"
local LEADER_CONTROL_KEY = "CoordinatorLeader"
local QUEUE_SHARD_PREFIX = "MMQueue_Shard_"
local LEADER_LEASE_TTL_SECONDS = 15
local ELECTION_HEARTBEAT_SECONDS = 5
local MATCHMAKING_TICK_SECONDS = 5
local DEFAULT_QUEUE_EXPIRATION_SECONDS = 600 -- 10 minutes
local MATCH_TEAM_SIZE = 5
local TOTAL_MATCH_PLAYERS = MATCH_TEAM_SIZE * 2 -- 10 players for 5v5
local TARGET_PLACE_ID = game.PlaceId -- Configurable target match place ID

export type QueueTicket = {
	userId: number,
	mmr: number,
	joinTime: number,
	partySize: number,
	partyMembers: { number },
	selectedMode: string,
}

export type LeaderRecord = {
	jobId: string,
	timestamp: number,
	term: number,
}

export type MatchLobby = {
	matchId: string,
	teamA: { QueueTicket },
	teamB: { QueueTicket },
	averageMMR: number,
}

local MatchmakingCoordinator = {}
MatchmakingCoordinator.__index = MatchmakingCoordinator

local isCoordinatorLeader = false
local electionThread: thread? = nil
local matchmakingThread: thread? = nil

-- Hidden MMR (server-authoritative, never replicated to client) with decay metric
-- Visible MMR is stored in PlayerDataService; hidden MMR is internal matchmaking rating.
-- Decay simulates rating fade for inactive players.
local HIDDEN_MMR_DECAY_PER_DAY = 8
local HIDDEN_MMR_DECAY_INTERVAL_SECONDS = 86400 -- 1 day
local HIDDEN_MMR_FLOOR = 100
local _hiddenMMR: { [number]: { value: number, lastUpdated: number } } = {}
local _hiddenMMRDecayMetric: { totalDecay: number, decayEvents: number, lastDecayAmount: number } = {
	totalDecay = 0,
	decayEvents = 0,
	lastDecayAmount = 0,
}
-- Expose decay tuning for external verification
MatchmakingCoordinator.HiddenMMRDecayPerDay = HIDDEN_MMR_DECAY_PER_DAY
MatchmakingCoordinator.HiddenMMRDecayInterval = HIDDEN_MMR_DECAY_INTERVAL_SECONDS
MatchmakingCoordinator.HiddenMMRFloor = HIDDEN_MMR_FLOOR

--[=[
    Deterministic Shard Calculation
    Distributes queue load evenly across NUM_SHARDS MemoryStore SortedMaps.
]=]
function MatchmakingCoordinator.GetShardIndex(userId: number): number
	return math.abs(userId) % NUM_SHARDS
end

function MatchmakingCoordinator.GetShardMap(shardIndex: number): MemoryStoreSortedMap?
	local mapName = QUEUE_SHARD_PREFIX .. tostring(shardIndex)
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(mapName)
	end)
	if ok then return map end
	return nil
end

function MatchmakingCoordinator.GetControlMap(): MemoryStoreSortedMap?
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(CONTROL_MAP_NAME)
	end)
	if ok then return map end
	return nil
end

--[=[
    Adds a player or party leader to the matchmaking queue.
    Uses deterministic sharding to route request to the target SortedMap.
]=]
function MatchmakingCoordinator.AddPlayerToQueueAsync(
	userId: number,
	mmr: number,
	partyMembers: { number }?,
	selectedMode: string?
): boolean
	local shardIndex = MatchmakingCoordinator.GetShardIndex(userId)
	local shardMap = MatchmakingCoordinator.GetShardMap(shardIndex)
	local ticketKey = tostring(userId)

	local members = partyMembers or { userId }
	local ticket: QueueTicket = {
		userId = userId,
		mmr = mmr,
		joinTime = os.time(),
		partySize = #members,
		partyMembers = members,
		selectedMode = selectedMode or "Standard5v5",
	}

	-- Priority score: inverse of join time or MMR (using MMR as main sort value)
	local priorityScore = math.floor(mmr)

	local success, err = pcall(function()
		shardMap:SetAsync(ticketKey, ticket, DEFAULT_QUEUE_EXPIRATION_SECONDS, priorityScore)
	end)

	if not success then
		warn("[MatchmakingCoordinator] AddPlayerToQueueAsync failed for userId " .. tostring(userId) .. ": " .. tostring(err))
		return false
	end

	return true
end

--[=[
    Removes a player from the matchmaking queue.
]=]
function MatchmakingCoordinator.RemovePlayerFromQueueAsync(userId: number): boolean
	local shardIndex = MatchmakingCoordinator.GetShardIndex(userId)
	local shardMap = MatchmakingCoordinator.GetShardMap(shardIndex)
	local ticketKey = tostring(userId)

	local success, err = pcall(function()
		shardMap:RemoveAsync(ticketKey)
	end)

	if not success then
		warn("[MatchmakingCoordinator] RemovePlayerFromQueueAsync failed for userId " .. tostring(userId) .. ": " .. tostring(err))
		return false
	end

	return true
end

--[=[
    Coordinator Election Protocol
    Atomically writes/updates control key in MemoryStore control map.
    Only one server in the cluster becomes leader and runs the matchmaker loop.
]=]
function MatchmakingCoordinator.TryElectCoordinatorAsync(): boolean
	local currentJobId = game.JobId ~= "" and game.JobId or "StudioLocalServer"
	local now = os.time()
	local elected = false

	local ok, controlMap = pcall(function()
		return MemoryStoreService:GetHashMap(CONTROL_MAP_NAME)
	end)
	if not ok or not controlMap then
		return false
	end

	local success, err = pcall(function()
		controlMap:UpdateAsync(LEADER_CONTROL_KEY, function(existing: any): LeaderRecord?
			if not existing then
				local newRecord: LeaderRecord = {
					jobId = currentJobId,
					timestamp = now,
					term = 1,
				}
				return newRecord
			else
				local record = existing :: LeaderRecord
				local elapsed = now - record.timestamp

				if record.jobId == currentJobId then
					record.timestamp = now
					return record
				elseif elapsed >= LEADER_LEASE_TTL_SECONDS then
					local newRecord: LeaderRecord = {
						jobId = currentJobId,
						timestamp = now,
						term = record.term + 1,
					}
					return newRecord
				else
					return record
				end
			end
		end, LEADER_LEASE_TTL_SECONDS + 5)
	end)

	if success then
		local checkSuccess, currentRecord = pcall(function()
			return controlMap:GetAsync(LEADER_CONTROL_KEY) :: LeaderRecord?
		end)

		if checkSuccess and currentRecord and currentRecord.jobId == currentJobId then
			elected = true
		end
	end

	return elected
end

--[=[
    Queries all sharded maps to collect active queue tickets.
    Used exclusively by the elected Coordinator server.
]=]
function MatchmakingCoordinator.CollectAllQueueTicketsAsync(): { QueueTicket }
	local allTickets: { QueueTicket } = {}

	for shardIndex = 0, NUM_SHARDS - 1 do
		local shardMap = MatchmakingCoordinator.GetShardMap(shardIndex)
		local success, items = pcall(function()
			return shardMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
		end)

		if success and items then
			for _, item in ipairs(items) do
				local ticket = item.value :: QueueTicket
				table.insert(allTickets, ticket)
			end
		end
	end

	return allTickets
end

--[=[
    Forms balanced 5v5 lobbies from candidate tickets.
]=]
function MatchmakingCoordinator.FormLobbies(tickets: { QueueTicket }): { MatchLobby }
	local lobbies: { MatchLobby } = {}

	-- Sort tickets by joinTime (FIFO priority with MMR weighting)
	table.sort(tickets, function(a, b)
		return a.joinTime < b.joinTime
	end)

	local remaining = table.clone(tickets)

	while #remaining >= TOTAL_MATCH_PLAYERS do
		local selected: { QueueTicket } = {}
		local totalMMR = 0

		for i = 1, TOTAL_MATCH_PLAYERS do
			local ticket = table.remove(remaining, 1) :: QueueTicket
			table.insert(selected, ticket)
			totalMMR += ticket.mmr
		end

		-- Split into 2 teams of 5
		table.sort(selected, function(a, b)
			return a.mmr > b.mmr
		end)

		local teamA: { QueueTicket } = {}
		local teamB: { QueueTicket } = {}
		local mmrA = 0
		local mmrB = 0

		-- Snake draft allocation for balanced MMR teams
		for idx, t in ipairs(selected) do
			if (idx % 2 == 1 and mmrA <= mmrB) or (mmrA < mmrB) then
				table.insert(teamA, t)
				mmrA += t.mmr
			else
				table.insert(teamB, t)
				mmrB += t.mmr
			end
		end

		local lobby: MatchLobby = {
			matchId = "Match_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
			teamA = teamA,
			teamB = teamB,
			averageMMR = totalMMR / TOTAL_MATCH_PLAYERS,
		}
		table.insert(lobbies, lobby)
	end

	return lobbies
end

--[=[
    Processes formed match lobbies:
    - Reserves private server place.
    - Removes matched tickets from sharded MemoryStores.
    - Teleports present players.
]=]
function MatchmakingCoordinator.ProcessLobbyAsync(lobby: MatchLobby): boolean
	-- 1. Reserve server
	local reserveSuccess, accessCode, reservedServerId = pcall(function()
		return TeleportService:ReserveServer(TARGET_PLACE_ID)
	end)

	if not reserveSuccess or not accessCode then
		warn("[MatchmakingCoordinator] Failed to reserve server for lobby " .. lobby.matchId)
		return false
	end

	-- 2. Remove tickets from MemoryStore sharded maps
	local matchedPlayers: { Player } = {}
	local allLobbyTickets: { QueueTicket } = {}
	local allUserIds: { number } = {}

	for _, ticket in ipairs(lobby.teamA) do
		table.insert(allLobbyTickets, ticket)
		table.insert(allUserIds, ticket.userId)
	end
	for _, ticket in ipairs(lobby.teamB) do
		table.insert(allLobbyTickets, ticket)
		table.insert(allUserIds, ticket.userId)
	end

	for _, ticket in ipairs(allLobbyTickets) do
		local shardIndex = MatchmakingCoordinator.GetShardIndex(ticket.userId)
		local shardMap = MatchmakingCoordinator.GetShardMap(shardIndex)
		pcall(function()
			shardMap:RemoveAsync(tostring(ticket.userId))
		end)

		local player = Players:GetPlayerByUserId(ticket.userId)
		if player then
			table.insert(matchedPlayers, player)
		end
	end

	-- Publish to MessagingService for remote players
	pcall(function()
		MessagingService:PublishAsync("MatchAssignment", {
			userIds = allUserIds,
			accessCode = accessCode,
			mapId = TARGET_PLACE_ID,
			serverId = reservedServerId,
		})
	end)

	-- 3. Teleport local players if present on this server instance
	if #matchedPlayers > 0 then
		local function tryTeleport()
			local teleportSuccess, teleportErr = pcall(function()
				local options = Instance.new("TeleportOptions")
				options.ReservedServerAccessCode = accessCode
				TeleportService:TeleportAsync(TARGET_PLACE_ID, matchedPlayers, options)
			end)
			return teleportSuccess, teleportErr
		end

		local success, err = tryTeleport()
		if not success then
			warn("[MatchmakingCoordinator] Teleport failed for lobby " .. lobby.matchId .. ": " .. tostring(err) .. ". Retrying in 2 seconds...")
			task.wait(2)
			success, err = tryTeleport()
			if not success then
				warn("[MatchmakingCoordinator] Teleport retry failed for lobby " .. lobby.matchId .. ": " .. tostring(err))
				return false
			end
		end
	end

	return true
end

--[=[
    Starts background election and matchmaking worker loops.
]=]
function MatchmakingCoordinator.StartService(): ()
	if electionThread ~= nil then
		return
	end
	
	pcall(function()
		MessagingService:SubscribeAsync("MatchAssignment", function(message)
			local data = message.Data
			if type(data) ~= "table" then return end
			local userIds = data.userIds
			local accessCode = data.accessCode
			if not userIds or type(userIds) ~= "table" then return end
			
			local localPlayers = {}
			for _, uid in ipairs(userIds) do
				local p = Players:GetPlayerByUserId(uid)
				if p then
					table.insert(localPlayers, p)
				end
			end
			
			if #localPlayers > 0 then
				local function tryLocalTeleport()
					return pcall(function()
						local options = Instance.new("TeleportOptions")
						options.ReservedServerAccessCode = accessCode
						TeleportService:TeleportAsync(TARGET_PLACE_ID, localPlayers, options)
					end)
				end
				local success, err = tryLocalTeleport()
				if not success then
					task.wait(2)
					tryLocalTeleport()
				end
			end
		end)
	end)

	-- Heartbeat election loop
	electionThread = task.spawn(function()
		while true do
			local becameLeader = MatchmakingCoordinator.TryElectCoordinatorAsync()
			isCoordinatorLeader = becameLeader
			task.wait(ELECTION_HEARTBEAT_SECONDS)
		end
	end)

	-- Matchmaking processing loop (Only executes if leader)
	matchmakingThread = task.spawn(function()
		while true do
			task.wait(MATCHMAKING_TICK_SECONDS)
			if isCoordinatorLeader then
				local tickets = MatchmakingCoordinator.CollectAllQueueTicketsAsync()
				if #tickets >= TOTAL_MATCH_PLAYERS then
					local lobbies = MatchmakingCoordinator.FormLobbies(tickets)
					for _, lobby in ipairs(lobbies) do
						MatchmakingCoordinator.ProcessLobbyAsync(lobby)
					end
				end
			end
		end
	end)
end

function MatchmakingCoordinator.IsCoordinator(): boolean
	return isCoordinatorLeader
end

--[=[
    Hidden MMR API — server-authoritative decay and metric
]=]
function MatchmakingCoordinator.GetHiddenMMR(userId: number): number
	local record = _hiddenMMR[userId]
	if record then
		return record.value
	end
	-- Default hidden MMR if none stored
	return 1000
end

function MatchmakingCoordinator.SetHiddenMMR(userId: number, mmr: number, timestamp: number?): ()
	if typeof(userId) ~= "number" or typeof(mmr) ~= "number" then
		return
	end
	local now = timestamp or os.time()
	local clamped = math.clamp(math.floor(mmr), HIDDEN_MMR_FLOOR, 5000)
	_hiddenMMR[userId] = { value = clamped, lastUpdated = now }
end

function MatchmakingCoordinator.ApplyHiddenMMRDecay(userId: number, nowTime: number?): number
	local now = nowTime or os.time()
	local record = _hiddenMMR[userId]
	if not record then
		-- Initialize with default and set timestamp to now (no decay yet)
		_hiddenMMR[userId] = { value = 1000, lastUpdated = now }
		return 1000
	end
	local elapsed = now - record.lastUpdated
	if elapsed < HIDDEN_MMR_DECAY_INTERVAL_SECONDS then
		return record.value
	end
	local days = math.floor(elapsed / HIDDEN_MMR_DECAY_INTERVAL_SECONDS)
	local decayAmount = days * HIDDEN_MMR_DECAY_PER_DAY
	local newValue = math.max(HIDDEN_MMR_FLOOR, record.value - decayAmount)
	local actualDecay = record.value - newValue
	if actualDecay > 0 then
		_hiddenMMRDecayMetric.totalDecay += actualDecay
		_hiddenMMRDecayMetric.decayEvents += 1
		_hiddenMMRDecayMetric.lastDecayAmount = actualDecay
		-- Log decay as analytics custom event (cardinality-safe)
		local ok, analytics = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("Analytics"):WaitForChild("AnalyticsWrapper"))
		end)
		if ok and analytics then
			pcall(function()
				local player = game:GetService("Players"):GetPlayerByUserId(userId)
				if player then
					analytics.LogCustomEvent(player, "HiddenMMR_Decay", 1, {
						decayAmount = tostring(actualDecay),
						binnedDecay = analytics.BinValue(actualDecay, { 5, 10, 20, 50 }, { "1-4", "5-9", "10-19", "20-49", "50+" }),
					})
				end
			end)
		end
	end
	record.value = newValue
	record.lastUpdated = now
	return newValue
end

function MatchmakingCoordinator.GetDecayedMMR(userId: number, nowTime: number?): number
	return MatchmakingCoordinator.ApplyHiddenMMRDecay(userId, nowTime)
end

function MatchmakingCoordinator.GetHiddenMMRDecayMetric(): { totalDecay: number, decayEvents: number, lastDecayAmount: number, averageDecay: number }
	local avg = 0
	if _hiddenMMRDecayMetric.decayEvents > 0 then
		avg = _hiddenMMRDecayMetric.totalDecay / _hiddenMMRDecayMetric.decayEvents
	end
	return {
		totalDecay = _hiddenMMRDecayMetric.totalDecay,
		decayEvents = _hiddenMMRDecayMetric.decayEvents,
		lastDecayAmount = _hiddenMMRDecayMetric.lastDecayAmount,
		averageDecay = avg,
	}
end

function MatchmakingCoordinator.ResetHiddenMMRDecayMetric()
	_hiddenMMRDecayMetric.totalDecay = 0
	_hiddenMMRDecayMetric.decayEvents = 0
	_hiddenMMRDecayMetric.lastDecayAmount = 0
end

function MatchmakingCoordinator.ClearHiddenMMR(userId: number)
	_hiddenMMR[userId] = nil
end

function MatchmakingCoordinator.ClearAllHiddenMMR()
	table.clear(_hiddenMMR)
	MatchmakingCoordinator.ResetHiddenMMRDecayMetric()
end

function MatchmakingCoordinator.GetHiddenMMRDecayPerDay(): number
	return HIDDEN_MMR_DECAY_PER_DAY
end


TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage, targetPlaceId, teleportOptions)
	warn(string.format("[MatchmakingCoordinator] TeleportInitFailed for %s: %s", player.Name, tostring(errorMessage)))
	task.spawn(function()
		task.wait(3)
		pcall(function()
			TeleportService:TeleportAsync(targetPlaceId, {player}, teleportOptions)
		end)
	end)
end)

return MatchmakingCoordinator