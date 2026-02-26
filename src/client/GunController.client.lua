local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- Added for FOV

print("🔴 GUN CONTROLLER v5952 (SYNC VERIFIED - PATH FIXED) LOADED 🔴")

-- Fallback for GunConfig: Check both shared/ and root
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local GunConfig
if Shared and Shared:FindFirstChild("GunConfig") then
    GunConfig = require(Shared.GunConfig)
else
    -- Fallback to root if Rojo setup differs
    GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
end

local GunFireEvent = ReplicatedStorage:WaitForChild("GunFireEvent") -- REPLICATEDSTORAGE, NOT SERVICE
local GunReloadEvent = ReplicatedStorage:WaitForChild("GunReloadEvent")
local GunHitEvent = ReplicatedStorage:WaitForChild("GunHitEvent") -- Server -> Client: damage feedback
local GameEvent   = ReplicatedStorage:WaitForChild("GameEvent", 10)
local TOOL_NAME = "AssaultRifle"


local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

-- Team data (populated from round_start) — declared after player so Name is accessible
local myTeam   = nil
local teamData = {}  -- [name] = "Red"|"Blue"
if GameEvent then
	GameEvent.OnClientEvent:Connect(function(eventName, data)
		if eventName == "round_start" and data and data.teams then
			teamData = data.teams
			myTeam   = data.teams[player.Name]
		elseif eventName == "round_end" or eventName == "intermission" then
			teamData = {}
			myTeam   = nil
		end
	end)
end

local function isTeammate(modelName)
	if not myTeam then return false end
	return teamData[modelName] == myTeam
end

-- === SPRING MODULE (Internal) ===
local Spring = {}
Spring.__index = Spring
function Spring.new(mass, force, damping, speed)
    local self = setmetatable({}, Spring)
    self.Target = Vector3.new()
    self.Position = Vector3.new()
    self.Velocity = Vector3.new()
    self.Mass = mass or 5; self.Force = force or 50; self.Damping = damping or 4; self.Speed = speed or 4
    return self
end
function Spring:Shove(force) self.Velocity = self.Velocity + force end
function Spring:Update(dt)
    local scaledDt = math.min(dt, 0.1) * self.Speed
    local acceleration = (self.Target - self.Position) * self.Force / self.Mass
    acceleration = acceleration - self.Velocity * self.Damping
    self.Velocity = self.Velocity + acceleration * scaledDt
    self.Position = self.Position + self.Velocity * scaledDt
    return self.Position
end

-- === STATE ===
local equipped = false
local tool = nil
local muzzleAtt = nil -- AAA Muzzle Flash
local fireSound = nil -- AAA Gunshot Audio
local ammo = GunConfig.AssaultRifle.MagSize
local reloading = false
local lastFire = 0
local triggerDown = false

local currentSpread = GunConfig.AssaultRifle.BaseSpread
local camSpring = Spring.new(5, 50, 4, 4) -- Smooth camera
local recoilSpring = Spring.new(5, 40, 5, 4) -- Snappy recoil

local camYaw = 0
local camPitch = 0
local currentZoom = GunConfig.AssaultRifle.OTSOffset.Z -- Start with default config zoom
local targetOffset = GunConfig.AssaultRifle.OTSOffset -- Base offset vector
local isAiming = false -- ADS STATE


-- Forward Declarations
local Reload 

-- UI
local gui, crosshairTop, crosshairBottom, crosshairLeft, crosshairRight, centerDot, ammoLabel
local reloadBarBg, reloadBarFill -- Reload progress bar

-- === HELPER FUNCTIONS ===

-- Floating Damage Numbers (RIVALS-style)
local function showDamageNumber(worldPos, damage, isHeadshot)
    -- Scale billboard size based on distance from camera
    local camPos = camera.CFrame.Position
    local dist = (worldPos - camPos).Magnitude
    local scaleMult = math.clamp(dist / 20, 1, 5) -- Scales up at distance (1x at 20 studs, 5x at 100+)
    
    -- Create a temporary part at the hit position
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Transparency = 1
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Position = worldPos + Vector3.new((math.random() - 0.5) * 1.5, 1, (math.random() - 0.5) * 1.5)
    part.Parent = workspace
    
    local baseSize = isHeadshot and 2.5 or 2
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DmgNumber"
    billboard.Size = UDim2.fromScale(baseSize * scaleMult, (baseSize * 0.6) * scaleMult)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Parent = part
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = tostring(damage)
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    
    if isHeadshot then
        label.TextColor3 = Color3.fromRGB(255, 50, 50) -- Red for headshot
    else
        label.TextColor3 = Color3.new(1, 1, 1) -- White for body
    end
    label.Parent = billboard
    
    -- Animate: float up + fade out
    local startY = part.Position.Y
    local lifetime = 0.8
    local elapsed = 0
    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
        elapsed = elapsed + dt
        local alpha = elapsed / lifetime
        
        -- Float upward
        part.Position = Vector3.new(part.Position.X, startY + alpha * 3, part.Position.Z)
        
        -- Fade out in last 40%
        if alpha > 0.6 then
            local fadeAlpha = (alpha - 0.6) / 0.4
            label.TextTransparency = fadeAlpha
            label.TextStrokeTransparency = 0.3 + 0.7 * fadeAlpha
        end
        
        if alpha >= 1 then
            conn:Disconnect()
            part:Destroy()
        end
    end)
end

-- Listen for hit feedback from server
GunHitEvent.OnClientEvent:Connect(function(hitPos, damage, isHeadshot)
    showDamageNumber(hitPos, damage, isHeadshot)
end)
local function createUI()
    if gui then gui:Destroy() end
    gui = Instance.new("ScreenGui")
    gui.Name = "AAAGunUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true -- FIX 3: Crosshair Alignment
    gui.Parent = player.PlayerGui
    
    local crosshairFolder = Instance.new("Folder")
    crosshairFolder.Name = "Crosshair"
    crosshairFolder.Parent = gui
    
    local function makeLine(name, size)
        local f = Instance.new("Frame")
        f.Name = name
        f.Size = size
        f.AnchorPoint = Vector2.new(0.5, 0.5) -- FIX: Center Pivot
        f.BackgroundColor3 = Color3.new(1, 1, 1)
        f.BorderSizePixel = 0
        f.Parent = crosshairFolder
        return f
    end
    
    -- Reduced line length (8 -> 6)
    crosshairTop = makeLine("Top", UDim2.new(0, 2, 0, 6))
    crosshairBottom = makeLine("Bottom", UDim2.new(0, 2, 0, 6))
    crosshairLeft = makeLine("Left", UDim2.new(0, 6, 0, 2))
    crosshairRight = makeLine("Right", UDim2.new(0, 6, 0, 2))
    
    centerDot = Instance.new("Frame")
    centerDot.Name = "CenterDot"
    centerDot.Size = UDim2.new(0, 2, 0, 2) -- Tiny dot
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.Position = UDim2.new(0.5, 0, 0.5, 0) -- Perfectly centered
    centerDot.BackgroundColor3 = Color3.new(1, 1, 1)
    centerDot.BorderSizePixel = 0
    centerDot.Parent = gui
    
    -- Ammo Label (Right of Crosshair)
    ammoLabel = Instance.new("TextLabel")
    ammoLabel.BackgroundTransparency = 1
    ammoLabel.Position = UDim2.new(0.5, 30, 0.5, 0)
    ammoLabel.Size = UDim2.new(0, 100, 0, 20)
    ammoLabel.Font = Enum.Font.GothamBold
    ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
    ammoLabel.TextColor3 = Color3.new(1,1,1)
    ammoLabel.TextStrokeTransparency = 0.5
    ammoLabel.TextSize = 18
    ammoLabel.Parent = gui
    
    -- Reload Progress Bar (Left of crosshair)
    reloadBarBg = Instance.new("Frame")
    reloadBarBg.Name = "ReloadBarBg"
    reloadBarBg.AnchorPoint = Vector2.new(1, 0.5)
    reloadBarBg.Position = UDim2.new(0.5, -22, 0.5, 0) -- Left of crosshair
    reloadBarBg.Size = UDim2.new(0, 4, 0, 40)
    reloadBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    reloadBarBg.BackgroundTransparency = 0.3
    reloadBarBg.BorderSizePixel = 0
    reloadBarBg.Visible = false
    reloadBarBg.Parent = gui
    
    -- Thin white outline
    local barStroke = Instance.new("UIStroke")
    barStroke.Color = Color3.fromRGB(180, 180, 180)
    barStroke.Thickness = 1
    barStroke.Transparency = 0.5
    barStroke.Parent = reloadBarBg
    
    -- Rounded corners
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 2)
    barCorner.Parent = reloadBarBg
    
    reloadBarFill = Instance.new("Frame")
    reloadBarFill.Name = "ReloadBarFill"
    reloadBarFill.AnchorPoint = Vector2.new(0, 1) -- Anchor bottom-left (fills upward)
    reloadBarFill.Position = UDim2.new(0, 0, 1, 0) -- Bottom of bg
    reloadBarFill.Size = UDim2.new(1, 0, 0, 0) -- Start empty (0 height)
    reloadBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    reloadBarFill.BorderSizePixel = 0
    reloadBarFill.Parent = reloadBarBg
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = reloadBarFill
end

local function updateUI()
    if not gui then return end
    ammoLabel.Text = tostring(ammo) .. " / " .. tostring(GunConfig.AssaultRifle.MagSize)
    if ammo < 10 then ammoLabel.TextColor3 = Color3.fromRGB(255, 50, 50) else ammoLabel.TextColor3 = Color3.new(1,1,1) end
    
    -- Expand Crosshair based on Spread + ADS State
    -- Reduced Scale: ADS = 8x, Hipfire = 16x (Tight)
    local scaleFactor = isAiming and 8 or 16 
    local range = currentSpread * scaleFactor
    
    -- Using AnchorPoint(0.5, 0.5), we just offset by range
    crosshairTop.Position = UDim2.new(0.5, 0, 0.5, -range - 6) -- Shifted Up
    crosshairBottom.Position = UDim2.new(0.5, 0, 0.5, range + 6)
    crosshairLeft.Position = UDim2.new(0.5, -range - 6, 0.5, 0) -- Shifted Left
    crosshairRight.Position = UDim2.new(0.5, range + 6, 0.5, 0)
    
    -- TINT RED IF AIM ASSIST ACTIVE
    if currentAssistTarget then
        centerDot.BackgroundColor3 = Color3.new(1, 0, 0) -- RED for lock
    else
        centerDot.BackgroundColor3 = Color3.new(1, 1, 1) -- WHITE default
    end
end

-- === VFX & SFX (AAA Standards) ===
local function playMuzzleFlash()
    if not muzzleAtt then return end
    
    -- Flash particles (burst)
    local flashEmitter = muzzleAtt:FindFirstChild("FlashEmitter")
    if flashEmitter then
        flashEmitter:Emit(math.random(3, 5))
    end
    
    -- Smoke wisps (burst)
    local smokeEmitter = muzzleAtt:FindFirstChild("SmokeEmitter")
    if smokeEmitter then
        smokeEmitter:Emit(math.random(2, 3))
    end
    
    -- Point light flash
    local light = muzzleAtt:FindFirstChild("FlashLight")
    if light then
        light.Brightness = math.random(6, 10)
        task.delay(0.04, function()
            if light then light.Brightness = 0 end
        end)
    end
end

local function playGunshot()
    -- Fully client-side sound (no server dependency)
    -- Creates a fresh Sound each shot for anti-stacking
    local handle = tool and tool:FindFirstChild("Handle")
    if not handle then return end
    
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://6862108495" -- Rifle gunshot
    s.Volume = 0.2
    s.PlaybackSpeed = 1.0 + (math.random() - 0.5) * 0.1 -- Slight pitch variation
    s.RollOffMaxDistance = 140
    s.RollOffMinDistance = 15
    s.EmitterSize = 10
    s.Parent = handle
    s:Play()
    s.Ended:Once(function() s:Destroy() end)
end

local function Fire()
    -- FIX: RESTRICT GUN USAGE (User Request)
    -- Must be ALIVE and NOT RAGDOLLED
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand then
        return 
    end

    -- Check ammo FIRST
    if ammo <= 0 then
        Reload() 
        return 
    end
    if reloading then return end
    
    local cfg = GunConfig.AssaultRifle
    
    local now = tick()
    if now - lastFire < cfg.FireRate then return end
    lastFire = now
    
    ammo = ammo - 1
    
    -- 0. CLIENT VFX/SFX (Immediate Feedback)
    playMuzzleFlash()
    playGunshot()
    
    -- 1. HEAT (Spread)
    currentSpread = math.min(currentSpread + cfg.SpreadPerShot, cfg.MaxSpread)
    
    -- 2. RECOIL (Camera Kick)
    local rx = (math.random() - 0.5) * cfg.RecoilHorizontal
    local ry = cfg.RecoilVertical
    recoilSpring:Shove(Vector3.new(ry, rx, 0) * 0.5)
    
    -- 3. RAYCAST (With Spread)
    local camCF = camera.CFrame
    
    local spreadRad = math.rad(currentSpread)
    local angle = math.random() * math.pi * 2
    local radius = math.sqrt(math.random()) * spreadRad
    local spreadX = math.cos(angle) * radius
    local spreadY = math.sin(angle) * radius
    
    local spreadDir = (camCF * CFrame.Angles(spreadX, spreadY, 0)).LookVector
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local result = workspace:Raycast(camCF.Position, spreadDir * cfg.MaxDistance, params)
    
    -- 4. NETWORK
    GunFireEvent:FireServer(camCF.Position, spreadDir, result and result.Instance, result and result.Position)
    
    -- 5. HIT MARKER SOUND (ding for body, DING for headshot)
    if result and result.Instance then
        local hitPart = result.Instance
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        if hitModel and hitModel:FindFirstChildOfClass("Humanoid") then
            -- Suppress hitsound for friendly fire
            if isTeammate(hitModel.Name) then
                -- no sound for teammates
            else
                local isHead = (hitPart.Name == "Head")
                local hitSound = Instance.new("Sound")
                hitSound.Parent = camera
                if isHead then
                    local headshotSounds = {"rbxassetid://1543848460", "rbxassetid://1543848180", "rbxassetid://1543848682", "rbxassetid://1543848901", "rbxassetid://1543849901"}
                    hitSound.SoundId = headshotSounds[math.random(1, #headshotSounds)]
                    hitSound.Volume = 3.0
                    hitSound.PlaybackSpeed = 1.0
                else
                    local bodySounds = {"rbxassetid://1657151888", "rbxassetid://1657152147"}
                    hitSound.SoundId = bodySounds[math.random(1, #bodySounds)]
                    hitSound.Volume = 4.0
                    hitSound.PlaybackSpeed = 1.0
                end
                hitSound:Play()
                hitSound.Ended:Once(function() hitSound:Destroy() end)
            end
        end
    end
    
    updateUI()
end

Reload = function()
    -- FIX: RESTRICT RELOADING (User Request)
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand then return end

    if reloading or ammo == GunConfig.AssaultRifle.MagSize then return end
    reloading = true
    ammoLabel.Text = "RLD"
    GunReloadEvent:FireServer()
    
    -- Play reload sound
    local handle = tool and tool:FindFirstChild("Handle")
    if handle then
        local rs = Instance.new("Sound")
        rs.SoundId = "rbxassetid://6404425152" -- Magazine reload
        rs.Volume = 0.7
        rs.Parent = handle
        rs:Play()
        rs.Ended:Once(function() rs:Destroy() end)
    end
    
    local reloadTime = GunConfig.AssaultRifle.ReloadTime
    
    -- Show reload bar (empty)
    if reloadBarBg and reloadBarFill then
        reloadBarBg.Visible = true
        reloadBarBg.BackgroundTransparency = 0.3
        reloadBarFill.Size = UDim2.new(1, 0, 0, 0) -- Empty
        reloadBarFill.BackgroundTransparency = 0
        
        -- Animate fill over reload duration
        local startTime = tick()
        local fillConn
        fillConn = RunService.RenderStepped:Connect(function()
            local elapsed = tick() - startTime
            local progress = math.clamp(elapsed / reloadTime, 0, 1)
            reloadBarFill.Size = UDim2.new(1, 0, progress, 0)
            
            -- Color shift: white → green as it fills
            local r = 1 - progress * 0.6
            local g = 1
            local b = 1 - progress * 0.6
            reloadBarFill.BackgroundColor3 = Color3.new(r, g, b)
            
            if progress >= 1 then
                fillConn:Disconnect()
            end
        end)
    end
    
    task.wait(reloadTime)
    ammo = GunConfig.AssaultRifle.MagSize
    reloading = false
    updateUI()
    
    -- Fade out the reload bar
    if reloadBarBg and reloadBarFill then
        task.spawn(function()
            for i = 0, 1, 0.05 do
                if not reloadBarBg then break end
                reloadBarBg.BackgroundTransparency = 0.3 + (0.7 * i)
                reloadBarFill.BackgroundTransparency = i
                task.wait(0.015)
            end
            if reloadBarBg then
                reloadBarBg.Visible = false
            end
        end)
    end
end

-- === MAIN LOOPS ===

-- === MAIN LOOPS ===

-- AIM ASSIST CONFIG
local ASSIST_CONE_ANGLE = 10 -- Degrees (INCREASED!)
local ASSIST_MAX_DIST = 150 -- Studs (INCREASED!)
local ASSIST_FRICTION = 0.5 -- Multiplier (STRONGER!)
local ASSIST_TRACKING_STRENGTH = 0.1 -- Multiplier (STRONGER!)
local ASSIST_PREDICTION_TIME = 0.1 -- Seconds

-- Aim Assist State
local currentAssistTarget = nil

-- Helper: Get Best Target
local function getBestAssistTarget()
    -- Only scan if equipped
    -- if not equipped or not player.Character then return nil end
    -- TEMPORARY DEBUG: Allow running if equip state is sketchy?
    if not player.Character then return nil end
    
    local camCF = camera.CFrame
    local camPos = camCF.Position
    local lookDir = camCF.LookVector
    
    local bestTarget = nil
    local bestDot = math.cos(math.rad(ASSIST_CONE_ANGLE)) -- Initial threshold
    
    local candidates = {}
    
    -- 1. Scan Players
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then table.insert(candidates, p.Character) end
    end
    
    -- 2. Scan Workspace for Dummy/NPCs (Top-level Models)
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child ~= player.Character then
            local hum = child:FindFirstChild("Humanoid")
            local root = child:FindFirstChild("HumanoidRootPart")
            if hum and root then
                -- Check if it's already in players list (avoid duplicate)
                local isPlayer = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == child then isPlayer = true; break end
                end
                
                if not isPlayer then 
                    table.insert(candidates, child) 
                end
            end
        end
    end
    
    if #candidates == 0 then return nil end
    
    -- Exclude Self + Wheelchair
    local filterList = {player.Character}
    local myChair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if myChair then table.insert(filterList, myChair) end
    
    -- AIM ASSIST SCAN
    for _, char in ipairs(candidates) do
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
             local toTarget = (root.Position - camPos)
            local dist = toTarget.Magnitude
            
            if dist <= ASSIST_MAX_DIST then
                local dir = toTarget.Unit
                local dot = lookDir:Dot(dir)
                
                if dot > bestDot then
                    -- Check LOS (filter out target's wheelchair too)
                    local params = RaycastParams.new()
                    local losFilter = {unpack(filterList)}
                    -- Also exclude the target's wheelchair if it exists
                    local targetChair = workspace:FindFirstChild(char.Name .. "_Wheelchair")
                    if targetChair then table.insert(losFilter, targetChair) end
                    params.FilterDescendantsInstances = losFilter
                    local hit = workspace:Raycast(camPos, toTarget, params)
                    
                    if hit then
                        if hit.Instance:IsDescendantOf(char) then
                            bestTarget = root
                            bestDot = dot
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end
-- ... (Main Loops) ...


-- 1. CAMERA LOOP (BindToRenderStep)
local function updateCamera(dt)
    if not equipped or not player.Character then return end
    
    -- FIX 2: FORCE HIDE MOUSE EVERY FRAME
    UserInputService.MouseIconEnabled = false
    
    -- A. Mouse Input + AIM ASSIST LAYER 1 (FRICTION)
    local delta = UserInputService:GetMouseDelta()
    
    -- Scan for target
    currentAssistTarget = getBestAssistTarget()
    
    local frictionMult = 1.0
    local trackingStrength = 0.0
    
    if currentAssistTarget then
        -- Check if crosshair is DIRECTLY on the target character
        -- If so, disable assist so player can freely aim at head/body
        local onTarget = false
        local assistChar = currentAssistTarget.Parent
        if assistChar then
            local centerRay = workspace:Raycast(
                camera.CFrame.Position,
                camera.CFrame.LookVector * ASSIST_MAX_DIST,
                RaycastParams.new()
            )
            if centerRay and centerRay.Instance:IsDescendantOf(assistChar) then
                onTarget = true
            end
        end
        
        if not onTarget then
            -- Near target but NOT on it: assist helps acquire
            if isAiming then
                frictionMult = 0.6  -- ADS: 40% slower
                trackingStrength = 0.05 -- Moderate Tracking
            else
                frictionMult = 0.75 -- Hipfire: Increased from 0.85 (Stronger)
                trackingStrength = 0.04 -- Weak tracking
            end
        end
        -- If onTarget: frictionMult stays 1.0, trackingStrength stays 0.0
        -- Player has full control to aim at head/body
    end
    
    -- Apply Friction 
    camYaw = camYaw - (delta.X * 0.005 * frictionMult)
    camPitch = math.clamp(camPitch - (delta.Y * 0.005 * frictionMult), -1.4, 1.4)
    
    -- AIM ASSIST LAYER 2 (VELOCITY TRACKING)
    local myRoot = player.Character.PrimaryPart
    if currentAssistTarget and myRoot and trackingStrength > 0 and (delta.Magnitude > 0 or isFiring or myRoot.AssemblyLinearVelocity.Magnitude > 1) then
        local driveByMultiplier = 1.0
        if delta.Magnitude == 0 and not isFiring then
            driveByMultiplier = 0.6
        end
        
        local targetVel = currentAssistTarget.AssemblyLinearVelocity
        local myVel = myRoot.AssemblyLinearVelocity
        local relVel = targetVel - myVel
        
        local predictedPos = currentAssistTarget.Position + (relVel * ASSIST_PREDICTION_TIME)
        local camPos = camera.CFrame.Position
        local toPred = (predictedPos - camPos).Unit
        
        local idealYaw = math.atan2(-toPred.X, -toPred.Z)
        local idealPitch = math.asin(toPred.Y)
        
        local yawDiff = (idealYaw - camYaw + math.pi) % (2 * math.pi) - math.pi
        local pitchDiff = (idealPitch - camPitch)
        
        camYaw = camYaw + (yawDiff * trackingStrength * driveByMultiplier * dt * 60)
        camPitch = camPitch + (pitchDiff * trackingStrength * driveByMultiplier * dt * 60)
    end
    
    recoilSpring:Update(dt)
    local rVal = recoilSpring.Position
    local rot = CFrame.fromOrientation(camPitch + math.rad(rVal.X), camYaw + math.rad(rVal.Y), 0)
    
    -- C. Smooth Offset (Fixed Zoom + ADS)
    local targetOff = GunConfig.AssaultRifle.OTSOffset
    if isAiming then
        targetOff = Vector3.new(2.0, 2.0, 5) -- ADS: Closer, Tighter
    end
    
    camSpring.Target = targetOff
    local off = camSpring:Update(dt)
    
    -- D. Final Position (Base -> Rotate -> Offset)
    local root = player.Character.PrimaryPart
    if root then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        
        -- Base pos: Root Position + Height (Stable)
        local basePos = root.Position + Vector3.new(0, 2.5, 0)
        
        -- Raycast
        local desiredPos = (CFrame.new(basePos) * rot * CFrame.new(off)).Position
        local dir = desiredPos - basePos
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {player.Character}
        local wallHit = workspace:Raycast(basePos, dir, params)
        if wallHit then
            desiredPos = wallHit.Position + (wallHit.Normal * 0.5)
        end
        
        camera.CFrame = CFrame.new(desiredPos, basePos + (rot.LookVector * 100))
    end
end

-- UNEQUIP TRANSITION LOOP
local transitionAlpha = 0
local transitionStartCF = CFrame.new()
local transitionActive = false
local stopTransition = false -- SIM 49.6: User Request (Freeze transition)

-- RAGDOLL SAFEGUARD (Gun Only - Collision fix is server-side in WheelchairService)
local function onStateChanged(old, new)
    -- Force Unequip on Crash
    if new == Enum.HumanoidStateType.PlatformStanding or new == Enum.HumanoidStateType.Physics then
        if equipped and tool and tool.Parent == player.Character then
            tool.Parent = player.Backpack
        end
    end
end

-- CAMERA TRANSITION LOGIC (The Offset Converge Method)
-- Instead of guessing where the camera goes, we offset it to where it IS, 
-- hand control to Roblox, and tween the offset to zero.

-- CAMERA TRANSITION CONSTANTS (User Calibrated)
local TRANSITION_HEIGHT = -1.55
local TRANSITION_PITCH = -20 -- Degrees
local TRANSITION_X_OFFSET = 0.2
local TRANSITION_ZOOM = 12.5

-- CAMERA TRANSITION LOGIC (Manual Smooth Interpolation)
local function transitionCamera(dt)
    if not transitionActive then return end
    
    -- Speed: Normal Smooth Blend (~0.4s)
    transitionAlpha = math.min(transitionAlpha + (dt * 2.5), 1) 
    
    local root = player.Character.PrimaryPart
    local head = player.Character:FindFirstChild("Head")
    if not head then return end
    
    local basePos = head.Position -- Use Head as Focus
    
    -- Target Offset (Head Space): Center + Height + X
    local defaultOffset = Vector3.new(TRANSITION_X_OFFSET, TRANSITION_HEIGHT, TRANSITION_ZOOM) 
    
    local currentOff = GunConfig.AssaultRifle.OTSOffset:Lerp(defaultOffset, transitionAlpha)
    
    -- ROTATION INTERPOLATION
    local _, rootYaw, _ = root.CFrame:ToOrientation()
    
    -- Ensure yaw matches Gun Yaw (Maintain Direction)
    local diff = (rootYaw - camYaw + math.pi) % (2 * math.pi) - math.pi
    local blendedYaw = camYaw + (diff * transitionAlpha) 
    
    -- Pitch Blend: Gun Pitch -> Target Pitch (Looking Down)
    local targetPitchRad = math.rad(TRANSITION_PITCH)
    local blendedPitch = camPitch * (1-transitionAlpha) + (targetPitchRad * transitionAlpha)
    
    local rot = CFrame.fromOrientation(blendedPitch, blendedYaw, 0)
    
    -- Calculate Position
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    
    -- Apply Offset logic robustly:
    -- Apply Y offset to basePos (Pivot Shift)
    local pivot = basePos + Vector3.new(0, currentOff.Y, 0)
    
    -- Apply X/Z offset relative to rotation
    local relativeOffset = CFrame.new(currentOff.X, 0, currentOff.Z)
    
    local desiredPos = (CFrame.new(pivot) * rot * relativeOffset).Position
    
    local dir = desiredPos - basePos
    local wallHit = workspace:Raycast(basePos, dir, params)
    if wallHit then
        desiredPos = wallHit.Position + (wallHit.Normal * 0.5)
    end
    
    camera.CFrame = CFrame.new(desiredPos, basePos + (rot.LookVector * 100))
    
    local isStopping = (stopTransition or transitionAlpha >= 1)
    
    if isStopping then
        local cancelledMidway = stopTransition and transitionAlpha < 1
        
        transitionActive = false
        stopTransition = false
        RunService:UnbindFromRenderStep("GunCamTransition")
        
        -- FINAL HANDOFF
        local finalCF = CFrame.new(desiredPos, basePos + (rot.LookVector * 100))
        camera.CFrame = finalCF
        
        -- Calculate distance (Maintain current zoom if cancelled)
        local zoomDist = cancelledMidway and (desiredPos - basePos).Magnitude or TRANSITION_ZOOM
        
        -- Set Focus roughly near character
        camera.Focus = finalCF * CFrame.new(0, 0, -zoomDist) 
        camera.CameraType = Enum.CameraType.Custom
        
        -- FORCE ZOOM RESET
        player.CameraMinZoomDistance = zoomDist
        player.CameraMaxZoomDistance = zoomDist
        
        task.delay(0.05, function()
            player.CameraMinZoomDistance = 0.5
            player.CameraMaxZoomDistance = 400
            player.CameraMode = Enum.CameraMode.Classic
        end)
        
        -- Cleanup
        ContextActionService:UnbindAction("SinkZoom")
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

local function onUnequip(tool)
    equipped = false
    
    -- Cleanup Inputs & UI
    ContextActionService:UnbindAction("AAA_Fire")
    ContextActionService:UnbindAction("AAA_Reload")
    -- AAA_Aim Removed (Handled by UIS cleanup)
    RunService:UnbindFromRenderStep("AAAGunCam")
    
    if gui then gui:Destroy(); gui = nil end
    UserInputService.MouseIconEnabled = true
    
    -- Reset Variables
    startCamCFrame = nil 
    transitionAlpha = 0
    transitionActive = true
    stopTransition = false
    
    -- Take Control
    camera.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep("GunCamTransition", Enum.RenderPriority.Camera.Value + 1, transitionCamera)
    
    -- Reset OTS Tween
    local h = player.Character:FindFirstChild("Humanoid")
    if h then
        TweenService:Create(h, TweenInfo.new(0.5), {CameraOffset = Vector3.zero}):Play()
    end
end


-- 2. LOGIC LOOP (Heartbeat)
RunService.Heartbeat:Connect(function(dt)
    if not equipped then return end
    currentSpread = math.max(GunConfig.AssaultRifle.BaseSpread, currentSpread - (GunConfig.AssaultRifle.SpreadDecay * dt))
    if triggerDown then Fire() end
    updateUI()
end)

-- === LIFECYCLE ===
local function onEquip(t)
    -- FIX: RESTRICT GUN USAGE (User Request)
    -- Cannot equip if dead or ragdolled
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand then
        if hum then hum:UnequipTools() end
        return
    end

    -- Cancel transition if active
    if transitionActive then
        RunService:UnbindFromRenderStep("GunCamTransition")
        transitionActive = false
    end
    stopTransition = false

    equipped = true
    tool = t
    
    -- Find AAA Components (WaitForChild to ensure replication)
    local handle = tool:WaitForChild("Handle", 1)
    if handle then
        muzzleAtt = handle:FindFirstChild("Muzzle") or handle:WaitForChild("Muzzle", 1)
    end
    
    -- FIX 2: Hide Mouse
    UserInputService.MouseIconEnabled = false
    
    -- Initialize Camera to current look direction
    local _, rotY, _ = camera.CFrame:ToOrientation()
    camYaw = rotY
    camPitch = 0 
    currentZoom = GunConfig.AssaultRifle.OTSOffset.Z
    camSpring.Position = GunConfig.AssaultRifle.OTSOffset
    
    createUI()
    
    ContextActionService:BindAction("AAA_Fire", function(_,s) triggerDown = (s==Enum.UserInputState.Begin) end, false, Enum.UserInputType.MouseButton1)
    
    -- ADS BINDING (UserInputService) - Bypasses CAS restoration
    -- Note: Removed ContextActionService for ADS to stop flicker
    local conn1, conn2
    local function cleanupInput()
        if conn1 then conn1:Disconnect(); conn1 = nil end
        if conn2 then conn2:Disconnect(); conn2 = nil end
    end
    
    conn1 = UserInputService.InputBegan:Connect(function(input, gpe)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isAiming = true
             UserInputService.MouseIconEnabled = false -- Force off
        end
    end)
    
    conn2 = UserInputService.InputEnded:Connect(function(input, gpe)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isAiming = false
            UserInputService.MouseIconEnabled = false -- Force off
            -- Ensure it stays locked
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)
    
    -- Store cleanup for Unequip
    tool.AncestryChanged:Connect(function()
        if not tool:IsDescendantOf(player.Character) then cleanupInput() end
    end)
    player.Character.Humanoid.Died:Connect(cleanupInput)
    
    ContextActionService:BindAction("AAA_Reload", function(_,s) if s==Enum.UserInputState.Begin then Reload() end end, false, Enum.KeyCode.R)
    
    -- FORCE CAMERA SCRIPTABLE TO KILL ROBLOX INPUTS
    camera.CameraType = Enum.CameraType.Scriptable
    
    -- SINK ZOOM: Bind Wheel to nothing to prevent Roblox Zoom
    ContextActionService:BindAction("SinkZoom", function() return Enum.ContextActionResult.Sink end, false, Enum.UserInputType.MouseWheel)
    
    -- CONNECT SAFEGUARD
    if player.Character then
        local human = player.Character:FindFirstChild("Humanoid")
        if human then human.StateChanged:Connect(onStateChanged) end
    end
    
    RunService:BindToRenderStep("AAAGunCam", Enum.RenderPriority.Camera.Value + 1, updateCamera)
end

-- Legacy onUnequip deleted. Using top-defined function.

-- Detect Tool
player.CharacterAdded:Connect(function(c)
    c.ChildAdded:Connect(function(t) if t:IsA("Tool") and t.Name == "AssaultRifle" then onEquip(t) end end)
    c.ChildRemoved:Connect(function(t) if t:IsA("Tool") and t.Name == "AssaultRifle" then onUnequip() end end)
end)

-- Initial check
if player.Character then
    local t = player.Character:FindFirstChild("AssaultRifle")
    if t then onEquip(t) end
end

-- FIX: HIDE BACKPACK (Hotbar) - User Request
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- FIX: BIND 'F' TO EQUIP/UNEQUIP
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F then
        local char = player.Character
        if not char then return end
        
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand then return end
        
        -- Removed SeatPart check to allow crawl-equip

        
        -- Check if currently equipped
        local currentTool = char:FindFirstChild("AssaultRifle")
        if currentTool then
            -- Unequip
            hum:UnequipTools()
        else
            -- Equip
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                local tool = backpack:FindFirstChild("AssaultRifle")
                if tool then
                    hum:EquipTool(tool)
                end
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        -- SIM 49.6: STOP UNEQUIP TRANSITION EARLY (No snap)
        if transitionActive then
            print("🖱️ TRANSITION STOPPED BY RIGHT CLICK")
            stopTransition = true
        end
    end
end)
