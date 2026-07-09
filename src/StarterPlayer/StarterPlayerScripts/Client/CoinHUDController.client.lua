-- CoinHUDController.client.lua
-- Displays a small coin counter in the bottom-right corner of the screen.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for leaderstats
local ls = player:WaitForChild("leaderstats", 30)
if not ls then warn("[CoinHUD] No leaderstats found!"); return end
local coinsStat = ls:WaitForChild("Money", 10)
if not coinsStat then warn("[CoinHUD] No Money stat found!"); return end

-- BUILD UI
local sg = Instance.new("ScreenGui")
sg.Name = "CoinHUD"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 5
sg.Parent = playerGui

-- Container frame (bottom-right)
local container = Instance.new("Frame")
container.Name = "CoinContainer"
container.Size = UDim2.new(0, 140, 0, 42)
container.Position = UDim2.new(1, -160, 1, -60)
container.AnchorPoint = Vector2.new(0, 0.5)
container.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = sg

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 200, 40)
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.Parent = container

-- Coin icon (gold circle with $ text)
local coinIcon = Instance.new("Frame")
coinIcon.Name = "CoinIcon"
coinIcon.Size = UDim2.new(0, 30, 0, 30)
coinIcon.Position = UDim2.new(0, 8, 0.5, 0)
coinIcon.AnchorPoint = Vector2.new(0, 0.5)
coinIcon.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
coinIcon.BorderSizePixel = 0
coinIcon.Parent = container

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.5, 0)
iconCorner.Parent = coinIcon

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(200, 150, 20)
iconStroke.Thickness = 2
iconStroke.Parent = coinIcon

local iconLabel = Instance.new("TextLabel")
iconLabel.Size = UDim2.fromScale(1, 1)
iconLabel.BackgroundTransparency = 1
iconLabel.Text = "$"
iconLabel.TextColor3 = Color3.fromRGB(80, 50, 0)
iconLabel.Font = Enum.Font.GothamBlack
iconLabel.TextSize = 18
iconLabel.Parent = coinIcon

-- Coin count label
local countLabel = Instance.new("TextLabel")
countLabel.Name = "CoinCount"
countLabel.Size = UDim2.new(1, -50, 1, 0)
countLabel.Position = UDim2.new(0, 44, 0, 0)
countLabel.BackgroundTransparency = 1
countLabel.Text = tostring(coinsStat.Value)
countLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
countLabel.Font = Enum.Font.GothamBlack
countLabel.TextSize = 20
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = container

-- Subtle text shadow
local shadow = Instance.new("TextLabel")
shadow.Size = UDim2.fromScale(1, 1)
shadow.Position = UDim2.new(0, 1, 0, 1)
shadow.BackgroundTransparency = 1
shadow.Text = tostring(coinsStat.Value)
shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
shadow.TextTransparency = 0.6
shadow.Font = Enum.Font.GothamBlack
shadow.TextSize = 20
shadow.TextXAlignment = Enum.TextXAlignment.Left
shadow.ZIndex = -1
shadow.Parent = countLabel

-- LIVE UPDATE (only when CoinFlyIn is NOT controlling the display)
-- CoinFlyIn directly manipulates countLabel.Text during animations,
-- so we skip the auto-update if a fly-in recently happened.
local lastFlyInTime = 0

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameEvent = ReplicatedStorage:WaitForChild("GameEvent")
local ChallengeCompleteEvent = ReplicatedStorage:FindFirstChild("ChallengeCompleteEvent") or ReplicatedStorage:WaitForChild("ChallengeCompleteEvent", 10)

GameEvent.OnClientEvent:Connect(function(eventName)
	if eventName == "round_end" then
		lastFlyInTime = tick() + 5 -- suppress for up to 5 seconds
	end
end)
if ChallengeCompleteEvent then
	ChallengeCompleteEvent.OnClientEvent:Connect(function()
		lastFlyInTime = tick() + 5
	end)
end

local lastCoinValue = coinsStat.Value

coinsStat.Changed:Connect(function(newValue)
	if newValue > lastCoinValue and player:GetAttribute("DataLoaded") then
		local sfx = Instance.new("Sound")
		sfx.SoundId = "rbxassetid://72764897006138"
		sfx.Volume = 0.8
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		sfx.Ended:Once(function() sfx:Destroy() end)
	end
	lastCoinValue = newValue

	-- Give a 0.05s delay so the RemoteEvents above can trigger and set lastFlyInTime FIRST
	task.delay(0.05, function()
		if tick() < lastFlyInTime then return end
		
		countLabel.Text = tostring(newValue)
		shadow.Text = tostring(newValue)
	end)
end)

-- Expose a function for CoinFlyIn to call to suppress auto-updates
-- (CoinFlyIn sets the attribute "FlyInActive" on the container)
container:GetAttributeChangedSignal("FlyInActive"):Connect(function()
	if container:GetAttribute("FlyInActive") then
		lastFlyInTime = tick()
	end
end)

print("✅ CoinHUDController Loaded")
