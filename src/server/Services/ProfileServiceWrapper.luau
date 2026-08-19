--!strict
--[=[
    Project OVERCLOCK: ProfileServiceWrapper
    Provides session-locked DataStore persistence (ProfileService pattern),
    atomic UpdateAsync transactions with exponential backoff retry logic,
    JobId session locking with 60s heartbeat autosave, 30-minute lease deadlock resolution,
    in-memory non-blocking join fallback, and shutdown save (BindToClose).
]=]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

-- Configuration Constants
local DEFAULT_DATASTORE_NAME = "PlayerData_v1"
local HEARTBEAT_INTERVAL_SECONDS = 60
local DEADLOCK_LEASE_TIMEOUT_SECONDS = 1800 -- 30 minutes
local MAX_RETRY_ATTEMPTS = 5
local BASE_RETRY_DELAY_SECONDS = 1

-- Session Lock Data Structure
export type SessionLock = {
	JobId: string,
	SessionId: string,
	Timestamp: number,
}

-- Envelope stored inside Roblox DataStore
export type ProfileEnvelope = {
	Data: { [string]: any },
	Lock: SessionLock?,
	SchemaVersion: number,
	LastSaved: number,
}

-- Internal Profile Interface
export type Profile = {
	UserId: number,
	Data: { [string]: any },
	SessionId: string,
	IsActive: (self: Profile) -> boolean,
	SaveAsync: (self: Profile) -> boolean,
	ReleaseAsync: (self: Profile) -> (),
	OnSessionEnded: {
		Connect: (self: any, callback: () -> ()) -> { Disconnect: (self: any) -> () },
	},
	_active: boolean,
	_lockThread: thread?,
	_bindableEvent: BindableEvent,
}

local ProfileServiceWrapper = {}
ProfileServiceWrapper.__index = ProfileServiceWrapper

-- Data Store Handle
local dataStore: DataStore? = nil

-- Registry of active player profiles for shutdown save handler
local activeProfiles: { [number]: Profile } = {}

local function getDataStore(): DataStore
	if not dataStore then
		dataStore = DataStoreService:GetDataStore(DEFAULT_DATASTORE_NAME)
	end
	return dataStore :: DataStore
end

-- Track active profiles upon load
function ProfileServiceWrapper.RegisterActiveProfile(userId: number, profile: Profile)
	activeProfiles[userId] = profile
end

function ProfileServiceWrapper.UnregisterActiveProfile(userId: number)
	activeProfiles[userId] = nil
end

-- Default profile template containing all required M7 top-level fields and legacy aliases
function ProfileServiceWrapper.GetDefaultProfile(userId: number, username: string?): { [string]: any }
	return {
		userId = userId,
		username = username or ("Player_" .. tostring(userId)),

		-- M7 Required Top-Level Schema Fields
		Level = 1,
		XP = 0,
		Credits = 500,
		OwnedCosmetics = { "DefaultSkin_AR", "DefaultSkin_Pistol" },
		EquippedSkins = {
			["AssaultRifle"] = "DefaultSkin_AR",
			["Sidearm"] = "DefaultSkin_Pistol",
		},
		SelectedOperative = "Vex",
		MatchStats = {
			Kills = 0,
			Deaths = 0,
			Wins = 0,
			Losses = 0,
			Assists = 0,
			Headshots = 0,
			MatchesPlayed = 0,
		},

		-- Supplementary / Backward Compatibility Fields
		level = 1,
		experience = 0,
		rankRating = 1000,
		rankTier = "Bronze I",
		currencies = {
			credits = 500,
			gems = 0,
			eventTokens = 0,
		},
		stats = {
			kills = 0,
			deaths = 0,
			assists = 0,
			wins = 0,
			losses = 0,
			headshots = 0,
			totalDamageDealt = 0,
			playtimeSeconds = 0,
			matchesPlayed = 0,
			accuracyRatio = 0,
		},
		equippedLoadout = {
			primaryWeaponId = "AssaultRifle",
			secondaryWeaponId = "Pistol",
			meleeWeaponId = "Knife_Tactical_01",
			tacticalGadgetId = "Smoke_Grenade",
			lethalGadgetId = "Frag_Grenade",
			perkIds = {},
			weaponSkins = {},
		},
		inventory = {
			["AssaultRifle"] = true,
			["Pistol"] = true,
			["Knife_Tactical_01"] = true,
		},
		unlockedClasses = { "Assault", "Recon" },
		settings = {
			mouseSensitivity = 1.0,
			fov = 90,
			crosshairColor = "#FFFFFF",
			soundVolume = 1.0,
			musicVolume = 0.8,
		},
		schemaVersion = 1,
		lastLoginTimestamp = os.time(),
	}
end

--[=[
    Recursively sanitizes data before writing to DataStore.
    - Strips NaN values (replaces with 0).
    - Converts Vector3 to plain array {x, y, z}.
    - Rejects mixed-type keys (e.g. dictionary with both string and number keys).
    - Rejects cyclic references.
    - Rejects non-serializable Roblox types (Instances, Threads, Functions, Signals).
]=]
function ProfileServiceWrapper.SanitizeData(
	value: any,
	visitedStack: { [any]: boolean }?
): (boolean, any, string?)
	local stack = visitedStack or {}
	local valueType = typeof(value)

	if valueType == "number" then
		-- Strip NaN or Infinite values
		if value ~= value then
			return true, 0, nil
		elseif value == math.huge or value == -math.huge then
			return true, 0, nil
		end
		return true, value, nil
	elseif valueType == "string" or valueType == "boolean" then
		return true, value, nil
	elseif valueType == "Vector3" then
		local vec = value :: Vector3
		return true, { vec.X, vec.Y, vec.Z }, nil
	elseif valueType == "table" then
		local tbl = value :: { [any]: any }

		-- Cyclic reference check
		if stack[tbl] then
			return false, nil, "Cyclic reference detected in table"
		end
		stack[tbl] = true

		local hasStringKeys = false
		local hasNumberKeys = false
		local hasInvalidKeys = false

		for k, _ in pairs(tbl) do
			local kType = typeof(k)
			if kType == "string" then
				hasStringKeys = true
			elseif kType == "number" then
				hasNumberKeys = true
			else
				hasInvalidKeys = true
			end
		end

		if hasInvalidKeys then
			stack[tbl] = nil
			return false, nil, "Invalid key type detected in table"
		end

		-- Mixed-type key rejection
		if hasStringKeys and hasNumberKeys then
			stack[tbl] = nil
			return false, nil, "Mixed-type keys rejected (table has both string and number keys)"
		end

		local sanitizedTable: { [any]: any } = {}
		for k, v in pairs(tbl) do
			local ok, sanitizedVal, err = ProfileServiceWrapper.SanitizeData(v, stack)
			if not ok then
				stack[tbl] = nil
				return false, nil, err
			end
			sanitizedTable[k] = sanitizedVal
		end

		stack[tbl] = nil
		return true, sanitizedTable, nil
	else
		return false, nil, "Non-serializable data type: " .. valueType
	end
end

--[=[
    Creates an in-memory fallback profile object for non-blocking player join when DataStore is unavailable.
]=]
function ProfileServiceWrapper.CreateInMemoryFallback(
	userId: number,
	defaultData: { [string]: any }?
): Profile
	local sessionId = HttpService:GenerateGUID(false)
	local bindable = Instance.new("BindableEvent")
	local rawData = defaultData or ProfileServiceWrapper.GetDefaultProfile(userId)
	local ok, sanitized, _ = ProfileServiceWrapper.SanitizeData(rawData)
	local finalData = if ok then sanitized else rawData

	local selfObj: Profile = {
		UserId = userId,
		Data = finalData,
		SessionId = sessionId,
		_active = true,
		_lockThread = nil,
		_bindableEvent = bindable,

		IsActive = function(p: Profile): boolean
			return p._active
		end,

		SaveAsync = function(_: Profile): boolean
			return true
		end,

		ReleaseAsync = function(p: Profile): ()
			if not p._active then
				return
			end
			p._active = false
			ProfileServiceWrapper.UnregisterActiveProfile(p.UserId)
			p._bindableEvent:Fire()
		end,

		OnSessionEnded = {
			Connect = function(_, callback: () -> ())
				local connection = bindable.Event:Connect(callback)
				return {
					Disconnect = function(_)
						connection:Disconnect()
					end,
				}
			end,
		},
	}

	ProfileServiceWrapper.RegisterActiveProfile(userId, selfObj)
	return selfObj
end

--[=[
    Loads a profile for the given userId with session locking and exponential backoff retry logic.
    Retries up to MAX_RETRY_ATTEMPTS using math.pow(2, attempt - 1) backoff delay.
]=]
function ProfileServiceWrapper.LoadProfileAsync(
	userId: number,
	defaultData: { [string]: any }?
): Profile?
	local key = "Player_" .. tostring(userId)
	local sessionId = HttpService:GenerateGUID(false)
	local currentJobId = game.JobId ~= "" and game.JobId or "Studio_Session"

	local store = getDataStore()
	local loadedEnvelope: ProfileEnvelope? = nil

	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local success, resultErr = pcall(function()
			store:UpdateAsync(key, function(existingValue: any)
				local envelope: ProfileEnvelope
				local now = os.time()

				if existingValue == nil then
					local initialData = defaultData or ProfileServiceWrapper.GetDefaultProfile(userId)
					local ok, sanitized, err = ProfileServiceWrapper.SanitizeData(initialData)
					if not ok then
						error("Failed to sanitize initial default data: " .. tostring(err))
					end

					envelope = {
						Data = sanitized,
						Lock = {
							JobId = currentJobId,
							SessionId = sessionId,
							Timestamp = now,
						},
						SchemaVersion = 1,
						LastSaved = now,
					}
					return envelope
				else
					envelope = existingValue :: ProfileEnvelope

					if envelope.Lock ~= nil then
						local lock = envelope.Lock
						local isOwnLock = (lock.JobId == currentJobId)
						local elapsedSeconds = now - lock.Timestamp

						-- 30-minute lease deadlock resolution
						local isDeadlocked = (elapsedSeconds >= DEADLOCK_LEASE_TIMEOUT_SECONDS)

						if not isOwnLock and not isDeadlocked then
							-- Profile is locked by an active external session. Reject claim.
							return nil
						end
					end

					-- Lock is absent, owned by this server, or deadlock lease expired. Acquire lock!
					local ok, sanitized, err = ProfileServiceWrapper.SanitizeData(envelope.Data)
					if not ok then
						error("Failed to sanitize envelope data: " .. tostring(err))
					end

					envelope.Data = sanitized
					envelope.Lock = {
						JobId = currentJobId,
						SessionId = sessionId,
						Timestamp = now,
					}
					envelope.LastSaved = now
					return envelope
				end
			end)
		end)

		if success then
			-- Verification read to check if we succeeded in acquiring the lock
			local getSuccess, verifyEnvelope = pcall(function()
				return store:GetAsync(key) :: ProfileEnvelope?
			end)

			if getSuccess and verifyEnvelope and verifyEnvelope.Lock and verifyEnvelope.Lock.SessionId == sessionId then
				loadedEnvelope = verifyEnvelope
				break
			end
		else
			local delay = math.min(16, BASE_RETRY_DELAY_SECONDS * math.pow(2, attempt - 1))
			warn(string.format("[ProfileServiceWrapper] Attempt %d/%d failed for userId %d: %s. Retrying in %ds...", 
				attempt, MAX_RETRY_ATTEMPTS, userId, tostring(resultErr), delay))
		end

		if attempt < MAX_RETRY_ATTEMPTS then
			local delay = math.min(16, BASE_RETRY_DELAY_SECONDS * math.pow(2, attempt - 1))
			task.wait(delay)
		end
	end

	if not loadedEnvelope then
		warn("[ProfileServiceWrapper] DataStore unavailable or session lock failed for userId " .. tostring(userId) .. ". Utilizing in-memory fallback profile.")
		return ProfileServiceWrapper.CreateInMemoryFallback(userId, defaultData)
	end

	local Players = game:GetService("Players")
	if not Players:GetPlayerByUserId(userId) then
		warn("[ProfileServiceWrapper] Player disconnected during profile load. Releasing lock for userId " .. tostring(userId))
		ProfileServiceWrapper.ReleaseProfileLock({ UserId = userId, SessionId = sessionId, Data = loadedEnvelope.Data } :: any)
		return nil
	end

	local bindable = Instance.new("BindableEvent")

	local selfObj: Profile = {
		UserId = userId,
		Data = loadedEnvelope.Data,
		SessionId = sessionId,
		_active = true,
		_lockThread = nil,
		_bindableEvent = bindable,

		IsActive = function(p: Profile): boolean
			return p._active
		end,

		SaveAsync = function(p: Profile): boolean
			if not p._active then
				return false
			end
			return ProfileServiceWrapper.SaveProfileData(p)
		end,

		ReleaseAsync = function(p: Profile): ()
			if not p._active then
				return
			end
			p._active = false
			if p._lockThread then
				task.cancel(p._lockThread)
				p._lockThread = nil
			end
			ProfileServiceWrapper.ReleaseProfileLock(p)
			ProfileServiceWrapper.UnregisterActiveProfile(p.UserId)
			p._bindableEvent:Fire()
		end,

		OnSessionEnded = {
			Connect = function(_, callback: () -> ())
				local connection = bindable.Event:Connect(callback)
				return {
					Disconnect = function(_)
						connection:Disconnect()
					end,
				}
			end,
		},
	}

	ProfileServiceWrapper.RegisterActiveProfile(userId, selfObj)

	-- Spawn 60-second Heartbeat Refresh Loop
	selfObj._lockThread = task.spawn(function()
		while selfObj._active do
			task.wait(HEARTBEAT_INTERVAL_SECONDS)
			if not selfObj._active then
				break
			end

			local now = os.time()
			local ok, _ = pcall(function()
				store:UpdateAsync(key, function(current: any)
					if current == nil then
						return nil
					end
					local env = current :: ProfileEnvelope
					if env.Lock == nil or env.Lock.SessionId ~= sessionId then
						error("SESSION_LOCK_MISMATCH")
					end

					local sanitizeOk, sanitizedData, sErr = ProfileServiceWrapper.SanitizeData(selfObj.Data)
					if not sanitizeOk then
						warn("[ProfileServiceWrapper] Heartbeat sanitization warning: " .. tostring(sErr))
						sanitizedData = env.Data
					end

					env.Data = sanitizedData
					env.Lock.Timestamp = now
					env.LastSaved = now
					return env
				end)
			end)

			if not ok then
				warn("[ProfileServiceWrapper] Heartbeat update failed for userId " .. tostring(userId))
			end

			-- Check if lock is still ours
			local checkOk, verifyEnv = pcall(function()
				return store:GetAsync(key) :: ProfileEnvelope?
			end)

			if checkOk and (not verifyEnv or not verifyEnv.Lock or verifyEnv.Lock.SessionId ~= sessionId) then
				warn("[ProfileServiceWrapper] Session lock stolen for userId " .. tostring(userId) .. ". Terminating session.")
				selfObj._active = false
				ProfileServiceWrapper.UnregisterActiveProfile(userId)
				selfObj._bindableEvent:Fire()
				break
			end
		end
	end)

	return selfObj
end

-- Saves profile data atomically to DataStore
function ProfileServiceWrapper.SaveProfileData(profile: Profile): boolean
	local key = "Player_" .. tostring(profile.UserId)
	local store = getDataStore()
	
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(current: any)
			if current == nil then
				return nil
			end
			local env = current :: ProfileEnvelope
			if env.Lock == nil or env.Lock.SessionId ~= profile.SessionId then
				error("SESSION_LOCK_MISMATCH")
			end

			local sanitizeOk, sanitizedData, sErr = ProfileServiceWrapper.SanitizeData(profile.Data)
			if not sanitizeOk then
				error("Sanitization error: " .. tostring(sErr))
			end

			env.Data = sanitizedData
			env.Lock.Timestamp = os.time()
			env.LastSaved = os.time()
			return env
		end)
	end)

	if not ok then
		warn("[ProfileServiceWrapper] SaveProfileData failed: " .. tostring(err))
		return false
	end
	return true
end

-- Releases profile session lock in DataStore
function ProfileServiceWrapper.ReleaseProfileLock(profile: Profile): ()
	local key = "Player_" .. tostring(profile.UserId)
	local store = getDataStore()

	pcall(function()
		store:UpdateAsync(key, function(current: any)
			if current == nil then
				return nil
			end
			local env = current :: ProfileEnvelope
			if env.Lock == nil or env.Lock.SessionId ~= profile.SessionId then
				return nil
			end

			local sanitizeOk, sanitizedData, _ = ProfileServiceWrapper.SanitizeData(profile.Data)
			if sanitizeOk then
				env.Data = sanitizedData
			end

			env.Lock = nil
			env.LastSaved = os.time()
			return env
		end)
	end)
end

-- Register game:BindToClose shutdown flush handler to guarantee data safety on server termination
game:BindToClose(function()
	print("[ProfileServiceWrapper] Server shutting down. Saving all active player profiles...")
	local threads = {}
	for _, profile in pairs(activeProfiles) do
		table.insert(
			threads,
			task.spawn(function()
				pcall(function()
					profile:SaveAsync()
					profile:ReleaseAsync()
				end)
			end)
		)
	end

	local start = os.clock()
	while next(activeProfiles) ~= nil and (os.clock() - start < 10) do
		task.wait(0.1)
	end
	print("[ProfileServiceWrapper] Shutdown save complete.")
end)

return ProfileServiceWrapper
