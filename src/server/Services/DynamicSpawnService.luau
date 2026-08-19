--!strict
--[=[
    Project OVERCLOCK: DynamicSpawnService
    Selects the optimal, safest spawn point based on a weighted distance 
    algorithm and Line-of-Sight (LoS) validations.
    Prevents spawn camping and ensures fair restarts during matches.
]=]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DynamicSpawnService = {}

export type SpawnScore = {
    cframe: CFrame,
    score: number,
}

-- Weights and thresholds
local LOS_PENALTY = 50000 -- Massive penalty if an enemy can see the spawn point
local MIN_SAFE_DISTANCE = 40 -- Studs
local PROXIMITY_PENALTY = 10000

--- Evaluates a list of CFrames and returns the safest one based on enemy locations
function DynamicSpawnService.GetOptimalSpawn(candidateSpawns: {CFrame}, enemies: {Player}): CFrame
    if not candidateSpawns or #candidateSpawns == 0 then
        return CFrame.new(0, 100, 0)
    end
    
    if not enemies or #enemies == 0 then
        -- No enemies, pick a random spawn
        return candidateSpawns[math.random(1, #candidateSpawns)]
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    
    -- Filter out all character models so we only raycast against static map geometry
    local allCharacters = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(allCharacters, p.Character) end
    end
    local spawnFolder = Workspace:FindFirstChild("Spawns") or Workspace:FindFirstChild("SpawnLocations")
    if spawnFolder then
        table.insert(allCharacters, spawnFolder)
    end
    raycastParams.FilterDescendantsInstances = allCharacters

    local bestSpawn: CFrame? = nil
    local bestScore = -math.huge

    for _, spawnCF in ipairs(candidateSpawns) do
        local score = 0
        local spawnPos = spawnCF.Position
        
        local minEnemyDist = math.huge
        local hasLOS = false

        for _, enemy in ipairs(enemies) do
            if enemy.Character then
                local hrp = enemy.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                local head = enemy.Character:FindFirstChild("Head") :: BasePart?
                
                if hrp and head then
                    local dist = (hrp.Position - spawnPos).Magnitude
                    if dist < minEnemyDist then
                        minEnemyDist = dist
                    end
                    
                    -- Check Line of Sight from Enemy Head to Spawn Point
                    local targetPos = spawnPos + Vector3.new(0, 3, 0)
                    local dir = (targetPos - head.Position)
                    local hit = Workspace:Raycast(head.Position, dir, raycastParams)
                    
                    -- If the ray hits nothing, it means there are no walls blocking the view
                    if not hit then
                        hasLOS = true
                    end
                end
            end
        end

        -- Base score is the distance to the CLOSEST enemy (we want to maximize this distance)
        if minEnemyDist == math.huge then
            score = 1000 -- Safe
        else
            score = minEnemyDist
        end
        
        -- Penalties
        if minEnemyDist < MIN_SAFE_DISTANCE then
            score -= PROXIMITY_PENALTY
        end
        
        if hasLOS then
            score -= LOS_PENALTY
        end

        if score > bestScore then
            bestScore = score
            bestSpawn = spawnCF
        end
    end

    return bestSpawn or candidateSpawns[math.random(1, #candidateSpawns)]
end

return DynamicSpawnService
