--!strict
--[[
	CombatConfig
	Tuning values for melee combat. The server reads these to validate every
	request, so the client cannot change them.
]]

export type Weapon = {
	DisplayName: string,
	ComboDamage: { number }, -- damage per hit in the combo; length = combo length
	Range: number, -- studs, measured flat (Y ignored)
	ArcDegrees: number, -- full width of the swing cone in front of the attacker
	Cooldown: number, -- seconds between two swings
	ComboWindow: number, -- seconds after a swing in which the next swing continues the combo
	ComboEndLag: number, -- extra seconds of cooldown after the final hit
	Knockback: number, -- studs/second applied on the final hit
	AnimationIds: { string }, -- one per combo hit; "" = no animation (placeholder)
}

local CombatConfig = {}

CombatConfig.Weapons = table.freeze({
	Fists = table.freeze({
		DisplayName = "Fists",
		ComboDamage = table.freeze({ 6, 6, 8, 12 }),
		Range = 6,
		ArcDegrees = 100,
		Cooldown = 0.32,
		ComboWindow = 0.9,
		ComboEndLag = 0.8,
		Knockback = 35,
		AnimationIds = table.freeze({ "", "", "", "" }),
	}),
	Sword = table.freeze({
		DisplayName = "Sword",
		ComboDamage = table.freeze({ 12, 12, 20 }),
		Range = 8.5,
		ArcDegrees = 120,
		Cooldown = 0.45,
		ComboWindow = 1.0,
		ComboEndLag = 1.1,
		Knockback = 50,
		AnimationIds = table.freeze({ "", "", "" }),
	}),
} :: { [string]: Weapon })

CombatConfig.DefaultWeapon = "Fists"

CombatConfig.Network = table.freeze({
	-- Token bucket per player: sustained rate and short burst.
	RequestsPerSecond = 6,
	Burst = 3,
	-- Extra range granted for network latency. Capped, so it can't be abused.
	MaxLatencySlackStuds = 2.5,
	-- How far the client's aim may differ from the server's view of the character.
	MaxAimDeviationDegrees = 75,
	-- A client clock this far ahead of the server is clamped (anti speed-hack).
	CooldownToleranceSeconds = 0.05,
})

CombatConfig.MaxTargetsPerSwing = 4

return CombatConfig
