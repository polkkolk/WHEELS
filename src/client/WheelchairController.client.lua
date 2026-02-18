local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Helpers
local WORLD_UP = Vector3.yAxis
local function smoothstep(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Configuration
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WheelchairConfig"))
local CrashEjectEvent = ReplicatedStorage:WaitForChild("CrashEjectEvent", 10)

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

-- SIM 46.0: Crash eject function (unified ejection with ragdoll fling)
local function crashEject(seat, rootPart, vel, speed, fwd, right, reason)
    if not CrashEjectEvent then return seat:Sit(nil) end
    
    local flatVel = Vector3.new(vel.X, 0, vel.Z)
    
    -- Compute desired VELOCITY CHANGE (not impulse — server applies mass)
    local flingVelocity
    local speedFactor = math.clamp(speed / 50, 0.3, 1.5)
    
    if reason == "wall" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = flingDir * 8 * speedFactor + Vector3.new(0, 5 * speedFactor, 0)
    elseif reason == "tilt" then
        local sideDir = right * (math.random() > 0.5 and 1 or -1)
        flingVelocity = sideDir * 5 * speedFactor + Vector3.new(0, 4 * speedFactor, 0)
    elseif reason == "velocity" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = flingDir * 6 * speedFactor + Vector3.new(0, 5 * speedFactor, 0)
    else
        flingVelocity = Vector3.new(0, 4, 0)
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
        end
        
        -- Only disconnect AFTER ragdoll was active and PlatformStand went back to false
        if ragdollActivated and not humanoid.PlatformStand then
            if collisionLoop then collisionLoop:Disconnect() end
            return
        end
        
        -- Force all limbs to collide (Humanoid resets R15 limbs to CanCollide=false every frame)
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and not (part.Parent:IsA("Accessory") or part.Parent:IsA("Accoutrement")) then
                    if part.Name ~= "HumanoidRootPart" then
                        part.CanCollide = true
                    end
                end
            end
        end
    end)
    
    CrashEjectEvent:FireServer({
        reason = reason,
        flingVelocity = flingVelocity, -- Raw velocity, NOT impulse
        speed = speed,
    })
    print("💥 CRASH EJECT!", reason, "| Speed:", math.floor(speed))
end

-- Attachments
local corners = {"FL", "FR", "RL", "RR"}
local attachments = {}

-- State
local isSpaceHeld = false -- Jump/Hop
local isShiftHeld = false -- Handbrake/Drift

-- Setup Character
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	suspensionForces = {}
	attachments = {}
end)

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
		
		return false 
	end
	
	local chairModel = seat.Parent
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


-- Input Handlers (Frame-Independent Jump - ChatGPT Fix)
local visualRoll = 0 -- Visual body roll angle
local jumpRequested = false  -- LATCHED REQUEST (not timer)
local sideGripRamp = 0 -- ChatGPT Fix: Rate-limit side grip to prevent tripping
local jumpStabilityTimer = 0 -- ChatGPT Fix: Temporarily neutralize rotation during jump

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		jumpRequested = true  -- Latch ON (survives any frame rate)
		print("⌨️ Jump requested (latched)")
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isShiftHeld = true
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
        wasSeated = false -- SIM 29.0: Mark as not seated
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
	local chairModel = seat.Parent
	local primary = chairModel.PrimaryPart
	
	-- Filter Character & Chair
	rayParams.FilterDescendantsInstances = {character, chairModel}
    
    local steer = seat.Steer
    local throttle = seat.Throttle
    
    -- STATE VARIABLES (Moved Up)
	local vel = rootPart.AssemblyLinearVelocity
	local fwd = primary.CFrame.LookVector
    local up = primary.CFrame.UpVector
    local right = primary.CFrame.RightVector
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
	
	-- 1. Suspension Logic (Raycast)
    -- Simple symmetric suspension for stability
    
    -- Ground Detection Tracking
    local anyRayHit = false
    local minDist = math.huge
    local hitPositions = {} -- Sim 22.0: Track points for normal calculation
    local hitNormals = {} -- SIM 45.0: Track surface normals for ramp alignment
    
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
            
			local dist = result.Distance
            local activeRest = Config.SusRestLength
            
			local offset = activeRest - dist
			
			-- SIM 35.0: CHATGPT SUSPENSION FIX
			-- Fix 1: Damping opposes motion (fSpring - fDamp is correct)
			-- Fix 2: Allow negative force for critical damping
			local fSpring = 0
			if offset > 0 then
				fSpring = Config.SusStiffness * offset
			end
			
			local localVel = rootPart:GetVelocityAtPosition(origin)
			local verticalSpeed = localVel:Dot(att.WorldCFrame.UpVector)
			local fDamp = Config.SusDamping * verticalSpeed
			
			-- ChatGPT: Allow negative force, clamp within limits
			local totalY = fSpring - fDamp
			
			-- Clamp: Allow SMALL negative (rebound damping) to prevent bounce
			-- SIM 36.0: Reduced maxRebound from 150 to 30 to prevent sinking
			local maxRebound = rootPart.AssemblyMass * 30  -- Max downward force (reduced)
			local maxLift = rootPart.AssemblyMass * 500    -- Max upward force
			totalY = math.clamp(totalY, -maxRebound, maxLift)
			
			force = Vector3.new(0, totalY, 0)
		end
		
		-- SIM 38.0: Suspension control
		-- Use wasAirborne since isAirborne isn't calculated yet
		if wasAirborne then
			force = Vector3.zero -- Hard off in air
		elseif jumpStabilityTimer > 0 then
			local suspensionAlpha = 1 - (jumpStabilityTimer / 0.25)
			suspensionAlpha = math.clamp(suspensionAlpha, 0, 1)
			force = force * suspensionAlpha
		end
		
		if suspensionForces[name] then
			suspensionForces[name].Force = force
		end
	end
	
    -- 5. Detect Grounding & Airborne State (ChatGPT Fix: Correct Order)
    local groundDist = anyRayHit and minDist or 100
    local tolerance = 1.5
    local isGrounded = anyRayHit and (minDist < Config.SusRestLength + tolerance)
	local isAirborne = not isGrounded

    -- SIM 45.0: Detect edge-fall (went airborne without jumping)
    -- Capture momentum lock for non-jump airborne transitions too
    if isAirborne and not wasAirborne then
        if momentumLockTimer <= 0 then -- Don't override if jump already set it
            lockedDriveDir = flatVel.Magnitude > 1 and flatVel.Unit or planarForward
            momentumLockTimer = 0.3
        end
        if isDrifting and driftCarryTimer <= 0 then
            driftCarryTimer = 0.35
        end
    end

    -- SIM 37.0: JUMP PROCESSING - MUST BE BEFORE STEERING
    -- This ensures jumpStabilityTimer is set BEFORE yaw impulse checks
    if jumpRequested and not isAirborne then
        jumpRequested = false
        print("🚀 JUMPING! Speed:", math.floor(speed), "Steer:", steer)
        
        -- Set timer FIRST (before any steering checks this frame)
        jumpStabilityTimer = 0.25
        
        -- SIM 45.0: Capture drive direction at takeoff
        lockedDriveDir = flatVel.Magnitude > 1 and flatVel.Unit or planarForward
        momentumLockTimer = 0.3 -- Preserve momentum for 300ms after landing
        
        -- SIM 45.0: Capture drift state for grip carry
        if isDrifting then
            driftCarryTimer = 0.35
        end
        
        -- SIM 40.1: Capture steer input for spin (ONLY when drifting)
        if isShiftHeld or isDrifting then
            local spinMultiplier = 0.8
            airSpinRate = -steer * Config.TurnSpeed * spinMultiplier
        else
            airSpinRate = 0 -- No spin on normal jumps
        end
        
        -- Clear pitch/roll, apply spin rate if drifting
        rootPart.AssemblyAngularVelocity = Vector3.new(0, airSpinRate, 0)
        
        -- Disable stabilizer initially (re-enabled in stabilizer block)
        if stabilizer then 
            stabilizer.Enabled = false 
            stabilizer.MaxTorque = 0
        end
        
        -- Apply jump force
        local jumpForce = rootPart.AssemblyMass * Config.JumpImpulse
        rootPart:ApplyImpulse(Vector3.new(0, jumpForce, 0))
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
	if not isAirborne and speed > currentDriftFloor and ((isShiftHeld and steer ~= 0) or (slipAngle > Config.DriftThreshold and speed > 20)) then
		isDriftingNow = true
		driftTime = driftTime + dt
	else
		driftTime = 0
	end
    isDrifting = isDriftingNow -- Update persistent state immediately
    
    -- SIM 45.0: Track drift carry timer
    if isDriftingNow and not isAirborne then
        driftCarryTimer = 0.35 -- Refresh while actively drifting on ground
    end
    if driftCarryTimer > 0 then
        driftCarryTimer = math.max(0, driftCarryTimer - dt)
    end
    local effectiveDrift = isDriftingNow or driftCarryTimer > 0
    
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
                att0.Parent = primary
                
                local att1 = Instance.new("Attachment")
                att1.Name = wheelName .. "_TrailR"
                att1.Parent = primary
                
                local trail = Instance.new("Trail")
                trail.Name = wheelName .. "_DriftTrail"
                trail.Attachment0 = att0
                trail.Attachment1 = att1
                trail.Lifetime = TRAIL_LIFETIME
                trail.MinLength = 0
                trail.FaceCamera = false
                trail.LightEmission = 0
                trail.LightInfluence = 1
                trail.Color = ColorSequence.new(Color3.fromRGB(35, 35, 35)) -- Slightly lighter gray
                trail.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.3),  -- Start: visible
                    NumberSequenceKeypoint.new(0.8, 0.4), -- Steady
                    NumberSequenceKeypoint.new(1, 1),     -- Fade out
                })
                trail.WidthScale = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(1, 1),
                })
                trail.Enabled = false -- Start disabled
                trail.Parent = primary
                
                -- Store attachments so we can move them to ground contact
                driftTrails[wheelName] = {Trail = trail, Att0 = att0, Att1 = att1}
            end
        end
    end
    
    -- Update trails: Snap attachments to GROUND position
    for wheelName, data in pairs(driftTrails) do
        local shouldEnable = false
        
        if isDriftingNow and not isAirborne then
            -- Check if this specific wheel hit the ground
            local hitPos = hitPositions[wheelName]
            if hitPos then
                shouldEnable = true
                
                -- Convert global hit position to Chassis-Local space
                local localHit = primary.CFrame:PointToObjectSpace(hitPos)
                
                -- Position attachments at ground contact (+ slight offset up to avoid z-fighting)
                -- Spread them apart by 0.4 total width (approx tire width)
                data.Att0.Position = localHit + Vector3.new(-0.2, 0.05, 0)
                data.Att1.Position = localHit + Vector3.new(0.2, 0.05, 0)
            end
        end
        
        data.Trail.Enabled = shouldEnable
    end

    -- Sim 14.1: Rig Check (Mass Fallback)
    local totalMass = rootPart.AssemblyMass
    local safeMass = totalMass
    if safeMass == math.huge or safeMass == 1/0 then safeMass = 200 end

    -- Sim 17.0: TILT DETECTION & DISMOUNT
    -- SIM 30.0: Skip during tilt grace period (prevents spawn flip)
    local upDot = up:Dot(Vector3.yAxis)
    local tiltAngle = math.deg(math.acos(math.clamp(upDot, -1, 1)))
    
    if tiltGraceTimer <= 0 and tiltAngle > (Config.DismountThreshold or 65) then
        if humanoid.Sit then
            print("⚠️ TILT OVER LIMIT ("..math.floor(tiltAngle).."°) - DISMOUNTING!")
            humanoid.Sit = false
        end
    end

    -- Sim 14.0: Forward ALIGNMENT CHECK
    -- DEBUG: Verify Input
    if math.random() < 0.05 then
        print("T:", throttle, "S:", steer, "Spd:", math.floor(currentSpeed), "Air:", isAirborne)
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
        local cappedVel = flatVel.Unit * Config.MaxSpeed * 1.15
        rootPart.AssemblyLinearVelocity = Vector3.new(cappedVel.X, vel.Y, cappedVel.Z)
    end
    
    -- SIM 42.0: SMART WALL COLLISION
    local bumperOrigin = primary.Position + (up * 1.5)
    local bumperLen = 4.0
    
    -- 1. FORWARD BUMPER: Checks in front of the chair
    local fwdBumperHit = workspace:Raycast(bumperOrigin, fwd * bumperLen, rayParams)
    local fwdBlocked = false
    if fwdBumperHit then
        if fwd:Dot(fwdBumperHit.Normal) < -0.2 then
            fwdBlocked = true
        end
    end
    
    -- 2. REAR BUMPER: Checks behind the chair
    local rearBumperHit = workspace:Raycast(bumperOrigin, -fwd * bumperLen, rayParams)
    local rearBlocked = false
    if rearBumperHit then
        if (-fwd):Dot(rearBumperHit.Normal) < -0.2 then
            rearBlocked = true
        end
    end
    
    -- 3. VELOCITY BUMPER: Checks direction of actual movement
    local moveDir = (speed > 1) and flatVel.Unit or fwd
    local velBumperHit = workspace:Raycast(bumperOrigin, moveDir * bumperLen, rayParams)
    local velBlocked = false
    if velBumperHit and speed > 3 then
        if moveDir:Dot(velBumperHit.Normal) < -0.2 then
            velBlocked = true
        end
    end
    
    -- 4. COLLISION RESPONSE
    -- SIM 42.0: Only block speed in the wall's direction
    if fwdBlocked and currentSpeed > 0 then
        currentSpeed = 0
    elseif rearBlocked and currentSpeed < 0 then
        currentSpeed = 0
    elseif velBlocked then
        currentSpeed = 0
    end
    
    -- Crash ejection for high-speed impacts
    if (fwdBlocked or velBlocked) then
        if speed > (Config.WallCrashThreshold or 40) then
            crashEject(seat, rootPart, vel, speed, fwd, right, fwdBlocked and "wall" or "velocity")
        end
    end
    
	-- Landing Grace Period
    if not isAirborne and wasAirborne then
        landingGraceTimer = 0.15
        
        -- SIM 45.0: Light sanity clamp (don't let integrator be LOWER than real speed)
        currentSpeed = math.max(currentSpeed, speed * 0.9)
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
    local graceMultiplier = 1 - (landingGraceTimer / 0.3)
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
    local steeringMultiplier = isShiftHeld and 1.0 or 0.4
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
    local targetHybrid = (isShiftHeld and steer ~= 0 and (not isAirborne or speed < 25) and speed > 25) and 1 or 0
    
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
        local driftTurnScale = isShiftHeld and 1.8 or 5.0 
        
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
            local maxLean = math.rad(70)
            local lean = 0
            if effectiveDrift then
                lean = math.clamp(lateralAccel / 5, -1, 1) * maxLean
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
                tiltEjectTimer = math.max(0, tiltEjectTimer - dt * 2) -- Decay twice as fast
            end
            
            if tiltEjectTimer > 0.35 then -- Must sustain for 350ms
                print("💥 TILT EJECT! Sustained:", string.format("%.0f° for %.2fs", math.deg(visualRoll), tiltEjectTimer))
                tiltEjectTimer = 0
                visualRoll = 0 -- Reset lean instantly on eject
                crashEject(seat, rootPart, vel, speed, fwd, right, "tilt")
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
        local baseGrip = effectiveDrift and Config.DriftGrip or 150
        local targetMaxFriction = rootPart.AssemblyMass * baseGrip
        
        -- Smooth the friction clamp (don't snap from 0.05 instantly)
        -- Sim 8.0: Much slower recovery (dt * 0.5) to prevent the "motorcycle stop"
        currentSideFriction = currentSideFriction + (targetMaxFriction - currentSideFriction) * dt * 0.5
        
        local finalFrictionMagnitude = math.min(math.abs(lateralSpeed) * 50, currentSideFriction * sideGripMultiplier)
        
        if math.abs(lateralSpeed) > 0.05 then
            sideForce.Force = (-planarRight * math.sign(lateralSpeed)) * finalFrictionMagnitude
        else
            sideForce.Force = Vector3.zero
        end
	end
	
	isDrifting = isDriftingNow
    
    -- Track state for next frame
    wasAirborne = isAirborne
    
    -- Body Roll handled in Stabilizer block (Option C)
    
    
    if jumpStabilityTimer > 0 then
        jumpStabilityTimer = math.max(0, jumpStabilityTimer - dt)
    end
    
    -- Note: Jump processing moved to earlier in frame (see line ~320)
end)

