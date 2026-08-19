--!strict
--[=[
    Project OVERCLOCK: Operative Statistics Registry
    Centralized data module defining Operative rosters, roles, ability stats,
    cooldowns, credit costs, and visual assets.
]=]

export type OperativeRole = "Intel" | "Defense" | "Mobility" | "Area Denial"
export type AbilitySlot = "Basic" | "Paid" | "Ultimate"

export type AbilityData = {
	id: string,
	name: string,
	slot: AbilitySlot,
	description: string,
	cooldown: number, -- PvP cooldown in seconds
	creditCost: number, -- PvP credit cost (0 for Basic & Ult)
	iconAsset: string?,
	range: number?, -- Effective range in studs
	duration: number?, -- Active duration in seconds
	damage: number?, -- Base damage if applicable
	radius: number?, -- Area radius in studs
}

export type OperativeData = {
	id: string,
	name: string,
	role: OperativeRole,
	description: string,
	portraitAsset: string?,
	abilities: {
		Basic: AbilityData,
		Paid: AbilityData,
		Ultimate: AbilityData,
	},
}

local OperativeRegistry: { [string]: OperativeData } = {
	Vex = {
		id = "Vex",
		name = "Vex",
		role = "Intel",
		description = "Intel specialist capable of tagging targets through walls and disabling enemy technology.",
		abilities = {
			Basic = {
				id = "Vex_Dart",
				name = "Tracking Dart",
				slot = "Basic",
				description = "Fires a high-velocity dart that tags hit enemies, revealing their outline through walls for 5s.",
				cooldown = 20,
				creditCost = 0,
				range = 200,
				duration = 5,
			},
			Paid = {
				id = "Vex_Trap",
				name = "Shock Trap",
				slot = "Paid",
				description = "Places a proximity trap that shocks entering enemies for 40 damage and slows movement by 40% for 3s.",
				cooldown = 15,
				creditCost = 300,
				damage = 40,
				radius = 8,
				duration = 3,
			},
			Ultimate = {
				id = "Vex_EMP",
				name = "Null Void EMP",
				slot = "Ultimate",
				description = "Emits a 35-stud EMP shockwave that silences enemy abilities for 8s and destroys active deployables.",
				cooldown = 0,
				creditCost = 0,
				radius = 35,
				duration = 8,
			},
		},
	},

	Warden = {
		id = "Warden",
		name = "Warden",
		role = "Defense",
		description = "Defensive anchor skilled at fortifying sightlines and shielding allies.",
		abilities = {
			Basic = {
				id = "Warden_Wall",
				name = "Energy Wall",
				slot = "Basic",
				description = "Deploys a transparent energy barrier (300 HP, 10s) blocking bullets and vision.",
				cooldown = 25,
				creditCost = 0,
				duration = 10,
			},
			Paid = {
				id = "Warden_Fortify",
				name = "Fortify Barrier",
				slot = "Paid",
				description = "Grants +30 temporary Overshield for 8s or fully repairs a deployed Energy Wall (+5s duration).",
				cooldown = 18,
				creditCost = 400,
				duration = 8,
			},
			Ultimate = {
				id = "Warden_Shield",
				name = "Aegis Shield",
				slot = "Ultimate",
				description = "Activates personal Aegis Shield for 8s, reducing all incoming damage by 50% with CC immunity.",
				cooldown = 0,
				creditCost = 0,
				duration = 8,
			},
		},
	},

	Fray = {
		id = "Fray",
		name = "Fray",
		role = "Mobility",
		description = "High-mobility duelist designed for aggressive entry frags and swift disengages.",
		abilities = {
			Basic = {
				id = "Fray_Blink",
				name = "Blink Dash",
				slot = "Basic",
				description = "Instantly blinks 25 studs in look direction.",
				cooldown = 12,
				creditCost = 0,
				range = 25,
			},
			Paid = {
				id = "Fray_Smoke",
				name = "Smoke Screen",
				slot = "Paid",
				description = "Throws a smoke canister creating a 15-stud volumetric smoke sphere lasting 10s.",
				cooldown = 15,
				creditCost = 250,
				radius = 15,
				duration = 10,
			},
			Ultimate = {
				id = "Fray_Hyperdrive",
				name = "Hyperdrive",
				slot = "Ultimate",
				description = "Boosts weapon fire rate (+30%), reload speed (+50%), and move speed (+20%) for 10s.",
				cooldown = 0,
				creditCost = 0,
				duration = 10,
			},
		},
	},

	Choke = {
		id = "Choke",
		name = "Choke",
		role = "Area Denial",
		description = "Area denial expert who controls chokepoints with static field disruptions and incendiary flames.",
		abilities = {
			Basic = {
				id = "Choke_Static",
				name = "Static Field Grenade",
				slot = "Basic",
				description = "Spawns a 12-stud static field for 7s that obscures enemy vision and blurs enemy HUD.",
				cooldown = 18,
				creditCost = 0,
				radius = 12,
				duration = 7,
			},
			Paid = {
				id = "Choke_Incendiary",
				name = "Incendiary",
				slot = "Paid",
				description = "Creates a 10-stud fire pool for 6s dealing 15 DPS (7.5 dmg per 0.5s tick).",
				cooldown = 20,
				creditCost = 300,
				damage = 15,
				radius = 10,
				duration = 6,
			},
			Ultimate = {
				id = "Choke_Zero",
				name = "Absolute Zero",
				slot = "Ultimate",
				description = "Creates a 30-stud cryogenic zone for 8s slowing enemies by 60% and dealing 5 DPS freeze damage.",
				cooldown = 0,
				creditCost = 0,
				damage = 5,
				radius = 30,
				duration = 8,
			},
		},
	},

	Pulse = {
		id = "Pulse",
		name = "Pulse",
		role = "Intel",
		description = "Recon operative specializing in radar sweeps, sonar detection, and map-wide vision.",
		abilities = {
			Basic = {
				id = "Pulse_Sonar",
				name = "Sonar Pulse",
				slot = "Basic",
				description = "Emits a 40-stud sonar wave displaying moving enemy positions on minimap/HUD for 4s.",
				cooldown = 16,
				creditCost = 0,
				radius = 40,
				duration = 4,
			},
			Paid = {
				id = "Pulse_Beacon",
				name = "Sensor Beacon",
				slot = "Paid",
				description = "Places a 50 HP sticky beacon (20-stud detection radius) that highlights enemies red for 3s.",
				cooldown = 20,
				creditCost = 300,
				radius = 20,
				duration = 3,
			},
			Ultimate = {
				id = "Pulse_Scan",
				name = "Global Scan",
				slot = "Ultimate",
				description = "Fires 3 map-wide radar waves at 1.5s intervals, highlighting line-of-sight enemies for 3s per wave.",
				cooldown = 0,
				creditCost = 0,
				duration = 6,
			},
		},
	},

	Bastion = {
		id = "Bastion",
		name = "Bastion",
		role = "Defense",
		description = "Heavy defensive specialist armed with deployable auto-turrets and repulsor shock mines.",
		abilities = {
			Basic = {
				id = "Bastion_Turret",
				name = "Auto-Turret",
				slot = "Basic",
				description = "Deploys a 150 HP mini-turret (40-stud range, 300 RPM, 8 dmg/shot) lasting 20s.",
				cooldown = 25,
				creditCost = 0,
				range = 40,
				damage = 8,
				duration = 20,
			},
			Paid = {
				id = "Bastion_Mine",
				name = "Repulsor Mine",
				slot = "Paid",
				description = "Deploys proximity mine dealing 25 damage and 50 studs/sec knockback impulse in 6-stud blast.",
				cooldown = 15,
				creditCost = 250,
				damage = 25,
				radius = 6,
			},
			Ultimate = {
				id = "Bastion_Siege",
				name = "Siege Turret",
				slot = "Ultimate",
				description = "Transforms into stationary Siege Turret for 12s (+100 shield, minigun 45 dmg/shot, 800 RPM).",
				cooldown = 0,
				creditCost = 0,
				damage = 45,
				duration = 12,
			},
		},
	},
}

local OperativeStats = {}

function OperativeStats.Get(id: string): OperativeData?
	return OperativeRegistry[id]
end

function OperativeStats.GetAll(): { [string]: OperativeData }
	return OperativeRegistry
end

function OperativeStats.GetAbility(id: string, slot: AbilitySlot): AbilityData?
	local op = OperativeRegistry[id]
	if not op then
		return nil
	end
	return op.abilities[slot]
end

return OperativeStats
