local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local activePrompts = {}

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style == Enum.ProximityPromptStyle.Default then return end

	local promptGui = Instance.new("BillboardGui")
	promptGui.Name = "CustomPrompt"
	promptGui.Size = UDim2.new(0, 150, 0, 50)
	-- Offset it slightly above the seat
	promptGui.StudsOffset = Vector3.new(0, 2, 0)
	promptGui.AlwaysOnTop = true
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 0, 0, 0) -- start small for pop-in animation
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BackgroundTransparency = 0.2
	frame.ClipsDescendants = true
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 255, 100)
	stroke.Thickness = 2
	stroke.Parent = frame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	-- Format: "[E] Sit"
	local keyName = prompt.KeyboardKeyCode.Name
	label.Text = "[" .. keyName .. "] " .. prompt.ActionText
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.ZIndex = 2
	label.Parent = frame
	
	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "FillFrame"
	fillFrame.Size = UDim2.new(0, 0, 1, 0)
	fillFrame.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	fillFrame.BackgroundTransparency = 0.5
	fillFrame.BorderSizePixel = 0
	fillFrame.ZIndex = 1
	fillFrame.Parent = frame
	
	frame.Parent = promptGui
	promptGui.Adornee = prompt.Parent
	promptGui.Parent = prompt.Parent
	
	activePrompts[prompt] = promptGui
	
	-- Pop-in Animation
	TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0)
	}):Play()
end)

local function hideGui(prompt, gui)
	local frame = gui:FindFirstChild("Frame")
	if frame then
		local tween = TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0)
		})
		tween:Play()
		tween.Completed:Connect(function()
			gui:Destroy()
		end)
	else
		gui:Destroy()
	end
	activePrompts[prompt] = nil
end

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if activePrompts[prompt] then
		hideGui(prompt, activePrompts[prompt])
	end
end)

-- Engine Bug Fix: PromptHidden doesn't always fire when the entire Service is disabled!
ProximityPromptService:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not ProximityPromptService.Enabled then
		for prompt, gui in pairs(activePrompts) do
			hideGui(prompt, gui)
		end
	end
end)

local fillTweens = {}

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
	if player ~= game.Players.LocalPlayer then return end
	local gui = activePrompts[prompt]
	if gui then
		local fill = gui:FindFirstChild("FillFrame", true)
		if fill then
			local tw = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
				Size = UDim2.new(1, 0, 1, 0)
			})
			tw:Play()
			fillTweens[prompt] = tw
		end
	end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
	if player ~= game.Players.LocalPlayer then return end
	if fillTweens[prompt] then
		fillTweens[prompt]:Cancel()
		fillTweens[prompt] = nil
	end
	local gui = activePrompts[prompt]
	if gui then
		local fill = gui:FindFirstChild("FillFrame", true)
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.2), {
				Size = UDim2.new(0, 0, 1, 0)
			}):Play()
		end
	end
end)
