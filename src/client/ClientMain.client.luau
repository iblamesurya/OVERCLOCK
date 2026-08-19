--!strict
--[=[ Project OVERCLOCK: ClientMain - Main client entry point ]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ControllersFolder = script.Parent:WaitForChild("Controllers")
local WeaponController = require(ControllersFolder:WaitForChild("WeaponController") :: any)
local CrosshairController = require(ControllersFolder:WaitForChild("CrosshairController") :: any)
local AnimationController = require(ControllersFolder:WaitForChild("AnimationController") :: any)
local MobileControlsController = require(ControllersFolder:WaitForChild("MobileControlsController") :: any)
local LobbyTransitionController = require(ControllersFolder:WaitForChild("LobbyTransitionController") :: any)
local OperativeController = require(ControllersFolder:WaitForChild("OperativeController") :: any)
local FPSMovementController = require(ControllersFolder:WaitForChild("FPSMovementController") :: any)

local UIFolder = script.Parent:WaitForChild("UI")
local HUDController = require(UIFolder:WaitForChild("HUDController") :: any)
local LobbyUIController = require(UIFolder:WaitForChild("LobbyUIController") :: any)
local MatchmakingQueueUI = require(UIFolder:WaitForChild("MatchmakingQueueUI") :: any)
local PlayerListChallengeUI = require(UIFolder:WaitForChild("PlayerListChallengeUI") :: any)
local ChallengeInviteModal = require(UIFolder:WaitForChild("ChallengeInviteModal") :: any)
local LoadoutInspectorUI = require(UIFolder:WaitForChild("LoadoutInspectorUI") :: any)
local AgentSelectUI = require(UIFolder:WaitForChild("AgentSelectUI") :: any)
local PracticeRangeHUD = require(UIFolder:WaitForChild("PracticeRangeHUD") :: any)
local PostMatchSummaryUI = require(UIFolder:WaitForChild("PostMatchSummaryUI") :: any)
local BuyMenuController = require(UIFolder:WaitForChild("BuyMenuController") :: any)
local ShopUIController = require(UIFolder:WaitForChild("ShopUIController") :: any)

local QueueEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("QueueEvents") :: any)
local ChallengeEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("ChallengeEvents") :: any)
local RemoteEvents = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvents") :: any)

local StarterGui = game:GetService("StarterGui")

print("[ClientMain] Initializing OVERCLOCK Client...")

local localPlayer = Players.LocalPlayer
localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
local currentMode: string = "Lobby" -- "Lobby" | "Match" | "Practice"
local isMobile = UserInputService.TouchEnabled

-- Disable default Roblox CoreGui
local function disableCoreGui()
	for _ = 1, 10 do
		local ok, _ = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then break end
		task.wait(0.5)
	end
end
task.spawn(disableCoreGui)

-- 1. Initialize all UI & Controllers
print("[BOOT] Initializing UI controllers...")
HUDController.Init(playerGui) print("[UI] HUDController ready")
CrosshairController.Init() print("[UI] CrosshairController ready")
AnimationController.Init() print("[UI] AnimationController ready")
MobileControlsController.Init(playerGui) print("[UI] MobileControlsController ready")
WeaponController.Init() print("[UI] WeaponController ready")
FPSMovementController.Init() print("[FPS] FPSMovementController ready")

LobbyUIController.Init(playerGui) print("[UI] LobbyUIController ready")
MatchmakingQueueUI.Initialize(playerGui) print("[UI] MatchmakingQueueUI ready")
PlayerListChallengeUI.Initialize(playerGui) print("[UI] PlayerListChallengeUI ready")
ChallengeInviteModal.Initialize(playerGui) print("[UI] ChallengeInviteModal ready")
LoadoutInspectorUI.Init(playerGui) print("[UI] LoadoutInspectorUI ready")
LobbyTransitionController.Init(playerGui) print("[UI] LobbyTransitionController ready")
AgentSelectUI.Init(playerGui) print("[UI] AgentSelectUI ready")
PracticeRangeHUD.Init(playerGui) print("[UI] PracticeRangeHUD ready")
PostMatchSummaryUI.Init(playerGui) print("[UI] PostMatchSummaryUI ready")
BuyMenuController.Init(playerGui) print("[UI] BuyMenuController ready")
ShopUIController.Init(playerGui) print("[UI] ShopUIController ready")
OperativeController.Init() print("[UI] OperativeController ready")

-- 2. Wire Lobby Callbacks
LobbyUIController.OnLoadoutClicked(function()
	LoadoutInspectorUI.Show()
end)

-- 1v1 Duel button -> queue for 1v1
LobbyUIController.OnPlayClicked(function()
	pcall(function()
		RemoteEvents.GetReliable("RequestQueue"):FireServer("1v1")
	end)
	MatchmakingQueueUI.ShowQueuePanel()
end)

-- 2v2 button -> queue for 2v2
LobbyUIController.OnChallengeClicked(function()
	pcall(function()
		RemoteEvents.GetReliable("RequestQueue"):FireServer("2v2")
	end)
	MatchmakingQueueUI.ShowQueuePanel()
end)

-- Practice Range button
LobbyUIController.OnPracticeClicked(function()
	pcall(function()
		RemoteEvents.GetReliable("EnterPracticeRange"):FireServer()
	end)
end)

-- Shop button
LobbyUIController.OnShopClicked(function()
	ShopUIController.Show()
end)

-- Default to Lobby mode
HUDController.SetHUDMode("Lobby")
LobbyUIController.ShowMainLobbyMenu()

print("[ClientMain] All Controllers & UI Initialized.")

-- 3. Mode transition helpers
local function setMode(mode: string)
	currentMode = mode
	if mode == "Match" then
		LobbyUIController.HideAllMenus()
		PlayerListChallengeUI.SetVisible(false)
		PracticeRangeHUD.Hide()
		HUDController.SetHUDMode("Match")
		CrosshairController.SetVisible(true)
		-- Mobile: show combat buttons, hide menu toggle
		if isMobile then
			MobileControlsController.SetCombatVisible(true)
			MobileControlsController.SetMenuButtonVisible(false)
		end
	elseif mode == "Practice" then
		LobbyUIController.HideAllMenus()
		PlayerListChallengeUI.SetVisible(false)
		PracticeRangeHUD.Show()
		HUDController.SetHUDMode("Match") -- reuse match HUD for health/crosshair
		CrosshairController.SetVisible(true)
		WeaponController.EquipWeapon("AssaultRifle")
		-- Mobile: show combat buttons, hide menu toggle
		if isMobile then
			MobileControlsController.SetCombatVisible(true)
			MobileControlsController.SetMenuButtonVisible(false)
		end
	elseif mode == "Lobby" then
		PracticeRangeHUD.Hide()
		BuyMenuController.Hide()
		PlayerListChallengeUI.SetVisible(true)
		HUDController.SetHUDMode("Lobby")
		CrosshairController.SetVisible(false)
		-- Mobile: hide combat buttons, show menu toggle
		if isMobile then
			MobileControlsController.SetCombatVisible(false)
			MobileControlsController.SetMenuButtonVisible(true)
		end
	end
end

-- 3b. Mobile: bind the ☰ menu toggle + FPS movement actions (sprint/crouch/jump → FPSMovementController)
if isMobile then
	task.defer(function()
		local menuBtn = MobileControlsController.GetMenuButton()
		if menuBtn then
			menuBtn.MouseButton1Click:Connect(function()
				LobbyUIController.ToggleFreeRoam()
			end)
		end
	end)
	-- Wire FPS movement mobile actions (Installing §6) - crouch press during sprint triggers slide in kernel
	pcall(function()
		MobileControlsController.BindCombatActions({
			onSprint = function(_, state) FPSMovementController.SetMobileAction("Sprint", state) end,
			onCrouch = function(_, state) FPSMovementController.SetMobileAction("Crouch", state) end,
			onJump = function(_, state) FPSMovementController.SetMobileAction("Jump", state) end,
		})
	end)
end

-- 4. Listen for server phase transitions
local function handleTransitionToMatch()
	LobbyTransitionController.TransitionToMatch(1.2, function()
		setMode("Match")
	end)
end

local function handleTransitionToLobby()
	LobbyTransitionController.TransitionToLobby(1.2, function()
		setMode("Lobby")
	end)
end

pcall(function()
	RemoteEvents.GetReliable("RoundStateChanged").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then return end
		local phase = data.phase or data.state
		if phase == "Buy" then
			BuyMenuController.Show(data.credits)
		elseif phase == "Live" then
			BuyMenuController.Hide()
		elseif phase == "RoundEnd" or phase == "Intermission" then
			BuyMenuController.Hide()
		elseif phase == "AgentSelect" then
			AgentSelectUI.Show(data.mode)
		end
	end)
end)

pcall(function()
	RemoteEvents.GetReliable("MatchPhaseTransition").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then return end
		if data.phase == "Match" or data.phase == "InGame" then
			AgentSelectUI.Hide()
			handleTransitionToMatch()
		elseif data.phase == "Lobby" then
			AgentSelectUI.Hide()
			handleTransitionToLobby()
		elseif data.phase == "PracticeRange" then
			LobbyTransitionController.TransitionToMatch(1.0, function()
				setMode("Practice")
			end)
		elseif data.phase == "AgentSelect" then
			AgentSelectUI.Show(data.mode)
		end
	end)
end)

-- Equip weapon remote listener (Practice Range / Server requests)
pcall(function()
	RemoteEvents.GetReliable("EquipWeapon").OnClientEvent:Connect(function(weaponId: any)
		if typeof(weaponId) == "string" then
			WeaponController.EquipWeapon(weaponId)
		end
	end)
end)

-- Ammo resupply remote listener (Practice Range ammo station)
pcall(function()
	RemoteEvents.GetReliable("ResupplyAmmo").OnClientEvent:Connect(function()
		WeaponController.ResupplyAmmo()
	end)
end)

-- Switch operative remote listener
pcall(function()
	RemoteEvents.GetReliable("SwitchOperative").OnClientEvent:Connect(function(opId: any)
		if typeof(opId) == "string" then
			OperativeController.SelectOperative(opId)
		end
	end)
end)

-- Queue events
pcall(function()
	local voteRemote = QueueEvents.GetRemoteEvent("MapVoteUpdate")
	voteRemote.OnClientEvent:Connect(function(result: any)
		if typeof(result) == "table" and result.votingEnded and result.winningMap then
			task.delay(1.5, function() handleTransitionToMatch() end)
		end
	end)
end)

pcall(function()
	local challengeRemote = ChallengeEvents.GetRemoteEvent("ChallengeRespond")
	challengeRemote.OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and data.accepted then
			local myId = localPlayer.UserId
			if data.challengerUserId == myId or data.targetUserId == myId then
				task.delay(0.5, function() handleTransitionToMatch() end)
			end
		end
	end)
end)

-- Leave practice range
pcall(function()
	RemoteEvents.GetReliable("LeavePracticeRange").OnClientEvent:Connect(function()
		handleTransitionToLobby()
	end)
end)

-- 5. Input Listeners (Desktop)
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if currentMode ~= "Match" and currentMode ~= "Practice" then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		WeaponController.StartFiring()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		WeaponController.SetAiming(true)
	elseif input.KeyCode == Enum.KeyCode.R then
		WeaponController.ReloadWeapon()
	elseif input.KeyCode == Enum.KeyCode.B and currentMode == "Match" then
		if BuyMenuController.IsVisible() then BuyMenuController.Hide() else BuyMenuController.Show() end
	elseif input.KeyCode == Enum.KeyCode.Q then
		OperativeController.UseAbility("Basic")
	elseif input.KeyCode == Enum.KeyCode.E then
		OperativeController.UseAbility("Paid")
	elseif input.KeyCode == Enum.KeyCode.X then
		OperativeController.UseAbility("Ultimate")
	elseif input.KeyCode == Enum.KeyCode.One then
		WeaponController.EquipWeapon("Pistol")
	elseif input.KeyCode == Enum.KeyCode.Two then
		WeaponController.EquipWeapon("AssaultRifle")
	elseif input.KeyCode == Enum.KeyCode.Three then
		WeaponController.EquipWeapon("SniperRifle")
	elseif input.KeyCode == Enum.KeyCode.Four then
		WeaponController.EquipWeapon("Shotgun")
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		WeaponController.StopFiring()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		WeaponController.SetAiming(false)
	end
end)

-- 6. Mobile Controls (FPSMovementController owns crouch/sprint/jump/slide)
if isMobile then
	MobileControlsController.BindCombatActions({
		onFire = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			if state == Enum.UserInputState.Begin then WeaponController.StartFiring()
			elseif state == Enum.UserInputState.End then WeaponController.StopFiring() end
			return Enum.ContextActionResult.Success
		end,
		onReload = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			if state == Enum.UserInputState.Begin then WeaponController.ReloadWeapon() end
			return Enum.ContextActionResult.Success
		end,
		onAim = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			if state == Enum.UserInputState.Begin then WeaponController.SetAiming(true)
			elseif state == Enum.UserInputState.End then WeaponController.SetAiming(false) end
			return Enum.ContextActionResult.Success
		end,
		onCrouch = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			FPSMovementController.SetMobileAction("Crouch", state)
			return Enum.ContextActionResult.Success
		end,
		onJump = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			FPSMovementController.SetMobileAction("Jump", state)
			return Enum.ContextActionResult.Success
		end,
		onSprint = function(_, state)
			if currentMode ~= "Match" and currentMode ~= "Practice" then return Enum.ContextActionResult.Pass end
			FPSMovementController.SetMobileAction("Sprint", state)
			return Enum.ContextActionResult.Success
		end,
	})
	-- Start with combat hidden (lobby mode)
	MobileControlsController.SetCombatVisible(false)
	MobileControlsController.SetMenuButtonVisible(true)
end

-- 7. Render Loop
RunService.RenderStepped:Connect(function(dt: number)
	if currentMode == "Match" or currentMode == "Practice" then
		-- AnimationController.Update(dt)
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Custom then
			local camOffset = AnimationController.GetCameraOffset()
			camera.CFrame = camera.CFrame * camOffset
		end

		local state = WeaponController.GetState()
		local activeStats = WeaponController.GetActiveStats()
		if state and activeStats then
			HUDController.UpdateAmmo(state.currentAmmo, state.reserveAmmo, activeStats.displayName)
		end
		if camera then
			local lookVector = camera.CFrame.LookVector
			local headingRad = math.atan2(-lookVector.X, -lookVector.Z)
			HUDController.UpdateCompass(math.deg(headingRad))
		end
	end
end)

-- 8. Character lifecycle
local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	AnimationController.UpdateMovementState(humanoid)
	humanoid.Running:Connect(function()
		AnimationController.UpdateMovementState(humanoid)
	end)
end

if localPlayer.Character then onCharacterAdded(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- 9. Listen for BulletTracer events from other players
pcall(function()
	RemoteEvents.GetUnreliable("BulletTracer").OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and data.shooterId ~= localPlayer.UserId then
			if typeof(data.origin) == "Vector3" and typeof(data.direction) == "Vector3" then
				WeaponController.RenderExternalTracer(data.origin, data.direction)
			end
		end
	end)
end)

-- Bot FireWeapon visuals (fix dropped 128 events) + MovementIntent ack (silence dropped intent)
pcall(function()
	RemoteEvents.GetUnreliable("FireWeapon").OnClientEvent:Connect(function(botId: any, origin: any, dir: any, weaponId: any)
		if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
			WeaponController.RenderExternalTracer(origin, dir)
		end
	end)
end)
pcall(function()
	-- MovementIntent is server-only; client just needs listener to avoid Studio "did you forget OnClientEvent?" spam if server ever echoes; silence it
	local mi = RemoteEvents.GetUnreliable("MovementIntent")
	if mi then mi.OnClientEvent:Connect(function() end) end
end)

print("[ClientMain] OVERCLOCK Client Ready!")
