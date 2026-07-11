-- LevelHUDController.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local XPAwardedEvent = ReplicatedStorage:WaitForChild("XPAwardedEvent")

-- 1. WAIT FOR LEADERSTATS & HIDDENSTATS
local ls = player:WaitForChild("leaderstats", 30)
local hiddenStats = player:WaitForChild("HiddenStats", 30)
if not ls or not hiddenStats then warn("[LevelHUD] No stats found!"); return end

local levelObj = ls:WaitForChild("Level", 30)
local xpObj = hiddenStats:WaitForChild("XP", 30)
if not levelObj or not xpObj then warn("[LevelHUD] Level/XP objects missing!"); return end

-- 2. CREATE UI
local sg = Instance.new("ScreenGui")
sg.Name = "LevelHUD"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "LevelContainer"
container.Size = UDim2.new(0, 300, 0, 32)
-- Placed to the right of the chatbox (default chat is around ~400px wide)
container.Position = UDim2.new(0, 420, 0, 10) 
container.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
container.BorderSizePixel = 0
container.Parent = sg

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(100, 110, 140)
stroke.Thickness = 2
stroke.Parent = container

-- Level Text (Left)
local currentLevelText = Instance.new("TextLabel")
currentLevelText.Size = UDim2.new(0, 40, 1, 0)
currentLevelText.Position = UDim2.new(0, 10, 0, 0)
currentLevelText.BackgroundTransparency = 1
currentLevelText.Text = tostring(levelObj.Value)
currentLevelText.TextColor3 = Color3.fromRGB(255, 255, 255)
currentLevelText.Font = Enum.Font.GothamBlack
currentLevelText.TextSize = 16
currentLevelText.TextXAlignment = Enum.TextXAlignment.Left
currentLevelText.Parent = container

-- Next Level Text (Right)
local nextLevelText = Instance.new("TextLabel")
nextLevelText.Size = UDim2.new(0, 40, 1, 0)
nextLevelText.Position = UDim2.new(1, -50, 0, 0)
nextLevelText.BackgroundTransparency = 1
nextLevelText.Text = tostring(levelObj.Value + 1)
nextLevelText.TextColor3 = Color3.fromRGB(180, 190, 210)
nextLevelText.Font = Enum.Font.GothamBold
nextLevelText.TextSize = 14
nextLevelText.TextXAlignment = Enum.TextXAlignment.Right
nextLevelText.Parent = container

-- XP Bar Background
local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -110, 0, 12)
barBg.Position = UDim2.new(0, 55, 0.5, -6)
barBg.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
barBg.BorderSizePixel = 0
barBg.Parent = container

local barBgCorner = Instance.new("UICorner")
barBgCorner.CornerRadius = UDim.new(1, 0)
barBgCorner.Parent = barBg

-- XP Bar Fill
local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold/Yellow
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = barFill

-- UPDATE LOGIC
local function updateBar(doBounce)
    local currentLevel = levelObj.Value
    local currentXP = xpObj.Value
    local requiredXP = math.floor(50 * (currentLevel ^ 1.6))
    
    currentLevelText.Text = tostring(currentLevel)
    nextLevelText.Text = tostring(currentLevel + 1)
    
    local fillRatio = math.clamp(currentXP / requiredXP, 0, 1)
    
    TweenService:Create(barFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(fillRatio, 0, 1, 0)}):Play()
    
    if doBounce then
        local uiScale = container:FindFirstChildOfClass("UIScale")
        if not uiScale then
            uiScale = Instance.new("UIScale")
            uiScale.Parent = container
        end
        uiScale.Scale = 1.1
        TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Scale = 1}):Play()
    end
end

-- Initialize
updateBar(false)

levelObj.Changed:Connect(function() updateBar(false) end)
xpObj.Changed:Connect(function() updateBar(false) end)

-- VFX STAR LOGIC
local function spawnStars(count, sourcePos)
    local cam = workspace.CurrentCamera
    for i = 1, count do
        task.delay((i - 1) * 0.05, function()
            local star = Instance.new("TextLabel")
            star.Text = "⭐"
            star.BackgroundTransparency = 1
            star.TextSize = 36
            star.Size = UDim2.new(0, 40, 0, 40)
            
            -- Spawn around center of screen, or custom sourcePos
            local cx, cy
            if sourcePos then
                cx = cam.ViewportSize.X * sourcePos.X.Scale + sourcePos.X.Offset
                cy = cam.ViewportSize.Y * sourcePos.Y.Scale + sourcePos.Y.Offset
            else
                cx, cy = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
            end
            
            local rx = cx + math.random(-150, 150)
            local ry = cy + math.random(-150, 150)
            star.Position = UDim2.new(0, rx, 0, ry)
            star.Parent = sg
            
            -- Tween to the bar
            local targetPos = container.AbsolutePosition + Vector2.new(container.AbsoluteSize.X / 2, container.AbsoluteSize.Y / 2)
            local t = TweenService:Create(star, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0, targetPos.X, 0, targetPos.Y),
                TextSize = 10,
                TextTransparency = 0.5
            })
            t:Play()
            t.Completed:Connect(function()
                star:Destroy()
                updateBar(true) -- Bounce bar on hit
            end)
        end)
    end
end

XPAwardedEvent.OnClientEvent:Connect(function(amount, reason, leveledUp)
    if reason == "Kill" then
        spawnStars(5)
    end
end)

local spawnEvent = ReplicatedStorage:FindFirstChild("SpawnXPStarsEvent")
if not spawnEvent then
    spawnEvent = Instance.new("BindableEvent")
    spawnEvent.Name = "SpawnXPStarsEvent"
    spawnEvent.Parent = ReplicatedStorage
end
spawnEvent.Event:Connect(function(count, sourcePos)
    spawnStars(count, sourcePos)
end)

print("✅ LevelHUDController Loaded")
