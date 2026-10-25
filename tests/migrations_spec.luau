local TestKit = require("./TestKit")
local Migrations = require("../src/shared/Data/Migrations")
local Schema = require("../src/shared/Data/Schema")

local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

describe("Migrations", function()
	it("has one step per schema version", function()
		expect(Migrations.LATEST).toBe(Schema.VERSION)
	end)

	it("upgrades legacy v0 data all the way to the latest version", function()
		local legacy = { Coins = 250, Items = { "Sword", "Sword", "Shield" }, Kills = 4 }
		local result = Migrations.run(legacy)

		expect(result.ok).toBe(true)
		expect(result.fromVersion).toBe(0)
		expect(result.toVersion).toBe(Schema.VERSION)

		local data = result.data :: any
		expect(data.Version).toBe(Schema.VERSION)
		expect(data.Cash).toBe(250)
		expect(data.Coins).toBe(nil)
		expect(data.Items).toBe(nil)
		expect(data.Inventory).toEqual({ Sword = 2, Shield = 1 })
		expect(data.LifetimeCash).toBe(250)
		expect(data.Stats).toEqual({ Kills = 4, Deaths = 0 })
		expect(data.Kills).toBe(nil)
		expect(data.PurchaseIdCache).toEqual({})
	end)

	it("never mutates the input table", function()
		local legacy = { Coins = 10, Items = { "Sword" } }
		Migrations.run(legacy)
		expect(legacy).toEqual({ Coins = 10, Items = { "Sword" } })
	end)

	it("starts from the stored version and skips earlier steps", function()
		local v2 = {
			Version = 2,
			Cash = 900,
			Inventory = { Potion = 3 },
			Settings = { MusicVolume = 0.2, ShowDamageNumbers = false },
		}
		local result = Migrations.run(v2)
		expect(result.ok).toBe(true)
		expect(result.fromVersion).toBe(2)
		local data = result.data :: any
		expect(data.Inventory).toEqual({ Potion = 3 })
		expect(data.Settings.MusicVolume).toBe(0.2)
		expect(data.Prestige).toBe(0)
	end)

	it("leaves current-version data unchanged", function()
		local current = Schema.deepCopy(Schema.Template) :: any
		current.Cash = 77
		local result = Migrations.run(current)
		expect(result.ok).toBe(true)
		expect(result.data).toEqual(current)
	end)

	it("refuses data saved by a newer server instead of downgrading it", function()
		local result = Migrations.run({ Version = Schema.VERSION + 1, Cash = 5 })
		expect(result.ok).toBe(false)
		expect(result.reason).toBe("newer_version")
		expect(result.data).toBe(nil)
	end)

	it("rejects a corrupt Version field", function()
		for _, bad in { "3", -1, 1.5, true } do
			local result = Migrations.run({ Version = bad })
			expect(result.ok).toBe(false)
			expect(result.reason).toBe("invalid_version")
		end
	end)

	it("cleans invalid numbers from legacy data", function()
		local result = Migrations.run({ Coins = 0 / 0, Kills = -3 })
		local data = result.data :: any
		expect(data.Cash).toBe(0)
		expect(data.Stats.Kills).toBe(0)
	end)

	it("ignores junk entries in the legacy item array", function()
		local result = Migrations.run({ Items = { "Sword", 42, "", false, "Sword" } })
		expect((result.data :: any).Inventory).toEqual({ Sword = 2 })
	end)

	it("produces data that already matches the template shape", function()
		local data = Migrations.run({ Coins = 1 }).data :: any
		for key in Schema.Template do
			expect(data[key] ~= nil).toBe(true)
		end
	end)
end)

describe("Schema.reconcile", function()
	it("fills missing fields without overwriting existing ones", function()
		local data = { Cash = 500, Settings = { MusicVolume = 0.1 } } :: any
		Schema.reconcile(data)
		expect(data.Cash).toBe(500)
		expect(data.Settings.MusicVolume).toBe(0.1)
		expect(data.Settings.ShowDamageNumbers).toBe(true)
		expect(data.Prestige).toBe(0)
	end)

	it("does not add template keys into player-owned maps", function()
		local data = { Inventory = { Sword = 1 } } :: any
		Schema.reconcile(data)
		expect(data.Inventory).toEqual({ Sword = 1 })
	end)

	it("gives each player a writable copy of the template", function()
		local a = Schema.deepCopy(Schema.Template) :: any
		local b = Schema.deepCopy(Schema.Template) :: any
		a.Generators.Lemonade = 3
		expect(b.Generators.Lemonade).toBe(nil)
	end)
end)

return nil
