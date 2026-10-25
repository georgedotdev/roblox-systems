--!strict
--[[
	CombatService
	Server-authoritative melee.

	The client sends only intent: { action = "Swing", aim = Vector3 }.
	The client never says who it hit or how much damage. The server:
	  1. rate-limits the player (token bucket),
	  2. type-checks the payload (Guard),
	  3. checks cooldown and combo state with server time (HitValidation),
	  4. finds targets with the server's own positions,
	  5. applies damage and knockback, then broadcasts effects.

	An exploiter who fires the remote 1000 times per second, sends NaN,
	or teleports the aim behind them gets nothing extra.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Combat.CombatConfig)
local Guard = require(Shared.Combat.Guard)
local HitValidation = require(Shared.Combat.HitValidation)
local RateLimiter = require(Shared.Combat.RateLimiter)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local CombatService = {}

local NET = CombatConfig.Network

local validateRequest = Guard.record({
	action = Guard.literal("Swing"),
	aim = Guard.vector3(0.5, 2), -- a unit look vector; small slack for float error
})

local limiter = RateLimiter.new(NET.RequestsPerSecond, NET.Burst)
local swingStates: { [Player]: HitValidation.SwingState } = {}
local strikes: { [Player]: number } = {} -- invalid payloads seen; logged, not kicked

-- Tag of the last attacker per humanoid, so a kill credits the right player.
local LAST_HIT_ATTRIBUTE = "LastHitByUserId"

local function getRoot(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getAliveHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function equippedWeaponId(player: Player): string
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool then
		local weaponId = tool:GetAttribute("WeaponId")
		if type(weaponId) == "string" and CombatConfig.Weapons[weaponId] then
			return weaponId
		end
	end
	return CombatConfig.DefaultWeapon
end

-- Every humanoid model near `origin` except the attacker.
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function findCandidates(attacker: Model, origin: Vector3, radius: number)
	overlapParams.FilterDescendantsInstances = { attacker }
	local seen: { [Model]: boolean } = {}
	local candidates = {}
	for _, part in Workspace:GetPartBoundsInRadius(origin, radius, overlapParams) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			local root = getRoot(model)
			if root and getAliveHumanoid(model) then
				table.insert(candidates, { id = model, position = root.Position })
			end
		end
	end
	return candidates
end

local function onCombatRequest(player: Player, payload: any)
	if not limiter:take(player) then
		return -- spam: drop silently
	end

	local valid, reason = validateRequest(payload)
	if not valid then
		strikes[player] = (strikes[player] or 0) + 1
		if strikes[player] % 20 == 1 then
			warn(`[CombatService] {player.Name} sent a bad payload: {reason}`)
		end
		return
	end

	local character = player.Character
	local root = getRoot(character)
	if character == nil or root == nil or getAliveHumanoid(character) == nil then
		return
	end

	local weapon = CombatConfig.Weapons[equippedWeaponId(player)]
	local state = swingStates[player]
	if state == nil then
		state = HitValidation.newState()
		swingStates[player] = state
	end

	local now = Workspace:GetServerTimeNow()
	local swing = HitValidation.tryStartSwing(state, weapon, now, NET.CooldownToleranceSeconds)
	if not swing.ok then
		return
	end

	local origin = root.Position
	local facing = HitValidation.resolveAim(root.CFrame.LookVector, payload.aim, NET.MaxAimDeviationDegrees)

	-- Latency slack: half the player's ping in studs of movement, capped.
	local pingSeconds = math.clamp(player:GetNetworkPing(), 0, 0.5)
	local slack = math.min(NET.MaxLatencySlackStuds, pingSeconds * 16) -- 16 = default WalkSpeed

	local candidates = findCandidates(character, origin, weapon.Range + slack + 3)
	local targets = HitValidation.selectTargets(
		origin,
		facing,
		candidates,
		weapon,
		CombatConfig.MaxTargetsPerSwing,
		slack
	)

	local hitReports = {}
	for _, model in targets do
		local humanoid = getAliveHumanoid(model)
		local targetRoot = getRoot(model)
		if humanoid and targetRoot then
			humanoid:SetAttribute(LAST_HIT_ATTRIBUTE, player.UserId)
			humanoid:TakeDamage(swing.damage)

			if swing.isFinisher and weapon.Knockback > 0 then
				local direction = Vector3.new(facing.X, 0, facing.Z)
				if direction.Magnitude > 0 then
					local push = direction.Unit * weapon.Knockback
						+ Vector3.new(0, weapon.Knockback * 0.35, 0)
					targetRoot:ApplyImpulse(push * targetRoot.AssemblyMass)
				end
			end

			table.insert(hitReports, {
				target = model,
				damage = swing.damage,
				position = targetRoot.Position,
			})
		end
	end

	Remotes.get("CombatEffect"):FireAllClients({
		attacker = character,
		comboIndex = swing.comboIndex,
		isFinisher = swing.isFinisher,
		hits = hitReports,
	})
end

-- Credits kills and counts deaths in saved stats.
local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil then
		return
	end
	humanoid.Died:Connect(function()
		local victimData = DataService.getData(player)
		if victimData then
			victimData.Stats.Deaths += 1
		end
		local killerId = humanoid:GetAttribute(LAST_HIT_ATTRIBUTE)
		local killer = if type(killerId) == "number" then Players:GetPlayerByUserId(killerId) else nil
		local killerData = killer and DataService.getData(killer)
		if killerData then
			killerData.Stats.Kills += 1
		end
	end)
end

function CombatService.Init() end

function CombatService.Start()
	Remotes.get("CombatRequest").OnServerEvent:Connect(onCombatRequest)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			swingStates[player] = HitValidation.newState()
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player)
		swingStates[player] = nil
		strikes[player] = nil
	end)
end

return CombatService
