-- VotingController.client.lua
-- Displays the voting screen when the server broadcasts "voting" phase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 15)
local VoteEvent = ReplicatedStorage:WaitForChild("VoteEvent", 15)

if not GameEvent then warn("VotingController: GameEvent missing!") return end
if not VoteEvent then warn("VotingController: VoteEvent missing!") return end

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local currentGui = nil
local activeCardFrames = nil
local dismissed = false

------------------------------------------------------------------------
-- DESTROY OLD GUI
------------------------------------------------------------------------
local function destroyGui()
	if currentGui and currentGui.Parent then
		currentGui:Destroy()
	end
	currentGui = nil
	activeCardFrames = nil
	dismissed = false
end

------------------------------------------------------------------------
-- BUILD VOTING UI
------------------------------------------------------------------------
local function buildVotingUI(cards)
	destroyGui()

	local sg = Instance.new("ScreenGui")
	sg.Name = "VotingGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = playerGui
	currentGui = sg

	-- Full-screen dim
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.45
	bg.BorderSizePixel = 0
	bg.Parent = sg

	-- Title (top-centre)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 52)
	title.Position = UDim2.new(0, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Text = "VOTE FOR THE NEXT MAP"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 32
	title.TextStrokeTransparency = 0
	title.Parent = sg

	-- Timer label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0, 28)
	timerLabel.Position = UDim2.new(0, 0, 0, 78)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "10s"
	timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.TextSize = 18
	timerLabel.Parent = sg

	-- X close button (top-right)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -60, 0, 16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = sg
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0.3, 0); cc.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		dismissed = true
		sg.Enabled = false
	end)

	-- ── 3 CARDS laid out horizontally across 80% of the screen ──────
	local CARD_W = 240
	local CARD_H = 300
	local GAP = 24
	local totalW = CARD_W * 3 + GAP * 2
	local startX = (1 - (totalW / workspace.CurrentCamera.ViewportSize.X)) / 2

	local cardFrames = {}

	for i, cardData in ipairs(cards) do
		local card = Instance.new("Frame")
		card.Name = "Card" .. i
		card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
		-- Position each card evenly
		local xPx = (i - 1) * (CARD_W + GAP)
		card.Position = UDim2.new(0.5, xPx - totalW/2 + (i-1) * 0, 0.5, -CARD_H/2)
		-- Correct x using absolute offset from center
		card.Position = UDim2.new(
			0.5,
			(i - 2) * (CARD_W + GAP),   -- i=1: -(CARD_W+GAP), i=2: 0, i=3: +(CARD_W+GAP)
			0.5,
			-CARD_H / 2 + 30
		)
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
		card.BorderSizePixel = 0
		card.Parent = sg
		local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 14); cr.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(70, 85, 130); cs.Thickness = 2; cs.Parent = card

		-- Gamemode name (big)
		local modeLbl = Instance.new("TextLabel")
		modeLbl.Size = UDim2.new(1, -20, 0, 52)
		modeLbl.Position = UDim2.new(0, 10, 0, 16)
		modeLbl.BackgroundTransparency = 1
		modeLbl.Text = cardData.gamemodeName
		modeLbl.TextColor3 = Color3.fromRGB(255, 220, 60)
		modeLbl.Font = Enum.Font.GothamBlack
		modeLbl.TextSize = 20
		modeLbl.TextXAlignment = Enum.TextXAlignment.Center
		modeLbl.TextWrapped = true
		modeLbl.Parent = card

		-- Divider
		local div = Instance.new("Frame")
		div.Size = UDim2.new(0.8, 0, 0, 1)
		div.Position = UDim2.new(0.1, 0, 0, 72)
		div.BackgroundColor3 = Color3.fromRGB(60, 70, 100)
		div.BorderSizePixel = 0
		div.Parent = card

		-- Map name
		local mapLbl = Instance.new("TextLabel")
		mapLbl.Size = UDim2.new(1, -20, 0, 36)
		mapLbl.Position = UDim2.new(0, 10, 0, 80)
		mapLbl.BackgroundTransparency = 1
		mapLbl.Text = cardData.mapName
		mapLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		mapLbl.Font = Enum.Font.GothamBold
		mapLbl.TextSize = 17
		mapLbl.TextXAlignment = Enum.TextXAlignment.Center
		mapLbl.Parent = card

		-- Description
		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, -20, 0, 36)
		descLbl.Position = UDim2.new(0, 10, 0, 120)
		descLbl.BackgroundTransparency = 1
		descLbl.Text = cardData.description
		descLbl.TextColor3 = Color3.fromRGB(140, 155, 185)
		descLbl.Font = Enum.Font.Gotham
		descLbl.TextSize = 14
		descLbl.TextXAlignment = Enum.TextXAlignment.Center
		descLbl.TextWrapped = true
		descLbl.Parent = card

		-- Head area (avatar headshots of voters)
		local headArea = Instance.new("Frame")
		headArea.Name = "HeadArea"
		headArea.Size = UDim2.new(1, -20, 0, 72)
		headArea.Position = UDim2.new(0, 10, 1, -100)
		headArea.BackgroundTransparency = 1
		headArea.ClipsDescendants = true
		headArea.Parent = card
		local hl = Instance.new("UIListLayout")
		hl.FillDirection = Enum.FillDirection.Horizontal
		hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		hl.VerticalAlignment = Enum.VerticalAlignment.Center
		hl.Padding = UDim.new(0, 4)
		hl.Parent = headArea

		-- Vote count
		local voteBadge = Instance.new("TextLabel")
		voteBadge.Name = "VoteBadge"
		voteBadge.Size = UDim2.new(1, -20, 0, 22)
		voteBadge.Position = UDim2.new(0, 10, 1, -26)
		voteBadge.BackgroundTransparency = 1
		voteBadge.Text = "0 votes"
		voteBadge.TextColor3 = Color3.fromRGB(130, 145, 175)
		voteBadge.Font = Enum.Font.GothamBold
		voteBadge.TextSize = 13
		voteBadge.TextXAlignment = Enum.TextXAlignment.Center
		voteBadge.Parent = card

		-- Invisible click button on top
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.ZIndex = 10
		btn.Parent = card

		local selectedIdx = i
		btn.MouseButton1Click:Connect(function()
			if dismissed then return end
			VoteEvent:FireServer(selectedIdx)
			-- Highlight this card
			for j, cf in ipairs(cardFrames) do
				local stroke = cf:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = (j == selectedIdx) and Color3.fromRGB(255, 220, 60) or Color3.fromRGB(70, 85, 130)
					stroke.Thickness = (j == selectedIdx) and 4 or 2
				end
			end
		end)

		-- Hover effect
		btn.MouseEnter:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(26, 32, 52) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(18, 22, 36) }):Play()
		end)

		cardFrames[i] = card

		-- DEAL ANIMATION: start above screen, tween down with stagger
		local finalPos = card.Position
		card.Position = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -0.5, 0)
		task.delay((i - 1) * 0.12, function()
			if card and card.Parent then
				TweenService:Create(card,
					TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = finalPos }
				):Play()
			end
		end)
	end

	return cardFrames
end

------------------------------------------------------------------------
-- UPDATE VOTER DISPLAY
------------------------------------------------------------------------
local function updateVoters(cardFrames, voterHeads, counts, timeLeft)
	if not cardFrames then return end
	for i, card in ipairs(cardFrames) do
		local headArea = card:FindFirstChild("HeadArea")
		local badge    = card:FindFirstChild("VoteBadge")

		if badge then
			local n = (counts and counts[i]) or 0
			badge.Text = n == 1 and "1 vote" or (n .. " votes")
		end

		if headArea then
			for _, c in ipairs(headArea:GetChildren()) do
				if c:IsA("ImageLabel") then c:Destroy() end
			end
			local voters = (voterHeads and voterHeads[i]) or {}
			for idx, info in ipairs(voters) do
				if idx > 5 then break end
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.new(0, 44, 0, 44)
				img.BackgroundColor3 = Color3.fromRGB(40, 48, 70)
				img.BorderSizePixel = 0
				img.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. info.userId .. "&width=60&height=60&format=png"
				img.Parent = headArea
				local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0.5, 0); ic.Parent = img
			end
		end
	end

	-- Update timer in VotingGui
	if currentGui and timeLeft then
		local tl = currentGui:FindFirstChild("TimerLabel")
		if tl then
			tl.Text = "Voting ends in " .. math.ceil(timeLeft) .. "s"
			tl.TextColor3 = (timeLeft <= 3) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(200, 200, 200)
		end
	end
end

------------------------------------------------------------------------
-- EVENT LISTENER
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)
	-- Only log voting-related events
	if eventName == "voting" or eventName == "vote_update" then
		print("🗳 VotingController received event:", eventName)
	end

	if eventName == "voting" then
		print("🗳 Building voting UI with", data and data.cards and #data.cards or 0, "cards")
		local frames = buildVotingUI(data.cards or {})
		activeCardFrames = frames
		print("🗳 Voting UI built, frames:", #(activeCardFrames or {}))

	elseif eventName == "vote_update" then
		if currentGui and currentGui.Parent then
			updateVoters(activeCardFrames, data.voterHeads, data.counts, data.timeLeft)
		end

	elseif eventName == "round_start" or eventName == "intermission" then
		destroyGui()
	end
end)

print("✅ VotingController Loaded")
