--!strict
--[=[
    Project OVERCLOCK: SpawnService
    Single Spawn Authority (R2).
    Sole authoritative owner of Player:LoadCharacter(), player.RespawnLocation,
    character:PivotTo(), location state tracking ("Lobby" | "PracticeRange" | "Match"),
    concurrency locking, character death handling, and falling player void rescue.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

export type LocationType = "Lobby" | "PracticeRange" | "Match"

local SpawnService = {}

-- Key Constants
local LOBBY_FALLBACK_CFRAME = CFrame.new(0, 106, 0)
local PRACTICE_RANGE_CFRAME = CFrame.new(500, 105, 60)
local VOID_RESCUE_Y = -200
local LOCK_TIMEOUT_SECONDS = 0.5

-- Internal State Tracking
local playerLocations: { [number]: LocationType } = {}
local customSpawns: { [number]: CFrame } = {}
local spawnLocks: { [number]: number } = {}
local rescueCooldowns: { [number]: boolean } = {}
local respawnRetries: { [number]: number } = {}

-- Lazy-required service references
local _lobbyFolderRef: any = nil
local _practiceRangeLayoutRef: any = nil
local _roundServiceRef: any = nil
local _directChallengeServiceRef: any = nil

local function getLobbyFolder(): any
	if not _lobbyFolderRef then
		local mapFolder = ReplicatedStorage:FindFirstChild("Map")
		if mapFolder then
			local lobbyMod = mapFolder:FindFirstChild("LobbyFolder")
			if lobbyMod then
				_lobbyFolderRef = require(lobbyMod :: any)
			end
		end
	end
	return _lobbyFolderRef
end

local function getPracticeRangeLayout(): any
	if not _practiceRangeLayoutRef then
		local mapFolder = ReplicatedStorage:FindFirstChild("Map")
		if mapFolder then
			local prMod = mapFolder:FindFirstChild("PracticeRangeMapLayout")
			if prMod then
				_practiceRangeLayoutRef = require(prMod :: any)
			end
		end
	end
	return _practiceRangeLayoutRef
end

local function getRoundService(): any
	if not _roundServiceRef then
		local services = ServerScriptService:FindFirstChild("Services")
		if services then
			local rsMod = services:FindFirstChild("RoundService")
			if rsMod then
				_roundServiceRef = require(rsMod :: any)
			end
		end
	end
	return _roundServiceRef
end

local function getDirectChallengeService(): any
	if not _directChallengeServiceRef then
		local services = ServerScriptService:FindFirstChild("Services")
		if services then
			local dcsMod = services:FindFirstChild("DirectChallengeService")
			if dcsMod then
				_directChallengeServiceRef = require(dcsMod :: any)
			end
		end
	end
	return _directChallengeServiceRef
end

--- Get Lobby SpawnLocation object for player
local function getLobbySpawnLocation(player: Player): SpawnLocation?
	local lobbyFolder = getLobbyFolder()
	if lobbyFolder and lobbyFolder.GetSpawnLocations then
		local spawnsList = lobbyFolder.GetSpawnLocations()
		if #spawnsList > 0 then
			return spawnsList[((math.abs(player.UserId) - 1) % #spawnsList) + 1]
		end
	end
	return nil
end

--- Get Practice Range SpawnLocation object
local function getPracticeRangeSpawnLocation(): SpawnLocation?
	local workspaceRef = game:GetService("Workspace")
	local practiceMap = workspaceRef:FindFirstChild("PracticeRangeMap")
	for _, desc in workspaceRef:GetDescendants() do
		if desc:IsA("SpawnLocation") then
			if
				desc:GetAttribute("PracticeSpawnIndex") ~= nil
				or desc:GetAttribute("IsPracticeSpawn") == true
				or (practiceMap and desc:IsDescendantOf(practiceMap))
			then
				return desc
			end
		end
	end
	return nil
end

--- Get Lobby target CFrame
local function getLobbyCFrame(player: Player): CFrame
	local spawn = getLobbySpawnLocation(player)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 5, 0)
	end
	return LOBBY_FALLBACK_CFRAME
end

--- Get Practice Range target CFrame (pure getter — no BuildMap side-effects; map must be built in Stage 3)
local function getPracticeRangeCFrame(player: Player, spawnIndex: number?): CFrame
	local workspaceRef = game:GetService("Workspace")
	local mapFolder = workspaceRef:FindFirstChild("PracticeRangeMap")
	if not mapFolder then
		warn("[SPAWN] PracticeRangeMap not yet built — using fallback position")
	end

	local prLayout = getPracticeRangeLayout()
	if prLayout and prLayout.GetSpawnPoints then
		local spawns = prLayout.GetSpawnPoints()
		if spawns and #spawns > 0 then
			-- Cycle spawn per player to spread out (3 spawns available)
			local idx = spawnIndex or ((math.abs(player.UserId) % #spawns) + 1)
			if idx < 1 or idx > #spawns then
				idx = 1
			end
			local pos = spawns[idx]
			if typeof(pos) == "Vector3" then
				-- 5 studs above floor to avoid clipping into pad
				return CFrame.new(pos + Vector3.new(0, 5, 0))
			elseif typeof(pos) == "CFrame" then
				return (pos :: CFrame) + Vector3.new(0, 5, 0)
			end
		end
	end
	-- Fallback still inside the map bounds (pre-offset + MAP_OFFSET)
	warn("[SPAWN] PracticeRange spawns missing, using fallback " .. tostring(PRACTICE_RANGE_CFRAME))
	return PRACTICE_RANGE_CFRAME
end

--- Determines appropriate CFrame for destination type
local function getDestinationCFrame(
	player: Player,
	destinationType: LocationType,
	customCFrame: CFrame?,
	spawnIndex: number?
): CFrame
	if customCFrame then
		return customCFrame
	end
	if destinationType == "Match" then
		return customSpawns[player.UserId] or getLobbyCFrame(player)
	elseif destinationType == "PracticeRange" then
		return getPracticeRangeCFrame(player, spawnIndex)
	else
		return getLobbyCFrame(player)
	end
end

--- Updates player's location state
function SpawnService.SetPlayerLocation(player: Player, location: LocationType)
	playerLocations[player.UserId] = location
end

--- Gets player's current location state
function SpawnService.GetPlayerLocation(player: Player): LocationType
	return playerLocations[player.UserId] or "Lobby"
end

--- Teleports existing character model to target CFrame safely (with anti-rubber-band notify)
function SpawnService.TeleportCharacter(player: Player, cframe: CFrame): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	-- Prevent MovementValidator rubber-band on large teleports
	pcall(function()
		local mv = ServerScriptService:FindFirstChild("Combat")
		if mv then
			local mod = mv:FindFirstChild("MovementAuthority")
			if mod then require(mod :: any).NotifyActiveTeleport(player) end
		end
	end)
	character:PivotTo(cframe)
	return true
end

-- Single global Heartbeat for all void rescues (lag fix: was N Heartbeats, now 1)
local trackedRescueChars: { [number]: Model } = {}
local globalRescueConn: RBXScriptConnection? = nil

local function ensureGlobalVoidRescue()
	if globalRescueConn then return end
	local RunService = game:GetService("RunService")
	globalRescueConn = RunService.Heartbeat:Connect(function()
		for uid, char in trackedRescueChars do
			if not char.Parent then
				trackedRescueChars[uid] = nil
				continue
			end
			local player = Players:GetPlayerByUserId(uid)
			if not player or not player.Parent then
				trackedRescueChars[uid] = nil
				continue
			end
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then continue end
			if root.Position.Y < VOID_RESCUE_Y and not rescueCooldowns[uid] then
				rescueCooldowns[uid] = true
				local loc = SpawnService.GetPlayerLocation(player)
				local workspaceRef = game:GetService("Workspace")

				if loc == "PracticeRange" and not workspaceRef:FindFirstChild("PracticeRangeMap") then
					warn(("[VOID] Rescue target map PracticeRange missing for %s! Rescuing to Lobby."):format(player.Name))
					playerLocations[uid] = "Lobby"
					loc = "Lobby"
				end

				local destCFrame = getDestinationCFrame(player, loc, customSpawns[uid])

				if loc == "PracticeRange" and not workspaceRef:FindFirstChild("PracticeRangeMap") then
					destCFrame = getLobbyCFrame(player)
					playerLocations[uid] = "Lobby"
					loc = "Lobby"
				end

				warn(("[VOID] Rescuing %s from Y=%.1f to %s at %s"):format(player.Name, root.Position.Y, loc, tostring(destCFrame.Position)))

				if char.Parent and root.Parent then
					-- Also notify MovementValidator to avoid rubber-band on rescue teleport
					pcall(function()
						local mv = ServerScriptService:FindFirstChild("Combat")
						if mv then
							local mod = mv:FindFirstChild("MovementValidator")
							if mod then require(mod :: any).NotifyTeleport(player) end
						end
					end)
					char:PivotTo(destCFrame)
				end
				task.delay(2, function()
					rescueCooldowns[uid] = nil
				end)
			end
		end
	end)
end

--- Attaches void rescue safety net to player character (global Heartbeat)
function SpawnService.AttachVoidRescue(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	ensureGlobalVoidRescue()
	trackedRescueChars[player.UserId] = character
	local conn: RBXScriptConnection? = nil

	-- Replace monitoring when character respawns
	conn = player.CharacterAdded:Connect(function(newChar)
		trackedRescueChars[player.UserId] = newChar
		SpawnService.AttachVoidRescue(player, newChar)
	end)

	local function cleanup()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		trackedRescueChars[player.UserId] = nil
	end

	-- Cleanup when character removed or player leaves
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup()
		end
	end)
	player.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup()
		end
	end)
end

--- Authoritative character spawn entry point (supports both : and . call syntax; prefer . )
function SpawnService.SpawnPlayer(
	selfOrPlayer: any,
	destinationTypeOrMode: any,
	customCFrameOrIndex: any
): (boolean, CFrame)
	local player: Player
	local modeStr: LocationType = "Lobby"
	local customCFrame: CFrame? = nil
	local spawnIndex: number? = nil

	-- Canonicalize overload: SpawnService:SpawnPlayer(player, mode) vs SpawnService.SpawnPlayer(player, mode, cframe/index)
	local isMethodCall = typeof(selfOrPlayer) == "table" and selfOrPlayer == SpawnService
	if isMethodCall then
		if typeof(destinationTypeOrMode) ~= "Instance" or not (destinationTypeOrMode :: any):IsA("Player") then
			error("[SPAWN] SpawnPlayer method call requires player as second argument")
		end
		player = destinationTypeOrMode :: Player
		local rawMode = customCFrameOrIndex
		if rawMode == "PracticeRange" or rawMode == "Practice" then
			modeStr = "PracticeRange"
		elseif rawMode == "Match" then
			modeStr = "Match"
		else
			modeStr = "Lobby"
		end
	else
		if typeof(selfOrPlayer) ~= "Instance" or not (selfOrPlayer :: any):IsA("Player") then
			error("[SPAWN] SpawnPlayer requires Player as first argument")
		end
		player = selfOrPlayer :: Player
		local rawMode = destinationTypeOrMode
		if rawMode == "PracticeRange" or rawMode == "Practice" then
			modeStr = "PracticeRange"
		elseif rawMode == "Match" then
			modeStr = "Match"
		else
			modeStr = "Lobby"
		end
		if typeof(customCFrameOrIndex) == "CFrame" then
			customCFrame = customCFrameOrIndex
		elseif typeof(customCFrameOrIndex) == "number" then
			spawnIndex = customCFrameOrIndex
		elseif customCFrameOrIndex ~= nil then
			warn("[SPAWN] Unexpected third argument type: " .. typeof(customCFrameOrIndex))
		end
	end

	local userId = player.UserId
	if not player.Parent then
		warn("[SPAWN] Spawn requested for player not in game: " .. tostring(player))
		return false, getDestinationCFrame(player, modeStr, customCFrame, spawnIndex)
	end

	-- Concurrency mutex with tick timestamp — stale-safe
	local lockKey = userId
	local existing = spawnLocks[lockKey]
	if existing then
		-- If lock older than 5s, treat as stale and clear
		if type(existing) == "number" and os.clock() - existing > 5 then
			warn("[SPAWN] Stale lock auto-cleared for " .. player.Name)
			spawnLocks[lockKey] = nil
		else
			local waited = 0
			while spawnLocks[lockKey] and waited < 1.2 do
				task.wait(0.05)
				waited += 0.05
			end
			if spawnLocks[lockKey] then
				warn(("[SPAWN] Spawn rejected for %s — busy (waited %.1fs)"):format(player.Name, waited))
				return false, getDestinationCFrame(player, modeStr, customCFrame, spawnIndex)
			end
		end
	end
	local startTick = os.clock()
	spawnLocks[lockKey] = startTick
	task.delay(5, function()
		if spawnLocks[lockKey] == startTick then
			warn("[SPAWN] Stale lock auto-released for userId " .. tostring(userId))
			spawnLocks[lockKey] = nil
		end
	end)

	-- Update state tracking
	playerLocations[userId] = modeStr
	if customCFrame then
		customSpawns[userId] = customCFrame
	end

	local destCFrame = getDestinationCFrame(player, modeStr, customCFrame, spawnIndex)

	-- Notify movement authority before 500-stud teleport (prevents false correction) — authority + fallback validator
	pcall(function()
		local mv = ServerScriptService:FindFirstChild("Combat")
		if mv then
			local modAuth = mv:FindFirstChild("MovementAuthority")
			if modAuth then require(modAuth :: any).NotifyActiveTeleport(player) end
			local mod = mv:FindFirstChild("MovementValidator")
			if mod then
				local m = require(mod :: any)
				if m.ForceTeleport then
					m.ForceTeleport(player, destCFrame.Position)
				else
					m.NotifyTeleport(player)
				end
			end
		end
	end)

	-- Configure Roblox RespawnLocation to match designated SpawnLocation
	if modeStr == "Lobby" then
		local spawnObj = getLobbySpawnLocation(player)
		if spawnObj then
			player.RespawnLocation = spawnObj
		end
	elseif modeStr == "PracticeRange" then
		local spawnObj = getPracticeRangeSpawnLocation()
		if spawnObj then
			player.RespawnLocation = spawnObj
		end
	else
		player.RespawnLocation = nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- If character is already alive, TELEPORT directly using PivotTo without destroying via LoadCharacter
	if character and humanoid and humanoid.Health > 0 and root and character.Parent == game:GetService("Workspace") then
		character:PivotTo(destCFrame)
		pcall(function()
			local mv = ServerScriptService:FindFirstChild("Combat")
			if mv then
				local modAuth = mv:FindFirstChild("MovementAuthority")
				if modAuth then require(modAuth :: any).NotifyActiveTeleport(player) end
				local mod = mv:FindFirstChild("MovementValidator")
				if mod then
					local m = require(mod :: any)
					if m.ForceTeleport then m.ForceTeleport(player, destCFrame.Position) end
				end
			end
		end)
		task.defer(function()
			if character and character.Parent then
				character:PivotTo(destCFrame)
				pcall(function()
					local mv = ServerScriptService:FindFirstChild("Combat")
					if mv then
						local mod = mv:FindFirstChild("MovementValidator")
						if mod then
							local m = require(mod :: any)
							if m.ForceTeleport then m.ForceTeleport(player, destCFrame.Position) end
						end
					end
				end)
			end
		end)
		print(
			("[SPAWN] Teleported alive player %s -> %s at %.1f, %.1f, %.1f"):format(
				player.Name,
				modeStr,
				destCFrame.Position.X,
				destCFrame.Position.Y,
				destCFrame.Position.Z
			)
		)
		spawnLocks[userId] = nil
		return true, destCFrame
	end

	-- Otherwise, LoadCharacter is required (robust: retry PivotTo even if HumanoidRootPart delayed)
	player:LoadCharacter()
	character = player.Character or player.CharacterAdded:Wait()
	-- Wait for HumanoidRootPart with longer timeout and fallback to any PrimaryPart
	local loadedRoot = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not loadedRoot then
		loadedRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart? or character.PrimaryPart :: BasePart?
	end
	-- Always attempt PivotTo even if root not yet found, with retries
	local function doPivot()
		if character and character.Parent == workspace then
			pcall(function() character:PivotTo(destCFrame) end)
			pcall(function()
				local mv = ServerScriptService:FindFirstChild("Combat")
				if mv then
					local modAuth = mv:FindFirstChild("MovementAuthority")
					if modAuth then require(modAuth :: any).NotifyActiveTeleport(player) end
					local mod = mv:FindFirstChild("MovementValidator")
					if mod then
						local m = require(mod :: any)
						if m.ForceTeleport then m.ForceTeleport(player, destCFrame.Position) end
					end
				end
			end)
		end
	end
	doPivot()
	task.defer(doPivot)
	task.delay(0.1, doPivot)
	task.delay(0.3, doPivot)
	if loadedRoot then
		print(
			("[SPAWN] Loaded character for player %s -> %s at %.1f, %.1f, %.1f"):format(
				player.Name,
				modeStr,
				destCFrame.Position.X,
				destCFrame.Position.Y,
				destCFrame.Position.Z
			)
		)
	else
		warn(("[SPAWN] HumanoidRootPart missing for %s, retried PivotTo to %s"):format(player.Name, tostring(destCFrame.Position)))
	end

	SpawnService.AttachVoidRescue(player, character)

	spawnLocks[userId] = nil

	return true, destCFrame
end

--- Handles character death and respawning rules
function SpawnService.HandleCharacterRespawn(player: Player)
	local dcs = getDirectChallengeService()
	local rs = getRoundService()

	local status = if dcs then dcs.GetPlayerStatus(player) else "In Lobby"
	local inActiveMatch = rs and rs.IsPlayerInActiveMatch and rs.IsPlayerInActiveMatch(player)

	if status == "In Match" or inActiveMatch then
		-- In PvP match: mid-round respawn handled by RoundService (spectate)
		pcall(function()
			if rs and rs.OnPlayerDied then
				rs.OnPlayerDied(player, nil)
			end
		end)
	else
		-- Non-match (Lobby / PracticeRange): auto-respawn after delay
		local retries = respawnRetries[player.UserId] or 0
		if retries >= 3 then
			SpawnService.SpawnPlayer(player, "Lobby")
			respawnRetries[player.UserId] = 0
			return
		end
		respawnRetries[player.UserId] = retries + 1

		task.wait(2)
		if player.Parent == Players then
			local currentLocation = SpawnService.GetPlayerLocation(player)
			SpawnService.SpawnPlayer(player, currentLocation)
			respawnRetries[player.UserId] = 0
		end
	end
end

local function applySpawnProtection(player: Player, character: Model)
	-- Handoff §6.1: Lobby → SpawnProtected (ForceField, 3s) → Playing, RespawnTime 6s
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end
	humanoid.MaxHealth = 100
	humanoid.BreakJointsOnDeath = false
	player:SetAttribute("PlayerState", "SpawnProtected")
	local ff = Instance.new("ForceField")
	ff.Name = "SpawnProtection"
	ff.Visible = false
	ff.Parent = character
	task.delay(3, function()
		if player.Character ~= character or not humanoid or humanoid.Health <= 0 then return end
		if ff.Parent then ff:Destroy() end
		if player:GetAttribute("PlayerState") == "SpawnProtected" then
			player:SetAttribute("PlayerState", "Playing")
		end
	end)
	humanoid.Died:Connect(function()
		player:SetAttribute("PlayerState", "Dead")
	end)
end

--- Called on PlayerAdded
function SpawnService.OnPlayerAdded(player: Player)
	playerLocations[player.UserId] = "Lobby"
	player:SetAttribute("PlayerState", "Lobby")
	-- Server authoritative RespawnTime per handoff
	pcall(function() Players.RespawnTime = 6 end)

	player.CharacterAdded:Connect(function(character)
		applySpawnProtection(player, character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			-- HandleCharacterRespawn already wired via Died above; keep single path
			humanoid.Died:Connect(function()
				-- Duplicate guard: applySpawnProtection already sets Dead, this ensures respawn logic
				SpawnService.HandleCharacterRespawn(player)
			end)
		end
	end)

	SpawnService.SpawnPlayer(player, "Lobby")
end

--- Called on PlayerRemoving
function SpawnService.OnPlayerRemoving(player: Player)
	playerLocations[player.UserId] = nil
	customSpawns[player.UserId] = nil
	spawnLocks[player.UserId] = nil
	rescueCooldowns[player.UserId] = nil
	respawnRetries[player.UserId] = nil
	pcall(function() player:SetAttribute("PlayerState", nil) end)
end

--- Initialize SpawnService
function SpawnService.Init()
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		SpawnService.OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SpawnService.OnPlayerRemoving(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			SpawnService.OnPlayerAdded(player)
		end)
	end

	print("[SpawnService] Initialized as Single Spawn Authority.")
end

return SpawnService
