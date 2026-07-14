-- ChallengeService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

-- Register TrafficCone collision group: collides with floor AND with Wheelchair
pcall(function()
    PhysicsService:RegisterCollisionGroup("TrafficCone")
end)
task.delay(1, function()
    pcall(function()
        -- FALSE = wheelchair drives straight through cones (no recoil).
        -- Must be delayed to ensure WheelchairService has registered 'Wheelchair' first.
        PhysicsService:CollisionGroupSetCollidable("TrafficCone", "Wheelchair", false)
        -- Also ignore the player's character limbs so they don't clip and push the chair up
        PhysicsService:CollisionGroupSetCollidable("TrafficCone", "SeatedPlayer", false)
        PhysicsService:CollisionGroupSetCollidable("TrafficCone", "Player", false)
        PhysicsService:CollisionGroupSetCollidable("TrafficCone", "RagdollCharacter", false)
    end)
end)

local function getRemote(name)
    local r = ReplicatedStorage:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = ReplicatedStorage
    end
    return r
end

local EnterChallengeEvent = getRemote("EnterChallengeEvent")
local ChallengeCompleteEvent = getRemote("ChallengeCompleteEvent")
local ConeHitEvent = getRemote("ConeHitEvent")
local EnableConeHighlightsEvent = getRemote("EnableConeHighlightsEvent")

local function getBindable(name)
    local b = ReplicatedStorage:FindFirstChild(name)
    if not b then
        b = Instance.new("BindableEvent")
        b.Name = name
        b.Parent = ReplicatedStorage
    end
    return b
end
local EnterChallengeBindable = getBindable("EnterChallengeBindable")

-- Lobby location to return to (find the actual SpawnLocation in workspace)
local LOBBY_SPAWN
for _, child in ipairs(workspace:GetChildren()) do
    if child:IsA("SpawnLocation") then
        LOBBY_SPAWN = child.CFrame.Position
        break
    end
end
if not LOBBY_SPAWN then
    warn("[ChallengeService] No SpawnLocation found! Falling back to origin.")
    LOBBY_SPAWN = Vector3.new(0, 50, 0)
end

-- State tracking
local activePlayers = {} -- [UserId] = { startTime, hits, conesHit = {} }
local REQUIRED_HITS = 50

-- COIN SYSTEM: Per-cycle cooldown (prevents double-completing for rewards)
local challengeCompletedThisCycle = {} -- [UserId] = true

local originalConeCFrames = {}

local function resetRoomCones(room, enableHighlight)
    local movedCount = 0
    for coneModel, origCF in pairs(originalConeCFrames) do
        if coneModel and coneModel.Parent and (coneModel:IsDescendantOf(room) or coneModel:IsDescendantOf(workspace)) then
            -- Fallback: if there are rooms but cones are in workspace directly, just assign them loosely
            local isAssignedToThisRoom = coneModel:IsDescendantOf(room)
            if room == workspace then isAssignedToThisRoom = true end
            
            if isAssignedToThisRoom then
                movedCount = movedCount + 1
                local primary = coneModel.PrimaryPart
                if primary then
                    for _, p in ipairs(coneModel:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Anchored = true
                            p.AssemblyLinearVelocity = Vector3.zero
                            p.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                    
                    local trail = primary:FindFirstChildWhichIsA("Trail")
                    if trail then trail:Destroy() end
                    
                    coneModel:PivotTo(origCF)
                    
                    for _, p in ipairs(coneModel:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Anchored = false
                        elseif p:IsA("SelectionBox") and p.Name == "ConeHighlight" then
                            p.Visible = enableHighlight or false
                        end
                    end
                end
            end
        end
    end
    print("[ChallengeService] resetRoomCones for", room.Name, "— reset", movedCount, "cones. Highlight:", enableHighlight)
end

local pendingRooms = {} -- [UserId] = room

local function assignRoom()
    local rooms = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:match("^ChallengeTrafficConeRoom%d*$") then
            table.insert(rooms, obj)
        end
    end
    
    table.sort(rooms, function(a, b)
        -- Extract numbers for sorting (e.g., ChallengeTrafficConeRoom1 -> 1)
        local numA = tonumber(a.Name:match("%d+")) or 0
        local numB = tonumber(b.Name:match("%d+")) or 0
        return numA < numB
    end)
    
    if #rooms == 0 then return workspace end
    
    for _, room in ipairs(rooms) do
        local isOccupied = false
        for _, state in pairs(activePlayers) do
            if state.room == room then
                isOccupied = true
                break
            end
        end
        for _, pending in pairs(pendingRooms) do
            if pending == room then
                isOccupied = true
                break
            end
        end
        if not isOccupied then return room end
    end
    return nil -- All rooms full
end

-- ─── 1. CONE HIT DETECTION ──────────────────────────────────────────────────
-- Iterate over the whole workspace and attach Touched events to any model named "ChallengeTrafficCone"
-- (Ideally we'd use CollectionService Tags for this, but scanning by name works if the map is static)

local function setupCone(coneModel)
    if coneModel:GetAttribute("_SetupComplete") then return end
    coneModel:SetAttribute("_SetupComplete", true)

    -- Remove any existing ground welds or grouped welds
    coneModel:BreakJoints()

    -- Find the main part to attach the touch event to
    local primary = coneModel.PrimaryPart
    if not primary then
        -- fallback to first BasePart
        for _, child in ipairs(coneModel:GetDescendants()) do
            if child:IsA("BasePart") then
                primary = child
                break
            end
        end
    end
    
    if not primary then return end
    
    -- Ensure PrimaryPart is set on the model (needed for PivotTo in resetAllCones)
    coneModel.PrimaryPart = primary
    
    -- Save original position for resetting later (must be before unanchoring)
    if not originalConeCFrames[coneModel] then
        originalConeCFrames[coneModel] = coneModel:GetPivot()
    end
    
    -- Ensure the cone is physically simulated so we can fling it
    -- Weld everything to primary part first
    for _, part in ipairs(coneModel:GetDescendants()) do
        if part:IsA("BasePart") and part ~= primary then
            local w = Instance.new("WeldConstraint")
            w.Part0 = primary
            w.Part1 = part
            w.Parent = primary
        end
    end
    
    -- Now unanchor all parts and assign to TrafficCone collision group
    local allParts = {}
    for _, part in ipairs(coneModel:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CollisionGroup = "TrafficCone"
            part.CanQuery = false -- Exclude completely from Wheelchair bumper raycasts!
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            table.insert(allParts, part)
        end
    end
    
    -- Add invisible hitbox part 1.5x the cone's size for easier hits
    local hitbox = Instance.new("Part")
    hitbox.Name = "ConeHitbox"
    -- Very very very slightly increase the hitbox (was 2.0 extra, now 2.5)
    hitbox.Size = primary.Size * 1.5 + Vector3.new(2.5, 0, 2.5)
    hitbox.CFrame = primary.CFrame
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.CanQuery = false
    hitbox.CollisionGroup = "TrafficCone"
    hitbox.Massless = true
    hitbox.Parent = coneModel
    local hitboxWeld = Instance.new("WeldConstraint")
    hitboxWeld.Part0 = primary
    hitboxWeld.Part1 = hitbox
    hitboxWeld.Parent = hitbox
    table.insert(allParts, hitbox)
    
    -- SelectionBox for green highlight
    for _, part in ipairs(coneModel:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "ConeHitbox" then
            local box = Instance.new("SelectionBox")
            box.Name = "ConeHighlight"
            box.Color3 = Color3.fromRGB(0, 255, 80) -- Bright green
            box.LineThickness = 0.05
            box.SurfaceColor3 = Color3.fromRGB(0, 255, 80)
            box.SurfaceTransparency = 0.5
            box.Adornee = part
            box.Parent = part
            box.Visible = false
        end
    end

    
    local function onConeHit(hit)
        local char = hit.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if not player then
            player = Players:GetPlayerFromCharacter(char.Parent)
            if player then char = char.Parent end
        end
        -- Check if it's a Wheelchair model
        if not player and char and char.Name:match("_Wheelchair$") then
            local pName = char.Name:gsub("_Wheelchair$", "")
            player = Players:FindFirstChild(pName)
        end
        if not player then return end
        
        local state = activePlayers[player.UserId]
        if not state then return end -- Player isn't in a challenge run
        
        -- 🌪 ALWAYS FLING THE CONE ON HIT
        -- Fling direction = away from the hit point, with small upward bias
        local flingDir = (primary.Position - hit.Position)
        if flingDir.Magnitude < 0.01 then flingDir = Vector3.new(0, 1, 0) end
        flingDir = Vector3.new(flingDir.X, math.abs(flingDir.Y) + 0.3, flingDir.Z).Unit
        
        -- Scale impulse to the wheelchair's actual speed
        local chairSpeed = hit.AssemblyLinearVelocity.Magnitude
        local speedFactor = math.clamp(chairSpeed / 30, 0.3, 2.0)
        local force = speedFactor * 1.5 * primary.AssemblyMass
        primary:ApplyImpulse(flingDir * force)
        
        -- Spin the cone: speed-scaled tumble
        local spinStrength = speedFactor * 40
        primary:ApplyAngularImpulse(Vector3.new(
            math.random(-100, 100) / 100 * spinStrength,
            math.random(-100, 100) / 100 * spinStrength * 0.5,
            math.random(-100, 100) / 100 * spinStrength
        ) * primary.AssemblyMass)
        
        -- ✨ MOTION BLUR TRAIL: appears on hit, fades out naturally
        if not primary:FindFirstChildWhichIsA("Trail") then
            local a0 = Instance.new("Attachment")
            a0.Position = Vector3.new(-primary.Size.X / 2, 0, 0)
            a0.Parent = primary
            local a1 = Instance.new("Attachment")
            a1.Position = Vector3.new(primary.Size.X / 2, 0, 0)
            a1.Parent = primary
            local trail = Instance.new("Trail")
            trail.Attachment0 = a0
            trail.Attachment1 = a1
            trail.Lifetime = math.clamp(speedFactor * 0.6, 0.2, 1.0)
            trail.MinLength = 0
            trail.FaceCamera = true
            trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
            trail.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.0),
                NumberSequenceKeypoint.new(1, 1.0),
            })
            trail.WidthScale = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            })
            trail.LightEmission = 0.4
            trail.Parent = primary
        end
        
        -- Stop here for SoccerBall (no scoring)
        if coneModel.Name == "SoccerBall" then return end
        
        -- Prevent counting the same cone twice for the same player run
        if state.conesHit[coneModel] then return end
        
        -- Mark as hit
        state.conesHit[coneModel] = true
        state.hits = state.hits + 1
        
        -- Disable green highlight on first scoring hit
        for _, p in ipairs(coneModel:GetDescendants()) do
            if p:IsA("SelectionBox") and p.Name == "ConeHighlight" then
                p.Visible = false
            end
        end
        
        -- Tell Client to update UI counter
        ConeHitEvent:FireClient(player, state.hits, REQUIRED_HITS)
        
        -- Check win condition
        if state.hits >= REQUIRED_HITS then
            local finalTime = tick() - state.startTime
            
            -- Stop their run so they don't trigger anything else
            activePlayers[player.UserId] = nil
            player:SetAttribute("InChallenge", nil)
            
            -- COIN REWARD (only if not already completed this cycle)
            local coinReward = 0
            if not challengeCompletedThisCycle[player.UserId] then
                if finalTime <= 30 then
                    coinReward = 30
                elseif finalTime <= 60 then
                    coinReward = 15
                else
                    coinReward = 5
                end
                
                if player:GetAttribute("OwnsVIP") then
                    coinReward = math.floor(coinReward * 1.25)
                end
                
                -- Award coins
                local ls = player:FindFirstChild("leaderstats")
                if ls then
                    local coins = ls:FindFirstChild("Money")
                    local hs = player:FindFirstChild("HiddenStats")
                    local lifetime = hs and hs:FindFirstChild("LifetimeCoins")
                    if coins then coins.Value = coins.Value + coinReward end
                    if lifetime then lifetime.Value = lifetime.Value + coinReward end
                    print("🪙 Challenge coins:", coinReward, "to", player.Name, "(time:", string.format("%.1f", finalTime) .. "s)")
                end
                
                -- Mark as completed this cycle
                challengeCompletedThisCycle[player.UserId] = true
            else
                print("🪙 Challenge already completed this cycle for", player.Name, "— no coins")
            end
            
            -- Disable highlight
            resetRoomCones(state.room or workspace, false)
            
            -- Teleport to lobby IMMEDIATELY so the win screen shows in the lobby
            local teleportFn = ServerStorage:FindFirstChild("TeleportWheelchair")
            if teleportFn then
                teleportFn:Invoke(player, CFrame.new(LOBBY_SPAWN + Vector3.new(0, 3, 0)))
            end
            
            -- THEN tell Client to show the score widget (player is already in lobby)
            ChallengeCompleteEvent:FireClient(player, finalTime, coinReward)
        end
    end
    
    -- Attach hit listener to ALL parts of the cone, so touching the tip counts
    for _, p in ipairs(allParts) do
        p.Touched:Connect(onConeHit)
    end
end

-- Re-run this whenever new cones are added (if map is cloned)
local function bindAllCones()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "SoccerBall" and obj:IsA("BasePart") then
            local model = Instance.new("Model")
            model.Name = "SoccerBall"
            model.PrimaryPart = obj
            obj.Parent = model
            model.Parent = workspace
            setupCone(model)
        elseif obj:IsA("Model") and (obj.Name == "ChallengeTrafficCone" or obj.Name == "SoccerBall") then
            setupCone(obj)
        end
    end
end
bindAllCones()

-- If map is generated dynamically, listen for new cones
workspace.DescendantAdded:Connect(function(obj)
    if obj.Name == "SoccerBall" and obj:IsA("BasePart") then
        local model = Instance.new("Model")
        model.Name = "SoccerBall"
        model.PrimaryPart = obj
        obj.Parent = model
        model.Parent = workspace
        setupCone(model)
    elseif obj:IsA("Model") and (obj.Name == "ChallengeTrafficCone" or obj.Name == "SoccerBall") then
        setupCone(obj)
    end
end)

-- ─── 2. ENTERING THE CHALLENGE (Triggered by Portal Script via Bindable) ─────
local challengeEntering = {} -- Debounce: prevent multiple fires per player

local ROOM_START_CFRAMES = {
    ChallengeTrafficConeRoom1 = CFrame.lookAt(Vector3.new(362, 11.5, -1979), Vector3.new(362, 11.5, -2000)) * CFrame.Angles(0, math.rad(-90), 0),
    ChallengeTrafficConeRoom2 = CFrame.lookAt(Vector3.new(2362, 11.5, -1979), Vector3.new(2362, 11.5, -2000)) * CFrame.Angles(0, math.rad(-90), 0)
}

EnterChallengeBindable.Event:Connect(function(player, fallbackDestCFrame)
    -- Hard guard: if already entering, ignore all subsequent fires from the Heartbeat scanner
    if challengeEntering[player.UserId] then return end
    
    local room = assignRoom()
    if not room then
        print("🚨 All challenge rooms are full! Player", player.Name, "must wait.")
        return
    end
    pendingRooms[player.UserId] = room
    
    challengeEntering[player.UserId] = true
    -- Reset debounce after 3 seconds no matter what, so they can re-enter if it fails
    task.delay(3, function()
        challengeEntering[player.UserId] = nil
    end)
    
    player:SetAttribute("InChallenge", true) -- Set IMMEDIATELY to block round joining during intro
    
    -- Figure out destination
    local destCFrame = fallbackDestCFrame
    if room ~= workspace then
        if ROOM_START_CFRAMES[room.Name] then
            destCFrame = ROOM_START_CFRAMES[room.Name]
        else
            local startPoint = room:FindFirstChild("StartPoint")
            if startPoint then
                destCFrame = startPoint.CFrame * CFrame.Angles(0, math.rad(-90), 0)
            end
        end
    end
    
    -- Snap cones back to start for the new attempt automatically in this room and enable highlight
    resetRoomCones(room, true)
    
    -- Teleport the wheelchair
    local teleportFn = ServerStorage:FindFirstChild("TeleportWheelchair")
    if teleportFn and destCFrame then
        teleportFn:Invoke(player, destCFrame)
    end
    
    -- Fire UI-only event to client
    EnterChallengeEvent:FireClient(player)
    
    -- Wait for the 3-second intro card + 3-second countdown before tracking starts
    task.delay(6.8, function()
        pendingRooms[player.UserId] = nil
        if player and player:GetAttribute("InChallenge") then
            activePlayers[player.UserId] = {
                startTime = tick(),
                hits = 0,
                conesHit = {},
                room = room
            }
        end
    end)
end)

-- Cleanup disconnected players or global aborts
local function cleanupChallenge(player)
    pendingRooms[player.UserId] = nil
    challengeEntering[player.UserId] = nil
    local state = activePlayers[player.UserId]
    if state then
        activePlayers[player.UserId] = nil
        player:SetAttribute("InChallenge", nil)
        
        local room = state.room or workspace
        local am = room:FindFirstChild("ActiveCones")
        if am then
            local hl = am:FindFirstChild("RoomHighlight")
            if hl then hl.Enabled = false end
        end
        
        -- Fire abort to cleanly close UI
        ChallengeCompleteEvent:FireClient(player, 0, 0, true)
    end
end
Players.PlayerRemoving:Connect(cleanupChallenge)

-- Clean up if the player dies or respawns during challenge
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        cleanupChallenge(player)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hum.Died:Connect(function()
                cleanupChallenge(player)
            end)
        end
    end)
end)
-- Hook existing players
for _, p in ipairs(Players:GetPlayers()) do
    if p.Character then
        local hum = p.Character:FindFirstChild("Humanoid")
        if hum then
            hum.Died:Connect(function() cleanupChallenge(p) end)
        end
    end
end

-- COIN SYSTEM: Create the reset bindable EAGERLY so it's always available
-- (GameService will find and fire it at round_end; previously it was created lazily
-- by GameService which caused ChallengeService's WaitForChild to time out)
local challengeResetBindable = ServerStorage:FindFirstChild("ChallengeResetBindable")
if not challengeResetBindable then
    challengeResetBindable = Instance.new("BindableEvent")
    challengeResetBindable.Name = "ChallengeResetBindable"
    challengeResetBindable.Parent = ServerStorage
end
challengeResetBindable.Event:Connect(function()
    challengeCompletedThisCycle = {}
    print("🪙 Challenge cooldown reset for new cycle")
end)
