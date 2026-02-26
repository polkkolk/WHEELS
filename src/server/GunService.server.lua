-- GunService.server.lua (Server)
-- Handles validation and damage for Sim 48.0 AAA Gun System

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- GAME KILL TRACKING: Bind to GameService via BindableEvent
local function fireGameKill(attackerPlayer, victimPlayer)
	local bindable = ServerStorage:FindFirstChild("GameKillBindable")
	if bindable then
		bindable:Fire(attackerPlayer, victimPlayer)
	end
end

-- TEAM CHECK: returns true if two named entities are on the same team
local function sameTeam(attackerName, victimName)
	local fn = ServerStorage:FindFirstChild("GetPlayerTeam")
	if not fn then return false end
	local at = fn:Invoke(attackerName)
	local vt = fn:Invoke(victimName)
	return at ~= nil and at == vt
end

local GunConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GunConfig"))

-- Remotes
local function getRemote(name)
    local r = ReplicatedStorage:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = ReplicatedStorage
    end
    return r
end

local GunFireEvent = getRemote("GunFireEvent")
local GunReloadEvent = getRemote("GunReloadEvent")
local GunHitEvent = getRemote("GunHitEvent") -- Server -> Client: damage feedback
local BloodEvent = getRemote("BloodEvent") -- VFX Broadcast
local KillEvent = getRemote("KillEvent") -- Notification Event

-- State Tracker
local playerStates = {}

local function getPlayerState(player)
    if not playerStates[player] then
        playerStates[player] = {
            LastFire = 0,
            Ammo = GunConfig.AssaultRifle.MagSize,
            Reloading = false
        }
    end
    return playerStates[player]
end

-- 1. FIRE HANDLER (With Tolerance)
GunFireEvent.OnServerEvent:Connect(function(player, origin, direction, target, hitPosition)
    local state = getPlayerState(player)
    local config = GunConfig.AssaultRifle
    
    local now = tick()
    
    -- A. Fire Rate Check (Grace 50ms)
    if now - state.LastFire < config.FireRate - 0.05 then return end
    
    -- B. Ammo Check
    if state.Ammo <= 0 or state.Reloading then return end
    
    -- Update State
    state.LastFire = now
    state.Ammo = state.Ammo - 1
    
    -- C. Hit Validation
    if target and target.Parent then
        local hitModel = target.Parent
        local humanoid = hitModel:FindFirstChild("Humanoid")
        
        -- Also check grandparent (for accessories/hats)
        if not humanoid then
            hitModel = target.Parent.Parent
            if hitModel then
                humanoid = hitModel:FindFirstChild("Humanoid")
            end
        end
        
        if humanoid and humanoid.Health > 0 then
            -- Distance Check
            local dist = (origin - hitPosition).Magnitude
            if dist > config.MaxDistance + 20 then return end
            
            -- FRIENDLY FIRE: skip damage if same team
            if sameTeam(player.Name, hitModel.Name) then return end

            -- Headshot Detection
            local isHeadshot = (target.Name == "Head")
            local damage = isHeadshot and config.HeadshotDamage or config.Damage
            
            -- KILL CREDIT LOGIC
            local wasAlive = humanoid.Health > 0
            humanoid:TakeDamage(damage)
            
            -- If we dealt the killing blow
            if wasAlive and humanoid.Health <= 0 then
                local ls = player:FindFirstChild("leaderstats")
                local kills = ls and ls:FindFirstChild("Kills")
                if kills then
                    kills.Value = kills.Value + 1
                    print("🏆 KILL:", player.Name, "killed", hitModel.Name)
                    
                    -- NOTIFY CLIENT
                    local KillEvent = getRemote("KillEvent")
                    KillEvent:FireClient(player, hitModel.Name, "Killed")
                    
                    -- GAME KILL TRACKING: Count all kills (players + dummies)
                    fireGameKill(player, nil)
                end
            end
            
            print(isHeadshot and "💀 HEADSHOT:" or "❌ Hit:", hitModel.Name, "| Dmg:", damage, "| Rem:", state.Ammo)
            
            -- Tell the shooter client about the hit (for floating damage numbers)
            GunHitEvent:FireClient(player, hitPosition, damage, isHeadshot)
            
            -- REPLICATED BLOOD VFX: Fire "Gunshot" type
            -- Normal is Bullet Direction (Exit Wound / Away from shooter)
            local hitNormal = (hitPosition - origin).Unit 
            BloodEvent:FireAllClients(hitPosition, hitNormal, hitModel, player, "Gunshot")
        end
    end
    
    -- Replicate Tracers to others? (TODO Loop)
end)

-- 3. LEADERSTATS & DATASTORE SETUP
local DataStoreService = game:GetService("DataStoreService")
local statsStore = DataStoreService:GetDataStore("WheelchairWarriors_Stats")

local function saveStats(player)
    local ls = player:FindFirstChild("leaderstats")
    local kills = ls and ls:FindFirstChild("Kills")
    local wins  = ls and ls:FindFirstChild("Wins")
    if kills then
        pcall(function() statsStore:SetAsync("Kills_" .. player.UserId, kills.Value) end)
    end
    if wins then
        pcall(function() statsStore:SetAsync("Wins_" .. player.UserId, wins.Value) end)
    end
end

Players.PlayerAdded:Connect(function(player)
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls.Parent = player
    
    local kills = Instance.new("IntValue")
    kills.Name = "Kills"
    kills.Parent = ls
    
    local wins = Instance.new("IntValue")
    wins.Name = "Wins"
    wins.Parent = ls
    
    -- Load Data
    local success, savedKills = pcall(function()
        return statsStore:GetAsync("Kills_" .. player.UserId)
    end)
    if success and savedKills then kills.Value = savedKills else kills.Value = 0 end

    local okW, savedWins = pcall(function()
        return statsStore:GetAsync("Wins_" .. player.UserId)
    end)
    if okW and savedWins then wins.Value = savedWins else wins.Value = 0 end
end)

Players.PlayerRemoving:Connect(function(player)
    saveStats(player)
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveStats(player)
    end
end)

-- 2. RELOAD HANDLER
GunReloadEvent.OnServerEvent:Connect(function(player)
    local state = getPlayerState(player)
    if state.Reloading then return end
    
    state.Reloading = true
    task.wait(GunConfig.AssaultRifle.ReloadTime)
    
    state.Ammo = GunConfig.AssaultRifle.MagSize
    state.Reloading = false
    print("🔄 Reloaded:", player.Name)
end)

-- 3. ASSET SETUP (Tool Giver)
local TOOL_NAME = "AssaultRifle"
local function setupTool()
    -- Always recreate to ensure latest config is applied
    local old = game.StarterPack:FindFirstChild(TOOL_NAME)
    if old then old:Destroy() end
    
    -- Also remove from all current player backpacks/characters
    for _, p in ipairs(Players:GetPlayers()) do
        local bp = p.Backpack:FindFirstChild(TOOL_NAME)
        if bp then bp:Destroy() end
        if p.Character then
            local ch = p.Character:FindFirstChild(TOOL_NAME)
            if ch then ch:Destroy() end
        end
    end
    
    local t = Instance.new("Tool")
    t.Name = TOOL_NAME
    t.RequiresHandle = true
    t.CanBeDropped = false
    t.GripPos = Vector3.new(0, -0.15, 0.4)
    t.GripForward = Vector3.new(0, 0, -1)
    t.GripRight = Vector3.new(1, 0, 0)
    t.GripUp = Vector3.new(0, 1, 0)
    
    -- COLORS
    local gunmetal = Color3.fromRGB(45, 45, 50)
    local darkGrey = Color3.fromRGB(35, 35, 38)
    local barrelCol = Color3.fromRGB(55, 55, 60)
    local magColor = Color3.fromRGB(40, 40, 42)
    local accent   = Color3.fromRGB(60, 60, 65)
    
    -- Helper: create a part and weld it to the handle
    local function gunPart(name, size, cf, color, material, parent)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Color = color or gunmetal
        p.Material = material or Enum.Material.SmoothPlastic
        p.CanCollide = false
        p.Anchored = false
        p.CFrame = cf
        p.Parent = parent or t
        return p
    end
    
    local function weldTo(part, handle)
        local w = Instance.new("WeldConstraint")
        w.Part0 = handle
        w.Part1 = part
        w.Parent = handle
    end
    
    -- ═══════════════════════════════════════════
    -- GUN BUILD (Assault Rifle — Detailed Multi-Part)
    -- ═══════════════════════════════════════════
    
    -- 1. HANDLE / RECEIVER (Tool Handle)
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.35, 0.5, 1.8)
    handle.Color = gunmetal
    handle.Material = Enum.Material.SmoothPlastic
    handle.CanCollide = false
    handle.Parent = t
    
    local baseCF = CFrame.new(0, 0, 0)
    handle.CFrame = baseCF
    
    -- Upper receiver (slightly raised flat top)
    local upperReceiver = gunPart("UpperReceiver",
        Vector3.new(0.33, 0.12, 1.6),
        baseCF * CFrame.new(0, 0.31, -0.1),
        gunmetal, Enum.Material.SmoothPlastic)
    weldTo(upperReceiver, handle)
    
    -- 2. BARREL
    local barrelPart = gunPart("Barrel",
        Vector3.new(0.15, 0.15, 2.2),
        baseCF * CFrame.new(0, 0.08, -1.9),
        barrelCol, Enum.Material.Metal)
    weldTo(barrelPart, handle)
    
    -- Gas tube (thin tube above barrel)
    local gasTube = gunPart("GasTube",
        Vector3.new(0.06, 0.06, 1.2),
        baseCF * CFrame.new(0, 0.22, -1.4),
        barrelCol, Enum.Material.Metal)
    weldTo(gasTube, handle)
    
    -- 3. HANDGUARD (Quad-rail style)
    local handguard = gunPart("Handguard",
        Vector3.new(0.32, 0.3, 1.1),
        baseCF * CFrame.new(0, 0.08, -1.35),
        darkGrey, Enum.Material.DiamondPlate)
    weldTo(handguard, handle)
    
    -- Handguard rail grooves (top)
    local hgRail = gunPart("HGRailTop",
        Vector3.new(0.2, 0.04, 1.0),
        baseCF * CFrame.new(0, 0.24, -1.35),
        accent, Enum.Material.Metal)
    weldTo(hgRail, handle)
    
    -- 4. PICATINNY RAIL (flat top rail on upper receiver)
    local picRail = gunPart("PicatinnyRail",
        Vector3.new(0.16, 0.04, 1.4),
        baseCF * CFrame.new(0, 0.39, -0.15),
        accent, Enum.Material.Metal)
    weldTo(picRail, handle)
    
    -- 5. STOCK (M4-style telescoping)
    local stockTube = gunPart("StockTube",
        Vector3.new(0.18, 0.18, 1.1),
        baseCF * CFrame.new(0, 0.05, 1.25),
        darkGrey, Enum.Material.Metal)
    weldTo(stockTube, handle)
    
    local stockBody = gunPart("StockBody",
        Vector3.new(0.28, 0.4, 0.6),
        baseCF * CFrame.new(0, 0.02, 1.55),
        darkGrey, Enum.Material.SmoothPlastic)
    weldTo(stockBody, handle)
    
    -- Cheek rest
    local cheekRest = gunPart("CheekRest",
        Vector3.new(0.24, 0.08, 0.35),
        baseCF * CFrame.new(0, 0.25, 1.5),
        darkGrey, Enum.Material.SmoothPlastic)
    weldTo(cheekRest, handle)
    
    -- Buttpad
    local buttpad = gunPart("Buttpad",
        Vector3.new(0.26, 0.42, 0.06),
        baseCF * CFrame.new(0, 0.02, 1.88),
        Color3.fromRGB(25, 25, 25), Enum.Material.Rubber)
    weldTo(buttpad, handle)
    
    -- 6. PISTOL GRIP (Ergonomic, angled)
    local grip = gunPart("PistolGrip",
        Vector3.new(0.22, 0.6, 0.28),
        baseCF * CFrame.new(0, -0.48, 0.25) * CFrame.Angles(math.rad(-12), 0, 0),
        darkGrey, Enum.Material.SmoothPlastic)
    weldTo(grip, handle)
    
    -- Grip texture (rubberized bottom)
    local gripTex = gunPart("GripTexture",
        Vector3.new(0.23, 0.25, 0.22),
        baseCF * CFrame.new(0, -0.58, 0.22) * CFrame.Angles(math.rad(-12), 0, 0),
        Color3.fromRGB(30, 30, 30), Enum.Material.DiamondPlate)
    weldTo(gripTex, handle)
    
    -- 7. TRIGGER GUARD
    local trigGuardFront = gunPart("TrigGuardF",
        Vector3.new(0.08, 0.1, 0.04),
        baseCF * CFrame.new(0, -0.22, -0.15),
        gunmetal, Enum.Material.Metal)
    weldTo(trigGuardFront, handle)
    
    local trigGuardBottom = gunPart("TrigGuardB",
        Vector3.new(0.08, 0.04, 0.35),
        baseCF * CFrame.new(0, -0.27, 0.0),
        gunmetal, Enum.Material.Metal)
    weldTo(trigGuardBottom, handle)
    
    -- Trigger
    local trigger = gunPart("Trigger",
        Vector3.new(0.04, 0.12, 0.04),
        baseCF * CFrame.new(0, -0.17, 0.0) * CFrame.Angles(math.rad(-20), 0, 0),
        Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
    weldTo(trigger, handle)
    
    -- 8. MAGAZINE (STANAG-style)
    local mag = gunPart("Magazine",
        Vector3.new(0.18, 0.75, 0.28),
        baseCF * CFrame.new(0, -0.55, -0.3) * CFrame.Angles(math.rad(-5), 0, 0),
        magColor, Enum.Material.Metal)
    weldTo(mag, handle)
    
    -- Mag base plate
    local magBase = gunPart("MagBase",
        Vector3.new(0.2, 0.04, 0.3),
        baseCF * CFrame.new(0, -0.93, -0.33) * CFrame.Angles(math.rad(-5), 0, 0),
        accent, Enum.Material.Metal)
    weldTo(magBase, handle)
    
    -- 9. CHARGING HANDLE (top rear)
    local chargingHandle = gunPart("ChargingHandle",
        Vector3.new(0.12, 0.06, 0.12),
        baseCF * CFrame.new(0, 0.35, 0.65),
        accent, Enum.Material.Metal)
    weldTo(chargingHandle, handle)
    
    -- 10. EJECTION PORT (right side cutout detail)
    local ejectionPort = gunPart("EjectionPort",
        Vector3.new(0.04, 0.14, 0.28),
        baseCF * CFrame.new(0.17, 0.18, 0.15),
        Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
    weldTo(ejectionPort, handle)
    
    -- Dust cover (over ejection port)
    local dustCover = gunPart("DustCover",
        Vector3.new(0.04, 0.02, 0.3),
        baseCF * CFrame.new(0.17, 0.26, 0.15),
        gunmetal, Enum.Material.SmoothPlastic)
    weldTo(dustCover, handle)
    
    -- 11. BOLT RELEASE (left side)
    local boltRelease = gunPart("BoltRelease",
        Vector3.new(0.04, 0.08, 0.1),
        baseCF * CFrame.new(-0.17, 0.1, 0.0),
        accent, Enum.Material.Metal)
    weldTo(boltRelease, handle)
    
    -- 12. FOREGRIP (stubby vertical grip)
    local foregrip = gunPart("Foregrip",
        Vector3.new(0.14, 0.3, 0.14),
        baseCF * CFrame.new(0, -0.22, -1.2),
        darkGrey, Enum.Material.SmoothPlastic)
    weldTo(foregrip, handle)
    
    -- 13. MUZZLE BRAKE (3-slot)
    local muzzleBrake = gunPart("MuzzleBrake",
        Vector3.new(0.2, 0.2, 0.25),
        baseCF * CFrame.new(0, 0.08, -2.95),
        accent, Enum.Material.Metal)
    weldTo(muzzleBrake, handle)
    
    -- Muzzle brake vent slots
    local ventR = gunPart("VentR",
        Vector3.new(0.04, 0.08, 0.15),
        baseCF * CFrame.new(0.12, 0.08, -2.92),
        Color3.fromRGB(15, 15, 15), Enum.Material.Metal)
    weldTo(ventR, handle)
    
    local ventL = gunPart("VentL",
        Vector3.new(0.04, 0.08, 0.15),
        baseCF * CFrame.new(-0.12, 0.08, -2.92),
        Color3.fromRGB(15, 15, 15), Enum.Material.Metal)
    weldTo(ventL, handle)
    
    -- 14. RED DOT SIGHT
    local sightBase = gunPart("SightBase",
        Vector3.new(0.18, 0.12, 0.3),
        baseCF * CFrame.new(0, 0.47, -0.3),
        Color3.fromRGB(30, 32, 35), Enum.Material.SmoothPlastic)
    weldTo(sightBase, handle)
    
    -- Sight housing (hood)
    local sightHood = gunPart("SightHood",
        Vector3.new(0.2, 0.18, 0.06),
        baseCF * CFrame.new(0, 0.5, -0.45),
        Color3.fromRGB(30, 32, 35), Enum.Material.SmoothPlastic)
    weldTo(sightHood, handle)
    
    local sightHoodR = gunPart("SightHoodR",
        Vector3.new(0.2, 0.18, 0.06),
        baseCF * CFrame.new(0, 0.5, -0.15),
        Color3.fromRGB(30, 32, 35), Enum.Material.SmoothPlastic)
    weldTo(sightHoodR, handle)
    
    -- Reticle (glowing red dot)
    local reticle = gunPart("Reticle",
        Vector3.new(0.03, 0.03, 0.03),
        baseCF * CFrame.new(0, 0.5, -0.3),
        Color3.fromRGB(255, 0, 0), Enum.Material.Neon)
    weldTo(reticle, handle)
    
    -- 15. FRONT SIGHT POST
    local frontSight = gunPart("FrontSight",
        Vector3.new(0.04, 0.18, 0.04),
        baseCF * CFrame.new(0, 0.27, -2.65),
        darkGrey, Enum.Material.Metal)
    weldTo(frontSight, handle)
    
    -- Front sight base
    local fSightBase = gunPart("FSightBase",
        Vector3.new(0.14, 0.06, 0.14),
        baseCF * CFrame.new(0, 0.19, -2.65),
        darkGrey, Enum.Material.Metal)
    weldTo(fSightBase, handle)
    
    -- 16. MUZZLE FLASH POINT (Attachment & Part)
    -- Invisible part for reference (optional, but good for raycasting if needed elsewhere)
    local muzzle = gunPart("MuzzlePart",
        Vector3.new(0.1, 0.1, 0.1),
        baseCF * CFrame.new(0, 0.08, -3.1),
        gunmetal)
    muzzle.Transparency = 1
    weldTo(muzzle, handle)
    
    -- AAA SETUP: Muzzle Attachment (For Flash & Smoke)
    local muzzleAtt = Instance.new("Attachment")
    muzzleAtt.Name = "Muzzle"
    -- Position at barrel tip, oriented so particles emit FORWARD (negative Z in tool space)
    muzzleAtt.CFrame = CFrame.new(0, 0.08, -3.1) * CFrame.Angles(0, math.rad(180), 0)
    muzzleAtt.Parent = handle
    
    -- 1. Muzzle Light (Instant flash)
    local flashLight = Instance.new("PointLight")
    flashLight.Name = "FlashLight"
    flashLight.Color = Color3.fromRGB(255, 220, 170)
    flashLight.Range = 12
    flashLight.Brightness = 0 -- Start OFF
    flashLight.Shadows = false
    flashLight.Parent = muzzleAtt
    
    -- 2. Muzzle Flash Particles (Directional forward flash)
    local flashEmitter = Instance.new("ParticleEmitter")
    flashEmitter.Name = "FlashEmitter"
    flashEmitter.Texture = "rbxassetid://6490035152" -- Sharp star/flare
    flashEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)), -- Bright white-yellow
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 200, 80)), -- Warm yellow
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 20))  -- Orange tip
    })
    flashEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4), -- Small, not orb-like
        NumberSequenceKeypoint.new(1, 0)
    })
    flashEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    flashEmitter.Lifetime = NumberRange.new(0.03, 0.05)
    flashEmitter.Speed = NumberRange.new(15, 30) -- Fast forward jet
    flashEmitter.SpreadAngle = Vector2.new(8, 8) -- Tight cone, exits barrel only
    flashEmitter.Rate = 0
    flashEmitter.LightEmission = 1
    flashEmitter.LightInfluence = 0
    flashEmitter.RotSpeed = NumberRange.new(-500, 500)
    flashEmitter.Rotation = NumberRange.new(0, 360)
    flashEmitter.Parent = muzzleAtt
    
    -- 3. Smoke/Gas Emitter (subtle wisp exiting barrel)
    local smokeEmitter = Instance.new("ParticleEmitter")
    smokeEmitter.Name = "SmokeEmitter"
    smokeEmitter.Texture = "rbxassetid://1084981836" -- Soft smoke puff
    smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(160, 160, 160))
    smokeEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 0.6)
    })
    smokeEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(1, 1)
    })
    smokeEmitter.Lifetime = NumberRange.new(0.1, 0.25)
    smokeEmitter.Speed = NumberRange.new(5, 12) -- Forward out barrel
    smokeEmitter.SpreadAngle = Vector2.new(10, 10) -- Tight
    smokeEmitter.Rate = 0
    smokeEmitter.LightEmission = 0.2
    smokeEmitter.RotSpeed = NumberRange.new(-100, 100)
    smokeEmitter.Rotation = NumberRange.new(0, 360)
    smokeEmitter.Parent = muzzleAtt
    
    -- NOTE: FireSound is handled CLIENT-SIDE in GunController.client.lua\n    -- (Avoids Roblox audio privacy issues with asset IDs)
    
    t.Parent = game.StarterPack
    
    -- Preview copy in workspace for inspection
    local previewModel = Instance.new("Model")
    previewModel.Name = "GunPreview"
    for _, child in ipairs(t:GetChildren()) do
        local clone = child:Clone()
        if clone:IsA("BasePart") then
            clone.Anchored = true
            clone.CanCollide = false
        end
        clone.Parent = previewModel
    end
    if previewModel:FindFirstChild("Handle") then
        previewModel.PrimaryPart = previewModel.Handle
        previewModel:PivotTo(CFrame.new(0, 10, -10))
    end
    previewModel.Parent = workspace
    
    -- Distribute to current players
    for _, p in ipairs(Players:GetPlayers()) do
        if not p.Backpack:FindFirstChild(TOOL_NAME) then
            t:Clone().Parent = p.Backpack
        end
    end
end
setupTool()
print("✅ GunService Sim 48.0 Loaded")
