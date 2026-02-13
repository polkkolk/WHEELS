--[[
	HUDController.client.lua
	Full combat HUD: health bar, ammo, crosshair, kill feed, scoreboard (Tab),
	timer, speedometer, and game announcements.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatConfig"))
local CombatState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatState"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Hide default cursor, we use our custom crosshair
UserInputService.MouseIconEnabled = false

----------------------------------------------------------------------
-- REMOTE REFERENCES
----------------------------------------------------------------------
local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local HealthUpdate = CombatRemotes:WaitForChild("HealthUpdate")
local AmmoUpdate = CombatRemotes:WaitForChild("AmmoUpdate")
local KillFeedEvent = CombatRemotes:WaitForChild("KillFeed")
local ScoreUpdate = CombatRemotes:WaitForChild("ScoreUpdate")

local GameRemotes = ReplicatedStorage:WaitForChild("GameRemotes")
local GameStateEvent = GameRemotes:WaitForChild("GameStateChanged")
local TimerEvent = GameRemotes:WaitForChild("TimerUpdate")
local AnnouncementEvent = GameRemotes:WaitForChild("Announcement")

----------------------------------------------------------------------
-- SCREEN GUI
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CombatHUD"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player.PlayerGui

----------------------------------------------------------------------
-- HELPER: Create rounded frame
----------------------------------------------------------------------
local function makeFrame(props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = props.Color or Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = props.Transparency or 0.4
	frame.BorderSizePixel = 0
	frame.Size = props.Size or UDim2.fromOffset(100, 30)
	frame.Position = props.Position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	frame.Parent = props.Parent or screenGui

	if props.Corner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.Corner)
		corner.Parent = frame
	end

	return frame
end

local function makeLabel(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.Size or UDim2.fromScale(1, 1)
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = props.Color or Color3.fromRGB(255, 255, 255)
	label.TextSize = props.TextSize or 16
	label.Text = props.Text or ""
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	label.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	label.Parent = props.Parent or screenGui
	return label
end

----------------------------------------------------------------------
-- 1. HEALTH BAR (Bottom Left)
----------------------------------------------------------------------
local healthContainer = makeFrame({
	Size = UDim2.fromOffset(260, 36),
	Position = UDim2.new(0, 24, 1, -24),
	Anchor = Vector2.new(0, 1),
	Color = Color3.fromRGB(15, 15, 15),
	Transparency = 0.3,
	Corner = 8,
})

local healthFill = makeFrame({
	Size = UDim2.fromScale(1, 1),
	Color = Color3.fromRGB(80, 220, 80),
	Transparency = 0.1,
	Corner = 8,
	Parent = healthContainer,
})

local healthLabel = makeLabel({
	Text = "100",
	TextSize = 18,
	Parent = healthContainer,
})

local healthIcon = makeLabel({
	Text = "❤️",
	TextSize = 16,
	Size = UDim2.fromOffset(30, 36),
	Position = UDim2.fromOffset(-32, 0),
	Parent = healthContainer,
})

local currentHealth = CombatConfig.MaxHealth
local displayHealth = CombatConfig.MaxHealth

----------------------------------------------------------------------
-- 2. AMMO COUNTER (Bottom Right)
----------------------------------------------------------------------
local ammoContainer = makeFrame({
	Size = UDim2.fromOffset(160, 50),
	Position = UDim2.new(1, -24, 1, -24),
	Anchor = Vector2.new(1, 1),
	Color = Color3.fromRGB(15, 15, 15),
	Transparency = 0.3,
	Corner = 8,
})

local ammoLabel = makeLabel({
	Text = "30 / 30",
	TextSize = 22,
	Parent = ammoContainer,
})

local reloadLabel = makeLabel({
	Text = "RELOADING...",
	TextSize = 14,
	Color = Color3.fromRGB(255, 200, 50),
	Position = UDim2.fromOffset(0, -20),
	Size = UDim2.fromScale(1, 0.4),
	Parent = ammoContainer,
})
reloadLabel.Visible = false

----------------------------------------------------------------------
-- 3. CROSSHAIR (Center)
----------------------------------------------------------------------
local crosshairContainer = Instance.new("Frame")
crosshairContainer.Name = "Crosshair"
crosshairContainer.BackgroundTransparency = 1
crosshairContainer.Size = UDim2.fromOffset(30, 30)
crosshairContainer.Position = UDim2.fromScale(0.5, 0.5)
crosshairContainer.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairContainer.ZIndex = 100
crosshairContainer.Parent = screenGui

local crosshairLines = {}
local lineData = {
	{Size = UDim2.fromOffset(2, 12), Pos = UDim2.fromScale(0.5, 0), Anchor = Vector2.new(0.5, 1)},  -- Top
	{Size = UDim2.fromOffset(2, 12), Pos = UDim2.fromScale(0.5, 1), Anchor = Vector2.new(0.5, 0)},  -- Bottom
	{Size = UDim2.fromOffset(12, 2), Pos = UDim2.fromScale(0, 0.5), Anchor = Vector2.new(1, 0.5)},  -- Left
	{Size = UDim2.fromOffset(12, 2), Pos = UDim2.fromScale(1, 0.5), Anchor = Vector2.new(0, 0.5)},  -- Right
}

for _, data in ipairs(lineData) do
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BorderSizePixel = 0
	line.Size = data.Size
	line.Position = data.Pos
	line.AnchorPoint = data.Anchor
	line.Parent = crosshairContainer
	table.insert(crosshairLines, line)
end

-- Center dot
local centerDot = Instance.new("Frame")
centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
centerDot.BorderSizePixel = 0
centerDot.Size = UDim2.fromOffset(3, 3)
centerDot.Position = UDim2.fromScale(0.5, 0.5)
centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
centerDot.Parent = crosshairContainer
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = centerDot

----------------------------------------------------------------------
-- 4. KILL FEED (Top Right)
----------------------------------------------------------------------
local killFeedContainer = Instance.new("Frame")
killFeedContainer.Name = "KillFeed"
killFeedContainer.BackgroundTransparency = 1
killFeedContainer.Size = UDim2.fromOffset(300, 200)
killFeedContainer.Position = UDim2.new(1, -24, 0, 60)
killFeedContainer.AnchorPoint = Vector2.new(1, 0)
killFeedContainer.Parent = screenGui

local killFeedLayout = Instance.new("UIListLayout")
killFeedLayout.SortOrder = Enum.SortOrder.LayoutOrder
killFeedLayout.VerticalAlignment = Enum.VerticalAlignment.Top
killFeedLayout.Padding = UDim.new(0, 4)
killFeedLayout.Parent = killFeedContainer

local killFeedOrder = 0

local function addKillFeedEntry(killerName, victimName)
	killFeedOrder = killFeedOrder + 1

	local entry = makeFrame({
		Size = UDim2.new(1, 0, 0, 26),
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.5,
		Corner = 4,
		Parent = killFeedContainer,
	})
	entry.LayoutOrder = killFeedOrder

	local isMe = killerName == player.Name
	local killerColor = isMe and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 255, 255)
	local victimColor = (victimName == player.Name) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(200, 200, 200)

	makeLabel({
		Text = killerName .. " 💀 " .. victimName,
		TextSize = 14,
		Color = killerColor,
		XAlign = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		Parent = entry,
	})

	-- Auto-remove after 6 seconds
	task.spawn(function()
		task.wait(4)
		for i = 1, 10 do
			task.wait(0.03)
			entry.BackgroundTransparency = 0.5 + (i / 10) * 0.5
			for _, child in ipairs(entry:GetChildren()) do
				if child:IsA("TextLabel") then
					child.TextTransparency = i / 10
				end
			end
		end
		entry:Destroy()
	end)
end

----------------------------------------------------------------------
-- 5. TIMER (Top Center)
----------------------------------------------------------------------
local timerLabel = makeLabel({
	Text = "5:00",
	TextSize = 24,
	Position = UDim2.new(0.5, 0, 0, 16),
	Anchor = Vector2.new(0.5, 0),
	Size = UDim2.fromOffset(120, 36),
	Color = Color3.fromRGB(255, 255, 255),
})

local timerBg = makeFrame({
	Size = UDim2.fromOffset(120, 36),
	Position = UDim2.new(0.5, 0, 0, 16),
	Anchor = Vector2.new(0.5, 0),
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.5,
	Corner = 8,
})
timerLabel.Parent = timerBg
timerLabel.Position = UDim2.fromScale(0, 0)
timerLabel.AnchorPoint = Vector2.new(0, 0)

----------------------------------------------------------------------
-- 6. ANNOUNCEMENT (Center Top)
----------------------------------------------------------------------
local announcementLabel = makeLabel({
	Text = "",
	TextSize = 28,
	Position = UDim2.new(0.5, 0, 0.2, 0),
	Anchor = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(600, 50),
})
announcementLabel.TextStrokeTransparency = 0.5
announcementLabel.Visible = false

local function showAnnouncement(text, color)
	announcementLabel.Text = text
	announcementLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	announcementLabel.Visible = true
	announcementLabel.TextTransparency = 0

	task.spawn(function()
		task.wait(3)
		for i = 1, 10 do
			task.wait(0.05)
			announcementLabel.TextTransparency = i / 10
		end
		announcementLabel.Visible = false
	end)
end

----------------------------------------------------------------------
-- 7. SCOREBOARD (Tab to Show)
----------------------------------------------------------------------
local scoreboardGui = Instance.new("Frame")
scoreboardGui.Name = "Scoreboard"
scoreboardGui.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
scoreboardGui.BackgroundTransparency = 0.15
scoreboardGui.Size = UDim2.fromOffset(420, 400)
scoreboardGui.Position = UDim2.fromScale(0.5, 0.5)
scoreboardGui.AnchorPoint = Vector2.new(0.5, 0.5)
scoreboardGui.BorderSizePixel = 0
scoreboardGui.Visible = false
scoreboardGui.Parent = screenGui

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 12)
sbCorner.Parent = scoreboardGui

local sbTitle = makeLabel({
	Text = "SCOREBOARD",
	TextSize = 20,
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 30),
	Parent = scoreboardGui,
})

-- Header row
local headerRow = makeFrame({
	Size = UDim2.new(1, -24, 0, 24),
	Position = UDim2.fromOffset(12, 48),
	Color = Color3.fromRGB(40, 40, 50),
	Transparency = 0.3,
	Corner = 4,
	Parent = scoreboardGui,
})

makeLabel({ Text = "Player", TextSize = 13, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromOffset(8, 0), XAlign = Enum.TextXAlignment.Left, Parent = headerRow })
makeLabel({ Text = "K", TextSize = 13, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.55, 0), Parent = headerRow })
makeLabel({ Text = "D", TextSize = 13, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.7, 0), Parent = headerRow })
makeLabel({ Text = "K/D", TextSize = 13, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.85, 0), Parent = headerRow })

local scoreEntryContainer = Instance.new("Frame")
scoreEntryContainer.Name = "Entries"
scoreEntryContainer.BackgroundTransparency = 1
scoreEntryContainer.Size = UDim2.new(1, -24, 1, -84)
scoreEntryContainer.Position = UDim2.fromOffset(12, 76)
scoreEntryContainer.Parent = scoreboardGui

local sbLayout = Instance.new("UIListLayout")
sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
sbLayout.Padding = UDim.new(0, 3)
sbLayout.Parent = scoreEntryContainer

local cachedScores = {}

local function updateScoreboard(scores)
	cachedScores = scores
	-- Clear old entries
	for _, child in ipairs(scoreEntryContainer:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for i, data in ipairs(scores) do
		local isMe = data.Name == player.Name
		local bgColor = isMe and Color3.fromRGB(40, 60, 80) or Color3.fromRGB(25, 25, 35)

		local row = makeFrame({
			Size = UDim2.new(1, 0, 0, 28),
			Color = bgColor,
			Transparency = 0.3,
			Corner = 4,
			Parent = scoreEntryContainer,
		})
		row.LayoutOrder = i

		local nameColor = Color3.fromRGB(255, 255, 255)
		if data.Team == "Red" then
			nameColor = Color3.fromRGB(255, 100, 100)
		elseif data.Team == "Blue" then
			nameColor = Color3.fromRGB(100, 150, 255)
		end

		makeLabel({ Text = data.Name, TextSize = 14, Color = nameColor, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromOffset(8, 0), XAlign = Enum.TextXAlignment.Left, Parent = row })
		makeLabel({ Text = tostring(data.Kills), TextSize = 14, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.55, 0), Parent = row })
		makeLabel({ Text = tostring(data.Deaths), TextSize = 14, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.7, 0), Parent = row })

		local kd = data.Deaths > 0 and string.format("%.1f", data.Kills / data.Deaths) or tostring(data.Kills)
		makeLabel({ Text = kd, TextSize = 14, Size = UDim2.fromScale(0.15, 1), Position = UDim2.fromScale(0.85, 0), Parent = row })
	end
end

-- Tab key toggles scoreboard
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		scoreboardGui.Visible = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab then
		scoreboardGui.Visible = false
	end
end)

----------------------------------------------------------------------
-- 8. SPEEDOMETER (Bottom Center)
----------------------------------------------------------------------
local speedContainer = makeFrame({
	Size = UDim2.fromOffset(120, 36),
	Position = UDim2.new(0.5, 0, 1, -24),
	Anchor = Vector2.new(0.5, 1),
	Color = Color3.fromRGB(15, 15, 15),
	Transparency = 0.4,
	Corner = 8,
})

local speedLabel = makeLabel({
	Text = "0",
	TextSize = 20,
	Parent = speedContainer,
	Size = UDim2.new(0.65, 0, 1, 0),
	Position = UDim2.fromScale(0, 0),
})

local speedUnit = makeLabel({
	Text = "SPS",
	TextSize = 11,
	Color = Color3.fromRGB(150, 150, 150),
	Parent = speedContainer,
	Size = UDim2.new(0.35, 0, 1, 0),
	Position = UDim2.fromScale(0.65, 0),
})

----------------------------------------------------------------------
-- 9. GAME STATE DISPLAY (Below Timer)
----------------------------------------------------------------------
local stateLabel = makeLabel({
	Text = "Waiting for players...",
	TextSize = 14,
	Color = Color3.fromRGB(180, 180, 180),
	Position = UDim2.new(0.5, 0, 0, 56),
	Anchor = Vector2.new(0.5, 0),
	Size = UDim2.fromOffset(300, 20),
})

----------------------------------------------------------------------
-- UPDATE LOOP
----------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	-- Move crosshair to mouse position
	local mousePos = UserInputService:GetMouseLocation()
	crosshairContainer.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)

	-- Smooth health bar
	displayHealth = displayHealth + (currentHealth - displayHealth) * dt * 10
	local healthPct = math.clamp(displayHealth / CombatConfig.MaxHealth, 0, 1)
	healthFill.Size = UDim2.new(healthPct, 0, 1, 0)
	healthLabel.Text = tostring(math.ceil(displayHealth))

	-- Health bar color (green → yellow → red)
	if healthPct > 0.6 then
		healthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	elseif healthPct > 0.3 then
		healthFill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
	else
		healthFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	end

	-- Ammo from shared combat state
	local ammo = CombatState.Ammo
	local mag = CombatState.MaxAmmo
	local reloading = CombatState.Reloading

	ammoLabel.Text = ammo .. " / " .. mag
	reloadLabel.Visible = reloading

	if ammo <= 5 and ammo > 0 then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	elseif ammo == 0 then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
	else
		ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	-- Speedometer
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local vel = rootPart.AssemblyLinearVelocity
			local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			speedLabel.Text = tostring(math.floor(flatSpeed))
		end
	end
end)

----------------------------------------------------------------------
-- EVENT HANDLERS
----------------------------------------------------------------------
HealthUpdate.OnClientEvent:Connect(function(health, maxHealth)
	currentHealth = health
end)

KillFeedEvent.OnClientEvent:Connect(function(killerName, victimName)
	addKillFeedEntry(killerName, victimName)
end)

ScoreUpdate.OnClientEvent:Connect(function(scores)
	updateScoreboard(scores)
end)

TimerEvent.OnClientEvent:Connect(function(timeLeft)
	local mins = math.floor(timeLeft / 60)
	local secs = timeLeft % 60
	timerLabel.Text = string.format("%d:%02d", mins, secs)

	if timeLeft <= 30 then
		timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	else
		timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end)

GameStateEvent.OnClientEvent:Connect(function(state, mode)
	if state == "Waiting" then
		stateLabel.Text = "Waiting for players..."
	elseif state == "Playing" then
		stateLabel.Text = "🔫 " .. mode
	elseif state == "Intermission" then
		stateLabel.Text = "Intermission"
	end
end)

AnnouncementEvent.OnClientEvent:Connect(function(message, color)
	showAnnouncement(message, color)
end)

print("✅ HUDController loaded")
