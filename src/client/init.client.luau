--!strict
-- Client entry point. Controllers only show state and send intent.

local Controllers = script.Controllers

require(Controllers.EconomyController).Start()
require(Controllers.CombatController).Start()
