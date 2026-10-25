--!strict
--[[
	DataService
	Loads, migrates, and saves player data with ProfileStore.

	Load order for each player:
	  1. StartSessionAsync  -> session lock, so the same data is never live on two servers
	  2. Migrations.run     -> upgrade old saves (BEFORE Reconcile, see Migrations.luau)
	  3. Reconcile          -> fill any new template fields
	  4. ProfileLoaded      -> other services may now read and write this player's data

	Other services never touch ProfileStore. They use getData / ProfileLoaded / Saving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Migrations = require(Shared.Data.Migrations)
local Schema = require(Shared.Data.Schema)
local Signal = require(Shared.Util.Signal)

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

-- Save to a throwaway store while testing in Studio. Set to false to test real saves.
local USE_MOCK_IN_STUDIO = true
local STORE_NAME = "PlayerData"

type PlayerData = Schema.PlayerData
type Profile = typeof(ProfileStore.New(STORE_NAME, Schema.Template):StartSessionAsync(""))

local DataService = {}

-- (player, data, migratedFromVersion)
DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, PlayerData, number>
-- (player, data) right before every save. Handlers write final values here.
DataService.Saving = Signal.new() :: Signal.Signal<Player, PlayerData>
-- (player) after the session ends. Clean up per-player state here.
DataService.ProfileReleased = Signal.new() :: Signal.Signal<Player>

local store = ProfileStore.New(STORE_NAME, Schema.Template)
local profiles: { [Player]: Profile } = {}

local function kick(player: Player, message: string)
	if player.Parent == Players then
		player:Kick(message)
	end
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		kick(player, "Your data could not be loaded. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: links the key to the user for erasure requests

	local result = Migrations.run(profile.Data)
	if not result.ok then
		-- Data is untouched (migration works on a copy), so ending the session is safe.
		profile:EndSession()
		if result.reason == "newer_version" then
			kick(player, "This server is out of date. Please rejoin to join a newer server.")
		else
			kick(player, "Your data could not be upgraded. Please contact support.")
		end
		warn(`[DataService] {player.Name}: migration refused ({result.reason}, v{result.fromVersion})`)
		return
	end
	profile.Data = result.data :: any
	profile:Reconcile()

	if result.fromVersion < result.toVersion then
		print(`[DataService] {player.Name}: migrated v{result.fromVersion} -> v{result.toVersion}`)
	end

	profile.OnSave:Connect(function()
		DataService.Saving:Fire(player, profile.Data)
	end)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		DataService.ProfileReleased:Fire(player)
		kick(player, "Your data was loaded on another server. Please rejoin.")
	end)

	-- The player may have left while the session was loading.
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	DataService.ProfileLoaded:Fire(player, profile.Data, result.fromVersion)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		-- EndSession fires OnSave (final values are written) and then OnSessionEnd.
		profile:EndSession()
	end
end

-- Returns live data for a loaded player, or nil while loading / after leaving.
-- Do not yield between reading and writing; the session can end at any yield.
function DataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile ~= nil and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

-- Yields until the player's data is loaded. Returns nil on timeout or leave.
function DataService.waitForData(player: Player, timeoutSeconds: number?): PlayerData?
	local deadline = os.clock() + (timeoutSeconds or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.getData(player)
		if data ~= nil then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

-- Iterates every loaded player.
function DataService.loadedPlayers(): { [Player]: PlayerData }
	local result = {}
	for player, profile in profiles do
		if profile:IsActive() then
			result[player] = profile.Data
		end
	end
	return result
end

function DataService.Init()
	if USE_MOCK_IN_STUDIO and RunService:IsStudio() then
		store = store.Mock :: any
		print("[DataService] Studio: using ProfileStore.Mock (nothing is saved)")
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players who joined before this script ran (common in Studio play-solo).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
