--!strict
--[[
	CombatController
	Client side of combat. It sends intent and shows feedback; it decides nothing.

	  * Input: mouse click, touch tap (outside UI), or gamepad R2.
	  * A local cooldown copy stops pointless remote spam. The server still
	    re-checks every request with its own clock.
	  * The swing animation and slash effect play at once (prediction), so input
	    feels instant. Other players' slashes come from the server's CombatEffect.
	  * Damage numbers and hit flashes appear only when the server confirms a hit.
	  * The slash is built from a Part and a Trail, so it needs no uploaded assets.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Combat.CombatConfig)
local HitValidation = require(Shared.Combat.HitValidation)
local Remotes = require(Shared.Net.Remotes)

local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 196, 61)
local SLASH_SECONDS = 0.14

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

-- A blade that sweeps across the swing arc, leaving a Trail behind it.
-- Odd combo hits sweep right-to-left, even hits left-to-right.
local function playSlash(
	character: Model,
	facing: Vector3,
	range: number,
	arcDegrees: number,
	comboIndex: number,
	isFinisher: boolean
)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if root == nil or flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit

	local length = range * 0.8
	local color = if isFinisher then GOLD else WHITE

	local blade = Instance.new("Part")
	blade.Name = "Slash"
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.CastShadow = false
	blade.Material = Enum.Material.Neon
	blade.Color = color
	blade.Transparency = 0.4
	blade.Size = Vector3.new(0.08, if isFinisher then 0.7 else 0.4, length)

	local inner = Instance.new("Attachment")
	inner.Position = Vector3.new(0, 0, length * 0.1)
	inner.Parent = blade
	local outer = Instance.new("Attachment")
	outer.Position = Vector3.new(0, 0, -length / 2)
	outer.Parent = blade

	local trail = Instance.new("Trail")
	trail.Attachment0 = inner
	trail.Attachment1 = outer
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = if isFinisher then 0.28 else 0.18
	trail.MinLength = 0
	trail.FaceCamera = false
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = blade

	local half = math.rad(arcDegrees / 2)
	local from, to = half, -half
	if comboIndex % 2 == 0 then
		from, to = -half, half
	end

	local function place(alpha: number)
		local origin = root.Position + Vector3.new(0, 0.6, 0)
		local angle = from + (to - from) * alpha
		blade.CFrame = CFrame.lookAt(origin, origin + flat)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, -length / 2 - 0.5)
	end
	place(0)
	blade.Parent = Workspace

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - started) / SLASH_SECONDS, 0, 1)
		place(alpha)
		blade.Transparency = 0.4 + 0.6 * alpha
		if alpha >= 1 then
			connection:Disconnect()
			trail.Enabled = false
			task.delay(trail.Lifetime, function()
				blade:Destroy()
			end)
		end
	end)
end

-- Short white flash on a model that was hit.
local function flashHit(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 0.1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
	task.delay(0.2, function()
		highlight:Destroy()
	end)
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

	-- Prediction: the server may still reject this swing; then no damage appears.
	playSlash(character :: Model, aim, weapon.Range, weapon.ArcDegrees, result.comboIndex, result.isFinisher)

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
	gui.Size = if isFinisher then UDim2.fromOffset(170, 70) else UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(damage)
	label.TextScaled = true
	label.TextColor3 = if isFinisher then GOLD else WHITE
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
	local isFinisher = effect.isFinisher == true

	-- The local player's slash already played on input; draw everyone else's.
	local attacker = effect.attacker
	if
		typeof(attacker) == "Instance"
		and attacker:IsA("Model")
		and attacker ~= player.Character
		and typeof(effect.facing) == "Vector3"
		and type(effect.range) == "number"
		and type(effect.arc) == "number"
		and type(effect.comboIndex) == "number"
	then
		playSlash(attacker, effect.facing, effect.range, effect.arc, effect.comboIndex, isFinisher)
	end

	for _, hit in effect.hits do
		if typeof(hit.position) == "Vector3" and type(hit.damage) == "number" then
			showDamage(hit.position, hit.damage, isFinisher)
		end
		if typeof(hit.target) == "Instance" and hit.target:IsA("Model") then
			flashHit(hit.target)
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
