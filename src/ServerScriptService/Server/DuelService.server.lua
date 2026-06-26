local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DuelEvent = Instance.new("RemoteEvent")
DuelEvent.Name = "DuelEvent"
DuelEvent.Parent = ReplicatedStorage

-- Shared state for other services to check if player is in a duel
local IsPlayerDueling = Instance.new("BindableFunction")
IsPlayerDueling.Name = "IsPlayerDueling"
IsPlayerDueling.Parent = ServerStorage

local queue = {}
local activeDuel = {
    p1 = nil,
    p2 = nil,
    startTime = 0,
    duration = 180, -- 3 Minutes
    active = false
}

local function getRealPlayers()
    return Players:GetPlayers()
end

IsPlayerDueling.OnInvoke = function(player)
    if not player then return false end
    if not activeDuel.active then return false end
    return player == activeDuel.p1 or player == activeDuel.p2
end

-- Teleportation helper specifically for Duel (similar to GameService)
local function teleportPlayerWithChair(player, spawnPart)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local chairName = char.Name .. "_Wheelchair"
	local chair = workspace:FindFirstChild(chairName)
	if chair then
		chair:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0))
		for _, part in ipairs(chair:GetDescendants()) do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end

		local seat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
		local hum = char:FindFirstChild("Humanoid")
		if seat then
			if seat.Occupant == hum then return end
			char:PivotTo(seat.CFrame * CFrame.new(0, 0.5, 0))
			if hum and hum.Health > 0 and not seat.Occupant then
				seat:Sit(hum)
			end
		else
			hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 5, 0)
		end
	else
		hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 5, 0)
	end
end

local function returnToLobby(player)
    -- We force a LoadCharacter to reliably reset them to original lobby SpawnLocations
    if player and player.Parent then
        player:LoadCharacter()
    end
end

local function endDuel(winner, loser)
    print("⚔️ 1v1 Duel Ended. Winner:", winner and winner.Name or "Tie")
    
    -- Cleanup UI for both
    if activeDuel.p1 then DuelEvent:FireClient(activeDuel.p1, "duel_end") end
    if activeDuel.p2 then DuelEvent:FireClient(activeDuel.p2, "duel_end") end
    
    local p1 = activeDuel.p1
    local p2 = activeDuel.p2
    
    -- Teleport survivors safely back to lobby
    if p1 and p1.Character and p1.Character:FindFirstChild("Humanoid") and p1.Character.Humanoid.Health > 0 then
        returnToLobby(p1)
    end
    if p2 and p2.Character and p2.Character:FindFirstChild("Humanoid") and p2.Character.Humanoid.Health > 0 then
        returnToLobby(p2)
    end
    
    -- DUEL STATUS CLEARED IMMEDIATELY
    -- (We no longer wait for respawn because KillCam requires manual respawning,
    -- and GameService's activeRoundPlayers table already prevents hijacking)
    
    -- ONLY NOW DO WE CLEAR THE DUEL STATUS
    activeDuel.active = false
    activeDuel.p1 = nil
    activeDuel.p2 = nil
    
    -- Check queue to immediately start next match if enough people are waiting
    if #queue >= 2 then
        task.delay(2, function()
            -- Make sure the queue was not emptied while we waited for respawns
            if #queue >= 2 and not activeDuel.active then
                local next1 = table.remove(queue, 1)
                local next2 = table.remove(queue, 1)
                startDuel(next1, next2)
            end
        end)
    end
end

function startDuel(player1, player2)
    -- Validation
    if not player1 or not player2 or not player1.Parent or not player2.Parent then
        print("⚔️ Duel cancelled, players left game")
        return
    end

    local spawn1 = workspace:FindFirstChild("1v1 spawn 1")
    local spawn2 = workspace:FindFirstChild("1v1 spawn 2")
    if not spawn1 or not spawn2 then
        warn("⚔️ 1v1 spawn parts are missing from Workspace! Names must be exactly '1v1 spawn 1' and '1v1 spawn 2'")
        return
    end

    activeDuel.active = true
    activeDuel.p1 = player1
    activeDuel.p2 = player2
    activeDuel.startTime = os.time()

    print("⚔️ 1v1 Duel Starting:", player1.Name, "VS", player2.Name)

    -- Teleport immediately
    teleportPlayerWithChair(player1, spawn1)
    teleportPlayerWithChair(player2, spawn2)

    -- Tell clients to show the Top Bar Timer UI
    DuelEvent:FireClient(player1, "duel_start", activeDuel.duration)
    DuelEvent:FireClient(player2, "duel_start", activeDuel.duration)
    
    -- Monitor deaths and time
    local connection1, connection2
    local function onP1Died()
        if connection1 then connection1:Disconnect() end
        if connection2 then connection2:Disconnect() end
        if activeDuel.active then endDuel(player2, player1) end
    end
    local function onP2Died()
        if connection1 then connection1:Disconnect() end
        if connection2 then connection2:Disconnect() end
        if activeDuel.active then endDuel(player1, player2) end
    end

    if player1.Character and player1.Character:FindFirstChild("Humanoid") then
        connection1 = player1.Character.Humanoid.Died:Connect(onP1Died)
    end
    if player2.Character and player2.Character:FindFirstChild("Humanoid") then
        connection2 = player2.Character.Humanoid.Died:Connect(onP2Died)
    end
end

-- Handle joining the queue
DuelEvent.OnServerEvent:Connect(function(player, action)
    if action == "join_queue" then
        -- Prevent duplicates
        for _, qp in ipairs(queue) do
            if qp == player then return end
        end
        if activeDuel.p1 == player or activeDuel.p2 == player then return end
        
        table.insert(queue, player)
        print("⚔️", player.Name, "joined 1v1 Queue. Queue length:", #queue)
        
        -- Start automatically if we have 2 and no active duel
        if #queue >= 2 and not activeDuel.active then
            local p1 = table.remove(queue, 1)
            local p2 = table.remove(queue, 1)
            startDuel(p1, p2)
        end
    end
end)

-- Main 3-Minute Loop for draws
task.spawn(function()
    while true do
        task.wait(1)
        if activeDuel.active then
            local elapsed = os.time() - activeDuel.startTime
            local timeLeft = activeDuel.duration - elapsed
            
            if timeLeft >= 0 then
                if activeDuel.p1 then DuelEvent:FireClient(activeDuel.p1, "time_update", timeLeft) end
                if activeDuel.p2 then DuelEvent:FireClient(activeDuel.p2, "time_update", timeLeft) end
            else
                -- Time's up! Draw
                print("⚔️ 1v1 Duel Time Expired (Draw)")
                endDuel(nil, nil)
            end
        end
        
        -- Clean up dead queue members
        for i = #queue, 1, -1 do
            if not queue[i] or not queue[i].Parent then
                table.remove(queue, i)
            end
        end
    end
end)

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(player)
    for i = #queue, 1, -1 do
        if queue[i] == player then
            table.remove(queue, i)
        end
    end
    
    if activeDuel.active then
        if activeDuel.p1 == player then
            endDuel(activeDuel.p2, player)
        elseif activeDuel.p2 == player then
            endDuel(activeDuel.p1, player)
        end
    end
end)
