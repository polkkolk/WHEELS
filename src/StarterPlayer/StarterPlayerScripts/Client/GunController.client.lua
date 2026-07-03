local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

print("🔴 GUN CONTROLLER v5952 (SYNC VERIFIED - PATH FIXED) LOADED 🔴")

-- Fallback for GunConfig: Check both shared/ and root
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local GunConfig
if Shared and Shared:FindFirstChild("GunConfig") then
    GunConfig = require(Shared.GunConfig)
else
    GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
end

local GunFireEvent = ReplicatedStorage:WaitForChild("GunFireEvent")
local GunReloadEvent = ReplicatedStorage:WaitForChild("GunReloadEvent")
local GunHitEvent = ReplicatedStorage:WaitForChild("GunHitEvent")
local GunSoundEvent = ReplicatedStorage:WaitForChild("GunSoundEvent", 10)
local GameEvent   = ReplicatedStorage:WaitForChild("GameEvent", 10)

-- SUPPORTED WEAPONS
local WEAPON_NAMES = {"AssaultRifle", "Pistol"}
local adsConn1, adsConn2
local isEquipping = false

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

-- Team data (populated from round_start)
local myTeam   = nil
local teamData = {}
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
local muzzleAtt = nil
local fireSound = nil

-- WEAPON SWITCHING STATE
local currentWeaponName = "AssaultRifle" -- Which weapon is currently active
local lastWeaponName = "AssaultRifle"    -- Last weapon used (for F toggle)

-- Per-weapon ammo tracking (persists across equip/unequip within a life)
local weaponAmmo = {
    AssaultRifle = GunConfig.AssaultRifle.MagSize,
    Pistol = GunConfig.Pistol.MagSize,
}

local reloading = false
local lastFire = 0
local triggerDown = false
local firedThisClick = false -- For semi-auto: ensures only 1 shot per click

-- Active config (set on equip based on currentWeaponName)
local activeConfig = GunConfig.AssaultRifle

local currentSpread = GunConfig.AssaultRifle.BaseSpread
local camSpring = Spring.new(5, 50, 4, 4)
local recoilSpring = Spring.new(5, 40, 5, 4)

local camYaw = 0
local camPitch = 0
local currentZoom = GunConfig.AssaultRifle.OTSOffset.Z
local targetOffset = GunConfig.AssaultRifle.OTSOffset
local isAiming = false

-- Forward Declarations
local Reload 

-- UI
local gui, crosshairTop, crosshairBottom, crosshairLeft, crosshairRight, centerDot, ammoLabel
local reloadBarBg, reloadBarFill

-- === HELPER FUNCTIONS ===

-- Floating Damage Numbers (RIVALS-style)
local function showDamageNumber(worldPos, damage, isHeadshot)
    local camPos = camera.CFrame.Position
    local dist = (worldPos - camPos).Magnitude
    local scaleMult = math.clamp(dist / 20, 1, 5)
    
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
        label.TextColor3 = Color3.fromRGB(255, 50, 50)
    else
        label.TextColor3 = Color3.new(1, 1, 1)
    end
    label.Parent = billboard
    
    local startY = part.Position.Y
    local lifetime = 0.8
    local elapsed = 0
    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
        elapsed = elapsed + dt
        local alpha = elapsed / lifetime
        
        part.Position = Vector3.new(part.Position.X, startY + alpha * 3, part.Position.Z)
        
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

if GunSoundEvent then
    GunSoundEvent.OnClientEvent:Connect(function(origin)
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://6862108495"
        s.Volume = 0.2
        s.PlaybackSpeed = 1.0 + (math.random() - 0.5) * 0.1
        s.RollOffMaxDistance = 140
        s.RollOffMinDistance = 15
        s.EmitterSize = 10
        
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.Transparency = 1
        p.Size = Vector3.new(0.1, 0.1, 0.1)
        p.Position = origin
        p.Parent = workspace
        
        s.Parent = p
        s:Play()
        s.Ended:Once(function()
            p:Destroy()
        end)
    end)
end
local function createUI()
    if gui then gui:Destroy() end
    gui = Instance.new("ScreenGui")
    gui.Name = "AAAGunUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player.PlayerGui
    
    local crosshairFolder = Instance.new("Folder")
    crosshairFolder.Name = "Crosshair"
    crosshairFolder.Parent = gui
    
    local function makeLine(name, size)
        local f = Instance.new("Frame")
        f.Name = name
        f.Size = size
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BackgroundColor3 = Color3.new(1, 1, 1)
        f.BorderSizePixel = 0
        f.Parent = crosshairFolder
        return f
    end
    
    crosshairTop = makeLine("Top", UDim2.new(0, 2, 0, 6))
    crosshairBottom = makeLine("Bottom", UDim2.new(0, 2, 0, 6))
    crosshairLeft = makeLine("Left", UDim2.new(0, 6, 0, 2))
    crosshairRight = makeLine("Right", UDim2.new(0, 6, 0, 2))
    
    centerDot = Instance.new("Frame")
    centerDot.Name = "CenterDot"
    centerDot.Size = UDim2.new(0, 2, 0, 2)
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
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
    reloadBarBg.Position = UDim2.new(0.5, -22, 0.5, 0)
    reloadBarBg.Size = UDim2.new(0, 4, 0, 40)
    reloadBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    reloadBarBg.BackgroundTransparency = 0.3
    reloadBarBg.BorderSizePixel = 0
    reloadBarBg.Visible = false
    reloadBarBg.Parent = gui
    
    local barStroke = Instance.new("UIStroke")
    barStroke.Color = Color3.fromRGB(180, 180, 180)
    barStroke.Thickness = 1
    barStroke.Transparency = 0.5
    barStroke.Parent = reloadBarBg
    
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 2)
    barCorner.Parent = reloadBarBg
    
    reloadBarFill = Instance.new("Frame")
    reloadBarFill.Name = "ReloadBarFill"
    reloadBarFill.AnchorPoint = Vector2.new(0, 1)
    reloadBarFill.Position = UDim2.new(0, 0, 1, 0)
    reloadBarFill.Size = UDim2.new(1, 0, 0, 0)
    reloadBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    reloadBarFill.BorderSizePixel = 0
    reloadBarFill.Parent = reloadBarBg
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = reloadBarFill
end

local function updateUI()
    if not gui then return end
    local ammo = weaponAmmo[currentWeaponName] or 0
    ammoLabel.Text = tostring(ammo) .. " / " .. tostring(activeConfig.MagSize)
    if ammo < 10 then ammoLabel.TextColor3 = Color3.fromRGB(255, 50, 50) else ammoLabel.TextColor3 = Color3.new(1,1,1) end
    
    local scaleFactor = isAiming and 8 or 16 
    local range = currentSpread * scaleFactor
    
    crosshairTop.Position = UDim2.new(0.5, 0, 0.5, -range - 6)
    crosshairBottom.Position = UDim2.new(0.5, 0, 0.5, range + 6)
    crosshairLeft.Position = UDim2.new(0.5, -range - 6, 0.5, 0)
    crosshairRight.Position = UDim2.new(0.5, range + 6, 0.5, 0)
    
    -- TINT RED IF AIM ASSIST ACTIVE
    if currentAssistTarget then
        centerDot.BackgroundColor3 = Color3.new(1, 0, 0)
    else
        centerDot.BackgroundColor3 = Color3.new(1, 1, 1)
    end
end

local function getGlobalIgnoreList()
    local list = {player.Character}
    local CollectionService = game:GetService("CollectionService")
    for _, part in ipairs(CollectionService:GetTagged("IgnoredWheelchairPart")) do
        table.insert(list, part)
    end
    return list
end

-- === VFX & SFX (AAA Standards) ===
local function playMuzzleFlash()
    if not muzzleAtt then return end
    
    local flashEmitter = muzzleAtt:FindFirstChild("FlashEmitter")
    if flashEmitter then
        flashEmitter:Emit(math.random(3, 5))
    end
    
    local smokeEmitter = muzzleAtt:FindFirstChild("SmokeEmitter")
    if smokeEmitter then
        smokeEmitter:Emit(math.random(2, 3))
    end
    
    local light = muzzleAtt:FindFirstChild("FlashLight")
    if light then
        light.Brightness = math.random(6, 10)
        task.delay(0.04, function()
            if light then light.Brightness = 0 end
        end)
    end
end

local function playGunshot()
    local handle = tool and tool:FindFirstChild("Handle")
    if not handle then return end
    
    -- Use different sounds for pistol vs rifle
    local soundId = "rbxassetid://6862108495" -- Default: Rifle gunshot
    if currentWeaponName == "Pistol" then
        soundId = "rbxassetid://6862108495" -- TODO: Replace with pistol sound asset if available
    end
    
    local s = Instance.new("Sound")
    s.SoundId = soundId
    s.Volume = 0.2
    s.PlaybackSpeed = currentWeaponName == "Pistol" and (1.2 + (math.random() - 0.5) * 0.15) or (1.0 + (math.random() - 0.5) * 0.1)
    s.RollOffMaxDistance = 140
    s.RollOffMinDistance = 15
    s.EmitterSize = 10
    s.Parent = handle
    s:Play()
    s.Ended:Once(function() s:Destroy() end)
end

local function Fire()
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics then
        return 
    end

    local ammo = weaponAmmo[currentWeaponName] or 0
    
    if ammo <= 0 then
        Reload() 
        return 
    end
    if reloading then return end
    
    -- Semi-auto check: if weapon is NOT full-auto, only fire once per click
    if not activeConfig.FullAuto and firedThisClick then return end
    
    local cfg = activeConfig
    
    local now = tick()
    if now - lastFire < cfg.FireRate then return end
    lastFire = now
    
    weaponAmmo[currentWeaponName] = ammo - 1
    firedThisClick = true -- Mark that we fired this click (for semi-auto)
    
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
    params.FilterDescendantsInstances = getGlobalIgnoreList()
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local result = workspace:Raycast(camCF.Position, spreadDir * cfg.MaxDistance, params)
    
    -- 4. NETWORK (send weapon name as first arg)
    local muzzle = tool and tool:FindFirstChild("MuzzlePart")
    local barrel = tool and tool:FindFirstChild("Handle")
    local originPos = (muzzle and muzzle.Position) or (barrel and barrel.Position) or camCF.Position
    GunFireEvent:FireServer(currentWeaponName, originPos, spreadDir, result and result.Instance, result and result.Position)
    
    -- 5. HIT MARKER SOUND
    if result and result.Instance then
        local hitPart = result.Instance
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        if hitModel and hitModel:FindFirstChildOfClass("Humanoid") then
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
                
                 -- VFX: BULLETPROOF PROCEDURAL BLOOD MIST ON HIT
                 local hitPos = result.Position
                 local TweenService = game:GetService("TweenService")
                 
                 for i = 1, 5 do
                     local mistPart = Instance.new("Part")
                     mistPart.Name = "BloodMist_Procedural"
                     mistPart.Shape = Enum.PartType.Ball
                     mistPart.Size = Vector3.new(0.2, 0.2, 0.2)
                     mistPart.Anchored = true
                     mistPart.CanCollide = false
                     mistPart.CanQuery = false
                     mistPart.CanTouch = false
                     mistPart.Massless = true
                     mistPart.Transparency = 0.2
                     mistPart.Material = Enum.Material.Neon
                     mistPart.Color = Color3.fromRGB(80, 0, 0)
                     
                     local randomDir = Vector3.new(
                         math.random() * 2 - 1,
                         math.random() * 2 - 1,
                         math.random() * 2 - 1
                     ).Unit
                     
                     mistPart.Position = hitPos
                     mistPart.Parent = workspace
                     
                     local tInfo = TweenInfo.new(
                         0.6 + (math.random() * 0.3),
                         Enum.EasingStyle.Quad,
                         Enum.EasingDirection.Out
                     )
                     
                     local goal = {
                         Size = Vector3.new(1.2, 1.2, 1.2),
                         Transparency = 1,
                         Position = hitPos + (randomDir * (0.2 + math.random() * 0.4))
                     }
                     
                     local tween = TweenService:Create(mistPart, tInfo, goal)
                     tween:Play()
                     
                     game:GetService("Debris"):AddItem(mistPart, 1.0)
                 end
            end
        end
    end
    
    updateUI()
end

Reload = function()
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics then return end

    local ammo = weaponAmmo[currentWeaponName] or 0
    if reloading or ammo == activeConfig.MagSize then return end
    reloading = true
    ammoLabel.Text = "RLD"
    GunReloadEvent:FireServer(currentWeaponName)
    
    -- Play reload sound
    local handle = tool and tool:FindFirstChild("Handle")
    if handle then
        local rs = Instance.new("Sound")
        rs.SoundId = "rbxassetid://6404425152"
        rs.Volume = 0.7
        rs.Parent = handle
        rs:Play()
        rs.Ended:Once(function() rs:Destroy() end)
    end
    
    local reloadTime = activeConfig.ReloadTime
    
    -- Show reload bar
    if reloadBarBg and reloadBarFill then
        reloadBarBg.Visible = true
        reloadBarBg.BackgroundTransparency = 0.3
        reloadBarFill.Size = UDim2.new(1, 0, 0, 0)
        reloadBarFill.BackgroundTransparency = 0
        
        local startTime = tick()
        local fillConn
        fillConn = RunService.RenderStepped:Connect(function()
            local elapsed = tick() - startTime
            local progress = math.clamp(elapsed / reloadTime, 0, 1)
            reloadBarFill.Size = UDim2.new(1, 0, progress, 0)
            
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
    weaponAmmo[currentWeaponName] = activeConfig.MagSize
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
local ASSIST_CONE_ANGLE = 10
local ASSIST_MAX_DIST = 150
local ASSIST_FRICTION = 0.5
local ASSIST_TRACKING_STRENGTH = 0.1
local ASSIST_PREDICTION_TIME = 0.1

-- Aim Assist State
local currentAssistTarget = nil

-- Helper: Get Best Target
local function getBestAssistTarget()
    if not player.Character then return nil end
    
    local camCF = camera.CFrame
    local camPos = camCF.Position
    local lookDir = camCF.LookVector
    
    local bestTarget = nil
    local bestDot = math.cos(math.rad(ASSIST_CONE_ANGLE))
    
    local candidates = {}
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isTeammate(p.Name) then 
            table.insert(candidates, p.Character) 
        end
    end
    
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child ~= player.Character and not isTeammate(child.Name) then
            local hum = child:FindFirstChild("Humanoid")
            local root = child:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 and not hum:GetAttribute("IsDead") then
                local isPlayer = false
                if Players:GetPlayerFromCharacter(child) then isPlayer = true end
                
                -- Skip teammates
                if isPlayer and isTeammate(child.Name) then continue end
                
                local nodes = {
                    child:FindFirstChild("Head"),
                    child:FindFirstChild("UpperTorso") or root,
                    child:FindFirstChild("LowerTorso"),
                    child:FindFirstChild("RightUpperArm"),
                    child:FindFirstChild("LeftUpperArm")
                }
                
                for _, targetNode in ipairs(nodes) do
                    if not targetNode then continue end
                    
                    local toTarget = targetNode.Position - camPos
                    if toTarget.Magnitude <= ASSIST_MAX_DIST then
                        local dir = toTarget.Unit
                        local dot = lookDir:Dot(dir)
                        
                        if dot > bestDot then
                            local params = RaycastParams.new()
                            params.FilterDescendantsInstances = getGlobalIgnoreList()
                            params.FilterType = Enum.RaycastFilterType.Exclude
                            
                            local dirUnit = toTarget.Unit
                            local rayLength = toTarget.Magnitude + 3.0 -- Penetrate the target to ensure hit
                            local hit = workspace:Raycast(camPos, dirUnit * rayLength, params)
                            
                            if hit then
                                if hit.Instance:IsDescendantOf(child) then
                                    bestTarget = targetNode
                                    bestDot = dot
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget, bestDot
end
-- ... (Main Loops) ...


-- 1. CAMERA LOOP (BindToRenderStep)
local function updateCamera(dt)
    if not equipped or not player.Character then return end
    
    UserInputService.MouseIconEnabled = false
    
    -- Mouse Delta for Camera Rotation
    local delta = UserInputService:GetMouseDelta()
    
    currentAssistTarget, assistDot = getBestAssistTarget()
    
    local frictionMult = 1.0
    local trackingStrength = 0.0
    
    if currentAssistTarget then
        local p = RaycastParams.new()
        p.FilterDescendantsInstances = getGlobalIgnoreList()
        p.FilterType = Enum.RaycastFilterType.Exclude

        local centerRay = workspace:Raycast(
                camera.CFrame.Position,
                camera.CFrame.LookVector * ASSIST_MAX_DIST,
                p
            )
            
        local onTarget = false
        if centerRay and centerRay.Instance:IsDescendantOf(currentAssistTarget.Parent) then
            onTarget = true
        end
        
        local deadzoneDot = math.cos(math.rad(3))
        
        if not onTarget and assistDot < deadzoneDot then
            if isAiming then
                frictionMult = ASSIST_FRICTION
                trackingStrength = ASSIST_TRACKING_STRENGTH
            else
                frictionMult = math.min(1.0, ASSIST_FRICTION * 1.5)
                trackingStrength = ASSIST_TRACKING_STRENGTH * 0.5
            end
        elseif onTarget then
            -- Sticky aim: slow down sensitivity when perfectly hovering on the target
            if isAiming then
                frictionMult = ASSIST_FRICTION * 0.8
            else
                frictionMult = 0.7 -- Slow down sensitivity by 30% when hipfiring on target
            end
            trackingStrength = ASSIST_TRACKING_STRENGTH -- Full magnetic pull even when dead-on
        else
            frictionMult = 1.0
            trackingStrength = 0.0
        end
    end
    
    local baseSens = isAiming and 0.002 or 0.005
    camYaw = camYaw - (delta.X * baseSens * frictionMult)
    camPitch = math.clamp(camPitch - (delta.Y * baseSens * frictionMult), -1.4, 1.4)
    
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
    
    -- C. Smooth Offset (Config-driven)
    local targetOff = activeConfig.OTSOffset
    if isAiming then
        -- ADS offset: tighter for all weapons
        local adsZ = activeConfig.OTSOffset.Z * 0.625  -- 62.5% of normal distance
        targetOff = Vector3.new(2.0, 2.0, adsZ)
    end
    
    camSpring.Target = targetOff
    local off = camSpring:Update(dt)
    
    -- D. Final Position
    local root = player.Character.PrimaryPart
    if root then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        
        local basePos = root.Position + Vector3.new(0, 2.5, 0)
        
        local desiredPos = (CFrame.new(basePos) * rot * CFrame.new(off)).Position
        local dir = desiredPos - basePos
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = getGlobalIgnoreList()
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
local stopTransition = false

-- CAMERA TRANSITION CONSTANTS (User Calibrated)
local TRANSITION_HEIGHT = -1.55
local TRANSITION_PITCH = -20
local TRANSITION_X_OFFSET = 0.2
local TRANSITION_ZOOM = 12.5

-- RAGDOLL SAFEGUARD
local function onStateChanged(old, new)
    if new == Enum.HumanoidStateType.PlatformStanding or new == Enum.HumanoidStateType.Physics then
        if equipped and tool and tool.Parent == player.Character then
            tool.Parent = player.Backpack
        end
    end
end

-- CAMERA TRANSITION LOGIC (Manual Smooth Interpolation)
local function transitionCamera(dt)
    if not transitionActive then return end
    
    transitionAlpha = math.min(transitionAlpha + (dt * 2.5), 1) 
    
    local root = player.Character.PrimaryPart
    local head = player.Character:FindFirstChild("Head")
    if not head then return end
    
    local basePos = head.Position
    
    local defaultOffset = Vector3.new(TRANSITION_X_OFFSET, TRANSITION_HEIGHT, TRANSITION_ZOOM) 
    
    local currentOff = activeConfig.OTSOffset:Lerp(defaultOffset, transitionAlpha)
    
    local _, rootYaw, _ = root.CFrame:ToOrientation()
    
    local diff = (rootYaw - camYaw + math.pi) % (2 * math.pi) - math.pi
    local blendedYaw = camYaw + (diff * transitionAlpha) 
    
    local targetPitchRad = math.rad(TRANSITION_PITCH)
    local blendedPitch = camPitch * (1-transitionAlpha) + (targetPitchRad * transitionAlpha)
    
    local rot = CFrame.fromOrientation(blendedPitch, blendedYaw, 0)
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = getGlobalIgnoreList()
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local pivot = basePos + Vector3.new(0, currentOff.Y, 0)
    
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
        
        local finalCF = CFrame.new(desiredPos, basePos + (rot.LookVector * 100))
        camera.CFrame = finalCF
        
        local zoomDist = cancelledMidway and (desiredPos - basePos).Magnitude or TRANSITION_ZOOM
        
        camera.Focus = finalCF * CFrame.new(0, 0, -zoomDist) 
        camera.CameraType = Enum.CameraType.Custom
        
        player.CameraMinZoomDistance = zoomDist
        player.CameraMaxZoomDistance = zoomDist
        
        task.delay(0.05, function()
            -- Set MinZoom slightly above 0.5 to prevent first-person lock when zoomed in, which turns the character invisible!
            player.CameraMinZoomDistance = 10
            player.CameraMaxZoomDistance = 400
            player.CameraMode = Enum.CameraMode.Classic
        end)
        
        ContextActionService:UnbindAction("SinkZoom")
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

-- ═══════════════════════════════════════════
-- GUN HOLSTER SYSTEM (must be defined BEFORE onEquip/onUnequip)
-- ═══════════════════════════════════════════
local holsterModelAR = nil   -- Assault Rifle holster (back of wheelchair)
local holsterModelPistol = nil -- Pistol holster (right hip)

local function buildHolsterForWeapon(weaponName, chairPrimary)
    if not chairPrimary then return nil end
    
    -- Find the source tool
    local sourceTool = game:GetService("StarterPack"):FindFirstChild(weaponName)
        or player.Backpack:FindFirstChild(weaponName)
        or player.Character and player.Character:FindFirstChild(weaponName)
    if not sourceTool then return nil end

    local m = Instance.new("Model")
    m.Name = weaponName .. "Holster"

    for _, part in ipairs(sourceTool:GetDescendants()) do
        if part:IsA("BasePart") then
            local clone = part:Clone()
            clone:SetAttribute("OrigTransparency", part.Transparency)
            for _, c in ipairs(clone:GetDescendants()) do
                if c:IsA("Constraint") or c:IsA("Script") or c:IsA("LocalScript") then c:Destroy() end
            end
            clone.CanCollide  = false
            clone.CanQuery    = false
            clone.CastShadow  = false
            clone.Anchored    = false
            clone.Parent      = m
        end
    end

    -- Different holster offsets per weapon
    local holsterOffset
    if weaponName == "Pistol" then
        -- BACK LEFT OF CHAIR: barrel pointing down
        holsterOffset = CFrame.new(-0.5, 1.2, 2.2)
            * CFrame.Angles(math.rad(-90), 0, 0)
    else
        -- BACK RIGHT OF CHAIR: barrel pointing down
        holsterOffset = CFrame.new(0.5, 1.2, 2.2)
            * CFrame.Angles(math.rad(-90), 0, 0)
    end

    local handle = m:FindFirstChild("Handle")
    if not handle then
        m:Destroy()
        return nil
    end
    handle.CFrame = chairPrimary.CFrame * holsterOffset

    local handleW = Instance.new("WeldConstraint")
    handleW.Part0 = chairPrimary
    handleW.Part1 = handle
    handleW.Parent = handle

    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") and p ~= handle then
            local realHandle = sourceTool:FindFirstChild("Handle")
            if realHandle then
                local relCF = realHandle.CFrame:Inverse() * p.CFrame
                p.CFrame = handle.CFrame * relCF
            end
            local w = Instance.new("WeldConstraint")
            w.Part0 = handle
            w.Part1 = p
            w.Parent = handle
        end
    end

    m.Parent = chairPrimary.Parent
    return m
end

local function buildAllHolsters(chairPrimary)
    -- Destroy old holsters
    if holsterModelAR and holsterModelAR.Parent then holsterModelAR:Destroy() end
    if holsterModelPistol and holsterModelPistol.Parent then holsterModelPistol:Destroy() end
    holsterModelAR = nil
    holsterModelPistol = nil
    
    if not chairPrimary then return end
    
    holsterModelAR = buildHolsterForWeapon("AssaultRifle", chairPrimary)
    holsterModelPistol = buildHolsterForWeapon("Pistol", chairPrimary)
    
    -- Hide the one that's currently equipped
    updateHolsterVisibility()
end

local function setHolsterTransparency(holsterModel, transparent)
    if not holsterModel then return end
    for _, p in ipairs(holsterModel:GetDescendants()) do
        if p:IsA("BasePart") then 
            local orig = p:GetAttribute("OrigTransparency")
            if orig then
                p.Transparency = transparent and 1 or orig
            end
        end
    end
end

function updateHolsterVisibility()
    if equipped then
        -- The equipped weapon's holster is hidden, the other is shown
        if currentWeaponName == "AssaultRifle" then
            setHolsterTransparency(holsterModelAR, true)  -- hide AR holster
            setHolsterTransparency(holsterModelPistol, false) -- show Pistol holster
        else
            setHolsterTransparency(holsterModelAR, false) -- show AR holster
            setHolsterTransparency(holsterModelPistol, true)  -- hide Pistol holster
        end
    else
        -- Nothing equipped, show both holsters
        setHolsterTransparency(holsterModelAR, false)
        setHolsterTransparency(holsterModelPistol, false)
    end
end

local holsterSeatedConn
local function setupHolsterTracking(char)
    if holsterSeatedConn then holsterSeatedConn:Disconnect() end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    holsterSeatedConn = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        if hum.SeatPart then
            task.wait(0.35)
            local chairModel = hum.SeatPart and hum.SeatPart.Parent
            local primary = chairModel and (chairModel.PrimaryPart or hum.SeatPart)
            if primary then
                buildAllHolsters(primary)
            end
        else
            if holsterModelAR and holsterModelAR.Parent then holsterModelAR:Destroy() end
            if holsterModelPistol and holsterModelPistol.Parent then holsterModelPistol:Destroy() end
            holsterModelAR = nil
            holsterModelPistol = nil
        end
    end)
end

local earlyUnequipTriggered = false

local function onUnequip(t)
    equipped = false
    updateHolsterVisibility()
    
    if adsConn1 then adsConn1:Disconnect() adsConn1 = nil end
    if adsConn2 then adsConn2:Disconnect() adsConn2 = nil end
    
    ContextActionService:UnbindAction("AAA_Fire")
    ContextActionService:UnbindAction("AAA_Reload")
    
    if not isEquipping then
        RunService:UnbindFromRenderStep("AAAGunCam")
        if gui then gui:Destroy(); gui = nil end
        UserInputService.MouseIconEnabled = true
    end
    
    local isDead = false
    if player.Character then
        local h = player.Character:FindFirstChild("Humanoid")
        if h and h.Health <= 0 then isDead = true end
    end
    
    if not earlyUnequipTriggered and not player:GetAttribute("ForceInstantUnequip") and not isDead then
        startCamCFrame = nil 
        transitionAlpha = 0
        transitionActive = true
        stopTransition = false
        
        camera.CameraType = Enum.CameraType.Scriptable
        RunService:BindToRenderStep("GunCamTransition", Enum.RenderPriority.Camera.Value + 1, transitionCamera)
        
        local h = player.Character:FindFirstChild("Humanoid")
        if h then
            TweenService:Create(h, TweenInfo.new(0.5), {CameraOffset = Vector3.zero}):Play()
        end
    else
        if not isEquipping then
            camera.CameraType = Enum.CameraType.Custom
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            
            -- Reset FOV immediately
            TweenService:Create(camera, TweenInfo.new(0.3), {FieldOfView = 70}):Play()
            local hum = player.Character and player.Character:FindFirstChild("Humanoid")
            if hum then
                TweenService:Create(hum, TweenInfo.new(0.3), {CameraOffset = Vector3.zero}):Play()
            end
        end
    end
    
    earlyUnequipTriggered = false
end


local armRaiseAlpha = 0

-- 2. LOGIC LOOP (Heartbeat)
RunService.Heartbeat:Connect(function(dt)
    if not equipped then return end
    currentSpread = math.max(activeConfig.BaseSpread, currentSpread - (activeConfig.SpreadDecay * dt))
    -- Full-auto: keep firing while trigger held. Semi-auto: firedThisClick prevents repeat
    if triggerDown then Fire() end
    updateUI()
    
    local timeSinceFire = tick() - lastFire
    local shouldRaise = triggerDown or (timeSinceFire < 0.6)
    if shouldRaise then
        armRaiseAlpha = math.min(armRaiseAlpha + dt * 15, 1)
    else
        armRaiseAlpha = math.max(armRaiseAlpha - dt * 3, 0)
    end
end)

-- === LIFECYCLE ===
local function onEquip(t)
    print("GunController: onEquip called for tool", t.Name)
    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics then
        print("GunController: onEquip early return! hum:", hum, "health:", hum and hum.Health, "state:", hum and hum:GetState())
        if hum then hum:UnequipTools() end
        return
    end
    
    local isCrawling = player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart:FindFirstChild("CrawlMover")
    if isCrawling and t.Name ~= "Pistol" then
        print("GunController: Cannot equip", t.Name, "while crawling!")
        if hum then hum:UnequipTools() end
        return
    end
    print("GunController: onEquip passed checks. Equipping...")

    -- Cancel transition if active
    if transitionActive then
        stopTransition = true
        RunService:UnbindFromRenderStep("GunCamTransition")
        transitionActive = false
    end
    
    -- ALWAYS unbind before binding to prevent Roblox engine bugs from stacking the renderstep
    RunService:UnbindFromRenderStep("AAAGunCam")
    RunService:BindToRenderStep("AAAGunCam", Enum.RenderPriority.Camera.Value + 1, updateCamera)
    
    equipped = true
    tool = t
    
    -- Determine which weapon this is and set the active config
    currentWeaponName = t.Name
    lastWeaponName = t.Name
    activeConfig = GunConfig[currentWeaponName] or GunConfig.AssaultRifle
    
    -- Initialize per-weapon ammo if not set
    if not weaponAmmo[currentWeaponName] then
        weaponAmmo[currentWeaponName] = activeConfig.MagSize
    end
    
    -- Reset spread to this weapon's base
    currentSpread = activeConfig.BaseSpread
    firedThisClick = false
    
    updateHolsterVisibility()
    
    local handle = tool:WaitForChild("Handle", 1)
    if handle then
        muzzleAtt = handle:FindFirstChild("Muzzle") or handle:WaitForChild("Muzzle", 1)
    end
    
    UserInputService.MouseIconEnabled = false
    
    if not isEquipping then
        local _, rotY, _ = camera.CFrame:ToOrientation()
        camYaw = rotY
        camPitch = 0 
    end
    
    isEquipping = false
    
    currentZoom = activeConfig.OTSOffset.Z
    camSpring.Position = activeConfig.OTSOffset
    
    createUI()
    
    ContextActionService:BindAction("AAA_Fire", function(_,s)
        if s == Enum.UserInputState.Begin then
            triggerDown = true
            firedThisClick = false -- Reset semi-auto flag on new click
        else
            triggerDown = false
        end
    end, false, Enum.UserInputType.MouseButton1)
    
    -- ADS BINDING
    if adsConn1 then adsConn1:Disconnect() adsConn1 = nil end
    if adsConn2 then adsConn2:Disconnect() adsConn2 = nil end
    
    adsConn1 = UserInputService.InputBegan:Connect(function(input, gpe)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isAiming = true
            UserInputService.MouseIconEnabled = false
        end
    end)
    
    adsConn2 = UserInputService.InputEnded:Connect(function(input, gpe)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            isAiming = false
            UserInputService.MouseIconEnabled = false
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)
    
    ContextActionService:BindAction("AAA_Reload", function(_,s) if s==Enum.UserInputState.Begin then Reload() end end, false, Enum.KeyCode.R)
    
    camera.CameraType = Enum.CameraType.Scriptable
    
    ContextActionService:BindAction("SinkZoom", function() return Enum.ContextActionResult.Sink end, false, Enum.UserInputType.MouseWheel)
    
    -- CONNECT SAFEGUARD
    if player.Character then
        local human = player.Character:FindFirstChild("Humanoid")
        if human then 
            human.StateChanged:Connect(onStateChanged) 
            human.Died:Connect(function()
                if equipped then
                    equipped = false
                    RunService:UnbindFromRenderStep("AAAGunCam")
                    RunService:UnbindFromRenderStep("GunCamTransition")
                    camera.CameraType = Enum.CameraType.Custom
                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    UserInputService.MouseIconEnabled = true
                    if adsConn1 then adsConn1:Disconnect() adsConn1 = nil end
                    if adsConn2 then adsConn2:Disconnect() adsConn2 = nil end
                    ContextActionService:UnbindAction("AAA_Fire")
                    ContextActionService:UnbindAction("AAA_Reload")
                    if gui then gui:Destroy(); gui = nil end
                end
            end)
        end
    end
end


-- Detect Tool equip/unequip for ANY supported weapon
local function isWeaponTool(t)
    if not t:IsA("Tool") then return false end
    for _, name in ipairs(WEAPON_NAMES) do
        if t.Name == name then return true end
    end
    return false
end

player.CharacterAdded:Connect(function(c)
    -- Reset per-weapon ammo on respawn
    weaponAmmo = {
        AssaultRifle = GunConfig.AssaultRifle.MagSize,
        Pistol = GunConfig.Pistol.MagSize,
    }
    
    setupHolsterTracking(c)
    c.ChildAdded:Connect(function(t) if isWeaponTool(t) then onEquip(t) end end)
    c.ChildRemoved:Connect(function(t) if isWeaponTool(t) then onUnequip() end end)
end)

-- Initial check
if player.Character then
    setupHolsterTracking(player.Character)
    player.Character.ChildAdded:Connect(function(t) if isWeaponTool(t) then onEquip(t) end end)
    player.Character.ChildRemoved:Connect(function(t) if isWeaponTool(t) then onUnequip(t) end end)
    -- Check if any weapon is already equipped
    for _, name in ipairs(WEAPON_NAMES) do
        local t = player.Character:FindFirstChild(name)
        if t then onEquip(t); break end
    end
end

-- FIX: HIDE BACKPACK (Hotbar)
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- ═══════════════════════════════════════════
-- WEAPON SWITCHING: 1 = AR, 2 = Pistol, F = Toggle Last
-- ═══════════════════════════════════════════

local function equipWeapon(weaponName)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Physics then return end
    if isEquipping then return end
    if player:GetAttribute("InShop") then return end
    
    local isCrawling = char.PrimaryPart and char.PrimaryPart:FindFirstChild("CrawlMover")
    if isCrawling and weaponName ~= "Pistol" then return end
    
    -- Check if this weapon is already equipped
    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool and currentTool.Name == weaponName then
        -- Same weapon: toggle unequip
        doUnequip(char, hum, currentTool)
        return
    end
    
    -- Different weapon or no weapon equipped
    if currentTool and isWeaponTool(currentTool) then
        -- Unequip current weapon first, then equip new one
        isEquipping = true
        earlyUnequipTriggered = true
        equipped = false
        
        if adsConn1 then adsConn1:Disconnect() adsConn1 = nil end
        if adsConn2 then adsConn2:Disconnect() adsConn2 = nil end
        ContextActionService:UnbindAction("AAA_Fire")
        ContextActionService:UnbindAction("AAA_Reload")
        
        task.spawn(function()
            -- Instant unequip for fast swap
            hum:UnequipTools()
            
            -- Play equip anim for new weapon
            local backpack = player:FindFirstChild("Backpack")
            local newTool = backpack and backpack:FindFirstChild(weaponName)
            if newTool and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Physics then
                if hum.SeatPart then
                    local animator = hum:FindFirstChild("Animator") or hum
                    local anim = Instance.new("Animation")
                    anim.AnimationId = "rbxassetid://128774563236313"
                    pcall(function() animator:LoadAnimation(anim):Play() end)
                end
                hum:EquipTool(newTool)
            end
            
            -- Failsafe: if we ended up empty handed, clean up the camera properly
            if not char:FindFirstChildOfClass("Tool") then
                isEquipping = false
                onUnequip(nil)
            end
        end)
        return
    end
    
    -- No weapon equipped, just equip
    doEquip(char, hum, weaponName)
end

function doUnequip(char, hum, currentTool)
    isEquipping = true
    earlyUnequipTriggered = true
    equipped = false
    
    if adsConn1 then adsConn1:Disconnect() adsConn1 = nil end
    if adsConn2 then adsConn2:Disconnect() adsConn2 = nil end
    ContextActionService:UnbindAction("AAA_Fire")
    ContextActionService:UnbindAction("AAA_Reload")
    
    if gui then gui:Destroy(); gui = nil end
    UserInputService.MouseIconEnabled = true
    
    startCamCFrame = nil 
    transitionAlpha = 0
    transitionActive = true
    stopTransition = false
    camera.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep("GunCamTransition", Enum.RenderPriority.Camera.Value + 1, transitionCamera)
    TweenService:Create(hum, TweenInfo.new(0.5), {CameraOffset = Vector3.zero}):Play()
    
    if hum.SeatPart then
        local animator = hum:FindFirstChild("Animator") or hum
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://128774563236313"
        
        task.delay(0.3, function()
            isEquipping = false
            if currentTool.Parent == char and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Physics then
                hum:UnequipTools()
            end
        end)
        
        pcall(function()
            local track = animator:LoadAnimation(anim)
            track:Play()
        end)
    else
        isEquipping = false
        if currentTool.Parent == char and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Physics then
            hum:UnequipTools()
        end
    end
end

function doEquip(char, hum, weaponName)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local weaponTool = backpack:FindFirstChild(weaponName)
    if not weaponTool then return end
    
    isEquipping = true
    
    if hum.SeatPart then
        local animator = hum:FindFirstChild("Animator") or hum
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://128774563236313"
        
        task.delay(0.3, function()
            isEquipping = false
            if weaponTool.Parent == backpack and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Physics then
                hum:EquipTool(weaponTool)
            end
        end)
        
        pcall(function()
            local track = animator:LoadAnimation(anim)
            track:Play()
        end)
    else
        isEquipping = false
        if weaponTool.Parent == backpack and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Physics then
            hum:EquipTool(weaponTool)
        end
    end
end

-- INPUT HANDLER: 1, 2, F keys + right-click transition cancel
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if input.KeyCode == Enum.KeyCode.One then
        -- 1 = Assault Rifle
        equipWeapon("AssaultRifle")
        
    elseif input.KeyCode == Enum.KeyCode.Two then
        -- 2 = Pistol
        equipWeapon("Pistol")
        
    elseif input.KeyCode == Enum.KeyCode.F then
        -- F = Toggle last used weapon
        equipWeapon(lastWeaponName)
        
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        if transitionActive then
            print("🖱️ TRANSITION STOPPED BY RIGHT CLICK")
            stopTransition = true
        end
    end
end)

-- ═══════════════════════════════════════════
-- PROCEDURAL ARM ANIMATION (Runs after Animator)
-- ═══════════════════════════════════════════
RunService.Stepped:Connect(function(_, dt)
    if not equipped or armRaiseAlpha <= 0 then return end
    local char = player.Character
    if not char then return end
    
    -- Pitch the arm with the camera
    local pitchOffset = camPitch
    local isCrawling = char.PrimaryPart and char.PrimaryPart:FindFirstChild("CrawlMover")
    
    local baseShoulderPitch = isCrawling and math.rad(180) or math.rad(90)
    local baseElbowBend = isCrawling and math.rad(30) or math.rad(15)
    
    local rightUpperArm = char:FindFirstChild("RightUpperArm")
    if rightUpperArm then
        local rightShoulder = rightUpperArm:FindFirstChild("RightShoulder")
        if rightShoulder then
            local currentTransform = rightShoulder.Transform
            -- Point forward (X=baseShoulderPitch + pitch), slightly inward (Z=-15)
            local targetTransform = CFrame.Angles(baseShoulderPitch + pitchOffset, 0, math.rad(-15))
            rightShoulder.Transform = currentTransform:Lerp(targetTransform, armRaiseAlpha)
        end
    end
    
    local rightLowerArm = char:FindFirstChild("RightLowerArm")
    if rightLowerArm then
        local rightElbow = rightLowerArm:FindFirstChild("RightElbow")
        if rightElbow then
            local currentTransform = rightElbow.Transform
            -- Bend the elbow
            local targetTransform = CFrame.Angles(baseElbowBend, 0, 0)
            rightElbow.Transform = currentTransform:Lerp(targetTransform, armRaiseAlpha)
        end
    end
    
    local rightHand = char:FindFirstChild("RightHand")
    if rightHand then
        local rightWrist = rightHand:FindFirstChild("RightWrist")
        if rightWrist then
            local currentTransform = rightWrist.Transform
            -- Straight wrist
            local targetTransform = CFrame.Angles(0, 0, 0)
            rightWrist.Transform = currentTransform:Lerp(targetTransform, armRaiseAlpha)
        end
    end
end)
