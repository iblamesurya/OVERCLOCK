--!strict
--[[
	OVERCLOCK: PremiumWeaponSkinService
	Place at ServerScriptService.Services.PremiumWeaponSkinService.

	The service only stores cosmetic selections and intentionally keeps gameplay
	state outside this module.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local Catalog = require(DataFolder:WaitForChild("PremiumWeaponCatalog") :: ModuleScript)

export type OwnershipResolver = (player: Player, skinId: string) -> boolean
export type PersistSelection = (player: Player, weaponId: string, skinId: string) -> boolean

type EquippedByWeapon = { [string]: string }

type Service = {
	_ownsSkin: OwnershipResolver,
	_persist: PersistSelection?,
	_equipped: { [number]: EquippedByWeapon },
	_lastRequestAt: { [number]: number },
	_connection: RBXScriptConnection?,
	SetEquipped: (self: Service, player: Player, weaponId: any, skinId: any) -> (boolean, string),
	GetEquipped: (self: Service, player: Player, weaponId: string) -> string,
	Bind: (self: Service, remote: RemoteEvent) -> (),
	Destroy: (self: Service) -> (),
}

local PremiumWeaponSkinService = {}
PremiumWeaponSkinService.__index = PremiumWeaponSkinService

local REQUEST_COOLDOWN_SECONDS = 0.35
local MAX_ID_LENGTH = 32

local function fallbackOwnership(_: Player, skinId: string): boolean
	-- Safe development fallback: only the free starter skin is usable until an
	-- ownership resolver is connected to PlayerDataService/receipt processing.
	return skinId == Catalog.GetDefaultSkinId()
end

function PremiumWeaponSkinService.new(ownsSkin: OwnershipResolver?, persist: PersistSelection?): Service
	local self = setmetatable({
		_ownsSkin = ownsSkin or fallbackOwnership,
		_persist = persist,
		_equipped = {} :: { [number]: EquippedByWeapon },
		_lastRequestAt = {} :: { [number]: number },
		_connection = nil :: RBXScriptConnection?,
	}, PremiumWeaponSkinService)
	return self :: any
end

function PremiumWeaponSkinService:SetEquipped(player: Player, weaponId: any, skinId: any): (boolean, string)
	if type(weaponId) ~= "string" or #weaponId == 0 or #weaponId > MAX_ID_LENGTH then
		return false, "Invalid weapon id"
	end
	if type(skinId) ~= "string" or #skinId == 0 or #skinId > MAX_ID_LENGTH then
		return false, "Invalid skin id"
	end
	if not Catalog.IsCompatible(weaponId, skinId) then
		return false, "Unknown cosmetic"
	end
	if not self._ownsSkin(player, skinId) then
		return false, "Skin is not owned"
	end

	local byWeapon = self._equipped[player.UserId]
	if not byWeapon then
		byWeapon = {}
		self._equipped[player.UserId] = byWeapon
	end

	if self._persist and not self._persist(player, weaponId, skinId) then
		return false, "Could not save selection"
	end

	byWeapon[weaponId] = skinId
	player:SetAttribute("EquippedSkin_" .. weaponId, skinId)
	return true, skinId
end

function PremiumWeaponSkinService:GetEquipped(player: Player, weaponId: string): string
	local byWeapon = self._equipped[player.UserId]
	return (byWeapon and byWeapon[weaponId]) or Catalog.GetDefaultSkinId()
end

function PremiumWeaponSkinService:Bind(remote: RemoteEvent)
	assert(remote:IsA("RemoteEvent"), "WeaponSkinRequest must be a RemoteEvent")
	if self._connection then
		self._connection:Disconnect()
	end

	self._connection = remote.OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end

		local now = os.clock()
		local last = self._lastRequestAt[player.UserId] or -math.huge
		if now - last < REQUEST_COOLDOWN_SECONDS then
			return
		end
		self._lastRequestAt[player.UserId] = now

		local ok, result = self:SetEquipped(player, payload.weaponId, payload.skinId)
		remote:FireClient(player, {
			kind = "WeaponSkinResult",
			success = ok,
			weaponId = type(payload.weaponId) == "string" and payload.weaponId or "",
			skinId = ok and result or "",
			reason = if ok then nil else result,
		})
	end)
end

function PremiumWeaponSkinService:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	table.clear(self._equipped)
	table.clear(self._lastRequestAt)
end

return PremiumWeaponSkinService
