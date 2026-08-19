--!strict
--[=[
    Project OVERCLOCK: Constants
    Centralized game constants for game modes, round rules, economy values,
    operative IDs, map IDs, and UI theme configuration.
]=]

local Constants = {}

-- Game Modes
Constants.GameModes = {
	DUEL_1V1 = "1v1",
	DUEL_2V2 = "2v2",
	PRACTICE_RANGE = "PracticeRange",
}

-- Round Configuration
Constants.RoundConfig = {
	BUY_PHASE_DURATION = 15,
	LIVE_PHASE_DURATION = 60,
	INTERMISSION_DURATION = 5,
	WINNING_SCORE = 7,
	TIE_SCORE = 6,
	MAX_ROUNDS = 13,
}

-- Economy Configuration
Constants.Economy = {
	STARTING_CREDITS = 800,
	MAX_CREDITS = 9000,
	WIN_BONUS = 3000,
	BASE_LOSS_BONUS = 1400,
	LOSS_BONUS_INCREMENT = 500,
	MAX_LOSS_BONUS = 2900,
	KILL_CREDITS = 300,
}

-- Operative Identifiers
Constants.Operatives = {
	VEX = "Vex",
	WARDEN = "Warden",
	FRAY = "Fray",
	CHOKE = "Choke",
	PULSE = "Pulse",
	BASTION = "Bastion",
}

-- Map Identifiers
Constants.Maps = {
	DUEL_ARENA = "DuelArena",
	PRACTICE_RANGE = "PracticeRangeMap",
	GREYBOX_ARENA = "GreyboxArena",
}

-- UI Theme Constants
Constants.UITheme = {
	PRIMARY_DARK = Color3.fromRGB(15, 18, 24),
	SECONDARY_DARK = Color3.fromRGB(24, 28, 38),
	SURFACE_DARK = Color3.fromRGB(34, 40, 52),
	ACCENT_CYAN = Color3.fromRGB(0, 220, 255),
	ACCENT_AMBER = Color3.fromRGB(255, 170, 0),
	ACCENT_RED = Color3.fromRGB(255, 60, 60),
	ACCENT_GREEN = Color3.fromRGB(60, 220, 100),
	TEXT_PRIMARY = Color3.fromRGB(240, 242, 245),
	TEXT_MUTED = Color3.fromRGB(160, 165, 175),
}

return Constants
