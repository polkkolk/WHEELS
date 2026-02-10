local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local WHEELCHAIR_NAME = "WheelchairRig"

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
                            
                            -- 1. LINEAR DRAG (CrawlBrake)
                            if not crawlBrake then
                                crawlBrake = Instance.new("LinearVelocity")
                                crawlBrake.Name = "CrawlBrake"
                                crawlBrake.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                                crawlBrake.VectorVelocity = Vector3.zero
                                crawlBrake.MaxForce = 800 -- Start with Glide
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
                                            brake.MaxForce = 800
                                        else
                                            brake.MaxForce = 1800
                                        end
                                    end
                                    task.wait(0.2)
                                end
                            end)
                        else
                            -- Player sat down, release the brakes
                            print("WheelchairService: Player seated - Releasing Brakes")
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
		if newChair then
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
