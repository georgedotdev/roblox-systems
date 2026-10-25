local TestKit = require("./TestKit")
local CombatConfig = require("../src/shared/Combat/CombatConfig")
local Guard = require("../src/shared/Combat/Guard")
local HitValidation = require("../src/shared/Combat/HitValidation")
local RateLimiter = require("../src/shared/Combat/RateLimiter")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local function v(x: number, z: number)
	return { X = x, Y = 0, Z = z }
end

local Fists = CombatConfig.Weapons.Fists
local FORWARD = v(0, -1) -- Roblox characters face -Z by default

describe("HitValidation.tryStartSwing", function()
	it("allows the first swing and starts the combo at 1", function()
		local state = HitValidation.newState()
		local result = HitValidation.tryStartSwing(state, Fists, 10)
		expect(result.ok).toBe(true)
		expect(result.comboIndex).toBe(1)
		expect(result.damage).toBe(Fists.ComboDamage[1])
	end)

	it("rejects a swing during the cooldown", function()
		local state = HitValidation.newState()
		HitValidation.tryStartSwing(state, Fists, 10)
		local result = HitValidation.tryStartSwing(state, Fists, 10 + Fists.Cooldown / 2)
		expect(result.ok).toBe(false)
		expect(result.reason).toBe("cooldown")
	end)

	it("forgives only the configured tolerance", function()
		local state = HitValidation.newState()
		HitValidation.tryStartSwing(state, Fists, 10)
		local early = 10 + Fists.Cooldown - 0.03
		expect(HitValidation.tryStartSwing(state, Fists, early, 0.05).ok).toBe(true)

		local state2 = HitValidation.newState()
		HitValidation.tryStartSwing(state2, Fists, 10)
		local tooEarly = 10 + Fists.Cooldown - 0.2
		expect(HitValidation.tryStartSwing(state2, Fists, tooEarly, 0.05).ok).toBe(false)
	end)

	it("chains a full combo and marks the last hit as the finisher", function()
		local state = HitValidation.newState()
		local t = 0
		local indexes = {}
		local finishers = {}
		for _ = 1, #Fists.ComboDamage do
			local result = HitValidation.tryStartSwing(state, Fists, t)
			table.insert(indexes, result.comboIndex)
			table.insert(finishers, result.isFinisher)
			t += Fists.Cooldown
		end
		expect(indexes).toEqual({ 1, 2, 3, 4 })
		expect(finishers).toEqual({ false, false, false, true })
	end)

	it("applies end lag after the finisher", function()
		local state = HitValidation.newState()
		local t = 0
		for _ = 1, #Fists.ComboDamage do
			HitValidation.tryStartSwing(state, Fists, t)
			t += Fists.Cooldown
		end
		local finisherAt = t - Fists.Cooldown
		local afterNormalCooldown = finisherAt + Fists.Cooldown + 0.01
		expect(HitValidation.tryStartSwing(state, Fists, afterNormalCooldown).ok).toBe(false)
		local afterEndLag = finisherAt + Fists.Cooldown + Fists.ComboEndLag + 1e-6
		local result = HitValidation.tryStartSwing(state, Fists, afterEndLag)
		expect(result.ok).toBe(true)
		expect(result.comboIndex).toBe(1)
	end)

	it("resets the combo when the combo window expires", function()
		local state = HitValidation.newState()
		HitValidation.tryStartSwing(state, Fists, 0)
		local late = Fists.ComboWindow + 0.1
		expect(HitValidation.tryStartSwing(state, Fists, late).comboIndex).toBe(1)
	end)

	it("does not change state when a swing is rejected", function()
		local state = HitValidation.newState()
		HitValidation.tryStartSwing(state, Fists, 0)
		local before = table.clone(state)
		HitValidation.tryStartSwing(state, Fists, 0.01)
		expect(state).toEqual(before)
	end)
end)

describe("HitValidation geometry", function()
	it("hits a target straight ahead within range", function()
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, v(0, -5), Fists)).toBe(true)
	end)

	it("misses a target just out of range", function()
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, v(0, -6.5), Fists)).toBe(false)
	end)

	it("latency slack extends range, but only by the slack given", function()
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, v(0, -7), Fists, 1.5)).toBe(true)
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, v(0, -8), Fists, 1.5)).toBe(false)
	end)

	it("misses a target behind the attacker", function()
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, v(0, 3), Fists)).toBe(false)
	end)

	it("respects the arc edges", function()
		-- Fists arc is 100°, so 50° each side. 45° is inside, 60° is outside.
		local inside = v(math.sin(math.rad(45)) * 4, -math.cos(math.rad(45)) * 4)
		local outside = v(math.sin(math.rad(60)) * 4, -math.cos(math.rad(60)) * 4)
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, inside, Fists)).toBe(true)
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, outside, Fists)).toBe(false)
	end)

	it("ignores height difference", function()
		local above = { X = 0, Y = 40, Z = -4 }
		expect(HitValidation.isInSwingCone(v(0, 0), FORWARD, above, Fists)).toBe(true)
	end)

	it("measures flat angles correctly", function()
		expect(HitValidation.flatAngleDegrees(v(1, 0), v(0, 1))).toBeNear(90)
		expect(HitValidation.flatAngleDegrees(v(1, 0), v(-1, 0))).toBeNear(180)
		expect(HitValidation.flatAngleDegrees(v(0, 0), v(1, 0))).toBe(180)
	end)
end)

describe("HitValidation.resolveAim", function()
	it("trusts a client aim close to the server view", function()
		local aim = v(math.sin(math.rad(30)), -math.cos(math.rad(30)))
		local facing, used = HitValidation.resolveAim(FORWARD, aim, 75)
		expect(used).toBe(true)
		expect(facing).toBe(aim)
	end)

	it("rejects an aim pointing behind the character", function()
		local facing, used = HitValidation.resolveAim(FORWARD, v(0, 1), 75)
		expect(used).toBe(false)
		expect(facing).toBe(FORWARD)
	end)

	it("falls back to the server view when no aim is sent", function()
		local facing, used = HitValidation.resolveAim(FORWARD, nil, 75)
		expect(used).toBe(false)
		expect(facing).toBe(FORWARD)
	end)
end)

describe("HitValidation.selectTargets", function()
	it("returns targets in the cone, nearest first, capped", function()
		local candidates = {
			{ id = "far", position = v(0, -5.5) },
			{ id = "behind", position = v(0, 2) },
			{ id = "near", position = v(0, -2) },
			{ id = "mid", position = v(1, -4) },
		}
		local hits = HitValidation.selectTargets(v(0, 0), FORWARD, candidates, Fists, 2)
		expect(hits).toEqual({ "near", "mid" })
	end)
end)

describe("Guard", function()
	local check = Guard.record({
		action = Guard.literal("Swing"),
		count = Guard.optional(Guard.integer(1, 8)),
		name = Guard.optional(Guard.string(10)),
	})

	it("accepts a well-formed payload", function()
		expect(check({ action = "Swing" })).toBe(true)
		expect(check({ action = "Swing", count = 3, name = "abc" })).toBe(true)
	end)

	it("rejects wrong types, unknown keys and bad values", function()
		expect(check(nil)).toBe(false)
		expect(check("Swing")).toBe(false)
		expect(check({ action = "Fly" })).toBe(false)
		expect(check({ action = "Swing", extra = 1 })).toBe(false)
		expect(check({ action = "Swing", count = 2.5 })).toBe(false)
		expect(check({ action = "Swing", count = 99 })).toBe(false)
		expect(check({ action = "Swing", name = string.rep("x", 11) })).toBe(false)
		expect(check({ [1] = "Swing" })).toBe(false)
	end)

	it("rejects NaN and infinity", function()
		local n = Guard.number()
		expect(n(0 / 0)).toBe(false)
		expect(n(math.huge)).toBe(false)
		expect(n(-math.huge)).toBe(false)
		expect(n(12.5)).toBe(true)
	end)

	it("rejects tables with a metatable", function()
		local sneaky = setmetatable({ action = "Swing" }, {})
		expect(check(sneaky)).toBe(false)
	end)

	it("keyOf only accepts existing keys", function()
		local weapon = Guard.keyOf(CombatConfig.Weapons)
		expect(weapon("Sword")).toBe(true)
		expect(weapon("Railgun")).toBe(false)
		expect(weapon(1)).toBe(false)
	end)
end)

describe("RateLimiter", function()
	local function fakeClock()
		local now = 0
		return function()
			return now
		end, function(dt: number)
			now += dt
		end
	end

	it("allows a burst, then blocks", function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(5, 3, clock)
		expect(limiter:take("p")).toBe(true)
		expect(limiter:take("p")).toBe(true)
		expect(limiter:take("p")).toBe(true)
		expect(limiter:take("p")).toBe(false)
	end)

	it("refills over time at the configured rate", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(5, 3, clock)
		for _ = 1, 3 do
			limiter:take("p")
		end
		advance(0.1) -- 0.5 tokens
		expect(limiter:take("p")).toBe(false)
		advance(0.1) -- 1.0 token
		expect(limiter:take("p")).toBe(true)
	end)

	it("never refills above the burst size", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(5, 3, clock)
		advance(1000)
		expect(limiter:peek("p")).toBe(3)
	end)

	it("keeps players independent", function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(1, 1, clock)
		expect(limiter:take("a")).toBe(true)
		expect(limiter:take("a")).toBe(false)
		expect(limiter:take("b")).toBe(true)
	end)

	it("blocks a spam script: 1000 requests in one second pass at most burst + rate", function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(6, 3, clock)
		local passed = 0
		for _ = 1, 1000 do
			if limiter:take("exploiter") then
				passed += 1
			end
			advance(0.001)
		end
		expect(passed).toBeAtMost(3 + 6)
	end)
end)

return nil
