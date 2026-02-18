local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Wait for Event
local BloodEvent = ReplicatedStorage:WaitForChild("BloodEvent", 10)

-- Assets
local BLOOD_POOL_ID = "rbxassetid://1383591891"   -- Detailed Puddle
local BLOOD_SPLAT_ID = "rbxassetid://10295261909" -- Wall Splatter
local GORE_CHUNKS = 15



local function onBloodEvent(pos, normal, victim)
	-- Use a GLOBAL persistent folder so new rays ignore old splatters
	local debrisFolder = Workspace:FindFirstChild("BloodDebrisSystem")
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "BloodDebrisSystem"
		debrisFolder.Parent = Workspace
	end

	-- 1. EXPLOSIVE SURFACE PAINTING (Coats everything in range)
	local paintParams = RaycastParams.new()
	local ignoreList = {victim, debrisFolder, game.Players.LocalPlayer.Character}
	
	-- IGNORE PLAYER WHEELCHAIR (Prevent "Stuck in Air" blood)
	local myChair = Workspace:FindFirstChild(game.Players.LocalPlayer.Name .. "_Wheelchair")
	if myChair then
		table.insert(ignoreList, myChair)
	end
	
	-- Robust Search: Use CollectionService to find ALL debris near the victim
	local CollectionService = game:GetService("CollectionService")
	
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
	
	-- Helper to spawn a splatter
	local function paintSurface(rayOrigin, rayDir, forcedSize, forcedTexture)
		local result = Workspace:Raycast(rayOrigin, rayDir, paintParams)
		if result then
			local size = forcedSize or (math.random(20, 50) / 10)
			
			local splat = Instance.new("Part")
			splat.Name = "BloodSplat"
			-- Block logic is reliable for orientation
			splat.Size = Vector3.new(size, 0.05, size)
			splat.Shape = Enum.PartType.Block 
			
			
            -- GEOMETRY BLOOD: Use Mesh to make it round (Organic)
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = Enum.MeshType.Sphere
            -- Flatten the SPHERE mesh significantly to look like a liquid puddle
            mesh.Scale = Vector3.new(1, 0.1, 1) -- Super thin relative to size
            mesh.Parent = splat
            
            splat.Color = Color3.fromRGB(100, 0, 0) -- Deep Red
            splat.Material = Enum.Material.SmoothPlastic
            splat.Transparency = math.random(1, 3) / 10 -- 0.1 to 0.3 varaince for blending
			
            splat.Anchored = true
			splat.CanCollide = false
            splat.CanTouch = false
            splat.CanQuery = false
            splat.CastShadow = false
            splat.CollisionGroup = "Debris"
			
			-- Align Y (Top) to Surface Normal
			local hitPos = result.Position + (result.Normal * 0.05) -- Lower lift slightly (0.05) since mesh is thinner
			
			-- LookAt aligns -Z to target. 
			-- We want Y (Thin axis 0.05) to align with Normal.
			-- If we lookAt(hitPos, hitPos + Normal), -Z points to Normal.
			-- Rotate 90 deg on X to bring Y to -Z.
			splat.CFrame = CFrame.lookAt(hitPos, hitPos + result.Normal) * CFrame.Angles(math.rad(90), 0, 0)
			splat.Parent = debrisFolder
			
            -- Spin around local Y (Normal)
			splat.CFrame = splat.CFrame * CFrame.Angles(0, math.random() * 6, 0)
		end
	end
	
	-- 2. MAIN PUDDLE (Massive Cohesive Blob)
	-- Instead of 300 tiny circles, spawn 1 massive core + 3-5 lobes for irregularity
	
	local function spawnBlob(centerPos, finalSize)
		-- Raycast down to find floor for this specific blob part
		local res = Workspace:Raycast(centerPos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), paintParams)
		if not res then return end
		
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
	for i = 1, 15 do -- Was 200!
		local dir = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5).Unit
		local size = math.random(20, 40) / 10 -- 2-4 Studs
        
        local res = Workspace:Raycast(pos, dir * 14, paintParams)
        if res then
             -- Manual Blob Creation at Hit Point (Adapted from spawnBlob)
             local splat = Instance.new("Part")
             splat.Name = "BloodBlobSmall"
             splat.Size = Vector3.new(0.1, 0.1, 0.1)
             splat.Shape = Enum.PartType.Block
             
             local mesh = Instance.new("SpecialMesh")
             mesh.MeshType = Enum.MeshType.Sphere
             mesh.Scale = Vector3.new(1, 0.1, 1)
             mesh.Parent = splat
             
             splat.Color = Color3.fromRGB(80, 0, 0)
             splat.Material = Enum.Material.SmoothPlastic
             splat.Transparency = 0
             splat.Reflectance = 0
             
             splat.Anchored = true
             splat.CanCollide = false
             splat.CanTouch = false
             splat.CanQuery = false
             splat.CastShadow = false
             splat.CollisionGroup = "Debris"
             
             local hitPos = res.Position + (res.Normal * 0.05)
             splat.CFrame = CFrame.lookAt(hitPos, hitPos + res.Normal) * CFrame.Angles(math.rad(90), 0, 0)
             splat.Parent = debrisFolder
             
             local finalSize = size
             local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
             local goal = {Size = Vector3.new(finalSize, 0.1, finalSize)}
             TweenService:Create(splat, tweenInfo, goal):Play()
        end
	end
	
	-- B. Downward Saturate (Floor/Seat - Guaranteed Coating)
	for i = 1, 10 do -- Was 100!
		local offset = Vector3.new(math.random(-6, 6), math.random(0, 5), math.random(-6, 6))
		spawnBlob(pos + offset, math.random(30, 50)/10)
	end

end

if BloodEvent then
	BloodEvent.OnClientEvent:Connect(onBloodEvent)
end
