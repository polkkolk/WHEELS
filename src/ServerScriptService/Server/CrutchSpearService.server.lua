local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Ensure RemoteEvent exists
local CrutchStateEvent = ReplicatedStorage:FindFirstChild("CrutchStateEvent")
if not CrutchStateEvent then
    CrutchStateEvent = Instance.new("RemoteEvent")
    CrutchStateEvent.Name = "CrutchStateEvent"
    CrutchStateEvent.Parent = ReplicatedStorage
end

local CrutchThrowEvent = ReplicatedStorage:FindFirstChild("CrutchThrowEvent")
if not CrutchThrowEvent then
    CrutchThrowEvent = Instance.new("RemoteEvent")
    CrutchThrowEvent.Name = "CrutchThrowEvent"
    CrutchThrowEvent.Parent = ReplicatedStorage
end

local GunHitEvent = ReplicatedStorage:WaitForChild("GunHitEvent")
local BloodEvent = ReplicatedStorage:WaitForChild("BloodEvent")

local activeCrutches = {} -- Tracks players currently holding M1 with the crutch
local hitDebounces = {} -- To prevent hitting the same player multiple times per strike

local BASE_DAMAGE = 10
local SPEED_MULTIPLIER = 0.5 -- How much damage each stud/sec of speed adds

-- TEAM CHECK
local function sameTeam(attackerName, victimName)
    local fn = ServerStorage:FindFirstChild("GetPlayerTeam")
    if not fn then return false end
    local at = fn:Invoke(attackerName)
    local vt = fn:Invoke(victimName)
    return at ~= nil and at == vt
end

-- GAME KILL TRACKING
local function fireGameKill(attackerPlayer, victimPlayer)
    local bindable = ServerStorage:FindFirstChild("GameKillBindable")
    if bindable then
        bindable:Fire(attackerPlayer, victimPlayer)
    end
end

local function fixCrutchTool(tool)
    if not tool:IsA("Tool") or tool.Name ~= "CRUTCH SPEAR" then return end
    
    -- Ensure all parts in the crutch are unanchored and CanCollide false
    for _, part in ipairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.Massless = true
        end
    end
    
    if tool:FindFirstChild("Handle") then return end -- Already fixed

    local crutchHandle = tool:FindFirstChild("crutch handle")
    if crutchHandle then
        local realHandle = Instance.new("Part")
        realHandle.Name = "Handle"
        realHandle.Size = Vector3.new(0.5, 0.5, 0.5)
        realHandle.Transparency = 1
        realHandle.CanCollide = false
        realHandle.Massless = true
        realHandle.CFrame = crutchHandle.CFrame
        realHandle.Parent = tool
        
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = realHandle
        weld.Part1 = crutchHandle
        weld.Parent = realHandle
    end
end

-- Find the CRUTCH SPEAR from workspace, ReplicatedStorage, or ServerStorage and set it up
local function setupCrutchTool()
    local sourceCrutch = workspace:FindFirstChild("CRUTCH SPEAR") or ReplicatedStorage:FindFirstChild("CRUTCH SPEAR") or ServerStorage:FindFirstChild("CRUTCH SPEAR")
    
    if not sourceCrutch then
        warn("?? CRUTCH SPEAR not found anywhere. The weapon will not be available.")
        return
    end
    
    print("? Found CRUTCH SPEAR source:", sourceCrutch.ClassName, "in", sourceCrutch.Parent.Name)

    local finalTool
    if sourceCrutch:IsA("Tool") then
        finalTool = sourceCrutch:Clone()
    else
        -- Wrap the Model/Part in a Tool
        finalTool = Instance.new("Tool")
        finalTool.Name = "CRUTCH SPEAR"
        finalTool.CanBeDropped = false
        
        -- FLATTEN: Clone all BaseParts as direct children of the Tool
        -- This is critical because Roblox requires Handle to be a direct child
        local sourceClone = sourceCrutch:Clone()
        for _, desc in ipairs(sourceClone:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Parent = finalTool
            end
        end
        sourceClone:Destroy()
    end
    
    -- Make sure it can't be dropped
    finalTool.CanBeDropped = false
    
    -- Fix all parts: unanchor, no collide, massless
    for _, part in ipairs(finalTool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.Massless = true
        end
    end
    
    -- Now find or create the Handle (MUST be a direct child of Tool)
    local handle = finalTool:FindFirstChild("Handle")
    
    if not handle then
        -- Look for "crutch handle" (case-insensitive search) among direct children first
        for _, child in ipairs(finalTool:GetChildren()) do
            if child:IsA("BasePart") and child.Name:lower() == "crutch handle" then
                child.Name = "Handle"
                handle = child
                print("? Renamed 'crutch handle' to 'Handle' (direct child)")
                break
            end
        end
    end
    
    if not handle then
        -- Search descendants and reparent to be a direct child
        for _, desc in ipairs(finalTool:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name:lower() == "crutch handle" then
                desc.Name = "Handle"
                desc.Parent = finalTool -- Force as direct child
                handle = desc
                print("? Renamed and reparented 'crutch handle' to be direct child Handle")
                break
            end
        end
    end
    
    if not handle then
        -- Last resort: use first BasePart found
        for _, child in ipairs(finalTool:GetChildren()) do
            if child:IsA("BasePart") then
                child.Name = "Handle"
                handle = child
                print("? Using first BasePart as Handle:", child.Name)
                break
            end
        end
    end
    
    if not handle then
        warn("?? CRUTCH SPEAR has no BaseParts! Cannot create Handle.")
        return
    end
    
    -- Ensure Handle is a DIRECT child of Tool (Roblox requirement)
    if handle.Parent ~= finalTool then
        handle.Parent = finalTool
    end
    
    -- Make Handle visible (in case it was set transparent)
    -- handle.Transparency = 0 -- Uncomment if needed
    
    -- Debug: print all parts
    print("?? CRUTCH SPEAR parts:")
    for _, child in ipairs(finalTool:GetChildren()) do
        if child:IsA("BasePart") then
            print("   Part:", child.Name, "Size:", child.Size, "Transparency:", child.Transparency)
        end
    end
    
    -- Remove any existing welds/constraints that reference old parent structure
    -- Then re-weld everything to Handle
    for _, part in ipairs(finalTool:GetChildren()) do
        if part:IsA("BasePart") and part ~= handle then
            -- Create a weld to keep this part attached to Handle
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = handle
            weld.Part1 = part
            weld.Parent = handle
        end
    end
    
    -- Set RequiresHandle AFTER Handle exists
    finalTool.RequiresHandle = true
    
    -- Set grip so the handle is held properly
    finalTool.GripPos = Vector3.new(0, 0, 0)
    finalTool.GripForward = Vector3.new(0, 0, -1)
    finalTool.GripRight = Vector3.new(1, 0, 0)
    finalTool.GripUp = Vector3.new(0, 1, 0)
    
    -- Put in StarterPack and ServerStorage (for world drops)
    local sp = game:GetService("StarterPack")
    local old = sp:FindFirstChild("CRUTCH SPEAR")
    if old then old:Destroy() end
    finalTool.Parent = sp
    
    local oldSS = ServerStorage:FindFirstChild("CRUTCH SPEAR")
    if oldSS then oldSS:Destroy() end
    finalTool:Clone().Parent = ServerStorage
    
    -- Give to existing players
    for _, p in ipairs(Players:GetPlayers()) do
        if not p.Backpack:FindFirstChild("CRUTCH SPEAR") and not (p.Character and p.Character:FindFirstChild("CRUTCH SPEAR")) then
            finalTool:Clone().Parent = p.Backpack
        end
    end
    
    print("? CRUTCH SPEAR setup complete - added to StarterPack and distributed")
end

setupCrutchTool()

-- State event listener
CrutchStateEvent.OnServerEvent:Connect(function(player, isActive)
    if typeof(isActive) ~= "boolean" then return end
    
    -- Verify they actually have the crutch equipped
    local char = player.Character
    if not char then return end
    
    local tool = char:FindFirstChild("CRUTCH SPEAR")
    if not tool then
        isActive = false
    end
    
    activeCrutches[player] = isActive
    
    if isActive then
        hitDebounces[player] = {} -- Reset debounce on new swing
    else
        hitDebounces[player] = nil
    end
end)

-- Make sure we clean up if player leaves or unequips
Players.PlayerRemoving:Connect(function(player)
    activeCrutches[player] = nil
    hitDebounces[player] = nil
end)

RunService.Heartbeat:Connect(function()
    for player, isActive in pairs(activeCrutches) do
        if not isActive then continue end
        
        local char = player.Character
        if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
            activeCrutches[player] = false
            continue
        end
        
        local tool = char:FindFirstChild("CRUTCH SPEAR")
        if not tool then
            activeCrutches[player] = false
            continue
        end
        
        local myRoot = char.PrimaryPart
        if not myRoot then continue end
        
        local mySpeed = myRoot.AssemblyLinearVelocity.Magnitude
        
        -- Block if the attacker is ragdolled
        local myHum = char:FindFirstChild("Humanoid")
        if myHum and myHum:GetState() == Enum.HumanoidStateType.Physics then
            activeCrutches[player] = false
            continue
        end
        
        -- Spatial query: use OverlapParams to also detect parts with CanCollide=false
        -- (character limbs are typically CanCollide=false)
        local overlapParams = OverlapParams.new()
        overlapParams.FilterDescendantsInstances = {char}
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        
        -- Create a large 12x12x8 hitbox, centered 5 studs in front of the attacker.
        -- We make it 12 studs tall to cover vertical aiming, and 12 studs wide for better side detection.
        local hitBoxCFrame = myRoot.CFrame * CFrame.new(0, 0, -5)
        local hitBoxSize = Vector3.new(12, 12, 8)
        
        local hitList = {}
        local overlaps = workspace:GetPartBoundsInBox(hitBoxCFrame, hitBoxSize, overlapParams)
        
        for _, overlap in ipairs(overlaps) do
            local model = overlap:FindFirstAncestorOfClass("Model")
            if model and model ~= char and model:FindFirstChild("Humanoid") then
                hitList[model] = overlap
            end
        end
        
        if not hitDebounces[player] then hitDebounces[player] = {} end
        
        for hitModel, hitPart in pairs(hitList) do
            local hum = hitModel:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 and not hum:GetAttribute("IsDead") then
                -- LOBBY SAFE ZONE
                local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
                if victimPlayer then
                    if player:GetAttribute("InRound") == false then continue end
                    if victimPlayer:GetAttribute("InRound") == false then continue end
                end
                
                if sameTeam(player.Name, hitModel.Name) then continue end
                
                -- Check debounce
                if hitDebounces[player][hitModel] then
                    local lastHit = hitDebounces[player][hitModel]
                    if tick() - lastHit < 1.0 then continue end -- Can only hit the same player every 1.0s per swing
                end
                
                hitDebounces[player][hitModel] = tick()
                
                local theirRoot = hitModel.PrimaryPart
                local theirSpeed = theirRoot and theirRoot.AssemblyLinearVelocity.Magnitude or 0
                
                local totalSpeed = mySpeed + theirSpeed
                
                -- No damage if combined speed is below 5 studs/sec
                if totalSpeed < 5 then continue end
                
                local finalDamage = math.floor(BASE_DAMAGE + (totalSpeed * SPEED_MULTIPLIER))
                
                local wasAlive = true
                hum:TakeDamage(finalDamage)
                
                -- Kill logic
                if wasAlive and hum.Health <= 0 then
                    hum:SetAttribute("IsDead", true)
                    
                    local KillEvent = ReplicatedStorage:FindFirstChild("KillEvent")
                    if KillEvent then
                        KillEvent:FireClient(player, hitModel.Name, "Killed")
                    end
                    
                    local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
                    if victimPlayer then
                        local ls = player:FindFirstChild("leaderstats")
                        local kills = ls and ls:FindFirstChild("Kills")
                        if kills then
                            kills.Value = kills.Value + 1
                            local killsLeaderboardStore = game:GetService("DataStoreService"):GetOrderedDataStore("KillsLeaderboard")
                            pcall(function() killsLeaderboardStore:SetAsync(player.Name, kills.Value) end)
                            fireGameKill(player, victimPlayer)
                            
                            local VictimKillCamEvent = ReplicatedStorage:FindFirstChild("VictimKillCamEvent")
                            if VictimKillCamEvent then
                                VictimKillCamEvent:FireClient(victimPlayer, player)
                            end
                        end
                    end
                end
                
                local isHeadshot = (hitPart.Name == "Head" or hitPart.Name == "HeadHitbox")
                local isKill = (hum.Health <= 0) or (not wasAlive)
                
                -- Replicate damage numbers and blood
                GunHitEvent:FireClient(player, hitPart.Position, finalDamage, isHeadshot, "CRUTCH MELEE", isKill)
                
                local hitNormal = (hitPart.Position - myRoot.Position).Unit
                BloodEvent:FireAllClients(hitPart.Position, hitNormal, hitModel, player, "Gunshot")
            end
        end
    end
end)

CrutchThrowEvent.OnServerEvent:Connect(function(player, hitPart, hitPos, normal, originPos)
    local char = player.Character
    if not char then return end
    
    local tool = char:FindFirstChild("CRUTCH SPEAR")
    if not tool then
        -- Maybe it's still in ReplicatedStorage locally? Let's check backpack too just in case.
        tool = player.Backpack:FindFirstChild("CRUTCH SPEAR")
    end
    
    -- Destroy the crutch completely so it's gone from inventory
    if tool then tool:Destroy() end
    
    -- Hit validation and logic
    if hitPart then
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        local hum = hitModel and hitModel:FindFirstChild("Humanoid")
        
        if hum and hum.Health > 0 and not hum:GetAttribute("IsDead") and hitModel ~= char then
            -- LOBBY SAFE ZONE
            local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
            if victimPlayer then
                if player:GetAttribute("InRound") == false then return end
                if victimPlayer:GetAttribute("InRound") == false then return end
            end
            
            if sameTeam(player.Name, hitModel.Name) then return end
            
            local isHead = hitPart.Name == "Head" or (hitPart.Parent and hitPart.Parent:IsA("Accessory"))
            local damage = isHead and 100 or 60
            
            local wasAlive = true
            hum:TakeDamage(damage)
            
            if wasAlive and hum.Health <= 0 then
                hum:SetAttribute("IsDead", true)
                local KillEvent = ReplicatedStorage:FindFirstChild("KillEvent")
                if KillEvent then KillEvent:FireClient(player, hitModel.Name, "Killed") end
                
                local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
                if victimPlayer then
                    local ls = player:FindFirstChild("leaderstats")
                    local kills = ls and ls:FindFirstChild("Kills")
                    if kills then
                        kills.Value = kills.Value + 1
                        local store = game:GetService("DataStoreService"):GetOrderedDataStore("KillsLeaderboard")
                        pcall(function() store:SetAsync(player.Name, kills.Value) end)
                        fireGameKill(player, victimPlayer)
                        local vkc = ReplicatedStorage:FindFirstChild("VictimKillCamEvent")
                        if vkc then vkc:FireClient(victimPlayer, player) end
                    end
                end
            end
            
            local isKill = (hum.Health <= 0) or (not wasAlive)
            GunHitEvent:FireClient(player, hitPos, damage, isHead, "CRUTCH THROW", isKill)
            BloodEvent:FireAllClients(hitPos, normal, hitModel, player, "Gunshot")
        else
            -- Hit world geometry! Spawn the dropped crutch
            local dropped = ServerStorage:FindFirstChild("CRUTCH SPEAR") or ReplicatedStorage:FindFirstChild("CRUTCH SPEAR")
            if dropped then
                local worldDrop = Instance.new("Model")
                worldDrop.Name = "Dropped Crutch"
                
                local crutchParts = dropped:Clone()
                for _, desc in ipairs(crutchParts:GetDescendants()) do
                    if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end
                    if desc:IsA("BasePart") then
                        desc.Anchored = true
                        desc.CanCollide = false
                        desc.Parent = worldDrop
                    end
                end
                crutchParts:Destroy()
                
                local handle = worldDrop:FindFirstChild("Handle")
                if handle then
                    local cone = worldDrop:FindFirstChild("Cone") or worldDrop:FindFirstChild("cone")
                    worldDrop.PrimaryPart = cone or handle
                    
                    local rayDir = (hitPos - originPos).Unit
                    local embedPos = hitPos + rayDir * 1.5
                    local lookCF = CFrame.lookAt(embedPos, embedPos + rayDir) * CFrame.Angles(math.rad(-90), 0, 0)
                    
                    worldDrop:PivotTo(lookCF)
                    
                    local hl = Instance.new("Highlight")
                    hl.FillColor = Color3.new(0, 1, 0)
                    hl.OutlineColor = Color3.new(0, 0.8, 0)
                    hl.FillTransparency = 0.2 -- Much bolder
                    hl.OutlineTransparency = 0 -- Bolder outline
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Adornee = worldDrop
                    hl.Parent = worldDrop
                    
                    local prompt = Instance.new("ProximityPrompt")
                    prompt.ActionText = "Pick Up"
                    prompt.ObjectText = "Crutch Spear"
                    prompt.KeyboardKeyCode = Enum.KeyCode.E
                    prompt.RequiresLineOfSight = false
                    prompt.MaxActivationDistance = 15
                    prompt.Style = Enum.ProximityPromptStyle.Custom
                    prompt.Parent = handle
                    prompt.Triggered:Connect(function(playerWhoTriggered)
                        local sp = game:GetService("ServerStorage")
                        local sourceCrutch = sp:FindFirstChild("CRUTCH SPEAR")
                        if sourceCrutch then
                            -- Only give if they don't already have one
                            if not playerWhoTriggered.Backpack:FindFirstChild("CRUTCH SPEAR") and not (playerWhoTriggered.Character and playerWhoTriggered.Character:FindFirstChild("CRUTCH SPEAR")) then
                                local newTool = sourceCrutch:Clone()
                                newTool.Parent = playerWhoTriggered.Backpack
                            end
                            if worldDrop and worldDrop.Parent then
                                worldDrop:Destroy()
                            end
                        end
                    end)
                    
                    -- Destroy lodged crutch when the thrower dies
                    local conn
                    if player.Character then
                        local hum = player.Character:FindFirstChild("Humanoid")
                        if hum then
                            conn = hum.Died:Connect(function()
                                if worldDrop and worldDrop.Parent then
                                    worldDrop:Destroy()
                                end
                            end)
                        end
                    end
                    worldDrop.Destroying:Connect(function()
                        if conn then conn:Disconnect() end
                    end)
                end
                worldDrop.Parent = workspace
            end
        end
    end
end)

print("? CrutchSpearService Loaded")
