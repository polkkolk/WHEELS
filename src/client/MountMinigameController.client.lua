local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Wait for the event to exist (created by Server)
local MountMinigameEvent = ReplicatedStorage:WaitForChild("MountMinigameEvent", 10)
if not MountMinigameEvent then
    warn("MountMinigameController: Timed out waiting for MountMinigameEvent.")
    return
end

--------------------------------------------------------------------------------
-- 1. UI GENERATION (Procedural Vector UI)
--------------------------------------------------------------------------------
local guiInfo = {
    screenGui = nil,
    mainFrame = nil,
    ringOuter = nil,
    targetZone = nil,
    indicator = nil,
    progressBarBg = nil,
    progressBarFill = nil,
    instructionText = nil
}

local function createUI()
    -- CLEANUP: Remove old instances if they exist
    local oldGui = player:WaitForChild("PlayerGui"):FindFirstChild("WheelchairMountMinigame")
    if oldGui then oldGui:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "WheelchairMountMinigame"
    sg.ResetOnSpawn = false
    sg.Enabled = false
    sg.Parent = player:WaitForChild("PlayerGui")

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 200, 0, 260)
    mainFrame.Position = UDim2.new(1, -50, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(1, 0.5)
    mainFrame.BackgroundTransparency = 1
    mainFrame.Parent = sg

    -- Instruction Text
    local instruction = Instance.new("TextLabel")
    instruction.Size = UDim2.new(1, 0, 0, 30)
    instruction.Position = UDim2.new(0, 0, 0, 0)
    instruction.BackgroundTransparency = 1
    instruction.Text = "Press 'E'"
    instruction.TextColor3 = Color3.new(1, 1, 1)
    instruction.TextScaled = true
    instruction.Font = Enum.Font.GothamBold
    instruction.TextStrokeTransparency = 0
    instruction.Parent = mainFrame

    -- =========================================================
    -- TIRE VISUAL
    -- =========================================================
    local ringDiameter = 160

    -- 1. OUTER RUBBER TREAD (near-black, full circle)
    local ringOuter = Instance.new("Frame")
    ringOuter.Name = "RingOuter"
    ringOuter.Size = UDim2.new(0, ringDiameter, 0, ringDiameter)
    ringOuter.Position = UDim2.new(0.5, 0, 0, 130)
    ringOuter.AnchorPoint = Vector2.new(0.5, 0.5)
    ringOuter.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
    ringOuter.BorderSizePixel = 0
    ringOuter.Parent = mainFrame
    local outerCorner = Instance.new("UICorner")
    outerCorner.CornerRadius = UDim.new(0.5, 0)
    outerCorner.Parent = ringOuter
    -- Subtle tread ring outline
    local treadStroke = Instance.new("UIStroke")
    treadStroke.Color = Color3.fromRGB(60, 60, 60)
    treadStroke.Thickness = 5
    treadStroke.Parent = ringOuter

    -- 2. METALLIC RIM (silver, inset from tread)
    local rimDiameter = ringDiameter - 28 -- 132px
    local rimFrame = Instance.new("Frame")
    rimFrame.Name = "Rim"
    rimFrame.Size = UDim2.new(0, rimDiameter, 0, rimDiameter)
    rimFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    rimFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    rimFrame.BackgroundColor3 = Color3.fromRGB(158, 163, 173)
    rimFrame.BorderSizePixel = 0
    rimFrame.Parent = ringOuter
    local rimCorner = Instance.new("UICorner")
    rimCorner.CornerRadius = UDim.new(0.5, 0)
    rimCorner.Parent = rimFrame
    local rimStroke = Instance.new("UIStroke")
    rimStroke.Color = Color3.fromRGB(215, 220, 228)
    rimStroke.Thickness = 2
    rimStroke.Parent = rimFrame

    -- 3. HUB (dark center disc)
    local hubDiameter = 50
    local hubFrame = Instance.new("Frame")
    hubFrame.Name = "Hub"
    hubFrame.Size = UDim2.new(0, hubDiameter, 0, hubDiameter)
    hubFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    hubFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    hubFrame.BackgroundColor3 = Color3.fromRGB(45, 50, 60)
    hubFrame.BorderSizePixel = 0
    hubFrame.ZIndex = 3
    hubFrame.Parent = rimFrame
    local hubCorner = Instance.new("UICorner")
    hubCorner.CornerRadius = UDim.new(0.5, 0)
    hubCorner.Parent = hubFrame
    local hubStroke = Instance.new("UIStroke")
    hubStroke.Color = Color3.fromRGB(88, 94, 106)
    hubStroke.Thickness = 2
    hubStroke.Parent = hubFrame

    -- Hub cap (small bright center dot)
    local capFrame = Instance.new("Frame")
    capFrame.Size = UDim2.new(0, 14, 0, 14)
    capFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    capFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    capFrame.BackgroundColor3 = Color3.fromRGB(205, 210, 220)
    capFrame.ZIndex = 4
    capFrame.Parent = hubFrame
    local capCorner = Instance.new("UICorner")
    capCorner.CornerRadius = UDim.new(0.5, 0)
    capCorner.Parent = capFrame

    -- 4. SPOKES (6 bars, hub → rim edge)
    local NUM_SPOKES = 6
    local hubRadius = hubDiameter / 2
    local rimRadius = rimDiameter / 2
    local spokeLength = rimRadius - hubRadius - 4
    local spokeWidth = 9
    for i = 1, NUM_SPOKES do
        local angleDeg = (i - 1) * (360 / NUM_SPOKES)
        local rad = math.rad(angleDeg)
        -- Midpoint between hub edge and rim edge in rimFrame-normalized coords
        local midRimNorm = ((rimRadius + hubRadius) / 2) / rimDiameter
        local cx = 0.5 + math.sin(rad) * midRimNorm
        local cy = 0.5 - math.cos(rad) * midRimNorm
        local spoke = Instance.new("Frame")
        spoke.Name = "Spoke" .. i
        spoke.Size = UDim2.new(0, spokeWidth, 0, spokeLength)
        spoke.Position = UDim2.new(cx, 0, cy, 0)
        spoke.AnchorPoint = Vector2.new(0.5, 0.5)
        spoke.Rotation = angleDeg
        spoke.BackgroundColor3 = Color3.fromRGB(128, 133, 143)
        spoke.BorderSizePixel = 0
        spoke.ZIndex = 2
        spoke.Parent = rimFrame
        local spokeCorner = Instance.new("UICorner")
        spokeCorner.CornerRadius = UDim.new(0.5, 0)
        spokeCorner.Parent = spoke
    end

    -- =========================================================
    -- GAME ELEMENTS (placed on the outer tread ring)
    -- =========================================================

    -- Target Zone (green notch = "land here")
    local targetZone = Instance.new("Frame")
    targetZone.Name = "TargetZone"
    targetZone.Size = UDim2.new(0, 13, 0, 26)
    targetZone.AnchorPoint = Vector2.new(0.5, 0.5)
    targetZone.BackgroundColor3 = Color3.fromRGB(55, 220, 55)
    targetZone.BorderSizePixel = 0
    targetZone.ZIndex = 5
    targetZone.Parent = ringOuter
    local tzCorner = Instance.new("UICorner")
    tzCorner.CornerRadius = UDim.new(0.5, 0)
    tzCorner.Parent = targetZone

    -- Moving Indicator (white bar with yellow stroke)
    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(0, 5, 0, 28)
    indicator.AnchorPoint = Vector2.new(0.5, 0.5)
    indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    indicator.BorderSizePixel = 0
    indicator.ZIndex = 5
    indicator.Parent = ringOuter
    local indCorner = Instance.new("UICorner")
    indCorner.CornerRadius = UDim.new(0.5, 0)
    indCorner.Parent = indicator
    local indStroke = Instance.new("UIStroke")
    indStroke.Color = Color3.fromRGB(255, 235, 80)
    indStroke.Thickness = 2
    indStroke.Parent = indicator

    -- Progress Bar
    local pbBg = Instance.new("Frame")
    pbBg.Name = "ProgressBarBg"
    pbBg.Size = UDim2.new(1, 0, 0, 20)
    pbBg.Position = UDim2.new(0, 0, 1, -20)
    pbBg.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    pbBg.Parent = mainFrame
    local pbBgCorner = Instance.new("UICorner")
    pbBgCorner.CornerRadius = UDim.new(0, 8)
    pbBgCorner.Parent = pbBg
    local pbBgStroke = Instance.new("UIStroke")
    pbBgStroke.Color = Color3.new(0.4, 0.4, 0.4)
    pbBgStroke.Thickness = 2
    pbBgStroke.Parent = pbBg
    local pbFill = Instance.new("Frame")
    pbFill.Name = "ProgressBarFill"
    pbFill.Size = UDim2.new(0, 0, 1, 0)
    pbFill.BackgroundColor3 = Color3.new(0.2, 0.8, 0.2)
    pbFill.Parent = pbBg
    local pbFillCorner = Instance.new("UICorner")
    pbFillCorner.CornerRadius = UDim.new(0, 8)
    pbFillCorner.Parent = pbFill

    -- Struct store
    guiInfo.screenGui = sg
    guiInfo.mainFrame = mainFrame
    guiInfo.ringOuter = ringOuter
    guiInfo.targetZone = targetZone
    guiInfo.indicator = indicator
    guiInfo.progressBarBg = pbBg
    guiInfo.progressBarFill = pbFill
    guiInfo.instructionText = instruction
end

createUI()

--------------------------------------------------------------------------------
-- 2. MINIGAME LOGIC
--------------------------------------------------------------------------------
local isActive = false
local currentSeat = nil
local progress = 0
local targetScore = 3

local currentAngle = 0
local indicatorSpeed = math.pi * 1.5 -- 0.75 revs per second
local targetAngle = 0
local hitWindow = math.pi / 4 -- 45 degrees total (22.5 each side) = ~12.5% of the circle

local renderConnection = nil
local inputConnection = nil

-- Helpers
local function setElementPositionOnRing(element, angle, radius)
    -- Center is 0.5, 0.5
    -- Angle 0 is top. We adjust standard trig (where 0 is right) by swapping X/Y or adding offset.
    -- X = sin(angle), Y = -cos(angle) makes 0 top, spinning clockwise.
    
    local x = 0.5 + (math.sin(angle) * radius)
    local y = 0.5 - (math.cos(angle) * radius)
    element.Position = UDim2.new(x, 0, y, 0)
    
    -- Rotate the UI element so the bar points toward the center like a clock tick
    element.Rotation = math.deg(angle)
end

local function updateProgressBar()
    local pct = math.clamp(progress / targetScore, 0, 1)
    local tween = TweenService:Create(guiInfo.progressBarFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(pct, 0, 1, 0)
    })
    tween:Play()
end

local function randomizeTarget()
    -- Ensure it's not too close to the current indicator angle so they don't get a free hit
    local newAngle
    repeat
        newAngle = math.random() * math.pi * 2
    until math.abs(newAngle - currentAngle) > (math.pi / 2)
    
    targetAngle = newAngle
    -- Ring radius is 0.5. We sit inside the stroke.
    setElementPositionOnRing(guiInfo.targetZone, targetAngle, 0.45)
end

local function endGame(success)
    if not isActive then return end -- Already ended
    
    isActive = false
    guiInfo.screenGui.Enabled = false
    
    -- Explicitly re-enable the prompt on the seat we were using
    if currentSeat then
        local p = currentSeat:FindFirstChildWhichIsA("ProximityPrompt")
        if p then p.Enabled = true end
    end
    
    -- Re-enable Service
    game:GetService("ProximityPromptService").Enabled = true
    
    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
    if inputConnection then
        inputConnection:Disconnect()
        inputConnection = nil
    end
    
    print("Minigame End | Success:", success, "| Seat:", currentSeat and currentSeat.Name or "NONE")
    
    if success and currentSeat then
        print("MountMinigameController: SUCCESS - Sending FireServer to seat player")
        MountMinigameEvent:FireServer(currentSeat, true)
    elseif not success and currentSeat then
        MountMinigameEvent:FireServer(currentSeat, false)
    end
    
    currentSeat = nil
end

local lastStartTime = 0 -- To prevent double-E triggers

local function handleInput(input, gameProcessed)
    if not isActive then return end
    if tick() - lastStartTime < 0.2 then return end -- Cooldown: Ignore the 'E' that opened the UI
    
    -- We only care about E key since it's the mount key
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.E then
        
        -- Calculate angular difference
        -- Normalize angles to 0..2PI
        local indNorm = currentAngle % (math.pi * 2)
        local tgtNorm = targetAngle % (math.pi * 2)
        
        local diff = math.abs(indNorm - tgtNorm)
        if diff > math.pi then
            diff = (math.pi * 2) - diff -- Shortest wrap-around distance
        end
        
        if diff <= (hitWindow / 2) then
            -- HIT (Green Zone)
            progress = progress + 1
            
            -- Feedback Flash
            local originalColor = guiInfo.targetZone.BackgroundColor3
            guiInfo.targetZone.BackgroundColor3 = Color3.new(1, 1, 1)
            task.delay(0.1, function()
                if guiInfo.targetZone then guiInfo.targetZone.BackgroundColor3 = originalColor end
            end)
            
            updateProgressBar()
            
            if progress >= targetScore then
                endGame(true)
            else
                randomizeTarget()
                -- Slightly increase speed for difficulty?
                indicatorSpeed = indicatorSpeed * 1.15
            end
        else
            -- MISS (Gray Zone)
            progress = 0
            
            -- Feedback Flash Error
            local originalColor = guiInfo.targetZone.BackgroundColor3
            guiInfo.targetZone.BackgroundColor3 = Color3.new(0.3, 0.3, 0.3)
            task.delay(0.1, function()
                if guiInfo.targetZone then guiInfo.targetZone.BackgroundColor3 = originalColor end
            end)
            
            randomizeTarget() -- SHUFFLE: Move the bar on failure (User Request)
            updateProgressBar()
            indicatorSpeed = math.pi * 1.5 -- Reset speed
        end
    end
end

--------------------------------------------------------------------------------
-- 3. NETWORK START
--------------------------------------------------------------------------------
MountMinigameEvent.OnClientEvent:Connect(function(seat)
    -- CHARACTER STATE CHECK: No mounting if Dead, Ragdolled, or Already Seated
    local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local isRagdolled = (humanoid:GetState() == Enum.HumanoidStateType.Physics or humanoid.PlatformStand)
    local isDead = (humanoid.Health <= 0)
    local isSeated = (humanoid.SeatPart ~= nil)
    
    if isRagdolled or isDead or isSeated then 
        warn("MountMinigameController: Blocked start (Char state invalid)")
        return 
    end
    
    currentSeat = seat
    isActive = true
    progress = 0
    currentAngle = 0
    indicatorSpeed = math.pi * 1.5 -- Reset base speed
    lastStartTime = tick() -- Track start time for input lockout
    
    updateProgressBar()
    randomizeTarget()
    
    guiInfo.screenGui.Enabled = true
    
    -- HARD LOCKOUT: Find the prompt on this seat and disable it directly
    -- This prevents the server property-changed signal from re-enabling it
    local p = seat:FindFirstChildWhichIsA("ProximityPrompt")
    if p then p.Enabled = false end
    
    game:GetService("ProximityPromptService").Enabled = false -- DISABLE PROMPTS GLOBALLY DURING GAME
    
    print("Minigame Started on Seat:", seat.Name)
    
    -- Cleanup old connections just in case
    if renderConnection then renderConnection:Disconnect() end
    if inputConnection then inputConnection:Disconnect() end
    
    -- Bind Input
    inputConnection = UserInputService.InputBegan:Connect(handleInput)
    
    -- Start Loop
    renderConnection = RunService.RenderStepped:Connect(function(dt)
        if not isActive then return end
        
        -- Move Indicator
        currentAngle = currentAngle + (indicatorSpeed * dt)
        setElementPositionOnRing(guiInfo.indicator, currentAngle, 0.45)
        
        -- Safety check: Did player walk away? Or did they die/ragdoll mid-game?
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local hum = player.Character:FindFirstChild("Humanoid")
            local dist = (player.Character.HumanoidRootPart.Position - seat.Position).Magnitude
            
            local isRagdolled = hum and (hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand)
            local isDead = hum and (hum.Health <= 0)
            
            if dist > 12.5 or isRagdolled or isDead then
                print("Minigame Cancelled: State invalid (Dist/Ragdoll/Health)")
                endGame(false) -- Cancel
            end
        end
    end)
end)
