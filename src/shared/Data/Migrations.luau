--!strict
--[[
	Migrations
	Upgrades saved player data from any old version to the current Schema.VERSION.

	Design:
	  * Each step upgrades exactly one version: Steps[n] turns version n-1 into version n.
	  * Steps run in order, so a v0 profile goes 0 -> 1 -> 2 -> 3.
	  * Migration is atomic. Steps run on a deep copy. The caller gets the new table
	    only if every step succeeds, so a crash mid-way never leaves half-migrated data.
	  * Data from a NEWER version is refused, never downgraded. This happens when an old
	    server is still running during a rollout. The caller should kick, not load.
	  * Run migrations BEFORE ProfileStore:Reconcile(). Reconcile would add Version = latest
	    to legacy data and skip every step.

	Version history (what each step does):
	  v0 -> v1  Legacy data had no Version. Rename Coins -> Cash.
	  v1 -> v2  Items was an array of ids ({"Sword", "Sword"}). Becomes a count map
	            ({Sword = 2}). Add Settings.
	  v2 -> v3  Economy + combat update. Add LifetimeCash, Prestige, Generators,
	            BoostExpiresAt, Stats, LastOnline, PurchaseIdCache.
]]

type Data = { [string]: any }
type Step = (data: Data) -> ()

local Migrations = {}

local function toNonNegativeNumber(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return 0
	end
	return value
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local Steps: { Step } = {
	-- [1] v0 -> v1: rename Coins to Cash.
	function(data: Data)
		data.Cash = toNonNegativeNumber(data.Cash or data.Coins)
		data.Coins = nil
	end,

	-- [2] v1 -> v2: Items array -> Inventory count map; add Settings.
	function(data: Data)
		local inventory: { [string]: number } = {}
		local items = data.Items
		if type(items) == "table" then
			for _, itemId in items do
				if type(itemId) == "string" and #itemId > 0 then
					inventory[itemId] = (inventory[itemId] or 0) + 1
				end
			end
		end
		data.Inventory = inventory
		data.Items = nil

		if type(data.Settings) ~= "table" then
			data.Settings = {
				MusicVolume = 0.5,
				ShowDamageNumbers = true,
			}
		end
	end,

	-- [3] v2 -> v3: economy and combat fields.
	function(data: Data)
		local cash = toNonNegativeNumber(data.Cash)
		data.Cash = cash
		-- Old players keep credit for what they already earned.
		data.LifetimeCash = math.max(toNonNegativeNumber(data.LifetimeCash), cash)
		data.Prestige = 0
		data.Generators = if type(data.Generators) == "table" then data.Generators else {}
		data.BoostExpiresAt = 0
		data.Stats = {
			Kills = toNonNegativeNumber(data.Kills),
			Deaths = toNonNegativeNumber(data.Deaths),
		}
		data.Kills = nil
		data.Deaths = nil
		data.LastOnline = 0
		data.PurchaseIdCache = {}
	end,
}

Migrations.LATEST = #Steps

export type Result = {
	ok: boolean,
	data: Data?, -- the migrated copy; nil when ok == false
	fromVersion: number,
	toVersion: number,
	reason: string?, -- "invalid_version" | "newer_version" | "step_failed"
}

-- Returns the version stored in `data`. Legacy data without a Version field is v0.
function Migrations.getVersion(data: Data): number?
	local version = data.Version
	if version == nil then
		return 0
	end
	if type(version) ~= "number" or version % 1 ~= 0 or version < 0 then
		return nil
	end
	return version
end

-- Migrates a copy of `data`. Never mutates the argument.
function Migrations.run(data: Data): Result
	local fromVersion = Migrations.getVersion(data)
	if fromVersion == nil then
		return { ok = false, data = nil, fromVersion = -1, toVersion = -1, reason = "invalid_version" }
	end
	if fromVersion > Migrations.LATEST then
		return {
			ok = false,
			data = nil,
			fromVersion = fromVersion,
			toVersion = fromVersion,
			reason = "newer_version",
		}
	end

	local working = deepCopy(data)
	for version = fromVersion + 1, Migrations.LATEST do
		local success, err = pcall(Steps[version], working)
		if not success then
			warn(`[Migrations] step to v{version} failed: {err}`)
			return {
				ok = false,
				data = nil,
				fromVersion = fromVersion,
				toVersion = version - 1,
				reason = "step_failed",
			}
		end
		working.Version = version
	end

	return {
		ok = true,
		data = working,
		fromVersion = fromVersion,
		toVersion = Migrations.LATEST,
		reason = nil,
	}
end

-- Exposed for tests only.
Migrations._steps = Steps

return Migrations
