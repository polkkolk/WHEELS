-- TeamIndicatorController.client.lua
-- Shows green Highlight + green name tag (through walls) for teammates only.
-- Uses LocalScript workspace mutation (client-only via FilteringEnabled).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 15)
if not GameEvent then return end

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local myTeam   = nil
local teamData = {}
local indicators = {}   -- [name] = { highlight, billboard }
local watchLoops = {}   -- [name] = true while active

local DUMMY_NAMES = { "RedTeamDummy", "BlueTeamDummy" }

------------------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------------------
local function clearAllIndicators()
	myTeam     = nil
	teamData   = {}
	watchLoops = {}
	for _, ind in pairs(indicators) do
		if ind.highlight and ind.highlight.Parent then ind.highlight:Destroy() end
		if ind.billboard and ind.billboard.Parent then ind.billboard:Destroy()  end
	end
	indicators = {}
end

------------------------------------------------------------------------
-- APPLY INDICATOR
-- Parented DIRECTLY to the model/head (LocalScript = client-only)
------------------------------------------------------------------------
local function applyIndicator(name, model)
	if not model then return end

	-- Destroy old
	local old = indicators[name]
	if old then
		if old.highlight and old.highlight.Parent then old.highlight:Destroy() end
		if old.billboard and old.billboard.Parent then old.billboard:Destroy()  end
	end

	-- 1. Highlight — parent inside model so Roblox renders it
	local teamColor = (teamData[name] == "Red")
		and Color3.fromRGB(255, 60, 60)
		or  Color3.fromRGB(60, 140, 255)

	-- Highlight is always green (teammate indicator)
	local highlight = Instance.new("Highlight")
	highlight.Name                = "TeamHighlight"
	highlight.FillColor           = Color3.fromRGB(0, 200, 80)
	highlight.OutlineColor        = Color3.fromRGB(0, 255, 100)
	highlight.FillTransparency    = 0.75
	highlight.OutlineTransparency = 0
	highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent              = model

	-- 2. BillboardGui — anchored to HumanoidRootPart (always present, reliable height)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local billboard
	if hrp then
		billboard = Instance.new("BillboardGui")
		billboard.Name                  = "TeamTag"
		billboard.Size                  = UDim2.new(0, 110, 0, 22)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)  -- well above any character
		billboard.AlwaysOnTop           = true
		billboard.ResetOnSpawn          = false
		billboard.Parent                = hrp

		local lbl = Instance.new("TextLabel")
		lbl.Size                   = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text                   = name
		lbl.TextColor3             = teamColor
		lbl.Font                   = Enum.Font.GothamBlack
		lbl.TextSize               = 13
		lbl.TextStrokeTransparency = 0.35
		lbl.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
		lbl.Parent                 = billboard
	end

	indicators[name] = { highlight = highlight, billboard = billboard }

	-- Hide the default Roblox overhead nametag for this teammate (client-only)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	print("TeamIndicator: applied to", name, "model =", model:GetFullName())
end

------------------------------------------------------------------------
-- WATCH PLAYER (re-apply on respawn)
------------------------------------------------------------------------
local function watchPlayer(otherPlayer)
	local name = otherPlayer.Name
	if teamData[name] ~= myTeam then return end

	applyIndicator(name, otherPlayer.Character)

	otherPlayer.CharacterAdded:Connect(function(char)
		if myTeam and teamData[name] == myTeam then
			task.wait(0.8)
			applyIndicator(name, char)
		end
	end)
end

------------------------------------------------------------------------
-- WATCH DUMMY (poll workspace every second, re-apply after respawn)
------------------------------------------------------------------------
local function watchDummy(dummyName)
	if teamData[dummyName] ~= myTeam then return end

	watchLoops[dummyName] = true
	task.spawn(function()
		while watchLoops[dummyName] do
			-- Search explicitly for a Model (not the BasePart spawn marker)
			local model = nil
			for _, obj in ipairs(workspace:GetChildren()) do
				if obj.Name == dummyName and obj:IsA("Model") then
					model = obj
					break
				end
			end

			local ind = indicators[dummyName]
			local hasValidHighlight = ind and ind.highlight and ind.highlight.Parent

			if model and not hasValidHighlight then
				applyIndicator(dummyName, model)
			elseif not model and hasValidHighlight then
				ind.highlight:Destroy()
				if ind.billboard and ind.billboard.Parent then ind.billboard:Destroy() end
				indicators[dummyName] = nil
			end
			task.wait(1)
		end
	end)
end

------------------------------------------------------------------------
-- BUILD ALL INDICATORS
------------------------------------------------------------------------
local function buildIndicators(teams)
	clearAllIndicators()
	teamData = teams
	myTeam   = teams[player.Name]

	print("TeamIndicator: myTeam =", myTeam)
	if not myTeam then return end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			watchPlayer(otherPlayer)
		end
	end

	for _, dummyName in ipairs(DUMMY_NAMES) do
		print("TeamIndicator: checking dummy", dummyName, "→ team =", teams[dummyName])
		watchDummy(dummyName)
	end
end

------------------------------------------------------------------------
-- LISTEN
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)
	if eventName == "round_start" then
		if data and data.teams then
			buildIndicators(data.teams)
		else
			clearAllIndicators()
		end
	elseif eventName == "round_end" or eventName == "intermission" then
		clearAllIndicators()
	end
end)

Players.PlayerAdded:Connect(function(newPlayer)
	if myTeam and teamData[newPlayer.Name] == myTeam then
		watchPlayer(newPlayer)
	end
end)

print("✅ TeamIndicatorController Loaded")
