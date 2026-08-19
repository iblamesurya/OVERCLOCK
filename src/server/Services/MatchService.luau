--!strict
--[=[
    Project OVERCLOCK: MatchService
    Service wrapper uniting MatchmakingCoordinator and DirectChallengeService.
]=]

local MatchmakingCoordinator = require(script.Parent:WaitForChild("MatchmakingCoordinator") :: any)
local DirectChallengeService = require(script.Parent:WaitForChild("DirectChallengeService") :: any)

local MatchService = {}

function MatchService.Init()
	if MatchmakingCoordinator and MatchmakingCoordinator.StartService then
		MatchmakingCoordinator.StartService()
	end
	if DirectChallengeService and DirectChallengeService.Init then
		DirectChallengeService.Init()
	end
end

function MatchService.GetPlayerStatus(player: Player): string
	return DirectChallengeService.GetPlayerStatus(player)
end

function MatchService.SetPlayerStatus(player: Player, status: string)
	DirectChallengeService.SetPlayerStatus(player, status)
end

return MatchService
