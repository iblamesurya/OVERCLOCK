--!strict
--[=[
    Project OVERCLOCK: QueueService
    Service wrapper delegating to QueueMatchmakingService.
]=]

local QueueMatchmakingService = require(script.Parent:WaitForChild("QueueMatchmakingService") :: any)

local QueueService = {}

function QueueService.Initialize()
	QueueMatchmakingService.Initialize()
end

function QueueService.EnterQueue(player: Player, mode: string)
	QueueMatchmakingService.EnterQueue(player, mode)
end

function QueueService.LeaveQueue(player: Player)
	QueueMatchmakingService.LeaveQueue(player)
end

function QueueService.GetQueueStatus(player: Player)
	return QueueMatchmakingService.GetQueueStatus(player)
end

return QueueService
