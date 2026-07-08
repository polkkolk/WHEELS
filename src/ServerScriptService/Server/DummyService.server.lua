-- DummyService: Spawns a target dummy in a wheelchair with 100 HP and auto-respawn
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")



local WHEELCHAIR_NAME = "WheelchairRig"
local DUMMY_SPAWN = Vector3.new(20, 10, 0) -- Spawn position (adjust as needed)
local CRAWLER_SPAWN = Vector3.new(30, 2, 0) -- Spawn position for Crawler (Nearby)
local RESPAWN_DELAY = 8 -- Seconds before respawn after death (Allows time for chair stealing)
local CRAWL_ANIMATION_ID = "rbxassetid://90172706246576"
-- HELPER: Create a proper R15 block rig (used universally by Crawler and Target dummies)
local function createBlockyRig()
    local desc = Instance.new("HumanoidDescription")
    -- Default blocky look
    desc.HeadColor = Color3.fromRGB(245, 205, 48)
    desc.TorsoColor = Color3.fromRGB(13, 105, 172)
    desc.LeftArmColor = Color3.fromRGB(245, 205, 48)
    desc.RightArmColor = Color3.fromRGB(245, 205, 48)
    desc.LeftLegColor = Color3.fromRGB(164, 189, 71)
    desc.RightLegColor = Color3.fromRGB(164, 189, 71)
    
    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    
    if ok and model then
        local root = model:WaitForChild("HumanoidRootPart")
        local upperTorso = model:WaitForChild("UpperTorso")
        local head = model:WaitForChild("Head")
        
        -- Create a custom, solid hitbox for the Torso
        local torsoHitbox = Instance.new("Part")
        torsoHitbox.Name = "TorsoHitbox"
        torsoHitbox.Size = Vector3.new(4, 3, 1.5) -- Wide enough to cover shoulders/arms
        torsoHitbox.CFrame = upperTorso.CFrame * CFrame.new(0, -0.5, 0)
        torsoHitbox.Transparency = 1
        torsoHitbox.CanCollide = false
        torsoHitbox.Massless = true
        
        local torsoWeld = Instance.new("WeldConstraint")
        torsoWeld.Part0 = upperTorso
        torsoWeld.Part1 = torsoHitbox
        torsoWeld.Parent = torsoHitbox
        torsoHitbox.Parent = model
        
        -- Create a custom, solid hitbox for the Head
        local headHitbox = Instance.new("Part")
        headHitbox.Name = "HeadHitbox" -- Use HeadHitbox so Roblox engine doesn't replace the visual head
        headHitbox.Size = Vector3.new(1.2, 1.2, 1.2)
        headHitbox.CFrame = head.CFrame
        headHitbox.Transparency = 1
        headHitbox.CanCollide = false
        headHitbox.Massless = true
        
        local headWeld = Instance.new("WeldConstraint")
        headWeld.Part0 = head
        headWeld.Part1 = headHitbox
        headWeld.Parent = headHitbox
        headHitbox.Parent = model
        
        return model
    else
        warn("DummyService: Failed to create R15 rig!")
        local fallback = Instance.new("Model")
        local root = Instance.new("Part", fallback)
        root.Name = "HumanoidRootPart"
        fallback.PrimaryPart = root
        Instance.new("Humanoid", fallback)
        return fallback
    end
end

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

-- (createDummy has been removed in favor of createBlockyRig)


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
        prompt.HoldDuration = 1 -- Instant mount for stolen chairs (User Request)
        prompt.Style = Enum.ProximityPromptStyle.Custom
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
                    
                    vehicleSeat:Sit(hum)
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
            task.spawn(function()
                -- Wait for physics to settle
                task.wait(0.5)
                if dummy and dummyHum and vehicleSeat and vehicleSeat.Parent then
                    vehicleSeat:Sit(dummyHum)
                    print("DummyService: Seated", dummy.Name)
                    setupOccupantPhysics(dummyHum)
                    
                    -- Play standard R15 sitting animation manually so it bends its legs!
                    local animator = dummyHum:FindFirstChildOfClass("Animator")
                    if not animator then
                        animator = Instance.new("Animator")
                        animator.Parent = dummyHum
                    end
                    
                    local sitAnim = Instance.new("Animation")
                    sitAnim.AnimationId = "rbxassetid://2506281703" -- Roblox Default R15 Sit
                    local sitTrack = animator:LoadAnimation(sitAnim)
                    sitTrack.Priority = Enum.AnimationPriority.Idle
                    sitTrack:Play()
                end
            end)
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



local function hookDummyRespawn(dummy, originalSpawnCF)
    local root = dummy:WaitForChild("HumanoidRootPart", 5)
    if not root then return end
    
    -- Determine if this is a crawler before deciding how to save the CF
    local isCrawler = dummy:GetAttribute("IsCrawler")
    
    -- Save spawn location (ONLY IF WE DON'T ALREADY HAVE IT)
    local spawnCF = originalSpawnCF
    if not spawnCF then
        if isCrawler then
            -- Initial spawn is level
            local pos = root.Position
            spawnCF = CFrame.new(pos.X, pos.Y, pos.Z)
        else
            spawnCF = root.CFrame
        end
    end
    
    local hum = dummy:WaitForChild("Humanoid")
    local hasRespawned = false -- Prevent double-fire from Died + HealthChanged
    
    local function doRespawn()
        if hasRespawned then return end
        hasRespawned = true
        print("DummyService: Dummy respawn triggered for", dummy.Name)
        
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
        
        local delayTime = isCrawler and 5 or RESPAWN_DELAY
        task.wait(delayTime - 1)
        
        -- Spawn NEW dummy at saved location
        local newDummy = createBlockyRig()
        newDummy.Name = isCrawler and "CrawlerDummy" or "TargetDummy"
        newDummy:PivotTo(spawnCF)
        newDummy.Parent = workspace
        
        if isCrawler then
             setupCrawler(newDummy)
        else
             ensureWheelchair(newDummy)
        end
        hookDummyRespawn(newDummy, spawnCF)
    end
    
    hum.Died:Connect(function()
        print("DummyService: Died event fired for", dummy.Name)
        doRespawn()
    end)
    
    -- BACKUP: HealthChanged catches cases where Died doesn't fire
    -- (known issue with PlatformStand=true / anchored Humanoids)
    hum.HealthChanged:Connect(function(newHealth)
        if newHealth <= 0 then
            print("DummyService: HealthChanged<=0 backup for", dummy.Name)
            doRespawn()
        end
    end)
end


-- HELPER: Setup Crawler (Animated / Flat on Ground)
function setupCrawler(dummy)
    dummy:SetAttribute("IsCrawler", true)
    local hum = dummy:WaitForChild("Humanoid")
    local root = dummy:WaitForChild("HumanoidRootPart")
    
    -- 1. Stats and State
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    hum.PlatformStand = true
    hum.HipHeight = 0
    hum.AutoRotate = false
    
    -- 2. "Pancake" Hitbox (Low Profile)
    root.Size = Vector3.new(4, 1, 4)
    root.CanCollide = true
    
    -- 3. Position: Keep root UPRIGHT — the animation handles the crawling pose.
    --    Pre-rotating the root conflicts with the animation's own joint transforms.
    local pos = root.Position
    local lookFlat = root.CFrame.LookVector
    local yaw = math.atan2(-lookFlat.X, -lookFlat.Z) + math.pi -- Add 180 degrees to face inward
    local flatCF = CFrame.new(pos.X, pos.Y, pos.Z)
        * CFrame.Angles(0, yaw, 0)
    dummy:PivotTo(flatCF)
    
    -- 4. Anchor root so physics can't fight the pose
    root.Anchored = true
    
    -- 5. Load and play crawling animation
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    
    local anim = Instance.new("Animation")
    anim.AnimationId = CRAWL_ANIMATION_ID
    local track = animator:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:Play()
    track:AdjustSpeed(0) -- Freeze at first frame (static crawling pose)
    
    -- 6. Physics Properties
    for _, part in ipairs(dummy:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "RagdollCharacter"
            part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.0, 0.5, 100, 100)
        end
    end
    
    print("DummyService: Spawning Crawler (R15 Animated Flat)", dummy.Name)
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
         local d = createBlockyRig()
         d.Name = "TargetDummy"
         d:PivotTo(spawnPart.CFrame)
         d.Parent = workspace
         ensureWheelchair(d)
         hookDummyRespawn(d)
    elseif existing == 0 then
        -- Default fallback if absolutely nothing exists
        local d = createBlockyRig()
        d.Name = "TargetDummy"
        d:PivotTo(CFrame.new(DUMMY_SPAWN))
        d.Parent = workspace
        ensureWheelchair(d)
        hookDummyRespawn(d)
    end
    -- 3. Find and bind all CrawlerBrickSpawnDummy locations
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "CrawlerBrickSpawnDummy" and obj:IsA("BasePart") then
            obj.Transparency = 1 -- Hide the brick spawn point
            obj.CanCollide = false
            
            local crawler = createBlockyRig()
            crawler.Name = "CrawlerDummy"
            
            -- Spawn slightly above the brick to prevent ground clipping
            crawler:PivotTo(obj.CFrame + Vector3.new(0, 1, 0))
            crawler.Parent = workspace
            
            setupCrawler(crawler)
            hookDummyRespawn(crawler)
        end
    end
end

-- Run Init
task.delay(1, function()
    initService()
    
    -- ALWAYS SPAWN ONE CRAWLER for testing (fallback)
    local crawler = createBlockyRig()
    crawler.Name = "CrawlerDummy"
    crawler:PivotTo(CFrame.new(CRAWLER_SPAWN))
    crawler.Parent = workspace
    setupCrawler(crawler)
    hookDummyRespawn(crawler)
end)


