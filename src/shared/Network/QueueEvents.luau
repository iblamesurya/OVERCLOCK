--!strict
--[=[
    Project OVERCLOCK v2: QueueEvents Network Module
    Defines and initializes reliable RemoteEvents and RemoteFunctions for queue management,
    player matchmaking, map voting, and match found notifications.
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type QueueMode = "1v1" | "2v2"

export type PlayerInfo = {
	userId: number,
	username: string,
	displayName: string,
}

export type QueueStatusData = {
	inQueue: boolean,
	mode: QueueMode?,
	queueTimeSeconds: number,
	playersInQueue: number,
}

export type MatchFoundData = {
	matchId: string,
	mode: QueueMode,
	teamId: number,
	teammates: { PlayerInfo },
	opponents: { PlayerInfo },
	votingDurationSeconds: number,
	availableMaps: { string },
}

export type MapVoteData = {
	matchId: string,
	mapName: string,
}

export type MapVoteResult = {
	matchId: string,
	mapVotes: { [string]: number },
	winningMap: string?,
	votingEnded: boolean,
}

local QueueEvents = {}

local remoteEventsCache: { [string]: RemoteEvent } = {}
local remoteFunctionsCache: { [string]: RemoteFunction } = {}
local remotesFolder: Folder? = nil
local reliableFolder: Folder? = nil
local functionsFolder: Folder? = nil

local RELIABLE_EVENT_NAMES = {
	"QueueMatchFound",
	"QueueStatusUpdate",
	"MapVoteUpdate",
}

local REMOTE_FUNCTION_NAMES = {
	"QueueEnter",
	"QueueLeave",
	"MapVoteSubmit",
}

local function getOrCreateFolders(): (Folder, Folder, Folder)
	if remotesFolder and reliableFolder and functionsFolder then
		return remotesFolder, reliableFolder, functionsFolder
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

	local function getSubfolder(name: string): Folder
		local existing = remDir:FindFirstChild(name)
		if existing and existing:IsA("Folder") then
			return existing
		end
		if RunService:IsServer() then
			local sf = Instance.new("Folder")
			sf.Name = name
			sf.Parent = remDir
			return sf
		else
			local sf = remDir:WaitForChild(name, 10) :: Folder
			return sf
		end
	end

	reliableFolder = getSubfolder("Reliable")
	functionsFolder = getSubfolder("Functions")

	return remotesFolder :: Folder, reliableFolder :: Folder, functionsFolder :: Folder
end

--- Initializes all queue RemoteEvent and RemoteFunction channels.
function QueueEvents.Initialize()
	local container, relFolder, fnFolder = getOrCreateFolders()

	if RunService:IsServer() then
		for _, name in ipairs(RELIABLE_EVENT_NAMES) do
			local existing = relFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not existing or not existing:IsA("RemoteEvent") then
				local newRemote = Instance.new("RemoteEvent")
				newRemote.Name = name
				newRemote.Parent = relFolder
				remoteEventsCache[name] = newRemote
			else
				remoteEventsCache[name] = existing :: RemoteEvent
			end
		end

		for _, name in ipairs(REMOTE_FUNCTION_NAMES) do
			local existing = fnFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not existing or not existing:IsA("RemoteFunction") then
				local newFn = Instance.new("RemoteFunction")
				newFn.Name = name
				newFn.Parent = fnFolder
				remoteFunctionsCache[name] = newFn
			else
				remoteFunctionsCache[name] = existing :: RemoteFunction
			end
		end
	else
		for _, name in ipairs(RELIABLE_EVENT_NAMES) do
			local remote = relFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if remote and remote:IsA("RemoteEvent") then
				remoteEventsCache[name] = remote :: RemoteEvent
			end
		end

		for _, name in ipairs(REMOTE_FUNCTION_NAMES) do
			local fn = fnFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if fn and fn:IsA("RemoteFunction") then
				remoteFunctionsCache[name] = fn :: RemoteFunction
			end
		end
	end
end

--- Returns a cached RemoteEvent channel by name.
function QueueEvents.GetRemoteEvent(name: string): RemoteEvent
	if remoteEventsCache[name] then
		return remoteEventsCache[name]
	end

	local container, relFolder, _ = getOrCreateFolders()
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

	error("[QueueEvents] RemoteEvent '" .. name .. "' not found!")
end

--- Returns a cached RemoteFunction channel by name.
function QueueEvents.GetRemoteFunction(name: string): RemoteFunction
	if remoteFunctionsCache[name] then
		return remoteFunctionsCache[name]
	end

	local container, _, fnFolder = getOrCreateFolders()
	local fn = fnFolder:FindFirstChild(name) or container:FindFirstChild(name)
	if fn and fn:IsA("RemoteFunction") then
		remoteFunctionsCache[name] = fn :: RemoteFunction
		return fn :: RemoteFunction
	end

	if RunService:IsServer() then
		local newFn = Instance.new("RemoteFunction")
		newFn.Name = name
		newFn.Parent = fnFolder
		remoteFunctionsCache[name] = newFn
		return newFn
	end

	error("[QueueEvents] RemoteFunction '" .. name .. "' not found!")
end

return QueueEvents
