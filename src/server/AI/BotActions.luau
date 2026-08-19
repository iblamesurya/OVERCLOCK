--!strict
--[=[
    Project OVERCLOCK: Bot Actions (Behavior Tree Nodes)
    Leaf nodes for the BT engine including Pathfinding, Combat, and Evading.
]=]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BehaviorTree = require(script.Parent.BehaviorTree)
local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)
local WeaponStats = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponStats") :: any)

local BotActions = {}

-- ----------------------------------------------------------------------------
-- Core Action: Reload
-- ----------------------------------------------------------------------------
function BotActions.ActionReload(): BehaviorTree.Node
    return BehaviorTree.Action(function(context: any)
        if context.ammo > 0 then
            return "Failure"
        end

        if not context.isReloading then
            context.isReloading = true
            context.reloadStartTime = os.clock()
        end

        if os.clock() - context.reloadStartTime >= 2.0 then -- 2 second reload
            context.ammo = 30
            context.isReloading = false
            return "Success"
        end

        return "Running"
    end)
end

-- ----------------------------------------------------------------------------
-- Core Action: Find Target
-- ----------------------------------------------------------------------------
function BotActions.ActionFindTarget(): BehaviorTree.Node
    return BehaviorTree.Action(function(context: any)
        if context.target and context.target.Character and context.target.Character:FindFirstChild("Humanoid") and context.target.Character.Humanoid.Health > 0 then
            -- Verify Line of Sight
            local targetHRP = context.target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then
                local dir = targetHRP.Position - context.rootPart.Position
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = {context.model, context.target.Character}
                local hit = Workspace:Raycast(context.rootPart.Position, dir, rayParams)
                if not hit then
                    return "Success" -- Target is valid and visible
                end
            end
        end

        -- Find new target
        local closestTarget = nil
        local closestDist = 200 -- Max vision range

        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - context.rootPart.Position).Magnitude
                    if dist < closestDist then
                        -- Check LoS
                        local dir = hrp.Position - context.rootPart.Position
                        local rayParams = RaycastParams.new()
                        rayParams.FilterType = Enum.RaycastFilterType.Exclude
                        rayParams.FilterDescendantsInstances = {context.model, player.Character}
                        local hit = Workspace:Raycast(context.rootPart.Position, dir, rayParams)
                        
                        if not hit then
                            closestDist = dist
                            closestTarget = player
                        end
                    end
                end
            end
        end

        if closestTarget then
            context.target = closestTarget
            return "Success"
        end

        context.target = nil
        return "Failure"
    end)
end

-- ----------------------------------------------------------------------------
-- Core Action: Engage Target
-- ----------------------------------------------------------------------------
function BotActions.ActionEngageTarget(): BehaviorTree.Node
    return BehaviorTree.Action(function(context: any)
        if not context.target or not context.target.Character then
            return "Failure"
        end
        local targetHRP = context.target.Character:FindFirstChild("HumanoidRootPart")
        if not targetHRP then return "Failure" end

        -- Face the target
        local lookPos = targetHRP.Position
        context.rootPart.CFrame = CFrame.new(context.rootPart.Position, Vector3.new(lookPos.X, context.rootPart.Position.Y, lookPos.Z))
        -- Stop moving
        context.humanoid:MoveTo(context.rootPart.Position)

        -- Fire weapon
        local now = os.clock()
        local diff = context.model:GetAttribute("BotDifficulty") or "Easy"

        -- Reaction Delay logic
        if not context.firstSpotted then
            context.firstSpotted = now
            local delay = 0.3
            if diff == "Medium" then delay = 0.2 elseif diff == "Hard" then delay = 0.1 end
            context.reactionDelay = delay + math.random() * 0.15
            return "Running"
        elseif now - context.firstSpotted < (context.reactionDelay or 0.25) then
            return "Running"
        end

        if now - (context.lastAttackTime or 0) > 0.2 and not context.isReloading then
            context.lastAttackTime = now
            context.ammo = context.ammo - 1
            
            -- Simulate fire event
            local origin = context.headPart.Position
            local direction = (targetHRP.Position - origin).Unit
            
            -- We don't actually need to raycast on client since we know we have LoS,
            -- But we trigger the visual effect for the player
            local FireWeapon = RemoteEvents.GetUnreliable("FireWeapon")
            FireWeapon:FireAllClients(context.botId, origin, direction, "AssaultRifle")
            
            -- Apply direct damage (simplified for bots)
            local targetHum = context.target.Character:FindFirstChild("Humanoid")
            if targetHum then
                local accuracy = 0.4
                if diff == "Medium" then accuracy = 0.7 elseif diff == "Hard" then accuracy = 0.9 end
                if math.random() <= accuracy then
                    targetHum:TakeDamage(WeaponStats.CalculateDamage("AssaultRifle", false, (origin - targetHRP.Position).Magnitude))
                end
            end
        end

        return "Success"
    end)
end

-- ----------------------------------------------------------------------------
-- Core Action: Take Cover (Flee)
-- ----------------------------------------------------------------------------
function BotActions.ActionTakeCover(): BehaviorTree.Node
    return BehaviorTree.Action(function(context: any)
        local diff = context.model:GetAttribute("BotDifficulty") or "Easy"
        if diff == "Easy" then return "Failure" end
        if context.humanoid.Health >= 40 then return "Failure" end

        if context.target and context.target.Character then
            local targetHRP = context.target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then
                local CollectionService = game:GetService("CollectionService")
                local covers = CollectionService:GetTagged("BulletBlocker")
                local bestCover = nil
                local bestDist = 30
                for _, cover in ipairs(covers) do
                    local dist = (cover.Position - context.rootPart.Position).Magnitude
                    if dist < bestDist then
                        local dir = cover.Position - targetHRP.Position
                        local params = RaycastParams.new()
                        params.FilterDescendantsInstances = {context.target.Character, context.model}
                        params.FilterType = Enum.RaycastFilterType.Exclude
                        local hit = Workspace:Raycast(targetHRP.Position, dir.Unit * dir.Magnitude, params)
                        if hit and hit.Instance == cover then
                            bestCover = cover
                            bestDist = dist
                        end
                    end
                end
                if bestCover then
                    local fleeDir = (bestCover.Position - targetHRP.Position).Unit
                    local fleePos = bestCover.Position + fleeDir * 4
                    context.humanoid:MoveTo(fleePos)
                    return "Running"
                else
                    local fleeDir = (context.rootPart.Position - targetHRP.Position).Unit
                    local fleePos = context.rootPart.Position + fleeDir * 10
                    context.humanoid:MoveTo(fleePos)
                    return "Running"
                end
            end
        end
        return "Failure"
    end)
end

-- ----------------------------------------------------------------------------
-- Core Action: Patrol Pathfinding
-- ----------------------------------------------------------------------------
function BotActions.ActionPatrol(waypoints: {Vector3}): BehaviorTree.Node
    return BehaviorTree.Action(function(context: any)
        if #waypoints == 0 then return "Failure" end

        if not context.path or not context.pathWaypoints then
            if context.isComputingPath then return "Running" end
            context.isComputingPath = true
            
            task.spawn(function()
                local newPath = PathfindingService:CreatePath({
                    AgentRadius = 2.0,
                    AgentHeight = 5.0,
                    AgentCanJump = true,
                    AgentJumpHeight = 10.0,
                    AgentMaxSlope = 45,
                })
                
                local targetWp = waypoints[context.currentWaypointIndex or 1]
                local success = pcall(function()
                    newPath:ComputeAsync(context.rootPart.Position, targetWp)
                end)
                
                if success and newPath.Status == Enum.PathStatus.Success then
                    context.path = newPath
                    context.pathWaypoints = newPath:GetWaypoints()
                    context.currentPathIndex = 2
                else
                    context.currentWaypointIndex = ((context.currentWaypointIndex or 1) % #waypoints) + 1
                    context.path = nil
                    context.pathWaypoints = nil
                end
                context.isComputingPath = false
            end)
            
            return "Running"
        end

        if context.pathWaypoints and context.currentPathIndex <= #context.pathWaypoints then
            local targetWp = context.pathWaypoints[context.currentPathIndex].Position
            context.humanoid:MoveTo(targetWp)
            
            if context.pathWaypoints[context.currentPathIndex].Action == Enum.PathWaypointAction.Jump then
                context.humanoid.Jump = true
            end
            
            if (context.rootPart.Position - targetWp).Magnitude < 3 then
                context.currentPathIndex += 1
            end
            return "Running"
        else
            -- Reached destination, pick next macro-waypoint
            context.path = nil
            context.pathWaypoints = nil
            context.currentWaypointIndex = ((context.currentWaypointIndex or 1) % #waypoints) + 1
            return "Success"
        end
    end)
end

return BotActions
