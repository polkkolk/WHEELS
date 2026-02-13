--[[
	CombatService.server.lua
	Server-authoritative combat: firing, hit detection, damage, kills, respawn.
	All damage is validated server-side. Clients only send intent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- Forward declarations (functions defined later but referenced earlier)
local handleDeath
local broadcastScores

----------------------------------------------------------------------
-- REMOTE EVENTS
----------------------------------------------------------------------
local Remotes = Instance.new("Folder")
Remotes.Name = "CombatRemotes"
Remotes.Parent = ReplicatedStorage

local FireEvent = Instance.new("RemoteEvent")
FireEvent.Name = "FireWeapon"
FireEvent.Parent = Remotes

local ReplicateShot = Instance.new("RemoteEvent")
ReplicateShot.Name = "ReplicateShot"
ReplicateShot.Parent = Remotes

local HitConfirm = Instance.new("RemoteEvent")
HitConfirm.Name = "HitConfirm"
HitConfirm.Parent = Remotes

local KillFeedEvent = Instance.new("RemoteEvent")
KillFeedEvent.Name = "KillFeed"
KillFeedEvent.Parent = Remotes

local HealthUpdate = Instance.new("RemoteEvent")
HealthUpdate.Name = "HealthUpdate"
HealthUpdate.Parent = Remotes

local AmmoUpdate = Instance.new("RemoteEvent")
AmmoUpdate.Name = "AmmoUpdate"
AmmoUpdate.Parent = Remotes

local ReloadEvent = Instance.new("RemoteEvent")
ReloadEvent.Name = "ReloadWeapon"
ReloadEvent.Parent = Remotes

local ScoreUpdate = Instance.new("RemoteEvent")
ScoreUpdate.Name = "ScoreUpdate"
ScoreUpdate.Parent = Remotes

----------------------------------------------------------------------
-- PLAYER STATE
----------------------------------------------------------------------
local playerStates = {}

local function getState(player)
	return playerStates[player.UserId]
end

local function initState(player)
	playerStates[player.UserId] = {
		Health = Config.MaxHealth,
		Ammo = Config.Weapon.MagSize,
		LastDamageTime = 0,
		LastFireTime = 0,
		IsReloading = false,
		IsDead = false,
		Kills = 0,
		Deaths = 0,
		SpawnProtectionEnd = os.clock() + Config.SpawnProtection,
	}
end

----------------------------------------------------------------------
-- HIT DETECTION (Server-Authoritative Hitscan)
----------------------------------------------------------------------
local function performHitscan(player, origin, direction)
	local state = getState(player)
	if not state or state.IsDead then return end
	
	local now = os.clock()
	
	-- Rate limit (server-side fire rate check)
	if now - state.LastFireTime < Config.Weapon.FireRate * 0.8 then return end -- 0.8 = small tolerance
	state.LastFireTime = now
	
	-- Ammo check
	if state.Ammo <= 0 or state.IsReloading then return end
	state.Ammo = state.Ammo - 1
	AmmoUpdate:FireClient(player, state.Ammo, Config.Weapon.MagSize)
	
	-- Validate origin (anti-cheat: must be near player)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local distFromPlayer = (origin - rootPart.Position).Magnitude
	if distFromPlayer > 15 then
		-- Suspicious origin, use server position instead
		origin = rootPart.Position + Vector3.new(0, 2, 0)
	end
	
	-- Normalize direction and apply server-side spread
	direction = direction.Unit
	
	-- Raycast
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character}
	rayParams.IgnoreWater = true
	
	local result = workspace:Raycast(origin, direction * Config.Weapon.MaxRange, rayParams)
	
	local hitPos = origin + direction * Config.Weapon.MaxRange
	local hitPlayer = nil
	local isHeadshot = false
	
	if result then
		hitPos = result.Position
		
		-- Check if we hit a player
		local hitPart = result.Instance
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")
		
		if hitModel then
			local hitHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
			if hitHumanoid and hitHumanoid.Health > 0 then
				local hitTarget = Players:GetPlayerFromCharacter(hitModel)
				if hitTarget and hitTarget ~= player then
					hitPlayer = hitTarget
					isHeadshot = hitPart.Name == "Head"
				end
			end
		end
	end
	
	-- Replicate shot visual to ALL other players
	ReplicateShot:FireAllClients(player, origin, hitPos)
	
	-- Apply damage if hit
	if hitPlayer then
		local targetState = getState(hitPlayer)
		if targetState and not targetState.IsDead then
			-- Check spawn protection
			if os.clock() < targetState.SpawnProtectionEnd then return end
			
			local damage = Config.Weapon.Damage
			if isHeadshot then
				damage = damage * Config.Weapon.HeadshotMultiplier
			end
			
			targetState.Health = math.max(0, targetState.Health - damage)
			targetState.LastDamageTime = os.clock()
			
			-- Notify shooter (hit marker)
			HitConfirm:FireClient(player, isHeadshot, damage)
			
			-- Update victim health
			HealthUpdate:FireClient(hitPlayer, targetState.Health, Config.MaxHealth)
			
			-- Set humanoid health to match
			local hitChar = hitPlayer.Character
			if hitChar then
				local hum = hitChar:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Health = targetState.Health
				end
			end
			
			-- Handle death
			if targetState.Health <= 0 then
				handleDeath(hitPlayer, player)
			end
		end
	end
end

----------------------------------------------------------------------
-- DEATH & RESPAWN
----------------------------------------------------------------------
handleDeath = function(victim, killer)
	local victimState = getState(victim)
	local killerState = getState(killer)
	
	if not victimState then return end
	victimState.IsDead = true
	victimState.Deaths = victimState.Deaths + 1
	
	if killerState then
		killerState.Kills = killerState.Kills + 1
	end
	
	-- Broadcast kill feed to all players
	local killerName = killer and killer.Name or "Unknown"
	local victimName = victim.Name
	KillFeedEvent:FireAllClients(killerName, victimName)
	
	-- Report kill to GameModeService for round/team scoring
	task.defer(function()
		local gmService = ServerScriptService:FindFirstChild("Server")
			and ServerScriptService.Server:FindFirstChild("GameModeService")
		local killReport = gmService and gmService:FindFirstChild("KillReport")
		if killReport then
			killReport:Fire(killer, victim)
		end
	end)
	
	-- Broadcast updated scores
	broadcastScores()
	
	-- Kill the humanoid (triggers WheelchairService cleanup)
	local character = victim.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
	
	-- Respawn after delay
	task.delay(Config.RespawnDelay, function()
		if victim and victim.Parent then
			victim:LoadCharacter()
		end
	end)
end

----------------------------------------------------------------------
-- HEALTH REGENERATION
----------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.5) -- Check every 0.5s
		local now = os.clock()
		
		for _, player in ipairs(Players:GetPlayers()) do
			local state = getState(player)
			if state and not state.IsDead and state.Health < Config.MaxHealth then
				if now - state.LastDamageTime >= Config.HealthRegenDelay then
					local oldHP = math.ceil(state.Health)
				state.Health = math.min(Config.MaxHealth, state.Health + Config.HealthRegenRate * 0.5)
				local newHP = math.ceil(state.Health)
					if newHP ~= oldHP then
						HealthUpdate:FireClient(player, state.Health, Config.MaxHealth)
					end
					
					-- Sync humanoid
					local character = player.Character
					if character then
						local hum = character:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.Health = state.Health
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- SCORE BROADCASTING
----------------------------------------------------------------------
broadcastScores = function()
	local scores = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local state = getState(player)
		if state then
			table.insert(scores, {
				Name = player.Name,
				Kills = state.Kills,
				Deaths = state.Deaths,
				Team = player:GetAttribute("Team") or "None",
			})
		end
	end
	
	-- Sort by kills descending
	table.sort(scores, function(a, b) return a.Kills > b.Kills end)
	ScoreUpdate:FireAllClients(scores)
end

----------------------------------------------------------------------
-- RELOAD HANDLER
----------------------------------------------------------------------
ReloadEvent.OnServerEvent:Connect(function(player)
	local state = getState(player)
	if not state or state.IsDead or state.IsReloading then return end
	if state.Ammo >= Config.Weapon.MagSize then return end
	
	state.IsReloading = true
	AmmoUpdate:FireClient(player, state.Ammo, Config.Weapon.MagSize, true) -- true = reloading
	
	task.delay(Config.Weapon.ReloadTime, function()
		if state then
			state.Ammo = Config.Weapon.MagSize
			state.IsReloading = false
			AmmoUpdate:FireClient(player, state.Ammo, Config.Weapon.MagSize, false)
		end
	end)
end)

----------------------------------------------------------------------
-- FIRE HANDLER
----------------------------------------------------------------------
FireEvent.OnServerEvent:Connect(function(player, origin, direction)
	-- Type validation
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	performHitscan(player, origin, direction)
end)

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
local function onCharacterAdded(player, character)
	local state = getState(player)
	if not state then return end
	
	-- Reset state for new life
	state.Health = Config.MaxHealth
	state.Ammo = Config.Weapon.MagSize
	state.IsReloading = false
	state.IsDead = false
	state.SpawnProtectionEnd = os.clock() + Config.SpawnProtection
	state.LastDamageTime = 0
	
	-- Set humanoid health
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	
	-- Visual spawn protection (ForceField)
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = character
	Debris:AddItem(ff, Config.SpawnProtection)

	-- Send initial state to client
	task.defer(function()
		HealthUpdate:FireClient(player, Config.MaxHealth, Config.MaxHealth)
		AmmoUpdate:FireClient(player, Config.Weapon.MagSize, Config.Weapon.MagSize, false)
	end)
end

local function onPlayerAdded(player)
	initState(player)
	
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	
	broadcastScores()
end

local function onPlayerRemoving(player)
	playerStates[player.UserId] = nil
	broadcastScores()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("✅ CombatService loaded")
