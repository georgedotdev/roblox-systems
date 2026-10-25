local TestKit = require("./TestKit")
local Economy = require("../src/shared/Economy/Economy")
local EconomyConfig = require("../src/shared/Economy/EconomyConfig")
local NumberFormat = require("../src/shared/Economy/NumberFormat")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Lemonade = EconomyConfig.Generators[1]

-- Reference implementation: add unit prices one by one.
local function slowCost(generator, owned: number, amount: number): number
	local total = 0
	for k = owned, owned + amount - 1 do
		total += generator.BaseCost * generator.Growth ^ k
	end
	return total
end

describe("Economy.costOf", function()
	it("prices the first unit at base cost", function()
		expect(Economy.costOf(Lemonade, 0, 1)).toBeNear(Lemonade.BaseCost)
	end)

	it("matches the unit-by-unit sum for many cases", function()
		for _, generator in EconomyConfig.Generators do
			for _, owned in { 0, 1, 7, 25, 120 } do
				for _, amount in { 1, 10, 33 } do
					expect(Economy.costOf(generator, owned, amount)).toBeNear(
						slowCost(generator, owned, amount)
					)
				end
			end
		end
	end)

	it("costs nothing to buy zero units", function()
		expect(Economy.costOf(Lemonade, 10, 0)).toBe(0)
	end)
end)

describe("Economy.maxAffordable", function()
	it("returns 0 when broke", function()
		expect(Economy.maxAffordable(Lemonade, 0, 0)).toBe(0)
		expect(Economy.maxAffordable(Lemonade, 0, Lemonade.BaseCost - 0.01)).toBe(0)
	end)

	it("is always affordable, and one more is not", function()
		for _, cash in { 15, 100, 12345, 9.87e6, 4.2e12 } do
			for _, owned in { 0, 5, 60 } do
				local n = Economy.maxAffordable(Lemonade, owned, cash)
				expect(Economy.costOf(Lemonade, owned, n)).toBeAtMost(cash)
				expect(Economy.costOf(Lemonade, owned, n + 1) > cash).toBe(true)
			end
		end
	end)

	it("handles exact amounts at the boundary", function()
		local exact = Economy.costOf(Lemonade, 3, 10)
		expect(Economy.maxAffordable(Lemonade, 3, exact)).toBe(10)
	end)
end)

describe("Economy rates", function()
	it("doubles output at each milestone", function()
		local at24 = Economy.generatorRate(EconomyConfig, Lemonade, 24)
		local at25 = Economy.generatorRate(EconomyConfig, Lemonade, 25)
		expect(at24).toBeNear(24)
		expect(at25).toBeNear(50)
		expect(Economy.generatorRate(EconomyConfig, Lemonade, 50)).toBeNear(200)
	end)

	it("sums generators and applies prestige and boost", function()
		local generators = { Lemonade = 10, Bakery = 2 }
		local base = 10 * 1 + 2 * 8
		expect(Economy.totalRate(EconomyConfig, generators, 0)).toBeNear(base)
		expect(Economy.totalRate(EconomyConfig, generators, 5)).toBeNear(base * 1.5)
		expect(Economy.totalRate(EconomyConfig, generators, 5, true)).toBeNear(base * 1.5 * 2)
	end)

	it("ignores unknown generator ids in saved data", function()
		expect(Economy.totalRate(EconomyConfig, { Ghost = 999 }, 0)).toBe(0)
	end)
end)

describe("Economy.offlineEarnings", function()
	it("pays half the rate for time away", function()
		local result = Economy.offlineEarnings(EconomyConfig, 1000, 1000 + 600, 10)
		expect(result.seconds).toBe(600)
		expect(result.earned).toBeNear(10 * 600 * 0.5)
	end)

	it("caps at 8 hours", function()
		local week = 7 * 24 * 3600
		local result = Economy.offlineEarnings(EconomyConfig, 1000, 1000 + week, 10)
		expect(result.seconds).toBe(EconomyConfig.OfflineMaxSeconds)
		expect(result.elapsed).toBe(week)
	end)

	it("pays nothing for a clock that moved backwards", function()
		expect(Economy.offlineEarnings(EconomyConfig, 5000, 4000, 10).earned).toBe(0)
	end)

	it("pays nothing to a brand-new player", function()
		expect(Economy.offlineEarnings(EconomyConfig, 0, 1e9, 10).earned).toBe(0)
	end)
end)

describe("Economy prestige", function()
	it("grows with the square root of lifetime cash", function()
		expect(Economy.prestigePointsFor(EconomyConfig, 999999)).toBe(0)
		expect(Economy.prestigePointsFor(EconomyConfig, 1e6)).toBe(1)
		expect(Economy.prestigePointsFor(EconomyConfig, 4e6)).toBe(2)
		expect(Economy.prestigePointsFor(EconomyConfig, 1e8)).toBe(10)
	end)

	it("only offers points not already claimed", function()
		expect(Economy.pendingPrestige(EconomyConfig, 1e8, 7)).toBe(3)
		expect(Economy.pendingPrestige(EconomyConfig, 1e8, 12)).toBe(0)
	end)

	it("lifetimeForPoints is the inverse of prestigePointsFor", function()
		for points = 1, 20 do
			local needed = Economy.lifetimeForPoints(EconomyConfig, points)
			expect(Economy.prestigePointsFor(EconomyConfig, needed)).toBe(points)
			expect(Economy.prestigePointsFor(EconomyConfig, needed - 1)).toBe(points - 1)
		end
	end)
end)

describe("NumberFormat", function()
	it("abbreviates with 3 significant digits", function()
		expect(NumberFormat.abbreviate(0)).toBe("0")
		expect(NumberFormat.abbreviate(999)).toBe("999")
		expect(NumberFormat.abbreviate(1000)).toBe("1K")
		expect(NumberFormat.abbreviate(1234)).toBe("1.23K")
		expect(NumberFormat.abbreviate(1230)).toBe("1.23K")
		expect(NumberFormat.abbreviate(45600000)).toBe("45.6M")
		expect(NumberFormat.abbreviate(999999)).toBe("999K")
		expect(NumberFormat.abbreviate(1e6)).toBe("1M")
		expect(NumberFormat.abbreviate(1.5e15)).toBe("1.5Qa")
		expect(NumberFormat.abbreviate(-2500)).toBe("-2.5K")
	end)

	it("never rounds up past the real value", function()
		expect(NumberFormat.abbreviate(1999)).toBe("1.99K")
	end)

	it("survives NaN and infinity", function()
		expect(NumberFormat.abbreviate(0 / 0)).toBe("NaN")
		expect(NumberFormat.abbreviate(math.huge)).toBe("∞")
	end)

	it("formats commas and durations", function()
		expect(NumberFormat.commas(1234567)).toBe("1,234,567")
		expect(NumberFormat.commas(999)).toBe("999")
		expect(NumberFormat.duration(45)).toBe("45s")
		expect(NumberFormat.duration(605)).toBe("10m 05s")
		expect(NumberFormat.duration(7500)).toBe("2h 05m")
	end)
end)

return nil
