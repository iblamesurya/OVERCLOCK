--!strict
--[=[
    Project OVERCLOCK: Data/Constants proxy
    Re-exports root Constants module.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Constants") :: any)

return Constants
