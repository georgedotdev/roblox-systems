--!strict
--[[
	PlaygroundService
	Demo setup for recording and testing: spawns R15 training dummies that
	respawn after death and credit kills to the last attacker.
	Remove this service in a real game.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DataService = require(script.Parent.DataService)

local PlaygroundService = {}

local DUMMY_POSITIONS = {
	Vector3.new(0, 4, -14),
	Vector3.new(-7, 4, -18),
	Vector3.new(7, 4, -18),
}
local RESPAWN_SECONDS = 3
local LAST_HIT_ATTRIBUTE = "LastHitByUserId"

local folder: Folder

local function creditKill(humanoid: Humanoid)
	local killerId = humanoid:GetAttribute(LAST_HIT_ATTRIBUTE)
	if type(killerId) ~= "number" then
		return
	end
	local killer = Players:GetPlayerByUserId(killerId)
	local data = killer and DataService.getData(killer)
	if data then
		data.Stats.Kills += 1
	end
end

local function spawnDummy(position: Vector3)
	local description = Instance.new("HumanoidDescription")
	local dummy = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	dummy.Name = "Training Dummy"

	local humanoid = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = 120
	humanoid.Health = 120
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn

	dummy:PivotTo(CFrame.lookAt(position, Vector3.new(0, position.Y, 0)))
	dummy.Parent = folder

	humanoid.Died:Connect(function()
		creditKill(humanoid)
		task.delay(RESPAWN_SECONDS, function()
			dummy:Destroy()
			spawnDummy(position)
		end)
	end)
end

function PlaygroundService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = Workspace
end

function PlaygroundService.Start()
	for _, position in DUMMY_POSITIONS do
		task.spawn(spawnDummy, position)
	end
end

return PlaygroundService
