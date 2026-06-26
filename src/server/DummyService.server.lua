-- DummyService: Spawns a target dummy in a wheelchair with 100 HP and auto-respawn
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")

-- MINIGAME: Remote event for mounting
local MountMinigameEvent = ReplicatedStorage:WaitForChild("MountMinigameEvent", 10)

local WHEELCHAIR_NAME = "WheelchairRig"
local DUMMY_SPAWN = Vector3.new(20, 10, 0) -- Spawn position (adjust as needed)
local CRAWLER_SPAWN = Vector3.new(30, 2, 0) -- Spawn position for Crawler (Nearby)
local RESPAWN_DELAY = 8 -- Seconds before respawn after death (Allows time for chair stealing)
local CRAWL_ANIMATION_ID = "rbxassetid://134714611005099"

-- Reuse weldModel from WheelchairService pattern
local function weldModel(model, primaryPart)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Standard Physics for Dummy Chair (Pushable, doesn't slide forever)
            part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.5, 0, 1, 1)
            
            if part ~= primaryPart then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = primaryPart
                weld.Part1 = part
                weld.Parent = primaryPart
            end
            part.Anchored = false
        end
    end
end

local function createDummy()
    -- Build an R15-like character model
    local dummy = Instance.new("Model")
    dummy.Name = "TargetDummy"
    
    -- HumanoidRootPart (required for aim assist detection)
    local rootPart = Instance.new("Part")
    rootPart.Name = "HumanoidRootPart"
    rootPart.Size = Vector3.new(2, 2, 1)
    rootPart.Transparency = 1
    rootPart.CanCollide = false
    rootPart.Anchored = false
    rootPart.Parent = dummy
    
    -- Torso / UpperTorso
    local torso = Instance.new("Part")
    torso.Name = "UpperTorso"
    torso.Size = Vector3.new(2, 1.6, 1)
    torso.BrickColor = BrickColor.new("Bright blue")
    torso.Anchored = false
    torso.CanCollide = true
    torso.Parent = dummy
    
    local torsoWeld = Instance.new("WeldConstraint")
    torsoWeld.Part0 = rootPart
    torsoWeld.Part1 = torso
    torsoWeld.Parent = rootPart
    
    -- Lower Torso
    local lowerTorso = Instance.new("Part")
    lowerTorso.Name = "LowerTorso"
    lowerTorso.Size = Vector3.new(2, 0.4, 1)
    lowerTorso.CFrame = rootPart.CFrame * CFrame.new(0, -1, 0)
    lowerTorso.BrickColor = BrickColor.new("Dark stone grey")
    lowerTorso.Anchored = false
    lowerTorso.CanCollide = true
    lowerTorso.Parent = dummy
    
    local ltWeld = Instance.new("WeldConstraint")
    ltWeld.Part0 = rootPart
    ltWeld.Part1 = lowerTorso
    ltWeld.Parent = rootPart
    
    -- Head (for headshot detection)
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.2, 1.2, 1.2)
    head.CFrame = rootPart.CFrame * CFrame.new(0, 1.8, 0)
    head.BrickColor = BrickColor.new("Bright yellow")
    head.Anchored = false
    head.CanCollide = true
    head.Parent = dummy
    
    -- Head mesh to make it look round
    local headMesh = Instance.new("SpecialMesh")
    headMesh.MeshType = Enum.MeshType.Sphere
    headMesh.Parent = head
    
    local headWeld = Instance.new("WeldConstraint")
    headWeld.Part0 = rootPart
    headWeld.Part1 = head
    headWeld.Parent = rootPart
    
    -- Face decal
    local face = Instance.new("Decal")
    face.Name = "face"
    face.Texture = "rbxasset://textures/face.png"
    face.Face = Enum.NormalId.Front
    face.Parent = head
    
    -- Left Arm
    local leftArm = Instance.new("Part")
    leftArm.Name = "LeftUpperArm"
    leftArm.Size = Vector3.new(1, 1.5, 1)
    leftArm.CFrame = rootPart.CFrame * CFrame.new(-1.5, 0, 0)
    leftArm.BrickColor = BrickColor.new("Bright yellow")
    leftArm.Anchored = false
    leftArm.CanCollide = true
    leftArm.Parent = dummy
    
    local laWeld = Instance.new("WeldConstraint")
    laWeld.Part0 = rootPart
    laWeld.Part1 = leftArm
    laWeld.Parent = rootPart
    
    -- Right Arm
    local rightArm = Instance.new("Part")
    rightArm.Name = "RightUpperArm"
    rightArm.Size = Vector3.new(1, 1.5, 1)
    rightArm.CFrame = rootPart.CFrame * CFrame.new(1.5, 0, 0)
    rightArm.BrickColor = BrickColor.new("Bright yellow")
    rightArm.Anchored = false
    rightArm.CanCollide = true
    rightArm.Parent = dummy
    
    local raWeld = Instance.new("WeldConstraint")
    raWeld.Part0 = rootPart
    raWeld.Part1 = rightArm
    raWeld.Parent = rootPart
    
    -- Left Leg
    local leftLeg = Instance.new("Part")
    leftLeg.Name = "LeftUpperLeg"
    leftLeg.Size = Vector3.new(1, 1.5, 1)
    leftLeg.CFrame = rootPart.CFrame * CFrame.new(-0.5, -2, 0)
    leftLeg.BrickColor = BrickColor.new("Dark stone grey")
    leftLeg.Anchored = false
    leftLeg.CanCollide = true
    leftLeg.Parent = dummy
    
    local llWeld = Instance.new("WeldConstraint")
    llWeld.Part0 = rootPart
    llWeld.Part1 = leftLeg
    llWeld.Parent = rootPart
    
    -- Right Leg
    local rightLeg = Instance.new("Part")
    rightLeg.Name = "RightUpperLeg"
    rightLeg.Size = Vector3.new(1, 1.5, 1)
    rightLeg.CFrame = rootPart.CFrame * CFrame.new(0.5, -2, 0)
    rightLeg.BrickColor = BrickColor.new("Dark stone grey")
    rightLeg.Anchored = false
    rightLeg.CanCollide = true
    rightLeg.Parent = dummy
    
    local rlWeld = Instance.new("WeldConstraint")
    rlWeld.Part0 = rootPart
    rlWeld.Part1 = rightLeg
    rlWeld.Parent = rootPart
    
    -- Humanoid (100 HP)
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = dummy
    
    -- Set PrimaryPart (required for aim assist)
    dummy.PrimaryPart = rootPart
    
    return dummy
end

-- Helper: Create/Find wheelchair for a dummy
local function ensureWheelchair(dummy)
    -- Check if already has a specific chair linked
    local existingChair = dummy:FindFirstChild("LinkedChair")
    if existingChair and existingChair.Value then return existingChair.Value end
    
    -- Look for a chair nearby named properly
    -- (Simple heuristic: closest chair within 5 studs)
    -- For now, we'll just create one if missing.
    
    local rigTemplate = ServerStorage:FindFirstChild(WHEELCHAIR_NAME) or game:GetService("ReplicatedStorage"):FindFirstChild(WHEELCHAIR_NAME)
    
    if not rigTemplate then 
        warn("DummyService: WheelchairRig not found in ServerStorage OR ReplicatedStorage!")
        return nil 
    end
    
    local chair = rigTemplate:Clone()
    chair.Name = dummy.Name .. "_Wheelchair"
    
    -- Position it so the dummy aligns with the seat (Offset Down)
    local root = dummy:FindFirstChild("HumanoidRootPart")
    if root then
        -- Lower the chair relative to the standing dummy so the dummy "falls" into the seat or spawns correctly
        -- Standard R15 HipHeight is ~2. Sit height is lower.
        chair:PivotTo(root.CFrame * CFrame.new(0, -1.5, 0))
    end
    
    chair.Parent = workspace
    print("DummyService: Spawning chair for", dummy.Name)
    
    -- Link them
    local link = Instance.new("ObjectValue")
    link.Name = "LinkedChair"
    link.Value = chair
    link.Parent = dummy
    
    -- Physics Setup
    for _, part in ipairs(chair:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Pushable physics
            part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.5, 0, 1, 1)
            part.CollisionGroup = "Wheelchair"
            game:GetService("CollectionService"):AddTag(part, "IgnoredWheelchairPart") -- FIX: Add Tag
        end
    end
    
    local vehicleSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
    
    -- Helper: Physics Setup for ANY occupant (Owner or Thief)
    local function setupOccupantPhysics(occupantHum)
         if not occupantHum then return end
         
         local player = game.Players:GetPlayerFromCharacter(occupantHum.Parent)
         local prim = chair.PrimaryPart or chair:FindFirstChild("PrimaryPart")
         
         -- 1. Unanchor & Network Ownership
         if prim then 
             prim.Anchored = false 
             if player then
                 prim:SetNetworkOwner(player)
                 print("DummyService: Network Owner set to", player.Name)
             else
                 -- If Dummy, server owns it (nil)
                 prim:SetNetworkOwner(nil)
             end
         end
         
         -- 2. NoCollision Constraints (Prevent self-collision with chair)
         local char = occupantHum.Parent
         if char then
             for _, charPart in pairs(char:GetDescendants()) do
                 if charPart:IsA("BasePart") then
                     for _, chairPart in pairs(chair:GetDescendants()) do
                         if chairPart:IsA("BasePart") then
                             local ncc = Instance.new("NoCollisionConstraint")
                             ncc.Name = "SeatNoCollision_"..char.Name
                             ncc.Part0 = charPart; ncc.Part1 = chairPart; ncc.Parent = chairPart
                         end
                     end
                 end
             end
         end
         
         -- 3. Disable Jump
         occupantHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    end

    local vehicleSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
    
     -- FIX: CLICK E TO SIT (User Request)
    if vehicleSeat then
        vehicleSeat.Disabled = false -- Enable Driving Controls
        vehicleSeat.CanTouch = false -- Disable Touch-to-Sit (Require Prompt)
        local prompt = Instance.new("ProximityPrompt")
        prompt.ObjectText = "Wheelchair"
        prompt.ActionText = "Sit"
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9 -- Reduced from 12 (User Request)
        prompt.Parent = vehicleSeat
        
        prompt.Triggered:Connect(function(playerWhoTriggered)
            -- Only sit if empty
            if not vehicleSeat.Occupant then
                local hum = playerWhoTriggered.Character and playerWhoTriggered.Character:FindFirstChild("Humanoid")
                if hum then 
                    -- FIX: No sitting while DEAD or Ragdolled (Physics State)
                    -- Removed PlatformStand check to allow Crawling entry
                    if hum.Health <= 0 then return end
                    if hum:GetState() == Enum.HumanoidStateType.Physics then return end
                    
                    -- MINIGAME: Fire event instead of direct sit
                    if MountMinigameEvent then
                        vehicleSeat:SetAttribute("MinigameActive", true) -- STOP DESPAWN (Reservation)
                        MountMinigameEvent:FireClient(playerWhoTriggered, vehicleSeat)
                    else
                        vehicleSeat:Sit(hum) -- Fallback
                    end
                end
            end
        end)
        
        -- FIX: Hide Prompt when Occupied
        vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
            prompt.Enabled = (vehicleSeat.Occupant == nil)
            
            -- Trigger physics setup when someone sits
            if vehicleSeat.Occupant then
                setupOccupantPhysics(vehicleSeat.Occupant)
            end
        end)
        
        -- FORCE DUMMY SIT IMMEDIATELY
        local dummyHum = dummy:FindFirstChild("Humanoid")
        if dummyHum then
            vehicleSeat:Sit(dummyHum)
            -- Manually trigger setup just in case signal misses
            setupOccupantPhysics(dummyHum)
        end
    end
    
    local primaryPart = chair.PrimaryPart or vehicleSeat
    
    if primaryPart then
        weldModel(chair, primaryPart)
        
        -- === PHYSICS COMPONENTS (Replicated from WheelchairService) ===
        -- Without these, the Client Controller cannot drive the chair!
        
        -- Center of Mass & Base Attachments
        local baseAtt = Instance.new("Attachment")
        baseAtt.Name = "BaseAttachment"
        baseAtt.Position = Vector3.new(0, -3.5, 0)
        baseAtt.Parent = primaryPart
        
        local comAtt = Instance.new("Attachment")
        comAtt.Name = "COM_Attachment"
        comAtt.Position = Vector3.new(0, -3.0, 0)
        comAtt.Parent = primaryPart
        
        -- Suspension (Visual/Physics placeholders for Controller)
        local corners = {
            FL = Vector3.new(-1.5, -1, -1.5), FR = Vector3.new( 1.5, -1, -1.5),
            RL = Vector3.new(-1.5, -1,  1.5), RR = Vector3.new( 1.5, -1,  1.5)
        }
        for name, offset in pairs(corners) do
            local att = Instance.new("Attachment")
            att.Name = name .. "_Attachment"
            att.Position = offset
            att.Parent = primaryPart
            local vf = Instance.new("VectorForce")
            vf.Name = name .. "_SuspensionForce"
            vf.Attachment0 = att
            vf.Force = Vector3.zero
            vf.RelativeTo = Enum.ActuatorRelativeTo.World
            vf.Parent = primaryPart
        end
        
        -- Propulsion
        local moveIso = Instance.new("LinearVelocity")
        moveIso.Name = "MoveVelocity"
        moveIso.Attachment0 = baseAtt
        moveIso.MaxForce = 0
        moveIso.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
        moveIso.LineDirection = Vector3.new(0, 0, -1)
        moveIso.RelativeTo = Enum.ActuatorRelativeTo.World
        moveIso.Parent = primaryPart
        
        -- Turning
        local turnIso = Instance.new("AngularVelocity")
        turnIso.Name = "TurnVelocity"
        turnIso.Attachment0 = comAtt
        turnIso.MaxTorque = 0
        turnIso.RelativeTo = Enum.ActuatorRelativeTo.World
        turnIso.AngularVelocity = Vector3.zero
        turnIso.Parent = primaryPart
        
        -- Drifting & Drag
        local sideForce = Instance.new("VectorForce")
        sideForce.Name = "SideForce"
        sideForce.Attachment0 = comAtt
        sideForce.RelativeTo = Enum.ActuatorRelativeTo.World
        sideForce.Force = Vector3.zero
        sideForce.Parent = primaryPart
        
        local dragForce = Instance.new("VectorForce")
        dragForce.Name = "DragForce"
        dragForce.Attachment0 = comAtt
        dragForce.RelativeTo = Enum.ActuatorRelativeTo.World
        dragForce.Force = Vector3.zero
        dragForce.Parent = primaryPart
        
        -- Stabilizer
        local stabilizer = Instance.new("AlignOrientation")
        stabilizer.Name = "Stabilizer"
        stabilizer.Mode = Enum.OrientationAlignmentMode.OneAttachment
        stabilizer.Attachment0 = comAtt
        comAtt.Axis = Vector3.new(0, 1, 0)
        stabilizer.AlignType = Enum.AlignType.PrimaryAxisParallel
        stabilizer.PrimaryAxis = Vector3.yAxis
        stabilizer.MaxTorque = 0 -- Controller sets this
        stabilizer.MaxAngularVelocity = 10
        stabilizer.Responsiveness = 20
        stabilizer.Parent = primaryPart
    end

    return chair
end



local function hookDummyRespawn(dummy)
    local root = dummy:WaitForChild("HumanoidRootPart", 5)
    if not root then return end
    
    -- Save spawn location
    local spawnCF = root.CFrame
    local isCrawler = dummy:GetAttribute("IsCrawler") -- Check if special dummy
    
    local hum = dummy:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        print("DummyService: Dummy died. Respawning...")
        
        -- FIX: Smart "Abandonment" Logic for Dummies
        local link = dummy:FindFirstChild("LinkedChair")
        local brokenChair = link and link.Value 
        
        if brokenChair and brokenChair.Parent then
             local seat = brokenChair:FindFirstChildWhichIsA("VehicleSeat", true)
             if seat then
                 local abandonmentTask = nil
                 
                 local function startCleanupTimer()
                     if abandonmentTask then task.cancel(abandonmentTask) end
                     abandonmentTask = task.delay(5, function()
                         -- ONLY DESTROY if no occupant AND no minigame in progress
                         local isMinigameActive = seat:GetAttribute("MinigameActive")
                         if brokenChair and brokenChair.Parent and not seat.Occupant and not isMinigameActive then
                             brokenChair:Destroy()
                         end
                     end)
                 end
                 
                 -- 1. Start timer if empty (dummy is dead/gone)
                 if not seat.Occupant then startCleanupTimer() end
                 
                 -- Helper: Physics Setup for ANY occupant (Owner or Thief)
                 local function setupOccupantPhysics(chair, occupantHum)
                    if not chair or not occupantHum then return end
                    
                    local player = game.Players:GetPlayerFromCharacter(occupantHum.Parent)
                    local prim = chair.PrimaryPart or chair:FindFirstChild("PrimaryPart")
                    
                    -- 1. Unanchor & Network Ownership
                    if prim then 
                        prim.Anchored = false 
                        if player then
                            prim:SetNetworkOwner(player)
                        end
                    end
                    
                    -- 2. NoCollision Constraints (Prevent self-collision with chair)
                    local char = occupantHum.Parent
                    if char then
                        for _, charPart in pairs(char:GetDescendants()) do
                            if charPart:IsA("BasePart") then
                                for _, chairPart in pairs(chair:GetDescendants()) do
                                    if chairPart:IsA("BasePart") then
                                        local ncc = Instance.new("NoCollisionConstraint")
                                        ncc.Name = "SeatNoCollision_Stolen"
                                        ncc.Part0 = charPart; ncc.Part1 = chairPart; ncc.Parent = chairPart
                                    end
                                end
                            end
                        end
                    end
                    
                    -- 3. Disable Jump State
                    occupantHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                end

                 -- 2. Monitor for theft/abandonment
                 seat:GetPropertyChangedSignal("Occupant"):Connect(function()
                     if not brokenChair or not brokenChair.Parent then return end
                     
                     if seat.Occupant then
                         -- Stolen! Cancel cleanup
                         if abandonmentTask then task.cancel(abandonmentTask) end
                         print("DummyService: Chair stolen! Cleanup cancelled.")
                         
                     else
                         -- Abandoned. Restart cleanup.
                         startCleanupTimer()
                     end
                 end)
             else
                 -- No seat found, destroy immediately (fallback)
                 task.delay(5, function() if brokenChair then brokenChair:Destroy() end end)
             end
        end
    -- REMOVED PREMATURE CLOSURES AND GARBAGE

        
        task.wait(1)
        dummy:Destroy()
        
        task.wait(RESPAWN_DELAY - 1)
        
        -- Spawn NEW dummy at saved location
        local newDummy = createDummy()
        newDummy.Name = isCrawler and "CrawlerDummy" or "TargetDummy"
        newDummy:PivotTo(spawnCF)
        newDummy.Parent = workspace
        
        if isCrawler then
             setupCrawler(newDummy)
        else
             ensureWheelchair(newDummy)
        end
        hookDummyRespawn(newDummy)
    end)
end

-- HELPER: Setup Crawler (Dismounted / Flat Physics)
function setupCrawler(dummy)
    dummy:SetAttribute("IsCrawler", true)
    local hum = dummy:WaitForChild("Humanoid")
    local root = dummy:WaitForChild("HumanoidRootPart")
    
    -- 1. Stats and State
    hum.WalkSpeed = 0 -- Disable walking (He is a static crawler for now, or use MoveTo if needed)
    hum.JumpPower = 0
    hum.PlatformStand = true -- Disable "Stand Up" force
    
    -- 2. "Pancake" Hitbox (Low Profile)
    -- Resize RootPart to be flat and wide
    root.Size = Vector3.new(4, 1, 4)
    root.CanCollide = true
    
    -- 3. Lay Flat (Coordinate Frame)
    -- Rotate 90 degrees forward to lie on face
    -- Move up slightly to prevent floor clipping during resize
    local currentCF = root.CFrame
    local flatCF = currentCF * CFrame.Angles(math.rad(90), 0, 0) + Vector3.new(0, 2, 0)
    dummy:PivotTo(flatCF)
    
    -- 4. Physics Properties
    -- High Friction to stop "Sliding" (User reported sliding)
    -- CollisionGroup "RagdollCharacter" (Pass through wheelchair)
    for _, part in ipairs(dummy:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "RagdollCharacter"
            part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.0, 0.5, 100, 100) -- High Friction/Density
        end
    end
    
    print("DummyService: Spawning Crawler (Flat Physics & RagdollGroup)", dummy.Name)
end

-- Startup: Logic
local function initService()
    -- 1. Scan for existing Edit-Mode dummies
    local existing = 0
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "TargetDummy" and child:FindFirstChild("Humanoid") then
            existing = existing + 1
            print("DummyService: Found existing dummy:", child)
            ensureWheelchair(child)
            hookDummyRespawn(child)
        end
    end
    
    -- 2. If explicit spawn exists, always spawn one there regardless? 
    -- User said "Make it appear in workspace", implying they might DELETE the spawn part if they have the dummy.
    -- Logic: If "DummySpawn" part exists, spawn one there.
    local spawnPart = workspace:FindFirstChild("DummySpawn")
    if spawnPart then
         -- Check if there's already one AT the spawn?
         -- Nah, just spawn one if spawn part specifically exists.
         local d = createDummy()
         d:PivotTo(spawnPart.CFrame)
         d.Parent = workspace
         ensureWheelchair(d)
         hookDummyRespawn(d)
    elseif existing == 0 then
        -- Default fallback if absolutely nothing exists
        local d = createDummy()
        d:PivotTo(CFrame.new(DUMMY_SPAWN))
        d.Parent = workspace
        ensureWheelchair(d)
        hookDummyRespawn(d)
    end
end

-- Run Init
task.delay(1, function()
    initService()
    
    -- ALWAYS SPAWN ONE CRAWLER for testing
    local crawler = createDummy()
    crawler.Name = "CrawlerDummy"
    crawler:PivotTo(CFrame.new(CRAWLER_SPAWN))
    crawler.Parent = workspace
    setupCrawler(crawler)
    hookDummyRespawn(crawler)
end)


