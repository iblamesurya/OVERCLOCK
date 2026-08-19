--!strict
--[=[
    Project OVERCLOCK: EconomyService
    Server-authoritative credit economy system for 1v1 and 2v2 PvP matches.
    Manages player credit balances, pistol round starting credits (800), sudden-death (5000),
    win bonus (+3000), scaling loss streak bonus (+1900, +2400, +2900 max), kill rewards (+200),
    and buy phase server validation.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

export type CatalogItem = {
	price: number,
	category: string,
	armorValue: number?,
}

local EconomyService = {}

-- Constants
EconomyService.PISTOL_ROUND_CREDITS = 800
EconomyService.SUDDEN_DEATH_CREDITS = 5000
EconomyService.WIN_BONUS = 3000
EconomyService.LOSS_STREAK_TIER_1 = 1900
EconomyService.LOSS_STREAK_TIER_2 = 2400
EconomyService.LOSS_STREAK_TIER_MAX = 2900
EconomyService.KILL_REWARD = 200

-- Shop item catalog definition
EconomyService.SHOP_CATALOG = {
	["Pistol"] = { price = 0, category = "Weapon" },
	["LightSMG"] = { price = 1000, category = "Weapon" },
	["HeavySMG"] = { price = 1500, category = "Weapon" },
	["AssaultRifle"] = { price = 2900, category = "Weapon" },
	["Carbine"] = { price = 2500, category = "Weapon" },
	["BurstRifle"] = { price = 2500, category = "Weapon" },
	["Shotgun"] = { price = 1800, category = "Weapon" },
	["SniperRifle"] = { price = 4500, category = "Weapon" },
	["LightArmor"] = { price = 400, category = "Armor", armorValue = 25 },
	["HeavyArmor"] = { price = 1000, category = "Armor", armorValue = 50 },
}

-- Internal balance storage (UserId -> Credits)
local playerBalances: { [number]: number } = {}
local transactionLocks: { [number]: boolean } = {}

-- Optional service references (set during Init or resolved lazily)
local _roundServiceRef: any = nil
local _combatServerRef: any = nil
local _directChallengeServiceRef: any = nil

local function getDirectChallengeService()
	if not _directChallengeServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local dcs = servicesFolder:FindFirstChild("DirectChallengeService")
			if dcs then
				_directChallengeServiceRef = require(dcs :: any)
			end
		end
	end
	return _directChallengeServiceRef
end

local function getRoundService()
	if not _roundServiceRef then
		local servicesFolder = ServerScriptService:FindFirstChild("Services")
		if servicesFolder then
			local rs = servicesFolder:FindFirstChild("RoundService")
			if rs then
				_roundServiceRef = require(rs :: any)
			end
		end
	end
	return _roundServiceRef
end

--- Set external service references if needed
function EconomyService.SetServiceReferences(roundService: any?, combatServer: any?)
	if roundService then
		_roundServiceRef = roundService
	end
	if combatServer then
		_combatServerRef = combatServer
	end
end

--- Initializes a player's credit balance for a match session.
function EconomyService.InitializePlayer(player: Player, startingCredits: number?): number
	local initial = startingCredits or EconomyService.PISTOL_ROUND_CREDITS
	local clamped = math.max(0, initial)
	playerBalances[player.UserId] = clamped

	EconomyService.NotifyBalanceUpdate(player, clamped)
	return clamped
end

--- Returns current credit balance for a player.
function EconomyService.GetCredits(player: Player): number
	return playerBalances[player.UserId] or 0
end

--- Sets a player's credit balance directly (clamped >= 0).
function EconomyService.SetCredits(player: Player, amount: number): number
	local clamped = math.max(0, amount)
	playerBalances[player.UserId] = clamped
	EconomyService.NotifyBalanceUpdate(player, clamped)
	return clamped
end

--- Notifies client of their current balance.
function EconomyService.NotifyBalanceUpdate(player: Player, newBalance: number)
	pcall(function()
		local syncRemote = RemoteEvents.GetReliable("ProfileSync" :: any)
		if syncRemote then
			syncRemote:FireClient(player, {
				credits = newBalance,
			})
		end
	end)
end

--- Awards kill reward credits (+200) to killer player.
function EconomyService.AwardKillReward(killerPlayer: Player): number
	local current = playerBalances[killerPlayer.UserId] or 0
	local updated = current + EconomyService.KILL_REWARD
	playerBalances[killerPlayer.UserId] = updated

	pcall(function()
		local noticeRemote = RemoteEvents.GetReliable("KillRewardNotice" :: any)
		if noticeRemote then
			noticeRemote:FireClient(killerPlayer, {
				amount = EconomyService.KILL_REWARD,
				newBalance = updated,
			})
		end
	end)

	EconomyService.NotifyBalanceUpdate(killerPlayer, updated)
	return updated
end

--- Calculates loss streak credit bonus.
function EconomyService.CalculateLossBonus(lossStreak: number): number
	if lossStreak <= 1 then
		return EconomyService.LOSS_STREAK_TIER_1 -- 1900
	elseif lossStreak == 2 then
		return EconomyService.LOSS_STREAK_TIER_2 -- 2400
	else
		return EconomyService.LOSS_STREAK_TIER_MAX -- 2900
	end
end

--- Processes end of round credit distribution to winning and losing teams.
function EconomyService.ProcessRoundEnd(winners: { Player }, losers: { Player }, loserLossStreak: number): { winnerBonus: number, loserBonus: number }
	local winBonus = EconomyService.WIN_BONUS
	local lossBonus = EconomyService.CalculateLossBonus(loserLossStreak)

	for _, winner in winners do
		if winner and winner.Parent then
			local current = playerBalances[winner.UserId] or 0
			local newBal = current + winBonus
			playerBalances[winner.UserId] = newBal
			EconomyService.NotifyBalanceUpdate(winner, newBal)
		end
	end

	for _, loser in losers do
		if loser and loser.Parent then
			local current = playerBalances[loser.UserId] or 0
			local newBal = current + lossBonus
			playerBalances[loser.UserId] = newBal
			EconomyService.NotifyBalanceUpdate(loser, newBal)
		end
	end

	return {
		winnerBonus = winBonus,
		loserBonus = lossBonus,
	}
end

--- Allocates 5000 credits to all players for Sudden Death rounds.
function EconomyService.SetSuddenDeathCredits(players: { Player })
	for _, player in players do
		if player and player.Parent then
			playerBalances[player.UserId] = EconomyService.SUDDEN_DEATH_CREDITS
			EconomyService.NotifyBalanceUpdate(player, EconomyService.SUDDEN_DEATH_CREDITS)
		end
	end
end

--- Server authority purchase request validation logic.
function EconomyService.ProcessPurchaseRequest(player: Player, itemId: string): (boolean, string, number)
	if transactionLocks[player.UserId] then
		return false, "TransactionInProgress", playerBalances[player.UserId] or 0
	end
	transactionLocks[player.UserId] = true

	local ok, success, reason, balance = pcall(function()
		local currentBalance = playerBalances[player.UserId] or 0

		-- 1. Check Shop Catalog item validity
		local catalogItem = EconomyService.SHOP_CATALOG[itemId]
		if not catalogItem then
			return false, "InvalidItem", currentBalance
		end
		local item = { price = catalogItem.price, category = catalogItem.category, armorValue = catalogItem.armorValue }

		-- 2. Check Practice Range status for free bypass
		local isPractice = false
		local dcs = getDirectChallengeService()
		if dcs then
			local status = dcs.GetPlayerStatus(player)
			if status == "Practice Range" then
				isPractice = true
				item.price = 0
			end
		end

		if not isPractice then
			-- 3. Check Match Buy Phase constraint if player is in an active match
			local rs = getRoundService()
			if rs then
				local playerMatch = rs.GetPlayerMatch(player)
				if playerMatch then
					local phase = rs.GetPlayerPhase(player)
					if phase ~= "Buy" then
						return false, "NotInBuyPhase", currentBalance
					end
				end
			end
		end

		-- 4. Check Credit Balance
		if currentBalance < item.price then
			return false, "InsufficientCredits", currentBalance
		end

		-- 5. Execute Purchase
		local newBalance = currentBalance - item.price
		playerBalances[player.UserId] = newBalance

		-- Apply Item Effects
		if item.category == "Armor" and item.armorValue then
			if _combatServerRef then
				pcall(function()
					_combatServerRef:RegisterPlayer(player.UserId, 100, item.armorValue)
				end)
			end
			local char = player.Character
			if char then
				char:SetAttribute("Armor", item.armorValue)
				char:SetAttribute("ArmorType", itemId)
			end
		elseif item.category == "Weapon" then
			local char = player.Character
			if char then
				char:SetAttribute("Equipped" .. item.category, itemId)
			end
		end

		EconomyService.NotifyBalanceUpdate(player, newBalance)
		return true, "PurchaseSuccess", newBalance
	end)

	transactionLocks[player.UserId] = nil

	if ok then
		return success, reason, balance
	else
		warn("Error processing purchase:", success)
		return false, "Error", playerBalances[player.UserId] or 0
	end
end

--- Removes a player from balance tracking upon disconnect.
function EconomyService.RemovePlayer(player: Player)
	playerBalances[player.UserId] = nil
end

--- Initializes EconomyService listeners and RemoteEvents.
function EconomyService.Init(roundServiceRef: any?, combatServerRef: any?)
	if roundServiceRef then
		_roundServiceRef = roundServiceRef
	end
	if combatServerRef then
		_combatServerRef = combatServerRef
	end

	Players.PlayerRemoving:Connect(function(player)
		EconomyService.RemovePlayer(player)
	end)

	-- NOTE: RequestPurchase remote is handled exclusively by ServerMain to avoid duplicate handlers.

	print("[EconomyService] Initialized successfully.")
end

return EconomyService
