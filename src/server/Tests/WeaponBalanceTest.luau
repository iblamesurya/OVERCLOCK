--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any)

local WeaponBalanceTest = {}

function WeaponBalanceTest.Run(): (boolean, {string})
	local logs = {}
	local passed = true

	for id, data in pairs(WeaponStats.GetAll()) do
		if data.damage <= 0 or data.damage >= 200 then passed = false; table.insert(logs, "Invalid damage for " .. id) end
		if data.fireRate <= 0 then passed = false; table.insert(logs, "Invalid RPM for " .. id) end
		if data.magazineCapacity <= 0 then passed = false; table.insert(logs, "Invalid mag for " .. id) end
		if data.maxRange <= 0 or data.maxRange >= 5000 then passed = false; table.insert(logs, "Invalid maxRange for " .. id) end
		if data.spreadMin >= data.spreadMax then passed = false; table.insert(logs, "Invalid spread logic for " .. id) end
		if data.headshotMultiplier < 1.0 then passed = false; table.insert(logs, "Invalid headshot multiplier for " .. id) end

		local ttk = 100 / (data.damage * (data.fireRate / 60))
		if ttk < 0.15 or ttk > 3.0 then passed = false; table.insert(logs, "TTK out of bounds for " .. id .. ": " .. tostring(ttk)) end
	end

	if passed then
		table.insert(logs, "✅ [PASS] WeaponBalanceTest passed for all weapons.")
	end

	return passed, logs
end

return WeaponBalanceTest
