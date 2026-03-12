local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local DuelEvent = ReplicatedStorage:WaitForChild("DuelEvent")

-- 1. Create the UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DuelUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = gui

-- BUTTON (Right side)
local queueButton = Instance.new("TextButton")
queueButton.Name = "QueueButton"
queueButton.Size = UDim2.new(0, 100, 0, 40)
queueButton.Position = UDim2.new(1, -120, 0.5, 0) -- Right edge, mid height
queueButton.AnchorPoint = Vector2.new(1, 0.5)
queueButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
queueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
queueButton.Text = "1v1"
queueButton.Font = Enum.Font.GothamBold
queueButton.TextSize = 18
queueButton.TextWrapped = true
queueButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = queueButton

-- TIMER BAR (Top center)
local timerFrame = Instance.new("Frame")
timerFrame.Name = "TimerFrame"
timerFrame.Size = UDim2.new(0, 200, 0, 50)
timerFrame.Position = UDim2.new(0.5, 0, 0, -60) -- Starts hidden off-screen (-Y)
timerFrame.AnchorPoint = Vector2.new(0.5, 0)
timerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
timerFrame.Visible = false
timerFrame.Parent = screenGui

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 8)
timerCorner.Parent = timerFrame

local timerStroke = Instance.new("UIStroke")
timerStroke.Color = Color3.fromRGB(255, 0, 0)
timerStroke.Thickness = 2
timerStroke.Parent = timerFrame

local timerText = Instance.new("TextLabel")
timerText.Size = UDim2.new(1, 0, 1, 0)
timerText.BackgroundTransparency = 1
timerText.TextColor3 = Color3.fromRGB(255, 255, 255)
timerText.Font = Enum.Font.GothamBold
timerText.TextSize = 24
timerText.Text = "3:00"
timerText.Parent = timerFrame

local isQueued = false

-- Queue Button Logic
queueButton.MouseButton1Click:Connect(function()
    if isQueued then return end
    isQueued = true
    queueButton.Text = "SEARCHING..."
    queueButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    DuelEvent:FireServer("join_queue")
end)

-- Server Event Handler
DuelEvent.OnClientEvent:Connect(function(action, arg)
    if action == "duel_start" then
        isQueued = false
        queueButton.Visible = false -- Hide queue button during duel
        
        -- FORCE CLEAR ANY LINGERING UI
        local vGui = gui:FindFirstChild("VotingGui")
        if vGui then vGui:Destroy() end
        local tGui = gui:FindFirstChild("TeamIndicatorGui")
        if tGui then tGui:Destroy() end
        local kGui = gui:FindFirstChild("KillNotificationGui")
        if kGui then kGui:Destroy() end
        
        -- Slide down timer
        timerFrame.Visible = true
        timerText.Text = "3:00"
        TweenService:Create(timerFrame, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 20)
        }):Play()

    elseif action == "time_update" then
        local mins = math.floor(arg / 60)
        local secs = arg % 60
        timerText.Text = string.format("%d:%02d", mins, secs)
        
        if arg <= 10 then
            timerText.TextColor3 = Color3.fromRGB(255, 50, 50)
        end

    elseif action == "duel_end" then
        isQueued = false
        queueButton.Text = "1v1"
        queueButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        queueButton.Visible = true
        timerText.TextColor3 = Color3.fromRGB(255, 255, 255)

        -- Slide timer up and hide
        local twn = TweenService:Create(timerFrame, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 0, -60)
        })
        twn:Play()
        twn.Completed:Connect(function()
            timerFrame.Visible = false
        end)
    end
end)
