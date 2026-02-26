local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

-- GAME KILL TRACKING: Bind to GameService via BindableEvent
local function fireGameKill(attackerPlayer, victimPlayer)
	local bindable = ServerStorage:FindFirstChild("GameKillBindable")
	if bindable then
		bindable:Fire(attackerPlayer, victimPlayer)
	end
end

-- TEAM CHECK: returns true if attacker and victim are on the same team
local function sameTeam(attackerName, victimName)
	local fn = ServerStorage:FindFirstChild("GetPlayerTeam")
	if not fn then return false end
	local at = fn:Invoke(attackerName)
	local vt = fn:Invoke(victimName)
	return at ~= nil and at == vt
end

local WHEELCHAIR_NAME = "WheelchairRig"

-- COLLISION GROUPS
PhysicsService:RegisterCollisionGroup("Wheelchair")
PhysicsService:RegisterCollisionGroup("RagdollCharacter")
PhysicsService:RegisterCollisionGroup("Player")
PhysicsService:RegisterCollisionGroup("SeatedPlayer")

-- RULES
PhysicsService:CollisionGroupSetCollidable("RagdollCharacter", "Wheelchair", false)
PhysicsService:CollisionGroupSetCollidable("SeatedPlayer", "Wheelchair", false)
PhysicsService:CollisionGroupSetCollidable("SeatedPlayer", "Player", false) -- Optional: prevent seated players from hitting walking ones

-- SIM 46.0: Create CrashEjectEvent for ragdoll fling
local CrashEjectEvent = Instance.new("RemoteEvent")
CrashEjectEvent.Name = "CrashEjectEvent"
CrashEjectEvent.Parent = ReplicatedStorage

-- MINIGAME: Create MountMinigameEvent for Tug-of-War UI
local MountMinigameEvent = Instance.new("RemoteEvent")
MountMinigameEvent.Name = "MountMinigameEvent"
MountMinigameEvent.Parent = ReplicatedStorage

local ragdollingCharacters = {}

-- Helper: Set character collision group
local function setCharacterCollisionGroup(char, groupName)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = groupName
        end
    end
end

-- MINIGAME: Handle Minigame Success (Server Force Sit)
MountMinigameEvent.OnServerEvent:Connect(function(player, targetSeat, success)
    if not targetSeat or not targetSeat:IsA("VehicleSeat") then return end
    
    -- If success is nil or true, it's a pass. If false, it's a cancellation.
    if success == false then
        targetSeat:SetAttribute("MinigameActive", false)
        return
    end

    if targetSeat.Occupant then return end -- Seat taken
    
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    
    print("WheelchairService: MountMinigameEvent Received from", player.Name, "| Success:", success)
    
    if hum and root and hum.Health > 0 then
        local dist = (root.Position - targetSeat.Position).Magnitude
        print("WheelchairService: Distance to seat:", math.floor(dist))
        
        -- Distance check sanity (Increased for debug)
        if dist < 50 then
            print("WheelchairService: Seating Lockdown START")
            local chair = targetSeat.Parent
            
            -- 1. HARD BRAKE: Stop all player movement
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            
            -- 2. STATE RESET & PHYSICS GHOST
            hum.PlatformStand = false
            hum.Sit = false
            setCharacterCollisionGroup(char, "SeatedPlayer")
            
            -- 3. CLEAN TRANSITION: Pivot then Sit
            char:PivotTo(targetSeat.CFrame * CFrame.new(0, 0.5, 0))
            
            -- 4. FORCE SIT
            print("WheelchairService: Calling targetSeat:Sit(hum)")
            hum:ChangeState(Enum.HumanoidStateType.Seated)
            targetSeat:Sit(hum)
            hum.Sit = true
            
            targetSeat:SetAttribute("MinigameActive", false)
            print("WheelchairService: Seating Flow COMPLETE")
        else
            warn("WheelchairService: Seating Failed - Player too far (", dist, ")")
        end
    end
end)

-- DISMOUNT HANDLER: Restore collisions when player leaves chair
local function monitorSeating(player, character)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
        if not humanoid.SeatPart then
            -- Player just got out
            setCharacterCollisionGroup(character, "Player")
            print("WheelchairService: Player dismounted, restored Player collision group")
        end
    end)
end

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
				5,      -- Density (Increased from 1 for Stability)
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
    
    -- 2. Unseat any occupant AND Destroy Prompts
    local seat = chairModel:FindFirstChildWhichIsA("VehicleSeat", true)
    if seat then
        if seat.Occupant then
            seat.Occupant.Jump = true
        end
        seat.Disabled = true -- Prevent reuse
        seat:ClearAllChildren() -- Wipes prompts, sounds, scripts
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

-- Helper to "Smush" the character (Scale Y down) and spawn blood
local function smushAndSplatter(char, attacker, impactVelocity)
    if not char then return end
    
    -- 1. Play Squish Sound
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then
        local sound = Instance.new("Sound")
        sound.SoundId = SMUSH_SOUND_ID
        sound.Volume = 2
        sound.RollOffMaxDistance = 100
        sound.Parent = root
        sound:Play()
        game:GetService("Debris"):AddItem(sound, 2)
    end
    
    -- 2. Flatten (Smush)
    local hum = char:FindFirstChild("Humanoid")
    if hum then
       -- R15 Scale (If compatible)
       local scale = hum:FindFirstChild("BodyHeightScale")
       if scale then
           scale.Value = 0.1
       end
    end
    
    -- 3. DISAPPEAR VICTIM (Ghost Mode)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("Decal") then
            -- Make invisible but keep anchored/collision off for blood paint
            part.Transparency = 1
            if part:IsA("BasePart") then
                part.CollisionGroup = "Debris" 
                part.CanCollide = false 
                part.CanTouch = false
                part.CanQuery = false 
                part.Anchored = true
                part.CastShadow = false
            end
        end
    end
    
    -- 4. FIRE CLIENT EVENT (Visuals)
    local pos = root and root.Position or char:GetPivot().Position
    BloodEvent:FireAllClients(pos, Vector3.new(0, 1, 0), char, attacker, impactVelocity)
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
        -- FIX: DON'T turn the Seat into debris. Destroy it to kill the prompt.
        if part:IsA("VehicleSeat") then
            part:Destroy()
            continue
        end

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
        
        -- Must be moving or falling to crush
        -- FIX: Track Last Velocity to catch impacts where velocity becomes 0 instantly
        local vel = attackerRoot.AssemblyLinearVelocity
        local speed = vel.Magnitude
        
        -- ALWAYS SCAN (Remove gates) - Logic determines kill, not detection
        -- This ensures we catch "Sitting on top" (Monster Truck) even if speed is 0
        
        -- FIX: MUST BE SEATED TO CRUSH (User Request)
        if not attackerHum.SeatPart or not attackerHum.SeatPart:IsA("VehicleSeat") then
            continue 
        end
        
        -- FIX: Identify the chair the attacker is ACTUALLY sitting in (Stolen or Owned)
        local attackerWheelchair = nil
        if attackerHum.SeatPart then
            attackerWheelchair = attackerHum.SeatPart.Parent
        end
        local ownedChair = workspace:FindFirstChild(attacker.Name .. "_Wheelchair")
        
        -- HIT DETECTION
        local hitInstance = nil
        
        -- Shared Params
        local filterList = {attackerChar}
        if attackerWheelchair then table.insert(filterList, attackerWheelchair) end
        if ownedChair and ownedChair ~= attackerWheelchair then table.insert(filterList, ownedChair) end
        
        local params = OverlapParams.new()
        params.FilterDescendantsInstances = filterList
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.MaxParts = 10
        
        -- A: GRAVITY CRUSH (BoxCast Down)
        -- ALWAYS CHECK DOWN (Catch Monster Truck cases)
        -- A: GRAVITY CRUSH (BoxCast Down)
        -- ALWAYS CHECK DOWN (Catch Monster Truck cases)
        local boxCFrame = attackerRoot.CFrame * CFrame.new(0, -1.5, 0) -- Forgiving check (-1.5)
        local boxSize = Vector3.new(8, 8, 8) -- HUGE box (8) to make aiming easier
        
        local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)
        if #parts > 0 then
             for _, p in ipairs(parts) do
                local m = p:FindFirstAncestorOfClass("Model")
                if m and (m:FindFirstChildOfClass("Humanoid") or string.find(m.Name, "_Wheelchair")) then
                    hitInstance = p
                    break
                end
            end
        end
            
        -- B: RAM CRUSH (BoxCast Forward)
        if not hitInstance then
            local boxCFrame = attackerRoot.CFrame * CFrame.new(0, 0, -3) 
            local boxSize = Vector3.new(4, 5, 4) 
            
            local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)
            if #parts > 0 then
                 for _, p in ipairs(parts) do
                    local m = p:FindFirstAncestorOfClass("Model")
                    if m and (m:FindFirstChildOfClass("Humanoid") or string.find(m.Name, "_Wheelchair")) then
                        hitInstance = p
                        print("DEBUG: Ram Box Hit:", p.Name)
                        break
                    end
                end
            end
        end
        
        if not hitInstance then continue end
        
        -- Check if hit part belongs to another player's wheelchair
        local hitPart = hitInstance
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        
        if not hitModel then continue end
        
        local victimChar
        local victimWheelchair
        
        -- Case A: Hit the Wheelchair directly
        if string.find(hitModel.Name, "_Wheelchair") then
            victimWheelchair = hitModel
            local victimName = string.gsub(hitModel.Name, "_Wheelchair", "")
            
            local p = Players:FindFirstChild(victimName)
            if p then 
                if p == attacker then continue end
                victimChar = p.Character 
            else
                victimChar = workspace:FindFirstChild(victimName)
            end
            
        -- Case B: Hit the Character directly
        elseif hitModel:FindFirstChildOfClass("Humanoid") then
            victimChar = hitModel
            if victimChar == attackerChar then continue end 
            
            local victimHum = victimChar:FindFirstChildOfClass("Humanoid")
            if victimHum and victimHum.SeatPart then
                victimWheelchair = victimHum.SeatPart.Parent
            else
                 victimWheelchair = workspace:FindFirstChild(victimChar.Name .. "_Wheelchair")
            end
        end
        
        if not victimChar then continue end
        
        -- FIX: PREVENT SUICIDE
        if victimWheelchair and victimWheelchair == attackerWheelchair then continue end
        
        local victimHum = victimChar:FindFirstChildOfClass("Humanoid")
        if not victimHum or victimHum.Health <= 0 then 
            -- print("DEBUG: Victim Dead/Nil Health") 
            continue 
        end
        
        -- NUANCED CRUSH LOGIC
        local validCrush = false
        local splatterDir = nil
        
        -- Logic: Compare Horizontal Speed vs Fall Speed
        local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        local vertSpeed = math.abs(vel.Y)
        
        -- print("DEBUG CHECK:", victimChar.Name, "H:", math.floor(horizSpeed), "V:", math.floor(vertSpeed), "Chair:", (victimWheelchair and "Yes" or "No"))
        
        if victimWheelchair then
            -- WHEELCHAIRS: Only vulnerable to Extreme Falls
            if vertSpeed > 60 then
                 validCrush = true
                 print("⬇️ HARD LANDING:", attacker.Name, "crushed chair of", victimChar.Name)
            end
        else
            -- PEDESTRIANS: Vulnerable to everything
            
            -- FIX: Prioritize Gravity Crush (User: "Jumping on them should be a crush")
            -- Check Vertical First. Threshold lowered from 60 to 25 (Standard Jump)
            if vertSpeed > 25 then
                -- GRAVITY MODE (Fountain Splatter)
                validCrush = true
                -- splatterDir = nil (Implicit Fountain)
                print("⬇️ GRAVITY / SQUASH:", attacker.Name, "landed on", victimChar.Name)
                
            elseif horizSpeed > 15 then
                -- RAM MODE (Forward Splatter)
                -- Only if NOT falling significantly
                validCrush = true
                -- ADD ARC: Low Upward Velocity (5) just to clear the floor
                splatterDir = (vel * 0.8) + Vector3.new(0, 5, 0)
                print("🚙 RUN OVER / RAM:", attacker.Name, "flattened", victimChar.Name)
            end
        end
        
        if not validCrush then continue end
        
        -- CRUSH EXECUTION
        -- FRIENDLY FIRE: Skip if attacker and victim are on the same team
        local attackerPlayer = Players:GetPlayerFromCharacter(attacker.Character or attacker)
        local victimPlayer   = Players:GetPlayerFromCharacter(victimChar)
        local attackerName   = attackerPlayer and attackerPlayer.Name or (attacker.Name)
        local victimName     = victimPlayer   and victimPlayer.Name   or victimChar.Name
        if sameTeam(attackerName, victimName) then return end

        crushDebounce[attacker] = true
        
        -- Trigger Effects (Sound, Blood, Disappear)
        smushAndSplatter(victimChar, attacker, splatterDir)
        
        -- Kill Victim
        victimHum.Health = 0
        if victimWheelchair then
            explodeWheelchair(victimWheelchair)
        end
        
        -- AWARD KILL
        local ls = attacker:FindFirstChild("leaderstats")
        local kills = ls and ls:FindFirstChild("Kills")
        if kills then
            kills.Value = kills.Value + 1
            
            -- NOTIFY CLIENT (Kill Feed)
            local KillEvent = ReplicatedStorage:FindFirstChild("KillEvent")
            if KillEvent then
                local method = (splatterDir) and "Flattened" or "Crushed"
                KillEvent:FireClient(attacker, victimChar.Name, method)
            end
            
            -- GAME KILL TRACKING: Count all kills (players + dummies)
            fireGameKill(attacker, nil)
        end
        
        task.delay(0.5, function() -- Faster logic?
            crushDebounce[attacker] = nil
        end)
    end
end)
  


local characterSetupLock = {} -- Prevents double-execution per character

local function onCharacterAdded(character)
	-- DEBOUNCE: prevent double wheelchair spawn if CharacterAdded fires twice
	if characterSetupLock[character] then
		warn("WheelchairService: Double CharacterAdded for", character.Name, "— skipping")
		return
	end
	characterSetupLock[character] = true

	-- Also destroy any existing wheelchair for this character (stale from prior run)
	local existingChair = workspace:FindFirstChild(character.Name .. "_Wheelchair")
	if existingChair then
		warn("WheelchairService: Destroying stale wheelchair for", character.Name)
		existingChair:Destroy()
	end

	print("WheelchairService: Character Added", character.Name)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	-- Cleanup lock when character is removed
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			characterSetupLock[character] = nil
		end
	end)

	-- 1. Disable Jumping & Set Collision Group
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
    setCharacterCollisionGroup(character, "Player")

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
	
	-- Assign wheelchair parts to Wheelchair CollisionGroup and Tag them
	for _, part in ipairs(newChair:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Wheelchair"
            CollectionService:AddTag(part, "IgnoredWheelchairPart") -- FIX: Persistent ID for raycast ignore
		end
	end
	
	print("WheelchairService: Cloned Chair", newChair)
	
	-- 2.5 Auto-Weld the chair parts
	-- We prefer the PrimaryPart, but fallback to the VehicleSeat if not set.
	local vehicleSeat = newChair:FindFirstChildWhichIsA("VehicleSeat", true)
    
    -- FIX: CLICK E TO SIT (User Request)
    if vehicleSeat then
        vehicleSeat.Disabled = true -- Disable Touch-to-Sit
        
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
                    
                    -- MINIGAME: Instead of sitting, tell client to start minigame UI
                    -- vehicleSeat:Sit(hum) 
                    vehicleSeat:SetAttribute("MinigameActive", true) -- STOP DESPAWN
                    MountMinigameEvent:FireClient(playerWhoTriggered, vehicleSeat)
                end
            end
        end)
        
        -- FIX: Hide Prompt when Occupied
        vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
            prompt.Enabled = (vehicleSeat.Occupant == nil)
        end)
    end
    
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
		stabilizer.MaxTorque = 100000 -- Default stability (prevents tipping on spawn)
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
                -- PHYSICS GHOST: Use CollisionGroups for instant, efficient exclusion
                setCharacterCollisionGroup(character, "SeatedPlayer")
				
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
                            
                            if not ragdollingCharacters[character] then
                                -- Restore normal Player collision group
                                setCharacterCollisionGroup(character, "Player")
                            else
                                -- Delayed cleanup: wait for ragdoll recovery before destroying constraints
                                task.spawn(function()
                                    while ragdollingCharacters[character] do task.wait(0.1) end
                                    setCharacterCollisionGroup(character, "Player")
                                    print("WheelchairService: Player group restored after recovery")
                                end)
                            end
                            
                            -- 1. LINEAR DRAG (CrawlBrake) - Using BodyVelocity for per-axis MaxForce (LinearVelocity MaxForce is scalar)
                            if not crawlBrake then
                                crawlBrake = Instance.new("BodyVelocity")
                                crawlBrake.Name = "CrawlBrake"
                                crawlBrake.Velocity = Vector3.zero
                                crawlBrake.MaxForce = Vector3.new(5000, 0, 5000) -- X/Z Braking ONLY (Gravity works)
                                crawlBrake.P = 1250
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
                                    if brake and brake:IsA("BodyVelocity") then
                                        if up.Y > 0.85 then
                                             -- Upright: Strong X/Z Hold
                                            brake.MaxForce = Vector3.new(5000, 0, 5000)
                                        else
                                            -- Tipped: Stronger X/Z Hold
                                            brake.MaxForce = Vector3.new(8000, 0, 8000)
                                        end
                                    end
                                    task.wait(0.2)
                                end
                            end)
                            
                            -- 4. DO NOT ANCHOR IMMEDIATELY (Let it fall)
                            -- BUT anchor 2 seconds after hitting ground (User Request: Fix infinite slide)
                            print("WheelchairService: Engaging Physics Brakes (Gravity Allowed)")
                            
                            -- 4. GROUND ANCHOR LOGIC (Raycast Loop)
                            -- User Request: Anchor 1s after hitting ground (or 1s after dismount if already on ground)
                            local anchorLoop
                            anchorLoop = task.spawn(function()
                                local startTime = os.clock()
                                
                                -- Wait until chair is valid and empty
                                while not seat.Occupant and primaryPart and primaryPart:IsDescendantOf(workspace) do
                                    -- Raycast Down to check for ground
                                    local params = RaycastParams.new()
                                    params.FilterDescendantsInstances = {newChair, character}
                                    params.FilterType = Enum.RaycastFilterType.Exclude
                                    
                                    local ray = workspace:Raycast(primaryPart.Position, Vector3.new(0, -4, 0), params)
                                    
                                    if ray then
                                        print("WheelchairService: Ground Verified via Raycast - Waiting 1s to Anchor")
                                        task.wait(1) 
                                        
                                        -- Re-verify after wait
                                        if not seat.Occupant and primaryPart and primaryPart:IsDescendantOf(workspace) then
                                            primaryPart.AssemblyLinearVelocity = Vector3.zero
                                            primaryPart.AssemblyAngularVelocity = Vector3.zero
                                            
                                            -- Upright
                                            local pos = primaryPart.Position
                                            local _, yaw, _ = primaryPart.CFrame:ToEulerAnglesYXZ()
                                            primaryPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
                                            
                                            primaryPart.Anchored = true
                                            print("WheelchairService: Chair Anchored (1s Delay)")
                                            
                                            if crawlBrake then crawlBrake:Destroy() end
                                            if spinBrake then spinBrake:Destroy() end
                                        end
                                        break -- Exit loop once anchored
                                    end
                                    
                                    -- Security Timeout (10s)
                                    if os.clock() - startTime > 10 then 
                                        print("WheelchairService: Anchor Loop Interface Timeout")
                                        break 
                                    end
                                    
                                    task.wait(0.1) -- Check 10 times a second
                                end
                            end)
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
        -- FIX: Delay destruction so chair can be stolen (6 seconds)
        -- FIX: Smart "Abandonment" Logic (User Request)
        -- 1. If someone is IN it, don't destroy.
        -- 2. If nobody is in it, destroy after 5s.
        -- 3. If someone gets OUT, restart 5s timer.
        
        local seat = newChair:FindFirstChildWhichIsA("VehicleSeat", true)
        if not seat then 
            task.delay(5, function() if newChair then newChair:Destroy() end end)
            return 
        end
        
        local abandonmentTask = nil
        
        local function startCleanupTimer()
            if abandonmentTask then task.cancel(abandonmentTask) end
            abandonmentTask = task.delay(5, function()
                if newChair and newChair.Parent and not seat.Occupant then
                    print("WheelchairService: Abandoned chair cleanup")
                    newChair:Destroy()
                end
            end)
        end
        
        -- Initial check: If empty, start timer
        if not seat.Occupant then
            startCleanupTimer()
        end
        
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
            
            -- 2. PHYSICS GHOST: Use CollisionGroups for instant, efficient exclusion
            setCharacterCollisionGroup(char, "SeatedPlayer")
            
            -- 3. Disable Jump State
            occupantHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
        end
        
        -- Monitor for stealing/abandoning
        local conn
        conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
            if not newChair or not newChair.Parent then
                if conn then conn:Disconnect() end
                return
            end
            
            if seat.Occupant then
                -- Someone stole it! Cancel cleanup
                if abandonmentTask then task.cancel(abandonmentTask) end
                print("WheelchairService: Chair stolen! Cleanup cancelled.")
                
                -- PHYSICS FIX: Full setup for new driver
                setupOccupantPhysics(newChair, seat.Occupant)
            else
                -- They left (switched chairs?). Restart cleanup.
                print("WheelchairService: Chair abandoned. Cutting power & Cleanup in 5s...")
                
                -- GRAVITY FIX: Zero all forces so it falls!
                -- If we don't do this, the last known VectorForce (Suspension) keeps it floating.
                for _, desc in pairs(newChair:GetDescendants()) do
                    if desc:IsA("VectorForce") then
                        desc.Force = Vector3.zero
                    elseif desc:IsA("LinearVelocity") then
                        desc.MaxForce = 0
                    elseif desc:IsA("AngularVelocity") then
                        desc.MaxTorque = 0
                    elseif desc:IsA("AlignOrientation") then
                        desc.MaxTorque = 0
                    end
                end
                
                startCleanupTimer()
            end
        end)
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
        onCharacterAdded(character)
        monitorSeating(player, character)
    end)
	-- If the character already exists (e.g. playing solo test), run it immediately
	if player.Character then
		onCharacterAdded(player.Character)
        monitorSeating(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Iterate existing players if script starts late
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end




