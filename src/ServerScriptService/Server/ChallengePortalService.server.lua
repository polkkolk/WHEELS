-- ChallengePortalService.server.lua
-- Rojo-synced server script. Finds ChallengeGateway at runtime,
-- disables ALL collisions, and runs Heartbeat detection.
-- No command bar or manual steps needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Wheelchair mesh seems to naturally face 90 degrees left of its lookVector.
-- We apply CFrame.Angles(0, math.rad(-90), 0) to rotate it 90 degrees right so it physically faces forward down the Z-track.
local DEST_CFRAME = CFrame.lookAt(Vector3.new(362, 11.5, -1979), Vector3.new(362, 11.5, -2000)) * CFrame.Angles(0, math.rad(-90), 0)
local GATEWAY_NAME = "ChallengeGateway"

-- Wait for the gateway model to exist in workspace
local gw = workspace:WaitForChild(GATEWAY_NAME, 30)
if not gw then
    warn("[ChallengePortalService] " .. GATEWAY_NAME .. " not found in workspace!")
    return
end

-- Force ALL descendant parts to be non-collidable AND non-queryable.
-- CanQuery = false prevents bumper RAYCASTS from detecting these parts as walls,
-- which was causing crash eject to fire before _Teleporting could replicate.
for _, part in ipairs(gw:GetDescendants()) do
    if part:IsA("BasePart") then
        part.CanCollide = false
        part.CanQuery = false
    end
end
print("[ChallengePortalService] Disabled collisions + raycasts on all gateway parts")

-- Destroy any old scripts inside the gateway (we handle everything now)
for _, child in ipairs(gw:GetChildren()) do
    if child:IsA("Script") or child:IsA("LocalScript") then
        print("[ChallengePortalService] Removing old script:", child.Name)
        child:Destroy()
    end
end

-- Find or create the Trigger volume
local trigger = gw:FindFirstChild("Trigger")
if not trigger then
    warn("[ChallengePortalService] No Trigger part found, creating one at gateway pivot")
    trigger = Instance.new("Part")
    trigger.Name = "Trigger"
    trigger.Size = Vector3.new(30, 30, 15)
    trigger.CFrame = gw:GetPivot()
    trigger.Anchored = true
    trigger.CanCollide = false
    trigger.CanQuery = true
    trigger.Transparency = 1
    trigger.Parent = gw
else
    trigger.Size = Vector3.new(30, 30, 15)
    trigger.CFrame = gw:GetPivot()
    trigger.CanCollide = false
    trigger.CanQuery = true  -- CRITICAL: re-enable after the gateway loop set it false
    trigger.Transparency = 1
end
print("[ChallengePortalService] Trigger ready:", trigger.Size)

-- Get or create the BindableEvent
local EnterChallengeBindable = ReplicatedStorage:FindFirstChild("EnterChallengeBindable")
if not EnterChallengeBindable then
    EnterChallengeBindable = Instance.new("BindableEvent")
    EnterChallengeBindable.Name = "EnterChallengeBindable"
    EnterChallengeBindable.Parent = ReplicatedStorage
end

-- Debounce table
local isTeleporting = {}

-- Heartbeat volume scanner
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

RunService.Heartbeat:Connect(function()
    local activePlayers = Players:GetPlayers()
    if #activePlayers == 0 then return end

    -- Build filter: characters + wheelchairs
    local filterList = {}
    for _, player in ipairs(activePlayers) do
        if player.Character then
            table.insert(filterList, player.Character)
        end
        local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
        if chair then
            table.insert(filterList, chair)
        end
    end
    overlapParams.FilterDescendantsInstances = filterList

    -- Scan for parts inside the trigger volume
    local partsInPortal = workspace:GetPartsInPart(trigger, overlapParams)

    -- Identify which players are inside
    local hitPlayers = {}
    for _, part in ipairs(partsInPortal) do
        local model = part.Parent
        local player = Players:GetPlayerFromCharacter(model)
        if not player then
            player = Players:GetPlayerFromCharacter(model and model.Parent)
        end
        if not player and model and model.Name:match("_Wheelchair$") then
            local pName = model.Name:gsub("_Wheelchair$", "")
            player = Players:FindFirstChild(pName)
        end
        if player then
            hitPlayers[player] = true
        end
    end

    -- Fire teleport for each detected player
    for player, _ in pairs(hitPlayers) do
        if not isTeleporting[player.UserId] then
            isTeleporting[player.UserId] = true
            
            -- Set _Teleporting BEFORE firing the bindable.
            -- The client's bumper raycasts will detect the portal Union parts
            -- and fire CrashEjectEvent. The server-side crash handler checks
            -- _Teleporting and rejects the crash — but ONLY if the flag is
            -- already set when the CrashEjectEvent arrives.
            local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
            if chair then
                local vSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
                if vSeat then
                    vSeat:SetAttribute("_Teleporting", true)
                end
            end
            
            print("[ChallengePortalService] Detected", player.Name, "- firing teleport")
            EnterChallengeBindable:Fire(player, DEST_CFRAME)
            task.delay(3, function()
                if player then
                    isTeleporting[player.UserId] = nil
                end
            end)
        end
    end
end)

print("[ChallengePortalService] Heartbeat scanner active")
