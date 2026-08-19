--!strict
--[[
	OVERCLOCK: PremiumWeaponPresentation
	Place at StarterPlayerScripts.Controllers.PremiumWeaponPresentation.

	Client presentation adapter for premium viewmodels.
	No gameplay stats, no damage, no remote creation — only viewmodel building
	and skin result handling.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local Catalog = require(DataFolder:WaitForChild("PremiumWeaponCatalog") :: ModuleScript)
local Viewmodel = require(DataFolder:WaitForChild("PremiumWeaponViewmodel") :: ModuleScript)

local PremiumWeaponPresentation = {}

function PremiumWeaponPresentation.BuildViewmodel(weaponId: string, skinId: string?): Model
	return Viewmodel.Build(weaponId :: any, skinId)
end

function PremiumWeaponPresentation.ApplySkin(model: Model, weaponId: string, skinId: string): boolean
	if not Catalog.IsCompatible(weaponId, skinId) then
		return false
	end
	return Viewmodel.ApplySkin(model, skinId)
end

function PremiumWeaponPresentation.RequestSkin(remote: RemoteEvent, weaponId: string, skinId: string): ()
	if typeof(weaponId) ~= "string" or typeof(skinId) ~= "string" then return end
	if #weaponId == 0 or #weaponId > 32 or #skinId == 0 or #skinId > 32 then return end
	remote:FireServer({ weaponId = weaponId, skinId = skinId })
end

function PremiumWeaponPresentation.BindSkinResults(remote: RemoteEvent, callback: (string, string) -> ()): RBXScriptConnection
	return remote.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		if payload.kind ~= "WeaponSkinResult" then return end
		if payload.success ~= true then return end
		local weaponId = payload.weaponId
		local skinId = payload.skinId
		if typeof(weaponId) ~= "string" or typeof(skinId) ~= "string" then return end
		if not Catalog.IsCompatible(weaponId, skinId) then return end
		callback(weaponId, skinId)
	end)
end

return PremiumWeaponPresentation
