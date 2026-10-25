--!strict
--[[
	EconomyConfig
	Numbers for the idle economy. Costs grow exponentially, so every purchase
	costs `Growth` times more than the last. Output doubles at each milestone.
]]

export type Generator = {
	Id: string,
	DisplayName: string,
	BaseCost: number,
	Growth: number, -- cost multiplier per unit owned (1.07 .. 1.15 is typical)
	BaseRate: number, -- cash per second per unit
}

export type Config = {
	Generators: { Generator },
	MilestoneEvery: number,
	MilestoneMultiplier: number,
	PrestigeDivisor: number,
	PrestigeBonusPerPoint: number,
	OfflineEfficiency: number,
	OfflineMaxSeconds: number,
	BoostMultiplier: number,
	StartingCash: number,
}

local EconomyConfig: Config = {
	Generators = {
		{ Id = "Lemonade", DisplayName = "Lemonade Stand", BaseCost = 15, Growth = 1.15, BaseRate = 1 },
		{ Id = "Bakery", DisplayName = "Bakery", BaseCost = 200, Growth = 1.15, BaseRate = 8 },
		{ Id = "Workshop", DisplayName = "Workshop", BaseCost = 3000, Growth = 1.14, BaseRate = 60 },
		{ Id = "Factory", DisplayName = "Factory", BaseCost = 50000, Growth = 1.13, BaseRate = 500 },
		{ Id = "Refinery", DisplayName = "Refinery", BaseCost = 1.2e6, Growth = 1.12, BaseRate = 6000 },
		{ Id = "Spaceport", DisplayName = "Spaceport", BaseCost = 4e7, Growth = 1.11, BaseRate = 90000 },
	},

	-- Every 25 units of one generator doubles that generator's output.
	MilestoneEvery = 25,
	MilestoneMultiplier = 2,

	-- Prestige points from lifetime cash: floor(sqrt(lifetime / divisor)).
	PrestigeDivisor = 1e6,
	-- Each prestige point adds +10% to all income.
	PrestigeBonusPerPoint = 0.1,

	-- While offline the player earns 50% of their rate, for up to 8 hours.
	OfflineEfficiency = 0.5,
	OfflineMaxSeconds = 8 * 60 * 60,

	-- Paid 2x boost (developer product).
	BoostMultiplier = 2,

	StartingCash = 15,
}

table.freeze(EconomyConfig)

return EconomyConfig
