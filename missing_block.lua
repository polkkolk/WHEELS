    
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
    if seat == currentSeat and trailsSetUp then
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
    if gpe then return end -- Ignore typing
    
	if input.KeyCode == Enum.KeyCode.Space then
        -- FIX: Don't latch jump if we aren't even in the chair!
        -- This prevents the "Sit -> Immediate Jump" bug if you jumped while walking
        if not humanoid.SeatPart then return end
        
		jumpRequested = true  -- Latch ON (survives any frame rate)
		print("⌨️ Jump requested (latched)")
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isShiftHeld = true
    -- DEBUG: Manual Dismount (User Request)
    elseif input.KeyCode == Enum.KeyCode.G then
        local seat = humanoid.SeatPart
        if seat then
            print("G KEY: Manual Eject")
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


-- State Variables
local landingGraceTimer = 0 -- ChatGPT Fix: Prevent post-hop torque spikes
local wasAirborne = false
local smoothedNormal = Vector3.new(0, 1, 0) -- Sim 22.0: Ramp Alignment

-- Raycast Params
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Main Physics Loop
RunService.Heartbeat:Connect(function(dt)
    if not updatePhysicsComponents() then 
        if wasSeated then
            print("🚪 DISMOUNT CLEANUP")
            wasSeated = false
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
    if not wasSeated then
        print("🔄 STATE RESET (Fresh Sit)")
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
                    -- Restore driving friction
                    part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5, 100, 1)
                end
            end
            local primary = chairModel.PrimaryPart
