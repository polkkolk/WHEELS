local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local WORLD_UP = Vector3.yAxis
local function smoothstep(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Configuration
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WheelchairConfig"))

-- Disable native Shift Lock so drifting doesn't mess up camera
-- Players.LocalPlayer.DevEnableMouseLock = false
local CrashEjectEvent = ReplicatedStorage:WaitForChild("CrashEjectEvent", 10)
local DRIFT_SOUND_ID = "rbxassetid://9061633595" -- Metal Scrape Loop

local player = Players.LocalPlayer

local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- Physics Variables
local suspensionForces = {} -- Map[Name] -> VectorForce
local moveForce = nil
local turnForce = nil
local sideForce = nil
local dragForce = nil
local stabilizer = nil
local currentSpeed = 0
local isDrifting = false
local driftTime = 0
local lastChairModel = nil -- SIM 17.2: Cache to restore friction on dismount

-- Sim 13.0: Script-Local State (Replaces Globals to prevent leakage)
local driftPowerRamp = 0
local momentumReserve = Config.MaxSpeed
local steadyHybrid = 0
local steadySteer = 0
local currentSideFriction = 0
local massPrinted = false
local wasSeated = false -- SIM 29.0: Track if we were previously seated
local tiltGraceTimer = 0 -- SIM 30.0: Ignore tilt dismount briefly after sit
local airSpinRate = 0 -- SIM 40.1: Captured spin rate for air momentum
local lastLateralVel = Vector3.zero -- SIM 44.0: Previous lateral velocity for accel calc
local tiltEjectTimer = 0 -- SIM 44.0: Time-over-threshold for fair ejection
local momentumLockTimer = 0 -- SIM 45.0: Momentum preservation window
local lockedDriveDir = nil -- SIM 45.0: Captured drive direction at takeoff
local driftCarryTimer = 0 -- SIM 45.0: Persist drift grip across airtime
local lastVerticalVel = 0 -- SIM 46.0: Previous frame vertical velocity for bump detection
local bumpCooldown = 0 -- SIM 46.0: Prevent double-trigger on bumps

-- Drift Trail System (uses Roblox Trail objects for continuous rendering)
local TRAIL_LIFETIME = 5.0
local driftTrails = {} -- Will hold Trail instances for RL and RR
local trailsSetUp = false
local currentSeat = nil -- Track active seat to prevent re-init loops
local chairModel = nil -- File scope for Visual Loop access
local driftSound = nil -- Sound Instance

player:GetAttributeChangedSignal("Shop_Equipped_DriftVFX"):Connect(function()
    for _, trail in ipairs(driftTrails) do
        if trail.a0 then trail.a0:Destroy() end
        if trail.a1 then trail.a1:Destroy() end
        if trail.trailTemplate then trail.trailTemplate:Destroy() end
    end
    driftTrails = {}
    trailsSetUp = false
end)
local animTracks = {} -- Map[Name] -> AnimationTrack
local animWeights = {Forward = 0, Reverse = 0, Idle = 0} -- Manual weight tracking

-- SIM 46.0: Crash eject function (unified ejection with ragdoll fling)
local function crashEject(seat, rootPart, vel, speed, fwd, right, reason)
    if not CrashEjectEvent then 
        if seat then seat:Sit(nil) end
        return
    end
    
    -- TELEPORT GUARD: suppress crash eject during teleport
    -- The attribute may not have replicated from the server yet,
    -- but this catches subsequent frames and the fallback chair lookup
    if seat and seat:GetAttribute("_Teleporting") then return end
    local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if chair then
        local vSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
        if vSeat and vSeat:GetAttribute("_Teleporting") then return end
    end
    
    -- RACE CONDITION FIX: Ignore crashes if we are within 35 studs of the ChallengeGateway.
    -- The portal frame (Bottom/Union) acts as a solid wall. Hitting it triggers a local crash,
    -- but the server will ignore the crash because it detects the teleport trigger at the exact same time.
    -- If we let the client proceed with crashEject, it destroys Motor6Ds locally, resulting in a glitched character.
    local gateway = workspace:FindFirstChild("ChallengeGateway")
    if gateway then
        local trigger = gateway:FindFirstChild("Trigger")
        if trigger and rootPart then
            local dist = (rootPart.Position - trigger.Position).Magnitude
            if dist < 35 then
                print("Crash eject blocked locally - near Challenge Gateway! Dist:", math.floor(dist))
                return
            end
        end
    end
    
    local flatVel = Vector3.new(vel.X, 0, vel.Z)
    
    -- Compute desired VELOCITY CHANGE (not impulse — server applies mass)
    local flingVelocity
    local speedFactor = math.clamp(speed / 50, 0.3, 1.5)
    
    if reason == "wall" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = -flingDir * 6 * speedFactor + Vector3.new(0, 8 * speedFactor, 0)
    elseif reason == "tilt" then
        local sideDir = right * (math.random() > 0.5 and 1 or -1)
        flingVelocity = sideDir * 5 * speedFactor + Vector3.new(0, 4 * speedFactor, 0)
    elseif reason == "velocity" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = -flingDir * 6 * speedFactor + Vector3.new(0, 8 * speedFactor, 0)
    else
        flingVelocity = Vector3.new(0, 4, 0)
    end
    
    -- STABILIZE CAMERA immediately — prevents jitter when seat ejects
    -- Use rootPart (not humanoid) — during PlatformStand the humanoid can float
    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = rootPart
    end

    -- Zero all wheelchair drive constraints BEFORE eject
    -- Prevents the chair from driving itself after player leaves
    if moveForce then moveForce.MaxForce = 0 end
    if turnForce then turnForce.MaxTorque = 0 end
    if sideForce then sideForce.Force = Vector3.zero end
    if dragForce then dragForce.Force = Vector3.zero end
    currentSpeed = 0
    
    -- Stop animations (they force limbs into floor)
    if humanoid then
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            track:Stop()
        end
    end
    
    -- CLIENT-SIDE collision enforcement (Roblox Humanoid resets R15 limbs every frame)
    -- Runs during ragdoll ONLY — auto-disconnects when PlatformStand goes true→false (recovery)
    -- Must track state because PlatformStand isn't true yet when this loop starts (network delay)
    local collisionLoop
    local ragdollActivated = false  -- Has PlatformStand been true at least once?
    collisionLoop = RunService.Stepped:Connect(function()
        if not humanoid then
            if collisionLoop then collisionLoop:Disconnect() end
            return
        end
        
        -- Track when ragdoll actually activates (server sets PlatformStand=true)
        if humanoid.PlatformStand then
            ragdollActivated = true
            -- During ragdoll: camera follows rootPart (physics-driven) not the floating humanoid
            local cam = workspace.CurrentCamera
            if cam then cam.CameraSubject = rootPart end
        end
        
        -- Only disconnect AFTER ragdoll was active and PlatformStand went back to false
        if ragdollActivated and not humanoid.PlatformStand then
            print("Recovery Complete - Starting Crawl System")
            ragdollActivated = false
            
            -- Motor6Ds are restored automatically via Server replication of clones
            
            -- FIX: Re-enable Prompts so we can sit again!
            -- Only if we aren't already seated (extra safety)
            if not humanoid.SeatPart then
                game:GetService("ProximityPromptService").Enabled = true
            end
            
            -- 1. DISABLE DEFAULT ANIMATIONS
            local animScript = character:FindFirstChild("Animate")
            if animScript then animScript.Disabled = true end
            
            for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do t:Stop() end
            
            -- 2. SETUP CRAWL ANIM & SPEED
            -- Disconnect the old collisionLoop to prevent re-entry
            if collisionLoop then collisionLoop:Disconnect(); collisionLoop = nil end
            
            -- DO NOT create a collision enforcement loop!
            -- Forcing all limbs CanCollide=true causes arms/torso to physically
            -- collide with the floor during the crawl animation, flinging the
            -- character at 60-80 studs/sec. Let the Humanoid manage its own
            -- limb collisions — it naturally sets legs collidable for ground contact.
            
            -- Switch camera back to humanoid
            local cam = workspace.CurrentCamera
            if cam then
                cam.CameraType = Enum.CameraType.Custom
                cam.CameraSubject = humanoid
            end
            humanoid.PlatformStand = false
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            humanoid.WalkSpeed = 4
            humanoid.HipHeight = 0.5
            humanoid.AutoRotate = true
            
            -- 1. Disable Freefall so the Humanoid doesn't disable AutoRotate
            -- 2. Disable Climbing to prevent the engine from flipping the body upside down against walls
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
            
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://90172706246576"
            local track = humanoid:LoadAnimation(anim)
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = true
            track:Play()
            track:AdjustSpeed(1)
            
            -- 2b. CUSTOM PHYSICS DRIVER (NO FRICTION, NO FLINGS)
            -- The Humanoid strictly refuses to walk if feet aren't touching the ground.
            -- Instead of fighting collisions, we completely bypass the native walking engine!
            -- We use LinearVelocity for perfect X/Z movement and AlignOrientation for turning.
            local crawlAtt = rootPart:FindFirstChild("CrawlAttachment")
            if not crawlAtt then
                crawlAtt = Instance.new("Attachment")
                crawlAtt.Name = "CrawlAttachment"
                crawlAtt.Parent = rootPart
            end
            
            local crawlMover = rootPart:FindFirstChild("CrawlMover")
            if not crawlMover then
                crawlMover = Instance.new("LinearVelocity")
                crawlMover.Name = "CrawlMover"
                crawlMover.Attachment0 = crawlAtt
                crawlMover.MaxForce = 100000 
                crawlMover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                crawlMover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
                crawlMover.MaxAxesForce = Vector3.new(100000, 0, 100000) -- Only force X/Z movement (keep Y gravity)
                crawlMover.RelativeTo = Enum.ActuatorRelativeTo.World
                crawlMover.Parent = rootPart
            end
            
            local crawlTorque = rootPart:FindFirstChild("CrawlTorque")
            if not crawlTorque then
                crawlTorque = Instance.new("AlignOrientation")
                crawlTorque.Name = "CrawlTorque"
                crawlTorque.Attachment0 = crawlAtt
                crawlTorque.Mode = Enum.OrientationAlignmentMode.OneAttachment
                crawlTorque.MaxTorque = math.huge
                crawlTorque.Responsiveness = 40
                crawlTorque.Parent = rootPart
            end
            
            -- Disable native AutoRotate so it doesn't fight our AlignOrientation
            humanoid.AutoRotate = false
            
            -- 3. MOVEMENT LOOP (Speed Control + Remount Check)
            local crawlLoop
            crawlLoop = RunService.Heartbeat:Connect(function()
                -- A. Remount Detection
                if humanoid.SeatPart then
                    print("Remount Detected - Stopping Crawl")
                    if crawlLoop then crawlLoop:Disconnect() end
                    if crawlMover then crawlMover:Destroy() end
                    if crawlTorque then crawlTorque:Destroy() end
                    if crawlAtt then crawlAtt:Destroy() end
                    track:Stop(0)
                    for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do t:Stop(0) end
                    if animScript then animScript.Disabled = false end
                    ragdollActivated = false
                    humanoid.WalkSpeed = 16
                    humanoid.HipHeight = 0
                    humanoid.AutoRotate = true
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
                    local cam = workspace.CurrentCamera
                    if cam then cam.CameraSubject = humanoid end
                    return
                end
                
                -- B. CUSTOM MOVEMENT & ROTATION
                local md = humanoid.MoveDirection
                
                if md.Magnitude > 0.1 then
                    track:AdjustSpeed(1)
                    crawlMover.VectorVelocity = md * 2.5 -- Slower, more natural crawl
                    crawlTorque.CFrame = CFrame.lookAt(Vector3.zero, md) -- AlignOrientation will smoothly blend this
                else
                    track:AdjustSpeed(0)
                    crawlMover.VectorVelocity = Vector3.zero
                    crawlTorque.CFrame = CFrame.lookAt(Vector3.zero, rootPart.CFrame.LookVector) -- Hold current rotation
                end
                
                -- DEBUG: Log crawl state every 30 frames
                if not _G._crawlDbg then _G._crawlDbg = 0 end
                _G._crawlDbg = _G._crawlDbg + 1
                if _G._crawlDbg % 30 == 0 then
                    local currentVel = rootPart.AssemblyLinearVelocity
                    print(string.format(
                        "[CRAWL DEBUG] MD=(%.2f,%.2f,%.2f) Vel=(%.2f,%.2f,%.2f) Spd=%.1f State=%s WS=%d Collide=%s",
                        md.X, md.Y, md.Z,
                        currentVel.X, currentVel.Y, currentVel.Z,
                        currentVel.Magnitude,
                        tostring(humanoid:GetState()),
                        humanoid.WalkSpeed,
                        tostring(rootPart.CanCollide)
                    ))
                end
            end)
            
            return
        end
        
    end)
    
    CrashEjectEvent:FireServer({
        reason = reason,
        flingVelocity = flingVelocity, -- Raw velocity, NOT impulse
        speed = speed,
    })
    
    -- FORCE UNEQUIP GUN
    humanoid:UnequipTools()
    
    -- 1. Ragdoll
    -- The server sets PlatformStand = true, but we must also do it locally instantly
    ragdollActivated = false 
    
    humanoid.PlatformStand = true
    humanoid.RequiresNeck = false
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    
    -- Disable Motor6Ds locally by DESTROYING them (forces absolute limb detachment)
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:FindFirstAncestorWhichIsA("Accessory") then continue end
        
        if (desc:IsA("JointInstance") or desc:IsA("WeldConstraint") or desc:IsA("RigidConstraint") or desc:IsA("AnimationConstraint")) and desc.Name ~= "RootJoint" and desc.Name ~= "Root" and desc.Name ~= "AccessoryWeld" and desc.Name ~= "RagdollSocket" then
            desc:Destroy()
        end
    end
    
    -- FORCE LIMBS TO COLLIDE WITH THE GROUND
    -- The Humanoid forces CanCollide=false on R15 limbs every frame. We must aggressively override it 
    -- during the ragdoll phase so the limbs bounce on the floor instead of phasing through it.
    if _G.ragdollCollisionLoop then _G.ragdollCollisionLoop:Disconnect() end
    _G.ragdollCollisionLoop = game:GetService("RunService").Heartbeat:Connect(function()
        if not character or not humanoid or not humanoid.PlatformStand then
            if _G.ragdollCollisionLoop then
                _G.ragdollCollisionLoop:Disconnect()
                _G.ragdollCollisionLoop = nil
            end
            return
        end
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
                desc.CanCollide = true
            end
        end
    end)
    
    -- FIX: Hide Prompts when Crashed/Ragdolled
    game:GetService("ProximityPromptService").Enabled = false
    
    print("💥 CRASH EJECT!", reason, "| Speed:", math.floor(speed))
end

-- Monitor Health Logic Moved to NotificationController (Persistent)
local function setupHealthMonitor()
    -- Deprecated: Handled in NotificationController
end

-- Attachments
local corners = {"FL", "FR", "RL", "RR"}
local attachments = {}
local ragdollJoints = {}

-- State
local isSpaceHeld = false -- Jump/Hop
local isShiftHeld = false -- Handbrake/Drift
local chatActive = false -- True when player is typing in chat

local DRIFT_SOUND_ID = "rbxassetid://6015314766" -- TTD Tires Squeal (User Requested "Toilet Battle Grounds")
local LOOP_TRIM_START = 0.8 -- Cut first 0.8s
local LOOP_TRIM_END = 4.5   -- Cut last 4.5s (Very aggressive trim)
local driftSoundLength = 0

-- VOOM SOUND (Arcade Acceleration)
local VOOM_SOUND_ID = "rbxassetid://12222046" -- Classic Roblox Car Engine Loop
local VOOM_MIN_SPEED = 10 
local VOOM_MAX_SPEED = 40 -- Pitch Cap
-- Removed Loop Limit (Let sound play normally)
local lastVoomTime = 0
local voomSound
local voomSoundLength = 0 -- For custom looping

-- Setup Character Function
local function setupCharacter(newChar)
    if not newChar then return end
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
    attachments = {}
    wasSeated = false -- Ensure we reset seating state on respawn so blur/wind re-initializes properly
    
    -- FIX: Centralized Prompt Visibility (Seated/Ragdolled/Dead)
    local function updatePrompts()
        if not humanoid then return end
        
        local isSeated = (humanoid.SeatPart ~= nil)
        local isRagdolled = (humanoid:GetState() == Enum.HumanoidStateType.Physics or humanoid.PlatformStand)
        local isDead = (humanoid.Health <= 0)
        
        -- ONLY enable if not ragdolled AND not dead
        local shouldBeEnabled = (not isRagdolled and not isDead)
        
        -- Apply globally
        game:GetService("ProximityPromptService").Enabled = shouldBeEnabled
    end
    
    humanoid.Seated:Connect(updatePrompts)
    humanoid.Died:Connect(updatePrompts)
    humanoid.StateChanged:Connect(updatePrompts)
    humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(updatePrompts)
    humanoid:GetPropertyChangedSignal("SeatPart"):Connect(updatePrompts)
    
    -- SIM 53.0: Roblox Core Script Camera Hijack Prevention
    -- When the server explicitly calls seat:Sit(hum) (e.g. teleport safety net),
    -- Roblox's core scripts forcefully change the CameraSubject to the VehicleSeat.
    -- We must instantly revert this to keep the camera focused on the player.
    workspace.CurrentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
        local cam = workspace.CurrentCamera
        if humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat") then
            if cam.CameraSubject == humanoid.SeatPart then
                print("Camera Hijack Detected! Restoring CameraSubject to Humanoid.")
                cam.CameraSubject = humanoid
            end
        end
    end)
    
    -- Periodic Re-check (Aggressive safety for network delays)
    spawn(function()
        while humanoid and humanoid.Parent do
            updatePrompts()
            task.wait(0.1) -- Faster check for prompt responsiveness
        end
    end)
    
    updatePrompts() -- Initial check
    
    -- MUTE DEFAULT FOOTSTEPS / JUMPS (AGGRESSIVE)
    local function muteSound(obj)
        if obj:IsA("Sound") then
            local name = obj.Name
            if name == "Running" or name == "Jumping" or name == "Landing" or name == "Splash" or name == "GettingUp" or name == "FreeFalling" then
                obj:Stop()
                obj.Volume = 0
                obj:Destroy()
            end
        end
    end

    -- Check existing
    for _, child in ipairs(rootPart:GetChildren()) do muteSound(child) end
    
    -- Watch for new ones (Roblox scripts add them later)
    rootPart.ChildAdded:Connect(muteSound)

    -- Check Head too
    local head = character:WaitForChild("Head", 2)
    if head then
        for _, child in ipairs(head:GetChildren()) do muteSound(child) end
        head.ChildAdded:Connect(muteSound)
    end
    -- Drift Sound Setup
    if driftSound then driftSound:Destroy() end
    driftSound = Instance.new("Sound")
    driftSound.Name = "DriftSound"
    driftSound.SoundId = DRIFT_SOUND_ID
    driftSound.Volume = 0.1 -- Start quiet (User requested lower volume)
    driftSound.Looped = true
    driftSound.Parent = rootPart
    
    -- Wait for load to get length for custom looping
    spawn(function()
        if not driftSound.IsLoaded then driftSound.Loaded:Wait() end
        driftSoundLength = driftSound.TimeLength
        print("🔊 Drift Sound Loaded: Length =", driftSoundLength)
    end)
    
    -- Voom Sound Setup (Arcade Acceleration)
    if voomSound then voomSound:Destroy() end
    voomSound = Instance.new("Sound")
    voomSound.Name = "ForwardVoom"
    voomSound.SoundId = VOOM_SOUND_ID
    voomSound.Volume = 0.35
    voomSound.PlaybackSpeed = 1
    voomSound.RollOffMaxDistance = 80
    voomSound.Parent = rootPart
    
    -- Wait for load to get length for custom looping
    spawn(function()
        if not voomSound.IsLoaded then voomSound.Loaded:Wait() end
        voomSoundLength = voomSound.TimeLength
        print("🔊 Voom Sound Loaded: Length =", voomSoundLength)
    end)
    
    print("🔊 Voom Sound Initialized on", newChar.Name)
end

-- Connect Event
player.CharacterAdded:Connect(setupCharacter)

-- INITIAL SETUP (If character already exists)
if player.Character then
    setupCharacter(player.Character)
end

-- Find Physics Components
local function updatePhysicsComponents()
	if not rootPart or not character then return false end
	
	-- 1. Find the Seat
	local seat = humanoid.SeatPart
	if not seat then 
		-- TELEPORT GUARD: If the server flagged us as teleporting, the SeatWeld
		-- may briefly break. DON'T trigger dismount cleanup — return true to
		-- keep the driving loop alive until the safety net re-seats us.
		local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
		if chair then
			local vSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
			if vSeat and vSeat:GetAttribute("_Teleporting") then
				return true
			end
		end
		
		-- SIM 19.0/20.0: PHYSICS HAND-OFF (Now handled by Server Anchor)
		if lastChairModel then
			for _, part in pairs(lastChairModel:GetDescendants()) do
				if part:IsA("BasePart") then
					-- SIM 21.3: Standard friction (0.7) to allow visible crawl
					part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.7, 0.5, 100, 1)
				end
			end
			lastChairModel = nil -- Clear so we don't repeat this
		end

		-- Also zero suspension so it doesn't "freeze" in the air
		for _, vf in pairs(suspensionForces) do
			vf.Force = Vector3.zero
		end
        
        -- ANIMATIONS: Stop all chair animations on dismount
        for _, track in pairs(animTracks) do
            if track.IsPlaying then track:Stop(0.5) end
        end
		
		return false 
	end
    -- CHECK: Are we already initialized for this seat?
    if seat == currentSeat and trailsSetUp and wasSeated then
        return true
    end
    currentSeat = seat

    -- Always reset trails on new control session
    -- (Fixes bug where re-entering same chair leaves driftTrails empty but trailsSetUp true)
    trailsSetUp = false
    driftTrails = {} -- Remove local! Use Global.
	chairModel = seat.Parent -- Assign validation to file scope var (was local)
	lastChairModel = chairModel -- Cache for dismount
	local primary = chairModel.PrimaryPart
	if not primary then return false end
	
	-- Map Attachments
	for _, name in pairs(corners) do
		local attName = name .. "_Attachment"
		local vfName = name .. "_SuspensionForce"
		
		local att = primary:FindFirstChild(attName)
		local vf = primary:FindFirstChild(vfName)
		
		if att and vf then
			attachments[name] = att
			suspensionForces[name] = vf
		end
	end
	
	-- Map Constraints
	moveForce = primary:FindFirstChild("MoveVelocity")
	turnForce = primary:FindFirstChild("TurnVelocity")
	sideForce = primary:FindFirstChild("SideForce")
    dragForce = primary:FindFirstChild("DragForce")
	stabilizer = primary:FindFirstChild("Stabilizer")
	
	-- Force Attachments (ChatGPT Fix: Split for stability)
	local comAtt = primary:FindFirstChild("COM_Attachment")
	local baseAtt = primary:FindFirstChild("BaseAttachment")
	
	if moveForce and sideForce and turnForce then
        if moveForce.Attachment0 ~= baseAtt then
		    moveForce.Attachment0 = baseAtt
		    sideForce.Attachment0 = comAtt
		    turnForce.Attachment0 = comAtt
            if dragForce then dragForce.Attachment0 = comAtt end
        end
	end
	
	return (moveForce and turnForce and sideForce)
end

local function setupAnimations()
    if not humanoid then return end
    
    -- Clear old
    for _, track in pairs(animTracks) do track:Stop(); track:Destroy() end
    animTracks = {}
    
    local animData = Config.Animations
    if not animData then return end
    
    for name, id in pairs(animData) do
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local track = humanoid:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action
        
        -- Default to looping, except for Jump
        if name == "Jump" then
            track.Looped = false
        else
            track.Looped = true
        end
        
        animTracks[name] = track
    end
end

local function updateAnimations(dt, throttle, speed, steer, isDrifting)
    local forwardTrack = animTracks.Forward
    local reverseTrack = animTracks.Reverse
    local idleTrack = animTracks.Idle
    local driftLeftTrack = animTracks.DriftLeft
    local driftRightTrack = animTracks.DriftRight
    
    if not forwardTrack then return end
    
    -- 1. Determine target weights
    local isSteeringLeft = (steer < -0.1)
    local isSteeringRight = (steer > 0.1)
    local isMovingForward = (throttle > 0.1)
    local isMovingReverse = (throttle < -0.1)
    
    local targetForward = 0
    local targetReverse = 0
    local targetIdle = 0
    local targetDriftLeft = 0
    local targetDriftRight = 0
    
    -- ══ INTERPRETATION LOGIC ══
    if isMovingReverse and speed > 1 then
        -- User Custom Mapping for Reverse Movement
        -- 1. Backwards Left = Reversed Right Turn
        if isSteeringLeft then
            targetDriftRight = 1
        -- 2. Backwards Right = Reversed Left Turn
        elseif isSteeringRight then
            targetDriftLeft = 1
        -- 3. Backwards Straight = Reversed Forward
        else
            targetForward = 1
        end
    else
        -- Forward / Stationary Movement
        -- Priority 1: Specific Turn Animations (DriftLeft / DriftRight)
        if isSteeringLeft and speed > 2 and driftLeftTrack then
            targetDriftLeft = 1
        elseif isSteeringRight and speed > 2 and driftRightTrack then
            targetDriftRight = 1
        
        -- Priority 2: Generic Turning (Unhandled Left or Right)
        elseif (isSteeringLeft or isSteeringRight) and speed > 2 then
            targetIdle = 1
            
        -- Priority 3: Pure Straight Movement
        elseif isMovingForward and math.abs(steer) <= 0.1 then
            targetForward = 1
            
        -- Default: Idle
        else
            targetIdle = 1
        end
    end
    
    -- 2. Smoothly blend weights
    -- We want snappy transitions but not "popping"
    local blendSpeed = 10 
    
    local function blend(trackName, target)
        local track = animTracks[trackName]
        if not track then return end
        
        if target > 0 and not track.IsPlaying then track:Play() end
        
        local current = animWeights[trackName] or 0
        local nextWeight = current + (target - current) * math.clamp(dt * blendSpeed, 0, 1)
        animWeights[trackName] = nextWeight
        
        track:AdjustWeight(nextWeight, 0.1)
        
        -- Stop if fully faded out for performance
        if nextWeight < 0.01 and track.IsPlaying then track:Stop() end
    end
    
    blend("Forward", targetForward)
    blend("Reverse", targetReverse)
    blend("Idle", targetIdle)
    if driftLeftTrack then
        blend("DriftLeft", targetDriftLeft)
    end
    if driftRightTrack then
        blend("DriftRight", targetDriftRight)
    end
    
    -- 3. Adjust Playback Speed based on Physical Speed & Direction
    -- Scale pushing speed: 0 studs/s = 0 speed, 50 studs/s = 1.5x anim speed
    local playbackDirection = (throttle < -0.1) and -1 or 1
    local reverseBoost = (playbackDirection == -1) and 3.5 or 1.0 -- Boost reverse speed (3.5x)
    local playbackSpeed = math.clamp(speed / 35, 0.2, 2.0) * playbackDirection * reverseBoost
    
    if forwardTrack.IsPlaying then forwardTrack:AdjustSpeed(playbackSpeed) end
    if reverseTrack.IsPlaying then reverseTrack:AdjustSpeed(playbackSpeed) end
    if idleTrack.IsPlaying then idleTrack:AdjustSpeed(1) end
    if driftLeftTrack and driftLeftTrack.IsPlaying then driftLeftTrack:AdjustSpeed(playbackSpeed) end
    if driftRightTrack and driftRightTrack.IsPlaying then driftRightTrack:AdjustSpeed(playbackSpeed) end
end


-- Input Handlers (Frame-Independent Jump - ChatGPT Fix)
local visualRoll = 0 -- Visual body roll angle
local jumpRequested = false  -- LATCHED REQUEST (not timer)
local sideGripRamp = 0 -- ChatGPT Fix: Rate-limit side grip to prevent tripping
local jumpStabilityTimer = 0 -- ChatGPT Fix: Temporarily neutralize rotation during jump

UserInputService.InputBegan:Connect(function(input, gpe)
    -- Track chat/textbox focus state for Heartbeat polling
    if input.UserInputType == Enum.UserInputType.Keyboard then
        chatActive = gpe
    end
    if gpe then return end -- Ignore game-processed inputs

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isShiftHeld = true
    elseif input.KeyCode == Enum.KeyCode.G then
		if game.Players.LocalPlayer:GetAttribute("InShop") then return end
        local seat = humanoid.SeatPart
        if seat then
            local vel = rootPart.AssemblyLinearVelocity
            local fwd = seat.CFrame.LookVector
            local right = seat.CFrame.RightVector
            crashEject(seat, rootPart, vel, vel.Magnitude, fwd, right, "manual_debug")
        end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isShiftHeld = false
	end
end)

-- Native Input ended checks for turning off Shift state


-- State Variables
local landingGraceTimer = 0 -- ChatGPT Fix: Prevent post-hop torque spikes
local wasAirborne = false
local wheelDistances = {} -- Track per-wheel distance for perfect trail grounding
local hitPositions = {} -- Track points for normal calculation/trail placement globally
local hitNormals = {} -- Track surface normals for ramp alignment globally
local smoothedNormal = Vector3.new(0, 1, 0) -- Sim 22.0: Ramp Alignment
local jumpCooldownTimer = 0 -- Sim 51.0: Prevent wall-clip double jumps

-- Raycast Params (We want to hit cones so we can react, but we'll filter them by mass later)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.CollisionGroup = "Wheelchair"
rayParams.IgnoreWater = true

-- Tracks previous Space key state for rising-edge detection in physics loop
local lastSpaceDown = false

-- Main Physics Loop
RunService.Heartbeat:Connect(function(dt)
    if humanoid and humanoid.Health <= 0 then 
        if _G.windTrails then
            for _, t in pairs(_G.windTrails) do
                if t.activeTrail then t.activeTrail.Enabled = false end
            end
        end
        if driftParticleR then driftParticleR.Enabled = false end
        if driftParticleL then driftParticleL.Enabled = false end
        if _G.blurWheels then
            for _, wd in ipairs(_G.blurWheels) do
                if wd.part then wd.part.Transparency = 1 end
            end
        end
        if chairModel then
            local wl = chairModel:FindFirstChild("Wheel_L")
            local wr = chairModel:FindFirstChild("Wheel_R")
            if wl then wl.Transparency = 0 end
            if wr then wr.Transparency = 0 end
            
            local wsl = chairModel:FindFirstChild("WindSource_L")
            local wsr = chairModel:FindFirstChild("WindSource_R")
            if wsl then
                local sl = wsl:FindFirstChild("DriftSparks")
                local gl = wsl:FindFirstChild("DriftSparks_Glow")
                if sl then sl.Enabled = false end
                if gl then gl.Enabled = false end
            end
            if wsr then
                local sr = wsr:FindFirstChild("DriftSparks")
                local gr = wsr:FindFirstChild("DriftSparks_Glow")
                if sr then sr.Enabled = false end
                if gr then gr.Enabled = false end
            end
        end
        if voomSound and voomSound.IsPlaying then voomSound:Stop() end
        return 
    end
    -- JUMP: Poll key state directly — completely bypasses InputBegan/gpe issues
    -- with VehicleSeat input capture. Rising-edge only (press, not hold).
    local spaceDown = _G.MobileJumpDown == true
    if not chatActive then
        spaceDown = spaceDown
            or UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or UserInputService:IsKeyDown(Enum.KeyCode.E)
    end
    
    local effectiveShiftHeld = isShiftHeld or _G.MobileDriftDown == true
        
    local inShop = game.Players.LocalPlayer:GetAttribute("InShop")
    if spaceDown and not lastSpaceDown and humanoid.SeatPart and not inShop then
        jumpRequested = true
        print("🚀 Jump latched via IsKeyDown | drifting:", isDrifting)
    end
    lastSpaceDown = spaceDown

    if not updatePhysicsComponents() then 
        if wasSeated then
            print("🔧 DISMOUNT CLEANUP")
            wasSeated = false
            isDrifting = false
            currentSpeed = 0
            _G.windActive = false
            
            if _G.windTrails then
                for _, t in pairs(_G.windTrails) do
                    if t.activeTrail then t.activeTrail.Enabled = false end
                end
            end
            if driftParticleR then driftParticleR.Enabled = false end
            if driftParticleL then driftParticleL.Enabled = false end
            if _G.blurWheels then
                for _, wd in ipairs(_G.blurWheels) do
                    if wd.part then wd.part.Transparency = 1 end
                end
            end
            if chairModel then
                local wl = chairModel:FindFirstChild("Wheel_L")
                local wr = chairModel:FindFirstChild("Wheel_R")
                if wl then wl.Transparency = 0 end
                if wr then wr.Transparency = 0 end
                
                local wsl = chairModel:FindFirstChild("WindSource_L")
                local wsr = chairModel:FindFirstChild("WindSource_R")
                if wsl then
                    local sl = wsl:FindFirstChild("DriftSparks")
                    local gl = wsl:FindFirstChild("DriftSparks_Glow")
                    if sl then sl.Enabled = false end
                    if gl then gl.Enabled = false end
                end
                if wsr then
                    local sr = wsr:FindFirstChild("DriftSparks")
                    local gr = wsr:FindFirstChild("DriftSparks_Glow")
                    if sr then sr.Enabled = false end
                    if gr then gr.Enabled = false end
                end
            end
            if voomSound and voomSound.IsPlaying then voomSound:Stop() end
            
            -- RESTORE DEFAULTS
            humanoid.AutoRotate = true
            local cam = workspace.CurrentCamera
            if cam then
                cam.CameraSubject = humanoid
            end
        end
        return 
    end
    -- Main Loop
    
    -- SIM 29.0/31.0/35.0: STATE RESET ON FIRST SIT
    if not wasSeated and humanoid.SeatPart then
        print("🔄 STATE RESET (Fresh Sit)")
        
        -- Fix Camera swinging via VehicleSeat Roblox default:
        local cam = workspace.CurrentCamera
        if cam and humanoid then
            cam.CameraSubject = humanoid
        end
        
        -- Disable the default Roblox speed HUD that appears on VehicleSeat
        local seat = humanoid.SeatPart
        if seat and seat:IsA("VehicleSeat") then
            seat.HeadsUpDisplay = false
        end
        
        currentSpeed = 0
        driftPowerRamp = 0
        momentumReserve = Config.MaxSpeed
        steadyHybrid = 0
        steadySteer = 0
        isDrifting = false
        driftTime = 0
        landingGraceTimer = 0
        jumpStabilityTimer = 0.25
        visualRoll = 0
        sideGripRamp = 0
        tiltGraceTimer = 1.0
        lastLateralVel = Vector3.zero -- SIM 44.0
        tiltEjectTimer = 0            -- SIM 44.0
        momentumLockTimer = 0 -- SIM 45.0
        lockedDriveDir = nil  -- SIM 45.0
        driftCarryTimer = 0   -- SIM 45.0
        wasSeated = true
        
    -- SIM 50.0: Initialize Wind Blur immediately on sit (don't wait for drift)
        local seat = humanoid.SeatPart
        if seat and seat.Parent then
            local chairModel = seat.Parent
            
            -- Force-preload all mesh assets to prevent low-poly fallback rendering
            local ContentProvider = game:GetService("ContentProvider")
            local meshParts = {}
            for _, p in ipairs(chairModel:GetDescendants()) do
                if p:IsA("MeshPart") and p.MeshId ~= "" then
                    table.insert(meshParts, p)
                end
            end
            if #meshParts > 0 then
                pcall(function()
                    ContentProvider:PreloadAsync(meshParts)
                end)
            end
            
            local primary = chairModel.PrimaryPart
            if primary then
                print("WHEELS LOG:", attachments.RL and attachments.RL.Parent, attachments.RR and attachments.RR.Parent)
                
                -- Global array to track our wind emitters for the Heartbeat loop
                _G.windTrails = {} 
                
                -- Create Left Wheel Attachment
                local attL = Instance.new("Attachment")
                attL.Name = "WindSource_L"
                attL.Position = Vector3.new(-1.8, -1.2, 2)
                attL.Parent = primary
                
                -- Create Right Wheel Attachment
                local attR = Instance.new("Attachment")
                attR.Name = "WindSource_R"
                attR.Position = Vector3.new(1.8, -1.2, 2)
                attR.Parent = primary
                
                -- Create fake "PS2 Style" motion blur discs over the static wheels
                local function createBlurDisc(name, offset, face)
                    local disc = Instance.new("Part")
                    disc.Name = name
                    disc.Shape = Enum.PartType.Cylinder
                    disc.Size = Vector3.new(0.05, 3.0, 3.0) -- Scaled up to 3 studs to fully cover the spokes
                    disc.Transparency = 1 -- Invisible while stopped
                    disc.Material = Enum.Material.Neon
                    disc.Color = Color3.fromRGB(40, 40, 40) -- Dark, dusty rim color
                    disc.CanCollide = false
                    disc.CanQuery = false -- CRITICAL: Prevents suspension raycasts from hitting the disc and levitating the chair
                    disc.CanTouch = false
                    disc.Massless = true
                    disc.Anchored = true
                    
                    -- Align the cylinder flat-side out against the wheel by keeping its native X-axis orientation
                    local cframeOffset = CFrame.new(offset)
                    disc.CFrame = primary.CFrame * cframeOffset
                    disc.Parent = workspace -- Parent to workspace so chairModel loops can't touch it
                    
                    -- Create physical intersecting spokes to spin with the disc to visually communicate rotation
                    local spokes = {}
                    local spokeAngles = {}
                    for i = 1, 4 do
                        local spoke = Instance.new("Part")
                        spoke.Name = "BlurSpoke"
                        spoke.Size = Vector3.new(0.07, 0.25, 2.85) -- Slightly thicker than the disc so they render clearly over it
                        spoke.Transparency = 1
                        spoke.Anchored = true -- Anchored so we manually position every frame
                        spoke.CanCollide = false
                        spoke.CanQuery = false -- CRITICAL: Prevents raycast interference
                        spoke.CanTouch = false
                        spoke.Massless = true
                        spoke.Material = Enum.Material.Neon
                        spoke.Color = Color3.fromRGB(150, 150, 160) -- Silver metallic contrast
                        
                        -- Rotate on the cylinder's X face to form a star
                        local angleOffset = CFrame.Angles(math.rad(i * 45), 0, 0)
                        spoke.CFrame = disc.CFrame * angleOffset
                        spoke.Parent = workspace -- Parent to workspace alongside disc
                        
                        table.insert(spokes, spoke)
                        table.insert(spokeAngles, angleOffset)
                    end
                    
                    return {part = disc, baseOffset = cframeOffset, spokes = spokes, spokeAngles = spokeAngles, spinAngle = 0}
                end
                
                -- ── AGGRESSIVE CLEANUP: Wipe any frozen blur discs from a previous chair ──
                if _G.blurWheels then
                    for _, wd in ipairs(_G.blurWheels) do
                        if wd.part and wd.part.Parent then
                            wd.part.Transparency = 1
                            wd.part:Destroy()
                        end
                        if wd.spokes then
                            for _, s in ipairs(wd.spokes) do
                                if s and s.Parent then s:Destroy() end
                            end
                        end
                    end
                    _G.blurWheels = nil
                end
                
                -- Force wipe any orphaned parts in workspace (client-side only so safe for multiplayer)
                for _, obj in ipairs(workspace:GetChildren()) do
                    if obj.Name == "BlurDisc_L" or obj.Name == "BlurDisc_R" or obj.Name == "BlurSpoke" or obj.Name == "CustomWindBlur" then
                        obj:Destroy()
                    end
                end

                -- Pushed halfway back to perfectly center on the wheels (Z: 1.3)
                -- Pushed outward slightly (X: ±1.5) to sit flush on the outside of the rims
                _G.blurWheels = {
                    createBlurDisc("BlurDisc_L", Vector3.new(-1.5, -1.5, 1.3), Enum.NormalId.Left),
                    createBlurDisc("BlurDisc_R", Vector3.new(1.5, -1.5, 1.3), Enum.NormalId.Right)
                }
                
                _G.windActive = true
            end
        end
        -- Visual Wheel Rotation removed: Wheels and frame are a single baked mesh "Metal".

        -- SIM 49.3: DISABLE CAMERA AUTO-ROTATION (Robust)
        -- Forcing CameraSubject to Humanoid stops the VehicleSeat's "Follow" camera
        local cam = workspace.CurrentCamera
        if cam then
            cam.CameraSubject = humanoid
            cam.CameraType = Enum.CameraType.Custom
        end
        humanoid.AutoRotate = false -- Prevent character rotation conflict
        
        -- ANIMATIONS: Load tracks once on sit
        animWeights = {Forward = 0, Reverse = 0, Idle = 0}
        setupAnimations()
        
        -- FIX: Re-enable default animations (In case we were crawling)
        local animScript = character:FindFirstChild("Animate")
        if animScript then animScript.Disabled = false end
        
        -- SIM 35.0 FIX 5: Clear angular velocity and restore physics
        local seat = humanoid.SeatPart
        if seat and seat.Parent then
            local chairModel = seat.Parent
            for _, part in pairs(chairModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    -- ChatGPT: Zero all velocities on spawn
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                    -- SIM: Restore Density to 1 so the steering feels light and fast, but Friction MUST remain 0!
                    part.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 1)
                end
            end
            local primary = chairModel.PrimaryPart
            if primary then
                local crawl = primary:FindFirstChild("CrawlBrake")
                local spin = primary:FindFirstChild("SpinBrake")
                if crawl then crawl:Destroy() end
                if spin then spin:Destroy() end
            end
        end
    end
    
     -- spawn flip)
    
    -- SIM 30.0: Tilt Grace Timer (prevents spawn flip)
    if tiltGraceTimer > 0 then
        tiltGraceTimer = tiltGraceTimer - dt
    end
    
	local seat = humanoid.SeatPart
	if not seat then return end -- Guard: seat lost mid-frame (crash eject, teleport, etc.)
	local chairModel = seat.Parent
	if not chairModel then return end
	local primary = chairModel.PrimaryPart
	
	-- Filter Character & Chair & ChallengeGateway (portal must be invisible to bumper raycasts)
	local excludeList = {character, chairModel}
	local gateway = workspace:FindFirstChild("ChallengeGateway")
	if gateway then table.insert(excludeList, gateway) end
	rayParams.FilterDescendantsInstances = excludeList
    
    -- SIM 54.0: BYPASS VehicleSeat input — read WASD directly via UserInputService
    -- VehicleSeat.Throttle/Steer can fail when network ownership is explicitly set.
    -- Direct key polling is 100% reliable regardless of ownership state.
    local throttle = 0
    local steer = 0
    
    -- Get universal movement input (works for PC, Gamepad, and native Mobile Joystick!)
    local moveVector = Vector3.zero
    pcall(function()
        local PlayerModule = require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"))
        local controls = PlayerModule:GetControls()
        if controls then
            moveVector = controls:GetMoveVector()
        end
    end)
    
    if not chatActive then
        throttle = 0
        steer = 0
        
        -- Forward/Backward (Z is negative for forward)
        if moveVector.Z < -0.1 then throttle = 1
        elseif moveVector.Z > 0.1 then throttle = -1 end
        
        -- Left/Right (X is positive for right)
        if moveVector.X < -0.1 then steer = -1
        elseif moveVector.X > 0.1 then steer = 1 end
    end
    
    if game.Players.LocalPlayer:GetAttribute("InShop") then
        steer = 0
        throttle = 0
        currentSpeed = 0
        momentumReserve = 0
    end
    
    -- STATE VARIABLES (Moved Up)
	local vel = rootPart.AssemblyLinearVelocity
	local fwd = primary.CFrame.LookVector
    local up = primary.CFrame.UpVector
    local right = primary.CFrame.RightVector
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
    local planarForward = Vector3.new(fwd.X, 0, fwd.Z).Unit
    
    -- Safety: Ensure currentSpeed is initialized (it is at file scope, but safe check)
    currentSpeed = currentSpeed or 0
	
	-- 1. Suspension Logic (Raycast)
    -- Simple symmetric suspension for stability
    
    -- Ground Detection Tracking
    local anyRayHit = false
    local minDist = math.huge
    table.clear(hitPositions)
    table.clear(hitNormals)
    
	for name, att in pairs(attachments) do
		local origin = att.WorldPosition
		local dir = -att.WorldCFrame.UpVector * Config.SusRayLength
		
		local result = workspace:Raycast(origin, dir, rayParams)
		local force = Vector3.zero
		
		if result then
            anyRayHit = true
            minDist = math.min(minDist, result.Distance)
            hitPositions[name] = result.Position
            hitNormals[name] = result.Normal -- SIM 45.0
            wheelDistances[name] = result.Distance
            
			local dist = result.Distance
            local activeRest = Config.SusRestLength
            
			local offset = activeRest - dist
			
			-- SIM 35.0: SUSPENSION FIX
			-- Spring force: pushes up when compressed below rest length
			local fSpring = 0
			if offset > 0 then
				fSpring = Config.SusStiffness * offset
			end
			
			-- Damping: opposes vertical velocity to prevent oscillation
			local localVel = rootPart:GetVelocityAtPosition(origin)
			local verticalSpeed = localVel.Y
			local fDamp = Config.SusDamping * verticalSpeed
			
			local totalY = fSpring - fDamp
			
			-- Per-spring clamp: gravity is ~196*mass shared across 4 springs
			-- Each spring should never exceed ~1.5x its share of gravity support
			local gravityPerSpring = rootPart.AssemblyMass * workspace.Gravity / 4
			local maxLift = gravityPerSpring * 3   -- 3x gravity share (enough to hold + respond to bumps)
			local maxRebound = gravityPerSpring * 0.5 -- Small rebound to prevent sinking
			totalY = math.clamp(totalY, -maxRebound, maxLift)
			
			force = Vector3.new(0, totalY, 0)
        else
            wheelDistances[name] = 100 -- Airborne corner
		end
		
		-- SIM 38.0: Suspension control
		-- FIX: Check jumpRequested! Suspension calculates before the jump fires. 
		-- If we don't zero it here, the physics engine processes a massive downward 
		-- anchor force on the exact same frame we apply the jump impulse!
		if jumpRequested then
			force = Vector3.zero -- Hard off on jump liftoff frame
		elseif jumpStabilityTimer > 0 then
			local suspensionAlpha = 1 - (jumpStabilityTimer / 0.25)
			suspensionAlpha = math.clamp(suspensionAlpha, 0, 1)
			force = force * suspensionAlpha
		end
		
		if suspensionForces[name] then
			suspensionForces[name].Force = force
		end
	end
	
    -- 5. Detect Grounding & Airborne State 
    local groundDist = anyRayHit and minDist or 100
    local tolerance = isDrifting and 5.0 or 1.5 -- Massive tolerance when drifting to account for 70-deg tilt
    local isGrounded = anyRayHit and (minDist < Config.SusRestLength + tolerance)
	local isAirborne = not isGrounded

    -- SIM 45.0: Detect edge-fall (went airborne without jumping)
    -- Capture momentum lock for non-jump airborne transitions too
    if isAirborne and not wasAirborne then
        if momentumLockTimer <= 0 then -- Don't override if jump already set it
            -- FIX: Standardize direction capture (intended forward)
            local takeoffDir = (flatVel.Magnitude > 1) and flatVel.Unit or planarForward
            lockedDriveDir = takeoffDir * (currentSpeed < -1 and -1 or 1)
            momentumLockTimer = 0.3
        end
        if isDrifting and driftCarryTimer <= 0 then
            driftCarryTimer = 0.35
        end
    end

    -- SIM 37.0: JUMP PROCESSING - MUST BE BEFORE STEERING
    -- This ensures jumpStabilityTimer is set BEFORE yaw impulse checks
    if jumpRequested and not isAirborne and jumpCooldownTimer <= 0 then
        jumpRequested = false
        -- Temporarily clear shift so drift state doesn't immediately re-engage mid-jump
        -- (drift requires effectiveShiftHeld; jump releases it for one frame via isDrifting carry)
        print("🚀 JUMPING! Speed:", math.floor(speed), "Drifting:", isDrifting)
        
        -- Set timers FIRST (before any steering checks this frame)
        jumpStabilityTimer = 0.25
        jumpCooldownTimer = 0.50 -- 500ms hard lockout to prevent double jumps from wall clips
        
        -- SIM 45.0: Capture drive direction at takeoff
        local takeoffDir = (flatVel.Magnitude > 1) and flatVel.Unit or planarForward
        lockedDriveDir = takeoffDir * (currentSpeed < -1 and -1 or 1)
        
        momentumLockTimer = 0.3 -- Preserve momentum for 300ms after landing
        
        -- SIM 45.0: Capture drift state for grip carry
        if isDrifting then
            driftCarryTimer = 0.35
        end
        
        -- SIM 40.1: Capture steer input for spin (during drift OR shift held)
        if isDrifting then
            local spinMultiplier = 0.8
            airSpinRate = -steer * Config.TurnSpeed * spinMultiplier
        else
            airSpinRate = 0
        end
        
        -- Clear pitch/roll, apply spin rate
        rootPart.AssemblyAngularVelocity = Vector3.new(0, airSpinRate, 0)
        
        if stabilizer then 
            stabilizer.Enabled = false 
            stabilizer.MaxTorque = 0
        end
        
        -- Apply jump force immediately rather than queuing an impulse.
        -- Drift physics (stabilizers/friction) frequently cancel queued impulses.
        -- Direct velocity assignment guarantees liftoff.
        local currentVel = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(currentVel.X, 50, currentVel.Z)
        
        local jumpTrack = animTracks.Jump
        if jumpTrack then
            jumpTrack:Play(0.05)
        end
    end

    -- Sim 12.0: CALCULATE DRIFT STATE AT START OF FRAME (Zero-Latency)
    local right = primary.CFrame.RightVector
    local lateralSpeed = vel:Dot(right)
	local slipAngle = 0
	if speed > 5 then
		local moveDir = flatVel.Unit
		slipAngle = math.deg(math.acos(math.clamp(moveDir:Dot(fwd), -1, 1)))
	end
	
    -- Sim 18.0/19.0: Drift Speed Floors
    local driftEntrySpeed = Config.DriftEntrySpeed or 50
    local driftExitSpeed = Config.DriftExitSpeed or 25
    local currentDriftFloor = isDrifting and driftExitSpeed or driftEntrySpeed
    
    -- (Wall collision moved to AFTER integrator - Sim 29.0)

    local isDriftingNow = false
    -- FIX: Maintain drift state mid-air so speed threshold doesn't reset to EntrySpeed (36) during flight
    if isAirborne and jumpStabilityTimer <= 0 then
        -- In mid-air, hold the state. Require Shift to keep it alive.
        if isDrifting and effectiveShiftHeld then
            isDriftingNow = true
        end
    else
        if speed > currentDriftFloor and ((effectiveShiftHeld and steer ~= 0) or (slipAngle > Config.DriftThreshold and speed > 20)) then
            isDriftingNow = true
            driftTime = driftTime + dt
        else
            driftTime = 0
        end
    end
    isDrifting = isDriftingNow -- Update persistent state immediately
    
    -- SIM 45.0: Track drift carry timer
    if isDriftingNow and not isAirborne then
        driftCarryTimer = 0.35 -- Refresh while actively drifting on ground
    end
    if not isAirborne and driftCarryTimer > 0 then
        driftCarryTimer = math.max(0, driftCarryTimer - dt)
    end
    -- SIM FIX: Always consider it a drift during landing grace to prevent the 150x 
    -- 'Mud Brake' from accidentally engaging if the wheel bumps the ground strangely
    local effectiveDrift = isDriftingNow or driftCarryTimer > 0 or landingGraceTimer > 0
    
    -- ═══ DRIFT TRAIL MARKS (Trail Objects) ═══
    -- Set up Trail objects on first drift (need primary part to exist)
    if not trailsSetUp and primary then
        trailsSetUp = true
        for _, wheelName in ipairs({"RL", "RR"}) do
            local att = attachments[wheelName]
            if att then
                -- Create two attachments offset left/right for trail width
                local att0 = Instance.new("Attachment")
                att0.Name = wheelName .. "_TrailL"
                att0.Parent = workspace.Terrain
                
                local att1 = Instance.new("Attachment")
                att1.Name = wheelName .. "_TrailR"
                att1.Parent = workspace.Terrain
                
                local trailTemplate = Instance.new("Trail")
                trailTemplate.Name = wheelName .. "_DriftTrail"
                trailTemplate.Lifetime = TRAIL_LIFETIME
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
                trailTemplate.Enabled = false -- Controlled dynamically
                
                local equippedDrift = player:GetAttribute("Shop_Equipped_DriftVFX") or "Default"
                
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
                glow.Texture = "rbxassetid://243527266" -- Soft Puffs
                glow.Orientation = Enum.ParticleOrientation.FacingCamera
                glow.VelocityInheritance = 0.3
                glow.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.6),
                    NumberSequenceKeypoint.new(1, 1)
                })
                glow.Rate = 0
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
                
                local activeTrail = trailTemplate:Clone()
                activeTrail.Attachment0 = att0
                activeTrail.Attachment1 = att1
                activeTrail.Parent = workspace.Terrain
                
                -- Store list of emitters
                table.insert(driftTrails, {
                    side=wheelName,
                    a0=att0, a1=att1, trailTemplate=trailTemplate, 
                    emitters={sparks, glow}, 
                    wheel=att,
                    lastEmit = 0,
                    wasGrounded = false,
                    activeTrail = activeTrail
                })
            end
        end
    end
    
    -- Update Trail Positions & Visibility
    local trainEnabled = effectiveDrift and (speed > 10) and not isAirborne -- FIX: Check isAirborne!
    
    if trainEnabled ~= _G.lastNetDriftState then
        _G.lastNetDriftState = trainEnabled
        local DriftSyncEvent = ReplicatedStorage:FindFirstChild("DriftSyncEvent")
        if DriftSyncEvent then
            DriftSyncEvent:FireServer(trainEnabled)
        end
    end
    
    -- (Visual Trail Update moved to Heartbeat for smooth ground snapping)

    -- Sim 14.1: Rig Check (Mass Fallback)
    local totalMass = rootPart.AssemblyMass
    local safeMass = totalMass
    if safeMass == math.huge or safeMass == 1/0 then safeMass = 200 end

    -- Sim 17.0: TILT DETECTION & DISMOUNT
    -- SIM 30.0: Skip during tilt grace period (prevents spawn flip)
    local upDot = up:Dot(Vector3.yAxis)
    -- [REMOVED TILT DISMOUNT PER USER REQUEST]

    -- Sim 14.0: Forward ALIGNMENT CHECK
    -- DEBUG: Verify Input
    if math.random() < 0.1 then
        local inShop = game.Players.LocalPlayer:GetAttribute("InShop")
        local wPressed = UserInputService:IsKeyDown(Enum.KeyCode.W)
        print(string.format("T: %d S: %d Spd: %d Air: %s | InShop: %s | W_Key: %s | SeatThr: %d", 
            throttle, steer, math.floor(currentSpeed), tostring(isAirborne), tostring(inShop), tostring(wPressed), seat.Throttle))
    end

    -- Sim 14.0: Forward ALIGNMENT CHECK
    local alignment = 0
    if speed > 5 then
        alignment = fwd:Dot(flatVel.Unit)
    end
    local isAligned = alignment > 0.8

    -- Drive Controls: Calculate target speed
    local goalSpeedBase = (throttle > 0) and Config.MaxSpeed or -Config.ReverseMaxSpeed
    
    -- SIM 18.0: STRICT REVERSE CAP
    if throttle < 0 then
        goalSpeedBase = math.clamp(goalSpeedBase, -Config.ReverseMaxSpeed, 0)
    end
    if throttle == 0 then goalSpeedBase = 0 end
    
    -- Momentum Reserve tracking (bleed extra speed slowly)
    if currentSpeed > momentumReserve then
        momentumReserve = currentSpeed
    else
        momentumReserve = math.max(Config.MaxSpeed, momentumReserve - dt * 2.0)
    end

    -- Goal Speed inherits the Momentum Reserve
    local goalSpeed = math.sign(goalSpeedBase) * math.max(math.abs(goalSpeedBase), momentumReserve)

    -- Sim 13.0: Deterministic Linear Ramp Logic
    if isDrifting then
        driftPowerRamp = math.min(1, driftPowerRamp + dt / 3.0) -- Strictly 3 second rise
    else
        driftPowerRamp = math.max(0, driftPowerRamp - dt / 2.0) -- 2 second decay
    end

    -- Sim 16.0/19.0: UNIFIED LINEAR INTEGRATOR (One Rate to Rule Them All)
    -- SIM 45.0: Momentum Lock — freeze integrator during airtime + landing window
    local momentumLocked = isAirborne or momentumLockTimer > 0
    if not momentumLocked then
        local speedDiff = goalSpeed - currentSpeed
        if throttle > 0 and speedDiff > 0 then
            -- Forward Accel: 12.0 or 15.0 (drift)
            local linearRate = isDrifting and 15 or 12 
            currentSpeed = currentSpeed + math.min(speedDiff, linearRate * dt)
        elseif throttle < 0 and speedDiff < 0 then
            -- SIM 19.0: REVERSE ACCEL HALVED (6.0)
            local reverseRate = 6.0
            currentSpeed = currentSpeed + math.max(speedDiff, -reverseRate * dt)
        else
            -- Deceleration (Keep it naturally heavy)
            currentSpeed = currentSpeed + speedDiff * (dt * 1.5) 
        end
    end
    -- (momentumLocked = true → currentSpeed frozen, physics handles velocity)
    
    -- DRAG CALCULATIONS (ChatGPT Fix)
    if dragForce then
        if math.abs(throttle) < 0.1 then
            local speedSq = vel.Magnitude * vel.Magnitude
            local fwdDrag = -fwd * (vel:Dot(fwd) * math.abs(vel:Dot(fwd))) * Config.RollingDragCoeff
            local sideDrag = -right * (vel:Dot(right) * math.abs(vel:Dot(right))) * (Config.RollingDragCoeff * 2)
            dragForce.Force = fwdDrag + sideDrag
        else
            dragForce.Force = Vector3.zero
        end
    end
    
    -- SLIP ANGLE & DYNAMICS 2.0 (ChatGPT Fix)
    local WORLD_UP = Vector3.yAxis
    local planarForward = (fwd - WORLD_UP * fwd:Dot(WORLD_UP)).Unit
    local yawAxis = WORLD_UP -- Fixed Stable Steering Axis
    
    local forwardSpeed = vel:Dot(planarForward)
    local lateralSpeed = vel:Dot(right)
    local currentYawVel = rootPart.AssemblyAngularVelocity:Dot(WORLD_UP)
    
    -- 1. Passive Yaw Damping (Beyblade Protection - consolidated)
    -- Beefed up to 50x to ensure the "weak" turns are stable and predictable
    local yawDampingForce = -currentYawVel * rootPart.AssemblyMass * 50 
    rootPart:ApplyAngularImpulse(WORLD_UP * yawDampingForce * dt)

    -- 2. Slip-Angle Steering Authority
    local slipAngle = math.atan2(lateralSpeed, math.max(math.abs(forwardSpeed), 1))
    local maxSlipRad = math.rad(Config.MaxSlipAngle)
    local slipRatio = math.abs(slipAngle) / maxSlipRad
    
    -- Authority Curve: Preservation over Removal
    local steerGain = 1 / (1 + slipRatio * slipRatio * 2.5)
    local effectiveSteer = steer * steerGain
    
    -- HARD SPEED CAP
    -- SIM 18.0: Enforce strict reverse cap of 15
    local minCap = -Config.ReverseMaxSpeed * 1.05
    local maxCap = Config.MaxSpeed * 1.1
    currentSpeed = math.clamp(currentSpeed, minCap, maxCap)
    
    -- VELOCITY CAP: Also cap actual velocity to reset drift speed
    if flatVel.Magnitude > Config.MaxSpeed * 1.15 then
        local targetVelMag = Config.MaxSpeed * 1.15
        local excessSpeed = flatVel.Magnitude - targetVelMag
        
        -- Use ApplyImpulse to brake excess speed instead of hard-overwriting AssemblyLinearVelocity
        -- Hard-overwriting instantly deletes any jump impulses queued earlier in the frame!
        local brakingImpulse = -flatVel.Unit * (excessSpeed * rootPart.AssemblyMass)
        rootPart:ApplyImpulse(brakingImpulse)
    end
    
    -- SIM 42.0: SMART WALL COLLISION
    local bumperOrigin = primary.Position + (up * 1.5)
    local bumperLen = 4.0
    
    -- HELPER: Ignore Characters (Humanoids) so hitting a player/dummy triggers a CRUSH, not a wall crash!
    local function isCharacter(hitInstance)
        local model = hitInstance:FindFirstAncestorOfClass("Model")
        return model and model:FindFirstChildOfClass("Humanoid") ~= nil
    end
    
    -- 1. FORWARD BUMPER: Checks in front of the chair
    local fwdBumperHit = workspace:Raycast(bumperOrigin, fwd * bumperLen, rayParams)
    local fwdBlocked = false
    if fwdBumperHit and not isCharacter(fwdBumperHit.Instance) then
        -- Ignore unanchored light physics objects (like traffic cones)
        if fwdBumperHit.Instance.Anchored or fwdBumperHit.Instance.AssemblyMass > 50 then
            -- Only treat as wall if the surface is STEEP (Normal.Y < 0.5)
            if fwd:Dot(fwdBumperHit.Normal) < -0.2 and fwdBumperHit.Normal.Y < 0.5 then
                fwdBlocked = true
            end
        end
    end
    
    -- 2. REAR BUMPER: Checks behind the chair
    local rearBumperHit = workspace:Raycast(bumperOrigin, -fwd * bumperLen, rayParams)
    local rearBlocked = false
    if rearBumperHit and not isCharacter(rearBumperHit.Instance) then
        if rearBumperHit.Instance.Anchored or rearBumperHit.Instance.AssemblyMass > 50 then
            if (-fwd):Dot(rearBumperHit.Normal) < -0.2 and rearBumperHit.Normal.Y < 0.5 then
                rearBlocked = true
            end
        end
    end
    
    -- 3. VELOCITY BUMPER: Checks direction of actual movement
    local moveDir = (speed > 1) and flatVel.Unit or fwd
    local velBumperHit = workspace:Raycast(bumperOrigin, moveDir * bumperLen, rayParams)
    local velBlocked = false
    if velBumperHit and not isCharacter(velBumperHit.Instance) and speed > 3 then
        if velBumperHit.Instance.Anchored or velBumperHit.Instance.AssemblyMass > 50 then
            if moveDir:Dot(velBumperHit.Normal) < -0.2 and velBumperHit.Normal.Y < 0.2 then
                velBlocked = true
            end
        end
    end
    
    -- 4. COLLISION RESPONSE
    -- SIM 42.0: Only block speed in the wall's direction
    -- FIX: Exclude from landing grace window! Suspension compression during landings can cause bumper rays to falsely hit terrain as strict walls!
    if landingGraceTimer <= 0 then
        if fwdBlocked and currentSpeed > 0 then
            currentSpeed = 0
        elseif rearBlocked and currentSpeed < 0 then
            currentSpeed = 0
        elseif velBlocked then
            currentSpeed = 0
        end
        
        -- Crash ejection for high-speed impacts
        -- Skip entirely while airborne, during landing grace, or during active teleport
        if not isAirborne and (fwdBlocked or velBlocked) then
            if speed > (Config.WallCrashThreshold or 50) then
                -- Suppress crash eject if server flagged us as teleporting
                local isTeleporting = seat:GetAttribute("_Teleporting")
                if isTeleporting then return end
                
                if fwdBlocked and fwdBumperHit then
                    print("⚠️ CRASH DETECTED ON PART: " .. tostring(fwdBumperHit.Instance.Name) .. " | PARENT: " .. tostring(fwdBumperHit.Instance.Parent.Name))
                end
                if velBlocked and velBumperHit then
                    print("⚠️ CRASH DETECTED ON PART: " .. tostring(velBumperHit.Instance.Name) .. " | PARENT: " .. tostring(velBumperHit.Instance.Parent.Name))
                end
                crashEject(seat, rootPart, vel, speed, fwd, right, fwdBlocked and "wall" or "velocity")
            end
        end
    end
    
    -- ═══ UPDATE DRIFT TRAILS ═══
    -- (Legacy Trail Logic Removed - Handled at line 640)
    
	-- Landing Grace Period
    if not isAirborne and wasAirborne then
        landingGraceTimer = 0.4   -- extended from 0.15 — prevents false wall/tilt eject right after landing
        
        -- SIM 45.0: Direction-aware sanity clamp
        -- FIX: Prevent violently reversing speed if currentSpeed fluctuated negative while flying.
        -- Match the momentum sign to actual flight velocity against the locked drive direction!
        local driveDir = lockedDriveDir or planarForward
        local sign = (flatVel:Dot(driveDir) < 0) and -1 or 1
        currentSpeed = sign * math.max(math.abs(currentSpeed), speed) -- Preserve 100% of speed upon landing
    end
    
    -- SIM 45.0: Momentum lock countdown (only ticks down while grounded)
    if not isAirborne and momentumLockTimer > 0 then
        momentumLockTimer = momentumLockTimer - dt
        if momentumLockTimer <= 0 then
            momentumLockTimer = 0
            lockedDriveDir = nil -- Release direction lock
        end
    end
    if landingGraceTimer > 0 then
        landingGraceTimer = math.max(0, landingGraceTimer - dt)
    end
    
    -- Ease-in grace multiplier (for steering/stabilizer, NOT drive force)
    -- math.clamp prevents negative multipliers (which flip forces backwards) when landingGrace is > 0.3s
    local graceMultiplier = math.clamp(1 - (landingGraceTimer / 0.3), 0, 1)
    -- Sim 22.0: Terrain Alignment Math (Ramp Pitching)
    -- SIM 45.0: Use averaged raycast hit normals for more reliable ramp detection
    local targetNormal = Vector3.new(0, 1, 0)
    if not isAirborne then
        local normalSum = Vector3.zero
        local normalCount = 0
        for _, n in pairs(hitNormals) do
            normalSum = normalSum + n
            normalCount = normalCount + 1
        end
        if normalCount > 0 then
            targetNormal = (normalSum / normalCount).Unit
        end
        -- Flip if pointing down
        if targetNormal.Y < 0 then targetNormal = -targetNormal end
    end
    
    -- Smooth the transition
    smoothedNormal = smoothedNormal:Lerp(targetNormal, dt * 12)

    -- STABILIZER LOGIC (Zero-Latence Recovery)
    if stabilizer then
        -- Sim 22.0: Align to Terrain Normal
        stabilizer.PrimaryAxis = smoothedNormal
        
        -- Aggressive Ramp: Use logic to snap to 100% stiffness faster if we are near upright
        local uprightDot = rootPart.CFrame.UpVector:Dot(smoothedNormal)
        local landingAggression = (uprightDot > 0.85) and 3 or 1
        
        stabilizer.Responsiveness = math.clamp(40 * graceMultiplier * landingAggression, 5, 40)
        
        -- ANTI-DIP: Boost pitch correction during landing to prevent "falling back"
        if landingGraceTimer > 0 then
            stabilizer.MaxTorque = rootPart.AssemblyMass * 800 -- Double torque to hold the line
        else
            stabilizer.MaxTorque = rootPart.AssemblyMass * 400
        end
    end
    -- STABILITY LOCK: Set 20% floor (0.2) to prevent "loose legs" on landing
    graceMultiplier = math.clamp(graceMultiplier * graceMultiplier, 0.2, 1) 
	
    -- FORCE UPDATES: Planar Projection (Dynamics 2.0 Stability)
    -- SIM 45.0: Use locked direction during momentum lock, else current forward
	moveForce.LineDirection = lockedDriveDir or planarForward
	moveForce.LineVelocity = currentSpeed
    
    -- DYNAMIC ATTACHMENT FIX: When standing still, pull from Center of Mass to prevent pitch stutter/jitter
    if seatThrottle == 0 and speed < 2 then
        local trueCom = moveForce.Parent:FindFirstChild("TrueCOM_Attachment")
        if trueCom then moveForce.Attachment0 = trueCom end
    else
        moveForce.Attachment0 = moveForce.Parent:FindFirstChild("BaseAttachment")
    end
    
    -- DRIVE FORCE & ROLLING RESISTANCE
    -- SIM 45.0: During momentum lock, keep force active even in air (prevents bounce dead zone)
    local safeMass = rootPart.AssemblyMass
    if safeMass == math.huge or safeMass == 1/0 then safeMass = 200 end
    
    if isAirborne and momentumLockTimer <= 0 then
        -- Only zero force during sustained flight (no momentum lock)
        moveForce.MaxForce = 0
    elseif momentumLockTimer > 0 then
        -- Full force during momentum lock (ground OR air bounces)
        moveForce.MaxForce = safeMass * 400
    else
        moveForce.MaxForce = safeMass * 400 * graceMultiplier
    end
	
    -- Sim 2.5 Steering Split: Normal (Stable) vs Drift (Performance)
    local speedRatio = math.clamp(speed / Config.MaxSpeed, 0, 1)
    local antiToppleScale = 1 - (speedRatio * 0.45) -- Keep 55% authority
    local steeringMultiplier = effectiveShiftHeld and 0.4 or 0.2
    local actualTurnTorque = Config.TurnTorque * antiToppleScale * steeringMultiplier
    
    -- ROTATIONAL AUTHORITY
    turnForce.MaxTorque = actualTurnTorque * rootPart.AssemblyMass

    if not isAirborne and isDrifting then
        actualTurnTorque = actualTurnTorque * 1.5 -- Reduced drift kick for stability
    end

	-- Sim 5.1: Increased cap from 8 to 12 for better stable responsiveness
	local targetTurnRate = math.clamp(-effectiveSteer * (Config.TurnSpeed * steeringMultiplier) * graceMultiplier, -12, 12)
    
    -- HYBRID TURNING 3.1 (Input-Driven Handoff)
    -- Shift = Drift Performance (Impulse), Normal = Solid Cruiser (Constraint)
    -- Sim 7.0: Drift Floor synced to 35 studs/s
    local targetHybrid = (effectiveShiftHeld and steer ~= 0 and (not isAirborne or speed < 25) and speed > 25) and 1 or 0
    
    -- Asymmetric ramp: FAST entry (no delay), smooth exit (no jab)
    local hybridRampSpeed = (targetHybrid > steadyHybrid) and 15 or 6
    steadyHybrid = steadyHybrid + (targetHybrid - steadyHybrid) * dt * hybridRampSpeed
    local hybridFactor = steadyHybrid
    
    -- Low Speed / Normal: Constraint authority (Cruiser mode)
    if hybridFactor < 0.98 then
        turnForce.Enabled = true
        turnForce.AngularVelocity = WORLD_UP * targetTurnRate
        -- Scale constraint power down as impulse power climbs
        turnForce.MaxTorque = actualTurnTorque * rootPart.AssemblyMass * (1 - hybridFactor) * (isAirborne and Config.AirControl or 1)
    else
        turnForce.Enabled = false
    end
    
    -- High Performance: Pure Torque authority (Drift mode)
    if hybridFactor > 0.02 then
        -- Sim 4.0: Implement SteadySteer to prevent 360-spin on rapid flip
        steadySteer = steadySteer + (effectiveSteer - steadySteer) * dt * 4 
        
        -- Fallback mass to prevent arithmetic errors if rig is malformed
        local safeMass = rootPart.AssemblyMass
        if safeMass == math.huge or safeMass == 1/0 then safeMass = 200 end -- Default fallback
        
        -- Sim 4.1: Widen drift radius by significantly lowering torque impulse scaling during drift
        local driftTurnScale = effectiveShiftHeld and 1.8 or 5.0 
        
        -- SIM 38.0: ZERO yaw torque in air OR during jump window
        -- Removed landingGrace check for immediate steering response
        if not isAirborne and jumpStabilityTimer <= 0 then
            local torqueMagnitude = -steadySteer * actualTurnTorque * safeMass * driftTurnScale
            local yawImpulse = WORLD_UP * torqueMagnitude * hybridFactor * dt
            rootPart:ApplyAngularImpulse(yawImpulse)
        end
    end
    
    -- Reduced air control
    if isAirborne then
        turnForce.MaxTorque = actualTurnTorque * Config.AirControl * rootPart.AssemblyMass
    else
        turnForce.MaxTorque = actualTurnTorque * rootPart.AssemblyMass * graceMultiplier
    end

	-- VIRTUAL ANTI-ROLL & BODY ROLL (Stabilizer - Option C)
	if stabilizer then
		-- SIM 39.0/40.1: Keep chair LEVEL but ALLOW SPIN
		if isAirborne or jumpStabilityTimer > 0 then
			-- Keep stabilizer ACTIVE but forcing UPRIGHT (no lean)
			stabilizer.Enabled = true
			stabilizer.MaxTorque = rootPart.AssemblyMass * 3000
			stabilizer.Responsiveness = 15
			stabilizer.PrimaryAxis = WORLD_UP
			visualRoll = 0
			
			-- SIM 40.1: MAINTAIN captured spin rate, damp only pitch/roll
			local angVel = rootPart.AssemblyAngularVelocity
			rootPart.AssemblyAngularVelocity = Vector3.new(
				angVel.X * 0.85, -- Damp pitch
				airSpinRate,     -- FORCE captured spin rate!
				angVel.Z * 0.85  -- Damp roll
			)
		else
			-- SIM 40.1: Reset spin rate on landing
			airSpinRate = 0
            stabilizer.Enabled = true
            
			-- STABILIZER RAMP
			stabilizer.MaxTorque = rootPart.AssemblyMass * 5000 * graceMultiplier
            stabilizer.Responsiveness = 20 * graceMultiplier
            
            -- SIM 44.0: LATERAL ACCELERATION TILT (ChatGPT Architecture)
            -- Rule: NEVER derive tilt from steering input. Use physics.
            -- lateralAccel = yawRate × forwardSpeed
            local yawRate = rootPart.AssemblyAngularVelocity.Y
            local forwardSpeed = vel:Dot(fwd)
            local lateralAccel = yawRate * forwardSpeed
            
            -- Lean angle: clamp to max, scale by accel
            -- Only tilt during drift, not normal turning
            local maxLean = math.rad(50) -- Reduced max lean from 70 to 50
            local lean = 0
            if effectiveDrift then
                lean = math.clamp(lateralAccel / 15, -1, 1) * maxLean -- Soften the lean curve
            end
            
            -- Smooth the lean (prevents jitter)
            visualRoll = visualRoll + (lean - visualRoll) * dt * 8
            
            -- Apply lean to stabilizer target via AlignOrientation
            -- Use smoothedNormal (terrain-aware) as base, not WORLD_UP
            local leanCF = CFrame.fromAxisAngle(planarForward, -visualRoll)
            local targetAxis = leanCF * smoothedNormal
            stabilizer.PrimaryAxis = stabilizer.PrimaryAxis:Lerp(targetAxis, dt * 10)
            
            -- SIM 44.0: HYSTERESIS EJECTION (time-over-threshold)
            local ejectAngle = math.rad(100) -- Must sustain 100+ degrees
            if math.abs(visualRoll) > ejectAngle and speed > 30 and tiltGraceTimer <= 0 then
                tiltEjectTimer = tiltEjectTimer + dt
            else
                -- [REMOVED TILT EJECT PER USER REQUEST]
            end
		end
	end

	-- 4. Drift / Grip Logic
	-- vel/fwd/speed defined at top
    -- isDriftingNow moved to top in Sim 12.0
	
	-- PASSIVE FRICTION (VectorForce)
	if isAirborne then
		sideForce.Force = Vector3.zero 
		sideGripRamp = 0
	else
		sideGripRamp = math.min(1, sideGripRamp + dt / 0.25)
		local sideGripMultiplier = graceMultiplier * sideGripRamp
        
        -- ChatGPT Fix: Smooth the grip transition to prevent "Tripping" on drift exit
        -- Sim 4.1: Force PLANAR friction (Y=0) to stop the breakdance bug
        local planarRight = (right - WORLD_UP * right:Dot(WORLD_UP)).Unit
        
        -- Sim 4.0: Extreme low drift grip for "Ice" feel (0.05 from config)
        -- SIM 45.0: Use effectiveDrift (includes carry timer) to prevent grip snap
        local baseGrip = effectiveDrift and Config.DriftGrip or 50
        local targetMaxFriction = rootPart.AssemblyMass * baseGrip
        
        -- Smooth the friction clamp (don't snap from 0.05 instantly)
        -- Sim 8.0: Much slower recovery (dt * 0.5) to prevent the "motorcycle stop"
        currentSideFriction = currentSideFriction + (targetMaxFriction - currentSideFriction) * dt * 0.5
        
        local restoringForce = math.abs(lateralSpeed) * rootPart.AssemblyMass * 20
        local finalFrictionMagnitude = math.min(restoringForce, currentSideFriction * sideGripMultiplier)
        
        if momentumLockTimer > 0 then
            sideForce.Force = Vector3.zero
            -- Sneakily snap friction to target so it doesn't build up massive grip while in the air
            currentSideFriction = targetMaxFriction
        elseif math.abs(lateralSpeed) > 0.05 then
            sideForce.Force = (-planarRight * math.sign(lateralSpeed)) * finalFrictionMagnitude
        else
            sideForce.Force = Vector3.zero
        end
	end
	
	isDrifting = isDriftingNow
    
    -- Track state for next frame
    wasAirborne = isAirborne
    
    -- Body Roll handled in Stabilizer block (Option C)
    
    -- Note: Jump processing moved to earlier in frame (see line ~320)
    
    if jumpStabilityTimer > 0 then
        jumpStabilityTimer = math.max(0, jumpStabilityTimer - dt)
    end
    
    if jumpCooldownTimer > 0 then
        jumpCooldownTimer = math.max(0, jumpCooldownTimer - dt)
    end
    -- AUDIO: Continuous "Voom" Loop (DISABLED PER USER REQUEST)
    if voomSound and voomSound.IsPlaying then
        voomSound:Stop()
    end
    -- if voomSound then
    --     local targetSpeed = math.min(currentSpeed, VOOM_MAX_SPEED) -- Cap at 40 per request
        
    --     if targetSpeed > VOOM_MIN_SPEED and not isShiftHeld then
    --         if not voomSound.IsPlaying then
    --             voomSound.Looped = true
    --             voomSound:Play()
    --         end
            
    --         -- PITCH SCALING (Medium Engine - Balance between Airplane and Tractor)
    --         local t = math.clamp((targetSpeed - VOOM_MIN_SPEED) / (VOOM_MAX_SPEED - VOOM_MIN_SPEED), 0, 1)
            
    --         -- Pitch: 0.7 -> 1.0 (Caps at normal pitch, starts a bit low)
    --         voomSound.PlaybackSpeed = 0.7 + t * 0.3
            
    --         -- Volume: 0.3 -> 0.6
    --         voomSound.Volume = 0.3 + t * 0.3
            
    --         -- Basic Looping (No custom trimming needed for an engine loop)
            
    --     else
    --         if voomSound.IsPlaying then
    --             voomSound:Stop() -- Or fade out
    --         end
    --     end
    -- end

    -- ═══ ANIMATION UPDATE ═══
    -- Use isDrifting (persistent state) for smoother transitions
    updateAnimations(dt, throttle, speed, steer, isDrifting)
end)

-- ═══ VISUAL UPDATE LOOP (Post-Physics) ═══
local visualConnection
visualConnection = RunService.Heartbeat:Connect(function(dt)
    -- FIX: Use 'chairModel' (variable in scope), not 'currentChair' (nil)
    -- FIX: Use 'chairModel' (variable in scope), not 'currentChair' (nil)
    if not chairModel then
        -- Clean up fake wheel blur if dismounted
        if _G.blurWheels then
            for _, wheelData in ipairs(_G.blurWheels) do
                if wheelData.part then wheelData.part.Transparency = 1 end
                if wheelData.spokes then
                    for _, spoke in ipairs(wheelData.spokes) do
                        spoke.Transparency = 1
                    end
                end
            end
        end
        return
    end

    -- Check Drift (Re-evaluate for visuals)
    local showTrails = false

    if isDrifting and not isAirborne and (math.abs(currentSpeed) > 10) then
        showTrails = true
    end


    -- AUDIO: Tire Squeal Loop (DISABLED PER USER REQUEST)
    if driftSound and driftSound.IsPlaying then
        driftSound:Stop()
    end
    -- if driftSound and driftSoundLength > 0 then
    --     if showTrails then
    --         if not driftSound.IsPlaying then 
    --             driftSound:Play()
    --             driftSound.TimePosition = LOOP_TRIM_START -- Start at trim
    --         end
            
    --         -- Custom Loop Check (Cut End)
    --         local loopEnd = math.max(0, driftSoundLength - LOOP_TRIM_END)
    --         if driftSound.TimePosition >= loopEnd then
    --             driftSound.TimePosition = LOOP_TRIM_START
    --         end
            
    --         -- PITCH: Smooth scaling (Lower Base = Deep Squeal)
    --         local speedFactor = math.clamp(math.abs(currentSpeed) / 100, 0, 0.4)
    --         driftSound.PlaybackSpeed = 0.5 + speedFactor -- Was 0.8
            
    --         -- VOLUME: Fade In
    --         driftSound.Volume = math.min(driftSound.Volume + dt * 5, 0.15) -- Max Volume 0.15 (User requested lower) 
    --     else
    --         -- Fade Out
    --         driftSound.Volume = math.max(driftSound.Volume - dt * 5, 0)
    --         if driftSound.Volume <= 0 and driftSound.IsPlaying then
    --             driftSound:Stop()
    --         end
    --     end
    -- end
    
    -- Calculate Tilt for Directional Sparks
    local rightTilt = rootPart.CFrame.RightVector.Y
    local now = os.clock() -- High precision timer
    
    for _, dtrail in ipairs(driftTrails) do
         local tireGrounded = false
         local groundThreshold = Config.SusRestLength + 1.0 -- 1 stud tolerance
         if showTrails then
             if dtrail.side == "RR" then
                 -- Right Wheel uses RR suspension ray
                 tireGrounded = (wheelDistances["RR"] and wheelDistances["RR"] <= groundThreshold)
             elseif dtrail.side == "RL" then
                 -- Left Wheel uses RL suspension ray
                 tireGrounded = (wheelDistances["RL"] and wheelDistances["RL"] <= groundThreshold)
             else
                 tireGrounded = true -- Fallback for core/center attachments
             end
         end
         
         -- 1. Constantly Snap Base Attachments to Ground
         local wPos = dtrail.wheel.WorldPosition
         local floorY = wPos.Y - 1.5 -- Extreme fallback
         
         -- Use specific wheel suspension distance if available
         if wheelDistances and wheelDistances[dtrail.side] then
             local dist = wheelDistances[dtrail.side]
             if dist <= groundThreshold then
                 floorY = wPos.Y - dist
             end
         end
         
         local attachPos = Vector3.new(wPos.X, floorY + 0.1, wPos.Z)
         
         -- PURE POSITION UPDATE (Fixes the Roblox "Triangle Spike" triangulation glitch)
         dtrail.a0.WorldPosition = attachPos - (rootPart.CFrame.RightVector * 0.25)
         dtrail.a1.WorldPosition = attachPos + (rootPart.CFrame.RightVector * 0.25)
         
         -- 2. TOGGLE TRAIL VISIBILITY
         if tireGrounded and not dtrail.wasGrounded then
             if dtrail.activeTrail then
                 dtrail.activeTrail.Enabled = true
             end
         elseif not tireGrounded and dtrail.wasGrounded then
             if dtrail.activeTrail then
                 dtrail.activeTrail.Enabled = false
             end
         end
         dtrail.wasGrounded = tireGrounded
         
         -- 4. ARCADE BURST LOGIC (Mario Kart Style)
         -- We do NOT toggle .Enabled. We Pulse .Emit()
         if dtrail.emitters and tireGrounded then
             local shouldEmit = true
             
             -- Frequency Control (Burst Rate)
             -- Emit every ~0.08s (12.5Hz) for "Machine Gun" effect
             if shouldEmit and (now - (dtrail.lastEmit or 0) > 0.08) then
                 dtrail.lastEmit = now
                 
                 -- EMIT BURST
                 -- dtrail.emitters[1] is Core
                 -- dtrail.emitters[2] is Glow
                 dtrail.emitters[1]:Emit(20) 
                 dtrail.emitters[2]:Emit(5)  
             end
         end
     end -- Closes driftTrails loop
     
     -- ═══ BULLETPROOF PROCEDURAL MOTION BLUR ("SONIC FEET") ═══
     if _G.windActive and rootPart then
         local absSpeed = math.abs(currentSpeed)
         -- Only trigger at high speeds to simulate sonic blur
         if absSpeed > 15 then
             local rateScale = math.clamp((absSpeed - 15) / 45, 0, 1)
             
             -- Spawn multiple trails per frame depending on speed (increased for fuller effect)
             local spawnCount = math.floor(2 + (rateScale * 5))
             
             for i = 1, spawnCount do
                 -- Randomly pick left or right wheel side
                 local sideOffset = (math.random() > 0.5) and 1.8 or -1.8
                 -- Lock the streaks directly under the physical wheels
                 local rx = sideOffset + (math.random() * 0.2 - 0.1) -- Keep very tight laterally
                 -- The wheels sit roughly 1.5 studs below the seat, and have a radius of 1.5, so the floor contact is -3.0
                 local ry = -2.9 + (math.random() * 0.3 - 0.15) -- Scrape the absolute bottom of the tires
                 local rz = 1.3 + (math.random() * 1.5 - 0.75)  -- Match the exact center of the wheels
                 
                 local startPos = rootPart.CFrame * Vector3.new(rx, ry, rz)
                 
                 -- Create custom wind streak
                 local trail = Instance.new("Part")
                 trail.Name = "CustomWindBlur"
                 trail.Anchored = true
                 trail.CanCollide = false
                 trail.Massless = true
                 trail.Material = Enum.Material.Neon
                 trail.Color = Color3.fromRGB(200, 230, 255) -- Icy blue/white
                 
                 -- Start size (super thin, super short)
                 local baseWidth = (0.02 + (math.random() * 0.05)) * math.max(0.1, rateScale)
                 trail.Size = Vector3.new(baseWidth, baseWidth, 0.2 + (rateScale * 0.8))
                 
                 -- Start completely invisible at exactly speed 15, smoothly becoming opaque 
                 trail.Transparency = 1 - (rateScale * 0.8) 
                 
                 -- Align to chair's direction
                 trail.CFrame = CFrame.lookAt(startPos, startPos + rootPart.CFrame.LookVector)
                 trail.Parent = workspace
                 
                 -- Tween the trail shooting backward, stretching out, and fading
                 local TweenService = game:GetService("TweenService")
                 local tInfo = TweenInfo.new(
                     0.25 + (math.random() * 0.1), -- Lightning fast
                     Enum.EasingStyle.Quad,
                     Enum.EasingDirection.Out
                 )
                 
                 -- Shoot backward relative to chair orientation, distance scales with speed, but kept much shorter
                 local endPos = startPos - (rootPart.CFrame.LookVector * (0.5 + (rateScale * 3)))
                 
                 local goal = {
                     CFrame = CFrame.lookAt(endPos, endPos + rootPart.CFrame.LookVector),
                     Size = Vector3.new(0, 0, 0.2 + (rateScale * 2)), -- Stretch out only a tiny bit
                     Transparency = 1 -- Fade out completely
                 }
                 
                 local tween = TweenService:Create(trail, tInfo, goal)
                 tween:Play()
                 
                 -- Clean up exactly when tween finishes
                 game:GetService("Debris"):AddItem(trail, 0.4)
             end
         end
         
         
         -- 🌟🌟🌟 FAKE PS2 WHEEL MOTION BLUR OVERLAYS 🌟🌟🌟
         local primary = chairModel.PrimaryPart
         if _G.blurWheels and primary then
             local currentAbsSpeed = math.abs(currentSpeed)
             for _, wheelData in ipairs(_G.blurWheels) do
                 local disc = wheelData.part
                 if disc then
                     -- Compute the disc's world CFrame (with spin)
                     wheelData.spinAngle = (wheelData.spinAngle + math.rad((currentAbsSpeed * dt) * 70)) % (math.pi * 2)
                     local discCF = primary.CFrame * wheelData.baseOffset * CFrame.Angles(wheelData.spinAngle, 0, 0)
                     disc.CFrame = discCF
                     
                     if currentAbsSpeed > 8 then
                         local blurScale = math.clamp((currentAbsSpeed - 8) / 30, 0, 1)
                         -- Fade in the dark transparent background disc
                         disc.Transparency = 1 - (blurScale * 0.5)
                         
                         -- Fade in and position spokes
                         for si, spoke in ipairs(wheelData.spokes) do
                             spoke.Transparency = 1 - (blurScale * 0.8)
                             if wheelData.spokeAngles and wheelData.spokeAngles[si] then
                                 spoke.CFrame = discCF * wheelData.spokeAngles[si]
                             end
                         end
                     else
                         -- Hide when slow/stopped
                         disc.Transparency = 1
                         for si, spoke in ipairs(wheelData.spokes) do
                             spoke.Transparency = 1
                             if wheelData.spokeAngles and wheelData.spokeAngles[si] then
                                 spoke.CFrame = discCF * wheelData.spokeAngles[si]
                             end
                         end
                     end
                 end
             end
         end
     end

     -- Note: Visual wheel rotation disabled due to baked mesh limitations.
end) -- Closes Heartbeat Loop

    -- Note: Jump processing moved to earlier in frame (see line ~320)
-- (Removed extra end)

-- RESET MOMENTUM ON ROUND START
local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 10)
if GameEvent then
    GameEvent.OnClientEvent:Connect(function(eventName, data)
        if eventName == "round_start" then
            -- Removed delayed momentum wipe (Server's killMomentum handles teleport wiping)
            -- Resetting here caused a 'freeze' feeling 0.5s into the round.
        elseif eventName == "round_end" then
            currentSpeed = 0
            isDrifting = false
            driftTime = 0
            momentumLockTimer = 0
            driftCarryTimer = 0
            lockedDriveDir = nil
            
            -- Stop physical movement
            if rootPart then
                rootPart.AssemblyLinearVelocity = Vector3.zero
                rootPart.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)
end

local hasSeatedOnce = false

-- Reset hasSeatedOnce when character respawns to avoid immediate Anti-Walk triggers
player.CharacterAdded:Connect(function()
    hasSeatedOnce = false
end)

-- ANTI-WALK SYSTEM
-- Detects if the player is unseated and trying to walk, and forces them into the crawl state
local antiWalkTimer = 0
RunService.Heartbeat:Connect(function(dt)
    if not player.Character then return end
    local char = player.Character
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end
    
    if hum.Health <= 0 then return end
    
    -- If they have a seat, mark that they have been seated at least once and return
    if hum.SeatPart then
        hasSeatedOnce = true
        antiWalkTimer = 0
        return 
    end
    
    -- Don't trigger if they are ragdolled, haven't ever sat down (spawning), or already crawling
    if hum.PlatformStand or not hasSeatedOnce or _G.ragdollCollisionLoop or root:FindFirstChild("CrawlMover") then 
        antiWalkTimer = 0
        return 
    end
    
    -- Teleport Guard
    local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if chair then
        local vSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
        if vSeat and vSeat:GetAttribute("_Teleporting") then 
            antiWalkTimer = 0
            return 
        end
    end
    
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics or state == Enum.HumanoidStateType.Jumping then
        antiWalkTimer = antiWalkTimer + (dt or 0.016)
        if antiWalkTimer > 0.8 then
            print("[Anti-Walk] Forcing player into crawl state!")
            hasSeatedOnce = false -- Reset so it waits for them to sit again (prevents spam loops if they get up repeatedly)
            crashEject(nil, root, Vector3.zero, 0, root.CFrame.LookVector, root.CFrame.RightVector, "anti_walk")
            antiWalkTimer = 0
        end
    else
        antiWalkTimer = 0
    end
end)
