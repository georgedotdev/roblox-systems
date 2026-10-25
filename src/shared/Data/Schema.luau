--!strict
--[[
	Schema
	The single source of truth for the shape of a player's saved data.

	Rules:
	  * VERSION must equal the highest step in Migrations. A test enforces this.
	  * Template is what a brand-new player starts with. ProfileStore deep-copies it.
	  * Never rename or remove a field here without adding a migration step.
]]

export type Settings = {
	MusicVolume: number,
	ShowDamageNumbers: boolean,
}

export type Stats = {
	Kills: number,
	Deaths: number,
}

export type PlayerData = {
	Version: number,

	-- Economy
	Cash: number,
	LifetimeCash: number,
	Prestige: number,
	Generators: { [string]: number }, -- generatorId -> amount owned
	BoostExpiresAt: number, -- unix seconds; 0 = no boost

	-- Items
	Inventory: { [string]: number }, -- itemId -> count

	-- Misc
	Settings: Settings,
	Stats: Stats,
	LastOnline: number, -- unix seconds; 0 = never saved
	PurchaseIdCache: { string }, -- recent developer-product receipts, newest last
}

local Schema = {}

Schema.VERSION = 3

Schema.Template = table.freeze({
	Version = Schema.VERSION,

	Cash = 0,
	LifetimeCash = 0,
	Prestige = 0,
	Generators = table.freeze({}),
	BoostExpiresAt = 0,

	Inventory = table.freeze({}),

	Settings = table.freeze({
		MusicVolume = 0.5,
		ShowDamageNumbers = true,
	}),
	Stats = table.freeze({
		Kills = 0,
		Deaths = 0,
	}),
	LastOnline = 0,
	PurchaseIdCache = table.freeze({}),
})

-- Deep copy that also strips table.freeze, so callers get a writable table.
function Schema.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = Schema.deepCopy(v)
	end
	return copy :: any
end

-- Fills in any field that exists in the template but is missing in `data`.
-- Existing values are never overwritten. Works like ProfileStore's :Reconcile().
function Schema.reconcile(data: { [any]: any }, template: { [any]: any }?)
	local source = template or (Schema.Template :: any)
	for key, templateValue in source :: any do
		local current = data[key]
		if current == nil then
			data[key] = Schema.deepCopy(templateValue)
		elseif type(current) == "table" and type(templateValue) == "table" then
			-- Only recurse into "record" tables. Arrays and maps (empty in the template)
			-- belong to the player and must not get template keys.
			if next(templateValue) ~= nil and #templateValue == 0 then
				Schema.reconcile(current, templateValue)
			end
		end
	end
end

return Schema
