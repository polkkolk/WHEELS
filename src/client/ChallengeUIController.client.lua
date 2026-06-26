-- ChallengeUIController.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinFlyIn = require(Shared:WaitForChild("CoinFlyIn"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Remote Events (created dynamically by server if they don't exist)
local function getRemote(name)
    local r = ReplicatedStorage:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = ReplicatedStorage
    end
    return r
end

local EnterChallengeEvent = getRemote("EnterChallengeEvent")
local ChallengeCompleteEvent = getRemote("ChallengeCompleteEvent")
local ConeHitEvent = getRemote("ConeHitEvent")

-- ─── UI SETUP ───────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChallengeUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = PlayerGui

-- Full-screen dark overlay for Intro
local introBg = Instance.new("Frame")
introBg.Size = UDim2.fromScale(1, 1)
introBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
introBg.BackgroundTransparency = 0.35
introBg.BorderSizePixel = 0
introBg.Visible = false
introBg.Parent = screenGui

-- Intro Card (styled like Team Card)
local introCard = Instance.new("Frame")
introCard.Size = UDim2.new(0, 400, 0, 220)
introCard.AnchorPoint = Vector2.new(0.5, 0.5)
introCard.Position = UDim2.new(0.5, 0, 1.5, 0) -- starts off bottom
introCard.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
introCard.BackgroundTransparency = 0.1
introCard.BorderSizePixel = 0
introCard.Visible = false
introCard.Parent = introBg

local uiCorner = Instance.new("UICorner"); uiCorner.CornerRadius = UDim.new(0, 18); uiCorner.Parent = introCard
local uiStroke = Instance.new("UIStroke"); uiStroke.Color = Color3.fromRGB(220, 180, 40); uiStroke.Thickness = 3; uiStroke.Parent = introCard

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -20, 0, 80)
titleText.Position = UDim2.new(0, 10, 0, 18)
titleText.BackgroundTransparency = 1
titleText.Text = "CHALLENGE"
titleText.TextColor3 = Color3.fromRGB(255, 200, 50)
titleText.Font = Enum.Font.GothamBlack
titleText.TextSize = 54
titleText.TextStrokeTransparency = 0.6
titleText.TextStrokeColor3 = Color3.fromRGB(200, 140, 20)
titleText.Parent = introCard

local introText = Instance.new("TextLabel")
introText.Size = UDim2.new(1, -20, 0, 68)
introText.Position = UDim2.new(0, 10, 0, 102)
introText.BackgroundTransparency = 1
introText.Text = "Hit all the cones as fast as possible!"
introText.TextColor3 = Color3.fromRGB(220, 220, 230)
introText.Font = Enum.Font.GothamBold
introText.TextSize = 22
introText.TextWrapped = true
introText.Parent = introCard

-- Giant Countdown Text (3.. 2.. 1.. GO!)
local countdownText = Instance.new("TextLabel")
countdownText.Size = UDim2.new(0, 300, 0, 300)
countdownText.Position = UDim2.new(0.5, -150, 0.5, -150)
countdownText.BackgroundTransparency = 1
countdownText.Text = ""
countdownText.TextColor3 = Color3.fromRGB(255, 255, 255)
countdownText.Font = Enum.Font.GothamBlack
countdownText.TextScaled = true
countdownText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
countdownText.TextStrokeTransparency = 0
countdownText.Visible = false
countdownText.Parent = screenGui

-- Timer Display (Starts Bottom Left)
local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(0, 200, 0, 72)
timerLbl.Position = UDim2.new(0, 30, 1, -110)
timerLbl.BackgroundTransparency = 1
timerLbl.Text = "00.000"
timerLbl.TextColor3 = Color3.fromRGB(0, 255, 150)
timerLbl.Font = Enum.Font.Code
timerLbl.TextSize = 64
timerLbl.TextXAlignment = Enum.TextXAlignment.Left
timerLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
timerLbl.TextStrokeTransparency = 0
timerLbl.Visible = false
timerLbl.Parent = screenGui

-- Cone Counter Display
local coneCounterLbl = Instance.new("TextLabel")
coneCounterLbl.Size = UDim2.new(0, 200, 0, 50)
coneCounterLbl.Position = UDim2.new(0, 30, 1, -165) 
coneCounterLbl.BackgroundTransparency = 1
coneCounterLbl.Text = "0/30"
coneCounterLbl.TextColor3 = Color3.fromRGB(255, 120, 30)
coneCounterLbl.Font = Enum.Font.GothamBlack
coneCounterLbl.TextSize = 48
coneCounterLbl.TextXAlignment = Enum.TextXAlignment.Left
coneCounterLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
coneCounterLbl.TextStrokeTransparency = 0
coneCounterLbl.Visible = false
coneCounterLbl.Parent = screenGui

-- ─── LOGIC STATE ────────────────────────────────────────────────────────────
local timerActive = false
local startTime = 0
local connection = nil

local function setPlayerFrozen(frozen)
    -- Anchor/Unanchor ALL Wheelchair parts + character's HumanoidRootPart.
    -- CRITICAL: Both sides of the SeatWeld must be anchored together,
    -- otherwise Roblox detects an overconstrained system and breaks the weld.
    local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if chair then
        for _, part in ipairs(chair:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = frozen
                if frozen then
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
    end
    -- Also freeze/unfreeze the character so the SeatWeld isn't overconstrained
    local char = player.Character
    if char then
        local rootPart = char:FindFirstChild("HumanoidRootPart")
        if rootPart then
            rootPart.Anchored = frozen
            if frozen then
                rootPart.AssemblyLinearVelocity = Vector3.zero
                rootPart.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end
end

local function formatTime(s)
    local mins = math.floor(s / 60)
    local secs = math.floor(s % 60)
    local ms = math.floor((s % 1) * 1000)
    if mins > 0 then
        return string.format("%d:%02d.%03d", mins, secs, ms)
    else
        return string.format("%02d.%03d", secs, ms)
    end
end

-- ─── SEQUENCES ──────────────────────────────────────────────────────────────

-- 1. START CHALLENGE
EnterChallengeEvent.OnClientEvent:Connect(function()
    if timerActive then return end
    
    timerLbl.Visible = false
    timerLbl.Position = UDim2.new(0, 30, 1, -90) -- reset pos
    timerLbl.TextSize = 48
    timerLbl.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Freeze Player instantly
    setPlayerFrozen(true)
    
    -- Hide default Roblox UI
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
    
    -- Show Intro Card logic
    introBg.Visible = true
    introCard.Visible = true
    introCard.Position = UDim2.new(0.5, 0, 1.5, 0)
    
    TweenService:Create(introCard, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.5, 0)
    }):Play()
    
    task.wait(3)
    
    local twOut = TweenService:Create(introCard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, 0, -0.6, 0)
    })
    twOut:Play()
    twOut.Completed:Wait()
    introBg.Visible = false
    
    -- Countdown
    countdownText.Visible = true
    for i = 3, 1, -1 do
        countdownText.Text = tostring(i)
        
        -- Pop animation
        countdownText.Size = UDim2.new(0, 100, 0, 100)
        countdownText.Position = UDim2.new(0.5, -50, 0.5, -50)
        local tw = TweenService:Create(countdownText, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 300, 0, 300),
            Position = UDim2.new(0.5, -150, 0.5, -150)
        })
        tw:Play()
        task.wait(1)
    end
    
    -- GO!
    countdownText.Text = "GO!"
    countdownText.TextColor3 = Color3.fromRGB(0, 255, 100)
    countdownText.Size = UDim2.new(0, 400, 0, 400)
    countdownText.Position = UDim2.new(0.5, -200, 0.5, -200)
    
    task.spawn(function()
        task.wait(0.8)
        countdownText.Visible = false
        countdownText.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    
    -- Unfreeze and Start Timer
    setPlayerFrozen(false)
    timerLbl.Visible = true
    coneCounterLbl.Text = "0/30"
    coneCounterLbl.Visible = true
    timerActive = true
    startTime = tick()
    
    if connection then connection:Disconnect() end
    connection = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        timerLbl.Text = formatTime(elapsed)
    end)
end)

-- 1.5 CONE HIT
ConeHitEvent.OnClientEvent:Connect(function(hits, required)
    coneCounterLbl.Text = tostring(hits) .. "/" .. tostring(required)
    
    -- Pop animation on hit
    local tw = TweenService:Create(coneCounterLbl, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextSize = 58
    })
    tw:Play()
    tw.Completed:Connect(function()
        TweenService:Create(coneCounterLbl, TweenInfo.new(0.2), { TextSize = 48 }):Play()
    end)
end)

-- 2. COMPLETE CHALLENGE
ChallengeCompleteEvent.OnClientEvent:Connect(function(finalTime, coinReward, aborted)
    if not timerActive then return end
    timerActive = false
    if connection then connection:Disconnect() end
    connection = nil
    
    if aborted then
        -- Cleanup quietly
        introBg.Visible = false
        timerLbl.Visible = false
        coneCounterLbl.Visible = false
        countdownText.Visible = false
        
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, true)
        end)
        setPlayerFrozen(false)
        return
    end
    
    -- Sync exact final time from server
    timerLbl.Text = formatTime(finalTime)
    
    -- Freeze Player again to see score
    setPlayerFrozen(true)
    
    -- ── DARK OVERLAY ──
    introBg.BackgroundTransparency = 1
    introBg.Visible = true
    TweenService:Create(introBg, TweenInfo.new(0.5), { BackgroundTransparency = 0.4 }):Play()
    
    -- ── "SUCCESS" HEADER ──
    local successLbl = Instance.new("TextLabel")
    successLbl.Size = UDim2.new(0, 600, 0, 80)
    successLbl.Position = UDim2.new(0.5, 0, 0.25, 0)
    successLbl.AnchorPoint = Vector2.new(0.5, 0.5)
    successLbl.BackgroundTransparency = 1
    successLbl.Text = "✦  SUCCESS  ✦"
    successLbl.TextColor3 = Color3.fromRGB(255, 220, 80)
    successLbl.Font = Enum.Font.GothamBlack
    successLbl.TextSize = 0
    successLbl.TextStrokeColor3 = Color3.fromRGB(180, 120, 0)
    successLbl.TextStrokeTransparency = 0
    successLbl.Parent = screenGui
    
    TweenService:Create(successLbl, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        TextSize = 56
    }):Play()
    
    -- ── TIMER TO CENTER ──
    timerLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerLbl.TextXAlignment = Enum.TextXAlignment.Center
    local twCenter = TweenService:Create(timerLbl, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -400, 0.5, -50),
        Size = UDim2.new(0, 800, 0, 120),
        TextSize = 100
    })
    twCenter:Play()
    twCenter.Completed:Wait()
    
    -- ── TIERED MEDAL TEXT ──
    local medalLbl = Instance.new("TextLabel")
    medalLbl.Size = UDim2.new(0, 600, 0, 50)
    medalLbl.Position = UDim2.new(0.5, 0, 0.5, 90) -- MOVED DOWN to avoid overlap with timer
    medalLbl.AnchorPoint = Vector2.new(0.5, 0)
    medalLbl.BackgroundTransparency = 1
    medalLbl.Font = Enum.Font.GothamBlack
    medalLbl.TextSize = 0
    medalLbl.TextStrokeTransparency = 0
    medalLbl.Parent = screenGui
    
    if finalTime <= 30 then
        -- GOLD
        medalLbl.Text = "PERFECT!"
        medalLbl.TextColor3 = Color3.fromRGB(255, 215, 0)
        medalLbl.TextStrokeColor3 = Color3.fromRGB(180, 140, 0)
    elseif finalTime <= 60 then
        -- SILVER
        medalLbl.Text = "Great Job!"
        medalLbl.TextColor3 = Color3.fromRGB(200, 210, 220)
        medalLbl.TextStrokeColor3 = Color3.fromRGB(120, 130, 140)
    else
        -- BRONZE
        medalLbl.Text = "You could do better..."
        medalLbl.TextColor3 = Color3.fromRGB(205, 150, 80)
        medalLbl.TextStrokeColor3 = Color3.fromRGB(140, 90, 30)
    end
    
    TweenService:Create(medalLbl, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        TextSize = 42
    }):Play()
    
    -- ── CONFETTI ──
    local confettiEmitters = {}
    local confettiColors = {
        Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 255, 80),
        Color3.fromRGB(80, 80, 255), Color3.fromRGB(255, 220, 40),
        Color3.fromRGB(255, 120, 220), Color3.fromRGB(80, 220, 255),
    }
    for i = 1, 4 do
        local confettiFrame = Instance.new("Frame")
        confettiFrame.Size = UDim2.new(0, 2, 0, 2)
        confettiFrame.Position = UDim2.new(0.15 + (i - 1) * 0.23, 0, 0, -10)
        confettiFrame.BackgroundTransparency = 1
        confettiFrame.Parent = screenGui
        
        for j = 1, 15 do
            task.spawn(function()
                local piece = Instance.new("Frame")
                piece.Size = UDim2.new(0, math.random(6, 12), 0, math.random(3, 8))
                piece.BackgroundColor3 = confettiColors[math.random(1, #confettiColors)]
                piece.Rotation = math.random(0, 360)
                piece.Position = UDim2.new(0, math.random(-80, 80), 0, 0)
                piece.Parent = confettiFrame
                
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 2)
                corner.Parent = piece
                
                local fallTime = math.random(15, 30) / 10
                local endX = piece.Position.X.Offset + math.random(-60, 60)
                TweenService:Create(piece, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(0, endX, 0, math.random(400, 700)),
                    Rotation = math.random(-720, 720),
                    BackgroundTransparency = 0.6,
                }):Play()
            end)
        end
        table.insert(confettiEmitters, confettiFrame)
    end
    
    -- ── COIN FLY-IN ANIMATION ──
    if coinReward and coinReward > 0 then
        task.spawn(function()
            CoinFlyIn.play(screenGui, coinReward, UDim2.new(0.5, 0, 0.75, 0))
        end)
    end
    
    task.wait(3)
    
    -- ── FADE OUT EVERYTHING ──
    TweenService:Create(successLbl, TweenInfo.new(0.4), { TextSize = 0 }):Play()
    TweenService:Create(medalLbl, TweenInfo.new(0.4), { TextSize = 0 }):Play()
    
    local twOut = TweenService:Create(timerLbl, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        TextSize = 0
    })
    twOut:Play()
    TweenService:Create(introBg, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
    twOut.Completed:Wait()
    
    -- Cleanup
    successLbl:Destroy()
    medalLbl:Destroy()
    for _, f in ipairs(confettiEmitters) do f:Destroy() end
    
    introBg.Visible = false
    timerLbl.Visible = false
    timerLbl.TextColor3 = Color3.fromRGB(0, 255, 150)
    coneCounterLbl.Visible = false
    
    -- Reset timer position
    timerLbl.Position = UDim2.new(0, 30, 1, -110)
    timerLbl.Size = UDim2.new(0, 200, 0, 72)
    timerLbl.TextSize = 64
    timerLbl.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Restore core UI (but NOT Backpack — the gun toolbar shows "press 1" which shouldn't appear)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, true)
    end)
    setPlayerFrozen(false)
end)

-- ── INSTANT CLIENT-SIDE CONE IMPULSE ──
-- This eliminates the network delay by applying the impulse on the client.
-- Because unanchored cones auto-assign network ownership to the closest player,
-- this impulse replicates instantly and feels perfectly responsive.
local function setupClientConeHit(coneModel)
    local primary = coneModel.PrimaryPart
    if not primary then return end
    
    local debounce = false
    local function hookPart(part)
        part.Touched:Connect(function(hit)
            if not timerActive then return end -- Only during active challenge
            if debounce then return end
            
            local char = player.Character
            local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
            if not char then return end
            
            -- Ensure WE hit it (character or wheelchair)
            if not hit:IsDescendantOf(char) and (not chair or not hit:IsDescendantOf(chair)) then return end
            
            debounce = true
            task.delay(0.5, function() debounce = false end)
            
            -- Apply impulse instantly on the client!
            local flingDir = (primary.Position - hit.Position)
            if flingDir.Magnitude < 0.01 then flingDir = Vector3.new(0, 1, 0) end
            flingDir = Vector3.new(flingDir.X, math.abs(flingDir.Y) + 0.3, flingDir.Z).Unit
            
            local chairSpeed = hit.AssemblyLinearVelocity.Magnitude
            if chairSpeed < 5 then chairSpeed = 30 end
            local speedFactor = math.clamp(chairSpeed / 30, 0.3, 2.0)
            local force = speedFactor * 1.5 * primary.AssemblyMass
            primary:ApplyImpulse(flingDir * force)
            
            local spinStrength = speedFactor * 40
            primary:ApplyAngularImpulse(Vector3.new(
                math.random(-100, 100) / 100 * spinStrength,
                math.random(-100, 100) / 100 * spinStrength * 0.5,
                math.random(-100, 100) / 100 * spinStrength
            ) * primary.AssemblyMass)
        end)
    end
    
    for _, p in ipairs(coneModel:GetDescendants()) do
        if p:IsA("BasePart") then hookPart(p) end
    end
end

workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") and obj.Name == "ChallengeTrafficCone" then
        task.wait(0.1) -- give server time to create hitbox
        setupClientConeHit(obj)
    end
end)
for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Model") and obj.Name == "ChallengeTrafficCone" then
        setupClientConeHit(obj)
    end
end
