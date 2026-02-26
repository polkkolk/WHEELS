-- RoundHUDController.client.lua
-- Shows intermission countdown, voting phase label, round timer, and live kill count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 10)
if not GameEvent then return end

------------------------------------------------------------------------
-- BUILD HUD
------------------------------------------------------------------------
local sg = Instance.new("ScreenGui")
sg.Name = "RoundHUD"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

-- ── Top-centre panel: phase label + timer ───────────────────────────
local topPanel = Instance.new("Frame")
topPanel.Name = "TopPanel"
topPanel.Size = UDim2.new(0, 280, 0, 64)
topPanel.Position = UDim2.new(0.5, 0, 0, 18)
topPanel.AnchorPoint = Vector2.new(0.5, 0)
topPanel.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
topPanel.BackgroundTransparency = 0.3
topPanel.BorderSizePixel = 0
topPanel.Visible = false
topPanel.Parent = sg
local tpc = Instance.new("UICorner"); tpc.CornerRadius = UDim.new(0, 12); tpc.Parent = topPanel
local tps = Instance.new("UIStroke"); tps.Color = Color3.fromRGB(70, 80, 110); tps.Thickness = 1.5; tps.Parent = topPanel

-- Phase label (e.g. "INTERMISSION" / "FREE FOR ALL")
local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name = "PhaseLabel"
phaseLabel.Size = UDim2.new(1, -16, 0, 26)
phaseLabel.Position = UDim2.new(0, 8, 0, 6)
phaseLabel.BackgroundTransparency = 1
phaseLabel.Text = "INTERMISSION"
phaseLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
phaseLabel.Font = Enum.Font.GothamBold
phaseLabel.TextSize = 14
phaseLabel.Parent = topPanel

-- Timer (large number)
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, -16, 0, 32)
timerLabel.Position = UDim2.new(0, 8, 0, 28)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "0:30"
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextSize = 26
timerLabel.Parent = topPanel

-- ── Kill count (bottom-right corner during round) ────────────────────
local killFrame = Instance.new("Frame")
killFrame.Name = "KillFrame"
killFrame.Size = UDim2.new(0, 150, 0, 52)
killFrame.Position = UDim2.new(1, -16, 1, -120)
killFrame.AnchorPoint = Vector2.new(1, 0)
killFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
killFrame.BackgroundTransparency = 0.3
killFrame.BorderSizePixel = 0
killFrame.Visible = false
killFrame.Parent = sg
local kfc = Instance.new("UICorner"); kfc.CornerRadius = UDim.new(0, 10); kfc.Parent = killFrame
local kfs = Instance.new("UIStroke"); kfs.Color = Color3.fromRGB(70, 80, 110); kfs.Thickness = 1.5; kfs.Parent = killFrame

local killLabelTitle = Instance.new("TextLabel")
killLabelTitle.Size = UDim2.new(1, -12, 0, 20)
killLabelTitle.Position = UDim2.new(0, 6, 0, 4)
killLabelTitle.BackgroundTransparency = 1
killLabelTitle.Text = "YOUR KILLS"
killLabelTitle.TextColor3 = Color3.fromRGB(160, 170, 190)
killLabelTitle.Font = Enum.Font.GothamBold
killLabelTitle.TextSize = 12
killLabelTitle.Parent = killFrame

local killCount = Instance.new("TextLabel")
killCount.Name = "KillCount"
killCount.Size = UDim2.new(1, -12, 0, 26)
killCount.Position = UDim2.new(0, 6, 0, 22)
killCount.BackgroundTransparency = 1
killCount.Text = "0"
killCount.TextColor3 = Color3.fromRGB(255, 220, 60)
killCount.Font = Enum.Font.GothamBlack
killCount.TextSize = 24
killCount.Parent = killFrame

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function showPanel(phase, timerText, timerColor)
	topPanel.Visible = true
	phaseLabel.Text = phase
	timerLabel.Text = timerText
	timerLabel.TextColor3 = timerColor or Color3.fromRGB(255, 255, 255)
end

local function hidePanel()
	topPanel.Visible = false
end

local myRoundKills = 0

local function setKillCount(n)
	myRoundKills = n
	killCount.Text = tostring(n)
	-- Small pop animation
	TweenService:Create(killCount, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 30 }):Play()
	task.delay(0.1, function()
		if killCount and killCount.Parent then
			TweenService:Create(killCount, TweenInfo.new(0.1), { TextSize = 24 }):Play()
		end
	end)
end

------------------------------------------------------------------------
-- LISTEN TO GAME EVENTS
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)

	if eventName == "intermission" then
		local t = data and data.timeLeft or 0
		local color = (t <= 5) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
		local label = (data and data.waitingForPlayers)
			and "WAITING FOR PLAYERS..."
			or "INTERMISSION"
		showPanel(label, formatTime(t), color)
		killFrame.Visible = false

	elseif eventName == "voting" then
		-- Hide the HUD panel while the voting GUI is open
		topPanel.Visible = false
		killFrame.Visible = false

	elseif eventName == "vote_update" then
		local t = data and data.timeLeft or 0
		-- Only show HUD timer if the player has dismissed the voting cards
		local votingGui = playerGui:FindFirstChild("VotingGui")
		local votingOpen = votingGui and votingGui.Enabled ~= false
		if not votingOpen then
			-- Voting GUI was dismissed — show the timer in the HUD
			topPanel.Visible = true
			phaseLabel.Text = "VOTING"
			timerLabel.Text = formatTime(t)
			timerLabel.TextColor3 = (t <= 3) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 220, 60)
		else
			topPanel.Visible = false
		end

	elseif eventName == "round_start" then
		myRoundKills = 0
		setKillCount(0)
		showPanel(data and data.gamemodeName or "FREE FOR ALL", formatTime(data and data.duration or 300), Color3.fromRGB(255, 255, 255))
		killFrame.Visible = true

	elseif eventName == "round_tick" then
		local t = data and data.timeLeft or 0
		local color = (t <= 30) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
		timerLabel.Text = formatTime(t)
		timerLabel.TextColor3 = color

	elseif eventName == "kills_update" then
		-- data is a {name = kills} table; find our own count
		if data and data[player.Name] then
			setKillCount(data[player.Name])
		end

	elseif eventName == "round_end" then
		hidePanel()
		killFrame.Visible = false

	end
end)

print("✅ RoundHUDController Loaded")
