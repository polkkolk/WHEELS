-- LeaderboardController.client.lua
-- Displays end-of-round podium leaderboard with avatars.
-- Top 3 players on podiums, kill counts, auto-close after timer, X to close early.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 10)
if not GameEvent then return end

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = parent
	return c
end

------------------------------------------------------------------------
-- BUILD PODIUM UI
------------------------------------------------------------------------
local function buildLeaderboard(data)
	local leaderboard = data.leaderboard or {}
	local old = playerGui:FindFirstChild("LeaderboardGui")
	if old then old:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name = "LeaderboardGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = playerGui

	-- Dark overlay
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.35
	bg.BorderSizePixel = 0
	bg.Parent = sg

	-- Main panel — starts above screen, tweens down
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 700, 0, 520)
	panel.Position = UDim2.new(0.5, 0, -0.6, 0)  -- start off-screen above
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	panel.BorderSizePixel = 0
	panel.Parent = sg
	makeCorner(panel, UDim.new(0, 18))
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(70, 80, 110); ps.Thickness = 2; ps.Parent = panel

	-- Slide in from top
	TweenService:Create(panel, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()

	-- Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -80, 0, 52)
	titleLbl.Position = UDim2.new(0, 0, 0, 18)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "ROUND OVER"
	titleLbl.TextColor3 = Color3.fromRGB(255, 220, 60)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 38
	titleLbl.Parent = panel

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -80, 0, 26)
	subLbl.Position = UDim2.new(0, 0, 0, 68)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = (data.gamemodeName or "Free For All") .. " — Final Standings"
	subLbl.TextColor3 = Color3.fromRGB(160, 170, 190)
	subLbl.Font = Enum.Font.Gotham
	subLbl.TextSize = 18
	subLbl.Parent = panel

	-- Winning team banner (Team Battle only)
	local bannerOffset = 0
	if data.winningTeam then
		bannerOffset = 36
		local banner = Instance.new("Frame")
		banner.Size = UDim2.new(0.88, 0, 0, 30)
		banner.Position = UDim2.new(0.06, 0, 0, 96)
		banner.BorderSizePixel = 0
		if data.winningTeam == "Red" then
			banner.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
		elseif data.winningTeam == "Blue" then
			banner.BackgroundColor3 = Color3.fromRGB(30, 80, 200)
		else
			banner.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
		end
		banner.Parent = panel
		makeCorner(banner, UDim.new(0, 6))
		local bannerLbl = Instance.new("TextLabel")
		bannerLbl.Size = UDim2.fromScale(1, 1)
		bannerLbl.BackgroundTransparency = 1
		bannerLbl.Text = data.winningTeam == "Tie" and "DRAW — No Winner"
			or data.winningTeam:upper() .. " TEAM WINS!"
		bannerLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		bannerLbl.Font = Enum.Font.GothamBlack
		bannerLbl.TextSize = 17
		bannerLbl.Parent = banner
	end

	-- Timer label (top LEFT inside panel — away from X button)
	local closeTimer = Instance.new("TextLabel")
	closeTimer.Name = "CloseTimer"
	closeTimer.Size = UDim2.new(0, 130, 0, 30)
	closeTimer.Position = UDim2.new(1, -200, 0, 20)  -- far enough left to not overlap X
	closeTimer.BackgroundTransparency = 1
	closeTimer.Text = ""
	closeTimer.TextColor3 = Color3.fromRGB(120, 130, 160)
	closeTimer.Font = Enum.Font.Gotham
	closeTimer.TextSize = 15
	closeTimer.TextXAlignment = Enum.TextXAlignment.Right
	closeTimer.Parent = panel

	-- X close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 38, 0, 38)
	closeBtn.Position = UDim2.new(1, -50, 0, 14)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 10
	closeBtn.Parent = panel
	makeCorner(closeBtn, UDim.new(0.3, 0))
	closeBtn.MouseButton1Click:Connect(function()
		sg:Destroy()
	end)

	-- ── PODIUM SECTION ──────────────────────────────────────────────
	-- Order: 2nd (left), 1st (centre/tallest), 3rd (right)
	local podiumOrder = { 2, 1, 3 }
	local podiumConfigs = {
		-- place → { xOffset, height, baseColor, placeLabel, labelColor }
		[1] = { x = 0,    h = 160, col = Color3.fromRGB(255, 200, 40),  label = "1st", lc = Color3.fromRGB(255, 200, 40) },
		[2] = { x = -230, h = 120, col = Color3.fromRGB(192, 192, 200), label = "2nd", lc = Color3.fromRGB(210, 210, 220) },
		[3] = { x = 230,  h = 90,  col = Color3.fromRGB(180, 120, 60),  label = "3rd", lc = Color3.fromRGB(180, 120, 60) },
	}

	for _, place in ipairs(podiumOrder) do
		local cfg = podiumConfigs[place]
		local entry = leaderboard[place] -- may be nil

		local cx = 0.5
		-- x offset in scale relative to panel width 700
		local xOff = cfg.x / 700

		-- ─ Podium block ─
		local blockH = cfg.h
		local podiumBlock = Instance.new("Frame")
		podiumBlock.Name = "Podium" .. place
		podiumBlock.Size = UDim2.new(0, 160, 0, blockH)
		podiumBlock.Position = UDim2.new(cx + xOff - 0.114, 0, 1, -(blockH + 50))
		podiumBlock.BackgroundColor3 = cfg.col
		podiumBlock.BorderSizePixel = 0
		podiumBlock.Parent = panel
		makeCorner(podiumBlock, UDim.new(0, 10))
		local topFace = Instance.new("Frame")
		topFace.Size = UDim2.new(1, 0, 0, 10)
		topFace.BackgroundColor3 = Color3.new(1,1,1)
		topFace.BackgroundTransparency = 0.75
		topFace.BorderSizePixel = 0
		topFace.Parent = podiumBlock
		makeCorner(topFace, UDim.new(0, 8))

		-- Place label on block
		local placeLbl = Instance.new("TextLabel")
		placeLbl.Size = UDim2.new(1, 0, 0, 30)
		placeLbl.Position = UDim2.new(0, 0, 0.5, -15)
		placeLbl.BackgroundTransparency = 1
		placeLbl.Text = cfg.label
		placeLbl.TextColor3 = Color3.fromRGB(30, 25, 15)
		placeLbl.Font = Enum.Font.GothamBlack
		placeLbl.TextSize = 22
		placeLbl.Parent = podiumBlock

		-- ─ Avatar section (above podium) ─
		local avatarBase = podiumBlock.Position.Y.Scale
		local avatarY = 1 - ((blockH + 50 + 140) / 520)

		-- Avatar image (headshot)
		local avatarImg = Instance.new("ImageLabel")
		avatarImg.Name = "Avatar"
		avatarImg.Size = UDim2.new(0, 80, 0, 80)
		avatarImg.Position = UDim2.new(cx + xOff - 0.057, 0, 0, 108 + bannerOffset)
		avatarImg.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
		avatarImg.BorderSizePixel = 0
		avatarImg.Parent = panel
		makeCorner(avatarImg, UDim.new(0.5, 0))
		local ais = Instance.new("UIStroke"); ais.Color = cfg.col; ais.Thickness = 3; ais.Parent = avatarImg

		if entry then
			avatarImg.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. entry.userId .. "&width=100&height=100&format=png"
		else
			avatarImg.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
		end

		-- Name label
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0, 160, 0, 26)
		nameLbl.Position = UDim2.new(cx + xOff - 0.114, 0, 0, 194 + bannerOffset)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = entry and entry.name or "—"
		nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 17
		nameLbl.Parent = panel

		-- Kills label
		local killsLbl = Instance.new("TextLabel")
		killsLbl.Size = UDim2.new(0, 160, 0, 22)
		killsLbl.Position = UDim2.new(cx + xOff - 0.114, 0, 0, 222)
		killsLbl.BackgroundTransparency = 1
		local killCount = entry and entry.kills or 0
		killsLbl.Text = killCount == 1 and "1 kill" or (killCount .. " kills")
		killsLbl.TextColor3 = cfg.lc
		killsLbl.Font = Enum.Font.Gotham
		killsLbl.TextSize = 14
		killsLbl.Parent = panel
	end

	-- ── RANK LIST (below podium, shows places 4+) ─────────────────
	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(0.88, 0, 0, 1)
	sep.Position = UDim2.new(0.06, 0, 0, 266)
	sep.BackgroundColor3 = Color3.fromRGB(60, 68, 95)
	sep.BorderSizePixel = 0
	sep.Parent = panel

	if #leaderboard > 3 then
		local scrollFrame = Instance.new("ScrollingFrame")
		scrollFrame.Size = UDim2.new(0.88, 0, 0, 125)
		scrollFrame.Position = UDim2.new(0.06, 0, 0, 276)
		scrollFrame.BackgroundTransparency = 1
		scrollFrame.BorderSizePixel = 0
		scrollFrame.ScrollBarThickness = 4
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, (#leaderboard - 3) * 34)
		scrollFrame.Parent = panel

		local listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 4)
		listLayout.Parent = scrollFrame

		for rank = 4, #leaderboard do
			local entry = leaderboard[rank]
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 30)
			row.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
			row.BorderSizePixel = 0
			row.LayoutOrder = rank
			row.Parent = scrollFrame
			makeCorner(row, UDim.new(0, 6))

			local rankLbl = Instance.new("TextLabel")
			rankLbl.Size = UDim2.new(0, 30, 1, 0)
			rankLbl.BackgroundTransparency = 1
			rankLbl.Text = "#" .. rank
			rankLbl.TextColor3 = Color3.fromRGB(130, 140, 160)
			rankLbl.Font = Enum.Font.GothamBold
			rankLbl.TextSize = 14
			rankLbl.Parent = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -80, 1, 0)
			nameLbl.Position = UDim2.new(0, 34, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = entry.name
			nameLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
			nameLbl.Font = Enum.Font.Gotham
			nameLbl.TextSize = 14
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = row

			local kLbl = Instance.new("TextLabel")
			kLbl.Size = UDim2.new(0, 60, 1, 0)
			kLbl.Position = UDim2.new(1, -64, 0, 0)
			kLbl.BackgroundTransparency = 1
			kLbl.Text = entry.kills .. " kills"
			kLbl.TextColor3 = Color3.fromRGB(180, 130, 50)
			kLbl.Font = Enum.Font.GothamBold
			kLbl.TextSize = 13
			kLbl.Parent = row
		end
	end

	-- Auto-close countdown
	local timeLeft = 15
	task.spawn(function()
		while timeLeft > 0 do
			closeTimer.Text = "Closes in " .. timeLeft .. "s"
			task.wait(1)
			timeLeft = timeLeft - 1
			if not sg.Parent then return end
		end
		if sg.Parent then sg:Destroy() end
	end)
end

------------------------------------------------------------------------
-- LISTEN
------------------------------------------------------------------------
GameEvent.OnClientEvent:Connect(function(eventName, data)
	if eventName == "round_end" then
		buildLeaderboard(data or {})
	elseif eventName == "intermission" then
		-- Optionally auto-close if still open
		local gui = playerGui:FindFirstChild("LeaderboardGui")
		if gui then
			task.delay(3, function()
				if gui and gui.Parent then gui:Destroy() end
			end)
		end
	end
end)

print("✅ LeaderboardController Loaded")
