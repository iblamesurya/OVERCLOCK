--!strict
--[=[
    Project OVERCLOCK v2: ChallengeEvents Network Module
    Defines and initializes reliable RemoteEvents for direct player-to-player 1v1 challenges
    (ChallengeSend, ChallengeReceive, ChallengeRespond, ChallengeCancel, ChallengeExpired).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ChallengeState = "Pending" | "Accepted" | "Declined" | "Expired" | "Canceled"

export type PlayerInfo = {
	userId: number,
	username: string,
	displayName: string,
}

export type ChallengeRequestData = {
	challengeId: string,
	challenger: PlayerInfo,
	target: PlayerInfo,
	timestamp: number,
	expiresAt: number,
}

export type ChallengeResponseData = {
	challengeId: string,
	challengerUserId: number,
	targetUserId: number,
	accepted: boolean,
	timestamp: number,
}

export type ChallengeCancelData = {
	challengeId: string,
	challengerUserId: number,
	targetUserId: number,
	reason: string?,
}

export type ChallengeExpiredData = {
	challengeId: string,
	challengerUserId: number,
	targetUserId: number,
}

export type ChallengeEventName =
	"ChallengeSend"
	| "ChallengeReceive"
	| "ChallengeRespond"
	| "ChallengeCancel"
	| "ChallengeExpired"

local ChallengeEvents = {}

local remoteEventsCache: { [string]: RemoteEvent } = {}
local remotesFolder: Folder? = nil
local reliableFolder: Folder? = nil

local RELIABLE_EVENT_NAMES: { ChallengeEventName } = {
	"ChallengeSend",
	"ChallengeReceive",
	"ChallengeRespond",
	"ChallengeCancel",
	"ChallengeExpired",
}

local function getOrCreateFolders(): (Folder, Folder)
	if remotesFolder and reliableFolder then
		return remotesFolder, reliableFolder
	end

	local networkFolder = ReplicatedStorage:FindFirstChild("Network")
	if not networkFolder then
		if RunService:IsServer() then
			networkFolder = Instance.new("Folder")
			networkFolder.Name = "Network"
			networkFolder.Parent = ReplicatedStorage
		else
			networkFolder = ReplicatedStorage:WaitForChild("Network", 10)
		end
	end

	if not networkFolder then
		error("[Network] Failed to find Network folder in ReplicatedStorage within timeout")
	end

	local remDir = networkFolder and networkFolder:FindFirstChild("Remotes")
	if not remDir then
		if RunService:IsServer() then
			remDir = Instance.new("Folder")
			remDir.Name = "Remotes"
			remDir.Parent = networkFolder
		else
			remDir = networkFolder:WaitForChild("Remotes", 10) :: Folder
		end
	end
	remotesFolder = remDir :: Folder

	local existingRel = remDir:FindFirstChild("Reliable")
	if existingRel and existingRel:IsA("Folder") then
		reliableFolder = existingRel
	elseif RunService:IsServer() then
		local sf = Instance.new("Folder")
		sf.Name = "Reliable"
		sf.Parent = remDir
		reliableFolder = sf
	else
		reliableFolder = remDir:WaitForChild("Reliable", 10) :: Folder
	end

	return remotesFolder :: Folder, reliableFolder :: Folder
end

--- Initializes all challenge RemoteEvent channels.
function ChallengeEvents.Initialize()
	local container, relFolder = getOrCreateFolders()

	if RunService:IsServer() then
		for _, name in ipairs(RELIABLE_EVENT_NAMES) do
			local remote = relFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not remote or not remote:IsA("RemoteEvent") then
				local newRemote = Instance.new("RemoteEvent")
				newRemote.Name = name
				newRemote.Parent = relFolder
				remoteEventsCache[name] = newRemote
			else
				remoteEventsCache[name] = remote :: RemoteEvent
			end
		end
	else
		for _, name in ipairs(RELIABLE_EVENT_NAMES) do
			local remote = relFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if remote and remote:IsA("RemoteEvent") then
				remoteEventsCache[name] = remote :: RemoteEvent
			end
		end
	end
end

--- Returns a cached RemoteEvent channel by name.
function ChallengeEvents.GetRemoteEvent(name: ChallengeEventName): RemoteEvent
	if remoteEventsCache[name] then
		return remoteEventsCache[name]
	end

	local container, relFolder = getOrCreateFolders()
	local remote = relFolder:FindFirstChild(name) or container:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		remoteEventsCache[name] = remote :: RemoteEvent
		return remote :: RemoteEvent
	end

	if RunService:IsServer() then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = relFolder
		remoteEventsCache[name] = newRemote
		return newRemote
	end

	error("[ChallengeEvents] RemoteEvent '" .. tostring(name) .. "' not found!")
end

return ChallengeEvents
