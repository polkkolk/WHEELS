local DEST_CFRAME = CFrame.new(362, 11.5, -1979)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local isTeleporting = {}

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

local trigger = script.Parent:WaitForChild("Trigger")

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

RunService.Heartbeat:Connect(function()
    local activePlayers = Players:GetPlayers()
    if #activePlayers == 0 then return end

    local filterList = {}
    for _, player in ipairs(activePlayers) do
        if player.Character then table.insert(filterList, player.Character) end
        local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
        if chair then table.insert(filterList, chair) end
    end

    overlapParams.FilterDescendantsInstances = filterList

    local partsInPortal = workspace:GetPartsInPart(trigger, overlapParams)

    local hitPlayers = {}
    for _, part in ipairs(partsInPortal) do
        local model = part.Parent
        local player = Players:GetPlayerFromCharacter(model)

        if not player then
            player = Players:GetPlayerFromCharacter(model.Parent)
        end

        if not player and model and model.Name:match("_Wheelchair$") then
            local pName = model.Name:gsub("_Wheelchair$", "")
            player = Players:FindFirstChild(pName)
        end

        if player then
            hitPlayers[player] = true
        end
    end

    for player, _ in pairs(hitPlayers) do
        if not isTeleporting[player.UserId] then
            isTeleporting[player.UserId] = true
            EnterChallengeBindable:Fire(player, DEST_CFRAME)
            task.delay(3, function()
                if player then
                    isTeleporting[player.UserId] = nil
                end
            end)
        end
    end
end)
