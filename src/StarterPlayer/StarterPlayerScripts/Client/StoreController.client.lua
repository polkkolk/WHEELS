-- StoreController.client.lua
-- Manages the Coin Store UI and prompts Roblox Developer Products

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PRODUCT_IDS = {
	{coins = 250, robux = 150, id = 3609550136},
	{coins = 500, robux = 290, id = 3609550195},
	{coins = 1000, robux = 550, id = 3609550233},
	{coins = 5000, robux = 2500, id = 3609550278, tag = "EXTREME VALUE!"}
}

-- Create UI
local sg = Instance.new("ScreenGui")
sg.Name = "StoreMenu"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 100
sg.Enabled = false
sg.Parent = playerGui

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency = 0.5
bg.Active = true
bg.Parent = sg

local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(0, 800, 0, 500)
container.Position = UDim2.new(0.5, 0, 0.5, 0)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
container.BorderSizePixel = 0
container.Parent = bg

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 16)
uiCorner.Parent = container

local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(255, 200, 40)
uiStroke.Thickness = 3
uiStroke.Transparency = 0.5
uiStroke.Parent = container

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 80)
title.BackgroundTransparency = 1
title.Text = "COIN STORE"
title.TextColor3 = Color3.fromRGB(255, 220, 50)
title.Font = Enum.Font.GothamBlack
title.TextSize = 42
title.Parent = container

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 50, 0, 50)
closeBtn.Position = UDim2.new(1, -15, 0, 15)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 24
closeBtn.AutoButtonColor = false
closeBtn.Parent = container

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0.5, 0)
closeCorner.Parent = closeBtn

local cardContainer = Instance.new("ScrollingFrame")
cardContainer.Name = "CardContainer"
cardContainer.Size = UDim2.new(1, -40, 1, -120)
cardContainer.Position = UDim2.new(0, 20, 0, 90)
cardContainer.BackgroundTransparency = 1
cardContainer.ScrollBarThickness = 8
cardContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
cardContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
cardContainer.Parent = container

local mainLayout = Instance.new("UIListLayout")
mainLayout.FillDirection = Enum.FillDirection.Vertical
mainLayout.Padding = UDim.new(0, 30)
mainLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainLayout.Parent = cardContainer

-- Coins Section
local coinsSection = Instance.new("Frame")
coinsSection.Name = "CoinsSection"
coinsSection.Size = UDim2.new(1, 0, 0, 0)
coinsSection.AutomaticSize = Enum.AutomaticSize.Y
coinsSection.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
coinsSection.LayoutOrder = 1
coinsSection.Parent = cardContainer

local coinsPadding = Instance.new("UIPadding")
coinsPadding.PaddingTop = UDim.new(0, 20)
coinsPadding.PaddingBottom = UDim.new(0, 20)
coinsPadding.Parent = coinsSection

local coinsCorner = Instance.new("UICorner")
coinsCorner.CornerRadius = UDim.new(0, 12)
coinsCorner.Parent = coinsSection

local coinsLayout = Instance.new("UIGridLayout")
coinsLayout.CellSize = UDim2.new(0, 170, 0, 250)
coinsLayout.CellPadding = UDim2.new(0, 15, 0, 20)
coinsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
coinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
coinsLayout.Parent = coinsSection

for i, product in ipairs(PRODUCT_IDS) do
	local card = Instance.new("TextButton")
	card.Name = "Product_" .. product.coins
	card.LayoutOrder = i
	card.Size = UDim2.new(0, 170, 0, 250)
	card.BackgroundColor3 = Color3.fromRGB(30, 36, 50)
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = coinsSection
	
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card
	
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 200, 40)
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.5
	cardStroke.Parent = card
	
	-- Coin icon
	local coinIcon = Instance.new("TextLabel")
	coinIcon.Size = UDim2.new(0, 80, 0, 80)
	coinIcon.Position = UDim2.new(0.5, 0, 0, 20)
	coinIcon.AnchorPoint = Vector2.new(0.5, 0)
	coinIcon.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
	coinIcon.Text = "$"
	coinIcon.TextColor3 = Color3.fromRGB(80, 50, 0)
	coinIcon.Font = Enum.Font.GothamBlack
	coinIcon.TextSize = 48
	coinIcon.Parent = card
	
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0.5, 0)
	iconCorner.Parent = coinIcon
	
	-- Coins amount
	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Size = UDim2.new(1, 0, 0, 40)
	coinsLabel.Position = UDim2.new(0, 0, 0, 110)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Text = product.coins .. " Coins"
	coinsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextSize = 24
	coinsLabel.Parent = card
	
	-- Buy Button (Robux)
	local buyBtn = Instance.new("Frame")
	buyBtn.Size = UDim2.new(0, 130, 0, 45)
	buyBtn.Position = UDim2.new(0.5, 0, 1, -20)
	buyBtn.AnchorPoint = Vector2.new(0.5, 1)
	buyBtn.BackgroundColor3 = Color3.fromRGB(40, 200, 80)
	buyBtn.Parent = card
	
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buyBtn
	
	local buyLabel = Instance.new("TextLabel")
	buyLabel.Size = UDim2.new(1, 0, 1, 0)
	buyLabel.BackgroundTransparency = 1
	buyLabel.Text = "R$ " .. product.robux
	buyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyLabel.Font = Enum.Font.GothamBlack
	buyLabel.TextSize = 20
	buyLabel.Parent = buyBtn
	
	if product.tag then
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Size = UDim2.new(1.2, 0, 0, 30)
		tagLabel.Position = UDim2.new(0.5, 0, 0, -15)
		tagLabel.AnchorPoint = Vector2.new(0.5, 0)
		tagLabel.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		tagLabel.Text = product.tag
		tagLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		tagLabel.Font = Enum.Font.GothamBold
		tagLabel.TextSize = 14
		tagLabel.Rotation = -5
		tagLabel.Parent = card
		
		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 6)
		tagCorner.Parent = tagLabel
		
		local tagStroke = Instance.new("UIStroke")
		tagStroke.Color = Color3.fromRGB(255, 255, 255)
		tagStroke.Thickness = 1.5
		tagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tagStroke.Parent = tagLabel
		
		-- Emphasize card
		cardStroke.Color = Color3.fromRGB(255, 50, 50)
		cardStroke.Thickness = 3
	end
	
	-- Hover logic
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = card

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(40, 48, 65),
			Position = UDim2.new(0, 0, 0, -10)
		}):Play()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(30, 36, 50),
			Position = UDim2.new(0, 0, 0, 0)
		}):Play()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	
	-- Click to prompt purchase
	card.MouseButton1Click:Connect(function()
		-- Button pop effect
		TweenService:Create(buyBtn, TweenInfo.new(0.1), {Size = UDim2.new(0, 120, 0, 40)}):Play()
		task.wait(0.1)
		TweenService:Create(buyBtn, TweenInfo.new(0.1), {Size = UDim2.new(0, 130, 0, 45)}):Play()
		
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)
end

-- ==============================================
-- GAMEPASSES SECTION
-- ==============================================
local gpHeader = Instance.new("TextLabel")
gpHeader.Name = "GamepassesHeader"
gpHeader.Size = UDim2.new(1, 0, 0, 40)
gpHeader.BackgroundTransparency = 1
gpHeader.Text = "GAMEPASSES"
gpHeader.TextColor3 = Color3.fromRGB(200, 100, 255)
gpHeader.Font = Enum.Font.GothamBlack
gpHeader.TextSize = 32
gpHeader.LayoutOrder = 2
gpHeader.Parent = cardContainer

local gpSection = Instance.new("Frame")
gpSection.Name = "GamepassesSection"
gpSection.Size = UDim2.new(1, 0, 0, 0)
gpSection.AutomaticSize = Enum.AutomaticSize.Y
gpSection.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
gpSection.LayoutOrder = 3
gpSection.Parent = cardContainer

local gpPadding = Instance.new("UIPadding")
gpPadding.PaddingTop = UDim.new(0, 20)
gpPadding.PaddingBottom = UDim.new(0, 20)
gpPadding.Parent = gpSection

local gpCorner = Instance.new("UICorner")
gpCorner.CornerRadius = UDim.new(0, 12)
gpCorner.Parent = gpSection

local gpLayout = Instance.new("UIGridLayout")
gpLayout.CellSize = UDim2.new(0, 170, 0, 250)
gpLayout.CellPadding = UDim2.new(0, 15, 0, 20)
gpLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gpLayout.SortOrder = Enum.SortOrder.LayoutOrder
gpLayout.Parent = gpSection

local DOUBLE_VOTES_ID = 1907323651
local ownsDoubleVotes = player:GetAttribute("OwnsDoubleVotes")

local dvCard = Instance.new("TextButton")
dvCard.Name = "Gamepass_DoubleVotes"
dvCard.LayoutOrder = 1
dvCard.BackgroundColor3 = ownsDoubleVotes and Color3.fromRGB(50, 50, 50) or Color3.fromRGB(40, 30, 60)
dvCard.Text = ""
dvCard.AutoButtonColor = false
dvCard.Parent = gpSection

local dvCorner = Instance.new("UICorner")
dvCorner.CornerRadius = UDim.new(0, 12)
dvCorner.Parent = dvCard

local dvStroke = Instance.new("UIStroke")
dvStroke.Color = Color3.fromRGB(200, 100, 255)
dvStroke.Thickness = 1.5
dvStroke.Transparency = ownsDoubleVotes and 0.8 or 0.2
dvStroke.Parent = dvCard

-- Icon
local dvIcon = Instance.new("TextLabel")
dvIcon.Size = UDim2.new(0, 80, 0, 80)
dvIcon.Position = UDim2.new(0.5, 0, 0, 20)
dvIcon.AnchorPoint = Vector2.new(0.5, 0)
dvIcon.BackgroundColor3 = ownsDoubleVotes and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(200, 100, 255)
dvIcon.Text = "🗳️"
dvIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
dvIcon.Font = Enum.Font.GothamBlack
dvIcon.TextSize = 50
dvIcon.Parent = dvCard

local dvIconCorner = Instance.new("UICorner")
dvIconCorner.CornerRadius = UDim.new(0.5, 0)
dvIconCorner.Parent = dvIcon

-- Title
local dvLabel = Instance.new("TextLabel")
dvLabel.Size = UDim2.new(1, 0, 0, 40)
dvLabel.Position = UDim2.new(0, 0, 0, 110)
dvLabel.BackgroundTransparency = 1
dvLabel.Text = "Double Votes"
dvLabel.TextColor3 = ownsDoubleVotes and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 255, 255)
dvLabel.Font = Enum.Font.GothamBold
dvLabel.TextSize = 20
dvLabel.Parent = dvCard

-- Thank You / Buy Button
if ownsDoubleVotes then
	local tyLabel = Instance.new("TextLabel")
	tyLabel.Size = UDim2.new(1, 0, 1, 0)
	tyLabel.Position = UDim2.new(0, 0, 0, 0)
	tyLabel.BackgroundTransparency = 1
	tyLabel.Text = "Thank You!"
	tyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	tyLabel.Font = Enum.Font.GothamBlack
	tyLabel.TextSize = 28
	tyLabel.Rotation = -15
	tyLabel.ZIndex = 10
	tyLabel.TextStrokeTransparency = 0
	tyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	tyLabel.Parent = dvCard
else
	local dvBuyBtn = Instance.new("Frame")
	dvBuyBtn.Size = UDim2.new(0, 130, 0, 45)
	dvBuyBtn.Position = UDim2.new(0.5, 0, 1, -20)
	dvBuyBtn.AnchorPoint = Vector2.new(0.5, 1)
	dvBuyBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 200)
	dvBuyBtn.Parent = dvCard

	local dvBuyCorner = Instance.new("UICorner")
	dvBuyCorner.CornerRadius = UDim.new(0, 8)
	dvBuyCorner.Parent = dvBuyBtn

	local dvBuyLabel = Instance.new("TextLabel")
	dvBuyLabel.Size = UDim2.new(1, 0, 1, 0)
	dvBuyLabel.BackgroundTransparency = 1
	dvBuyLabel.Text = "R$ 79" -- Adjust robux price here
	dvBuyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	dvBuyLabel.Font = Enum.Font.GothamBlack
	dvBuyLabel.TextSize = 20
	dvBuyLabel.Parent = dvBuyBtn
	
	-- Hover logic
	local dvScale = Instance.new("UIScale")
	dvScale.Scale = 1
	dvScale.Parent = dvCard

	dvCard.MouseEnter:Connect(function()
		TweenService:Create(dvCard, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(60, 40, 80),
			Position = UDim2.new(0, 0, 0, -10)
		}):Play()
		TweenService:Create(dvScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
	end)
	dvCard.MouseLeave:Connect(function()
		TweenService:Create(dvCard, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(40, 30, 60),
			Position = UDim2.new(0, 0, 0, 0)
		}):Play()
		TweenService:Create(dvScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	
	dvCard.MouseButton1Click:Connect(function()
		TweenService:Create(dvBuyBtn, TweenInfo.new(0.1), {Size = UDim2.new(0, 120, 0, 40)}):Play()
		task.wait(0.1)
		TweenService:Create(dvBuyBtn, TweenInfo.new(0.1), {Size = UDim2.new(0, 130, 0, 45)}):Play()
		MarketplaceService:PromptGamePassPurchase(player, DOUBLE_VOTES_ID)
	end)
end
-- ==============================================

-- Close Button Logic
closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(255, 80, 80)}):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(200, 50, 50)}):Play()
end)
closeBtn.MouseButton1Click:Connect(function()
	sg.Enabled = false
end)

-- Open Event Listener
local storeEvent = ReplicatedStorage:FindFirstChild("ToggleStoreMenu")
if not storeEvent then
	storeEvent = Instance.new("BindableEvent")
	storeEvent.Name = "ToggleStoreMenu"
	storeEvent.Parent = ReplicatedStorage
end

storeEvent.Event:Connect(function()
	sg.Enabled = not sg.Enabled
	if sg.Enabled then
		container.Size = UDim2.new(0, 750, 0, 450)
		TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 800, 0, 500)}):Play()
	end
end)

print("✅ StoreController Loaded")
