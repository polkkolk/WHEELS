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
local smoothTurnForce = 0 -- SIM 41.0: Ramped turn force (gradual buildup)
local reactiveTilt = 0 -- SIM 41.0: Tilt caused by sudden turn changes

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
        smoothTurnForce = 0 -- SIM 41.0: Reset turn ramp
        reactiveTilt = 0    -- SIM 41.0: Reset reactive tilt
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
    
	for name, att in pairs(attachments) do
		local origin = att.WorldPosition
		local dir = -att.WorldCFrame.UpVector * Config.SusRayLength
		
		local result = workspace:Raycast(origin, dir, rayParams)
		local force = Vector3.zero
		
		if result then
            anyRayHit = true
            minDist = math.min(minDist, result.Distance)
            hitPositions[name] = result.Position
            
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

    -- SIM 37.0: JUMP PROCESSING - MUST BE BEFORE STEERING
    -- This ensures jumpStabilityTimer is set BEFORE yaw impulse checks
    if jumpRequested and not isAirborne then
        jumpRequested = false
        print("🚀 JUMPING! Speed:", math.floor(speed), "Steer:", steer)
        
        -- Set timer FIRST (before any steering checks this frame)
        jumpStabilityTimer = 0.25
        
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
	if not isAirborne and speed > currentDriftFloor and (isShiftHeld or (slipAngle > Config.DriftThreshold and speed > 20)) then
		isDriftingNow = true
		driftTime = driftTime + dt
	else
		driftTime = 0
	end
    isDrifting = isDriftingNow -- Update persistent state immediately

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
        -- Wall in front: block forward speed, allow reverse
        currentSpeed = 0
        if math.random() < 0.1 then
            print("🧱 WALL (front)! Blocking forward.")
        end
    elseif rearBlocked and currentSpeed < 0 then
        -- Wall behind: block reverse speed, allow forward
        currentSpeed = 0
        if math.random() < 0.1 then
            print("🧱 WALL (rear)! Blocking reverse.")
        end
    elseif velBlocked then
        currentSpeed = 0
        if math.random() < 0.1 then
            print("🧱 WALL (velocity)! Blocking movement.")
        end
    end
    
    -- Crash ejection for high-speed impacts
    if (fwdBlocked or velBlocked) then
        if speed > (Config.WallCrashThreshold or 40) then
            print("💥 CRASH EJECTION!")
            seat:Sit(nil)
        end
    end
	
	-- Landing Grace Period
    if not isAirborne and wasAirborne then
        landingGraceTimer = 0.15 -- SIM 38.0: Reduced to 150ms for responsive steering
    end
    if landingGraceTimer > 0 then
        landingGraceTimer = math.max(0, landingGraceTimer - dt)
    end
    
    -- Ease-in grace multiplier
    local graceMultiplier = 1 - (landingGraceTimer / 0.3)
    -- Sim 22.0: Terrain Alignment Math (Ramp Pitching)
    local targetNormal = Vector3.new(0, 1, 0)
    if not isAirborne then
        -- We need at least 3 points to define a plane
        local p = hitPositions
        if p.FL and p.FR and p.RL and p.RR then
            -- Use average of diagonal/edge crosses for stability
            local fwdVec = ((p.FL + p.FR) * 0.5) - ((p.RL + p.RR) * 0.5)
            local rightVec = ((p.FR + p.RR) * 0.5) - ((p.FL + p.RL) * 0.5)
            targetNormal = rightVec:Cross(fwdVec).Unit
        elseif p.FL and p.FR and p.RL then
            targetNormal = (p.FR - p.FL):Cross(p.RL - p.FL).Unit
        elseif p.FL and p.FR and p.RR then
            targetNormal = (p.FR - p.FL):Cross(p.RR - p.FL).Unit
        end
        -- Flip if pointing down
        if targetNormal.Y < 0 then targetNormal = -targetNormal end
    end
    
    -- Smooth the transition
    smoothedNormal = smoothedNormal:Lerp(targetNormal, dt * 8)

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
	moveForce.LineDirection = planarForward -- Drives horizontally ONLY
	moveForce.LineVelocity = currentSpeed
    
    -- DRIVE FORCE & ROLLING RESISTANCE
    if isAirborne then
        moveForce.MaxForce = 0
    else
        -- Fallback mass
        local safeMass = rootPart.AssemblyMass
        if safeMass == math.huge or safeMass == 1/0 then safeMass = 200 end

        -- Sim 16.0: Persistent Heavyweight Force
        -- Use a high constant force (400x Mass) to ensure the chair follows 
        -- the integrator with zero "fighting" or "friction bleed".
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
    local targetHybrid = (isShiftHeld and (not isAirborne or speed < 35) and speed > 35) and 1 or 0
    
    -- Smooth transition to prevent "Bucking" (Sim 3.1 Fix)
    -- SIM 43.0: Slowed from 8 to 4 for smoother drift entry (prevents jab)
    steadyHybrid = steadyHybrid + (targetHybrid - steadyHybrid) * dt * 4
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
            
            -- SIM 42.0/43.0: REACTIVE TILT SYSTEM
            local driftTurnMultiplier = isDrifting and 2.5 or 1.0
            local targetTurnForce = steer * driftTurnMultiplier
            
            -- Ramp smoothTurnForce toward target (gradual buildup)
            local turnRampSpeed = isDrifting and 3.0 or 5.0
            local prevTurnForce = smoothTurnForce
            smoothTurnForce = smoothTurnForce + (targetTurnForce - smoothTurnForce) * dt * turnRampSpeed
            
            -- Reactive kick: spike from sudden changes, decays quickly
            local instantDelta = (smoothTurnForce - prevTurnForce) / dt
            reactiveTilt = reactiveTilt + (-instantDelta * 0.06 - reactiveTilt) * dt * 6
            reactiveTilt = math.clamp(reactiveTilt, -2.0, 2.0)
            
            -- STEADY TILT: Based on CURRENT turn force × speed
            local speedFactor = math.clamp(speed / Config.MaxSpeed, 0, 1)
            local steadyTilt = -smoothTurnForce * speedFactor * math.rad(25) -- SIM 43.0: 12→25°
            
            -- Reactive tilt spike (from sudden changes)
            local reactiveTiltAngle = reactiveTilt * math.rad(35) -- SIM 43.0: 20→35°
            
            -- Total tilt
            local totalTiltAngle = steadyTilt + reactiveTiltAngle
            
            -- SIM 43.0: TILT EJECT (raised to normal dismount range)
            local tiltEjectThreshold = math.rad(70) -- 70 degrees (near Roblox default ~80)
            if math.abs(totalTiltAngle) > tiltEjectThreshold and speed > 30 and tiltGraceTimer <= 0 then
                print("💥 TILT EJECT! Angle:", math.deg(totalTiltAngle))
                seat:Sit(nil)
            end
            
            -- Cap and smooth
            local cappedTilt = math.clamp(totalTiltAngle, -math.rad(60), math.rad(60))
            visualRoll = visualRoll + (cappedTilt - visualRoll) * dt * 8
            
            -- Apply Lean to Stabilizer Goal
            local leanCF = CFrame.fromAxisAngle(planarForward, visualRoll)
            local targetAxis = leanCF * WORLD_UP
            stabilizer.PrimaryAxis = stabilizer.PrimaryAxis:Lerp(targetAxis, dt * 10)
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
        local baseGrip = isDriftingNow and Config.DriftGrip or 150
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
    
    -- SIM 37.0: MOVED to end - timer decrement only
    if jumpStabilityTimer > 0 then
        jumpStabilityTimer = math.max(0, jumpStabilityTimer - dt)
    end
    
    -- Note: Jump processing moved to earlier in frame (see line ~320)
end)

