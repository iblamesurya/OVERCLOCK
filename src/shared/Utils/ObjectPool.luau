--!strict
--[=[
    Project OVERCLOCK: ObjectPool
    High-performance object pooling utility for Roblox instances.
    Pre-allocates reusable instances during loading to eliminate dynamic allocations
    (Instance.new / Destroy) during active gameplay.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type PoolResetCallback = (instance: Instance) -> ()
export type PoolGetCallback = (instance: Instance) -> ()

export type ObjectPoolConfig = {
	template: Instance | () -> Instance,
	initialSize: number,
	container: Instance?,
	resetHandler: PoolResetCallback?,
	getHandler: PoolGetCallback?,
}

export type ObjectPoolImpl = {
	__index: ObjectPoolImpl,
	new: (config: ObjectPoolConfig) -> ObjectPool,
	createHitmarkerPool: (initialSize: number?, container: Instance?) -> ObjectPool,
	createTracerPool: (initialSize: number?, container: Instance?) -> ObjectPool,
	Get: (self: ObjectPool) -> Instance,
	Return: (self: ObjectPool, instance: Instance) -> boolean,
	Preallocate: (self: ObjectPool, count: number) -> (),
	GetAvailableCount: (self: ObjectPool) -> number,
	GetTotalCount: (self: ObjectPool) -> number,
	GetInUseCount: (self: ObjectPool) -> number,
	Destroy: (self: ObjectPool) -> (),
}

export type ObjectPool = typeof(setmetatable(
	{} :: {
		_template: Instance | () -> Instance,
		_container: Instance,
		_available: { Instance },
		_inUse: { [Instance]: boolean },
		_totalCount: number,
		_resetHandler: PoolResetCallback?,
		_getHandler: PoolGetCallback?,
	},
	{} :: ObjectPoolImpl
))

local ObjectPool = {} :: ObjectPoolImpl
ObjectPool.__index = ObjectPool

local defaultContainerFolder: Folder? = nil

local function getDefaultContainer(): Folder
	if not defaultContainerFolder then
		local folder = Instance.new("Folder")
		folder.Name = "ObjectPoolContainer"
		folder.Parent = ReplicatedStorage
		defaultContainerFolder = folder
	end
	return defaultContainerFolder :: Folder
end

function ObjectPool.new(templateOrConfig: any, initialSizeParam: number?, containerParam: Instance?): ObjectPool
	local template: Instance | () -> Instance
	local initialSize: number
	local container: Instance
	local resetHandler: ((item: Instance) -> ())?
	local getHandler: ((item: Instance) -> ())?

	if typeof(templateOrConfig) == "Instance" or type(templateOrConfig) == "function" then
		template = templateOrConfig
		initialSize = initialSizeParam or 10
		container = containerParam or getDefaultContainer()
	elseif type(templateOrConfig) == "table" then
		template = templateOrConfig.template
		initialSize = templateOrConfig.initialSize or 10
		container = templateOrConfig.container or getDefaultContainer()
		resetHandler = templateOrConfig.resetHandler
		getHandler = templateOrConfig.getHandler
	else
		error("[ObjectPool] Invalid arguments provided to ObjectPool.new")
	end

	local self = setmetatable({
		_template = template,
		_container = container,
		_available = {},
		_inUse = {},
		_totalCount = 0,
		_resetHandler = resetHandler,
		_getHandler = getHandler,
	}, ObjectPool)

	if initialSize > 0 then
		self:Preallocate(initialSize)
	end

	return self :: ObjectPool
end

function ObjectPool.Preallocate(self: ObjectPool, count: number)
	for _ = 1, count do
		local inst: Instance
		if typeof(self._template) == "function" then
			inst = (self._template :: () -> Instance)()
		else
			inst = (self._template :: Instance):Clone()
		end

		if self._resetHandler then
			self._resetHandler(inst)
		else
			if inst:IsA("LayerCollector") then
				(inst :: any).Enabled = false
			elseif inst:IsA("GuiObject") then
				(inst :: any).Visible = false
			end
		end
		inst.Parent = self._container

		table.insert(self._available, inst)
		self._totalCount += 1
	end
end

function ObjectPool.Get(self: ObjectPool): Instance
	local inst: Instance
	if #self._available > 0 then
		inst = table.remove(self._available, #self._available) :: Instance
	else
		if typeof(self._template) == "function" then
			inst = (self._template :: () -> Instance)()
		else
			inst = (self._template :: Instance):Clone()
		end
		self._totalCount += 1
	end

	self._inUse[inst] = true

	if self._getHandler then
		self._getHandler(inst)
	else
		-- Default activation
		if inst:IsA("BasePart") then
			inst.Parent = workspace
		end
		if inst:IsA("LayerCollector") then
			(inst :: any).Enabled = true
		elseif inst:IsA("GuiObject") then
			(inst :: any).Visible = true
		end
	end

	return inst
end

function ObjectPool.Return(self: ObjectPool, instance: Instance): boolean
	if not self._inUse[instance] then
		return false
	end

	self._inUse[instance] = nil

	if self._resetHandler then
		self._resetHandler(instance)
	else
		-- Default deactivation
		if instance:IsA("BasePart") then
			instance.CFrame = CFrame.new(0, -1000, 0)
		end
		if instance:IsA("LayerCollector") then
			(instance :: any).Enabled = false
		elseif instance:IsA("GuiObject") then
			(instance :: any).Visible = false
		end
	end

	instance.Parent = self._container
	table.insert(self._available, instance)
	return true
end

function ObjectPool.GetAvailableCount(self: ObjectPool): number
	return #self._available
end

function ObjectPool.GetTotalCount(self: ObjectPool): number
	return self._totalCount
end

function ObjectPool.GetInUseCount(self: ObjectPool): number
	local count = 0
	for _ in self._inUse do
		count += 1
	end
	return count
end

function ObjectPool.createHitmarkerPool(initialSize: number?, container: Instance?): ObjectPool
	local size = initialSize or 30

	local function hitmarkerFactory(): Instance
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "HitmarkerBillboard"
		billboard.Size = UDim2.new(0, 40, 0, 40)
		billboard.AlwaysOnTop = true
		billboard.ResetOnSpawn = false
		billboard.Enabled = false

		local containerFrame = Instance.new("Frame")
		containerFrame.Name = "Container"
		containerFrame.Size = UDim2.new(1, 0, 1, 0)
		containerFrame.BackgroundTransparency = 1
		containerFrame.Parent = billboard

		local line1 = Instance.new("Frame")
		line1.Name = "Line1"
		line1.Size = UDim2.new(0, 14, 0, 2)
		line1.Position = UDim2.new(0.5, 0, 0.5, 0)
		line1.AnchorPoint = Vector2.new(0.5, 0.5)
		line1.Rotation = 45
		line1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line1.BorderSizePixel = 0
		line1.Parent = containerFrame

		local line2 = Instance.new("Frame")
		line2.Name = "Line2"
		line2.Size = UDim2.new(0, 14, 0, 2)
		line2.Position = UDim2.new(0.5, 0, 0.5, 0)
		line2.AnchorPoint = Vector2.new(0.5, 0.5)
		line2.Rotation = -45
		line2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line2.BorderSizePixel = 0
		line2.Parent = containerFrame

		return billboard
	end

	return ObjectPool.new({
		template = hitmarkerFactory,
		initialSize = size,
		container = container,
		resetHandler = function(inst: Instance)
			if inst:IsA("BillboardGui") then
				inst.Enabled = false
				inst.Adornee = nil
			end
		end,
		getHandler = function(inst: Instance)
			if inst:IsA("BillboardGui") then
				inst.Enabled = true
			end
		end,
	})
end

function ObjectPool.createTracerPool(initialSize: number?, container: Instance?): ObjectPool
	local size = initialSize or 50

	local function tracerFactory(): Instance
		local part = Instance.new("Part")
		part.Name = "BulletTracer"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new(0.1, 0.1, 4)
		part.Color = Color3.fromRGB(255, 220, 100)
		part.Transparency = 0
		return part
	end

	return ObjectPool.new({
		template = tracerFactory,
		initialSize = size,
		container = container,
		resetHandler = function(inst: Instance)
			if inst:IsA("BasePart") then
				inst.Transparency = 1
				inst.CFrame = CFrame.new(0, -9999, 0)
			end
		end,
		getHandler = function(inst: Instance)
			if inst:IsA("BasePart") then
				inst.Transparency = 0
			end
		end,
	})
end

function ObjectPool.Destroy(self: ObjectPool)
	for _, inst in self._available do
		inst:Destroy()
	end
	for inst in self._inUse do
		inst:Destroy()
	end
	table.clear(self._available)
	table.clear(self._inUse)
	self._totalCount = 0
end

return ObjectPool
