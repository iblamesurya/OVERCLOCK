--!strict
--[[
	OVERCLOCK: MovementAuthorityBootstrap
	Place at ServerScriptService.Combat.MovementAuthorityBootstrap.

	Attach this once from CombatServer.InitializeNetworkListeners after remotes are
	initialized. It replaces client-position authority with a
	MovementIntent remote carrying bounded inputs only.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: ModuleScript)
local MovementAuthority = require(script.Parent:WaitForChild("MovementAuthority") :: ModuleScript)

type CombatSnapshotSink = {
	UpdatePlayerSpatial: (self: CombatSnapshotSink, userId: number, position: Vector3, velocity: Vector3, cframe: CFrame, timestamp: number) -> (),
}

local MovementAuthorityBootstrap = {}

local authority: MovementAuthority.MovementAuthorityClass? = nil
local remoteConnection: RBXScriptConnection? = nil
local playerAddedConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local characterConnections: { [number]: RBXScriptConnection } = {}

local function disconnectCharacterConnection(userId: number)
	local connection = characterConnections[userId]
	if connection then
		connection:Disconnect()
		characterConnections[userId] = nil
	end
end

local function attachCharacter(authorityInstance: MovementAuthority.MovementAuthorityClass, player: Player)
	disconnectCharacterConnection(player.UserId)
	if player.Character then
		authorityInstance:Register(player)
	end
	characterConnections[player.UserId] = player.CharacterAdded:Connect(function()
		authorityInstance:Register(player)
	end)
end

function MovementAuthorityBootstrap.Attach(combatServer: CombatSnapshotSink): MovementAuthority.MovementAuthorityClass
	if authority then
		return authority
	end

	local remote: any = nil
	pcall(function() remote = RemoteEvents.GetUnreliable("MovementIntent") end)
	if not remote or not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
		warn("[MovementAuthorityBootstrap] MovementIntent missing, retrying after RemoteEvents.Initialize()")
		pcall(function() RemoteEvents.Initialize() end)
		pcall(function() remote = RemoteEvents.GetUnreliable("MovementIntent") end)
	end
	if not remote then
		warn("[MovementAuthorityBootstrap] MovementIntent still missing - authority disabled")
		return nil :: any
	end

	local instance = MovementAuthority.new()
	instance:SetSnapshotSink(function(userId, position, velocity, cframe, timestamp)
		combatServer:UpdatePlayerSpatial(userId, position, velocity, cframe, timestamp)
	end)

	remoteConnection = remote.OnServerEvent:Connect(function(player: Player, payload: any)
		instance:SetIntent(player, payload)
	end)

	playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		attachCharacter(instance, player)
	end)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		disconnectCharacterConnection(player.UserId)
		instance:Remove(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		attachCharacter(instance, player)
	end

	instance:Start()
	authority = instance
	return instance
end

function MovementAuthorityBootstrap.GetAuthority(): MovementAuthority.MovementAuthorityClass?
	return authority
end

function MovementAuthorityBootstrap.Destroy()
	if remoteConnection then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for userId in pairs(characterConnections) do
		disconnectCharacterConnection(userId)
	end
	if authority then
		authority:Stop()
		authority = nil
	end
end

return MovementAuthorityBootstrap
