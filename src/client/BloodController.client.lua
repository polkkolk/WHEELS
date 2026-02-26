local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService") -- FIX: Define globally

-- Wait for Event
local BloodEvent = ReplicatedStorage:WaitForChild("BloodEvent", 10)

-- Assets
local BLOOD_POOL_ID = "rbxassetid://1383591891"   -- Detailed Puddle
local BLOOD_SPLAT_ID = "rbxassetid://10295261909" -- Wall Splatter
local GORE_CHUNKS = 15



local function createProjectile(startPos, velocity, ignoreList, spawnBlobFunc, sizeScale)
	sizeScale = sizeScale or 1
	local part = Instance.new("Part")
	part.Name = "BloodProjectile"
	part.Size = Vector3.new(0.2, 0.2, 0.2) * sizeScale
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 0, 0) -- Bright Red Neon for visibility in air
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Position = startPos
	part.Parent = Workspace
	
	-- Trail
	local att0 = Instance.new("Attachment", part)
	att0.Position = Vector3.new(-0.1, 0, 0) * sizeScale
	local att1 = Instance.new("Attachment", part)
	att1.Position = Vector3.new(0.1, 0, 0) * sizeScale
	
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.FaceCamera = true
	trail.Lifetime = 0.2
	trail.WidthScale = NumberSequence.new(1 * sizeScale)
	trail.Color = ColorSequence.new(Color3.fromRGB(120, 0, 0)) -- Crimson Trail
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Parent = part
	
	-- Physics Loop
	local t = 0
	local pos = startPos
	local vel = velocity
	local conn
	
	conn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		if t > 5 or not part.Parent then -- Increased to 5s to ensure ground hit
			conn:Disconnect()
			if part.Parent then part:Destroy() end
			return
		end
		
		local lastPos = pos
		-- Gravity + Drag
		-- Increased gravity for faster fall (was -50)
		vel = vel + Vector3.new(0, -100, 0) * dt 
		pos = pos + vel * dt
		
		-- Raycast (Move)
		local dir = pos - lastPos
		local dist = dir.Magnitude
		
		if dist > 0 then
			local params = RaycastParams.new()
			local filter = {part, Workspace.CurrentCamera}
			if ignoreList then
				for _, obj in ipairs(ignoreList) do table.insert(filter, obj) end
			end
			params.FilterDescendantsInstances = filter
			params.FilterType = Enum.RaycastFilterType.Exclude
			
			local result = Workspace:Raycast(lastPos, dir, params)
			if result then
				-- Hit!
				conn:Disconnect()
				part:Destroy() -- visuals only
				
				-- Spawn Splash using the UNIFIED Blob Logic
                -- We use the hit position as the center
                if spawnBlobFunc then
                    -- Scale the blob size by sizeScale (default 2-4 studs * scale)
                    local blobSize = (math.random(20, 40)/10) * sizeScale
                    spawnBlobFunc(result.Position, blobSize, result)
                end
				return
			end
		end
		
		part.Position = pos
		part.CFrame = CFrame.lookAt(pos, pos + vel)
	end)
end

local function onBloodEvent(pos, normal, victim, attacker, bloodType)
	-- Use a GLOBAL persistent folder so new rays ignore old splatters
	local debrisFolder = Workspace:FindFirstChild("BloodDebrisSystem")
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "BloodDebrisSystem"
		debrisFolder.Parent = Workspace
	end

	-- 0. INSTANT GHOST MODE (Client Side)
	-- Force local invisible/non-collidable state to prevent race conditions with Server replication
	-- ONLY for "Crush" events (nil bloodType), NOT gunshots!
	if victim and bloodType ~= "Gunshot" then
		for _, part in ipairs(victim:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanQuery = false
				part.CanTouch = false
				part.CanCollide = false
				part.CollisionGroup = "Debris"
			end
		end
	end

	-- 1. EXPLOSIVE SURFACE PAINTING (Coats everything in range)
	local paintParams = RaycastParams.new()
	local ignoreList = {victim, debrisFolder, game.Players.LocalPlayer.Character}
	
	-- FIX: IGNORE ATTACKER & THEIR WHEELCHAIR (Prevent floating blood on attacker's chair)
	if attacker then
		-- If attacker is a Player object, get character
		if attacker:IsA("Player") and attacker.Character then
			table.insert(ignoreList, attacker.Character)
		elseif attacker:IsA("Model") then
			table.insert(ignoreList, attacker) -- Dummy attacker
		end
		
		local attackerChair = Workspace:FindFirstChild(attacker.Name .. "_Wheelchair")
		if attackerChair then
			table.insert(ignoreList, attackerChair)
		end
	end
	
	-- FIX: IGNORE ALL WHEELCHAIR PARTS (Tagged by Server)
	-- This handles Intact Chairs, Exploded Debris, and Orphaned Parts
	local chairParts = CollectionService:GetTagged("IgnoredWheelchairPart")
	for _, part in ipairs(chairParts) do
		table.insert(ignoreList, part)
	end
	
	-- Robust Search: Use CollectionService to find ALL debris near the victim
	-- (CollectionService is now Global)
	
	-- Wait briefly for replication
	task.wait(0.1)
	
	local allDebris = CollectionService:GetTagged("BloodDebris")
	local foundDebris = false
	
	for _, item in ipairs(allDebris) do
		-- Handle both Models (old way) and BaseParts (new orphaned way)
		local itemPos = nil
		if item:IsA("BasePart") then
			itemPos = item.Position
		elseif item:IsA("Model") then
			itemPos = item:GetPivot().Position
		end
		
		if itemPos and (itemPos - pos).Magnitude < 20 then
			table.insert(ignoreList, item)
			foundDebris = true
		end
	end
    
	if foundDebris then
		print("BloodController: Found Tagged Debris near victim")
	else
		warn("BloodController: NO DEBRIS FOUND - Paint might be blocked!")
	end
	
	paintParams.FilterDescendantsInstances = ignoreList
	paintParams.FilterType = Enum.RaycastFilterType.Exclude
	

	
	-- 2. MAIN PUDDLE (Massive Cohesive Blob)
	-- Instead of 300 tiny circles, spawn 1 massive core + 3-5 lobes for irregularity
	
	local function spawnBlob(centerPos, finalSize, overrideResult)
		-- Raycast down to find floor ONLY if overrideResult is nil
        local res = overrideResult
        if not res then
            res = Workspace:Raycast(centerPos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), paintParams)
        end
        
		if not res then return end
		
		-- FINAL FILTER: Reject hits on non-map objects
		if res.Instance.CollisionGroup == "Wheelchair" or 
		   res.Instance.CollisionGroup == "Debris" or 
		   res.Instance.CollisionGroup == "Player" then 
            print("BLOCKED BLOOD ON:", res.Instance.Name, "Group:", res.Instance.CollisionGroup)
			return 
		end
		
		-- REJECT UNANCHORED: Only paint static map geometry (anchored parts like walls, floors, etc.)
		if not res.Instance.Anchored then
			return
		end
		
		-- REJECT VICTIM: Explicit check in case IgnoreList failed or Ghost Mode lagged
		if victim and res.Instance:IsDescendantOf(victim) then
			print("BLOCKED VICTIM HIT:", res.Instance.Name)
			return
		end
		
		-- DEBUG: What did we actually hit?
		print("Blood Hit:", res.Instance:GetFullName(), "Anchor:", res.Instance.Anchored)
		
		local splat = Instance.new("Part")
		splat.Name = "BloodBlob"
		-- Start small, tween big
		splat.Size = Vector3.new(0.1, 0.1, 0.1) 
		splat.Shape = Enum.PartType.Block
		
		-- GEOMETRY BLOOD: Solid, Wet, Smooth
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.1, 1) -- Keep Y extremely thin
		mesh.Parent = splat
		
		splat.Color = Color3.fromRGB(120, 0, 0) -- Crimson (Bright enough to not be purple)
		splat.Material = Enum.Material.SmoothPlastic
		splat.Transparency = 0 -- Opaque (Solid to hide seams)
		splat.Reflectance = 0 -- No Purple Sky Reflection
		
		splat.Anchored = true
		splat.CanCollide = false
		splat.CanTouch = false
		splat.CanQuery = false
		splat.CastShadow = false
		splat.CollisionGroup = "Debris"
		
		-- Align Y (Thin) to Normal
		local hitPos = res.Position + (res.Normal * 0.05)
		splat.CFrame = CFrame.lookAt(hitPos, hitPos + res.Normal) * CFrame.Angles(math.rad(90), 0, 0)
		splat.Parent = debrisFolder
		
		-- Tween Size for "Spreading" effect (Grow)
		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local goal = {Size = Vector3.new(finalSize, 0.1, finalSize)}
		TweenService:Create(splat, tweenInfo, goal):Play()
		
		-- Random Spin
		splat.CFrame = splat.CFrame * CFrame.Angles(0, math.random() * 6, 0)
        
        -- CLEANUP: "Seep into Ground" Animation
        task.delay(8, function()
            if not splat or not splat.Parent then return end
            -- Fade out and Shrink over 2 seconds
            local fadeInfo = TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
            local fadeGoal = {
                Transparency = 1,
                Size = Vector3.new(0.1, 0.1, 0.1) -- Shrink to nothing
            }
            local tween = TweenService:Create(splat, fadeInfo, fadeGoal)
            tween:Play()
            tween.Completed:Connect(function()
                splat:Destroy()
            end)
        end)
	end

    -- === GUNSHOT HANDLER (Single Projectile) ===
    -- Placed HERE so 'spawnBlob' and 'paintParams' are fully defined!
    if bloodType == "Gunshot" then
        -- Direction: Bullet Exit (away from shooter)
        local outDir = normal
        local spread = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5) * 0.2 -- Tighter spread
        local finalDir = (outDir + spread + Vector3.new(0, 0.2, 0)).Unit
        
        -- High velocity for gunshot impact
        local vel = finalDir * math.random(40, 60)
        
        -- Use the FULL ignore list (paintParams.FilterDescendantsInstances)
        -- This ensures the projectile passes through the victim/chair safely!
        -- SIZE SCALE: 0.5 (50% smaller for gunshots)
        createProjectile(pos, vel, paintParams.FilterDescendantsInstances, spawnBlob, 0.5)
        return
    end

	-- A. Central Core (The Big One)
	spawnBlob(pos, math.random(100, 140)/10) -- 10-14 Studs
	
	-- B. Irregular Lobes (Attached to side)
	for i = 1, math.random(3, 5) do
		local angle = math.random() * math.pi * 2
		local dist = math.random(40, 70)/10 -- 4-7 Studs away
		local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		
		spawnBlob(pos + offset, math.random(50, 90)/10) -- 5-9 Studs
	end

	-- 3. EXPLOSIVE SPLATTER (Random Directions - REDUCED COUNT, LARGER BLOBS)
	for i = 1, 25 do -- Was 300! Drastically reduced density
		-- Random sphere direction + downward bias
		local dir = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5).Unit
		if dir.Y > 0 then dir = dir * Vector3.new(1, -0.5, 1) end -- Bias down
		
        local size = math.random(30, 60) / 10 -- 3.0 to 6.0 Studs (Medium Blobs, not dots)
		spawnBlob(pos + (dir * 2), size) -- Spawn slightly offset
	end

	-- A. Spherical Burst (Walls/Ceiling/Wheelchair Sides)
	for i = 1, 15 do 
		local dir = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5).Unit
		local size = math.random(20, 40) / 10 -- 2-4 Studs
        
        local res = Workspace:Raycast(pos, dir * 14, paintParams)
        if res then
            -- Use the unified spawnBlob for consistency
            spawnBlob(res.Position, size, res)
        end
	end
	
	-- B. Downward Saturate (Floor/Seat - Guaranteed Coating)
	for i = 1, 10 do -- Was 100!
		local offset = Vector3.new(math.random(-6, 6), math.random(0, 5), math.random(-6, 6))
		spawnBlob(pos + offset, math.random(30, 50)/10)
	end

	-- 3. PROJECTILES (Droplets that fly out)
	-- FIX: Use Modifier (bloodType/splatterDir) if valid Vector3
	local directionalVel = nil
	if typeof(bloodType) == "Vector3" then
		directionalVel = bloodType
	end
	
	for i = 1, 60 do -- Increased from 30 (Double the gore)
		local vel
		if directionalVel then
			-- DIRECTIONAL: Use Server Velocity + Random Spread
			-- Spread should be relative to speed (faster = tighter cone?)
			local spreadScale = 0.4 
			local spread = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5) * directionalVel.Magnitude * spreadScale
			vel = directionalVel + spread
		else
			-- FOUNTAIN: Random Explosion (Gravity Crush default)
			local angle = math.random() * math.pi * 2
			local spread = math.random(10, 40)  -- Wider spread (was 5-25)
			local upward = math.random(30, 80) -- Higher launch (was 20-45)
			vel = Vector3.new(math.cos(angle) * spread, upward, math.sin(angle) * spread)
		end
		
		createProjectile(pos + Vector3.new(0, 2, 0), vel, ignoreList, spawnBlob)
	end
	
	-- WALL-SEEKER PROJECTILES: Horizontal droplets that hit walls & vertical surfaces
	-- These supplement the fountain (which mostly hits the floor with gravity)
	for i = 1, 15 do
		local angle = math.random() * math.pi * 2
		local hSpeed = math.random(25, 55) -- Fast horizontal so they reach walls
		-- Slight random vertical tilt: mostly horizontal, can go slightly up or down
		local vTilt = math.random(-15, 10) -- Negative = slight down, positive = slight up
		local vel = Vector3.new(math.cos(angle) * hSpeed, vTilt, math.sin(angle) * hSpeed)
		createProjectile(pos + Vector3.new(0, 1, 0), vel, ignoreList, spawnBlob, 0.8)
	end
end

if BloodEvent then
	BloodEvent.OnClientEvent:Connect(onBloodEvent)
end
