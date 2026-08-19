--!strict
--[=[ OVERCLOCK: RemoteEvents - Centralized Network Remote Manager ]=]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = {}
local FOLDER_NAME = "Remotes"

local reliableNames = {
	"DamageDealt", "PlayerDeath", "ItemPurchase", "MatchPhaseTransition",
	"ProfileSync", "ReliableCombat", "RoundStateChanged", "RequestPurchase",
	"PurchaseResult", "UseAbility", "AbilityStateUpdate", "SelectAgent",
	"AgentSelectUpdate", "AgentLocked", "ResetRangeStats", "RangeStatsUpdated",
	"SwitchOperative", "SwitchWeapon", "EquipWeapon", "KillFeed",
	"MatchResult", "EnterPracticeRange", "LeavePracticeRange",
	"RequestQueue", "CancelQueue", "QueueUpdate", "EnemyRevealed",
	"AbilityReplicated", "OperativeStateSync", "KillRewardNotice",
	"QueueMatchFound", "QueueStatusUpdate", "MapVoteUpdate",
	"ChallengeSend", "ChallengeReceive", "ChallengeRespond",
	"ChallengeCancel", "ChallengeExpired", "ResupplyAmmo",
	-- Premium cosmetics (server-validated, cosmetic-only)
	"WeaponSkinRequest",
	-- Handoff compatibility (AgentArenaPrototype) — server-authoritative hitscan/projectile
	"RequestFire", "RequestReload", "GameStateChanged",
}

local unreliableNames = {
	"BulletTracer", "WeaponSwaySync", "FootstepSound", "UnreliableCombat",
	-- Handoff visuals
	"ShotVisual", "ImpactVisual",
	-- Bot combat visuals (used by BotActions:FireAllClients)
	"FireWeapon",
	-- FPS movement intent (client -> server, bounded, rate-limited)
	"MovementIntent",
}

local functionNames = {
	"QueueEnter", "QueueLeave", "MapVoteSubmit",
}

local cacheReliable: { [string]: RemoteEvent } = {}
local cacheUnreliable: { [string]: UnreliableRemoteEvent } = {}
local cacheFunctions: { [string]: RemoteFunction } = {}

local folderInstance: Folder? = nil
local folderReliable: Folder? = nil
local folderUnreliable: Folder? = nil
local folderFunctions: Folder? = nil

local function getOrCreateFolders(): (Folder, Folder, Folder, Folder)
	if folderInstance and folderReliable and folderUnreliable and folderFunctions then
		return folderInstance, folderReliable, folderUnreliable, folderFunctions
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

	local remotesDir = networkFolder and networkFolder:FindFirstChild(FOLDER_NAME)
	if not remotesDir then
		if RunService:IsServer() then
			remotesDir = Instance.new("Folder")
			remotesDir.Name = FOLDER_NAME
			remotesDir.Parent = networkFolder
		else
			remotesDir = networkFolder:WaitForChild(FOLDER_NAME, 10) :: Folder
		end
	end
	folderInstance = remotesDir :: Folder

	local function getSubfolder(name: string): Folder
		local existing = remotesDir:FindFirstChild(name)
		if existing and existing:IsA("Folder") then
			return existing
		end
		if RunService:IsServer() then
			local sf = Instance.new("Folder")
			sf.Name = name
			sf.Parent = remotesDir
			return sf
		else
			local sf = remotesDir:WaitForChild(name, 10) :: Folder
			return sf
		end
	end

	folderReliable = getSubfolder("Reliable")
	folderUnreliable = getSubfolder("Unreliable")
	folderFunctions = getSubfolder("Functions")

	return folderInstance :: Folder, folderReliable :: Folder, folderUnreliable :: Folder, folderFunctions :: Folder
end

-- Compatibility shim: handoff expects ReplicatedStorage.Remotes but OVERCLOCK uses Network/Remotes
function RemoteEvents.EnsureLegacyRemotes()
	local legacy = ReplicatedStorage:FindFirstChild("Remotes")
	if not legacy and RunService:IsServer() then
		legacy = Instance.new("Folder")
		legacy.Name = "Remotes"
		legacy.Parent = ReplicatedStorage
	end
	if legacy then
		for _, name in reliableNames do
			if name == "RequestFire" or name == "RequestReload" or name == "GameStateChanged" then
				local existing = legacy:FindFirstChild(name)
				if not existing and RunService:IsServer() then
					local r = Instance.new("RemoteEvent")
					r.Name = name
					r.Parent = legacy
				end
			end
		end
		for _, name in unreliableNames do
			if name == "ShotVisual" or name == "ImpactVisual" then
				local existing = legacy:FindFirstChild(name)
				if not existing and RunService:IsServer() then
					local r = Instance.new("UnreliableRemoteEvent")
					r.Name = name
					r.Parent = legacy
				end
			end
		end
	end
end

function RemoteEvents.Initialize()
	local container, reliableFolder, unreliableFolder, functionsFolder = getOrCreateFolders()
	RemoteEvents.EnsureLegacyRemotes()

	if RunService:IsServer() then
		for _, name in reliableNames do
			local existing = reliableFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not existing or not existing:IsA("RemoteEvent") then
				local r = Instance.new("RemoteEvent")
				r.Name = name
				r.Parent = reliableFolder
				cacheReliable[name] = r
			else
				cacheReliable[name] = existing :: RemoteEvent
			end
		end

		for _, name in unreliableNames do
			local existing = unreliableFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not existing or not existing:IsA("UnreliableRemoteEvent") then
				local r = Instance.new("UnreliableRemoteEvent")
				r.Name = name
				r.Parent = unreliableFolder
				cacheUnreliable[name] = r
			else
				cacheUnreliable[name] = existing :: UnreliableRemoteEvent
			end
		end

		for _, name in functionNames do
			local existing = functionsFolder:FindFirstChild(name) or container:FindFirstChild(name)
			if not existing or not existing:IsA("RemoteFunction") then
				local fn = Instance.new("RemoteFunction")
				fn.Name = name
				fn.Parent = functionsFolder
				cacheFunctions[name] = fn
			else
				cacheFunctions[name] = existing :: RemoteFunction
			end
		end

		print("[NETWORK] All required remotes available")
	else
		for _, name in reliableNames do
			local r = reliableFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if r and r:IsA("RemoteEvent") then cacheReliable[name] = r :: RemoteEvent end
		end
		for _, name in unreliableNames do
			local r = unreliableFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if r and r:IsA("UnreliableRemoteEvent") then cacheUnreliable[name] = r :: UnreliableRemoteEvent end
		end
		for _, name in functionNames do
			local fn = functionsFolder:WaitForChild(name, 15) or container:WaitForChild(name, 5)
			if fn and fn:IsA("RemoteFunction") then cacheFunctions[name] = fn :: RemoteFunction end
		end
	end
end

function RemoteEvents.GetReliable(name: string): RemoteEvent
	if cacheReliable[name] then return cacheReliable[name] end
	local container, reliableFolder, _, _ = getOrCreateFolders()
	local r = reliableFolder:FindFirstChild(name) or (container and container:FindFirstChild(name))
	if r and r:IsA("RemoteEvent") then
		cacheReliable[name] = r :: RemoteEvent
		return r :: RemoteEvent
	end
	if RunService:IsServer() then
		-- Fail-closed: do not auto-create typo remotes; surface error for caller to fix
		warn(`[NETWORK] GetReliable miss for '{name}' — not in reliableNames allowlist`)
		error(`RemoteEvent '{name}' not found! (typo or missing Initialize)`)
	end
	error(`RemoteEvent '{name}' not found!`)
end

function RemoteEvents.GetUnreliable(name: string): UnreliableRemoteEvent
	if cacheUnreliable[name] then return cacheUnreliable[name] end
	local container, _, unreliableFolder, _ = getOrCreateFolders()
	local r = unreliableFolder:FindFirstChild(name) or (container and container:FindFirstChild(name))
	if r and r:IsA("UnreliableRemoteEvent") then
		cacheUnreliable[name] = r :: UnreliableRemoteEvent
		return r :: UnreliableRemoteEvent
	end
	if RunService:IsServer() then
		warn(`[NETWORK] GetUnreliable miss for '{name}'`)
		error(`UnreliableRemoteEvent '{name}' not found! (typo or missing Initialize)`)
	end
	error(`UnreliableRemoteEvent '{name}' not found!`)
end

function RemoteEvents.GetRemoteFunction(name: string): RemoteFunction
	if cacheFunctions[name] then return cacheFunctions[name] end
	local container, _, _, functionsFolder = getOrCreateFolders()
	local fn = functionsFolder:FindFirstChild(name) or (container and container:FindFirstChild(name))
	if fn and fn:IsA("RemoteFunction") then
		cacheFunctions[name] = fn :: RemoteFunction
		return fn :: RemoteFunction
	end
	if RunService:IsServer() then
		warn(`[NETWORK] GetRemoteFunction miss for '{name}'`)
		error(`RemoteFunction '{name}' not found! (typo or missing Initialize)`)
	end
	error(`RemoteFunction '{name}' not found!`)
end

return RemoteEvents
