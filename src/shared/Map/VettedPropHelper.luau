--!strict
-- src/shared/Map/VettedPropHelper.luau
-- Shared vetted pipeline helpers — cloning from ServerStorage.Templates.VettedProps
-- and applying dressing properties per roblox-asset-audit hard-cover rule.
-- 8 vetted IDs: LowPolyTree 10355960847, LowPolyTreePack 4870769649, LowPolyRocks 6562523344,
--   WoodenBox02 430288318, LowPolyBarrel 4204999283, SciFiContainer 13679876057, EnergyRifleVisual 443695083, TankBotVisual 7198227425
-- Hard-cover pairing: WeaponRay (Map) vs ProjectileRay vs Decoration filtering; mesh Decoration CanQuery=false, blocker Map CanQuery=true

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local VettedPropHelper = {}

local AssetRegistry: any = nil
pcall(function()
	AssetRegistry = require(ReplicatedStorage:WaitForChild("AssetRegistry", 2) :: any)
end)
if not AssetRegistry then
	pcall(function()
		AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared", 2):WaitForChild("AssetRegistry", 2) :: any)
	end)
end

function VettedPropHelper.GetAssetRecord(assetKey: string): any
	if AssetRegistry and AssetRegistry[assetKey] then
		return AssetRegistry[assetKey]
	end
	return nil
end

function VettedPropHelper.GetVettedPropsFolder(): Folder?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local vp = templates:FindFirstChild("VettedProps")
	if vp and vp:IsA("Folder") then return vp :: Folder end
	return nil
end

-- Clone a vetted template by assetKey or numeric id string. Returns nil if not staged => zero-art fallback.
function VettedPropHelper.CloneVetted(assetKey: string): Instance?
	local vp = VettedPropHelper.GetVettedPropsFolder()
	if not vp then return nil end
	local byKey = vp:FindFirstChild(assetKey)
	if byKey then
		return byKey:Clone()
	end
	local rec = VettedPropHelper.GetAssetRecord(assetKey)
	if rec and rec.id then
		local byId = vp:FindFirstChild(tostring(rec.id))
		if byId then return byId:Clone() end
		-- Some templates may be stored under sanitized name but preserve id attribute
		for _, child in vp:GetChildren() do
			if child:GetAttribute("SourceAssetId") == rec.id then
				return child:Clone()
			end
		end
	end
	return nil
end

-- Apply dressing properties per AssetRegistry role.
-- Decoration: CanQuery=false, CollisionGroup=Decoration, CanCollide=false
-- HardCover: mesh is decoration (CanQuery=false, Decoration) paired with invisible blocker (Map, CanQuery=true)
-- WeaponVisual / EnemyVisual: decoration dressing (CanQuery=false)
function VettedPropHelper.ApplyVisualProps(inst: Instance, assetKey: string)
	local rec = VettedPropHelper.GetAssetRecord(assetKey)
	local role = rec and rec.role or "Decoration"
	local isHardCover = role == "HardCover"
	local isDecoration = role == "Decoration"

	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CollisionGroup = "Decoration"
			if isHardCover then
				-- Hard-cover dressing stays decoration and does NOT block ray; blocker owns WeaponRay
				d.CanQuery = false
				d:SetAttribute("IsHardCoverVisual", true)
			else
				d.CanQuery = false
				d:SetAttribute("IsDecoration", true)
			end
		end
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CollisionGroup = "Decoration"
		if isHardCover then
			(inst :: BasePart).CanQuery = false
			inst:SetAttribute("IsHardCoverVisual", true)
		else
			(inst :: BasePart).CanQuery = false
			inst:SetAttribute("IsDecoration", true)
		end
	end
	-- Preserve vetted tag + map prop for analytics, not for ray filtering
	pcall(function()
		CollectionService:AddTag(inst, "VettedAsset")
		CollectionService:AddTag(inst, "MapProp")
	end)
end

-- Create invisible primitive collision owner for hard-cover (handoff §6.4: Map, CanQuery=true, BulletBlocker tag)
function VettedPropHelper.MakeInvisibleBlocker(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.Transparency = 1
	p.Color = Color3.fromRGB(90, 90, 90)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Map"
	p.Parent = parent
	pcall(function()
		CollectionService:AddTag(p, "BulletBlocker")
		CollectionService:AddTag(p, "MapProp")
	end)
	return p
end

-- Create a non-blocking decoration pad (for trees/rocks/weapon/bot visuals that should not block WeaponRay)
function VettedPropHelper.MakeDecorationPad(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CollisionGroup = "Decoration"
	p.Parent = parent
	pcall(function()
		CollectionService:AddTag(p, "MapProp")
	end)
	return p
end

-- Attempt to clone and place a vetted visual at blocker/parent CFrame. Returns cloned instance or nil (fallback-safe).
function VettedPropHelper.PlaceVisualAt(parent: Instance, assetKey: string, cframe: CFrame, offset: Vector3?): Instance?
	local vis = VettedPropHelper.CloneVetted(assetKey)
	if not vis then return nil end
	local cf = cframe
	if offset then cf += offset end
	if vis:IsA("Model") then
		pcall(function() (vis :: Model):PivotTo(cf) end)
		vis.Parent = parent
	elseif vis:IsA("BasePart") then
		(vis :: BasePart).CFrame = cf
		vis.Parent = parent
	else
		-- Unknown instance (Folder etc), try pivot then parent
		pcall(function() (vis :: any):PivotTo(cf) end)
		vis.Parent = parent
	end
	VettedPropHelper.ApplyVisualProps(vis, assetKey)
	return vis
end

return VettedPropHelper
