-- TeamAnnouncementController.client.lua
-- Shows a team assignment screen when a Team Battle round starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 15)
if not GameEvent then return end

------------------------------------------------------------------------
-- SHOW TEAM SCREEN
------------------------------------------------------------------------
local function showTeamScreen(myTeam)
	-- Remove old if any
	local old = playerGui:FindFirstChild("TeamAnnouncementGui")
	if old then old:Destroy() end

	local isRed = myTeam == "Red"
	local teamColor    = isRed and Color3.fromRGB(220, 40, 40)   or Color3.fromRGB(40, 100, 220)
	local teamName     = isRed and "RED TEAM"                    or "BLUE TEAM"
	local teamTagline  = isRed and "Get those blues!"            or "Eliminate those reds!"
	local glowColor    = isRed and Color3.fromRGB(255, 80, 80)   or Color3.fromRGB(80, 160, 255)

	local sg = Instance.new("ScreenGui")
	sg.Name = "TeamAnnouncementGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = playerGui

	-- Full-screen dark overlay
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.35
	bg.BorderSizePixel = 0
	bg.Parent = sg

	-- Centre card (starts below screen, slides up)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 400, 0, 220)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 1.5, 0) -- off bottom
	card.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = sg
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 18); cr.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Color = teamColor; cs.Thickness = 3; cs.Parent = card

	-- Slide up
	TweenService:Create(card,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }
	):Play()

	-- Team name (big colored text)
	local teamLbl = Instance.new("TextLabel")
	teamLbl.Size = UDim2.new(1, -20, 0, 80)
	teamLbl.Position = UDim2.new(0, 10, 0, 18)
	teamLbl.BackgroundTransparency = 1
	teamLbl.Text = teamName
	teamLbl.TextColor3 = teamColor
	teamLbl.Font = Enum.Font.GothamBlack
	teamLbl.TextSize = 54
	teamLbl.TextStrokeTransparency = 0.6
	teamLbl.TextStrokeColor3 = glowColor
	teamLbl.Parent = card

	-- Tagline
	local tagLbl = Instance.new("TextLabel")
	tagLbl.Size = UDim2.new(1, -20, 0, 34)
	tagLbl.Position = UDim2.new(0, 10, 0, 102)
	tagLbl.BackgroundTransparency = 1
	tagLbl.Text = teamTagline
	tagLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
	tagLbl.Font = Enum.Font.GothamBold
	tagLbl.TextSize = 22
	tagLbl.Parent = card

	-- OK button
	local okBtn = Instance.new("TextButton")
	okBtn.Size = UDim2.new(0, 140, 0, 42)
	okBtn.Position = UDim2.new(0.5, -70, 1, -56)
	okBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 60)
	okBtn.Text = "OK"
	okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	okBtn.Font = Enum.Font.GothamBlack
	okBtn.TextSize = 22
	okBtn.BorderSizePixel = 0
	okBtn.Parent = card
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = okBtn

	-- Hover effect
	okBtn.MouseEnter:Connect(function()
		TweenService:Create(okBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(40, 200, 80) }):Play()
	end)
	okBtn.MouseLeave:Connect(function()
		TweenService:Create(okBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(30, 160, 60) }):Play()
	end)

	local function dismiss()
		TweenService:Create(card,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, -0.6, 0) }
		):Play()
		task.delay(0.35, function()
			if sg and sg.Parent then sg:Destroy() end
		end)
	end

	okBtn.MouseButton1Click:Connect(dismiss)

	-- Auto-dismiss after 8 seconds
	task.delay(8, function()
		if sg and sg.Parent then dismiss() end
	end)
end

------------------------------------------------------------------------
-- LISTEN
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)
	if eventName == "round_start" then
		if data and data.teams then
			local myTeam = data.teams[player.Name]
			if myTeam then
				showTeamScreen(myTeam)
			end
		end
	elseif eventName == "round_end" or eventName == "intermission" then
		local old = playerGui:FindFirstChild("TeamAnnouncementGui")
		if old then old:Destroy() end
	end
end)

print("✅ TeamAnnouncementController Loaded")
