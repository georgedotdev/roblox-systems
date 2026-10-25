--!strict
--[[
	Guard
	Small runtime validators for remote payloads. Exploiters can send any value
	through a RemoteEvent: wrong types, NaN, huge strings, nested tables.
	Every remote handler checks its arguments with a Guard before using them.

	A validator is a function (value) -> (ok, reason?).

	Example:
		local check = Guard.record({
			action = Guard.literal("Attack", "Block"),
			comboHint = Guard.optional(Guard.integer(1, 8)),
		})
		local ok, reason = check(payload)
]]

export type Validator = (value: any) -> (boolean, string?)

local Guard = {}

function Guard.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Guard.number(min: number?, max: number?): Validator
	return function(value)
		if not Guard.isFinite(value) then
			return false, "expected finite number"
		end
		if min and value < min then
			return false, `number below {min}`
		end
		if max and value > max then
			return false, `number above {max}`
		end
		return true
	end
end

function Guard.integer(min: number?, max: number?): Validator
	local numberCheck = Guard.number(min, max)
	return function(value)
		local ok, reason = numberCheck(value)
		if not ok then
			return false, reason
		end
		if value % 1 ~= 0 then
			return false, "expected integer"
		end
		return true
	end
end

function Guard.string(maxLength: number): Validator
	return function(value)
		if type(value) ~= "string" then
			return false, "expected string"
		end
		if #value > maxLength then
			return false, "string too long"
		end
		return true
	end
end

function Guard.boolean(): Validator
	return function(value)
		if type(value) ~= "boolean" then
			return false, "expected boolean"
		end
		return true
	end
end

-- Accepts only one of the given exact values.
function Guard.literal(...: any): Validator
	local allowed = {}
	for _, v in { ... } do
		allowed[v] = true
	end
	return function(value)
		if value == nil or allowed[value] ~= true then
			return false, "value not allowed"
		end
		return true
	end
end

-- Accepts a key of the given lookup table (for example a weapon id).
function Guard.keyOf(lookup: { [string]: any }): Validator
	return function(value)
		if type(value) ~= "string" or lookup[value] == nil then
			return false, "unknown key"
		end
		return true
	end
end

function Guard.optional(inner: Validator): Validator
	return function(value)
		if value == nil then
			return true
		end
		return inner(value)
	end
end

-- Roblox Vector3 with finite components. Optionally checks the length range.
function Guard.vector3(minMagnitude: number?, maxMagnitude: number?): Validator
	return function(value)
		if typeof(value) ~= "Vector3" then
			return false, "expected Vector3"
		end
		if not (Guard.isFinite(value.X) and Guard.isFinite(value.Y) and Guard.isFinite(value.Z)) then
			return false, "non-finite Vector3"
		end
		local magnitude = value.Magnitude
		if minMagnitude and magnitude < minMagnitude then
			return false, "vector too short"
		end
		if maxMagnitude and magnitude > maxMagnitude then
			return false, "vector too long"
		end
		return true
	end
end

-- A table with exactly these keys. Unknown keys are rejected, so payloads stay small.
function Guard.record(shape: { [string]: Validator }): Validator
	return function(value)
		if type(value) ~= "table" then
			return false, "expected table"
		end
		if getmetatable(value) ~= nil then
			return false, "table must not have a metatable"
		end
		for key in value do
			if type(key) ~= "string" or shape[key] == nil then
				return false, `unexpected key {tostring(key)}`
			end
		end
		for key, validator in shape do
			local ok, reason = validator(value[key])
			if not ok then
				return false, `{key}: {reason}`
			end
		end
		return true
	end
end

return Guard
