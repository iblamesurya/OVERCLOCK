--!strict
--[=[
    Project OVERCLOCK: Leaderboard Service
    Manages Global Leaderboards utilizing OrderedDataStores to rank players.
]=]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local LeaderboardService = {}

local KillsLeaderboard: OrderedDataStore? = nil
local pendingUpdates: { [number]: number } = {}

local function getLeaderboard(): OrderedDataStore?
    if not KillsLeaderboard then
        pcall(function()
            KillsLeaderboard = DataStoreService:GetOrderedDataStore("GlobalKills_v1")
        end)
    end
    return KillsLeaderboard
end

local UPDATE_INTERVAL = 300 -- 5 minutes

local TopKillsCache: {{UserId: number, Kills: number}} = {}

-- Poll the OrderedDataStore to get top 10
function LeaderboardService.RefreshLeaderboard()
    local success, errorMessage = pcall(function()
        local lb = getLeaderboard()
        if not lb then return end
        local pages = lb:GetSortedAsync(false, 10)
        local topTen = pages:GetCurrentPage()
        
        table.clear(TopKillsCache)
        
        for rank, data in ipairs(topTen) do
            local userId = tonumber(data.key)
            if userId then
                table.insert(TopKillsCache, {
                    UserId = userId,
                    Kills = data.value
                })
            end
        end
    end)
    
    if not success then
        warn("[LeaderboardService] Failed to refresh leaderboard: " .. tostring(errorMessage))
    end
end

function LeaderboardService.GetTopKills()
    return TopKillsCache
end

function LeaderboardService.UpdatePlayerScore(userId: number, kills: number)
    pendingUpdates[userId] = kills
end

local function flushUpdates()
    local lb = getLeaderboard()
    if not lb then return end
    for userId, kills in pairs(pendingUpdates) do
        pendingUpdates[userId] = nil
        task.spawn(function()
            local success, errorMessage = pcall(function()
                lb:SetAsync(tostring(userId), kills)
            end)
            if not success then
                warn("[LeaderboardService] Failed to update score for " .. userId .. ": " .. tostring(errorMessage))
            end
        end)
    end
end

-- Setup periodic refresh
task.spawn(function()
    while true do
        flushUpdates()
        LeaderboardService.RefreshLeaderboard()
        task.wait(UPDATE_INTERVAL)
    end
end)

return LeaderboardService
