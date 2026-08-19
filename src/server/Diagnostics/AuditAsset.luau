-- tools/audit_asset.luau — ScratchAssetAudit -> audit report (never auto-approves)
-- Set `candidate` to the Model/MeshPart inserted into Workspace.ScratchAssetAudit.
-- Produces totals{parts,scripts,remotes,constraints}, lists code/remotes/constraints,
-- and per-part anchored/canCollide/canTouch/canQuery/collisionGroup/size.
-- Usage: Studio Command Bar / MCP execute_luau. Also requireable for tests.
-- 8 vetted leads (AssetRegistry): LowPolyTree 10355960847, LowPolyTreePack 4870769649, LowPolyRocks 6562523344,
--   WoodenBox02 430288318, LowPolyBarrel 4204999283, SciFiContainer 13679876057, EnergyRifleVisual 443695083, TankBotVisual 7198227425
-- Hard-cover pairing: mesh CanQuery=false/Decoration or CanQuery=true + BulletBlocker (Map), test WeaponRay vs ProjectileRay

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local AuditAsset = {}

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

function AuditAsset.Audit(candidate: Instance)
	assert(candidate, "AuditAsset.Audit: candidate is nil")
	local report = {
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
				anchored = object.Anchored,
				canCollide = object.CanCollide,
				canTouch = object.CanTouch,
				canQuery = object.CanQuery,
				collisionGroup = object.CollisionGroup,
				size = { object.Size.X, object.Size.Y, object.Size.Z },
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

	-- Handle single MeshPart candidate with no descendants (model case vs meshpart case)
	if candidate:IsA("BasePart") and report.totals.parts == 0 then
		-- Candidate is itself a MeshPart/Part with no descendants; count it as one part
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

-- Executable path: run when file is executed in Studio (not required as module)
local ranAsScript = false
pcall(function()
	local scratch = Workspace:WaitForChild("ScratchAssetAudit", 2)
	if scratch then
		local candidate = scratch:FindFirstChildWhichIsA("Model") or scratch:FindFirstChildWhichIsA("MeshPart") or scratch:FindFirstChildWhichIsA("BasePart")
		if candidate and debug.info(2, "s") == "[C]" then
			-- Heuristic: if we're the main chunk, run audit
			ranAsScript = false
		end
	end
end)

-- If Workspace.ScratchAssetAudit has a candidate and we're not being required, auto-print.
-- This preserves the original tool behavior when executed via Command Bar / execute_luau.
if not ranAsScript then
	local ok, scratch = pcall(function() return Workspace:WaitForChild("ScratchAssetAudit", 1) end)
	if ok and scratch then
		local candidate = scratch:FindFirstChildWhichIsA("Model") or scratch:FindFirstChildWhichIsA("MeshPart") or scratch:FindFirstChildWhichIsA("BasePart")
		if candidate then
			local report = AuditAsset.Audit(candidate)
			print(HttpService:JSONEncode(report))
			print("Audit rule: approve only after a human/agent verifies creator, permission, license, source URL, visual scale, script/remotes absence, collision/query settings, and performance.")
		end
	end
end

return AuditAsset
