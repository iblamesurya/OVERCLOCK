--!strict
--[=[
    Project OVERCLOCK: MapSafety
    Validates map spawn points via downward raycasting to ensure floor collision safety.
]=]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapSafety = {}

-- Standing clearance height (stud requirement above spawn point for player to stand uncrouched).
-- Mirrors FPSMovementConfig.StandClearanceHeight = 3.0 studs.
local STANDING_CLEARANCE = 3.0
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Physics"):WaitForChild("FPSMovementConfig"))
	end)
	if ok and cfg and typeof(cfg.StandClearanceHeight) == "number" then
		STANDING_CLEARANCE = cfg.StandClearanceHeight
	end
end

--[=[
    Verifies that a single spawn point has a collidable floor beneath it.
    Performs a downward raycast from spawnCFrame.Position + Vector3.new(0, 5, 0)
    extending downwards Vector3.new(0, -15, 0) with RaycastParams (IgnoreWater = true, RespectCanCollide = true).
]=]
function MapSafety.verifySpawnPointFloor(
	spawnCFrame: CFrame | Vector3 | BasePart,
	mapFolder: Instance?
): (boolean, string?)
	local cf: CFrame
	if typeof(spawnCFrame) == "CFrame" then
		cf = spawnCFrame
	elseif typeof(spawnCFrame) == "Vector3" then
		cf = CFrame.new(spawnCFrame)
	elseif typeof(spawnCFrame) == "Instance" and spawnCFrame:IsA("BasePart") then
		cf = spawnCFrame.CFrame
	else
		local err = string.format("Invalid spawn point argument type: %s", typeof(spawnCFrame))
		return false, err
	end

	local origin = cf.Position + Vector3.new(0, 5, 0)
	-- Extended to -50 to cover high spawns and StreamingEnabled streamed-out floors (fallback baseplate at Y=90 is excluded via CollisionGroup check)
	local direction = Vector3.new(0, -50, 0)

	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Exclude all player characters so we don't falsely detect a character as floor
	local chars: { Instance } = {}
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	-- Also exclude FallbackBaseplate (transient safety net should not count as map floor)
	local fallback = Workspace:FindFirstChild("FallbackBaseplate")
	if fallback then
		table.insert(chars, fallback)
	end
	if #chars > 0 then
		params.FilterDescendantsInstances = chars
	end

	local result = Workspace:Raycast(origin, direction, params)
	-- Ensure hit is not the FallbackBaseplate itself if it was not filtered
	if result and result.Instance and result.Instance.Name == "FallbackBaseplate" then
		-- Treat as no floor — map geometry missing
		return false, string.format("Spawn point at (%.1f, %.1f, %.1f) only hits FallbackBaseplate — missing map floor!", cf.Position.X, cf.Position.Y, cf.Position.Z)
	end
	if result and result.Instance and result.Instance.CanCollide then
		return true, nil
	end

	local posStr = string.format("(%.1f, %.1f, %.1f)", cf.Position.X, cf.Position.Y, cf.Position.Z)
	local errMsg = string.format("Spawn point at %s lacks collidable floor!", posStr)
	return false, errMsg
end

-- Alias for HasFloor requirement: explicit HasFloor check (same as verifySpawnPointFloor)
MapSafety.HasFloor = MapSafety.verifySpawnPointFloor
MapSafety.hasFloor = MapSafety.verifySpawnPointFloor

--[=[
    Verifies standing clearance (3.0 studs) above a spawn point.
    Ensures player can stand without ceiling obstruction.
    Raycasts upward from spawnCFrame.Position + Vector3.new(0, 1.0, 0) by StandingClearance 3.0.
    Returns true if clearance is free (no hit), false if blocked.
]=]
function MapSafety.verifyStandingClearance(
	spawnCFrame: CFrame | Vector3 | BasePart,
	_mapFolder: Instance?
): (boolean, string?)
	local cf: CFrame
	if typeof(spawnCFrame) == "CFrame" then
		cf = spawnCFrame
	elseif typeof(spawnCFrame) == "Vector3" then
		cf = CFrame.new(spawnCFrame)
	elseif typeof(spawnCFrame) == "Instance" and spawnCFrame:IsA("BasePart") then
		cf = spawnCFrame.CFrame
	else
		local err = string.format("Invalid spawn point argument type: %s", typeof(spawnCFrame))
		return false, err
	end

	local origin = cf.Position + Vector3.new(0, 1.0, 0)
	local direction = Vector3.new(0, STANDING_CLEARANCE, 0)

	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars: { Instance } = {}
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	local fallback = Workspace:FindFirstChild("FallbackBaseplate")
	if fallback then
		table.insert(chars, fallback)
	end
	if #chars > 0 then
		params.FilterDescendantsInstances = chars
	end

	local result = Workspace:Raycast(origin, direction, params)
	if result and result.Instance and result.Instance.CanCollide then
		local posStr = string.format("(%.1f, %.1f, %.1f)", cf.Position.X, cf.Position.Y, cf.Position.Z)
		local errMsg = string.format("Spawn point at %s lacks standing clearance (%.1f studs) — blocked by %s!", posStr, STANDING_CLEARANCE, result.Instance:GetFullName())
		return false, errMsg
	end
	return true, nil
end

MapSafety.HasStandingClearance = MapSafety.verifyStandingClearance
MapSafety.hasStandingClearance = MapSafety.verifyStandingClearance
MapSafety.StandingClearance = STANDING_CLEARANCE
MapSafety.HasFloorAndClearance = function(spawnCFrame: CFrame | Vector3 | BasePart, mapFolder: Instance?): (boolean, string?)
	local okFloor, errFloor = MapSafety.verifySpawnPointFloor(spawnCFrame, mapFolder)
	if not okFloor then
		return false, errFloor
	end
	return MapSafety.verifyStandingClearance(spawnCFrame, mapFolder)
end

--[=[
    Validates all spawn points for a map.
    Returns true if every spawn point has a collidable floor and standing clearance, false otherwise.
    Still prints "[MAP] Every spawn has collidable floor" on full success for backward compatibility.
]=]
function MapSafety.assertMapReady(mapFolder: Instance?, spawnPoints: { any }): boolean
	if not spawnPoints or #spawnPoints == 0 then
		warn("[MAP ERROR] No spawn points provided for map validation! (mapFolder=" .. tostring(mapFolder and mapFolder.Name or "nil") .. ")")
		return false
	end
	if not mapFolder or not mapFolder.Parent then
		warn("[MAP ERROR] Map folder missing or not parented during assertMapReady!")
		return false
	end

	local allPassed = true
	for _, spawnPoint in spawnPoints do
		local cf: CFrame
		if typeof(spawnPoint) == "CFrame" then
			cf = spawnPoint
		elseif typeof(spawnPoint) == "Vector3" then
			cf = CFrame.new(spawnPoint)
		elseif typeof(spawnPoint) == "Instance" and spawnPoint:IsA("BasePart") then
			cf = spawnPoint.CFrame
		else
			warn("[MAP ERROR] Invalid spawn point item encountered during map ready assertion!")
			allPassed = false
			continue
		end

		local okFloor, errFloor = MapSafety.verifySpawnPointFloor(cf, mapFolder)
		if not okFloor then
			warn(string.format("[MAP ERROR] %s", errFloor or "Spawn point lacks collidable floor!"))
			allPassed = false
		end

		local okClear, errClear = MapSafety.verifyStandingClearance(cf, mapFolder)
		if not okClear then
			warn(string.format("[MAP ERROR] %s", errClear or "Spawn point lacks standing clearance!"))
			allPassed = false
		end
	end

	if allPassed then
		print("[MAP] Every spawn has collidable floor")
		return true
	else
		return false
	end
end

return MapSafety
