-- RoundHUDController.client.lua
-- Shows intermission countdown, voting phase label, round timer, and live kill count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 10)
if not GameEvent then return end

------------------------------------------------------------------------
-- BUILD HUD
------------------------------------------------------------------------
local sg = Instance.new("ScreenGui")
sg.Name = "RoundHUD"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

-- ── Top-centre panel: phase label + timer ───────────────────────────
local topPanel = Instance.new("Frame")
topPanel.Name = "TopPanel"
topPanel.Size = UDim2.new(0, 280, 0, 64)
topPanel.Position = UDim2.new(0.5, 0, 0, 18)
topPanel.AnchorPoint = Vector2.new(0.5, 0)
topPanel.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
topPanel.BackgroundTransparency = 0.3
topPanel.BorderSizePixel = 0
topPanel.Visible = false
topPanel.Parent = sg
local tpc = Instance.new("UICorner"); tpc.CornerRadius = UDim.new(0, 12); tpc.Parent = topPanel
local tps = Instance.new("UIStroke"); tps.Color = Color3.fromRGB(70, 80, 110); tps.Thickness = 1.5; tps.Parent = topPanel

-- Phase label (e.g. "INTERMISSION" / "FREE FOR ALL")
local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name = "PhaseLabel"
phaseLabel.Size = UDim2.new(1, -16, 0, 26)
phaseLabel.Position = UDim2.new(0, 8, 0, 6)
phaseLabel.BackgroundTransparency = 1
phaseLabel.Text = "INTERMISSION"
phaseLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
phaseLabel.Font = Enum.Font.GothamBold
phaseLabel.TextSize = 14
phaseLabel.Parent = topPanel

-- Timer (large number)
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, -16, 0, 32)
timerLabel.Position = UDim2.new(0, 8, 0, 28)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "0:30"
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextSize = 26
timerLabel.TextStrokeTransparency = 1
timerLabel.Parent = topPanel

local currentPhaseText = "INTERMISSION"

-- ── Avatar Row Container ─────────────────────────────────────────────
local avatarContainer = Instance.new("Frame")
avatarContainer.Name = "AvatarContainer"
avatarContainer.Size = UDim2.new(1, 0, 0, 90)
avatarContainer.Position = UDim2.new(0.5, 0, 0, 50)
avatarContainer.AnchorPoint = Vector2.new(0.5, 0)
avatarContainer.BackgroundTransparency = 1
avatarContainer.Visible = false
avatarContainer.Parent = sg

local avatarLayout = Instance.new("UIListLayout")
avatarLayout.FillDirection = Enum.FillDirection.Horizontal
avatarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
avatarLayout.SortOrder = Enum.SortOrder.LayoutOrder
avatarLayout.Padding = UDim.new(0, 8)
avatarLayout.Parent = avatarContainer
-- ── Team Kill Scoreboard (below timer, Team Battle only) ─────────────
local teamScorePanel = Instance.new("Frame")
teamScorePanel.Name = "TeamScorePanel"
teamScorePanel.Size = UDim2.new(0, 180, 0, 32)
teamScorePanel.Position = UDim2.new(0.5, 0, 0, 86)
teamScorePanel.AnchorPoint = Vector2.new(0.5, 0)
teamScorePanel.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
teamScorePanel.BackgroundTransparency = 0.3
teamScorePanel.BorderSizePixel = 0
teamScorePanel.Visible = false
teamScorePanel.Parent = sg
local tspc = Instance.new("UICorner"); tspc.CornerRadius = UDim.new(0, 8); tspc.Parent = teamScorePanel
local tsps = Instance.new("UIStroke"); tsps.Color = Color3.fromRGB(70, 80, 110); tsps.Thickness = 1; tsps.Parent = teamScorePanel

local redScoreLbl = Instance.new("TextLabel")
redScoreLbl.Name = "RedScore"
redScoreLbl.Size = UDim2.new(0, 50, 1, 0)
redScoreLbl.Position = UDim2.new(0, 12, 0, 0)
redScoreLbl.BackgroundTransparency = 1
redScoreLbl.Text = "0"
redScoreLbl.TextColor3 = Color3.fromRGB(255, 60, 60)
redScoreLbl.Font = Enum.Font.GothamBlack
redScoreLbl.TextSize = 20
redScoreLbl.TextXAlignment = Enum.TextXAlignment.Right
redScoreLbl.Parent = teamScorePanel

local dashLbl = Instance.new("TextLabel")
dashLbl.Size = UDim2.new(0, 20, 1, 0)
dashLbl.Position = UDim2.new(0.5, -10, 0, 0)
dashLbl.BackgroundTransparency = 1
dashLbl.Text = "-"
dashLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
dashLbl.Font = Enum.Font.GothamBlack
dashLbl.TextSize = 20
dashLbl.Parent = teamScorePanel

local blueScoreLbl = Instance.new("TextLabel")
blueScoreLbl.Name = "BlueScore"
blueScoreLbl.Size = UDim2.new(0, 50, 1, 0)
blueScoreLbl.Position = UDim2.new(1, -62, 0, 0)
blueScoreLbl.BackgroundTransparency = 1
blueScoreLbl.Text = "0"
blueScoreLbl.TextColor3 = Color3.fromRGB(60, 120, 255)
blueScoreLbl.Font = Enum.Font.GothamBlack
blueScoreLbl.TextSize = 20
blueScoreLbl.TextXAlignment = Enum.TextXAlignment.Left
blueScoreLbl.Parent = teamScorePanel

local isTeamBattle = false

-- ── Freeze Countdown (3-2-1-GO at round start) ──────────────────────
local countdownLbl = Instance.new("TextLabel")
countdownLbl.Name = "RoundCountdown"
countdownLbl.Size = UDim2.new(0, 300, 0, 200)
countdownLbl.Position = UDim2.new(0.5, 0, 0.45, 0)
countdownLbl.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLbl.BackgroundTransparency = 1
countdownLbl.Text = ""
countdownLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
countdownLbl.Font = Enum.Font.GothamBlack
countdownLbl.TextScaled = true
countdownLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
countdownLbl.TextStrokeTransparency = 0
countdownLbl.Visible = false
countdownLbl.ZIndex = 50
countdownLbl.Parent = sg

-- Join Button (bottom of top panel)
local joinBtn = Instance.new("TextButton")
joinBtn.Name = "JoinButton"
joinBtn.Size = UDim2.new(0, 150, 0, 40)
joinBtn.Position = UDim2.new(0.5, 0, 1, 12)
joinBtn.AnchorPoint = Vector2.new(0.5, 0)
joinBtn.BackgroundColor3 = Color3.fromRGB(40, 200, 80)
joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
joinBtn.Font = Enum.Font.GothamBold
joinBtn.TextSize = 20
joinBtn.Text = "JOIN"
joinBtn.Visible = false
joinBtn.Parent = topPanel

local jbc = Instance.new("UICorner")
jbc.CornerRadius = UDim.new(0, 6)
jbc.Parent = joinBtn

local JoinRoundEvent = ReplicatedStorage:FindFirstChild("JoinRoundEvent")
if not JoinRoundEvent then
    -- It should be created by the server, but we can't do it locally. Just warn if missing.
    -- We'll assume the server creates it in GameService.
end

joinBtn.MouseButton1Click:Connect(function()
    joinBtn.Visible = false
    if JoinRoundEvent then
        JoinRoundEvent:FireServer()
    end
end)

-- ── Kill count (bottom-right corner during round) ────────────────────
local killFrame = Instance.new("Frame")
killFrame.Name = "KillFrame"
killFrame.Size = UDim2.new(0, 150, 0, 52)
killFrame.Position = UDim2.new(1, -16, 1, -170)
killFrame.AnchorPoint = Vector2.new(1, 0)
killFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
killFrame.BackgroundTransparency = 0.3
killFrame.BorderSizePixel = 0
killFrame.Visible = false
killFrame.Parent = sg
local kfc = Instance.new("UICorner"); kfc.CornerRadius = UDim.new(0, 10); kfc.Parent = killFrame
local kfs = Instance.new("UIStroke"); kfs.Color = Color3.fromRGB(70, 80, 110); kfs.Thickness = 1.5; kfs.Parent = killFrame

local killLabelTitle = Instance.new("TextLabel")
killLabelTitle.Size = UDim2.new(1, -12, 0, 20)
killLabelTitle.Position = UDim2.new(0, 6, 0, 4)
killLabelTitle.BackgroundTransparency = 1
killLabelTitle.Text = "YOUR KILLS"
killLabelTitle.TextColor3 = Color3.fromRGB(160, 170, 190)
killLabelTitle.Font = Enum.Font.GothamBold
killLabelTitle.TextSize = 12
killLabelTitle.Parent = killFrame

local killCount = Instance.new("TextLabel")
killCount.Name = "KillCount"
killCount.Size = UDim2.new(1, -12, 0, 26)
killCount.Position = UDim2.new(0, 6, 0, 22)
killCount.BackgroundTransparency = 1
killCount.Text = "0"
killCount.TextColor3 = Color3.fromRGB(255, 220, 60)
killCount.Font = Enum.Font.GothamBlack
killCount.TextSize = 24
killCount.Parent = killFrame

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function showPanel(phase, timerText, timerColor)
    if isDueling then return end
	topPanel.Visible = true
	currentPhaseText = phase
	
	if phase == "INTERMISSION" or phase == "VOTING" or phase == "WAITING FOR PLAYERS..." or phase == "ROUND IN PROGRESS" then
		-- Boxed styling
		topPanel.Size = UDim2.new(0, 280, 0, 64)
		topPanel.BackgroundTransparency = 0.3
		tps.Transparency = 0
		
		phaseLabel.Visible = true
		phaseLabel.Text = phase
		
		timerLabel.Size = UDim2.new(1, -16, 0, 32)
		timerLabel.Position = UDim2.new(0, 8, 0, 28)
		timerLabel.Text = timerText
		timerLabel.TextSize = 26
		timerLabel.TextStrokeTransparency = 1
		timerLabel.Font = Enum.Font.GothamBlack
	else
		-- Mid-round unboxed styling
		topPanel.Size = UDim2.new(0, 400, 0, 32)
		topPanel.BackgroundTransparency = 1
		tps.Transparency = 1
		
		phaseLabel.Visible = false
		
		timerLabel.Size = UDim2.new(1, 0, 1, 0)
		timerLabel.Position = UDim2.new(0, 0, 0, 0)
		timerLabel.Text = phase .. (timerText ~= "" and (" - " .. timerText) or "")
		timerLabel.TextSize = 20
		timerLabel.TextStrokeTransparency = 0.3
		timerLabel.Font = Enum.Font.GothamBold
	end
	
	timerLabel.TextColor3 = timerColor or Color3.fromRGB(255, 255, 255)
end

local function hidePanel()
	topPanel.Visible = false
	avatarContainer.Visible = false
end

local isDueling = false
local DuelEvent = ReplicatedStorage:WaitForChild("DuelEvent", 5)
if DuelEvent then
    DuelEvent.OnClientEvent:Connect(function(action)
        if action == "duel_start" then
            isDueling = true
            hidePanel()
            killFrame.Visible = false
        elseif action == "duel_end" then
            isDueling = false
        end
    end)
end

local myRoundKills = 0

local function setKillCount(n)
	myRoundKills = n
	killCount.Text = tostring(n)
	-- Small pop animation
	TweenService:Create(killCount, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 30 }):Play()
	task.delay(0.1, function()
		if killCount and killCount.Parent then
			TweenService:Create(killCount, TweenInfo.new(0.1), { TextSize = 24 }):Play()
		end
	end)
end

local function updateAvatars(killsData)
    for _, child in ipairs(avatarContainer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    
    local sorted = {}
    for name, kills in pairs(killsData) do
        table.insert(sorted, {name = name, kills = kills})
    end
    
    avatarContainer.Visible = true
    if #sorted == 0 then return end
    table.sort(sorted, function(a, b)
        return a.kills > b.kills -- most kills on left
    end)
    
    for i, entry in ipairs(sorted) do
        local p = Players:FindFirstChild(entry.name)
        if p then
            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(0, 64, 0, 84)
            frame.BackgroundTransparency = 1
            frame.LayoutOrder = i
            
            local avatar = Instance.new("ImageLabel")
            avatar.Size = UDim2.new(0, 64, 0, 64)
            avatar.Position = UDim2.new(0, 0, 0, 0)
            avatar.BackgroundColor3 = Color3.fromRGB(20, 24, 34) -- Placeholder background color
            avatar.BackgroundTransparency = 0 -- Instantly visible while loading
            task.spawn(function()
                avatar.Image = Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
            end)
            avatar.Parent = frame
            
            local UICorner = Instance.new("UICorner")
            UICorner.CornerRadius = UDim.new(0, 8)
            UICorner.Parent = avatar
            
            if p == player then
                local UIStroke = Instance.new("UIStroke")
                UIStroke.Color = Color3.fromRGB(255, 255, 255)
                UIStroke.Thickness = 2.5
                UIStroke.Parent = avatar
            end
            
            local killsLbl = Instance.new("TextLabel")
            killsLbl.Size = UDim2.new(1, 0, 0, 20)
            killsLbl.Position = UDim2.new(0, 0, 1, -4)
            killsLbl.BackgroundTransparency = 1
            killsLbl.Text = tostring(entry.kills)
            killsLbl.TextColor3 = Color3.fromRGB(255, 220, 60)
            killsLbl.Font = Enum.Font.GothamBlack
            killsLbl.TextSize = 18
            killsLbl.TextStrokeTransparency = 0
            killsLbl.Parent = frame
            
            frame.Parent = avatarContainer
        end
    end
end

------------------------------------------------------------------------
-- LISTEN TO GAME EVENTS
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)

	if eventName == "intermission" then
		local t = data and data.timeLeft or 0
		local color = (t <= 5) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
		local label = (data and data.waitingForPlayers)
			and "WAITING FOR PLAYERS..."
			or "INTERMISSION"
		showPanel(label, formatTime(t), color)
		killFrame.Visible = false
        joinBtn.Visible = false
        avatarContainer.Visible = false

	elseif eventName == "voting" then
		-- Hide the HUD panel while the voting GUI is open
		topPanel.Visible = false
		killFrame.Visible = false
        joinBtn.Visible = false
        avatarContainer.Visible = false

	elseif eventName == "vote_update" then
		local t = data and data.timeLeft or 0
		-- Only show HUD timer if the player has dismissed the voting cards
		local votingGui = playerGui:FindFirstChild("VotingGui")
		local votingOpen = votingGui and votingGui.Enabled ~= false
		if not votingOpen then
			-- Voting GUI was dismissed — show the timer in the HUD
			topPanel.Visible = true
			currentPhaseText = "VOTING"
			
			-- Boxed styling
			topPanel.Size = UDim2.new(0, 280, 0, 64)
			topPanel.BackgroundTransparency = 0.3
			tps.Transparency = 0
			phaseLabel.Visible = true
			phaseLabel.Text = currentPhaseText
			timerLabel.Size = UDim2.new(1, -16, 0, 32)
			timerLabel.Position = UDim2.new(0, 8, 0, 28)
			timerLabel.TextSize = 26
			timerLabel.TextStrokeTransparency = 1
			timerLabel.Font = Enum.Font.GothamBlack
			
			timerLabel.Text = formatTime(t)
			timerLabel.TextColor3 = (t <= 3) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 220, 60)
            joinBtn.Visible = false
		else
			topPanel.Visible = false
		end

	elseif eventName == "round_start" then
		myRoundKills = 0
		setKillCount(0)
		isTeamBattle = data and data.isTeamBattle or false
		if not isTeamBattle then
			updateAvatars(data and data.initialKills or {})
		else
			avatarContainer.Visible = false
		end
		showPanel(data and data.gamemodeName or "FREE FOR ALL", formatTime(data and data.duration or 300), Color3.fromRGB(255, 255, 255))
		killFrame.Visible = true
		
		-- Show team score panel for Team Battle
		if isTeamBattle then
			redScoreLbl.Text = "0"
			blueScoreLbl.Text = "0"
			teamScorePanel.Visible = true
		else
			teamScorePanel.Visible = false
		end
		


	elseif eventName == "round_tick" then
		local t = data and data.timeLeft or 0
		local color = (t <= 30) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
		
		if currentPhaseText == "INTERMISSION" or currentPhaseText == "VOTING" or currentPhaseText == "WAITING FOR PLAYERS..." or currentPhaseText == "ROUND IN PROGRESS" then
			timerLabel.Text = formatTime(t)
		else
			timerLabel.Text = currentPhaseText .. " - " .. formatTime(t)
		end
		
		timerLabel.TextColor3 = color
        
        -- Check if player is in the lobby or game
        local inLobby = false
        if player.Character and player.Character.PrimaryPart then
            -- Let's say Y < 100 is lobby, Y > 100 is map. Or just use distance from (0,0,0)
            -- A safer way is to check if they have a team assigned or kills frame visible, but
            -- for now we can just show the join button anytime round_tick fires and they click it
            -- Actually, let's just show it, but the button hides itself on click.
            -- Better yet, if killFrame.Visible == false, they aren't in the round.
        end
        
        if not killFrame.Visible then
            topPanel.Visible = true -- Ensure the HUD returns after voting is dismissed!
            currentPhaseText = "ROUND IN PROGRESS"
            
            -- Boxed styling for lobby spectators watching the round
			topPanel.Size = UDim2.new(0, 280, 0, 64)
			topPanel.BackgroundTransparency = 0.3
			tps.Transparency = 0
			phaseLabel.Visible = true
			phaseLabel.Text = currentPhaseText
			timerLabel.Size = UDim2.new(1, -16, 0, 32)
			timerLabel.Position = UDim2.new(0, 8, 0, 28)
			timerLabel.TextSize = 26
			timerLabel.TextStrokeTransparency = 1
			timerLabel.Font = Enum.Font.GothamBlack
            timerLabel.Text = formatTime(t)
            
            joinBtn.Visible = true
        else
            joinBtn.Visible = false
        end

	elseif eventName == "kills_update" then
        if not killFrame.Visible then return end -- DO NOT show avatar row if player is in the lobby
		-- data is a {name = kills} table; find our own count
		if data and data[player.Name] then
			setKillCount(data[player.Name])
		end
		if data and not isTeamBattle then
			updateAvatars(data)
		end

	elseif eventName == "team_kills_update" then
		-- data = { Red = N, Blue = N }
		if data then
			redScoreLbl.Text = tostring(data.Red or 0)
			blueScoreLbl.Text = tostring(data.Blue or 0)
		end

	elseif eventName == "round_end" then
		hidePanel()
		killFrame.Visible = false
		teamScorePanel.Visible = false
        avatarContainer.Visible = false
		
	elseif eventName == "lobby_return" then
        -- Force UI back to lobby state so they can join again
        killFrame.Visible = false
        teamScorePanel.Visible = false
        avatarContainer.Visible = false
        
        if data and data.phase == "round" then
            showPanel("ROUND IN PROGRESS", "", Color3.fromRGB(255, 255, 255))
            joinBtn.Position = UDim2.new(0.5, 0, 1, 12)
            joinBtn.Visible = true
        elseif data and data.phase == "intermission" then
            showPanel("INTERMISSION", "", Color3.fromRGB(255, 255, 255))
            joinBtn.Visible = false
        elseif data and data.phase == "voting" then
            joinBtn.Visible = false
        else
            hidePanel()
        end
	end
end)

print("✅ RoundHUDController Loaded")
