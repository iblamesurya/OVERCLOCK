--!strict
-- src/server/Services/VettedPropService.luau
-- Server-authoritative vetted pipeline: ScratchAssetAudit -> audit -> sanitize -> ServerStorage.Templates.VettedProps
-- Implements roblox-asset-audit §4 sanitization + roblox-asset-audit template rules.
-- 8 vetted IDs: LowPolyTree 10355960847, LowPolyTreePack 4870769649, LowPolyRocks 6562523344,
--   WoodenBox02 430288318, LowPolyBarrel 4204999283, SciFiContainer 13679876057, EnergyRifleVisual 443695083, TankBotVisual 7198227425
-- Pipeline: Workspace.ScratchAssetAudit -> AuditAsset.Audit() -> sanitize (strip scripts/remotes) -> VettedProps with SourceAssetId/SourceUrl/Creator/VettedDate/AuditReport -> VettedPropSlots

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local AssetRegistry: any = nil
pcall(function()
	AssetRegistry = require(ReplicatedStorage:WaitForChild("AssetRegistry", 2) :: any)
end)
if not AssetRegistry then
	pcall(function()
		AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared", 2):WaitForChild("AssetRegistry", 2) :: any)
	end)
end

local VettedPropService = {}

type AuditReport = {
	candidate: string,
	class: string,
	totals: { parts: number, scripts: number, remotes: number, constraints: number, unknownExecutables: number },
	code: { string },
	remotes: { string },
	constraints: { string },
	parts: { any },
	reviewRequired: { string },
}

local FORBIDDEN_CLASS = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
	Tool = true,
	HopperBin = true,
}

local function getScratch(): Folder?
	return Workspace:FindFirstChild("ScratchAssetAudit") :: Folder?
end

local function getVettedPropsFolder(): Folder
	local templates = ServerStorage:FindFirstChild("Templates") :: Folder?
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "Templates"
		templates.Parent = ServerStorage
	end
	local vp = templates:FindFirstChild("VettedProps")
	if not vp then
		vp = Instance.new("Folder")
		vp.Name = "VettedProps"
		vp.Parent = templates
	end
	return vp :: Folder
end

-- Generate audit report for a candidate (mirrors AuditAsset.luau logic)
function VettedPropService.Audit(candidate: Instance): AuditReport
	local report: AuditReport = {
		candidate = candidate.Name,
		class = candidate.ClassName,
		totals = { parts = 0, scripts = 0, remotes = 0, constraints = 0, unknownExecutables = 0 },
		code = {},
		remotes = {},
		constraints = {},
		parts = {},
		reviewRequired = {},
	}

	for _, object in candidate:GetDescendants() do
		if object:IsA("BasePart") then
			report.totals.parts += 1
			table.insert(report.parts, {
				path = object:GetFullName(),
				class = object.ClassName,
				anchored = (object :: BasePart).Anchored,
				canCollide = (object :: BasePart).CanCollide,
				canTouch = (object :: BasePart).CanTouch,
				canQuery = (object :: BasePart).CanQuery,
				collisionGroup = (object :: BasePart).CollisionGroup,
				size = { (object :: BasePart).Size.X, (object :: BasePart).Size.Y, (object :: BasePart).Size.Z },
			})
		elseif object:IsA("Script") or object:IsA("LocalScript") or object:IsA("ModuleScript") then
			report.totals.scripts += 1
			table.insert(report.code, object:GetFullName())
		elseif object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then
			report.totals.remotes += 1
			table.insert(report.remotes, object:GetFullName())
		elseif object:IsA("Constraint") or object:IsA("BodyMover") or object:IsA("VectorForce") then
			report.totals.constraints += 1
			table.insert(report.constraints, object:GetFullName())
		elseif FORBIDDEN_CLASS[object.ClassName] then
			report.totals.unknownExecutables += 1
			table.insert(report.reviewRequired, object:GetFullName() .. " (" .. object.ClassName .. ")")
		end
	end
	-- Also check candidate itself if it's a BasePart
	if candidate:IsA("BasePart") then
		-- Already counted descendants only; count candidate if needed but spec counts descendants.
		-- Ensure at least parts =1 for single MeshPart candidates
		if report.totals.parts == 0 then
			report.totals.parts = 1
			table.insert(report.parts, {
				path = candidate:GetFullName(),
				class = candidate.ClassName,
				anchored = (candidate :: BasePart).Anchored,
				canCollide = (candidate :: BasePart).CanCollide,
				canTouch = (candidate :: BasePart).CanTouch,
				canQuery = (candidate :: BasePart).CanQuery,
				collisionGroup = (candidate :: BasePart).CollisionGroup,
				size = { (candidate :: BasePart).Size.X, (candidate :: BasePart).Size.Y, (candidate :: BasePart).Size.Z },
			})
		end
	end

	if report.totals.scripts > 0 then
		table.insert(report.reviewRequired, "REJECT by default: executable code is present.")
	end
	if report.totals.remotes > 0 then
		table.insert(report.reviewRequired, "REJECT by default: network remote is present.")
	end
	if report.totals.constraints > 0 then
		table.insert(report.reviewRequired, "REVIEW: physical constraints/forces are present.")
	end
	if report.totals.parts == 0 then
		table.insert(report.reviewRequired, "REVIEW: no BasePart descendants were found.")
	end
	return report
end

-- Sanitize a cloned candidate for use as vetted template.
-- Strips scripts/remotes/constraints/forces, anchors, sets collision, tags, attributes.
function VettedPropService.Sanitize(candidate: Instance, assetKey: string, auditReport: AuditReport?): Instance
	local clone = candidate:Clone()
	clone.Name = assetKey
	-- Strip forbidden descendants
	for _, obj in clone:GetDescendants() do
		if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
			obj:Destroy()
		elseif obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("BindableEvent") or obj:IsA("BindableFunction") then
			obj:Destroy()
		elseif obj:IsA("Tool") or obj:IsA("HopperBin") then
			obj:Destroy()
		elseif obj:IsA("Constraint") or obj:IsA("BodyMover") or obj:IsA("VectorForce") then
			-- Remove forces unless explicitly required (default reject)
			obj:Destroy()
		end
	end

	local rec = AssetRegistry and AssetRegistry[assetKey] or nil
	local role = rec and rec.role or "Decoration"
	-- Apply anchor / collision / query per role
	local function sanitizePart(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		if role == "HardCover" then
			part.CollisionGroup = "Decoration"
			part.CanQuery = false -- paired blocker will handle WeaponRay (Map)
			part:SetAttribute("IsHardCoverVisual", true)
		elseif role == "Decoration" then
			part.CollisionGroup = "Decoration"
			part.CanQuery = false
			part:SetAttribute("IsDecoration", true)
		elseif role == "WeaponVisual" or role == "EnemyVisual" then
			part.CollisionGroup = "Decoration"
			part.CanQuery = false
			part:SetAttribute("IsDecoration", true)
		else
			part.CollisionGroup = "Decoration"
			part.CanQuery = false
		end
	end

	if clone:IsA("BasePart") then
		sanitizePart(clone :: BasePart)
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			sanitizePart(d :: BasePart)
		end
	end

	pcall(function()
		CollectionService:AddTag(clone, "VettedAsset")
		CollectionService:AddTag(clone, "MapProp")
	end)

	-- Preserve source metadata as attributes on template
	if rec then
		clone:SetAttribute("SourceAssetId", rec.id)
		clone:SetAttribute("SourceUrl", rec.url)
		clone:SetAttribute("Creator", rec.creator)
	else
		local numericId = tonumber(assetKey)
		if numericId then
			clone:SetAttribute("SourceAssetId", numericId)
		end
	end
	clone:SetAttribute("VettedDate", os.date("!%Y-%m-%d"))
	if auditReport then
		local ok, json = pcall(function() return HttpService:JSONEncode(auditReport) end)
		if ok and json then
			-- Truncate if too large for attribute (max 1k)
			if #json > 900 then json = string.sub(json, 1, 900) end
			clone:SetAttribute("AuditReport", json)
		end
	end
	clone:SetAttribute("VettedBy", "VettedPropService")

	return clone
end

-- Stage the current Scratch candidate into VettedProps under assetKey.
-- Returns (template, report, decision) where decision is "sanitize" or "reject"
function VettedPropService.StageFromScratch(assetKey: string): (Instance?, AuditReport?, string)
	local scratch = getScratch()
	if not scratch then
		warn("[VettedPropService] Missing Workspace.ScratchAssetAudit")
		return nil, nil, "reject"
	end
	local candidate = scratch:FindFirstChildWhichIsA("Model") or scratch:FindFirstChildWhichIsA("MeshPart")
	-- Also try any instance (in case candidate is Folder)
	if not candidate then
		candidate = scratch:FindFirstChildWhichIsA("BasePart")
	end
	if not candidate then
		warn("[VettedPropService] No candidate in ScratchAssetAudit")
		return nil, nil, "reject"
	end
	local report = VettedPropService.Audit(candidate)
	-- Decision: reject if scripts or remotes or Tool present
	if report.totals.scripts > 0 or report.totals.remotes > 0 or report.totals.unknownExecutables > 0 then
		warn(string.format("[VettedPropService] REJECT %s: scripts=%d remotes=%d unknown=%d", assetKey, report.totals.scripts, report.totals.remotes, report.totals.unknownExecutables))
		return nil, report, "reject"
	end

	local sanitized = VettedPropService.Sanitize(candidate, assetKey, report)
	local vp = getVettedPropsFolder()
	-- Remove existing template with same name
	local existing = vp:FindFirstChild(assetKey)
	if existing then existing:Destroy() end
	-- Also remove by id if different name
	if AssetRegistry and AssetRegistry[assetKey] then
		local byId = vp:FindFirstChild(tostring(AssetRegistry[assetKey].id))
		if byId then byId:Destroy() end
	end
	sanitized.Parent = vp
	print(string.format("[VettedPropService] Sanitized %s -> ServerStorage.Templates.VettedProps/%s", assetKey, sanitized.Name))
	return sanitized, report, "sanitize"
end

-- Clone vetted template into a slot (fallback-safe)
function VettedPropService.CloneToSlot(assetKey: string, cframe: CFrame, parent: Instance, offset: Vector3?): Instance?
	local vp = getVettedPropsFolder()
	if not vp then return nil end
	local template = vp:FindFirstChild(assetKey)
	if not template and AssetRegistry and AssetRegistry[assetKey] then
		template = vp:FindFirstChild(tostring(AssetRegistry[assetKey].id))
		if not template then
			for _, child in vp:GetChildren() do
				if child:GetAttribute("SourceAssetId") == AssetRegistry[assetKey].id then
					template = child
					break
				end
			end
		end
	end
	if not template then return nil end
	local clone = template:Clone()
	local cf = cframe
	if offset then cf += offset end
	if clone:IsA("Model") then
		pcall(function() (clone :: Model):PivotTo(cf) end)
	elseif clone:IsA("BasePart") then
		(clone :: BasePart).CFrame = cf
	else
		pcall(function() (clone :: any):PivotTo(cf) end)
	end
	clone.Parent = parent
	return clone
end

return VettedPropService
