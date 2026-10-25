--!strict
--[[
	ReceiptService
	Developer products, granted exactly once.

	Roblox may call ProcessReceipt more than once for the same purchase
	(rejoin, server crash, retry). Each grant stores the PurchaseId in the
	profile. The callback returns PurchaseGranted only after that PurchaseId
	is confirmed in Profile.LastSavedData, so the reward and the receipt are
	saved together or not at all. This follows ProfileStore's recommended pattern.

	Set the product ids below after you create the products on the Creator Dashboard.
	A product id of 0 is skipped.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local ReceiptService = {}

local PURCHASE_ID_CACHE_SIZE = 100
local SAVE_RETRY_SECONDS = 10

type Grant = (player: Player) -> ()

local PRODUCTS: { [number]: { name: string, grant: Grant } } = {}

local function register(productId: number, name: string, grant: Grant)
	if productId ~= 0 then
		PRODUCTS[productId] = { name = name, grant = grant }
	end
end

-- Replace the 0s with your real developer product ids.
register(0, "2x Income (30 min)", function(player)
	assert(EconomyService.grantBoost(player, 30 * 60), "player data not loaded")
end)
register(0, "Cash Crate (15 min of income)", function(player)
	assert(EconomyService.grantMinutesOfIncome(player, 15) > 0, "player data not loaded")
end)

local function waitForProfile(player: Player)
	local profile = DataService.getProfile(player)
	while profile == nil and player.Parent == Players do
		task.wait()
		profile = DataService.getProfile(player)
	end
	return profile
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = PRODUCTS[receipt.ProductId]
	if player == nil or product == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = waitForProfile(player)
	if profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = receipt.PurchaseId
	local cache = profile.Data.PurchaseIdCache

	if table.find(cache, purchaseId) == nil then
		local ok, err = pcall(product.grant, player)
		if not ok then
			warn(`[ReceiptService] grant failed for {player.Name} ({product.name}): {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #cache >= PURCHASE_ID_CACHE_SIZE do
			table.remove(cache, 1)
		end
		table.insert(cache, purchaseId)
	end

	local function isSaved(): boolean
		local saved = profile.LastSavedData and profile.LastSavedData.PurchaseIdCache
		return saved ~= nil and table.find(saved, purchaseId) ~= nil
	end

	while profile:IsActive() do
		if isSaved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local before = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == before then
			profile.OnAfterSave:Wait()
		end
		if isSaved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		task.wait(SAVE_RETRY_SECONDS)
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function ReceiptService.Init() end

function ReceiptService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ReceiptService
