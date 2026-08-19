--!strict
--[=[
    Project OVERCLOCK v2: DirectChallengeService
    Server-side service managing direct player-to-player 1v1 lobby challenges,
    challenge state machine (Pending, Accepted, Declined, Expired, Canceled),
    15-second auto-expiration timer, status tracking ("In Lobby", "In Queue", "In Match"),
    and duel arena map instantiation & player teleportation upon challenge acceptance.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ChallengeEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("ChallengeEvents") :: any)
local GreyboxArenaMap = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("GreyboxArenaMap") :: any)
local MapRegistry = require(ReplicatedStorage:WaitForChild("Map"):WaitForChild("MapRegistry") :: any)
local SpawnService = require(script.Parent:WaitForChild("SpawnService") :: any)

local CHALLENGE_TIMEOUT_SECONDS = 15

local function waitForCharacterWithTimeout(player: Player, timeout: number): Model?
	if player.Character then
		return player.Character
	end
	local char: Model? = nil
	local thread = coroutine.running()
	local conn: RBXScriptConnection
	local disconnectConn: RBXScriptConnection
	local resolved = false

	local function resolve()
		if resolved then
			return
		end
		resolved = true
		if conn then
			conn:Disconnect()
		end
		if disconnectConn then
			disconnectConn:Disconnect()
		end
		task.spawn(thread)
	end

	conn = player.CharacterAdded:Connect(function(c)
		char = c
		resolve()
	end)
	-- Also handle disconnect
	disconnectConn = game:GetService("Players").PlayerRemoving:Connect(function(p)
		if p == player then
			resolve()
		end
	end)
	task.delay(timeout, function()
		resolve()
	end)
	coroutine.yield()
	return char
end

export type PlayerLobbyStatus = "In Lobby" | "In Queue" | "In Match"

export type ActiveChallenge = {
	challengeId: string,
	challengerUserId: number,
	targetUserId: number,
	state: ChallengeEvents.ChallengeState,
	createdAt: number,
	expiresAt: number,
	expireThread: thread?,
}

local DirectChallengeService = {}

local activeChallenges: { [string]: ActiveChallenge } = {}
local playerChallengeMap: { [number]: string } = {}
local playerStatuses: { [number]: PlayerLobbyStatus } = {}

local isInitialized = false

local function getPlayerInfo(player: Player): ChallengeEvents.PlayerInfo
	return {
		userId = player.UserId,
		username = player.Name,
		displayName = player.DisplayName,
	}
end

--- Returns the current status of a player ("In Lobby", "In Queue", "In Match").
function DirectChallengeService.GetPlayerStatus(player: Player): PlayerLobbyStatus
	return playerStatuses[player.UserId] or "In Lobby"
end

--- Updates the status of a player.
function DirectChallengeService.SetPlayerStatus(player: Player, status: PlayerLobbyStatus)
	playerStatuses[player.UserId] = status
end

--- Retrieves an active challenge record by ID.
function DirectChallengeService.GetChallenge(challengeId: string): ActiveChallenge?
	return activeChallenges[challengeId]
end

--- Retrieves the active challenge ID associated with a player UserId.
function DirectChallengeService.GetActiveChallengeForPlayer(player: Player): ActiveChallenge?
	local challengeId = playerChallengeMap[player.UserId]
	if not challengeId then
		return nil
	end
	return activeChallenges[challengeId]
end

local function cleanupChallenge(challengeId: string)
	local challenge = activeChallenges[challengeId]
	if not challenge then
		return
	end

	if challenge.expireThread then
		task.cancel(challenge.expireThread)
		challenge.expireThread = nil
	end

	playerChallengeMap[challenge.challengerUserId] = nil
	playerChallengeMap[challenge.targetUserId] = nil
	activeChallenges[challengeId] = nil
end

--- Instantiates duel arena map and teleports accepted 1v1 combatants to spawn points.
local function spawnDuelArenaAndTeleport(challenger: Player, targetPlayer: Player)
	DirectChallengeService.SetPlayerStatus(challenger, "In Match")
	DirectChallengeService.SetPlayerStatus(targetPlayer, "In Match")

	local arenaFolder: Folder? = nil
	if MapRegistry.IsMapRegistered("GreyboxArena") then
		arenaFolder = MapRegistry.LoadMapInstance("GreyboxArena", Workspace)
	else
		arenaFolder = GreyboxArenaMap.BuildMap(Workspace)
	end

	if arenaFolder then
		arenaFolder.Name = "DuelArenaInstance_" .. tostring(os.time())
	end

	local redSpawns = GreyboxArenaMap.GetSpawnPoints("Red")
	local blueSpawns = GreyboxArenaMap.GetSpawnPoints("Blue")

	local redPos = if #redSpawns > 0 then redSpawns[1] else Vector3.new(-12, 102, -100)
	local bluePos = if #blueSpawns > 0 then blueSpawns[1] else Vector3.new(12, 102, 100)

	local redCFrame = CFrame.new(redPos + Vector3.new(0, 3, 0))
	local blueCFrame = CFrame.new(bluePos + Vector3.new(0, 3, 0))

	local challengerChar = waitForCharacterWithTimeout(challenger, 10)
	if challengerChar then
		pcall(function()
			return SpawnService.SpawnPlayer(challenger, "Match", redCFrame)
		end)
		SpawnService.SetPlayerLocation(challenger, "Match")
	end

	local targetChar = waitForCharacterWithTimeout(targetPlayer, 10)
	if targetChar then
		pcall(function()
			return SpawnService.SpawnPlayer(targetPlayer, "Match", blueCFrame)
		end)
		SpawnService.SetPlayerLocation(targetPlayer, "Match")
	end

	-- Initialize state machine via RoundService
	local matchId = "Duel_"
		.. tostring(challenger.UserId)
		.. "_"
		.. tostring(targetPlayer.UserId)
		.. "_"
		.. tostring(os.time())
	local servicesFolder = ServerScriptService:FindFirstChild("Services")
	if servicesFolder then
		local rsMod = servicesFolder:FindFirstChild("RoundService")
		if rsMod then
			local RoundService = require(rsMod :: any)
			RoundService.StartMatch(matchId, "1v1", { challenger }, { targetPlayer })
		end
	end
end

--- Sends a direct 1v1 challenge from challenger to target player.
function DirectChallengeService.SendChallenge(challenger: Player, targetPlayer: Player): (boolean, string?)
	if challenger == targetPlayer then
		return false, "Cannot challenge yourself."
	end

	if DirectChallengeService.GetPlayerStatus(challenger) ~= "In Lobby" then
		return false, "You are currently busy."
	end

	if DirectChallengeService.GetPlayerStatus(targetPlayer) ~= "In Lobby" then
		return false, "Target player is currently busy or in a match."
	end

	if playerChallengeMap[challenger.UserId] ~= nil then
		cleanupChallenge(playerChallengeMap[challenger.UserId])
	end

	if playerChallengeMap[targetPlayer.UserId] ~= nil then
		return false, "Target player already has a challenge pending."
	end

	local now = os.time()
	local expiresAt = now + CHALLENGE_TIMEOUT_SECONDS
	local challengeId = "Challenge_"
		.. tostring(challenger.UserId)
		.. "_"
		.. tostring(targetPlayer.UserId)
		.. "_"
		.. tostring(now)

	local challenge: ActiveChallenge = {
		challengeId = challengeId,
		challengerUserId = challenger.UserId,
		targetUserId = targetPlayer.UserId,
		state = "Pending",
		createdAt = now,
		expiresAt = expiresAt,
		expireThread = nil,
	}

	-- Schedule 15-second auto-expiration timer
	challenge.expireThread = task.delay(CHALLENGE_TIMEOUT_SECONDS, function()
		if activeChallenges[challengeId] and activeChallenges[challengeId].state == "Pending" then
			activeChallenges[challengeId].state = "Expired"

			local expiredRemote = ChallengeEvents.GetRemoteEvent("ChallengeExpired")
			local payload: ChallengeEvents.ChallengeExpiredData = {
				challengeId = challengeId,
				challengerUserId = challenger.UserId,
				targetUserId = targetPlayer.UserId,
			}

			local cPlayer = Players:GetPlayerByUserId(challenger.UserId)
			local tPlayer = Players:GetPlayerByUserId(targetPlayer.UserId)

			if cPlayer then
				expiredRemote:FireClient(cPlayer, payload)
			end
			if tPlayer then
				expiredRemote:FireClient(tPlayer, payload)
			end

			cleanupChallenge(challengeId)
		end
	end)

	activeChallenges[challengeId] = challenge
	playerChallengeMap[challenger.UserId] = challengeId
	playerChallengeMap[targetPlayer.UserId] = challengeId

	local requestData: ChallengeEvents.ChallengeRequestData = {
		challengeId = challengeId,
		challenger = getPlayerInfo(challenger),
		target = getPlayerInfo(targetPlayer),
		timestamp = now,
		expiresAt = expiresAt,
	}

	local receiveRemote = ChallengeEvents.GetRemoteEvent("ChallengeReceive")
	receiveRemote:FireClient(targetPlayer, requestData)

	return true, nil
end

--- Responds to a direct 1v1 challenge (Accept / Decline).
function DirectChallengeService.RespondChallenge(
	targetPlayer: Player,
	challengeId: string,
	accept: boolean
): (boolean, string?)
	local challenge = activeChallenges[challengeId]
	if not challenge then
		return false, "Challenge not found or already expired."
	end

	if challenge.targetUserId ~= targetPlayer.UserId then
		return false, "Unauthorized challenge response."
	end

	if challenge.state ~= "Pending" then
		return false, "Challenge is no longer pending."
	end

	local challenger = Players:GetPlayerByUserId(challenge.challengerUserId)
	if not challenger then
		cleanupChallenge(challengeId)
		return false, "Challenger is no longer in the server."
	end

	local now = os.time()
	local responsePayload: ChallengeEvents.ChallengeResponseData = {
		challengeId = challengeId,
		challengerUserId = challenge.challengerUserId,
		targetUserId = targetPlayer.UserId,
		accepted = accept,
		timestamp = now,
	}

	local respondRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")

	if accept then
		challenge.state = "Accepted"
		if challenge.expireThread then
			task.cancel(challenge.expireThread)
			challenge.expireThread = nil
		end
		respondRemote:FireClient(challenger, responsePayload)
		respondRemote:FireClient(targetPlayer, responsePayload)

		spawnDuelArenaAndTeleport(challenger, targetPlayer)
		cleanupChallenge(challengeId)
	else
		challenge.state = "Declined"
		respondRemote:FireClient(challenger, responsePayload)
		respondRemote:FireClient(targetPlayer, responsePayload)
		cleanupChallenge(challengeId)
	end

	return true, nil
end

--- Cancels an outgoing pending 1v1 challenge.
function DirectChallengeService.CancelChallenge(challenger: Player, challengeId: string): (boolean, string?)
	local challenge = activeChallenges[challengeId]
	if not challenge then
		return false, "Challenge not found."
	end

	if challenge.challengerUserId ~= challenger.UserId then
		return false, "Unauthorized challenge cancellation."
	end

	if challenge.state ~= "Pending" then
		return false, "Challenge is no longer pending."
	end

	challenge.state = "Canceled"

	local cancelRemote = ChallengeEvents.GetRemoteEvent("ChallengeCancel")
	local cancelPayload: ChallengeEvents.ChallengeCancelData = {
		challengeId = challengeId,
		challengerUserId = challenger.UserId,
		targetUserId = challenge.targetUserId,
		reason = "Challenger canceled request.",
	}

	local targetPlayer = Players:GetPlayerByUserId(challenge.targetUserId)
	if targetPlayer then
		cancelRemote:FireClient(targetPlayer, cancelPayload)
	end
	cancelRemote:FireClient(challenger, cancelPayload)

	cleanupChallenge(challengeId)
	return true, nil
end

--- Initializes DirectChallengeService remote listeners and player state lifecycle.
-- Simple per-player token bucket for challenge spam
local challengeRateBuckets: { [number]: { tokens: number, last: number } } = {}
local function checkChallengeRateLimit(userId: number): boolean
	local now = os.clock()
	local b = challengeRateBuckets[userId]
	if not b then
		b = { tokens = 3, last = now }
		challengeRateBuckets[userId] = b
	end
	local elapsed = math.max(0, now - b.last)
	b.tokens = math.min(3, b.tokens + elapsed * 1)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function DirectChallengeService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	ChallengeEvents.Initialize()

	local sendRemote = ChallengeEvents.GetRemoteEvent("ChallengeSend")
	sendRemote.OnServerEvent:Connect(function(player: Player, targetUserId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkChallengeRateLimit(player.UserId) then
			return
		end
		if typeof(targetUserId) ~= "number" or targetUserId <= 0 or targetUserId ~= math.floor(targetUserId) then
			return
		end
		if player.UserId == targetUserId then
			return
		end
		if DirectChallengeService.GetPlayerStatus(player) ~= "In Lobby" then
			return
		end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if targetPlayer and targetPlayer:IsDescendantOf(Players) then
			if DirectChallengeService.GetPlayerStatus(targetPlayer) ~= "In Lobby" then
				return
			end
			DirectChallengeService.SendChallenge(player, targetPlayer)
		end
	end)

	local respondRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")
	respondRemote.OnServerEvent:Connect(function(player: Player, challengeId: any, accept: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if
			typeof(challengeId) ~= "string"
			or #challengeId == 0
			or #challengeId > 100
			or typeof(accept) ~= "boolean"
		then
			return
		end

		local challenge = activeChallenges[challengeId]
		if not challenge or challenge.targetUserId ~= player.UserId or challenge.state ~= "Pending" then
			return
		end

		DirectChallengeService.RespondChallenge(player, challengeId, accept)
	end)

	local cancelRemote = ChallengeEvents.GetRemoteEvent("ChallengeCancel")
	cancelRemote.OnServerEvent:Connect(function(player: Player, challengeId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if typeof(challengeId) ~= "string" or #challengeId == 0 or #challengeId > 100 then
			return
		end

		local challenge = activeChallenges[challengeId]
		if not challenge or challenge.challengerUserId ~= player.UserId or challenge.state ~= "Pending" then
			return
		end

		DirectChallengeService.CancelChallenge(player, challengeId)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		playerStatuses[player.UserId] = "In Lobby"
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local challengeId = playerChallengeMap[player.UserId]
		if challengeId then
			local challenge = activeChallenges[challengeId]
			if challenge and challenge.state == "Pending" then
				if challenge.challengerUserId == player.UserId then
					local targetPlayer = Players:GetPlayerByUserId(challenge.targetUserId)
					if targetPlayer then
						local cancelRemote = ChallengeEvents.GetRemoteEvent("ChallengeCancel")
						cancelRemote:FireClient(targetPlayer, {
							challengeId = challengeId,
							challengerUserId = player.UserId,
							targetUserId = challenge.targetUserId,
							reason = "Challenger left the server.",
						})
					end
				else
					local challenger = Players:GetPlayerByUserId(challenge.challengerUserId)
					if challenger then
						local cancelRemote = ChallengeEvents.GetRemoteEvent("ChallengeCancel")
						cancelRemote:FireClient(challenger, {
							challengeId = challengeId,
							challengerUserId = challenge.challengerUserId,
							targetUserId = player.UserId,
							reason = "Target player left the server.",
						})
					end
				end
			end
			cleanupChallenge(challengeId)
		end

		playerStatuses[player.UserId] = nil
	end)
end

return DirectChallengeService
