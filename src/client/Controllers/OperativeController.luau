--!strict
--[=[
    Project OVERCLOCK: Client Operative Controller
    Manages keybindings (E, C, X), placement preview gizmos for deployable abilities,
    instant agent selection for Practice Range, client-side particle/visual replication,
    enemy highlight outlines (wallhacks), and HUD state getters.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local OperativeStats = require(DataFolder:WaitForChild("OperativeStats") :: any)

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local RemoteEvents = require(NetworkFolder:WaitForChild("RemoteEvents") :: any)

type AbilitySlot = OperativeStats.AbilitySlot
type OperativeData = OperativeStats.OperativeData
type AbilityData = OperativeStats.AbilityData

local OperativeController = {}

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

-- Client-side state prediction & sync
local currentOperativeId = "Vex"
local ultCharge = 0
local cooldownRemaining = {
	Basic = 0,
	Paid = 0,
	Ultimate = 0,
}
local isSilenced = false
local overshieldAmount = 0
local damageReductionAmount = 0

local activeVFX: { BasePart } = {}

-- Placement Preview Gizmo state
local isPreviewActive = false
local pendingSlot: AbilitySlot? = nil
local previewGizmo: BasePart? = nil
local renderConnection: RBXScriptConnection? = nil

-- List of deployable abilities that require placement preview
local DEPLOYABLE_ABILITIES: { [string]: { size: Vector3, color: Color3, shape: Enum.PartType? } } = {
	Vex_Trap = { size = Vector3.new(4, 0.4, 4), color = Color3.fromRGB(255, 170, 0) },
	Warden_Wall = { size = Vector3.new(12, 8, 1), color = Color3.fromRGB(0, 170, 255) },
	Fray_Smoke = { size = Vector3.new(15, 15, 15), color = Color3.fromRGB(180, 180, 200), shape = Enum.PartType.Ball },
	Choke_Static = { size = Vector3.new(12, 6, 12), color = Color3.fromRGB(180, 100, 255), shape = Enum.PartType.Cylinder },
	Choke_Incendiary = { size = Vector3.new(10, 0.4, 10), color = Color3.fromRGB(255, 60, 0) },
	Choke_Zero = { size = Vector3.new(30, 2, 30), color = Color3.fromRGB(100, 220, 255), shape = Enum.PartType.Cylinder },
	Pulse_Beacon = { size = Vector3.new(1.5, 1.5, 1.5), color = Color3.fromRGB(255, 220, 0) },
	Bastion_Turret = { size = Vector3.new(3, 4, 3), color = Color3.fromRGB(220, 50, 50) },
	Bastion_Mine = { size = Vector3.new(2, 0.4, 2), color = Color3.fromRGB(255, 100, 0) },
}

--- Returns currently selected Operative statistics
function OperativeController.GetSelectedOperative(): OperativeData?
	return OperativeStats.Get(currentOperativeId)
end

--- Returns current ultimate charge percentage (0-100)
function OperativeController.GetUltCharge(): number
	return ultCharge
end

--- Returns remaining cooldown seconds for given ability slot
function OperativeController.GetCooldownRemaining(slot: AbilitySlot): number
	return cooldownRemaining[slot] or 0
end

--- Returns whether local player is silenced by EMP
function OperativeController.IsSilenced(): boolean
	return isSilenced
end

--- Selects an operative on demand (Practice Range or Lobby)
function OperativeController.SelectOperative(opId: string)
	local opData = OperativeStats.Get(opId)
	if not opData then
		return
	end

	currentOperativeId = opId
	pcall(function()
		local selectRemote = RemoteEvents.GetReliable("SelectAgent" :: any)
		if selectRemote then
			selectRemote:FireServer(opId)
		end
	end)
end

--- Cancels placement preview gizmo
function OperativeController.CancelPreview()
	isPreviewActive = false
	pendingSlot = nil

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if previewGizmo then
		previewGizmo:Destroy()
		previewGizmo = nil
	end
end

--- Gets raycast ground target position for placement preview
local function getTargetCFrame(): CFrame
	local camera = Workspace.CurrentCamera
	if not camera then
		return CFrame.new(mouse.Hit.Position)
	end

	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local rayParams = RaycastParams.new()
	if localPlayer.Character then
		rayParams.FilterDescendantsInstances = { localPlayer.Character }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
	end

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 200, rayParams)
	if result then
		return CFrame.new(result.Position, result.Position + unitRay.Direction)
	else
		local targetPos = unitRay.Origin + (unitRay.Direction * 30)
		return CFrame.new(targetPos)
	end
end

--- Starts placement preview mode for deployables
local function startPreview(slot: AbilitySlot, abilityData: AbilityData)
	OperativeController.CancelPreview()

	local deploySpec = DEPLOYABLE_ABILITIES[abilityData.id]
	if not deploySpec then
		-- Fallback gizmo spec if not defined explicitly
		deploySpec = { size = Vector3.new(4, 4, 4), color = Color3.fromRGB(0, 255, 200) }
	end

	isPreviewActive = true
	pendingSlot = slot

	local gizmo = Instance.new("Part")
	gizmo.Name = "AbilityPlacementGizmo"
	gizmo.Size = deploySpec.size
	gizmo.Color = deploySpec.color
	gizmo.Material = Enum.Material.Neon
	gizmo.Transparency = 0.5
	gizmo.Anchored = true
	gizmo.CanCollide = false
	if deploySpec.shape then
		gizmo.Shape = deploySpec.shape
	end
	gizmo.Parent = Workspace
	previewGizmo = gizmo

	renderConnection = RunService.RenderStepped:Connect(function()
		if not isPreviewActive or not previewGizmo then
			return
		end
		local cf = getTargetCFrame()
		previewGizmo.CFrame = cf
	end)
end

--- Triggers an ability execution by slot
function OperativeController.UseAbility(slot: AbilitySlot)
	if isSilenced then
		return
	end

	local opData = OperativeController.GetSelectedOperative()
	if not opData then
		return
	end

	local abilityData = opData.abilities[slot]
	if not abilityData then
		return
	end

	-- If on cooldown, ignore
	if (cooldownRemaining[slot] or 0) > 0 then
		return
	end

	-- Check if ability is a deployable requiring placement preview
	if DEPLOYABLE_ABILITIES[abilityData.id] then
		if not isPreviewActive or pendingSlot ~= slot then
			startPreview(slot, abilityData)
			return
		end
	end

	-- Confirm and fire ability request to server
	local targetCF = getTargetCFrame()
	OperativeController.CancelPreview()

	pcall(function()
		local useRemote = RemoteEvents.GetReliable("UseAbility" :: any)
		if useRemote then
			useRemote:FireServer(slot, targetCF)
		end
	end)
end

--- Confirms current pending placement preview
local function confirmPlacement()
	if isPreviewActive and pendingSlot then
		local slot = pendingSlot
		local targetCF = getTargetCFrame()
		OperativeController.CancelPreview()

		pcall(function()
			local useRemote = RemoteEvents.GetReliable("UseAbility" :: any)
			if useRemote then
				useRemote:FireServer(slot, targetCF)
			end
		end)
	end
end

--- Replicates visual effects locally for triggered abilities
local function handleAbilityReplicated(data: any)
	if typeof(data) ~= "table" or not data.abilityId then
		return
	end

	local abilityId = data.abilityId
	local targetCF = data.targetCFrame or CFrame.new()

	if abilityId == "Vex_EMP" then
		-- Expanding EMP shockwave effect
		local empPart = Instance.new("Part")
		empPart.Name = "EMP_Visual"
		empPart.Shape = Enum.PartType.Ball
		empPart.Size = Vector3.new(2, 2, 2)
		empPart.CFrame = targetCF
		empPart.Color = Color3.fromRGB(0, 220, 255)
		empPart.Material = Enum.Material.Neon
		empPart.Transparency = 0.2
		empPart.Anchored = true
		empPart.CanCollide = false
		empPart.Parent = Workspace

		local tweenInfo = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(empPart, tweenInfo, {
			Size = Vector3.new(70, 70, 70),
			Transparency = 1,
		})
		tween:Play()
		Debris:AddItem(empPart, 0.7)
		table.insert(activeVFX, empPart)

	elseif abilityId == "Fray_Blink" then
		-- Dash particle line / trail effect
		local dashPart = Instance.new("Part")
		dashPart.Size = Vector3.new(0.5, 0.5, 25)
		dashPart.CFrame = targetCF
		dashPart.Color = Color3.fromRGB(255, 255, 255)
		dashPart.Material = Enum.Material.Neon
		dashPart.Transparency = 0.3
		dashPart.Anchored = true
		dashPart.CanCollide = false
		dashPart.Parent = Workspace

		TweenService:Create(dashPart, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(dashPart, 0.4)
		table.insert(activeVFX, dashPart)

	elseif abilityId == "Choke_Static" then
		-- Static field visual energy cloud
		local staticPart = Instance.new("Part")
		staticPart.Shape = Enum.PartType.Cylinder
		staticPart.Size = Vector3.new(12, 24, 24)
		staticPart.CFrame = targetCF * CFrame.Angles(0, 0, math.rad(90))
		staticPart.Color = Color3.fromRGB(180, 100, 255)
		staticPart.Material = Enum.Material.Neon
		staticPart.Transparency = 0.6
		staticPart.Parent = Workspace

		Debris:AddItem(staticPart, 7)
		table.insert(activeVFX, staticPart)
	end
end

--- Attaches temporary highlight outline (wallhack effect)
local function handleEnemyRevealed(data: any)
	if typeof(data) ~= "table" then
		return
	end

	local targetChar = data.targetCharacter :: Model?
	local duration = data.duration or 3
	local color = data.outlineColor or Color3.fromRGB(255, 50, 50)

	if targetChar and targetChar:IsA("Model") then
		local existing = targetChar:FindFirstChild("RevealHighlight")
		if existing then
			existing:Destroy()
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "RevealHighlight"
		highlight.FillColor = color
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.5
		highlight.OutlineTransparency = 0.0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = targetChar
		highlight.Parent = targetChar

		Debris:AddItem(highlight, duration)
	end
end

--- Initializes client input bindings and remote event listeners
function OperativeController.Init()
	local function clearVFX()
		for _, vfx in activeVFX do
			if vfx.Parent then
				vfx:Destroy()
			end
		end
		table.clear(activeVFX)
	end

	localPlayer.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid")
		hum.Died:Connect(clearVFX)
	end)
	if localPlayer.Character then
		local hum = localPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.Died:Connect(clearVFX)
		end
	end

	-- 1. State Sync Listener
	pcall(function()
		local syncRemote = RemoteEvents.GetReliable("OperativeStateSync" :: any)
		if syncRemote then
			syncRemote.OnClientEvent:Connect(function(data: any)
				if typeof(data) == "table" then
					if data.selectedOperative then
						currentOperativeId = data.selectedOperative
					end
					if type(data.ultCharge) == "number" then
						ultCharge = data.ultCharge
					end
					if typeof(data.cooldowns) == "table" then
						cooldownRemaining.Basic = data.cooldowns.Basic or 0
						cooldownRemaining.Paid = data.cooldowns.Paid or 0
						cooldownRemaining.Ultimate = data.cooldowns.Ultimate or 0
					end
					if type(data.isSilenced) == "boolean" then
						isSilenced = data.isSilenced
					end
				end
			end)
		end

		local repRemote = RemoteEvents.GetReliable("AbilityReplicated" :: any)
		if repRemote then
			repRemote.OnClientEvent:Connect(handleAbilityReplicated)
		end

		local revealRemote = RemoteEvents.GetReliable("EnemyRevealed" :: any)
		if revealRemote then
			revealRemote.OnClientEvent:Connect(handleEnemyRevealed)
		end
	end)

	-- 2. Local Cooldown Decay Loop
	RunService.RenderStepped:Connect(function(dt: number)
		if cooldownRemaining.Basic > 0 then
			cooldownRemaining.Basic = math.max(0, cooldownRemaining.Basic - dt)
		end
		if cooldownRemaining.Paid > 0 then
			cooldownRemaining.Paid = math.max(0, cooldownRemaining.Paid - dt)
		end
		if cooldownRemaining.Ultimate > 0 then
			cooldownRemaining.Ultimate = math.max(0, cooldownRemaining.Ultimate - dt)
		end
	end)

	-- 3. Input Key Bindings (E -> Basic, C -> Paid, X -> Ultimate)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isPreviewActive then
				confirmPlacement()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if isPreviewActive then
				OperativeController.CancelPreview()
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			if isPreviewActive then
				OperativeController.CancelPreview()
			end
		elseif input.KeyCode == Enum.KeyCode.E then
			OperativeController.UseAbility("Basic")
		elseif input.KeyCode == Enum.KeyCode.C then
			OperativeController.UseAbility("Paid")
		elseif input.KeyCode == Enum.KeyCode.X then
			OperativeController.UseAbility("Ultimate")
		end
	end)

	print("[OperativeController] Initialized successfully.")
end

return OperativeController
