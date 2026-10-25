--!strict
--[[
	EconomyService
	Server-authoritative idle economy.

	  * Income is computed on the server once per second from the saved
	    generator counts. The client never reports cash.
	  * Purchases arrive as intent ({ generatorId, amount }). The server prices
	    them with the same Economy module and rejects anything unaffordable.
	  * Offline earnings use LastOnline, which is written right before every save
	    (DataService.Saving). A crash loses at most one autosave period of time.
	  * A clock that moved backwards, or a missing timestamp, earns nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy.Economy)
local EconomyConfig = require(Shared.Economy.EconomyConfig)
local Guard = require(Shared.Combat.Guard)
local NumberFormat = require(Shared.Economy.NumberFormat)
local RateLimiter = require(Shared.Combat.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Schema = require(Shared.Data.Schema)

local DataService = require(script.Parent.DataService)

type PlayerData = Schema.PlayerData

local EconomyService = {}

local TICK_SECONDS = 1
local MAX_BUY_AMOUNT = 1000 -- amount 0 means "buy max"

local generatorLookup: { [string]: Economy.Generator } = {}
for _, generator in EconomyConfig.Generators do
	generatorLookup[generator.Id] = generator
end

local validatePurchase = Guard.record({
	generatorId = Guard.keyOf(generatorLookup),
	amount = Guard.integer(0, MAX_BUY_AMOUNT),
})
local validatePrestige = Guard.record({})

local limiter = RateLimiter.new(8, 6)
local lastTick: { [Player]: number } = {}

local function isBoostActive(data: PlayerData): boolean
	return data.BoostExpiresAt > os.time()
end

local function currentRate(data: PlayerData): number
	return Economy.totalRate(EconomyConfig, data.Generators, data.Prestige, isBoostActive(data))
end

local function addCash(data: PlayerData, amount: number)
	if amount <= 0 or not Guard.isFinite(amount) then
		return
	end
	data.Cash += amount
	data.LifetimeCash += amount
end

local function notify(player: Player, kind: string, payload: { [string]: any })
	payload.kind = kind
	Remotes.get("EconomyNotice"):FireClient(player, payload)
end

local function updateLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local cash = leaderstats:FindFirstChild("Cash") :: StringValue?
	if cash == nil then
		local value = Instance.new("StringValue")
		value.Name = "Cash"
		value.Parent = leaderstats
		cash = value
	end
	local prestige = leaderstats:FindFirstChild("Prestige") :: IntValue?
	if prestige == nil then
		local value = Instance.new("IntValue")
		value.Name = "Prestige"
		value.Parent = leaderstats
		prestige = value
	end
	(cash :: StringValue).Value = NumberFormat.abbreviate(data.Cash);
	(prestige :: IntValue).Value = data.Prestige
end

local function sendState(player: Player, data: PlayerData)
	Remotes.get("EconomyState"):FireClient(player, {
		cash = data.Cash,
		rate = currentRate(data),
		lifetimeCash = data.LifetimeCash,
		prestige = data.Prestige,
		pendingPrestige = Economy.pendingPrestige(EconomyConfig, data.LifetimeCash, data.Prestige),
		generators = data.Generators,
		boostExpiresAt = data.BoostExpiresAt,
		serverTime = os.time(),
	})
	updateLeaderstats(player, data)
end

local function onProfileLoaded(player: Player, data: PlayerData)
	local isNewPlayer = data.LifetimeCash == 0 and data.Cash == 0 and next(data.Generators) == nil
	if isNewPlayer then
		data.Cash = EconomyConfig.StartingCash
	end

	local offline = Economy.offlineEarnings(EconomyConfig, data.LastOnline, os.time(), currentRate(data))
	if offline.earned > 0 then
		addCash(data, offline.earned)
		notify(player, "WelcomeBack", {
			earned = offline.earned,
			seconds = offline.seconds,
			capped = offline.elapsed > offline.seconds,
		})
	end

	data.LastOnline = os.time()
	lastTick[player] = os.clock()
	sendState(player, data)
end

local function onPurchase(player: Player, payload: any)
	if not limiter:take(player) then
		return
	end
	local valid = validatePurchase(payload)
	if not valid then
		return
	end
	local data = DataService.getData(player)
	if data == nil then
		return
	end

	local generator = generatorLookup[payload.generatorId]
	local owned = data.Generators[generator.Id] or 0
	local amount = payload.amount
	if amount == 0 then
		amount = math.min(Economy.maxAffordable(generator, owned, data.Cash), MAX_BUY_AMOUNT)
	end
	if amount <= 0 then
		notify(player, "CannotAfford", { generatorId = generator.Id })
		return
	end

	local cost = Economy.costOf(generator, owned, amount)
	if cost > data.Cash then
		notify(player, "CannotAfford", { generatorId = generator.Id })
		return
	end

	-- No yield between the check and the write, so the session cannot end in between.
	data.Cash -= cost
	data.Generators[generator.Id] = owned + amount
	sendState(player, data)
end

local function onPrestige(player: Player, payload: any)
	if not limiter:take(player) or not validatePrestige(payload) then
		return
	end
	local data = DataService.getData(player)
	if data == nil then
		return
	end
	local gain = Economy.pendingPrestige(EconomyConfig, data.LifetimeCash, data.Prestige)
	if gain <= 0 then
		return
	end
	data.Prestige += gain
	data.Cash = EconomyConfig.StartingCash
	data.Generators = {}
	notify(player, "Prestiged", { gained = gain, total = data.Prestige })
	sendState(player, data)
end

local function tick()
	local now = os.clock()
	for player, data in DataService.loadedPlayers() do
		local previous = lastTick[player]
		if previous then
			-- Clamp dt so a long server hitch can't pay out a huge lump.
			local dt = math.clamp(now - previous, 0, 5)
			addCash(data, currentRate(data) * dt)
			sendState(player, data)
		end
		lastTick[player] = now
	end
end

-- Public: used by ReceiptService for paid products.
function EconomyService.grantBoost(player: Player, seconds: number): boolean
	local data = DataService.getData(player)
	if data == nil then
		return false
	end
	-- Stack on top of an active boost instead of overwriting it.
	data.BoostExpiresAt = math.max(data.BoostExpiresAt, os.time()) + seconds
	notify(player, "BoostStarted", { expiresAt = data.BoostExpiresAt })
	sendState(player, data)
	return true
end

function EconomyService.grantMinutesOfIncome(player: Player, minutes: number): number
	local data = DataService.getData(player)
	if data == nil then
		return 0
	end
	-- At least 1000 cash, so a brand-new player still gets something useful.
	local amount = math.max(1000, currentRate(data) * minutes * 60)
	addCash(data, amount)
	sendState(player, data)
	return amount
end

-- Studio-only test hook: set the attribute from the server command bar to
-- replay offline earnings as if the player had been away that long:
--   game.Players:GetPlayers()[1]:SetAttribute("DebugOfflineSeconds", 3600)
-- The attribute is cleared after each use, so the same line can run again.
local function replayOffline(player: Player, seconds: number)
	local data = DataService.getData(player)
	if data == nil then
		return
	end
	if currentRate(data) <= 0 then
		-- Offline earnings are a share of income; with no income there is nothing to pay.
		notify(player, "NoOfflineIncome", {})
		return
	end
	data.LastOnline = os.time() - seconds
	onProfileLoaded(player, data)
end

local validateDebugSeconds = Guard.integer(60, 24 * 3600)

local function attachDebugHook(player: Player)
	if not RunService:IsStudio() then
		return
	end
	player:GetAttributeChangedSignal("DebugOfflineSeconds"):Connect(function()
		local seconds = player:GetAttribute("DebugOfflineSeconds")
		if type(seconds) ~= "number" or seconds <= 0 then
			return
		end
		player:SetAttribute("DebugOfflineSeconds", nil)
		replayOffline(player, seconds)
	end)
end

function EconomyService.Init() end

function EconomyService.Start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.Saving:Connect(function(_player, data)
		data.LastOnline = os.time()
	end)
	DataService.ProfileReleased:Connect(function(player)
		lastTick[player] = nil
		limiter:remove(player)
	end)

	Remotes.get("EconomyPurchase").OnServerEvent:Connect(onPurchase)
	Remotes.get("EconomyPrestige").OnServerEvent:Connect(onPrestige)

	Players.PlayerRemoving:Connect(function(player)
		lastTick[player] = nil
	end)
	-- Studio-only demo keys (O / P in EconomyController). Never active in live servers.
	if RunService:IsStudio() then
		Remotes.get("DebugOffline").OnServerEvent:Connect(function(player, seconds)
			if validateDebugSeconds(seconds) then
				replayOffline(player, seconds)
			end
		end)
	end
	Players.PlayerAdded:Connect(attachDebugHook)
	for _, player in Players:GetPlayers() do
		attachDebugHook(player)
	end

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			tick()
		end
	end)
end

return EconomyService
