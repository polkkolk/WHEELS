local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local WHEELCHAIR_NAME = "WheelchairRig"

-- COLLISION GROUPS (Prevents ragdoll limb-wheelchair wedging)
PhysicsService:RegisterCollisionGroup("Wheelchair")
PhysicsService:RegisterCollisionGroup("RagdollCharacter")
PhysicsService:CollisionGroupSetCollidable("RagdollCharacter", "Wheelchair", false)

-- SIM 46.0: Create CrashEjectEvent for ragdoll fling
local CrashEjectEvent = Instance.new("RemoteEvent")
CrashEjectEvent.Name = "CrashEjectEvent"
CrashEjectEvent.Parent = ReplicatedStorage

-- Track which characters are currently ragdolling (for NoCollisionConstraint persistence)
local ragdollingCharacters = {}

-- Wait for the rig to exist to avoid errors if the script runs before the asset loads
local function getWheelchairRig()
	local rig = ServerStorage:FindFirstChild(WHEELCHAIR_NAME)
	if not rig then
		warn("WheelchairService: Could not find '" .. WHEELCHAIR_NAME .. "' in ServerStorage!")
	end
	return rig
end

-- Helper to weld the model together so it doesn't fall apart
local function weldModel(model, primaryPart)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			-- PHYSICS FIX: Remove friction from physical parts
			-- We behave like a hovercraft physically, but use LinearVelocity to simulate tire grip.
			-- This prevents the wheels from "Grinding" against the floor and stopping the turn.
			part.CustomPhysicalProperties = PhysicalProperties.new(
				1,      -- Density (Standard)
				0,      -- Friction (Ice)
				0,      -- Elasticity (No bounce)
				100,    -- FrictionWeight (Max, override floor)
				1       -- ElasticityWeight
			)

			if part ~= primaryPart then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primaryPart
				weld.Part1 = part
				weld.Parent = primaryPart
			end
            -- SIM 15.0 FIX: Ensure no parts are anchored by default
            part.Anchored = false
		end
	end
end

-- SIM 46.0: Motor6D Ragdoll system
local function enableRagdoll(character)
    local joints = {}
    local savedGroups = {}
    local savedCollisions = {}
    
    -- 1. SAVE original CollisionGroups + CanCollide (restored during recovery)
    -- During ragdoll, character STAYS in original group for realistic collisions
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if not (part.Parent:IsA("Accessory") or part.Parent:IsA("Accoutrement")) then
                savedGroups[part] = part.CollisionGroup
                savedCollisions[part] = part.CanCollide
                
                -- R15 limbs default to CanCollide=false. PlatformStand stops
                -- the Humanoid from managing this, so we force them ON for ground physics.
                if part.Name == "HumanoidRootPart" then
                    part.CanCollide = false -- Prevent double-collision with torso
                else
                    part.CanCollide = true  -- Limbs interact with ground
                end
            end
        end
    end
    
    -- 2. Break joints and add BallSockets
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("Motor6D") and desc.Name ~= "RootJoint" then
            table.insert(joints, {
                joint = desc,
                parent = desc.Parent,
            })
            
            local att0 = Instance.new("Attachment")
            att0.Name = "RagdollAtt0"
            att0.CFrame = desc.C0
            att0.Parent = desc.Part0
            
            local att1 = Instance.new("Attachment")
            att1.Name = "RagdollAtt1"
            att1.CFrame = desc.C1
            att1.Parent = desc.Part1
            
            local socket = Instance.new("BallSocketConstraint")
            socket.Name = "RagdollSocket"
            socket.Attachment0 = att0
            socket.Attachment1 = att1
            socket.LimitsEnabled = true
            socket.UpperAngle = 45
            socket.Parent = desc.Parent
            
            desc.Enabled = false
        end
    end
    
    return {
        joints = joints, 
        savedGroups = savedGroups,
        savedCollisions = savedCollisions,
    }
end

local function disableRagdoll(character, data)
    local joints = data.joints
    
    -- 1. Destroy BallSocket constraints
    for _, desc in ipairs(character:GetDescendants()) do
        if desc.Name == "RagdollSocket" or desc.Name == "RagdollAtt0" or desc.Name == "RagdollAtt1" then
            desc:Destroy()
        end
    end
    
    -- 2. Re-enable Motor6Ds
    for _, jData in ipairs(joints) do
        if jData.joint and jData.joint.Parent then
            jData.joint.Enabled = true
        end
    end
    
    -- 3. Restore original CanCollide states
    for part, state in pairs(data.savedCollisions) do
        if part and part.Parent then
            part.CanCollide = state
        end
    end
    
    -- NOTE: CollisionGroup is restored LATER in staged recovery (not here)
end

local function restoreCollisionGroups(data)
    for part, group in pairs(data.savedGroups) do
        if part and part.Parent then
            part.CollisionGroup = group
        end
    end
end

-- SIM 46.0: Crash eject handler
CrashEjectEvent.OnServerEvent:Connect(function(player, flingData)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end
	
	local flingVelocity = flingData and flingData.flingVelocity or Vector3.new(0, 5, 0)
	local crashSpeed = flingData and flingData.speed or 30
	local reason = flingData and flingData.reason or "crash"
	
	print("🚑 CRASH EJECT:", player.Name, "| Reason:", reason, "| Speed:", math.floor(crashSpeed))
	
	-- 1. Unseat
	local seat = humanoid.SeatPart
	if seat then
		seat:Sit(nil)
	end
	task.wait(0.1)
	
	-- 2. Motor6D ragdoll + PlatformStand
	local ragdollData = enableRagdoll(character)
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	ragdollingCharacters[character] = true -- Flag for NoCollisionConstraint persistence
	
	-- 3. Apply fling velocity (raw velocity, no mass multiplication)
	if rootPart and rootPart.Parent then
		rootPart.AssemblyLinearVelocity = flingVelocity
		rootPart.AssemblyAngularVelocity = Vector3.new(
			math.random(-3, 3),
			math.random(-2, 2),
			math.random(-3, 3)
		)
	end
	
	-- 4. STAGED RECOVERY after 2.5s
	-- Rule: Never allow rig to enter reference pose while collidable
	task.delay(2.5, function()
		if character and character.Parent and humanoid and humanoid.Health > 0 then
			-- STAGE 1: Raycast-Safe Teleport (still in RagdollCharacter group)
			if rootPart then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				
				-- Find safe ground position
				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = {character}
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -50, 0), rayParams)
				if result then
					character:PivotTo(CFrame.new(result.Position + Vector3.new(0, 5, 0)))
				else
					character:PivotTo(rootPart.CFrame + Vector3.new(0, 6, 0))
				end
			end
			
			-- STAGE 2: Switch to RagdollCharacter group BEFORE re-enabling Motor6Ds
			-- This prevents the I-pose snap from colliding with wheelchair/geometry
			for part, _ in pairs(ragdollData.savedGroups) do
				if part and part.Parent then
					part.CollisionGroup = "RagdollCharacter"
				end
			end
			
			-- STAGE 3: Disable ragdoll constraints (re-enable Motor6Ds)
			-- Character is now in RagdollCharacter group (safe from collision flings)
			disableRagdoll(character, ragdollData)
			
			-- STAGE 4: Wait for animation to stabilize the pose
			task.wait(0.15)
			
			-- STAGE 5: Restore physics (NOW safe — animation has control)
			restoreCollisionGroups(ragdollData)
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			
			-- STAGE 6: Cleanup
			humanoid.WalkSpeed = 16
			ragdollingCharacters[character] = nil
			print("🚑 Recovery: Staged (CollisionGroup safe)")
		end
	end)
end)

-- === WHEELCHAIR CRUSH KILL MECHANIC ===

-- Explode a wheelchair: destroy welds, launch parts in all directions
local function explodeWheelchair(chairModel)
    if not chairModel or not chairModel.Parent then return end
    
    local parts = {}
    local center = Vector3.zero
    local partCount = 0
    
    -- Collect all BaseParts and find center
    for _, desc in ipairs(chairModel:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
            center = center + desc.Position
            partCount = partCount + 1
        end
    end
    
    if partCount == 0 then return end
    center = center / partCount
    
    -- 1. Destroy ALL welds/constraints (unglue everything)
    for _, desc in ipairs(chairModel:GetDescendants()) do
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("Motor6D")
            or desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint")
            or desc:IsA("SpringConstraint") or desc:IsA("RopeConstraint")
            or desc:IsA("LinearVelocity") or desc:IsA("AngularVelocity")
            or desc:IsA("AlignOrientation") or desc:IsA("AlignPosition")
            or desc:IsA("VectorForce") or desc:IsA("NoCollisionConstraint") then
            desc:Destroy()
        end
    end
    
    -- 2. Unseat any occupant
    local seat = chairModel:FindFirstChildWhichIsA("VehicleSeat", true)
    if seat and seat.Occupant then
        seat.Occupant.Jump = true
    end
    
    -- 3. Launch each part in a random outward direction
    for _, part in ipairs(parts) do
        part.Anchored = false
        part.CanCollide = false -- FIX: Ghost debris so player doesn't get stuck
        part.CollisionGroup = "Default"
        
        local outDir = (part.Position - center)
        if outDir.Magnitude < 0.1 then
            outDir = Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5)
        end
        outDir = outDir.Unit
        
        local launchSpeed = math.random(30, 80)
        local upBoost = math.random(20, 50)
        part.AssemblyLinearVelocity = outDir * launchSpeed + Vector3.new(0, upBoost, 0)
        part.AssemblyAngularVelocity = Vector3.new(
            math.random(-15, 15),
            math.random(-15, 15),
            math.random(-15, 15)
        )
        
        -- Keep in model so Client can Ignore it for Raycasts
        -- part.Parent = workspace -- Removed repackaging
    end
    
    -- 4. Schedule cleanup of the entire model
    game:GetService("Debris"):AddItem(chairModel, 5)
end

-- === BLOOD VFX (Client Sided) ===
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SMUSH_SOUND_ID = "rbxassetid://429400881"   -- Gore Splatter

local CollectionService = game:GetService("CollectionService")

-- SETUP COLLISION GROUPS FOR DEBRIS
-- "Debris" should collide with "Default" (Map) but NOT "Player"
local success, err = pcall(function()
    PhysicsService:RegisterCollisionGroup("Debris")
    PhysicsService:RegisterCollisionGroup("Player")
    PhysicsService:CollisionGroupSetCollidable("Debris", "Player", false)
    PhysicsService:CollisionGroupSetCollidable("Debris", "Debris", false)
    PhysicsService:CollisionGroupSetCollidable("Debris", "Default", true) -- EXPLICITLY ENABLE MAP COLLISION
end)
if not success then warn("CollisionGroup Error: " .. tostring(err)) end

-- Ensure Players are in "Player" group
local function setPlayerGroup(char)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "Player"
        end
    end
end
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(setPlayerGroup)
end)


-- Create RemoteEvent
local BloodEvent = ReplicatedStorage:FindFirstChild("BloodEvent")
if not BloodEvent then
    BloodEvent = Instance.new("RemoteEvent")
    BloodEvent.Name = "BloodEvent"
    BloodEvent.Parent = ReplicatedStorage
end

local function smushAndSplatter(victimChar)
    if not victimChar then return end
    
    local root = victimChar:FindFirstChild("HumanoidRootPart")
    local pos = root and root.Position or victimChar:GetPivot().Position
    
    -- 1. Play Sound (Server Side for sync)
    local sound = Instance.new("Sound")
    sound.SoundId = SMUSH_SOUND_ID
    sound.Volume = 4
    sound.PlaybackSpeed = math.random(90, 110) / 100
    sound.Parent = root or workspace
    sound:Play()
    game:GetService("Debris"):AddItem(sound, 3)
    
    -- 2. DISAPPEAR VICTIM (Ghost Mode)
    for _, part in ipairs(victimChar:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("Decal") then
            part.Transparency = 1
            if part:IsA("BasePart") then
                part.CollisionGroup = "Debris" -- Ghost functionality
                part.CanCollide = false -- Explicit off for victim
                part.Anchored = true
                part.CastShadow = false
                if part.Name == "HumanoidRootPart" then part.CanQuery = false end
            end
        end
    end
    
    -- 3. FIRE CLIENT EVENT (Visuals)
    BloodEvent:FireAllClients(pos, Vector3.new(0, 1, 0), victimChar)
end

-- Explode a wheelchair: destroy welds, launch parts in all directions
local function explodeWheelchair(chairModel)
    if not chairModel or not chairModel.Parent then return end
    
    local parts = {}
    local center = Vector3.zero
    local partCount = 0
    
    -- Collect all BaseParts and find center
    for _, desc in ipairs(chairModel:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
            center = center + desc.Position
            partCount = partCount + 1
        end
    end
    
    if partCount == 0 then return end
    center = center / partCount
    
    -- 1. Destroy ALL welds/constraints (unglue everything)
    for _, desc in ipairs(chairModel:GetDescendants()) do
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("Motor6D")
            or desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint")
            or desc:IsA("SpringConstraint") or desc:IsA("RopeConstraint")
            or desc:IsA("LinearVelocity") or desc:IsA("AngularVelocity")
            or desc:IsA("AlignOrientation") or desc:IsA("AlignPosition")
            or desc:IsA("VectorForce") or desc:IsA("NoCollisionConstraint") then
            desc:Destroy()
        end
    end
    
    -- 2. Unseat any occupant
    local seat = chairModel:FindFirstChildWhichIsA("VehicleSeat", true)
    if seat and seat.Occupant then
        seat.Occupant.Jump = true
    end
    
    -- 3. Launch each part in a random outward direction
    for i, part in ipairs(parts) do
        -- ORPHAN THE PART: Detach from model so it survives model destruction
        part.Parent = workspace
        
        -- TAG: Add to Debris for Client
        CollectionService:AddTag(part, "BloodDebris")
        game:GetService("Debris"):AddItem(part, 10) -- Independent cleanup
        
        part.Anchored = false -- Restore Physics
        part.CanCollide = true 
        part.CollisionGroup = "Debris"
        
        -- Reset velocity
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
        
        local outDir = (part.Position - center)
        if outDir.Magnitude < 0.1 then
            outDir = Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5)
        end
        outDir = outDir.Unit
        
        -- JUJUTSU IMPACT: High velocity for dramatic effect
        local launchSpeed = math.random(30, 80)
        local upBoost = math.random(20, 50)
        part.AssemblyLinearVelocity = outDir * launchSpeed + Vector3.new(0, upBoost, 0)
        part.AssemblyAngularVelocity = Vector3.new(
            math.random(-25, 25),
            math.random(-25, 25),
            math.random(-25, 25)
        )
    end
    
    -- 4. Destroy the empty model shell immediately
    chairModel:Destroy()
end
local crushDebounce = {}

RunService.Heartbeat:Connect(function()
    for _, attacker in ipairs(Players:GetPlayers()) do
        if crushDebounce[attacker] then continue end
        
        local attackerChar = attacker.Character
        if not attackerChar then continue end
        
        local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")
        local attackerHum = attackerChar:FindFirstChildOfClass("Humanoid")
        if not attackerRoot or not attackerHum or attackerHum.Health <= 0 then continue end
        
        -- Must be falling fast (downward velocity > 15 studs/s)
        local vel = attackerRoot.AssemblyLinearVelocity
        if vel.Y > -15 then continue end
        
        -- Raycast downward from attacker's feet
        local rayStart = attackerRoot.Position
        local rayDir = Vector3.new(0, -6, 0)
        
        local filterList = {attackerChar}
        local attackerWheelchair = workspace:FindFirstChild(attacker.Name .. "_Wheelchair")
        if attackerWheelchair then
            table.insert(filterList, attackerWheelchair)
        end
        
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = filterList
        params.FilterType = Enum.RaycastFilterType.Exclude
        
        local result = workspace:Raycast(rayStart, rayDir, params)
        if not result or not result.Instance then continue end
        
        -- Check if hit part belongs to another player's wheelchair
        local hitPart = result.Instance
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        
        if not hitModel then continue end
        
        local victimChar
        local victimWheelchair
        
        -- Case A: Hit the Wheelchair directly
        if string.find(hitModel.Name, "_Wheelchair") then
            victimWheelchair = hitModel
            local victimName = string.gsub(hitModel.Name, "_Wheelchair", "")
            
            -- Find character (Player or Dummy)
            local p = Players:FindFirstChild(victimName)
            if p then 
                if p == attacker then continue end -- Self-hit (should be filtered but double check)
                victimChar = p.Character 
            else
                victimChar = workspace:FindFirstChild(victimName)
            end
            
        -- Case B: Hit the Character directly (e.g. Head/Shoulders)
        elseif hitModel:FindFirstChildOfClass("Humanoid") then
            victimChar = hitModel
            if victimChar == attackerChar then continue end -- Self-hit
            
            -- Find their wheelchair
            victimWheelchair = workspace:FindFirstChild(victimChar.Name .. "_Wheelchair")
        end
        
        if not victimChar or not victimWheelchair then continue end
        
        local victimHum = victimChar:FindFirstChildOfClass("Humanoid")
        if not victimHum or victimHum.Health <= 0 then continue end
        
        -- CRUSH KILL!
        crushDebounce[attacker] = true
        print("WHEELCHAIR CRUSH:", attacker.Name, "landed on", victimChar.Name)
        
        -- Trigger Effects (Sound, Blood, Disappear)
        smushAndSplatter(victimChar)
        
        -- Kill Victim
        victimHum.Health = 0
        explodeWheelchair(victimWheelchair)
        
        task.delay(1, function()
            crushDebounce[attacker] = nil
        end)
    end
end)

local function onCharacterAdded(character)
	print("WheelchairService: Character Added", character.Name)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- 1. Disable Jumping (Lock them in)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0

	-- 2. Clone the Chair
	local rigTemplate = getWheelchairRig()
	if not rigTemplate then 
		warn("WheelchairService: Template Missing!")
		return 
	end
	print("WheelchairService: Found rig template:", rigTemplate.Name)
	
	local validSeat = rigTemplate:FindFirstChildWhichIsA("VehicleSeat", true)
	if not validSeat then
		warn("WheelchairService: '" .. WHEELCHAIR_NAME .. "' has no VehicleSeat!")
		return
	end

	local newChair = rigTemplate:Clone()
	newChair.Name = character.Name .. "_Wheelchair"
	newChair.Parent = workspace
	
	-- Assign wheelchair parts to Wheelchair CollisionGroup
	for _, part in ipairs(newChair:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Wheelchair"
		end
	end
	
	print("WheelchairService: Cloned Chair", newChair)
	
	-- 2.5 Auto-Weld the chair parts
	-- We prefer the PrimaryPart, but fallback to the VehicleSeat if not set.
	local vehicleSeat = newChair:FindFirstChildWhichIsA("VehicleSeat", true)
	local primaryPart = newChair.PrimaryPart or vehicleSeat
	
	if primaryPart then
		weldModel(newChair, primaryPart)
		
		-- 3. Move Chair to Player (Rigid Spawn Protocol - ChatGPT Fix)
		local rootPos = rootPart.Position
		local rootLook = rootPart.CFrame.LookVector
		local flatLook = Vector3.new(rootLook.X, 0, rootLook.Z).Unit
		
		-- Force Flat CFrame (No pitch/roll from character)
		local spawnCF = CFrame.lookAt(rootPos + Vector3.new(0, 3.5, 0), rootPos + Vector3.new(0, 3.5, 0) + flatLook)
		newChair:PivotTo(spawnCF)
		
		-- Zero all velocities to prevent spawn-jitter
		for _, part in pairs(newChair:GetDescendants()) do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
		print("WheelchairService: Rigid spawn at", spawnCF.Position)
		
		-- 3.5. Setup Physics Constraints (Raycast Suspension Model)
        
        -- Ground Attachment: For linear forces (prevents tipping)
		local baseAtt = Instance.new("Attachment")
		baseAtt.Name = "BaseAttachment"
		baseAtt.Position = Vector3.new(0, -3.5, 0) -- DROPPED TO -3.5 (Sim 20.0)
		baseAtt.Parent = primaryPart
		
		-- ATTACHMENT SPLIT (Fix Orbital Rotation)
        -- COM Attachment: For rotation forces (prevents orbital motion)
		local comAtt = Instance.new("Attachment")
		comAtt.Name = "COM_Attachment"
        comAtt.Position = Vector3.new(0, -3.0, 0) -- DROPPED TO -3.0 (Sim 20.0: Bottom Heavy)
		comAtt.Parent = primaryPart
		
		-- Suspension Attachments (Corner Points)
        -- AXIS REVERT: Standard Roblox.
        -- Assuming Mesh Faces -Z (Standard).
        -- Width = X. Depth = Z.
		local corners = {
			FL = Vector3.new(-1.5, -1, -1.5), -- Front Left
			FR = Vector3.new( 1.5, -1, -1.5), -- Front Right
			RL = Vector3.new(-1.5, -1,  1.5), -- Rear Left
			RR = Vector3.new( 1.5, -1,  1.5)  -- Rear Right
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
		
		-- Propulsion (LinearVelocity) - GROUND LEVEL
		local moveIso = Instance.new("LinearVelocity")
		moveIso.Name = "MoveVelocity"
		moveIso.Attachment0 = baseAtt -- Ground attachment
		moveIso.MaxForce = 0
		moveIso.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		moveIso.LineDirection = Vector3.new(0, 0, -1) 
		moveIso.RelativeTo = Enum.ActuatorRelativeTo.World 
		moveIso.Parent = primaryPart
		
		-- Turning (AngularVelocity) - CENTER OF MASS
		local turnIso = Instance.new("AngularVelocity")
		turnIso.Name = "TurnVelocity"
		turnIso.Attachment0 = comAtt -- COM attachment (FIX: prevents orbit)
		turnIso.MaxTorque = 0
		turnIso.RelativeTo = Enum.ActuatorRelativeTo.World
		turnIso.AngularVelocity = Vector3.zero
		turnIso.Parent = primaryPart
		
		-- Drifting / Side Slip (VectorForce) - Passive Friction Model
		local sideForce = Instance.new("VectorForce")
		sideForce.Name = "SideForce"
		sideForce.Attachment0 = comAtt -- Apply at COM for stability
		sideForce.RelativeTo = Enum.ActuatorRelativeTo.World
		sideForce.Force = Vector3.zero
		sideForce.Parent = primaryPart
        
        -- Rolling Drag (VectorForce) - ChatGPT Fix
        local dragForce = Instance.new("VectorForce")
        dragForce.Name = "DragForce"
        dragForce.Attachment0 = comAtt
        dragForce.RelativeTo = Enum.ActuatorRelativeTo.World
        dragForce.Force = Vector3.zero
        dragForce.Parent = primaryPart
		
		-- VIRTUAL ANTI-ROLL (AlignOrientation) - ChatGPT Fix
		-- Keeps chair upright (X/Z) using PrimaryAxisParallel (doesn't fight turning/Yaw)
		local stabilizer = Instance.new("AlignOrientation")
		stabilizer.Name = "Stabilizer"
		stabilizer.Mode = Enum.OrientationAlignmentMode.OneAttachment
		stabilizer.Attachment0 = comAtt
		comAtt.Axis = Vector3.new(0, 1, 0) -- Set Local Up as the primary axis
		
		stabilizer.AlignType = Enum.AlignType.PrimaryAxisParallel
		stabilizer.PrimaryAxis = Vector3.yAxis -- Target World Up (Sim 2.0)
		stabilizer.MaxTorque = 0 -- Controller sets this
		stabilizer.MaxAngularVelocity = 10
		stabilizer.Responsiveness = 20
		stabilizer.Parent = primaryPart
		
		print("WheelchairService: Physics Setup Complete")

	else
		warn("WheelchairService: Chair has no PrimaryPart to attach physics to!")
	end

	-- 4. Force Sit (Delayed to allow physics settling)
	task.delay(0.5, function()
		if newChair and newChair.Parent and humanoid and humanoid.Health > 0 then
			local seat = newChair:FindFirstChildWhichIsA("VehicleSeat", true)
			if seat then
				-- PHYSICS FIX: Disable collision between character and ENTIRE chair
				for _, charPart in pairs(character:GetDescendants()) do
					if charPart:IsA("BasePart") then
                        for _, chairPart in pairs(newChair:GetDescendants()) do
                            if chairPart:IsA("BasePart") then
                                local ncc = Instance.new("NoCollisionConstraint")
                                ncc.Name = "SeatNoCollision"
                                ncc.Part0 = charPart
                                ncc.Part1 = chairPart
                                ncc.Parent = chairPart
                            end
                        end
					end
				end
				
				-- PHYSICS FIX: Disable jumping state to prevent dismounting
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
				
				seat:Sit(humanoid)
				print("WheelchairService: Forced Sit")
                
                -- SIM 31.0: Prevent duplicate listener registration
                if not seat:GetAttribute("_OccupantListenerSet") then
                    seat:SetAttribute("_OccupantListenerSet", true)
                    
                    -- SIM 26.0: SERVER-SIDE STATE-AWARE DISMOUNT PHYSICS (Permanent)
                    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
                        local crawlBrake = primaryPart:FindFirstChild("CrawlBrake")
                        local spinBrake = primaryPart:FindFirstChild("SpinBrake")
                        
                        if not seat.Occupant then
                            print("WheelchairService: Player dismounted - Engaging Adaptive Physics")
                            
                            -- KEEP NoCollisionConstraints during ragdoll (prevents limb-chair wedging)
                            -- Only destroy them AFTER ragdoll recovery is complete
                            if not ragdollingCharacters[character] then
                                for _, desc in pairs(newChair:GetDescendants()) do
                                    if desc:IsA("NoCollisionConstraint") and desc.Name == "SeatNoCollision" then
                                        desc:Destroy()
                                    end
                                end
                            else
                                -- Delayed cleanup: wait for ragdoll recovery before destroying constraints
                                task.spawn(function()
                                    while ragdollingCharacters[character] do task.wait(0.1) end
                                    for _, desc in pairs(newChair:GetDescendants()) do
                                        if desc:IsA("NoCollisionConstraint") and desc.Name == "SeatNoCollision" then
                                            desc:Destroy()
                                        end
                                    end
                                    print("WheelchairService: NoCollisionConstraints cleaned after recovery")
                                end)
                            end
                            
                            -- 1. LINEAR DRAG (CrawlBrake) - Strong enough to hold zero-friction chair
                            if not crawlBrake then
                                crawlBrake = Instance.new("LinearVelocity")
                                crawlBrake.Name = "CrawlBrake"
                                crawlBrake.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                                crawlBrake.VectorVelocity = Vector3.zero
                                crawlBrake.MaxForce = 5000 -- Strong hold (chair has 0 friction)
                                crawlBrake.Attachment0 = primaryPart:FindFirstChild("BaseAttachment") or primaryPart:FindFirstChildWhichIsA("Attachment")
                                crawlBrake.Parent = primaryPart
                            end
                            
                            -- 2. ANGULAR DRAG (SpinBrake)
                            if not spinBrake then
                                spinBrake = Instance.new("AngularVelocity")
                                spinBrake.Name = "SpinBrake"
                                spinBrake.AngularVelocity = Vector3.zero
                                spinBrake.MaxTorque = 5000 
                                spinBrake.Attachment0 = primaryPart:FindFirstChild("BaseAttachment") or primaryPart:FindFirstChildWhichIsA("Attachment")
                                spinBrake.Parent = primaryPart
                            end

                            -- 3. DYNAMIC TILT-LOOP (Sim 26.0)
                            task.spawn(function()
                                while not seat.Occupant and primaryPart and primaryPart.Parent do
                                    local up = primaryPart.CFrame.UpVector
                                    local brake = primaryPart:FindFirstChild("CrawlBrake")
                                    if brake then
                                        if up.Y > 0.85 then
                                            brake.MaxForce = 5000
                                        else
                                            brake.MaxForce = 8000
                                        end
                                    end
                                    task.wait(0.2)
                                end
                            end)
                            
                            -- 4. ANCHOR immediately (prevents player pushing zero-friction chair)
                            primaryPart.AssemblyLinearVelocity = Vector3.zero
                            primaryPart.AssemblyAngularVelocity = Vector3.zero
                            -- Upright the chair before anchoring (remove pitch/roll, keep Y rotation)
                            local pos = primaryPart.Position
                            local _, yaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
                            primaryPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
                            primaryPart.Anchored = true
                            print("WheelchairService: Chair uprighted & anchored")
                        else
                            -- Player sat down, release the brakes and unanchor
                            print("WheelchairService: Player seated - Releasing Brakes")
                            primaryPart.Anchored = false
                            if crawlBrake then crawlBrake:Destroy() end
                            if spinBrake then spinBrake:Destroy() end
                        end
                    end)
                end
			end
		end
	end)
	
	-- 5. Cleanup when player dies
	humanoid.Died:Connect(function()
		-- FIX: Don't destroy if it's currently exploding (debris mode)
		if newChair and newChair.Parent and not newChair:GetAttribute("Exploding") then
			newChair:Destroy()
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	-- If the character already exists (e.g. playing solo test), run it immediately
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Iterate existing players if script starts late
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end




