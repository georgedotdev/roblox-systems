--!strict
--[[
	TestKit
	A tiny test framework with no dependencies. Runs under Lune (CI) and in Studio.

		describe("Economy", function()
			it("prices the first unit at base cost", function()
				expect(Economy.costOf(gen, 0, 1)).toBeNear(15)
			end)
		end)
]]

local TestKit = {}

type Result = { name: string, ok: boolean, err: string? }

local results: { Result } = {}
local prefix: { string } = {}

local function fullName(name: string): string
	local parts = table.clone(prefix)
	table.insert(parts, name)
	return table.concat(parts, " > ")
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	for k, v in value do
		table.insert(parts, `{tostring(k)}={show(v)}`)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

function TestKit.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestKit.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	table.insert(results, { name = fullName(name), ok = ok, err = if ok then nil else tostring(err) })
end

function TestKit.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function matchers.toBeNear(expected: number, tolerance: number?)
		local limit = tolerance or 1e-6 * math.max(1, math.abs(expected))
		if type(actual) ~= "number" or math.abs(actual - expected) > limit then
			error(`expected {expected} (±{limit}), got {show(actual)}`, 2)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error(`expected truthy, got {show(actual)}`, 2)
		end
	end

	function matchers.toBeFalsy()
		if actual then
			error(`expected falsy, got {show(actual)}`, 2)
		end
	end

	function matchers.toBeAtMost(limit: number)
		if type(actual) ~= "number" or actual > limit then
			error(`expected <= {limit}, got {show(actual)}`, 2)
		end
	end

	function matchers.toBeAtLeast(limit: number)
		if type(actual) ~= "number" or actual < limit then
			error(`expected >= {limit}, got {show(actual)}`, 2)
		end
	end

	return matchers
end

-- Prints a report. Returns the number of failures.
function TestKit.report(): number
	local failures = 0
	for _, result in results do
		if result.ok then
			print(`  PASS  {result.name}`)
		else
			failures += 1
			print(`  FAIL  {result.name}\n        {result.err}`)
		end
	end
	print(`\n{#results - failures} passed, {failures} failed, {#results} total`)
	return failures
end

return TestKit
