--!strict
--[[
	Remotes
	One place that names every remote. The server creates them; the client
	waits for them. A typo in a remote name fails loudly here, not silently.

	Unreliable remotes carry frequent state that is resent anyway (the idle
	economy tick). Everything that must arrive uses a normal RemoteEvent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFINITIONS: { [string]: "RemoteEvent" | "UnreliableRemoteEvent" } = {
	-- Combat
	CombatRequest = "RemoteEvent", -- client -> server: { action = "Swing", aim = Vector3 }
	CombatEffect = "UnreliableRemoteEvent", -- server -> clients: hit feedback for VFX

	-- Economy
	EconomyPurchase = "RemoteEvent", -- client -> server: { generatorId, amount }
	EconomyPrestige = "RemoteEvent", -- client -> server: {}
	EconomyState = "UnreliableRemoteEvent", -- server -> client: full state, about once per second
	EconomyNotice = "RemoteEvent", -- server -> client: one-off messages (welcome back, errors)

	-- Studio-only demo hook; the server ignores it in live games
	DebugOffline = "RemoteEvent", -- client -> server: seconds to replay as offline time
}

local FOLDER_NAME = "Remotes"
local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if folder == nil then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Returns the remote. Creates it on the server; waits for it on the client.
function Remotes.get(name: string): any
	local className = DEFINITIONS[name]
	assert(className, `Unknown remote "{name}"`)

	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote == nil then
		if RunService:IsServer() then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name, 30)
			assert(remote, `Remote "{name}" did not appear`)
		end
	end
	return remote
end

-- Server only: create all remotes up front so clients never wait.
function Remotes.createAll()
	assert(RunService:IsServer(), "Remotes.createAll is server-only")
	for name in DEFINITIONS do
		Remotes.get(name)
	end
end

return Remotes
