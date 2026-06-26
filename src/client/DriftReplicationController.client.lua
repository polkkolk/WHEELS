local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Dictionary to keep track of drift emitters for all wheelchairs
local wheelchairEffects = {}

local DRIFT_DEFS = {
    Default = { id = "rbxassetid://13587823522", color = Color3.fromRGB(255, 255, 255), isBubble = false },
    Fire = { id = "rbxassetid://13587823522", color = Color3.fromRGB(255, 100, 0), isBubble = false },
    Ice = { id = "rbxassetid://13587823522", color = Color3.fromRGB(0, 200, 255), isBubble = false },
    Magic = { id = "rbxassetid://243527266", color = Color3.fromRGB(200, 0, 255), isBubble = false },
    Demon = { id = "rbxassetid://243527266", color = Color3.fromRGB(255, 0, 0), isBubble = false },
    Bubbles = { id = "rbxassetid://1777844544534", color = Color3.fromRGB(255, 255, 255), isBubble = true },
    Grass = { id = "rbxassetid://77737119859056", color = Color3.fromRGB(0, 255, 100), isBubble = false },
}

local function setupDriftEffects(wheelchairModel, player)
    local effects = {}
    local equippedDrift = player:GetAttribute("Shop_Equipped_DriftVFX") or "Default"
    local def = DRIFT_DEFS[equippedDrift] or DRIFT_DEFS.Default

    local primary = wheelchairModel.PrimaryPart or wheelchairModel:FindFirstChild("Metal")
    if not primary then return end

    for _, wheelData in ipairs({
        {name = "RL", offset = Vector3.new(-1.8, -1.5, 1.3)},
        {name = "RR", offset = Vector3.new(1.8, -1.5, 1.3)}
    }) do
        local att0 = Instance.new("Attachment")
        att0.Name = "DriftAtt0_" .. wheelData.name
        att0.Position = wheelData.offset
        att0.Parent = workspace.Terrain

            local sparks = Instance.new("ParticleEmitter")
            sparks.Name = "DriftSparks_Core"
            sparks.Orientation = Enum.ParticleOrientation.FacingCamera
            sparks.LightInfluence = 0
            sparks.ZOffset = 2
            sparks.VelocityInheritance = 0.8
            sparks.Rate = 0
            sparks.EmissionDirection = Enum.NormalId.Back
            sparks.Enabled = false
            sparks.Parent = att0

            local glow = Instance.new("ParticleEmitter")
            glow.Name = "DriftSparks_Glow"
            glow.Texture = "rbxassetid://243527266"
            glow.Orientation = Enum.ParticleOrientation.FacingCamera
            glow.LightInfluence = 0
            glow.ZOffset = 1
            glow.VelocityInheritance = 0.8
            glow.Rate = 0
            glow.EmissionDirection = Enum.NormalId.Back
            glow.Enabled = false
            glow.Parent = att0

            if equippedDrift == "Magic" then
                -- Core: Pink Magic Stars
                sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                sparks.LightEmission = 1
                sparks.Brightness = 10
                sparks.Color = ColorSequence.new(Color3.fromRGB(255, 50, 200))
                sparks.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.6),
                    NumberSequenceKeypoint.new(1, 0)
                })
                sparks.Lifetime = NumberRange.new(0.4, 0.8)
                sparks.Speed = NumberRange.new(25, 45)
                sparks.SpreadAngle = Vector2.new(20, 20)
                sparks.Acceleration = Vector3.new(0, -10, 0)
                sparks.Drag = 3
                sparks.Rotation = NumberRange.new(0, 360)
                sparks.RotSpeed = NumberRange.new(-100, 100)
                
                -- Glow: Pink Heat
                glow.LightEmission = 0.8
                glow.Color = ColorSequence.new(Color3.fromRGB(255, 20, 150))
                glow.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1.2),
                    NumberSequenceKeypoint.new(1, 0.5)
                })
                glow.Lifetime = NumberRange.new(0.2, 0.4)
                glow.Speed = NumberRange.new(10, 20)
                glow.Drag = 4
                glow.Acceleration = Vector3.new(0, 10, 0)
            elseif equippedDrift == "Demon" then
                -- Core: Red fire-shaped shards
                sparks.Texture = "rbxasset://textures/particles/fire_main.dds"
                sparks.LightEmission = 1
                sparks.Brightness = 5
                sparks.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 30, 30)),
                    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 0, 0)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 0, 0))
                })
                sparks.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.3),
                    NumberSequenceKeypoint.new(0.3, 1.1),
                    NumberSequenceKeypoint.new(0.6, 0.5),
                    NumberSequenceKeypoint.new(1, 0)
                })
                sparks.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.1),
                    NumberSequenceKeypoint.new(0.8, 0.3),
                    NumberSequenceKeypoint.new(1, 1)
                })
                sparks.Lifetime = NumberRange.new(0.5, 0.9)
                sparks.Speed = NumberRange.new(30, 50)
                sparks.SpreadAngle = Vector2.new(15, 15)
                sparks.Acceleration = Vector3.new(0, -15, 0)
                sparks.Drag = 2
                sparks.Rotation = NumberRange.new(0, 360)
                sparks.RotSpeed = NumberRange.new(-60, 60)
                
                -- Glow: Dark Crimson
                glow.LightEmission = 0.3
                glow.Color = ColorSequence.new(Color3.fromRGB(80, 0, 0))
                glow.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1.5),
                    NumberSequenceKeypoint.new(1, 0.8)
                })
                glow.Lifetime = NumberRange.new(0.3, 0.6)
                glow.Speed = NumberRange.new(15, 25)
                glow.Drag = 5
                glow.Acceleration = Vector3.new(0, 5, 0)
            elseif equippedDrift == "Bubbles" then
                -- Core: Soft round bubbles floating up
                sparks.Texture = "rbxassetid://71964547566123" -- Black bg invisible at LightEmission=1
                sparks.LightEmission = 1
                sparks.LightInfluence = 0
                sparks.Brightness = 3
                sparks.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 230, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 200, 255))
                })
                sparks.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.2),
                    NumberSequenceKeypoint.new(0.3, 0.6),
                    NumberSequenceKeypoint.new(0.85, 0.8),
                    NumberSequenceKeypoint.new(1, 0)
                })
                sparks.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.3),
                    NumberSequenceKeypoint.new(0.6, 0.5),
                    NumberSequenceKeypoint.new(1, 1)
                })
                sparks.Lifetime = NumberRange.new(1.0, 2.0)
                sparks.Speed = NumberRange.new(4, 12)
                sparks.SpreadAngle = Vector2.new(50, 50)
                sparks.Acceleration = Vector3.new(0, 8, 0) -- Float upward
                sparks.Drag = 3
                sparks.Rotation = NumberRange.new(0, 360)
                sparks.RotSpeed = NumberRange.new(-10, 10) -- Barely spin
                sparks.VelocityInheritance = 0.2 -- Mostly free-floating

                -- Glow: Soft blue shimmer
                glow.LightEmission = 0.2
                glow.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
                glow.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1.0),
                    NumberSequenceKeypoint.new(1, 0.5)
                })
                glow.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.5),
                    NumberSequenceKeypoint.new(1, 1)
                })
                glow.Lifetime = NumberRange.new(0.5, 1.0)
                glow.Speed = NumberRange.new(2, 6)
                glow.Drag = 5
                glow.Acceleration = Vector3.new(0, 6, 0)
            elseif equippedDrift == "Grass" then
                -- Core: Custom transparent triangle
                sparks.Texture = "rbxassetid://77737119859056" 
                sparks.LightEmission = 1
                sparks.LightInfluence = 0
                sparks.Brightness = 3
                sparks.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 50)),
                    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 200, 40)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 120, 20))
                })
                sparks.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.1),
                    NumberSequenceKeypoint.new(0.2, 0.8),
                    NumberSequenceKeypoint.new(0.6, 0.5),
                    NumberSequenceKeypoint.new(1, 0)
                })
                sparks.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0),
                    NumberSequenceKeypoint.new(0.8, 0.1),
                    NumberSequenceKeypoint.new(1, 1)
                })
                sparks.Lifetime = NumberRange.new(0.8, 1.3)
                sparks.Speed = NumberRange.new(15, 30)
                sparks.SpreadAngle = Vector2.new(25, 25)
                sparks.Acceleration = Vector3.new(0, -10, 0)
                sparks.Drag = 2
                sparks.Rotation = NumberRange.new(0, 360)
                sparks.RotSpeed = NumberRange.new(-120, 120)

                -- Glow: Bright lime
                glow.LightEmission = 0.6
                glow.Color = ColorSequence.new(Color3.fromRGB(80, 255, 100))
                glow.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1.5),
                    NumberSequenceKeypoint.new(1, 0.5)
                })
                glow.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.5),
                    NumberSequenceKeypoint.new(1, 1)
                })
                glow.Lifetime = NumberRange.new(0.3, 0.6)
                glow.Speed = NumberRange.new(10, 20)
                glow.Drag = 4
                glow.Acceleration = Vector3.new(0, 5, 0)
            else
                -- Default: Yellow Sparks
                sparks.Texture = "rbxassetid://241594419"
                sparks.LightEmission = 1
                sparks.Brightness = 5
                sparks.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 100)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
                })
                sparks.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.3),
                    NumberSequenceKeypoint.new(1, 0)
                })
                sparks.Lifetime = NumberRange.new(0.3, 0.5)
                sparks.Speed = NumberRange.new(20, 40)
                sparks.SpreadAngle = Vector2.new(45, 45)
                sparks.Acceleration = Vector3.new(0, -30, 0)
                sparks.Drag = 2
                
                -- Glow: Orange Heat
                glow.LightEmission = 0.5
                glow.Color = ColorSequence.new(Color3.fromRGB(255, 100, 50))
                glow.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.7),
                    NumberSequenceKeypoint.new(1, 0.3)
                })
                glow.Lifetime = NumberRange.new(0.1, 0.2)
                glow.Speed = NumberRange.new(5, 10)
                glow.Drag = 5
                glow.Acceleration = Vector3.new(0, 5, 0)
            end

            table.insert(effects, {
                wheelPosOffset = wheelData.offset,
                primary = primary,
                sparks = sparks,
                glow = glow,
                lastEmit = 0
            })
    end
    
    wheelchairEffects[wheelchairModel] = {
        effects = effects,
        player = player,
        lastEquipped = equippedDrift,
        attributeConn = player:GetAttributeChangedSignal("Shop_Equipped_DriftVFX"):Connect(function()
            -- Force recreate on next frame
            if wheelchairEffects[wheelchairModel] then
                wheelchairEffects[wheelchairModel].attributeConn:Disconnect()
                for _, eff in ipairs(wheelchairEffects[wheelchairModel].effects) do
                    if eff.sparks.Parent then eff.sparks.Parent:Destroy() end
                    if eff.activeTrail then eff.activeTrail:Destroy() end
                end
                wheelchairEffects[wheelchairModel] = nil
            end
        end)
    }

    -- Add Trail Template
    local trailTemplate = Instance.new("Trail")
    trailTemplate.Name = "DriftTrail"
    trailTemplate.Lifetime = 5.0
    trailTemplate.MinLength = 0
    trailTemplate.FaceCamera = false
    trailTemplate.LightEmission = 0
    trailTemplate.LightInfluence = 1
    trailTemplate.Color = ColorSequence.new(Color3.new(0, 0, 0)) -- Pure Black
    trailTemplate.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),  -- Start: Ghostly
        NumberSequenceKeypoint.new(1, 1),    -- Fade out
    })
    trailTemplate.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    trailTemplate.Enabled = false
    
    for _, eff in ipairs(effects) do
        local a1 = Instance.new("Attachment")
        a1.Name = "DriftAtt1"
        a1.Position = eff.wheelPosOffset + Vector3.new(0, 0.1, 0.5)
        a1.Parent = eff.primary
        eff.a0 = eff.sparks.Parent
        eff.a1 = a1
        
        local activeTrail = trailTemplate:Clone()
        activeTrail.Attachment0 = eff.a0
        activeTrail.Attachment1 = eff.a1
        activeTrail.Parent = workspace.Terrain
        eff.activeTrail = activeTrail
        eff.wasGrounded = false
    end
end

RunService.RenderStepped:Connect(function()
    local now = tick()
    
    -- Cleanup destroyed wheelchairs
    for model, data in pairs(wheelchairEffects) do
        if not model or not model.Parent then
            if data.attributeConn then data.attributeConn:Disconnect() end
            wheelchairEffects[model] = nil
        end
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name:match("_Wheelchair$") then
            local playerName = obj.Name:gsub("_Wheelchair$", "")
            local player = Players:FindFirstChild(playerName)
            
            -- ONLY run replication for OTHER players. The local player's WheelchairController handles their own effects flawlessly.
            if player and player ~= localPlayer then
                if not wheelchairEffects[obj] then
                    setupDriftEffects(obj, player)
                end
                
                local hrp = obj.PrimaryPart or obj:FindFirstChild("Metal")
                if hrp then
                    local vel = hrp.AssemblyLinearVelocity
                    local speed = vel.Magnitude
                    local rightDot = hrp.CFrame.RightVector:Dot(vel.Unit)
                    
                    -- Drift conditions (Synced from server)
                    local isDrifting = obj:GetAttribute("IsDrifting") == true
                    
                    if wheelchairEffects[obj] then
                        for _, eff in ipairs(wheelchairEffects[obj].effects) do
                            -- PURE POSITION UPDATE (Fixes triangulation glitch)
                            local wPos = eff.primary.CFrame * eff.wheelPosOffset
                            local ray = workspace:Raycast(wPos, Vector3.new(0, -4, 0))
                            
                            -- Match WheelchairController local trail logic precisely
                            local floorY = ray and ray.Position.Y or (wPos.Y - 1.5)
                            local attachPos = Vector3.new(wPos.X, floorY + 0.1, wPos.Z)
                            
                            eff.a0.WorldPosition = attachPos - (hrp.CFrame.RightVector * 0.25)
                            
                            if ray then
                                eff.a1.WorldPosition = attachPos + (hrp.CFrame.RightVector * 0.25)
                                if eff.activeTrail then eff.activeTrail.Enabled = isDrifting end
                                eff.wasGrounded = true
                            else
                                if eff.activeTrail then eff.activeTrail.Enabled = false end
                                eff.wasGrounded = false
                            end
                            
                            -- SPARKS BURST
                            if isDrifting and eff.wasGrounded then
                                if now - eff.lastEmit > 0.08 then
                                    eff.lastEmit = now
                                    eff.sparks:Emit(20)
                                    eff.glow:Emit(5)
                                end
                            end
                        end
                    end
                    
                    -- WIND LINES (Procedural Motion Blur)
                    if speed > 15 then
                        local rateScale = math.clamp((speed - 15) / 45, 0, 1)
                        local spawnCount = math.floor(2 + (rateScale * 5))
                        for i = 1, spawnCount do
                            local sideOffset = (math.random() > 0.5) and 1.8 or -1.8
                            local rx = sideOffset + (math.random() * 0.2 - 0.1)
                            local ry = -2.9 + (math.random() * 0.3 - 0.15)
                            local rz = 1.3 + (math.random() * 1.5 - 0.75)
                            
                            local startPos = hrp.CFrame * Vector3.new(rx, ry, rz)
                            
                            local trail = Instance.new("Part")
                            trail.Name = "CustomWindBlur"
                            trail.Anchored = true
                            trail.CanCollide = false
                            trail.Massless = true
                            trail.Material = Enum.Material.Neon
                            trail.Color = Color3.fromRGB(200, 230, 255)
                            
                            local baseWidth = (0.02 + (math.random() * 0.05)) * math.max(0.1, rateScale)
                            trail.Size = Vector3.new(baseWidth, baseWidth, 0.2 + (rateScale * 0.8))
                            trail.Transparency = 1 - (rateScale * 0.8) 
                            trail.CFrame = CFrame.lookAt(startPos, startPos + hrp.CFrame.LookVector)
                            trail.Parent = workspace
                            
                            local TweenService = game:GetService("TweenService")
                            local tInfo = TweenInfo.new(0.25 + (math.random() * 0.1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                            local endPos = startPos - (hrp.CFrame.LookVector * (0.5 + (rateScale * 3)))
                            
                            local goal = {
                                CFrame = CFrame.lookAt(endPos, endPos + hrp.CFrame.LookVector),
                                Size = Vector3.new(0, 0, 0.2 + (rateScale * 2)),
                                Transparency = 1
                            }
                            
                            TweenService:Create(trail, tInfo, goal):Play()
                            game:GetService("Debris"):AddItem(trail, 0.4)
                        end
                    end
                end
            end
        end
    end
end)
