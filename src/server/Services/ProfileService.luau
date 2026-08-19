--!strict
--[=[
    Project OVERCLOCK: ProfileService
    Service wrapper delegating to ProfileServiceWrapper.
]=]

local ProfileServiceWrapper = require(script.Parent:WaitForChild("ProfileServiceWrapper") :: any)

local ProfileService = {}

function ProfileService.LoadProfileAsync(userId: number)
	return ProfileServiceWrapper.LoadProfileAsync(userId)
end

function ProfileService.GetDefaultProfile(userId: number, username: string?)
	return ProfileServiceWrapper.GetDefaultProfile(userId, username)
end

function ProfileService.CreateInMemoryFallback(userId: number, defaultData: any)
	return ProfileServiceWrapper.CreateInMemoryFallback(userId, defaultData)
end

function ProfileService.RegisterActiveProfile(userId: number, profile: any)
	ProfileServiceWrapper.RegisterActiveProfile(userId, profile)
end

function ProfileService.UnregisterActiveProfile(userId: number)
	ProfileServiceWrapper.UnregisterActiveProfile(userId)
end

return ProfileService
