--!strict
--[=[
    Project OVERCLOCK: Player Data Service
    Central hub for loading, manipulating, and saving player statistics
    utilizing ProfileServiceWrapper for robust session-locking.
]=]

local Players = game:GetService("Players")
local ProfileServiceWrapper = require(script.Parent:WaitForChild("ProfileServiceWrapper") :: any)
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService") :: any)

local PlayerDataService = {}

export type PlayerData = {
    Kills: number,
    Deaths: number,
    Coins: number,
    MMR: number,
}

local DataStoreName = "PlayerData_Prod_v1"

local ProfileTemplate: PlayerData = {
    Kills = 0,
    Deaths = 0,
    Coins = 100,
    MMR = 1000,
}

local Profiles: { [player]: ProfileServiceWrapper.Profile } = {}

function PlayerDataService.GetProfile(player: Player): ProfileServiceWrapper.Profile?
    return Profiles[player]
end

function PlayerDataService.AddKill(player: Player)
    local profile = Profiles[player]
        if profile and profile:IsActive() then
            profile.Data.Kills += 1
            
            -- Very basic Elo simulation
            profile.Data.MMR += 15
            
            -- Update UI
            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local killsObj = leaderstats:FindFirstChild("Kills") :: IntValue
                if killsObj then killsObj.Value = profile.Data.Kills end
            end
            
            -- Update Leaderboard
            LeaderboardService.UpdatePlayerScore(player.UserId, profile.Data.Kills)
        end
end

function PlayerDataService.AddDeath(player: Player)
    local profile = Profiles[player]
    if profile and profile:IsActive() then
        profile.Data.Deaths += 1
        
        profile.Data.MMR = math.max(0, profile.Data.MMR - 10)
        
        -- Update UI
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local deathsObj = leaderstats:FindFirstChild("Deaths") :: IntValue
            if deathsObj then deathsObj.Value = profile.Data.Deaths end
        end
    end
end

local function onPlayerAdded(player: Player)
    local profile = ProfileServiceWrapper.LoadProfileAsync(
        player.UserId,
        ProfileTemplate
    )
    
    if profile then
        profile.OnSessionEnded:Connect(function()
            Profiles[player] = nil
            player:Kick("Your data session was locked by another server. Please rejoin.")
        end)
        
        if player:IsDescendantOf(Players) then
            Profiles[player] = profile
            
            -- Hook up leaderstats for UI display
            local leaderstats = Instance.new("Folder")
            leaderstats.Name = "leaderstats"
            leaderstats.Parent = player
            
            local killsObj = Instance.new("IntValue")
            killsObj.Name = "Kills"
            killsObj.Value = profile.Data.Kills
            killsObj.Parent = leaderstats
            
            local deathsObj = Instance.new("IntValue")
            deathsObj.Name = "Deaths"
            deathsObj.Value = profile.Data.Deaths
            deathsObj.Parent = leaderstats
            
            -- We update leaderstats periodically in a loop or via signals.
            -- For simplicity, let's just keep the master data in Profile.
        else
            -- Player left before profile finished loading
            profile:ReleaseAsync()
        end
    else
        player:Kick("Could not load data. Please try again later.")
    end
end

local function onPlayerRemoving(player: Player)
    local profile = Profiles[player]
    if profile then
        profile:ReleaseAsync()
        Profiles[player] = nil
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players already in server (Studio edge case)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

return PlayerDataService
