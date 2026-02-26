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
	GameEvent:FireAllClients(phaseName, data)
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
		GameEvent:FireAllClients("kills_update", killTable)
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
local function getSpawnParts(mapName)
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
local function teleportPlayerWithChair(player, char, spawnPart)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 1. Teleport the character
	hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 5, 0)
	killMomentum(char)

	-- 2. Move their wheelchair (if it exists) and re-seat them
	local chairName = char.Name .. "_Wheelchair"
	local chair = workspace:FindFirstChild(chairName)
	if chair then
		chair:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0))
		killMomentum(chair)
		-- Force re-seat the player if dismounted
		local seat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
		local hum = char:FindFirstChild("Humanoid")
		if seat and hum and hum.Health > 0 and not seat.Occupant then
			task.delay(0.3, function()
				if seat and hum and hum.Health > 0 and not seat.Occupant then
					seat:Sit(hum)
				end
			end)
		end
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
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum then
			-- let the game handle respawn naturally
			player:LoadCharacter()
		end
	end
end

------------------------------------------------------------------------
-- BUILD LEADERBOARD DATA
------------------------------------------------------------------------
local function buildLeaderboard()
	local arr = {}
	for player, kills in pairs(roundKills) do
		if Players:FindFirstChild(player.Name) then
			table.insert(arr, { name = player.Name, kills = kills, userId = player.UserId })
		end
	end
	table.sort(arr, function(a, b) return a.kills > b.kills end)
	-- Return top 3 (pad with nil slots on client side if < 3)
	return arr
end

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

	teleportPlayersToMap(mapCfg.name)
	task.wait(2) -- brief settle time

	broadcastPhase("round_start", {
		mapName      = mapCfg.name,
		gamemodeName = modeCfg.name,
		duration     = modeCfg.duration,
		isTeamBattle = modeCfg.teamBattle or false,
		teams        = modeCfg.teamBattle and playerTeams or nil,
	})

	-- Hook: when a player respawns during the round, move them to the map after
	-- WheelchairService has seated them (0.5s delay). We wait 0.8s to be safe,
	-- then pivot the wheelchair to a spawn point — the seated player moves with it.
	local respawnConnections = {}
	local function hookRespawn(p)
		local conn = p.CharacterAdded:Connect(function(char)
			if phase ~= "round" then return end
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			if not hrp or phase ~= "round" then return end

			-- Wait for WheelchairService to spawn + force-sit (0.5s) with buffer
			task.wait(0.8)
			if phase ~= "round" then return end

			local spawnParts = getSpawnParts(mapCfg.name)
			if #spawnParts == 0 then return end
			local spawnPart = spawnParts[math.random(1, #spawnParts)]

			-- Move the wheelchair (player is seated in it, they'll move with it)
			local chairName = char.Name .. "_Wheelchair"
			local chair = workspace:FindFirstChild(chairName)
			if chair then
				chair:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0))
				killMomentum(chair)
				killMomentum(char)
				print("🔄 Moved wheelchair + seated player to map spawn:", p.Name)
			else
				-- Fallback: chair not found, move HRP directly
				hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 5, 0)
				killMomentum(char)
				warn("GameService: No wheelchair found for", p.Name, "— moved HRP only")
			end
		end)
		table.insert(respawnConnections, conn)
	end

	for _, p in ipairs(Players:GetPlayers()) do
		hookRespawn(p)
	end

	-- Also hook players who join mid-round
	local newPlayerConn = Players.PlayerAdded:Connect(function(p)
		if phase == "round" then hookRespawn(p) end
	end)

	local t = modeCfg.duration
	while t > 0 do
		task.wait(1)
		t = t - 1
		broadcastPhase("round_tick", { timeLeft = t })
	end

	-- Cleanup respawn hooks
	for _, conn in ipairs(respawnConnections) do
		conn:Disconnect()
	end
	newPlayerConn:Disconnect()
end

------------------------------------------------------------------------
-- END OF ROUND / LEADERBOARD
local function runEndOfRound()
	phase = "end"
	local leaderboard = buildLeaderboard()
	local winningTeam = nil

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
		local teamKills = { Red = 0, Blue = 0 }
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

	broadcastPhase("round_end", {
		leaderboard  = leaderboard,
		gamemodeName = currentModeCfg and currentModeCfg.name or "Free For All",
		winningTeam  = winningTeam,  -- "Red" | "Blue" | "Tie" | nil (FFA)
	})
	task.wait(GameConfig.LeaderboardShowTime)
	teleportPlayersToLobby()
	task.wait(3)
end

------------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------------
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
