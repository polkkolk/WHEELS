local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

------------------------------------------------------------------------
-- REMOTE EVENTS (Client ↔ Server)
------------------------------------------------------------------------
local function getOrMakeRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local GameEvent  = getOrMakeRemote("GameEvent")  -- Server → All Clients
local VoteEvent  = getOrMakeRemote("VoteEvent")  -- Client → Server

local JoinRoundEvent = getOrMakeRemote("JoinRoundEvent") -- Client → Server (Late Join)

local VictimKillCamEvent = getOrMakeRemote("VictimKillCamEvent") -- Server → Victim
local KillCamRespawnEvent = getOrMakeRemote("KillCamRespawnEvent") -- Client → Server

-- Forward declaration for teleport & spawns
local teleportPlayerWithChair
local getSpawnParts

local DriftSyncEvent = getOrMakeRemote("DriftSyncEvent")
DriftSyncEvent.OnServerEvent:Connect(function(player, isDrifting)
    local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if chair then
        chair:SetAttribute("IsDrifting", isDrifting == true)
    end
end)

-- Disable AutoRespawn so we can manage the kill cam flow manually
Players.CharacterAutoLoads = false

local function fixAccessoryHitboxes(char)
    -- Make all current and future accessories transparent to raycasts
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Parent and part.Parent:IsA("Accessory") then
            part.CanQuery = false
        end
    end
    char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") and part.Parent and part.Parent:IsA("Accessory") then
            part.CanQuery = false
        end
    end)
end

-- Spawn players when they first join
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(fixAccessoryHitboxes)
	player:LoadCharacter()
end)


-- BINDABLE EVENT for server-to-server kill tracking
-- WheelchairService and GunService fire this when a real player is killed
local GameKillBindable = Instance.new("BindableEvent")
GameKillBindable.Name = "GameKillBindable"
GameKillBindable.Parent = ServerStorage

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local roundKills    = {}        -- [player] = killCount for this round
local votes         = {}        -- [player] = cardIndex voted for
local phase         = "idle"    -- "intermission" | "voting" | "round" | "end"
local playerTeams   = {}        -- [playerName] = "Red" | "Blue" (Team Battle only)
local currentModeCfg = nil      -- set in runRound, read by runEndOfRound
local activeRoundPlayers  = {}  -- [playerName] = true, set when player enters green circle

-- MUST be declared AFTER playerTeams so OnInvoke captures the real table
local GetPlayerTeam = Instance.new("BindableFunction")
GetPlayerTeam.Name   = "GetPlayerTeam"
GetPlayerTeam.Parent = ServerStorage
GetPlayerTeam.OnInvoke = function(playerName)
	return playerTeams[playerName]
end

local function getRealPlayers()
	return Players:GetPlayers()
end

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function broadcastPhase(phaseName, data)
	-- Mirror phase to ServerStorage for JoinRoundArea color updates
	do
		local _pv = ServerStorage:FindFirstChild('GamePhaseString')
		if _pv then
			if phaseName == 'intermission' or phaseName == 'voting' or phaseName == 'round' or phaseName == 'round_start' or phaseName == 'round_end' then
				_pv.Value = phaseName
			end
		end
	end
	local isDueling = ServerStorage:FindFirstChild("IsPlayerDueling")
	for _, p in ipairs(Players:GetPlayers()) do
        if isDueling then
            local success, result = pcall(function()
                return isDueling:Invoke(p)
            end)
            if success and result == true then
                continue
            end
        end
		GameEvent:FireClient(p, phaseName, data)
	end
end

local function resetRoundKills()
	roundKills = {}
	for _, p in ipairs(Players:GetPlayers()) do
		roundKills[p] = 0
	end
end

local function addKill(killerPlayer)
	if killerPlayer and Players:FindFirstChild(killerPlayer.Name) then
		roundKills[killerPlayer] = (roundKills[killerPlayer] or 0) + 1
		-- Broadcast updated kills table as a plain name→count table
		local killTable = {}
		for p, k in pairs(roundKills) do
			if Players:FindFirstChild(p.Name) then
				killTable[p.Name] = k
			end
		end
		local isDueling = ServerStorage:FindFirstChild("IsPlayerDueling")
		for _, p in ipairs(Players:GetPlayers()) do
            if isDueling then
                local success, result = pcall(function() return isDueling:Invoke(p) end)
                if success and result == true then continue end
            end
			GameEvent:FireClient(p, "kills_update", killTable)
		end
	end
end

-- Listen for kills from WheelchairService / GunService (server-to-server)
GameKillBindable.Event:Connect(function(killerPlayer, victimPlayer)
	if phase == "round" then
		addKill(killerPlayer)
	end
end)

------------------------------------------------------------------------
-- TEAM ASSIGNMENT
------------------------------------------------------------------------
local function assignTeams()
	playerTeams = {}
	local all = Players:GetPlayers()
	-- Shuffle (Fisher-Yates)
	for i = #all, 2, -1 do
		local j = math.random(i)
		all[i], all[j] = all[j], all[i]
	end
	for i, p in ipairs(all) do
		playerTeams[p.Name] = (i % 2 == 1) and "Red" or "Blue"
	end

	-- Always assign the two test dummies to fixed teams
	-- (They're workspace Models, not Players, but we track them in playerTeams for kill credit)
	if workspace:FindFirstChild("RedTeamDummy") then
		playerTeams["RedTeamDummy"] = "Red"
	end
	if workspace:FindFirstChild("BlueTeamDummy") then
		playerTeams["BlueTeamDummy"] = "Blue"
	end

	print("Teams assigned:", playerTeams)
end

------------------------------------------------------------------------
-- LEADERBOARD
------------------------------------------------------------------------
local function buildLeaderboard()
	local arr = {}
	for p, kills in pairs(roundKills) do
		if Players:FindFirstChild(p.Name) then
			table.insert(arr, {
				name   = p.Name,
				kills  = kills,
				userId = p.UserId,
				team   = playerTeams[p.Name],  -- nil for FFA
			})
		end
	end
	table.sort(arr, function(a, b) return a.kills > b.kills end)
	return arr
end

------------------------------------------------------------------------
-- SPAWN HELPERS
------------------------------------------------------------------------
getSpawnParts = function(mapName)
	-- Look for spawn pads in workspace.Map (user-placed SpawnLocations or Parts)
	local mapFolder = workspace:FindFirstChild("Map")
	if not mapFolder then
		warn("GameService: workspace.Map not found!")
		return {}
	end

	local parts = {}
	-- Collect all SpawnLocation and BasePart instances that look like spawns
	for _, child in ipairs(mapFolder:GetDescendants()) do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name:lower():find("spawn")) then
            if child:IsA("SpawnLocation") then
                child.Enabled = false
            end
			table.insert(parts, child)
		end
	end

	if #parts == 0 then
		warn("GameService: No spawn pads found in workspace.Map!")
	end
	return parts
end

-- Zero all velocity on a model (kills drift/momentum carry-over after teleport)
local function killMomentum(model)
	if not model then return end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity  = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- Also handle if model itself is a BasePart
	if model:IsA("BasePart") then
		model.AssemblyLinearVelocity  = Vector3.zero
		model.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Helper: move a player's wheelchair to a spawn point and re-seat them
teleportPlayerWithChair = function(player, char, spawnPart)
	local hrp = char and char:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	local chairName = char.Name .. "_Wheelchair"
	local chair = workspace:FindFirstChild(chairName)
    
    local TeleportWheelchair = ServerStorage:FindFirstChild("TeleportWheelchair")
    if chair and TeleportWheelchair then
        -- Use the central safe teleport function that preserves welds and ignores dismount logic
        TeleportWheelchair:Invoke(player, spawnPart.CFrame * CFrame.new(0, 3, 0))
        
        -- Force Network Ownership back to player immediately!
        local pPart = chair.PrimaryPart
        if pPart and pPart:CanSetNetworkOwnership() then
            pPart:SetNetworkOwner(player)
        end
    else
		-- FALLBACK: If chair totally failed to spawn or was destroyed, at least move the player!
		print("teleportPlayerWithChair: Wheelchair not found! Teleporting character manually.")
		char:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0))
		killMomentum(char)
    end
end

local function teleportPlayersToMap(mapName)
	local spawnParts = getSpawnParts(mapName)
	if #spawnParts == 0 then
		warn("GameService: No spawn parts found for", mapName)
		return
	end

	local players = getRealPlayers()
	for i, player in ipairs(players) do
        -- 1v1 Minigame Isolation Check
        local isDueling = ServerStorage:FindFirstChild("IsPlayerDueling")
        if isDueling then
            local success, result = pcall(function() return isDueling:Invoke(player) end)
            if success and result == true then continue end
        end
        
        -- Only teleport players who entered the green circle
        if not activeRoundPlayers[player.Name] then continue end
		local spawnPart = spawnParts[((i - 1) % #spawnParts) + 1]
		local char = player.Character
		if char then
			teleportPlayerWithChair(player, char, spawnPart)
		end
	end
end

local function teleportPlayersToLobby()
	-- Players respawn at their normal SpawnLocations; just reset them
	for _, player in ipairs(Players:GetPlayers()) do
        -- 1v1 Minigame Isolation Check
        local isDueling = ServerStorage:FindFirstChild("IsPlayerDueling")
        if isDueling then
            local success, result = pcall(function() return isDueling:Invoke(player) end)
            if success and result == true then continue end
        end
        
        -- Only teleport players who entered the green circle for the round
        if not activeRoundPlayers[player.Name] then continue end
        
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum then
			-- let the game handle respawn naturally
			player:LoadCharacter()
		end
	end
end

-- NOTE: buildLeaderboard() is defined above (line ~116) — do not redeclare here.

------------------------------------------------------------------------
-- VOTING
------------------------------------------------------------------------
local function runVoting()
	votes = {}
	phase = "voting"

	-- Build cards (one per map×gamemode combination — for now just 1 card repeated 3x)
	local cards = {}
	for i = 1, 3 do
		local mapIdx  = ((i - 1) % #GameConfig.Maps) + 1
		local modeIdx = ((i - 1) % #GameConfig.Gamemodes) + 1
		cards[i] = {
			mapName      = GameConfig.Maps[mapIdx].name,
			gamemodeName = GameConfig.Gamemodes[modeIdx].name,
			description  = GameConfig.Gamemodes[modeIdx].description,
			cardIndex    = i,
		}
	end

	broadcastPhase("voting", { cards = cards, duration = GameConfig.VotingTime })

	local t = 0
	local tickRate = 0.5
	while t < GameConfig.VotingTime do
		task.wait(tickRate)
		t = t + tickRate

		-- Build vote counts per card
		local counts = { 0, 0, 0 }
		local voterHeads = { {}, {}, {} } -- list of userIds per card
		for player, cardIdx in pairs(votes) do
			if Players:FindFirstChild(player.Name) then
				counts[cardIdx] = (counts[cardIdx] or 0) + 1
				table.insert(voterHeads[cardIdx], { name = player.Name, userId = player.UserId })
			end
		end
		broadcastPhase("vote_update", {
			counts     = counts,
			voterHeads = voterHeads,
			timeLeft   = GameConfig.VotingTime - t,
		})
	end

	-- Tally winner (most votes; tie → random among tied)
	local counts = { 0, 0, 0 }
	for _, cardIdx in pairs(votes) do
		counts[cardIdx] = (counts[cardIdx] or 0) + 1
	end

	local maxVotes = 0
	local winners  = {}
	for i = 1, 3 do
		if (counts[i] or 0) >= maxVotes then
			if (counts[i] or 0) > maxVotes then
				maxVotes = counts[i]
				winners = { i }
			else
				table.insert(winners, i)
			end
		end
	end
	local winnerCard = winners[math.random(1, #winners)]
	local mapIdx     = ((winnerCard - 1) % #GameConfig.Maps) + 1
	local modeIdx    = ((winnerCard - 1) % #GameConfig.Gamemodes) + 1
	return GameConfig.Maps[mapIdx], GameConfig.Gamemodes[modeIdx]
end

-- Accept votes from clients
VoteEvent.OnServerEvent:Connect(function(player, cardIndex)
	if phase == "voting" then
		if type(cardIndex) == "number" and cardIndex >= 1 and cardIndex <= 3 then
			votes[player] = cardIndex
		end
	end
end)

------------------------------------------------------------------------
-- INTERMISSION
------------------------------------------------------------------------
local function runIntermission()
	phase = "intermission"
	local t = GameConfig.IntermissionTime

	while t > 0 do
		broadcastPhase("intermission", { timeLeft = t })
		task.wait(1)
		t = t - 1
	end

	-- After timer expires, wait for enough players (non-spinning)
	local minPlayers = GameConfig.Gamemodes[1] and GameConfig.Gamemodes[1].minPlayers or 1
	while #Players:GetPlayers() < minPlayers do
		broadcastPhase("intermission", { timeLeft = 0, waitingForPlayers = true })
		print("🎮 Waiting for players:", #Players:GetPlayers(), "/", minPlayers)
		task.wait(5)
	end
end

------------------------------------------------------------------------
-- ROUND
------------------------------------------------------------------------
local function runRound(mapCfg, modeCfg)
	phase = "round"
	currentModeCfg = modeCfg   -- expose to runEndOfRound
	resetRoundKills()
	playerTeams = {}  -- clear teams from last round

	-- Assign teams for Team Battle rounds
	if modeCfg.teamBattle then
		assignTeams()
	end

	local currentMapVal = ServerStorage:FindFirstChild("CurrentMapCfg")
	if not currentMapVal then
		currentMapVal = Instance.new("StringValue")
		currentMapVal.Name = "CurrentMapCfg"
		currentMapVal.Parent = ServerStorage
	end
	currentMapVal.Value = mapCfg.name

	teleportPlayersToMap(mapCfg.name)
	task.wait(0.5) -- brief settle time before freeze

	-- Only send round_start to players who chose to join via the green circle.
	-- Lobby players should NOT receive this event (it shows the team card + kill HUD).
	local roundStartData = {
		mapName      = mapCfg.name,
		gamemodeName = modeCfg.name,
		duration     = modeCfg.duration,
		isTeamBattle = modeCfg.teamBattle or false,
		teams        = modeCfg.teamBattle and playerTeams or nil,
	}
	-- Still update the GamePhaseString so the green circle sees the phase change
	do
		local _pv = ServerStorage:FindFirstChild("GamePhaseString")
		if _pv then _pv.Value = "round" end
	end
    
	-- FORCE THE VOTING UI TO CLOSE FOR ALL PLAYERS (INCLUDING LOBBY SPECTATORS)
	broadcastPhase("voting_end")
	
	for _, p in ipairs(Players:GetPlayers()) do
		if activeRoundPlayers[p.Name] then
			GameEvent:FireClient(p, "round_start", roundStartData)
		end
	end

	-- (hookRespawn was removed because KillCamRespawnEvent("respawn") and JoinRoundEvent already handle teleporting players to the map)

	local newPlayerConn = Players.PlayerAdded:Connect(function(p)
		-- (No longer hooking respawn on PlayerAdded mid-round)
	end)

	local t = modeCfg.duration
	while t > 0 do
		task.wait(1)
		t = t - 1
		broadcastPhase("round_tick", { timeLeft = t })
		
		-- Team Battle: broadcast team kill totals every tick
		if modeCfg.teamBattle then
			local teamKills = { Red = 0, Blue = 0 }
			for pName, team in pairs(playerTeams) do
				local kills = roundKills[Players:FindFirstChild(pName)] or 0
				if team and teamKills[team] then
					teamKills[team] = teamKills[team] + kills
				end
			end
			broadcastPhase("team_kills_update", teamKills)
		end
	end

	-- Cleanup respawn hooks
	newPlayerConn:Disconnect()
end

------------------------------------------------------------------------
-- END OF ROUND / LEADERBOARD
local function runEndOfRound()
	phase = "end"
	local leaderboard = buildLeaderboard()
	local winningTeam = nil
	local teamKills = nil

	-- DEBUG: print everything relevant to team win calculation
	print("=== runEndOfRound DEBUG ===")
	print("  currentModeCfg:", currentModeCfg and currentModeCfg.name or "NIL")
	print("  teamBattle:", currentModeCfg and currentModeCfg.teamBattle or false)
	print("  playerTeams:", playerTeams)
	for _, e in ipairs(leaderboard) do
		print("  ENTRY:", e.name, "kills:", e.kills, "team:", e.team)
	end

	if currentModeCfg and currentModeCfg.teamBattle then
		-- ── TEAM BATTLE: find winning team by total kills ──────────────
		teamKills = { Red = 0, Blue = 0 }
		for _, entry in ipairs(leaderboard) do
			if entry.team then
				teamKills[entry.team] = (teamKills[entry.team] or 0) + entry.kills
			end
		end
		if teamKills.Red > teamKills.Blue then
			winningTeam = "Red"
		elseif teamKills.Blue > teamKills.Red then
			winningTeam = "Blue"
		else
			winningTeam = "Tie"
		end
		print("Team kills — Red:", teamKills.Red, "Blue:", teamKills.Blue, "→ Winner:", winningTeam)

		-- Award Win to ALL players on the winning team
		if winningTeam ~= "Tie" then
			for pName, team in pairs(playerTeams) do
				if team == winningTeam then
					local p = Players:FindFirstChild(pName)
					if p then
						local ls = p:FindFirstChild("leaderstats")
						local wins = ls and ls:FindFirstChild("Wins")
						if wins then
							wins.Value = wins.Value + 1
							print("Win awarded to", pName, "(", team, "team)")
						end
					end
				end
			end
		end
	else
		-- ── FFA: award win to 1st place only ──────────────────────────
		if leaderboard[1] and leaderboard[1].kills > 0 then
			local winnerPlayer = Players:FindFirstChild(leaderboard[1].name)
			if winnerPlayer then
				local ls = winnerPlayer:FindFirstChild("leaderstats")
				local wins = ls and ls:FindFirstChild("Wins")
				if wins then
					wins.Value = wins.Value + 1
					print("Win awarded to", leaderboard[1].name)
				end
			end
		end
	end

	-- ── COIN REWARDS ─────────────────────────────────────────────────
	-- Helper: award coins to a player (adds to both Coins and LifetimeCoins)
	local function awardCoins(p, amount)
		local ls = p:FindFirstChild("leaderstats")
		if not ls then return end
		local money = ls:FindFirstChild("Money")
		local hs = p:FindFirstChild("HiddenStats")
		local lifetime = hs and hs:FindFirstChild("LifetimeCoins")
		if money then money.Value = money.Value + amount end
		if lifetime then lifetime.Value = lifetime.Value + amount end
		print("🪙 Awarded", amount, "coins to", p.Name)
	end

	-- Build a set of winner names for quick lookup
	local winnerNames = {}
	if currentModeCfg and currentModeCfg.teamBattle then
		if winningTeam and winningTeam ~= "Tie" then
			for pName, team in pairs(playerTeams) do
				if team == winningTeam then winnerNames[pName] = true end
			end
		end
	else
		-- FFA: only 1st place is the winner
		if leaderboard[1] and leaderboard[1].kills > 0 then
			winnerNames[leaderboard[1].name] = true
		end
	end

	-- Award coins to all active round participants
	local roundRewards = {}
	for pName, _ in pairs(activeRoundPlayers) do
		local p = Players:FindFirstChild(pName)
		if p then
			if winnerNames[pName] then
				awardCoins(p, 30) -- Winner reward
				roundRewards[pName] = 30
			else
				awardCoins(p, 5)  -- Participation/loss reward
				roundRewards[pName] = 5
			end
		end
	end

	-- Reset challenge cooldown for a new cycle
	local challengeReset = ServerStorage:FindFirstChild("ChallengeResetBindable")
	if not challengeReset then
		challengeReset = Instance.new("BindableEvent")
		challengeReset.Name = "ChallengeResetBindable"
		challengeReset.Parent = ServerStorage
	end
	challengeReset:Fire()

	broadcastPhase("round_end", {
		leaderboard  = leaderboard,
		gamemodeName = currentModeCfg and currentModeCfg.name or "Free For All",
		winningTeam  = winningTeam,  -- "Red" | "Blue" | "Tie" | nil (FFA)
		teamKills    = (currentModeCfg and currentModeCfg.teamBattle) and teamKills or nil,
		roundRewards = roundRewards,
	})
	task.wait(GameConfig.LeaderboardShowTime)
	teleportPlayersToLobby()
    activeRoundPlayers = {}  -- reset for next round
	task.wait(3)
end

------------------------------------------------------------------------
-- LOBBY SPAWN DUPLICATION (Dynamic platform)
------------------------------------------------------------------------
-- Find any existing Lobby SpawnLocations (outside the Map folder) and clone them
for _, child in ipairs(workspace:GetChildren()) do
    if child:IsA("SpawnLocation") then
        local newSpawn = child:Clone()
        -- Offset the new spawn by 15 studs on the X axis to put it side-by-side
        newSpawn.CFrame = child.CFrame * CFrame.new(15, 0, 0)
        newSpawn.Parent = workspace
        print("✅ Duplicated Lobby Spawn:", child.Name, "to", newSpawn.CFrame.Position)
    end
end

------------------------------------------------------------------------
-- JOIN ROUND AREA LISTENER (BindableEvent from JoinRoundArea.server.lua)
------------------------------------------------------------------------
local function setupJoinAreaListener()
    local joinAreaEvent = ReplicatedStorage:WaitForChild("JoinRoundAreaEvent", 30)
    if not joinAreaEvent then
        warn("[GameService] JoinRoundAreaEvent not found!")
        return
    end
    joinAreaEvent.Event:Connect(function(player)
        if not player or not Players:FindFirstChild(player.Name) then return end

        -- Mark them as an active round participant
        activeRoundPlayers[player.Name] = true
        print("🟢", player.Name, "entered the green circle — marked as active round player")

        -- If the round is already running, teleport them in immediately
        if phase == "round" and currentModeCfg then
            local currentMapCfg = ServerStorage:FindFirstChild("CurrentMapCfg")
            local mapName = currentMapCfg and currentMapCfg.Value or "City"
            local spawnParts = getSpawnParts(mapName)
            if #spawnParts > 0 and player.Character then
                local spawnPart = spawnParts[math.random(1, #spawnParts)]
                teleportPlayerWithChair(player, player.Character, spawnPart)
            end
            -- Fire round_start so their HUD loads
            GameEvent:FireClient(player, "round_start", {
                mapName      = mapName,
                gamemodeName = currentModeCfg.name,
                duration     = currentModeCfg.duration,
                isTeamBattle = currentModeCfg.teamBattle or false,
                teams        = currentModeCfg.teamBattle and playerTeams or nil,
            })
        end
    end)
end
task.spawn(setupJoinAreaListener)

------------------------------------------------------------------------


------------------------------------------------------------------------
-- LATE JOIN HANDLER
------------------------------------------------------------------------
local JoinRoundEvent = getOrMakeRemote("JoinRoundEvent")

JoinRoundEvent.OnServerEvent:Connect(function(player)
    if phase == "lobby" then return end
    
    -- BLOCK joining if they are currently doing a challenge
    if player:GetAttribute("InChallenge") then
        print("❌ Blocked", player.Name, "from joining round — they are in a challenge!")
        return
    end
    
    -- Mark as active round player immediately on join
    activeRoundPlayers[player.Name] = true
    print("🟢 JOIN BUTTON:", player.Name, "marked as active round player")
    -- Safety check: ensure they aren't somehow dueling
    local isDueling = ServerStorage:FindFirstChild("IsPlayerDueling")
    if isDueling then
        local success, result = pcall(function() return isDueling:Invoke(player) end)
        if success and result == true then return end
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Only teleport them immediately if the round is actively running
    if phase ~= "round" then return end

    -- Teleport to current map
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then
        local spawnParts = getSpawnParts("Unknown") -- mapName doesn't matter, getSpawnParts just searches workspace.Map
        if #spawnParts > 0 then
            local spawnPart = spawnParts[math.random(1, #spawnParts)]
            teleportPlayerWithChair(player, char, spawnPart)
        end
    end

    -- Tell their client that the round has started (so they get the Kill HUD)
    local currentMapCfg = ServerStorage:FindFirstChild("CurrentMapCfg")
    local actualMapName = currentMapCfg and currentMapCfg.Value or "Map"
    GameEvent:FireClient(player, "round_start", {
        mapName      = actualMapName,
        gamemodeName = currentModeCfg.name,
        duration     = currentModeCfg.duration,
        isTeamBattle = currentModeCfg.teamBattle or false,
        teams        = currentModeCfg.teamBattle and playerTeams or nil,
    })
    
    print("🎮", player.Name, "late-joined the active round.")
end)

------------------------------------------------------------------------

KillCamRespawnEvent.OnServerEvent:Connect(function(player, action)
	if action == "respawn" then
		local oldChar = player.Character
		player:LoadCharacter()
        
        -- If the round is currently active and the player is part of it, spawn them back in the map
        if phase == "round" and activeRoundPlayers[player.Name] then
            local char = player.Character
            if not char or char == oldChar then
                char = player.CharacterAdded:Wait()
            end
            if not char then return end
            
            -- teleportPlayerWithChair is declared globally or forward-declared earlier in the file
            task.wait(1.5) -- wait for wheelchair to fully attach
            local currentMapCfg = ServerStorage:FindFirstChild("CurrentMapCfg")
            local mapName = currentMapCfg and currentMapCfg.Value or "City"
            
            local spawns = getSpawnParts(mapName)
            
            if #spawns > 0 then
                local spawnPart = spawns[math.random(1, #spawns)]
                teleportPlayerWithChair(player, char, spawnPart)
            end
            
            -- Resend their HUD
            local GameEvent = ReplicatedStorage:FindFirstChild("GameEvent")
            if GameEvent and currentModeCfg then
                GameEvent:FireClient(player, "round_start", {
                    mapName      = mapName,
                    gamemodeName = currentModeCfg.name,
                    duration     = currentModeCfg.duration,
                    isTeamBattle = currentModeCfg.teamBattle or false,
                    teams        = currentModeCfg.teamBattle and playerTeams or nil,
                })
            end
        end
	elseif action == "lobby" then
		-- Remove them from the active round so they spawn in the lobby instead of the map
		if activeRoundPlayers then
			activeRoundPlayers[player.Name] = nil
		end
		player:LoadCharacter()
        
        -- Tell the client to reset lighting and UI
        local GameEvent = ReplicatedStorage:FindFirstChild("GameEvent")
        if GameEvent then
            GameEvent:FireClient(player, "lobby_return", { phase = phase })
        end
	end
end)

------------------------------------------------------------------------
-- MAIN LOOP
task.spawn(function()
	-- Wait for the game to fully load
	task.wait(5)
	print("🎮 GameService: Main loop starting")

	while true do
		local ok, err

		-- INTERMISSION
		print("🎮 Phase: INTERMISSION")
		ok, err = pcall(runIntermission)
		if not ok then warn("GameService INTERMISSION ERROR:", err) task.wait(5) continue end

		-- VOTING
		print("🎮 Phase: VOTING")
		local mapCfg, modeCfg
		ok, err = pcall(function()
			mapCfg, modeCfg = runVoting()
		end)
		if not ok then warn("GameService VOTING ERROR:", err) task.wait(5) continue end

		-- ROUND
		print("🎮 Phase: ROUND →", mapCfg and mapCfg.name or "?")
		ok, err = pcall(runRound, mapCfg, modeCfg)
		if not ok then warn("GameService ROUND ERROR:", err) task.wait(5) continue end

		-- END
		print("🎮 Phase: END OF ROUND")
		ok, err = pcall(runEndOfRound)
		if not ok then warn("GameService END ERROR:", err) task.wait(5) end
	end
end)

print("✅ GameService Loaded")
