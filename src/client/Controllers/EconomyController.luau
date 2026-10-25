--!strict
--[[
	EconomyController
	Idle-economy UI, built in code so the repo has no binary .rbxm files.

	The server sends the full state about once per second. Between updates
	the cash counter is interpolated from the rate, so it ticks smoothly.
	This is display only: every purchase is still priced and checked on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy.Economy)
local EconomyConfig = require(Shared.Economy.EconomyConfig)
local NumberFormat = require(Shared.Economy.NumberFormat)
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer

local EconomyController = {}

-- Palette
local INK = Color3.fromRGB(14, 17, 23)
local PANEL = Color3.fromRGB(22, 27, 36)
local ROW = Color3.fromRGB(30, 37, 49)
local LINE = Color3.fromRGB(46, 56, 72)
local TEXT = Color3.fromRGB(235, 239, 245)
local MUTED = Color3.fromRGB(140, 152, 170)
local ACCENT = Color3.fromRGB(94, 234, 160)
local GOLD = Color3.fromRGB(255, 196, 61)
local DISABLED = Color3.fromRGB(58, 66, 80)

type State = {
	cash: number,
	rate: number,
	lifetimeCash: number,
	prestige: number,
	pendingPrestige: number,
	generators: { [string]: number },
	boostExpiresAt: number,
	serverTime: number,
}

local state: State? = nil
local receivedAt = 0
local buyMode = 1 -- 1, 10, or 0 (max)

local rows: { [string]: { owned: TextLabel, rate: TextLabel, button: TextButton, price: TextLabel } } = {}
local cashLabel: TextLabel
local rateLabel: TextLabel
local boostLabel: TextLabel
local prestigeButton: TextButton
local modeButtons: { [number]: TextButton } = {}
local toastHolder: Frame

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = TEXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = INK
	b.BackgroundColor3 = ACCENT
	for key, value in props do
		(b :: any)[key] = value
	end
	corner(b, 8)
	b.Parent = parent
	return b
end

-- Cash shown now = last server cash + rate * time since that update.
local function displayedCash(): number
	if state == nil then
		return 0
	end
	return state.cash + state.rate * (os.clock() - receivedAt)
end

local function toast(text: string, color: Color3?)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 44)
	frame.BackgroundColor3 = PANEL
	corner(frame, 10)
	stroke(frame, color or LINE)
	local l = label(frame, {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Text = text,
		TextSize = 15,
		TextWrapped = true,
	})
	l.TextTransparency = 1
	frame.BackgroundTransparency = 1
	frame.Parent = toastHolder

	local fadeIn = TweenInfo.new(0.25)
	TweenService:Create(frame, fadeIn, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(l, fadeIn, { TextTransparency = 0 }):Play()
	task.delay(4, function()
		local fadeOut = TweenInfo.new(0.4)
		TweenService:Create(frame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, fadeOut, { TextTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

local function amountFor(generator: Economy.Generator, owned: number, cash: number): number
	if buyMode == 0 then
		return Economy.maxAffordable(generator, owned, cash)
	end
	return buyMode
end

local function refreshRows()
	if state == nil then
		return
	end
	local cash = displayedCash()
	for _, generator in EconomyConfig.Generators do
		local row = rows[generator.Id]
		local owned = state.generators[generator.Id] or 0
		local amount = amountFor(generator, owned, cash)
		local shownAmount = math.max(amount, 1)
		local cost = Economy.costOf(generator, owned, shownAmount)
		local affordable = amount > 0 and cost <= cash

		row.owned.Text = `{owned} owned`
		row.rate.Text = `+{NumberFormat.abbreviate(Economy.generatorRate(EconomyConfig, generator, owned))}/s`
		row.button.Text = `Buy {shownAmount}`
		row.price.Text = NumberFormat.abbreviate(cost)
		row.button.BackgroundColor3 = if affordable then ACCENT else DISABLED
		row.button.TextColor3 = if affordable then INK else MUTED
	end
end

local function refreshHeader()
	if state == nil then
		return
	end
	cashLabel.Text = `${NumberFormat.abbreviate(displayedCash())}`
	rateLabel.Text = `+{NumberFormat.abbreviate(state.rate)} / sec`

	local boostLeft = state.boostExpiresAt - (state.serverTime + (os.clock() - receivedAt))
	boostLabel.Visible = boostLeft > 0
	if boostLeft > 0 then
		boostLabel.Text = `2x BOOST  {NumberFormat.duration(boostLeft)}`
	end

	if state.pendingPrestige > 0 then
		prestigeButton.Text = `Prestige  +{state.pendingPrestige}  (+{state.pendingPrestige * 10}% income)`
		prestigeButton.BackgroundColor3 = GOLD
		prestigeButton.TextColor3 = INK
	else
		local nextPoint = state.prestige + 1
		local needed = Economy.lifetimeForPoints(EconomyConfig, nextPoint)
		prestigeButton.Text = `Prestige at ${NumberFormat.abbreviate(needed)} lifetime`
		prestigeButton.BackgroundColor3 = DISABLED
		prestigeButton.TextColor3 = MUTED
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 16, 0.5, 0)
	panel.Size = UDim2.fromOffset(340, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.04
	corner(panel, 14)
	stroke(panel, LINE)
	panel.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fitToScreen()
		local camera = workspace.CurrentCamera
		local height = camera and camera.ViewportSize.Y or 720
		scale.Scale = math.clamp(height / 820, 0.62, 1)
	end
	fitToScreen()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = panel

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	label(panel, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Text = "CASH",
		TextSize = 12,
		TextColor3 = MUTED,
		Font = Enum.Font.GothamBold,
	})
	cashLabel = label(panel, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 40),
		Text = "$0",
		TextSize = 38,
		Font = Enum.Font.GothamBlack,
	})
	rateLabel = label(panel, {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "+0 / sec",
		TextSize = 15,
		TextColor3 = ACCENT,
	})
	boostLabel = label(panel, {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 13,
		TextColor3 = GOLD,
		Font = Enum.Font.GothamBold,
		Visible = false,
	})

	-- Buy mode toggle: x1 / x10 / MAX
	local modes = Instance.new("Frame")
	modes.LayoutOrder = 5
	modes.Size = UDim2.new(1, 0, 0, 30)
	modes.BackgroundTransparency = 1
	modes.Parent = panel
	local modeList = Instance.new("UIListLayout")
	modeList.FillDirection = Enum.FillDirection.Horizontal
	modeList.Padding = UDim.new(0, 6)
	modeList.Parent = modes
	for i, mode in { 1, 10, 0 } do
		local b = button(modes, {
			LayoutOrder = i,
			Size = UDim2.new(1 / 3, -4, 1, 0),
			Text = if mode == 0 then "MAX" else `x{mode}`,
			TextSize = 14,
		})
		modeButtons[mode] = b
		b.Activated:Connect(function()
			buyMode = mode
			for m, other in modeButtons do
				other.BackgroundColor3 = if m == buyMode then ACCENT else ROW
				other.TextColor3 = if m == buyMode then INK else TEXT
			end
			refreshRows()
		end)
		b.BackgroundColor3 = if mode == buyMode then ACCENT else ROW
		b.TextColor3 = if mode == buyMode then INK else TEXT
	end

	-- Generator rows
	for i, generator in EconomyConfig.Generators do
		local row = Instance.new("Frame")
		row.LayoutOrder = 10 + i
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundColor3 = ROW
		corner(row, 10)
		row.Parent = panel

		label(row, {
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.new(1, -130, 0, 18),
			Text = generator.DisplayName,
			TextSize = 15,
			Font = Enum.Font.GothamBold,
		})
		local owned = label(row, {
			Position = UDim2.fromOffset(12, 31),
			Size = UDim2.fromOffset(90, 14),
			Text = "0 owned",
			TextSize = 12,
			TextColor3 = MUTED,
		})
		local rate = label(row, {
			Position = UDim2.fromOffset(104, 31),
			Size = UDim2.fromOffset(90, 14),
			Text = "+0/s",
			TextSize = 12,
			TextColor3 = ACCENT,
		})
		local buy = button(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(108, 40),
			Text = "",
			TextSize = 13,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local buyPadding = Instance.new("UIPadding")
		buyPadding.PaddingTop = UDim.new(0, 5)
		buyPadding.Parent = buy
		local price = label(buy, {
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 14),
			Text = "",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = INK,
			Font = Enum.Font.GothamMedium,
		})
		buy:GetPropertyChangedSignal("TextColor3"):Connect(function()
			price.TextColor3 = buy.TextColor3
		end)
		buy.Activated:Connect(function()
			Remotes.get("EconomyPurchase"):FireServer({ generatorId = generator.Id, amount = buyMode })
		end)

		rows[generator.Id] = { owned = owned, rate = rate, button = buy, price = price }
	end

	prestigeButton = button(panel, {
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Prestige",
		TextSize = 14,
		BackgroundColor3 = DISABLED,
		TextColor3 = MUTED,
	})
	prestigeButton.Activated:Connect(function()
		if state and state.pendingPrestige > 0 then
			Remotes.get("EconomyPrestige"):FireServer({})
		end
	end)

	toastHolder = Instance.new("Frame")
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 12)
	toastHolder.Size = UDim2.fromOffset(360, 0)
	toastHolder.AutomaticSize = Enum.AutomaticSize.Y
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local toastList = Instance.new("UIListLayout")
	toastList.Padding = UDim.new(0, 6)
	toastList.Parent = toastHolder

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.cash) ~= "number" then
		return
	end
	state = payload :: State
	receivedAt = os.clock()
	refreshHeader()
	refreshRows()
end

local function onNotice(notice: any)
	if type(notice) ~= "table" then
		return
	end
	if notice.kind == "WelcomeBack" then
		local suffix = if notice.capped then " (8h cap)" else ""
		toast(
			`Welcome back! You earned ${NumberFormat.abbreviate(notice.earned)} in {NumberFormat.duration(
				notice.seconds
			)}{suffix}`,
			ACCENT
		)
	elseif notice.kind == "Prestiged" then
		toast(`Prestiged! +{notice.gained} points ({notice.total} total)`, GOLD)
	elseif notice.kind == "BoostStarted" then
		toast("2x income boost active!", GOLD)
	elseif notice.kind == "CannotAfford" then
		toast("Not enough cash yet.")
	end
end

function EconomyController.Start()
	build()
	Remotes.get("EconomyState").OnClientEvent:Connect(onState)
	Remotes.get("EconomyNotice").OnClientEvent:Connect(onNotice)

	-- Smooth counter: refresh text a few times per second, not every frame.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			refreshHeader()
			refreshRows()
		end
	end)
end

return EconomyController
