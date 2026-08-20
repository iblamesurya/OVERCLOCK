--!strict
--[=[ Project OVERCLOCK: ServerMain - Main server entry point ]=]
warn("[BOOT] ServerMain version OVERHAUL_2026_08_04 is running")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local function safeRequire(parent: Instance, childName: string): any
	local child = parent:WaitForChild(childName, 5)
	if not child then
		warn("[BOOT ERROR] Timeout (5s) waiting for module '" .. childName .. "' in " .. parent:GetFullName())
		error("[BOOT FATAL] Missing required module '" .. childName .. "' in " .. parent:GetFullName())
	end
	local success, result = pcall(require, child)
	if not success then
		warn("[BOOT ERROR] Failed to require " .. childName .. ": " .. tostring(result))
		error("[BOOT FATAL] require(" .. childName .. ") failed: " .. tostring(result))
	end
	return result
end

local function safeInit(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		print("[BOOT] " .. name .. " initialized.")
	else
		warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
	end
end

local function safeInitAsync(name: string, fn: () -> ()): thread
	return task.spawn(function()
		local ok, err = pcall(fn)
		if ok then
			print("[BOOT] " .. name .. " initialized.")
		else
			warn("[BOOT ERROR] Failed to initialize " .. name .. ": " .. tostring(err))
		end
	end)
end

-- Per-player rate limiter for high-frequency remotes (spam protection)
local _rateBuckets: { [number]: { [string]: { tokens: number, last: number } } } = {}
local function checkRate(player: Player, key: string, capacity: number, perSec: number): boolean
	local uid = player.UserId
	local buckets = _rateBuckets[uid]
	if not buckets then
		buckets = {}
		_rateBuckets[uid] = buckets
	end
	local b = buckets[key]
	local now = os.clock()
	if not b then
		b = { tokens = capacity, last = now }
		buckets[key] = b
	end
	local elapsed = math.max(0, now - b.last)
	b.tokens = math.min(capacity, b.tokens + elapsed * perSec)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(p)
	_rateBuckets[p.UserId] = nil
end)

Players.CharacterAutoLoads = false

-- ==========================================================
-- STAGE 1: Core Infrastructure & Network Remotes
-- ==========================================================
print("[BOOT] 1/6 Core Infrastructure & Network Remotes")
local NetworkFolder = ReplicatedStorage:WaitForChild("Network", 5)
local RemoteEvents = NetworkFolder and safeRequire(NetworkFolder, "RemoteEvents")
local QueueEvents = NetworkFolder and safeRequire(NetworkFolder, "QueueEvents")
local ChallengeEvents = NetworkFolder and safeRequire(NetworkFolder, "ChallengeEvents")

if RemoteEvents then
	local ok, err = pcall(function()
		RemoteEvents.Initialize()
	end)
	if ok then
		print("[BOOT] RemoteEvents initialized.")
	else
		warn("[BOOT ERROR] Failed to initialize RemoteEvents: " .. tostring(err))
	end
end
if QueueEvents then
	local ok, err = pcall(function()
		QueueEvents.Initialize()
	end)
	if ok then
		print("[BOOT] QueueEvents initialized.")
	else
		warn("[BOOT ERROR] Failed to initialize QueueEvents: " .. tostring(err))
	end
end
if ChallengeEvents then
	local ok, err = pcall(function()
		ChallengeEvents.Initialize()
	end)
	if ok then
		print("[BOOT] ChallengeEvents initialized.")
	else
		warn("[BOOT ERROR] Failed to initialize ChallengeEvents: " .. tostring(err))
	end
end

-- ==========================================================
-- STAGE 2: Data & Core Services
-- ==========================================================
print("[BOOT] 2/6 Data & Core Services")
local ServicesFolder = script.Parent:WaitForChild("Services", 5)
local ProfileServiceWrapper = ServicesFolder and safeRequire(ServicesFolder, "ProfileServiceWrapper")
local ReceiptProcessor = ServicesFolder and safeRequire(ServicesFolder, "ReceiptProcessor")
local SocialInviteService = ServicesFolder and safeRequire(ServicesFolder, "SocialInviteService")
local SpawnService = ServicesFolder and safeRequire(ServicesFolder, "SpawnService")
local BootstrapService = ServicesFolder and safeRequire(ServicesFolder, "BootstrapService")

-- Bootstrap world before any map/combat init (handoff §4) — idempotent
if BootstrapService then
	safeInit("BootstrapService", function()
		BootstrapService.EnsureWorld()
	end)
end
if ReceiptProcessor then
	safeInitAsync("ReceiptProcessor", function()
		ReceiptProcessor.Init()
	end)
end
if SocialInviteService then
	safeInitAsync("SocialInviteService", function()
		SocialInviteService.Init()
	end)
end

-- ==========================================================
-- STAGE 3: Map System & Layout Safety
-- ==========================================================
print("[BOOT] 3/6 Map System & Layout Safety")
local MapFolder = ReplicatedStorage:WaitForChild("Map", 5)
local MapRegistry = MapFolder and safeRequire(MapFolder, "MapRegistry")
local GreyboxArenaMap = MapFolder and safeRequire(MapFolder, "GreyboxArenaMap")
local CommunityArenaMap = MapFolder and safeRequire(MapFolder, "CommunityArenaMap")
local LobbyFolder = MapFolder and safeRequire(MapFolder, "LobbyFolder")
local DuelArenaMap = MapFolder and safeRequire(MapFolder, "DuelArenaMap")
local PracticeRangeMapLayout = MapFolder and safeRequire(MapFolder, "PracticeRangeMapLayout")
local MapSafety = MapFolder and safeRequire(MapFolder, "MapSafety")

if MapRegistry then
	safeInitAsync("MapRegistry", function()
		MapRegistry.AutoRegisterDefaultMaps()
	end)
end
-- PRIMARY COMPETITIVE MAP: NeonSubway replaces old Greybox as the 1v1/2v2 arena (full remodel you asked for)
if NeonSubwayMap then
	safeInit("NeonSubwayMap", function()
		local folder = NeonSubwayMap.BuildMap(Workspace)
		print("[ServerMain] Built NeonSubway Map — PRIMARY ARENA (full remodel).")
		if NeonSubwayMap.GetSpawnPoints and MapSafety then
			local redSpawns = NeonSubwayMap.GetSpawnPoints("Red") or {}
			local blueSpawns = NeonSubwayMap.GetSpawnPoints("Blue") or {}
			local allSpawns = {}
			for _, p in redSpawns do table.insert(allSpawns, p) end
			for _, p in blueSpawns do table.insert(allSpawns, p) end
			MapSafety.assertMapReady(folder, allSpawns)
		end
	end)
end
-- Legacy Greybox kept but hidden when NeonSubway is primary (you see old map only if this runs)
-- if GreyboxArenaMap then ... end -- DISABLED for full remodel
-- Community arena as practice/outpost at 500,100,0 (optional dressing)
if CommunityArenaMap then
	safeInit("CommunityArenaMap", function()
		local folder = CommunityArenaMap.BuildMap(Workspace)
		print("[ServerMain] Built Community Arena Map (good visuals).")
		if CommunityArenaMap.GetSpawnPoints and MapSafety then
			MapSafety.assertMapReady(folder, CommunityArenaMap.GetSpawnPoints())
		end
	end)
end
-- Primitive arena fallback (handoff §4) — always playable even if no external art and if Lobby/Duel fail
local PrototypeArena = MapFolder and safeRequire(MapFolder, "PrototypeArena")
if PrototypeArena and not Workspace:FindFirstChild("CommunityArenaMap") then
	safeInit("PrototypeArena", function()
		local mapFolder, spawnFolder = PrototypeArena.Build()
		print("[ServerMain] Built Primitive Prototype Arena (fallback).")
		if MapSafety and mapFolder then
			-- Validate floor for the two spawn points
			local spawns = {}
			if spawnFolder then
				for _, inst in spawnFolder:GetChildren() do
					if inst:IsA("SpawnLocation") then table.insert(spawns, inst.CFrame) end
				end
			end
			if #spawns > 0 then MapSafety.assertMapReady(mapFolder, spawns) end
		end
	end)
end

if LobbyFolder then
	safeInit("LobbyFolder", function()
		LobbyFolder.BuildLobby(Workspace)
	end)
end

warn("[BOOT] LobbyFolder exists:", Workspace:FindFirstChild("LobbyFolder") ~= nil)
warn("[BOOT] CharacterAutoLoads:", Players.CharacterAutoLoads)

if LobbyFolder then
	local lobbySpawns = LobbyFolder.GetSpawnLocations()
	print("[MAP] Lobby spawn count:", #lobbySpawns)
	for index, spawn in lobbySpawns do
		print(
			("[MAP] Spawn %d: %s | enabled=%s | pos=%s"):format(
				index,
				spawn:GetFullName(),
				tostring(spawn.Enabled),
				tostring(spawn.Position)
			)
		)
	end
	if MapSafety then
		MapSafety.assertMapReady(Workspace:FindFirstChild("LobbyFolder"), lobbySpawns)
	end
end

-- Already built NeonSubway as primary at top of Stage 3 — skip duplicate
do end

if DuelArenaMap then
	safeInitAsync("DuelArenaMap", function()
		if DuelArenaMap.BuildMap then
			local folder = DuelArenaMap.BuildMap(Workspace)
			print("[ServerMain] Built Duel Arena Map.")
			if DuelArenaMap.GetSpawnPoints and MapSafety then
				local redSpawns = DuelArenaMap.GetSpawnPoints("Red") or {}
				local blueSpawns = DuelArenaMap.GetSpawnPoints("Blue") or {}
				local allSpawns = {}
				for _, p in redSpawns do
					table.insert(allSpawns, p)
				end
				for _, p in blueSpawns do
					table.insert(allSpawns, p)
				end
				MapSafety.assertMapReady(folder, allSpawns)
			end
		end
	end)
end

if PracticeRangeMapLayout then
	safeInit("PracticeRangeMapLayout", function()
		if PracticeRangeMapLayout.BuildMap then
			local folder = PracticeRangeMapLayout.BuildMap(Workspace)
			print("[ServerMain] Built Practice Range Map.")
			if PracticeRangeMapLayout.GetSpawnPoints and MapSafety then
				MapSafety.assertMapReady(folder, PracticeRangeMapLayout.GetSpawnPoints())
			end
		end
	end)
end

for _, desc in Workspace:GetDescendants() do
	if desc:IsA("SpawnLocation") then
		local practiceMap = Workspace:FindFirstChild("PracticeRangeMap")
		local isLobby = desc:GetAttribute("LobbySpawnIndex") ~= nil
		local isPractice = desc:GetAttribute("PracticeSpawnIndex") ~= nil
			or desc:GetAttribute("IsPracticeSpawn") == true
			or (practiceMap and desc:IsDescendantOf(practiceMap))
		local isArena = string.find(desc:GetFullName(), "DuelArena") ~= nil
			or string.find(desc:GetFullName(), "GreyboxArena") ~= nil
		local isFallback = desc.Parent == Workspace and desc.Neutral
		if not isLobby and not isPractice and not isArena and not isFallback then
			desc.Enabled = false
		else
			desc.Enabled = true
		end
	end
end

-- Invisible safety baseplate — catches void falls (sized to arena bounds only, lag fix: was 5000×5000 CanCollide=true)
local baseplate = Instance.new("Part")
baseplate.Name = "FallbackBaseplate"
baseplate.Size = Vector3.new(600, 4, 600)
baseplate.Position = Vector3.new(0, 90, 0)
baseplate.Anchored = true
baseplate.Material = Enum.Material.SmoothPlastic
baseplate.Color = Color3.fromRGB(35, 40, 50)
baseplate.Transparency = 1
baseplate.CanCollide = false
baseplate.CanQuery = false
baseplate.CanTouch = false
baseplate.CollisionGroup = "Triggers"
-- Tag for MapSafety to exclude from floor checks
baseplate:SetAttribute("IsFallbackBaseplate", true)
baseplate.Parent = Workspace

-- ==========================================================
-- STAGE 4: Combat & Operative Systems
-- ==========================================================
print("[BOOT] 4/6 Combat & Operative Systems")
local CombatFolder = script.Parent:WaitForChild("Combat", 5)
local CombatServer = CombatFolder and safeRequire(CombatFolder, "CombatServer")
local OperativeService = ServicesFolder and safeRequire(ServicesFolder, "OperativeService")
local BotService = ServicesFolder and safeRequire(ServicesFolder, "BotService")

local combatServerInstance: any = nil
if CombatServer then
	safeInit("CombatServer", function()
		combatServerInstance = CombatServer.new()
		combatServerInstance:InitializeNetworkListeners()
	end)
end

-- Premium cosmetics — server-validated, cosmetic-only (damage/rate/ammo never from client)
local PremiumWeaponSkinService = ServicesFolder and safeRequire(ServicesFolder, "PremiumWeaponSkinService")
local premiumSkinService: any = nil
if PremiumWeaponSkinService then
	safeInit("PremiumWeaponSkinService", function()
		local function ownsSkin(player: Player, skinId: string): boolean
			-- Fallback: only starter skin until PlayerDataService inventory wired; never trust client claims
			return skinId == "ObsidianVector"
		end
		premiumSkinService = PremiumWeaponSkinService.new(ownsSkin)
		local skinRemote = RemoteEvents.GetReliable("WeaponSkinRequest") :: RemoteEvent
		premiumSkinService:Bind(skinRemote)
		print("[BOOT] PremiumWeaponSkinService bound to WeaponSkinRequest")
	end)
end

if OperativeService then
	safeInitAsync("OperativeService", function()
		OperativeService.Init()
	end)
end
if BotService then
	safeInitAsync("BotService", function()
		BotService.Init()
	end)
end

-- ==========================================================
-- STAGE 5: Matchmaking & Round State Machine
-- ==========================================================
print("[BOOT] 5/6 Matchmaking & Round State Machine")
local MatchmakingCoordinator = ServicesFolder and safeRequire(ServicesFolder, "MatchmakingCoordinator")
local QueueMatchmakingService = ServicesFolder and safeRequire(ServicesFolder, "QueueMatchmakingService")
local DirectChallengeService = ServicesFolder and safeRequire(ServicesFolder, "DirectChallengeService")
local RoundService = ServicesFolder and safeRequire(ServicesFolder, "RoundService")
local EconomyService = ServicesFolder and safeRequire(ServicesFolder, "EconomyService")

if MatchmakingCoordinator then
	safeInitAsync("MatchmakingCoordinator", function()
		MatchmakingCoordinator.StartService()
	end)
end
if QueueMatchmakingService then
	safeInitAsync("QueueMatchmakingService", function()
		QueueMatchmakingService.Initialize()
	end)
end
if DirectChallengeService then
	safeInitAsync("DirectChallengeService", function()
		DirectChallengeService.Init()
	end)
end

if RoundService then
	-- CombatServer must be ready before RoundService; Stage 4 is now synchronous so instance is available
	if not combatServerInstance then
		warn("[BOOT ERROR] CombatServer instance missing before RoundService init")
	end
	safeInit("RoundService", function()
		RoundService.Init(combatServerInstance)
		if RoundService.SetCombatServer then
			RoundService.SetCombatServer(combatServerInstance)
		end
	end)
end

if EconomyService then
	safeInitAsync("EconomyService", function()
		EconomyService.Init(RoundService, combatServerInstance)
	end)
end

-- ==========================================================
-- STAGE 6: Setting Up Player Handlers & Single Spawn Authority
-- ==========================================================
print("[BOOT] 6/6 Setting Up Player Handlers & Single Spawn Authority")

if SpawnService then
	safeInit("SpawnService", function()
		SpawnService.Init()
	end)
end

-- Player profiles
local playerProfiles: { [number]: any } = {}

-- Practice Range tracking
local practiceRangePlayers: { [number]: boolean } = {}

local function onPlayerAdded(player: Player)
	DirectChallengeService.SetPlayerStatus(player, "In Lobby")

	task.spawn(function()
		local profile = ProfileServiceWrapper.LoadProfileAsync(player.UserId)
		if not profile then
			warn("[BOOT] Profile load failed for " .. player.Name .. ", using fallback.")
			local ok1, defaultData = pcall(function()
				return ProfileServiceWrapper.GetDefaultProfile(player.UserId, player.Name)
			end)
			if ok1 and defaultData then
				local ok2, fallback = pcall(function()
					return ProfileServiceWrapper.CreateInMemoryFallback(player.UserId, defaultData)
				end)
				if ok2 and fallback then
					profile = fallback
				end
			end
		end
		if profile then
			playerProfiles[player.UserId] = profile
			pcall(function()
				ProfileServiceWrapper.RegisterActiveProfile(player.UserId, profile)
			end)
		end
		print("[BOOT] Profile ready for " .. player.Name)
	end)
end

local function onPlayerRemoving(player: Player)
	if combatServerInstance then
		combatServerInstance:UnregisterPlayer(player.UserId)
	end
	practiceRangePlayers[player.UserId] = nil

	local profile = playerProfiles[player.UserId]
	if profile then
		pcall(function()
			if profile.SaveAsync then
				profile:SaveAsync()
			end
			if profile.ReleaseAsync then
				profile:ReleaseAsync()
			end
		end)
		pcall(function()
			ProfileServiceWrapper.UnregisterActiveProfile(player.UserId)
		end)
		playerProfiles[player.UserId] = nil
	end
end

-- 7. Match return + Practice Range remotes
local function returnPlayerToLobby(player: Player)
	practiceRangePlayers[player.UserId] = nil
	player:SetAttribute("IsPracticeRange", nil)
	if DirectChallengeService then
		DirectChallengeService.SetPlayerStatus(player, "In Lobby")
	end
	if combatServerInstance then
		combatServerInstance:RegisterPlayer(player.UserId)
	end
	if SpawnService then
		SpawnService.SpawnPlayer(player, "Lobby")
	end
	pcall(function()
		RemoteEvents.GetReliable("MatchPhaseTransition"):FireClient(player, { phase = "Lobby" })
	end)
end

-- Practice Range spawn helper — must guarantee teleport to PracticeRangeMap @500,100,0 (landscape separated from Lobby@0 and Neon@1000, Community@1500)
local function spawnPlayerInPracticeRange(player: Player): boolean
	-- Map is already built in Stage 3; no on-demand BuildMap here (lag fix)
	local function revertToLobby(reason: string)
		practiceRangePlayers[player.UserId] = nil
		player:SetAttribute("IsPracticeRange", nil)
		if DirectChallengeService then
			DirectChallengeService.SetPlayerStatus(player, "In Lobby")
		end
		if SpawnService then
			SpawnService.SpawnPlayer(player, "Lobby")
		end
		pcall(function()
			RemoteEvents.GetReliable("MatchPhaseTransition"):FireClient(player, { phase = "Lobby" })
		end)
		warn(("[PRACTICE] Reverted %s to Lobby: %s"):format(player.Name, reason))
	end

	-- Verify map exists before committing status — prevents lobby-with-gun desync
	if not Workspace:FindFirstChild("PracticeRangeMap") then
		revertToLobby("PracticeRangeMap missing")
		return false
	end

	practiceRangePlayers[player.UserId] = true
	player:SetAttribute("IsPracticeRange", true)
	if DirectChallengeService then
		DirectChallengeService.SetPlayerStatus(player, "Practice Range")
	end
	if combatServerInstance and combatServerInstance.SetMatchPhase then
		combatServerInstance:SetMatchPhase("PracticeRange")
	end
	if combatServerInstance then
		combatServerInstance:RegisterPlayer(player.UserId)
	end
	if not SpawnService then
		revertToLobby("SpawnService missing")
		return false
	end
	-- SpawnService now does ForceTeleport(dest) internally; pre-notify not needed
	local spawned = SpawnService.SpawnPlayer(player, "PracticeRange")
	print(("[PRACTICE] SpawnPlayer for %s -> %s"):format(player.Name, tostring(spawned)))
	if not spawned then
		task.wait(0.6)
		spawned = SpawnService.SpawnPlayer(player, "PracticeRange")
		print(("[PRACTICE] Retry SpawnPlayer for %s -> %s"):format(player.Name, tostring(spawned)))
	end
	if not spawned then
		revertToLobby("Spawn busy after retry")
		return false
	end
	-- Verify player actually arrived near 500, not still at lobby 0
	task.delay(0.5, function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - Vector3.new(500, 107, 70)).Magnitude > 300 then
			warn(("[PRACTICE] Post-check %s still far from range (%.1f) — retrying"):format(player.Name, root.Position.Magnitude))
			SpawnService.SpawnPlayer(player, "PracticeRange")
		end
	end)
	return true
end

-- Death remote (rate-limited + In-Match guard: cannot dodge death via lobby return)
pcall(function()
	RemoteEvents.GetReliable("PlayerDeath").OnServerEvent:Connect(function(player: Player, data: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "PlayerDeath", 5, 2) then
			return
		end
		if typeof(data) ~= "table" or data.returnToLobby ~= true then
			return
		end
		-- Disallow lobby return while in active match (prevents death-dodge exploit)
		local roundSvc = ServicesFolder and ServicesFolder:FindFirstChild("RoundService")
		if roundSvc then
			local ok, inMatch = pcall(function()
				local rs = require(roundSvc :: any)
				return rs.IsPlayerInActiveMatch and rs.IsPlayerInActiveMatch(player)
			end)
			if ok and inMatch then
				warn(("[SECURITY] PlayerDeath ReturnToLobby blocked for %s — in active match"):format(player.Name))
				return
			end
		end
		returnPlayerToLobby(player)
	end)
end)

-- Match phase return (rate-limited)
pcall(function()
	RemoteEvents.GetReliable("MatchPhaseTransition").OnServerEvent:Connect(function(player: Player, data: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "MatchPhaseTransition", 5, 2) then
			return
		end
		if typeof(data) == "table" and data.action == "ReturnToLobby" then
			returnPlayerToLobby(player)
		end
	end)
end)

-- Enter Practice Range — only fire PracticeRange phase if spawn succeeded (prevents lobby-with-gun)
pcall(function()
	RemoteEvents.GetReliable("EnterPracticeRange").OnServerEvent:Connect(function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "EnterPracticeRange", 3, 1) then
			return
		end
		if DirectChallengeService and DirectChallengeService.GetPlayerStatus(player) ~= "In Lobby" then
			return
		end
		local ok = spawnPlayerInPracticeRange(player)
		if ok then
			pcall(function()
				RemoteEvents.GetReliable("MatchPhaseTransition"):FireClient(player, { phase = "PracticeRange" })
			end)
			pcall(function()
				if BotService and BotService.OnPlayerEnterRange then
					BotService.OnPlayerEnterRange(player)
				end
			end)
		end
	end)
end)

-- Leave Practice Range (rate-limited, must be in PracticeRange)
pcall(function()
	RemoteEvents.GetReliable("LeavePracticeRange").OnServerEvent:Connect(function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "LeavePracticeRange", 5, 2) then
			return
		end
		if not practiceRangePlayers[player.UserId] then
			return
		end
		pcall(function()
			if BotService and BotService.OnPlayerLeaveRange then
				BotService.OnPlayerLeaveRange(player)
			end
		end)
		returnPlayerToLobby(player)
	end)
end)

-- Queue request
pcall(function()
	RemoteEvents.GetReliable("RequestQueue").OnServerEvent:Connect(function(player: Player, mode: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "RequestQueue", 3, 1) then
			return
		end
		if typeof(mode) ~= "string" or (mode ~= "1v1" and mode ~= "2v2") then
			return
		end
		if DirectChallengeService and DirectChallengeService.GetPlayerStatus(player) ~= "In Lobby" then
			return
		end
		pcall(function()
			QueueMatchmakingService.EnterQueue(player, mode)
		end)
	end)
end)

-- Cancel queue (rate-limited)
pcall(function()
	RemoteEvents.GetReliable("CancelQueue").OnServerEvent:Connect(function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "CancelQueue", 5, 2) then
			return
		end
		pcall(function()
			QueueMatchmakingService.LeaveQueue(player)
		end)
	end)
end)

-- Agent select
pcall(function()
	RemoteEvents.GetReliable("SelectAgent").OnServerEvent:Connect(function(player: Player, operativeId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if typeof(operativeId) ~= "string" or #operativeId == 0 or #operativeId > 50 then
			return
		end
		if not checkRate(player, "SelectAgent", 5, 2) then
			return
		end
		pcall(function()
			if OperativeService and OperativeService.SelectOperative then
				OperativeService.SelectOperative(player, operativeId)
			end
		end)
		-- Broadcast lock
		pcall(function()
			RemoteEvents.GetReliable("AgentLocked")
				:FireAllClients({ operativeId = operativeId, playerId = player.UserId })
		end)
	end)
end)

-- Ability usage
pcall(function()
	RemoteEvents.GetReliable("UseAbility").OnServerEvent:Connect(function(player: Player, data: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "UseAbility", 10, 8) then
			return
		end
		if typeof(data) ~= "table" then
			return
		end
		if
			typeof(data.slot) ~= "string" or (data.slot ~= "Basic" and data.slot ~= "Paid" and data.slot ~= "Ultimate")
		then
			return
		end
		pcall(function()
			if OperativeService and OperativeService.UseAbility then
				OperativeService.UseAbility(player, data.slot, data.targetPosition)
			end
		end)
	end)
end)

-- Weapon switching in practice range
pcall(function()
	RemoteEvents.GetReliable("SwitchWeapon").OnServerEvent:Connect(function(player: Player, weaponId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "SwitchWeapon", 10, 5) then
			return
		end
		if typeof(weaponId) ~= "string" or #weaponId == 0 or #weaponId > 50 then
			return
		end
		if not practiceRangePlayers[player.UserId] then
			return
		end
		pcall(function()
			RemoteEvents.GetReliable("EquipWeapon"):FireClient(player, weaponId)
		end)
	end)
end)

-- Operative switching in practice range
pcall(function()
	RemoteEvents.GetReliable("SwitchOperative").OnServerEvent:Connect(function(player: Player, operativeId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "SwitchOperative", 10, 5) then
			return
		end
		if typeof(operativeId) ~= "string" or #operativeId == 0 or #operativeId > 50 then
			return
		end
		if not practiceRangePlayers[player.UserId] then
			return
		end
		pcall(function()
			if OperativeService and OperativeService.SelectOperative then
				OperativeService.SelectOperative(player, operativeId)
			end
		end)
		pcall(function()
			RemoteEvents.GetReliable("SwitchOperative"):FireClient(player, operativeId)
		end)
	end)
end)

-- Purchase validation
pcall(function()
	RemoteEvents.GetReliable("RequestPurchase").OnServerEvent:Connect(function(player: Player, itemId: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "RequestPurchase", 10, 5) then
			return
		end
		if typeof(itemId) ~= "string" or #itemId == 0 or #itemId > 50 then
			return
		end
		local success, reason, balance = false, "Invalid", 0
		pcall(function()
			if EconomyService and EconomyService.ProcessPurchaseRequest then
				success, reason, balance = EconomyService.ProcessPurchaseRequest(player, itemId)
			end
		end)
		pcall(function()
			RemoteEvents.GetReliable("PurchaseResult"):FireClient(player, {
				success = success,
				reason = reason,
				balance = balance,
				itemId = itemId,
			})
		end)
	end)
end)

-- Reset range stats (rate-limited, practice-only)
pcall(function()
	RemoteEvents.GetReliable("ResetRangeStats").OnServerEvent:Connect(function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player:IsDescendantOf(Players) then
			return
		end
		if not checkRate(player, "ResetRangeStats", 5, 2) then
			return
		end
		if not practiceRangePlayers[player.UserId] then
			return
		end
		pcall(function()
			if BotService and BotService.ResetPlayerStats then
				BotService.ResetPlayerStats(player)
			end
		end)
	end)
end)

-- ProximityPrompt triggers (Lobby gates + Ammo Resupply Station) — production queue via gates
pcall(function()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		if not prompt:IsDescendantOf(Workspace) then
			warn("[SECURITY] PromptTriggered from non-Workspace prompt: " .. prompt:GetFullName())
			return
		end
		if not checkRate(player, "PromptTriggered", 8, 4) then
			return
		end
		local stationType = prompt:GetAttribute("StationType")
			or (prompt.Parent and prompt.Parent:GetAttribute("StationType"))
		if stationType == "AmmoResupply" then
			if not practiceRangePlayers[player.UserId] and (not DirectChallengeService or DirectChallengeService.GetPlayerStatus(player) == "In Lobby") then
				-- Allow ammo resupply only in appropriate context
			end
			pcall(function()
				RemoteEvents.GetReliable("ResupplyAmmo"):FireClient(player)
			end)
			return
		end
		local triggerType = prompt:GetAttribute("TriggerType")
			or (prompt.Parent and prompt.Parent:GetAttribute("TriggerType"))
		if triggerType == "Play" then
			if DirectChallengeService and DirectChallengeService.GetPlayerStatus(player) ~= "In Lobby" then
				return
			end
			if not checkRate(player, "GatePlay", 3, 1) then
				return
			end
			pcall(function()
				QueueMatchmakingService.EnterQueue(player, "1v1")
			end)
		elseif triggerType == "Challenge" then
			if not checkRate(player, "GateChallenge", 3, 1) then
				return
			end
			pcall(function()
				RemoteEvents.GetReliable("ChallengeReceive"):FireClient(player, { action = "OpenChallengeUI" })
			end)
		elseif triggerType == "Loadout" then
			if not checkRate(player, "GateLoadout", 3, 1) then
				return
			end
			pcall(function()
				RemoteEvents.GetReliable("ProfileSync"):FireClient(player, { action = "OpenLoadout" })
			end)
		elseif triggerType == "Settings" then
			if not checkRate(player, "GateSettings", 3, 1) then
				return
			end
			pcall(function()
				RemoteEvents.GetReliable("ProfileSync"):FireClient(player, { action = "OpenSettings" })
			end)
		end
	end)
end)

-- 8. Connect player events
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

print("[BOOT] 6/6 Server ready")
