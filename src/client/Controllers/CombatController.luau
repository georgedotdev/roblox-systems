--!strict
--[[
	CombatController
	Client side of combat. It sends intent and shows feedback; it decides nothing.

	  * Input: mouse click, touch tap (outside UI), or gamepad R2.
	  * A local cooldown copy stops pointless remote spam. The server still
	    re-checks every request with its own clock.
	  * The swing animation plays at once (prediction) so input feels instant.
	  * Damage numbers appear only when the server confirms a hit.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Combat.CombatConfig)
local HitValidation = require(Shared.Combat.HitValidation)
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer

local CombatController = {}

local localState = HitValidation.newState()
local animationTracks: { [string]: AnimationTrack } = {}

local function equippedWeapon(): CombatConfig.Weapon
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local weaponId = tool and tool:GetAttribute("WeaponId")
	if type(weaponId) == "string" and CombatConfig.Weapons[weaponId] then
		return CombatConfig.Weapons[weaponId]
	end
	return CombatConfig.Weapons[CombatConfig.DefaultWeapon]
end

local function playSwingAnimation(weapon: CombatConfig.Weapon, comboIndex: number)
	local animationId = weapon.AnimationIds[comboIndex]
	if animationId == nil or animationId == "" then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local track = animationTracks[animationId]
	if track == nil then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		track = animator:LoadAnimation(animation)
		animationTracks[animationId] = track
	end
	track:Play(0.05)
end

local function swing()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		return
	end

	local weapon = equippedWeapon()
	local result = HitValidation.tryStartSwing(localState, weapon, Workspace:GetServerTimeNow())
	if not result.ok then
		return
	end
	playSwingAnimation(weapon, result.comboIndex)

	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local aim = if flat.Magnitude > 1e-3 then flat.Unit else root.CFrame.LookVector

	Remotes.get("CombatRequest"):FireServer({ action = "Swing", aim = aim })
end

local function onAction(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin then
		swing()
	end
	return Enum.ContextActionResult.Pass
end

-- Floating damage number above the target.
local function showDamage(position: Vector3, damage: number, isFinisher: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new(math.random(-10, 10) / 10, 2.5, math.random(-10, 10) / 10)
	anchor.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(damage)
	label.TextScaled = true
	label.TextColor3 = if isFinisher then Color3.fromRGB(255, 196, 61) else Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { Position = anchor.Position + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.75, function()
		anchor:Destroy()
	end)
end

local function onCombatEffect(effect: any)
	if type(effect) ~= "table" or type(effect.hits) ~= "table" then
		return
	end
	for _, hit in effect.hits do
		if typeof(hit.position) == "Vector3" and type(hit.damage) == "number" then
			showDamage(hit.position, hit.damage, effect.isFinisher == true)
		end
	end
end

function CombatController.Start()
	ContextActionService:BindAction(
		"MeleeSwing",
		onAction,
		false,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.Touch,
		Enum.KeyCode.ButtonR2
	)
	Remotes.get("CombatEffect").OnClientEvent:Connect(onCombatEffect)

	player.CharacterAdded:Connect(function()
		localState = HitValidation.newState()
		table.clear(animationTracks)
	end)
end

return CombatController
