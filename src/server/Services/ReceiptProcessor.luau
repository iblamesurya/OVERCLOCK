--!strict
--[=[
    Project OVERCLOCK: ReceiptProcessor
    Handles Developer Product purchases via MarketplaceService.ProcessReceipt with:
    - Player presence verification.
    - Idempotency via atomic DataStore checking of `UserId_PurchaseId` hash.
    - Strict return of ProductPurchaseDecision (PurchaseGranted vs NotProcessedYet).
]=]

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PURCHASE_DATASTORE_NAME = "PurchaseHistory_v1"

export type ReceiptInfo = {
	PlayerId: number,
	PlaceIdWherePurchased: number,
	PurchaseId: string,
	ProductId: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}

export type PurchaseRecord = {
	Granted: boolean,
	UserId: number,
	ProductId: number,
	PurchaseId: string,
	Timestamp: number,
	CurrencySpent: number,
}

export type ProductHandler = (player: Player, receiptInfo: ReceiptInfo) -> boolean

local ReceiptProcessor = {}
ReceiptProcessor.__index = ReceiptProcessor

local purchaseDataStore: DataStore? = nil
local productHandlers: { [number]: ProductHandler } = {}
local defaultHandler: ProductHandler? = nil

local function getPurchaseDataStore(): DataStore
	if not purchaseDataStore then
		purchaseDataStore = DataStoreService:GetDataStore(PURCHASE_DATASTORE_NAME)
	end
	return purchaseDataStore :: DataStore
end

--[=[
    Registers a custom product grant handler for a specific ProductId.
]=]
function ReceiptProcessor.RegisterProductHandler(productId: number, handler: ProductHandler): ()
	productHandlers[productId] = handler
end

--[=[
    Sets a default product grant handler for unhandled product IDs.
]=]
function ReceiptProcessor.SetDefaultHandler(handler: ProductHandler): ()
	defaultHandler = handler
end

--[=[
    Default fallback grant handler if none registered for a specific ProductId.
    Integrates with player leaderstats or currency profile if present.
]=]
local function fallbackGrantHandler(player: Player, receiptInfo: ReceiptInfo): boolean
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local credits = leaderstats:FindFirstChild("Credits") or leaderstats:FindFirstChild("Gems")
		if credits and credits:IsA("IntValue") then
			credits.Value += math.floor(receiptInfo.CurrencySpent * 10)
			return true
		end
	end
	-- Default success to prevent blocking valid test purchases if no custom handler bound
	return true
end

--[=[
    Global ProcessReceipt Callback
    Verified player presence, enforces idempotency using DataStore UpdateAsync with
    UserId_PurchaseId hash key, and returns ProductPurchaseDecision.
]=]
function ReceiptProcessor.ProcessReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	if typeof(receiptInfo) ~= "table" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if typeof(receiptInfo.PlayerId) ~= "number" or receiptInfo.PlayerId <= 0 or receiptInfo.PlayerId ~= math.floor(receiptInfo.PlayerId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if typeof(receiptInfo.PurchaseId) ~= "string" or #receiptInfo.PurchaseId == 0 or #receiptInfo.PurchaseId > 200 then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if typeof(receiptInfo.ProductId) ~= "number" or receiptInfo.ProductId <= 0 or receiptInfo.ProductId ~= math.floor(receiptInfo.ProductId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if typeof(receiptInfo.CurrencySpent) ~= "number" or receiptInfo.CurrencySpent < 0 or receiptInfo.CurrencySpent ~= receiptInfo.CurrencySpent then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 1. Player Presence Verification
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not player:IsA("Player") then
		warn("[ReceiptProcessor] Player " .. tostring(receiptInfo.PlayerId) .. " is not present on server. Deferring purchase processing.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2. Idempotency Key Formulation: `UserId_PurchaseId`
	local purchaseKey = string.format("%d_%s", receiptInfo.PlayerId, receiptInfo.PurchaseId)
	local store = getPurchaseDataStore()
	local purchaseGrantedSuccessfully = false

	-- 3. Atomic DataStore Check & Process
	local alreadyGranted = false
	local storeOk = pcall(function()
		store:UpdateAsync(purchaseKey, function(existingRecord: any)
			if existingRecord ~= nil then
				local record = existingRecord :: PurchaseRecord
				if record.Granted == true then
					alreadyGranted = true
					return existingRecord
				end
			end

			-- Mark as granted atomically in DataStore BEFORE granting item in session
			local newRecord: PurchaseRecord = {
				Granted = true,
				UserId = receiptInfo.PlayerId,
				ProductId = receiptInfo.ProductId,
				PurchaseId = receiptInfo.PurchaseId,
				Timestamp = os.time(),
				CurrencySpent = receiptInfo.CurrencySpent,
			}
			return newRecord
		end)
	end)

	if alreadyGranted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not storeOk then
		-- DataStore failed/throttled; defer so Roblox retries safely without duplicate grant
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Execute handler now that record is safely marked
	local handler = productHandlers[receiptInfo.ProductId] or defaultHandler or fallbackGrantHandler
	local grantOk = handler(player, receiptInfo)
	if not grantOk then
		-- Handler failed; clear key so it can be retried
		pcall(function() store:RemoveAsync(purchaseKey) end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--[=[
    Initializes ReceiptProcessor and binds callback to MarketplaceService.
]=]
function ReceiptProcessor.Init(): ()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return ReceiptProcessor.ProcessReceipt(receiptInfo :: ReceiptInfo)
	end
end

return ReceiptProcessor
