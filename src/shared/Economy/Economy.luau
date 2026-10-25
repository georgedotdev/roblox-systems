--!strict
--[[
	Economy
	Pure math for the idle economy. The server is the only place that changes
	cash; the client uses the same functions only to preview prices.

	Cost of the k-th unit (0-based) = BaseCost * Growth^k.
	Buying `amount` units starting at `owned` is a geometric series:
		cost = BaseCost * Growth^owned * (Growth^amount - 1) / (Growth - 1)
	The inverse of that series gives the largest affordable amount in O(1).

	The config is passed into every function. The module has no requires, so it
	runs the same in Studio, on the client, and in the Lune test runner.
]]

export type Generator = {
	Id: string,
	DisplayName: string,
	BaseCost: number,
	Growth: number,
	BaseRate: number,
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

export type OfflineResult = {
	earned: number,
	seconds: number, -- seconds that counted (after the cap)
	elapsed: number, -- real seconds away (0 when the clock looks wrong)
}

local Economy = {}

function Economy.findGenerator(config: Config, id: string): Generator?
	for _, generator in config.Generators do
		if generator.Id == id then
			return generator
		end
	end
	return nil
end

-- Total price of `amount` units when `owned` are already owned.
function Economy.costOf(generator: Generator, owned: number, amount: number): number
	if amount <= 0 then
		return 0
	end
	local g = generator.Growth
	return generator.BaseCost * g ^ owned * (g ^ amount - 1) / (g - 1)
end

-- Largest amount that `cash` can buy. Uses the closed form, then corrects
-- for floating-point rounding so the result is always affordable.
function Economy.maxAffordable(generator: Generator, owned: number, cash: number): number
	if cash <= 0 then
		return 0
	end
	local g = generator.Growth
	local first = generator.BaseCost * g ^ owned
	if cash < first then
		return 0
	end
	local n = math.floor(math.log(cash * (g - 1) / first + 1) / math.log(g))
	while n > 0 and Economy.costOf(generator, owned, n) > cash do
		n -= 1
	end
	while Economy.costOf(generator, owned, n + 1) <= cash do
		n += 1
	end
	return n
end

-- Output multiplier from milestones: x2 at 25, x4 at 50, x8 at 75 ...
function Economy.milestoneMultiplier(config: Config, owned: number): number
	return config.MilestoneMultiplier ^ math.floor(owned / config.MilestoneEvery)
end

function Economy.generatorRate(config: Config, generator: Generator, owned: number): number
	if owned <= 0 then
		return 0
	end
	return generator.BaseRate * owned * Economy.milestoneMultiplier(config, owned)
end

function Economy.prestigeMultiplier(config: Config, prestige: number): number
	return 1 + config.PrestigeBonusPerPoint * prestige
end

-- Cash per second for a full set of generators.
-- `boostActive` applies the paid multiplier.
function Economy.totalRate(
	config: Config,
	generators: { [string]: number },
	prestige: number,
	boostActive: boolean?
): number
	local base = 0
	for _, generator in config.Generators do
		base += Economy.generatorRate(config, generator, generators[generator.Id] or 0)
	end
	local rate = base * Economy.prestigeMultiplier(config, prestige)
	if boostActive then
		rate *= config.BoostMultiplier
	end
	return rate
end

-- Earnings while the player was away.
-- A missing timestamp, or a clock that went backwards, earns nothing.
function Economy.offlineEarnings(config: Config, lastOnline: number, now: number, rate: number): OfflineResult
	if lastOnline <= 0 or rate <= 0 then
		return { earned = 0, seconds = 0, elapsed = 0 }
	end
	local elapsed = now - lastOnline
	if elapsed <= 0 then
		return { earned = 0, seconds = 0, elapsed = 0 }
	end
	local seconds = math.min(elapsed, config.OfflineMaxSeconds)
	return {
		earned = rate * seconds * config.OfflineEfficiency,
		seconds = seconds,
		elapsed = elapsed,
	}
end

-- Total prestige points that `lifetimeCash` is worth.
function Economy.prestigePointsFor(config: Config, lifetimeCash: number): number
	if lifetimeCash <= 0 then
		return 0
	end
	return math.floor(math.sqrt(lifetimeCash / config.PrestigeDivisor))
end

-- Points the player would gain by prestiging now.
function Economy.pendingPrestige(config: Config, lifetimeCash: number, currentPrestige: number): number
	return math.max(0, Economy.prestigePointsFor(config, lifetimeCash) - currentPrestige)
end

-- Lifetime cash needed to reach `points` total prestige points.
function Economy.lifetimeForPoints(config: Config, points: number): number
	return points * points * config.PrestigeDivisor
end

return Economy
