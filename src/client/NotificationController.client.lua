local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local updatedGui = nil -- Reference to current GUI

-- Wait for Remote
local killEvent = ReplicatedStorage:WaitForChild("KillEvent", 10)
if not killEvent then
    warn("NotificationController: KillEvent missing!")
end

-- Create GUI Elements
local function createNotificationGui()
    if updatedGui then return updatedGui end
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "KillNotificationGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true -- Match GunController
    gui.Parent = player:WaitForChild("PlayerGui")
    
    -- Container for Stacking
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0.3, 0, 0.5, 0) 
    container.Position = UDim2.new(0.5, 140, 0.5, -10) -- Right of Center (Ammo end + gap)
    container.BackgroundTransparency = 1
    container.Parent = gui
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = container
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left -- Left Align Text
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding = UDim.new(0, 2) -- Tighter gap
    
    updatedGui = gui
    return gui
end

local function showKillMessage(victimName, killType)
    if not killType then killType = "Killed" end
    local gui = createNotificationGui()
    local container = gui:FindFirstChild("Container")
    
    -- Create Label
    local label = Instance.new("TextLabel")
    label.Name = "KillMessage"
    label.Size = UDim2.new(1, 0, 0, 16) 
    label.BackgroundTransparency = 1
    
    label.RichText = true -- Enable formatting (Color tags)
    local redHex = "#FF1E00" -- Vivid Red (255, 30, 0)
    local whiteHex = "#FFFFFF"
    label.Text = string.format('<font color="%s">%s</font> <font color="%s">%s</font>', whiteHex, killType, redHex, tostring(victimName))
    
    label.TextColor3 = Color3.new(1, 1, 1) -- Base color (White)
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 60 -- Start HUGE (Impact)
    label.Rotation = math.random(-15, 15) -- Cocked
    label.TextXAlignment = Enum.TextXAlignment.Left -- Align to left
    label.TextScaled = false
    label.Parent = container
    
    -- Animation 1: IMPACT (Slam Down)
    label.TextTransparency = 0
    label.TextStrokeTransparency = 0
    
    local impactInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local impactGoal = {
        TextSize = 14, -- Even smaller (User Request)
        Rotation = 0   -- Straighten out
    }
    TweenService:Create(label, impactInfo, impactGoal):Play()
    
    -- Fade Out & Destroy
    task.delay(2.0, function() -- Keep visible for 2s
        if label and label.Parent then
            local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Linear)
            local goal = {TextTransparency = 1, TextStrokeTransparency = 1}
            local tween = TweenService:Create(label, tweenInfo, goal)
            tween:Play()
            tween.Completed:Connect(function()
                label:Destroy()
            end)
        end
    end)
end

if killEvent then
    killEvent.OnClientEvent:Connect(function(victimName, killType)
        print("NotificationController: RECEIVED KILL EVENT for", victimName, killType)
        showKillMessage(victimName, killType)
    end)
    print("NotificationController: Listening for kills...")
end

-- Death monitor now handled in WheelchairController
-- (Removed local ProximityPromptService management to prevent conflicts)
