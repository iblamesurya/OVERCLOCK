--!strict
--[[
	OVERCLOCK: MovementController (RETIRED)
	Place at StarterPlayerScripts.Controllers.MovementController.

	This module is retired. FPSMovementController is the sole owner of
	movement. This stub remains only to avoid require errors from any
	lingering references; it performs no movement and never touches
	humanoid state or network.
--]]

local MovementController = {}

function MovementController.Init()
	warn("[MovementController] retired — FPSMovementController owns movement")
	return
end

function MovementController.SetCrouching(_active: boolean)
	return
end

function MovementController.Destroy()
	return
end

return MovementController
