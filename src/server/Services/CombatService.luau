--!strict
--[=[
    Project OVERCLOCK: CombatService
    Service wrapper delegating to CombatServer.
]=]

local CombatServer = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatServer") :: any)

local CombatService = {}

function CombatService.new()
	return CombatServer.new()
end

function CombatService.GetCombatServerInstance()
	return CombatServer
end

return CombatService
