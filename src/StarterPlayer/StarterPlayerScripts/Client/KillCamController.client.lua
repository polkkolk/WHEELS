local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local VictimKillCamEvent = ReplicatedStorage:WaitForChild("VictimKillCamEvent")
local KillCamRespawnEvent = ReplicatedStorage:WaitForChild("KillCamRespawnEvent")

-- Create KillCam UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KillCamGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Top center info
local infoFrame = Instance.new("Frame")
infoFrame.Size = UDim2.new(1, 0, 0, 150)
infoFrame.Position = UDim2.new(0, 0, 0, 50)
infoFrame.BackgroundTransparency = 1
infoFrame.Parent = screenGui

local killedByText = Instance.new("TextLabel")
killedByText.Size = UDim2.new(1, 0, 0, 40)
killedByText.Position = UDim2.new(0, 0, 0, 0)
killedByText.BackgroundTransparency = 1
killedByText.Text = "KILLED BY"
killedByText.TextColor3 = Color3.fromRGB(255, 50, 50)
killedByText.Font = Enum.Font.GothamBlack
killedByText.TextSize = 36
killedByText.Parent = infoFrame

local killerNameText = Instance.new("TextLabel")
killerNameText.Size = UDim2.new(1, 0, 0, 50)
killerNameText.Position = UDim2.new(0, 0, 0, 40)
killerNameText.BackgroundTransparency = 1
killerNameText.Text = "Username"
killerNameText.TextColor3 = Color3.fromRGB(255, 255, 255)
killerNameText.Font = Enum.Font.GothamBold
killerNameText.TextSize = 48
killerNameText.Parent = infoFrame

local killerHpText = Instance.new("TextLabel")
killerHpText.Size = UDim2.new(1, 0, 0, 30)
killerHpText.Position = UDim2.new(0, 0, 0, 95)
killerHpText.BackgroundTransparency = 1
killerHpText.Text = "100 HP"
killerHpText.TextColor3 = Color3.fromRGB(100, 255, 100)
killerHpText.Font = Enum.Font.GothamMedium
killerHpText.TextSize = 24
killerHpText.Parent = infoFrame

-- skipPrompt removed
local buttonContainer = Instance.new("Frame")
buttonContainer.Size = UDim2.new(0, 420, 0, 60)
buttonContainer.Position = UDim2.new(0.5, -210, 1, -100)
buttonContainer.BackgroundTransparency = 1
buttonContainer.Visible = false
buttonContainer.Parent = screenGui

local respawnBtn = Instance.new("TextButton")
respawnBtn.Size = UDim2.new(0, 200, 1, 0)
respawnBtn.Position = UDim2.new(0, 0, 0, 0)
respawnBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
respawnBtn.Text = "RESPAWN"
respawnBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
respawnBtn.Font = Enum.Font.GothamBlack
respawnBtn.TextSize = 20
respawnBtn.Parent = buttonContainer
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = respawnBtn end

local lobbyBtn = Instance.new("TextButton")
lobbyBtn.Size = UDim2.new(0, 200, 1, 0)
lobbyBtn.Position = UDim2.new(0, 220, 0, 0)
lobbyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
lobbyBtn.Text = "BACK TO LOBBY"
lobbyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
lobbyBtn.Font = Enum.Font.GothamBlack
lobbyBtn.TextSize = 18
lobbyBtn.Parent = buttonContainer
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = lobbyBtn end

-- State
local isDead = false
local currentKiller = nil

local hiddenGuis = {}

local function hideOtherGuis()
    hiddenGuis = {}
    for _, gui in ipairs(localPlayer.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "KillCamGui" and gui.Enabled then
            hiddenGuis[gui] = true
            gui.Enabled = false
        end
    end
end

local function restoreOtherGuis()
    for gui, _ in pairs(hiddenGuis) do
        if gui and gui.Parent then
            gui.Enabled = true
        end
    end
    hiddenGuis = {}
end

local function resetCamera()
    camera.CameraSubject = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid") or nil
    camera.CameraType = Enum.CameraType.Custom
end

local function startKillCam(killerPlayer)
    if isDead then return end
    isDead = true
    currentKiller = killerPlayer

    hideOtherGuis()
    
    -- Unlock mouse so they can click buttons
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true

    -- Update UI
    if killerPlayer then
        killedByText.Text = "KILLED BY"
        killerNameText.Text = killerPlayer.Name
        
        local hum = killerPlayer.Character and killerPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            killerHpText.Text = math.max(0, math.floor(hum.Health)) .. " HP"
        else
            killerHpText.Text = "Unknown HP"
        end
        
        -- Lock camera to killer
        if hum then
            camera.CameraSubject = hum
        end
    else
        -- Suicide or map fall
        killedByText.Text = "YOU DIED"
        killerNameText.Text = ""
        killerHpText.Text = ""
    end

    buttonContainer.Visible = true
    -- Bounce animation from bottom
    buttonContainer.Position = UDim2.new(0.5, -210, 1, 100)
    TweenService:Create(buttonContainer, TweenInfo.new(0.6, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -210, 1, -100)
    }):Play()

    screenGui.Enabled = true
end

-- Listen for official kills
VictimKillCamEvent.OnClientEvent:Connect(function(killerPlayer)
    startKillCam(killerPlayer)
end)

local function setupCharacter(char)
    isDead = false
    screenGui.Enabled = false
    restoreOtherGuis()
    resetCamera()
    
    local hum = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart", 5)
    
    -- Check for map falls (Void)
    local voidCheck
    voidCheck = RunService.Heartbeat:Connect(function()
        if isDead or not char.Parent then
            if voidCheck then voidCheck:Disconnect() end
            return
        end
        
        -- If we are falling into the void, immediately force respawn
        if root and root.Position.Y < workspace.FallenPartsDestroyHeight + 50 then
            isDead = true
            if voidCheck then voidCheck:Disconnect() end
            KillCamRespawnEvent:FireServer("lobby")
        end
    end)
    
    hum.Died:Connect(function()
        task.wait(0.2)
        -- If VictimKillCamEvent didn't fire, it's a generic death (e.g. reset)
        if not isDead then
            isDead = true
            
            -- Lock camera to current position so it doesn't snap to a random player
            if camera then
                camera.CameraType = Enum.CameraType.Scriptable
            end
            
            task.delay(1, function()
                -- If the killcam UI is now visible, it means VictimKillCamEvent arrived slightly late.
                -- Do NOT send them to the lobby in this case!
                if screenGui.Enabled then return end
                
                KillCamRespawnEvent:FireServer("lobby")
            end)
        end
    end)
end

-- Fallback for suicide / resets / map falls
localPlayer.CharacterAdded:Connect(setupCharacter)

-- If character already exists on script start
if localPlayer.Character then
    setupCharacter(localPlayer.Character)
end

-- Update Loop
RunService.RenderStepped:Connect(function(dt)
    if not isDead then return end

    if currentKiller and currentKiller.Character then
        local hum = currentKiller.Character:FindFirstChild("Humanoid")
        if hum then
            killerHpText.Text = math.max(0, math.floor(hum.Health)) .. " HP"
            camera.CameraSubject = hum
        end
    end
end)

-- Buttons
respawnBtn.MouseButton1Click:Connect(function()
    if not isDead then return end
    KillCamRespawnEvent:FireServer("respawn")
    screenGui.Enabled = false
    restoreOtherGuis()
    resetCamera()
end)

lobbyBtn.MouseButton1Click:Connect(function()
    if not isDead then return end
    KillCamRespawnEvent:FireServer("lobby")
    screenGui.Enabled = false
    restoreOtherGuis()
    resetCamera()
end)
