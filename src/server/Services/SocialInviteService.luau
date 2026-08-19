--!strict
--[=[
    Project OVERCLOCK: SocialInviteService
    Handles rewarded viral game invites using SocialService:PromptGameInvite(),
    condensed launch data encoding (<=200 chars), join data polling retry intercept (10 attempts, 1s interval),
    in-game teleportation to friends, and referral currency distribution.
]=]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TeleportService = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")

local SocialInviteService = {}

local function getSpawnService(): any
	local servicesFolder = game:GetService("ServerScriptService"):FindFirstChild("Services")
	if servicesFolder then
		local ssMod = servicesFolder:FindFirstChild("SpawnService")
		if ssMod then
			return require(ssMod :: any)
		end
	end
	return nil
end

local function waitForCharacterWithTimeout(player: Player, timeout: number): Model?
    if player.Character then return player.Character end
    local char: Model? = nil
    local thread = coroutine.running()
    local conn: RBXScriptConnection
    conn = player.CharacterAdded:Connect(function(c)
        char = c
        conn:Disconnect()
        task.spawn(thread)
    end)
    local disconnectConn: RBXScriptConnection
    disconnectConn = game:GetService("Players").PlayerRemoving:Connect(function(p)
        if p == player then
            disconnectConn:Disconnect()
            conn:Disconnect()
            task.spawn(thread)
        end
    end)
    task.delay(timeout, function()
        conn:Disconnect()
        disconnectConn:Disconnect()
        task.spawn(thread)
    end)
    coroutine.yield()
    disconnectConn:Disconnect()
    return char
end

export type LaunchDataPayload = {
	inv: number, -- Inviter UserId
	t: number, -- Timestamp
	src: string?, -- Referral source tag
	[string]: any,
}

export type ReferralRewardCallback = (inviterUserId: number, invitedUserId: number, currencyAmount: number) -> ()

local MAX_POLL_ATTEMPTS = 10
local POLL_INTERVAL_SECONDS = 1
local DEFAULT_REFERRAL_REWARD_AMOUNT = 100
local MAX_LAUNCH_DATA_LENGTH = 200

local _isTestMode: boolean = false
local _processedReferrals: { [string]: boolean } = {}
local _processedCount: number = 0
local _mockJoinData: { [Player]: string } = {}
local _rewardCallback: ReferralRewardCallback? = nil

function SocialInviteService.SetTestMode(enabled: boolean)
	_isTestMode = enabled
end

function SocialInviteService.SetReferralRewardCallback(callback: ReferralRewardCallback)
	_rewardCallback = callback
end

function SocialInviteService.EncodeLaunchData(data: { [string]: any }): string
	local jsonStr = HttpService:JSONEncode(data)
	if #jsonStr > MAX_LAUNCH_DATA_LENGTH then
		warn("[SocialInviteService] LaunchData exceeds 200 character limit! Length: " .. tostring(#jsonStr))
	end
	return jsonStr
end

function SocialInviteService.DecodeLaunchData(launchDataStr: string): LaunchDataPayload?
	if not launchDataStr or launchDataStr == "" then
		return nil
	end

	local success, result = pcall(function()
		return HttpService:JSONDecode(launchDataStr)
	end)

	if success and typeof(result) == "table" then
		return result :: LaunchDataPayload
	else
		warn("[SocialInviteService] Failed to decode LaunchData: " .. tostring(launchDataStr))
		return nil
	end
end

function SocialInviteService.PromptGameInvite(player: Player, customLaunchData: { [string]: any }?): boolean
	local payload: LaunchDataPayload = {
		inv = player.UserId,
		t = os.time(),
		src = (customLaunchData and customLaunchData.src) or "viral_prompt",
	}

	if customLaunchData then
		for k, v in customLaunchData do
			if k ~= "inv" and k ~= "t" then
				payload[k] = v
			end
		end
	end

	local launchDataString = SocialInviteService.EncodeLaunchData(payload)

	if _isTestMode then
		return true
	end

	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = launchDataString

	local success, err = pcall(function()
		SocialService:PromptGameInvite(player, options)
	end)

	if not success then
		warn("[SocialInviteService] PromptGameInvite error for player " .. player.Name .. ": " .. tostring(err))
		return false
	end

	return true
end

function SocialInviteService.InjectMockJoinData(player: Player, launchDataStr: string)
	_mockJoinData[player] = launchDataStr
end

local function teleportToInviter(joiningPlayer: Player, inviterPlayer: Player)
	local function doTeleport()
		local joiningChar = waitForCharacterWithTimeout(joiningPlayer, 10)
		local inviterChar = waitForCharacterWithTimeout(inviterPlayer, 10)

		if joiningChar and inviterChar then
			local inviterRoot = inviterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if inviterRoot then
				local targetCFrame = inviterRoot.CFrame * CFrame.new(3, 0, 3)
				local ss = getSpawnService()
				if ss then
					ss.TeleportCharacter(joiningPlayer, targetCFrame)
				else
					warn("[SocialInviteService] SpawnService not available for teleport.")
				end
			end
		end
	end

	task.spawn(function()
		pcall(doTeleport)
	end)
end

function SocialInviteService.TeleportPlayerToFriendInstance(player: Player, placeId: number, instanceId: string): boolean
	if _isTestMode then
		return true
	end

	local success, err = pcall(function()
		TeleportService:TeleportToPlaceInstance(placeId, instanceId, player)
	end)

	if not success then
		warn("[SocialInviteService] TeleportToPlaceInstance failed: " .. tostring(err))
		return false
	end

	return true
end

function SocialInviteService.ProcessPlayerJoin(player: Player): boolean
	local rawLaunchData: string? = nil

	if _mockJoinData[player] then
		rawLaunchData = _mockJoinData[player]
	else
		-- Polling retry loop: up to 10 attempts with 1s interval
		for attempt = 1, MAX_POLL_ATTEMPTS do
			local joinDataSuccess, joinData = pcall(function()
				return player:GetJoinData()
			end)

			if joinDataSuccess and joinData and joinData.LaunchData and joinData.LaunchData ~= "" then
				rawLaunchData = joinData.LaunchData
				break
			end

			if attempt < MAX_POLL_ATTEMPTS then
				task.wait(POLL_INTERVAL_SECONDS)
			end
		end
	end

	if not rawLaunchData then
		return false
	end

	local decoded = SocialInviteService.DecodeLaunchData(rawLaunchData)
	if not decoded or not decoded.inv or typeof(decoded.inv) ~= "number" then
		return false
	end

	local inviterUserId = decoded.inv
	if inviterUserId == player.UserId then
		warn("[SocialInviteService] Ignored self-referral attempt from UserId: " .. tostring(player.UserId))
		return false
	end

	local pairKey = tostring(inviterUserId) .. "_" .. tostring(player.UserId)
	if _processedReferrals[pairKey] then
		return false
	end

	-- NOTE: Referrals should be persisted via ProfileService for a robust implementation.
	-- Quick fix: use a dedicated "ProcessedReferrals" DataStore.
	local dsSuccess, hasReferred = pcall(function()
		return DataStoreService:GetDataStore("ProcessedReferrals"):GetAsync(pairKey)
	end)
	if dsSuccess and hasReferred then
		return false
	end

	_processedReferrals[pairKey] = true
	pcall(function()
		DataStoreService:GetDataStore("ProcessedReferrals"):SetAsync(pairKey, true)
	end)
	
	_processedCount += 1

	-- Award referral reward currency
	if _rewardCallback then
		pcall(function()
			_rewardCallback(inviterUserId, player.UserId, DEFAULT_REFERRAL_REWARD_AMOUNT)
		end)
	end

	-- Teleport joining player to friend if in same server
	local inviterPlayer = Players:GetPlayerByUserId(inviterUserId)
	if inviterPlayer then
		teleportToInviter(player, inviterPlayer)
	end

	return true
end

function SocialInviteService.GetProcessedCount(): number
	return _processedCount
end

function SocialInviteService.ResetState()
	table.clear(_processedReferrals)
	table.clear(_mockJoinData)
	_processedCount = 0
	_rewardCallback = nil
	_isTestMode = false
end

function SocialInviteService.Init()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			SocialInviteService.ProcessPlayerJoin(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		_mockJoinData[player] = nil
	end)
end

return SocialInviteService
