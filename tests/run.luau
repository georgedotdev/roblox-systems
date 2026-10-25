--[[
	Test entry point. Run from the repo root:
		lune run tests/run
	Exits with code 1 when any test fails, so CI fails too.
]]

local process = require("@lune/process")
local TestKit = require("./TestKit")

print("Running tests\n")
require("./migrations_spec")
require("./combat_spec")
require("./economy_spec")

local failures = TestKit.report()
process.exit(if failures > 0 then 1 else 0)
