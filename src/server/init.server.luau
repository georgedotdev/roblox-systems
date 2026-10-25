--!strict
--[[
	Server entry point.
	Every service has Init() (no yielding, no cross-service calls) and
	Start() (connect events, start loops). All Inits run before any Start,
	so services can rely on each other being initialised. This is the same
	lifecycle Knit uses, without the framework dependency.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)
Remotes.createAll()

local Services = script.Services
local ORDER = {
	require(Services.DataService),
	require(Services.EconomyService),
	require(Services.ReceiptService),
	require(Services.CombatService),
	require(Services.PlaygroundService),
}

for _, service in ORDER do
	service.Init()
end
for _, service in ORDER do
	service.Start()
end

print("[Server] all services started")
