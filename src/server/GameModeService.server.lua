--[[
	GameModeService.server.lua
	Manages game rounds, modes (FFA / TDM), scoring, and match flow.
	State Machine: Waiting → Playing → Intermission → Playing ...
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- Forward declarations (functions defined later but referenced earlier)
local startIntermission
local waitForPlayers

----------------------------------------------------------------------
-- REMOTE EVENTS
----------------------------------------------------------------------
local Remotes = Instance.new("Folder")
Remotes.Name = "GameRemotes"
Remotes.Parent = ReplicatedStorage

local GameStateEvent = Instance.new("RemoteEvent")
GameStateEvent.Name = "GameStateChanged"
GameStateEvent.Parent = Remotes

local TimerEvent = Instance.new("RemoteEvent")
TimerEvent.Name = "TimerUpdate"
TimerEvent.Parent = Remotes

local AnnouncementEvent = Instance.new("RemoteEvent")
AnnouncementEvent.Name = "Announcement"
AnnouncementEvent.Parent = Remotes

----------------------------------------------------------------------
-- GAME STATE
----------------------------------------------------------------------
local GameState = {
	WAITING = "Waiting",
	PLAYING = "Playing",
	INTERMISSION = "Intermission",
}

local currentState = GameState.WAITING
local currentMode = GameConfig.DefaultMode -- "FFA" or "TDM"
local roundTimer = 0
local teamScores = { Red = 0, Blue = 0 }

----------------------------------------------------------------------
-- TEAM ASSIGNMENT (TDM)
----------------------------------------------------------------------
local function getTeamCounts()
	local counts = { Red = 0, Blue = 0 }
	for _, player in ipairs(Players:GetPlayers()) do
		local team = player:GetAttribute("Team")
		if team and counts[team] ~= nil then
			counts[team] = counts[team] + 1
		end
	end
	return counts
end

local function assignTeam(player)
	if currentMode ~= "TDM" then
		player:SetAttribute("Team", "None")
		return
	end
	
	local counts = getTeamCounts()
	local team = counts.Red <= counts.Blue and "Red" or "Blue"
	player:SetAttribute("Team", team)
	
	local teamData = nil
	for _, t in ipairs(GameConfig.TDM.Teams) do
		if t.Name == team then
			teamData = t
			break
		end
	end
	
	if teamData then
		AnnouncementEvent:FireClient(player, "You are on " .. team .. " Team!", teamData.Color)
	end
end

----------------------------------------------------------------------
-- STATE TRANSITIONS
----------------------------------------------------------------------
local function setState(newState)
	currentState = newState
	GameStateEvent:FireAllClients(currentState, currentMode)
	print("🎮 Game State:", currentState, "Mode:", currentMode)
end

local function announce(message, color)
	color = color or Color3.fromRGB(255, 255, 255)
	AnnouncementEvent:FireAllClients(message, color)
end

----------------------------------------------------------------------
-- ROUND FLOW
----------------------------------------------------------------------
local function resetRound()
	teamScores = { Red = 0, Blue = 0 }
	
	-- Reset player kill counts for this round
	-- (CombatService tracks lifetime stats, we track round stats here)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("RoundKills", 0)
		player:SetAttribute("RoundDeaths", 0)
		
		if currentMode == "TDM" then
			assignTeam(player)
		end
	end
end

local function checkWinCondition()
	if currentState ~= GameState.PLAYING then return nil end
	
	local modeConfig = currentMode == "TDM" and GameConfig.TDM or GameConfig.FFA
	
	if currentMode == "FFA" then
		for _, player in ipairs(Players:GetPlayers()) do
			local kills = player:GetAttribute("RoundKills") or 0
			if kills >= modeConfig.KillTarget then
				return player.Name .. " wins!"
			end
		end
	else -- TDM
		if teamScores.Red >= modeConfig.KillTarget then
			return "Red Team wins!"
		elseif teamScores.Blue >= modeConfig.KillTarget then
			return "Blue Team wins!"
		end
	end
	
	return nil
end

local function startRound()
	resetRound()
	
	local modeConfig = currentMode == "TDM" and GameConfig.TDM or GameConfig.FFA
	roundTimer = modeConfig.TimeLimit
	
	setState(GameState.PLAYING)
	announce("Round started! Mode: " .. currentMode, Color3.fromRGB(100, 255, 100))
	
	-- Respawn everyone
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			player:LoadCharacter()
		end
	end
	
	-- Round timer loop
	while currentState == GameState.PLAYING and roundTimer > 0 do
		task.wait(1)
		roundTimer = roundTimer - 1
		TimerEvent:FireAllClients(roundTimer)
		
		-- Check win condition
		local winner = checkWinCondition()
		if winner then
			announce("🏆 " .. winner, Color3.fromRGB(255, 215, 0))
			break
		end
	end
	
	-- Time ran out
	if currentState == GameState.PLAYING then
		if not checkWinCondition() then
			announce("⏰ Time's up!", Color3.fromRGB(255, 200, 50))
		end
		startIntermission()
	end
end

startIntermission = function()
	setState(GameState.INTERMISSION)
	announce("Next round in " .. GameConfig.IntermissionTime .. " seconds...", Color3.fromRGB(200, 200, 255))
	
	-- Toggle mode for variety
	currentMode = currentMode == "FFA" and "TDM" or "FFA"
	
	task.wait(GameConfig.IntermissionTime)
	
	if #Players:GetPlayers() >= GameConfig.MinPlayersToStart then
		startRound()
	else
		setState(GameState.WAITING)
		waitForPlayers()
	end
end

----------------------------------------------------------------------
-- WAITING FOR PLAYERS
----------------------------------------------------------------------
waitForPlayers = function()
	setState(GameState.WAITING)
	announce("Waiting for " .. GameConfig.MinPlayersToStart .. " players...", Color3.fromRGB(200, 200, 200))
	
	while #Players:GetPlayers() < GameConfig.MinPlayersToStart do
		task.wait(1)
	end
	
	announce("Starting in 5 seconds!", Color3.fromRGB(100, 255, 100))
	task.wait(5)
	
	if #Players:GetPlayers() >= GameConfig.MinPlayersToStart then
		startRound()
	else
		waitForPlayers()
	end
end

----------------------------------------------------------------------
-- KILL TRACKING (Listens to CombatService kills)
----------------------------------------------------------------------
-- CombatService broadcasts kills via KillFeed RemoteEvent
-- We also track round-specific scores by listening to humanoid deaths
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	
	humanoid.Died:Connect(function()
		if currentState ~= GameState.PLAYING then return end
		
		local deaths = (player:GetAttribute("RoundDeaths") or 0) + 1
		player:SetAttribute("RoundDeaths", deaths)
		
		-- For TDM scoring, we track via the combat service's kill attribution
		-- This just tracks deaths on our side
	end)
end

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("RoundKills", 0)
	player:SetAttribute("RoundDeaths", 0)
	
	if currentMode == "TDM" then
		assignTeam(player)
	end
	
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	
	-- Notify new player of current state
	task.defer(function()
		GameStateEvent:FireClient(player, currentState, currentMode)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Clean up team assignment
	player:SetAttribute("Team", nil)
	player:SetAttribute("RoundKills", nil)
	player:SetAttribute("RoundDeaths", nil)
end)

----------------------------------------------------------------------
-- PUBLIC API: Called by CombatService when a kill happens
----------------------------------------------------------------------
-- We expose a BindableEvent for CombatService to report kills
local KillReport = Instance.new("BindableEvent")
KillReport.Name = "KillReport"
KillReport.Parent = script

KillReport.Event:Connect(function(killerPlayer, victimPlayer)
	if currentState ~= GameState.PLAYING then return end
	
	-- Round kills
	local kills = (killerPlayer:GetAttribute("RoundKills") or 0) + 1
	killerPlayer:SetAttribute("RoundKills", kills)
	
	-- TDM team scoring
	if currentMode == "TDM" then
		local team = killerPlayer:GetAttribute("Team")
		if team and teamScores[team] ~= nil then
			teamScores[team] = teamScores[team] + 1
		end
	end
end)

----------------------------------------------------------------------
-- START
----------------------------------------------------------------------
task.spawn(waitForPlayers)
print("✅ GameModeService loaded")
