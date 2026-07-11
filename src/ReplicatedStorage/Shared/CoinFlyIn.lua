-- CoinFlyIn.lua (shared module)
-- Creates a "+X$" label at a source position, then spawns coin icons
-- that fly toward the bottom-right HUD coin counter with a stagger.
-- Each coin landing increments the counter and shakes the bar.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CoinFlyIn = {}

-- Creates the gold coin circle (same as the HUD icon)
local function makeCoinIcon(parent, size)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, size, 0, size)
	frame.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(200, 150, 20)
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "$"
	label.TextColor3 = Color3.fromRGB(80, 50, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = math.floor(size * 0.6)
	label.ZIndex = 110 -- Fix for Global ZIndexBehavior
	label.Parent = frame

	return frame
end

-- Shake the coin bar container
local function shakeContainer(container)
	if not container or not container.Parent then return end
	local origPos = container.Position
	-- Quick up-down shake
	TweenService:Create(container, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset - 4)
	}):Play()
	task.delay(0.05, function()
		if not container or not container.Parent then return end
		TweenService:Create(container, TweenInfo.new(0.05, Enum.EasingStyle.Quad), {
			Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset + 3)
		}):Play()
	end)
	task.delay(0.1, function()
		if not container or not container.Parent then return end
		TweenService:Create(container, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = origPos
		}):Play()
	end)
end

--- Play the coin fly-in animation.
-- @param screenGui ScreenGui to parent temporary elements to
-- @param amount number of coins earned
-- @param sourcePos UDim2 position where the "+X$" label appears
-- @param xpAmount optional number of XP earned
function CoinFlyIn.play(screenGui, amount, sourcePos, xpAmount)
	if not amount or amount <= 0 then return end
	
	-- Find the CoinHUD container and label
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local coinHUD = playerGui and playerGui:FindFirstChild("CoinHUD")
	local coinContainer = coinHUD and coinHUD:FindFirstChild("CoinContainer")
	local coinCountLabel = coinContainer and coinContainer:FindFirstChild("CoinCount")
	local shadowLabel = coinCountLabel and coinCountLabel:FindFirstChild("TextLabel") -- shadow
	
	-- Get current displayed value (before the server increment)
	-- Signal the HUD to suppress auto-updates during fly-in
	if coinContainer then
		coinContainer:SetAttribute("FlyInActive", true)
	end

	-- Use leaderstats as the source of truth.
	-- By the time CoinFlyIn.play() is called, the server may have already
	-- replicated the new value. Subtract `amount` to get the pre-award baseline
	-- so the animation counts UP to the correct final total.
	local ls = Players.LocalPlayer:FindFirstChild("leaderstats")
	local coinsStat = ls and ls:FindFirstChild("Money")
	local currentTotal = coinsStat and coinsStat.Value or 0
	local displayedValue = math.max(0, currentTotal - amount)

	if coinCountLabel then
		coinCountLabel.Text = tostring(displayedValue)
		for _, child in ipairs(coinCountLabel:GetChildren()) do
			if child:IsA("TextLabel") then
				child.Text = tostring(displayedValue)
				shadowLabel = child
				break
			end
		end
	end
	
	-- The HUD coin counter target position (bottom-right)
	local targetPos = UDim2.new(1, -130, 1, -60)
	
	-- 1. Show "+X$" label at source
	local plusLabel = Instance.new("TextLabel")
	plusLabel.Size = UDim2.new(0, 300, 0, 60)
	plusLabel.Position = sourcePos or UDim2.new(0.5, 0, 0.55, 0)
	plusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	plusLabel.BackgroundTransparency = 1
	plusLabel.Text = "+" .. tostring(amount) .. "$"
	plusLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
	plusLabel.Font = Enum.Font.GothamBlack
	plusLabel.TextSize = 0
	plusLabel.TextStrokeColor3 = Color3.fromRGB(100, 70, 0)
	plusLabel.TextStrokeTransparency = 0
	plusLabel.ZIndex = 100
	plusLabel.Parent = screenGui
	
	-- Pop in
	TweenService:Create(plusLabel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 48
	}):Play()
    
    local xpLabel
    if xpAmount and xpAmount > 0 then
        xpLabel = Instance.new("TextLabel")
        xpLabel.Size = UDim2.new(0, 300, 0, 40)
        local pos = sourcePos or UDim2.new(0.5, 0, 0.55, 0)
        xpLabel.Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + 40)
        xpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        xpLabel.BackgroundTransparency = 1
        xpLabel.Text = "+" .. tostring(xpAmount) .. " XP"
        xpLabel.TextColor3 = Color3.fromRGB(80, 200, 255)
        xpLabel.Font = Enum.Font.GothamBlack
        xpLabel.TextSize = 0
        xpLabel.TextStrokeColor3 = Color3.fromRGB(0, 50, 100)
        xpLabel.TextStrokeTransparency = 0
        xpLabel.ZIndex = 100
        xpLabel.Parent = screenGui
        
        TweenService:Create(xpLabel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            TextSize = 36
        }):Play()
    end
	
	task.wait(0.8)
	
	-- 2. Spawn coin icons that fly to the HUD
	local coinCount = math.min(amount, 10) -- Cap visual coins at 10
	local coinsPerIcon = math.ceil(amount / coinCount 	)
	local awarded = 0
	
	for i = 1, coinCount do
		task.spawn(function()
			task.wait((i - 1) * 0.1) -- Stagger each coin
			
			local coin = makeCoinIcon(screenGui, 28)
			coin.ZIndex = 100
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			
			-- Scatter start position around the label
			local srcX = (sourcePos or UDim2.new(0.5, 0, 0.55, 0)).X.Scale
			local srcY = (sourcePos or UDim2.new(0.5, 0, 0.55, 0)).Y.Scale
			coin.Position = UDim2.new(srcX, math.random(-40, 40), srcY, math.random(-20, 20))
			
			-- Quick scale-up
			coin.Size = UDim2.new(0, 12, 0, 12)
			local lbl = coin:FindFirstChildOfClass("TextLabel")
			if lbl then lbl.TextSize = 7 end

			TweenService:Create(coin, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 28, 0, 28)
			}):Play()
			if lbl then
				TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					TextSize = 16
				}):Play()
			end
			
			task.wait(0.15)
			
			-- Fly to HUD target
			local flyTween = TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = targetPos,
				Size = UDim2.new(0, 16, 0, 16)
			})
			flyTween:Play()
			if lbl then
				TweenService:Create(lbl, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextSize = 9
				}):Play()
			end
			flyTween.Completed:Wait()
			
			-- COIN LANDED — increment display and shake
			local thisAward = math.min(coinsPerIcon, amount - awarded)
			awarded = awarded + thisAward
			displayedValue = displayedValue + thisAward
			
			if coinCountLabel then
				coinCountLabel.Text = tostring(displayedValue)
				if shadowLabel then
					shadowLabel.Text = tostring(displayedValue)
				end
			end
			
			-- Shake the coin bar
			shakeContainer(coinContainer)
			
			coin:Destroy()
		end)
	end
	
	-- 3. Fade out the "+X$" label
	task.wait(0.3)
	TweenService:Create(plusLabel, TweenInfo.new(0.5), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
    if xpLabel then
        TweenService:Create(xpLabel, TweenInfo.new(0.5), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }):Play()
    end
	task.delay(0.6, function()
		plusLabel:Destroy()
        if xpLabel then xpLabel:Destroy() end
	end)

	-- Clear suppression so normal Changed handler resumes
	task.delay(2, function()
		if coinContainer and coinContainer.Parent then
			coinContainer:SetAttribute("FlyInActive", false)
			-- Sync to the real value in case of any drift
			local ls2 = Players.LocalPlayer:FindFirstChild("leaderstats")
			local stat2 = ls2 and ls2:FindFirstChild("Money")
			if stat2 and coinCountLabel and coinCountLabel.Parent then
				coinCountLabel.Text = tostring(stat2.Value)
				if shadowLabel and shadowLabel.Parent then
					shadowLabel.Text = tostring(stat2.Value)
				end
			end
		end
	end)
end

return CoinFlyIn
