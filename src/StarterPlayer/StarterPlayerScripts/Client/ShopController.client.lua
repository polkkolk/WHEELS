-- ShopController.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── UI SETUP ───────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Dimmed background removed per request

-- Main Panel (Left side of screen)
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 400, 1, 0)
panel.Position = UDim2.new(0, -400, 0, 0) -- starts off-screen
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
panel.BorderSizePixel = 0
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 0) -- Flat against edge
corner.Parent = panel

-- Gradient for slick look
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 24, 38)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 18))
})
grad.Rotation = 90
grad.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 60)
title.Position = UDim2.new(0, 20, 0, 40)
title.BackgroundTransparency = 1
title.Text = "WHEELCHAIR SHOP"
title.TextColor3 = Color3.fromRGB(255, 210, 50)
title.Font = Enum.Font.GothamBlack
title.TextSize = 28
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

-- ─── TAB BAR ────────────────────────────────────────────────────────────────
local TAB_NAMES = {"Base", "Cushions", "Wheels", "Drift VFX", "Decals"}
local TAB_H     = 42
local TAB_Y     = 110   -- sits just below title

local tabBar = Instance.new("Frame")
tabBar.Name              = "TabBar"
tabBar.Size              = UDim2.new(1, -40, 0, TAB_H)
tabBar.Position          = UDim2.new(0, 20, 0, TAB_Y)
tabBar.BackgroundColor3  = Color3.fromRGB(10, 12, 20)
tabBar.BorderSizePixel   = 0
tabBar.Parent            = panel
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,10); c.Parent=tabBar end

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection       = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
tabLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
tabLayout.SortOrder           = Enum.SortOrder.LayoutOrder
tabLayout.Padding             = UDim.new(0, 2)
tabLayout.Parent              = tabBar

-- Content area (one ScrollingFrame per tab, all same position)
local CONTENT_TOP = TAB_Y + TAB_H + 10
local CONTENT_BOT = 80   -- space for close button

local contentFrames = {}
local tabButtons    = {}
local activeTab     = 1

local C_TAB_ACTIVE   = Color3.fromRGB(255, 210, 50)
local C_TAB_INACTIVE = Color3.fromRGB(28, 33, 52)
local C_TEXT_ACTIVE  = Color3.fromRGB(15, 18, 28)
local C_TEXT_INACTIVE= Color3.fromRGB(160, 170, 195)

local _revertPreview   = nil   -- forward-declared; assigned by color system below
local _refreshItems    = nil   -- forward-declared
local _previewEquipped = nil   -- forward-declared

-- Map tab index → category name (only tabs that have color previews)
local TAB_CATEGORIES = {[1] = "Base", [2] = "Cushions", [3] = "Wheels", [4] = "DriftVFX"}

local function selectTab(idx, isOpening)
    if not isOpening then
        local sfx = Instance.new("Sound")
        sfx.SoundId = "rbxassetid://127183292018512"
        sfx.Volume = 0.5
        sfx.Parent = game:GetService("SoundService")
        sfx:Play()
        sfx.Ended:Once(function() sfx:Destroy() end)
    end
    local suppressSmoke = not isOpening
    activeTab = idx
    if _revertPreview then _revertPreview(suppressSmoke) end
    -- _revertPreview now automatically previews ALL equipped colors across all tabs
    for i, btn in ipairs(tabButtons) do
        local isActive = (i == idx)
        TweenService:Create(btn, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            BackgroundColor3 = isActive and C_TAB_ACTIVE or C_TAB_INACTIVE
        }):Play()
        btn:FindFirstChild("Label").TextColor3 = isActive and C_TEXT_ACTIVE or C_TEXT_INACTIVE
        btn:FindFirstChild("Label").Font = isActive and Enum.Font.GothamBlack or Enum.Font.GothamMedium
    end
    for i, cf in ipairs(contentFrames) do
        cf.Visible = (i == idx)
    end
end

for i, name in ipairs(TAB_NAMES) do
    -- Tab button
    local btn = Instance.new("TextButton")
    btn.Name              = "Tab_"..name
    btn.LayoutOrder       = i
    btn.Size              = UDim2.new(1/#TAB_NAMES, -2, 1, -6)
    btn.BackgroundColor3  = C_TAB_INACTIVE
    btn.AutoButtonColor   = false
    btn.BorderSizePixel   = 0
    btn.Text              = ""
    btn.Parent            = tabBar
    do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=btn end

    local lbl = Instance.new("TextLabel")
    lbl.Name                  = "Label"
    lbl.Size                  = UDim2.fromScale(1,1)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = name
    lbl.Font                  = Enum.Font.GothamMedium
    lbl.TextSize              = 13
    lbl.TextColor3            = C_TEXT_INACTIVE
    lbl.Parent                = btn

    btn.MouseButton1Click:Connect(function() selectTab(i) end)

    -- Hover highlight
    btn.MouseEnter:Connect(function()
        if activeTab ~= i then
            btn.BackgroundColor3 = Color3.fromRGB(38, 44, 65)
        end
    end)
    btn.MouseLeave:Connect(function()
        if activeTab ~= i then
            btn.BackgroundColor3 = C_TAB_INACTIVE
        end
    end)

    tabButtons[i] = btn

    -- Content frame for this tab
    local cf = Instance.new("ScrollingFrame")
    cf.Name                 = "Content_"..name
    cf.Size                 = UDim2.new(1, -40, 1, -(CONTENT_TOP + CONTENT_BOT))
    cf.Position             = UDim2.new(0, 20, 0, CONTENT_TOP)
    cf.BackgroundTransparency = 1
    cf.BorderSizePixel      = 0
    cf.ScrollBarThickness   = 4
    cf.ScrollBarImageColor3 = Color3.fromRGB(255, 210, 50)
    cf.Visible              = false
    cf.Parent               = panel

    local gl = Instance.new("UIGridLayout")
    gl.CellSize    = UDim2.new(0, 155, 0, 155)
    gl.CellPadding = UDim2.new(0, 12, 0, 12)
    gl.SortOrder   = Enum.SortOrder.LayoutOrder
    gl.Parent      = cf

    -- Auto-size canvas
    gl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        cf.CanvasSize = UDim2.new(0, 0, 0, gl.AbsoluteContentSize.Y + 12)
    end)

    contentFrames[i] = cf
end

-- Activate first tab on open
selectTab(1)

-- ─── COLOR SHOP SYSTEM ──────────────────────────────────────────────────────
-- shopWheelchair and shopCameraPart are hoisted here so preview functions
-- can reference them before the SYSTEM LOGIC block assigns them below.
local shopWheelchair = nil
local shopCameraPart = nil
local fakeAvatar     = nil
local realPartsHidden = {}

local COLOR_DEFS = {
    {name = "Red",         color = Color3.fromRGB(200, 30, 30)},
    {name = "Orange",      color = Color3.fromRGB(230, 130, 20)},
    {name = "Yellow",      color = Color3.fromRGB(255, 210, 50)},
    {name = "Dark Green",  color = Color3.fromRGB(30, 120, 30)},
    {name = "Light Green", color = Color3.fromRGB(100, 210, 80)},
    {name = "Dark Blue",   color = Color3.fromRGB(30, 50, 180)},
    {name = "Light Blue",  color = Color3.fromRGB(80, 170, 255)},
    {name = "Purple",      color = Color3.fromRGB(130, 50, 180)},
    {name = "Pink",        color = Color3.fromRGB(255, 100, 170)},
    {name = "Brown",       color = Color3.fromRGB(120, 70, 30)},
    {name = "Black",       color = Color3.fromRGB(17, 17, 17)},
	{name = "White",       color = Color3.fromRGB(231, 231, 236)},
}

local DRIFT_DEFS = {
    {name = "Default",        color = Color3.fromRGB(255, 210, 50)},
    {name = "Magic",          color = Color3.fromRGB(255, 50, 200)},
    {name = "Demon",          color = Color3.fromRGB(180, 10, 10)},
    {name = "Bubbles",        color = Color3.fromRGB(130, 210, 255)},
    {name = "Grass",          color = Color3.fromRGB(50, 220, 80)},
}

local ITEM_COST = 100
local DRIFT_COST = 500

local CUSHION_TARGETS = {
    Cushion1 = true, Cushion2 = true, Cushion3 = true, Cushion4 = true,
    Foot_Part1 = true, Foot_Part2 = true, Foot_Part3 = true,
    Handle1 = true, Handle2 = true,
}

local WHEEL_TARGETS = {
    Wheel_Part1 = true, Wheel_Part2 = true,
    Wheel_Part3 = true, Wheel_Part4 = true,
}

-- Remotes (created by ShopService on the server)
local ShopPurchaseFunc = ReplicatedStorage:WaitForChild("ShopPurchaseFunc", 10)
local ShopEquipEvent   = ReplicatedStorage:WaitForChild("ShopEquipEvent", 10)

-- ─── DISPLAY WHEELCHAIR PREVIEW ─────────────────────────────────────────────
local displayOriginals = {}   -- [BasePart] = original Color3

local function storeDisplayOriginals()
    if not shopWheelchair then return end
    if next(displayOriginals) then return end
    for _, desc in ipairs(shopWheelchair:GetDescendants()) do
        if desc:IsA("BasePart") then
            displayOriginals[desc] = desc.Color
        end
    end
end

local function revertDisplayWheelchair()
    for part, origColor in pairs(displayOriginals) do
        if part.Parent then
            part.Color = origColor
        end
    end
end

local Debris = game:GetService("Debris")

local function emitWhiteSmoke(part, count)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/smoke_main.dds" -- Built-in thick cloud texture
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.5),
        NumberSequenceKeypoint.new(0.3, 4.5),
        NumberSequenceKeypoint.new(1, 6)
    })
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.6, 0.6),
        NumberSequenceKeypoint.new(1, 1)
    })
    pe.Color = ColorSequence.new(Color3.new(1, 1, 1)) -- Always white
    pe.Speed = NumberRange.new(6, 12)
    pe.Drag = 5 -- Fast initial pop, then billows slowly
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Lifetime = NumberRange.new(1.0, 1.5)
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-30, 30)
    pe.Rate = 0
    pe.Enabled = false
    pe.Parent = part
    
    pe:Emit(count)
    Debris:AddItem(pe, 2)
end

local function previewOnDisplay(category, color, suppressSmoke)
    if not shopWheelchair then return end
    storeDisplayOriginals()
    
    local targetParts = {}
    
    if category == "Base" then
        for _, desc in ipairs(shopWheelchair:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name == "Metal" then
                table.insert(targetParts, desc)
            end
        end
    elseif category == "Cushions" then
        for _, desc in ipairs(shopWheelchair:GetDescendants()) do
            if desc:IsA("BasePart") and CUSHION_TARGETS[desc.Name] then
                table.insert(targetParts, desc)
            end
        end
    elseif category == "Wheels" then
        for _, desc in ipairs(shopWheelchair:GetDescendants()) do
            if desc:IsA("BasePart") and WHEEL_TARGETS[desc.Name] then
                table.insert(targetParts, desc)
            end
        end
    elseif category == "DriftVFX" then
        -- Static fountain preview for Drift VFX
        local prim = shopWheelchair.PrimaryPart or shopWheelchair:FindFirstChild("Metal")
        if prim then
            for _, child in ipairs(prim:GetChildren()) do
                if child.Name == "PreviewDriftEmitters" then child:Destroy() end
            end
            
            local offsets = {
                Vector3.new(1.5, -1, 1.5),
                Vector3.new(-1.5, -1, 1.5),
                Vector3.new(1.5, -1, -1.5),
                Vector3.new(-1.5, -1, -1.5)
            }
            
            for _, offset in ipairs(offsets) do
                local att = Instance.new("Attachment")
                att.Name = "PreviewDriftEmitters"
                att.Position = offset
                att.Parent = prim
                
                if color == DRIFT_DEFS[1].color then -- Default
                    local sparks = Instance.new("ParticleEmitter")
                    sparks.Texture = "rbxassetid://241594419"
                    sparks.LightEmission = 1
                    sparks.Brightness = 5
                    sparks.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 100)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
                    })
                    sparks.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.8),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                    sparks.Lifetime = NumberRange.new(0.8, 1.3)
                    sparks.Speed = NumberRange.new(15, 30)
                    sparks.SpreadAngle = Vector2.new(15, 15)
                    sparks.EmissionDirection = Enum.NormalId.Top
                    sparks.Rate = 150 -- More particles
                    sparks.Parent = att
                elseif color == DRIFT_DEFS[2].color then -- Magic
                    local tri = Instance.new("ParticleEmitter")
                    tri.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                    tri.LightEmission = 1
                    tri.Brightness = 10
                    tri.Color = ColorSequence.new(Color3.fromRGB(255, 50, 200))
                    tri.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1.2),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                    tri.Lifetime = NumberRange.new(0.8, 1.3)
                    tri.Speed = NumberRange.new(15, 30)
                    tri.SpreadAngle = Vector2.new(20, 20)
                    tri.EmissionDirection = Enum.NormalId.Top
                    tri.Rotation = NumberRange.new(0, 360)
                    tri.RotSpeed = NumberRange.new(-100, 100)
                    tri.Rate = 200 -- More particles
                    tri.Parent = att
                elseif color == DRIFT_DEFS[3].color then -- Demon
                    local tri = Instance.new("ParticleEmitter")
                    tri.Texture = "rbxasset://textures/particles/fire_main.dds"
                    tri.LightEmission = 1
                    tri.Brightness = 5
                    tri.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 30, 30)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 0, 0)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 0, 0))
                    })
                    tri.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.5),
                        NumberSequenceKeypoint.new(0.3, 1.5),
                        NumberSequenceKeypoint.new(0.6, 0.8),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                    tri.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.1),
                        NumberSequenceKeypoint.new(0.8, 0.3),
                        NumberSequenceKeypoint.new(1, 1)
                    })
                    tri.Lifetime = NumberRange.new(0.8, 1.3)
                    tri.Speed = NumberRange.new(15, 30)
                    tri.SpreadAngle = Vector2.new(15, 15)
                    tri.EmissionDirection = Enum.NormalId.Top
                    tri.Rotation = NumberRange.new(0, 360)
                    tri.RotSpeed = NumberRange.new(-60, 60)
                    tri.Rate = 180
                    tri.Parent = att
                elseif color == DRIFT_DEFS[4].color then -- Bubbles
                    local bub = Instance.new("ParticleEmitter")
                    bub.Texture = "rbxassetid://71964547566123" -- Black bg becomes invisible at LightEmission=1
                    bub.LightEmission = 1   -- Additive blend: black pixels = invisible
                    bub.LightInfluence = 0
                    bub.Brightness = 3
                    bub.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 230, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 200, 255))
                    })
                    -- Semi-transparent round bubbles that float up and pop
                    bub.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.2),
                        NumberSequenceKeypoint.new(0.3, 0.7),
                        NumberSequenceKeypoint.new(0.85, 0.9),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                    bub.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.3),
                        NumberSequenceKeypoint.new(0.6, 0.5),
                        NumberSequenceKeypoint.new(1, 1)
                    })
                    bub.Lifetime = NumberRange.new(1.0, 1.8)
                    bub.Speed = NumberRange.new(4, 10)
                    bub.SpreadAngle = Vector2.new(40, 40)
                    bub.EmissionDirection = Enum.NormalId.Top
                    bub.Rotation = NumberRange.new(0, 360)
                    bub.RotSpeed = NumberRange.new(-15, 15) -- Gentle drift
                    bub.Rate = 80
                    bub.Parent = att
                elseif color == DRIFT_DEFS[5].color then -- Grass
                    local tri = Instance.new("ParticleEmitter")
                    tri.Texture = "rbxassetid://77737119859056" -- Original pure black background image
                    tri.LightEmission = 1      -- Additive blending: pure black becomes 100% invisible
                    tri.LightInfluence = 0
                    tri.Brightness = 3         -- Raised brightness, but not blown out
                    tri.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 50)),   -- Pure bright green
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 200, 40)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 120, 20))
                    })
                    tri.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.1),
                        NumberSequenceKeypoint.new(0.2, 0.8),
                        NumberSequenceKeypoint.new(0.6, 0.5),
                        NumberSequenceKeypoint.new(1, 0)
                    })
                    tri.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0),
                        NumberSequenceKeypoint.new(0.8, 0.1),
                        NumberSequenceKeypoint.new(1, 1)
                    })
                    tri.Lifetime = NumberRange.new(0.8, 1.3)
                    tri.Speed = NumberRange.new(15, 30)
                    tri.SpreadAngle = Vector2.new(25, 25)
                    tri.EmissionDirection = Enum.NormalId.Top
                    tri.Rotation = NumberRange.new(0, 360)
                    tri.RotSpeed = NumberRange.new(-120, 120)
                    tri.Rate = 160
                    tri.Parent = att
                end
            end
        end
    end
    
    -- VFX Logic
    if not suppressSmoke then
        local changedParts = {}
        for _, part in ipairs(targetParts) do
            if part.Color ~= color then
                table.insert(changedParts, part)
            end
        end
        
        if #changedParts > 0 then
            if category == "Base" then
                emitWhiteSmoke(changedParts[1], 3)
            else
                -- Randomly pick parts to emit from (4 for Cushions, 3 for Wheels)
                local numToPick = category == "Cushions" and 4 or 3
                numToPick = math.min(numToPick, #changedParts)
                
                local pool = {}
                for _, p in ipairs(changedParts) do table.insert(pool, p) end
                
                for i = 1, numToPick do
                    local randIdx = math.random(1, #pool)
                    emitWhiteSmoke(pool[randIdx], 1)
                    table.remove(pool, randIdx)
                end
            end
        end
    end

    -- Apply Colors
    for _, part in ipairs(targetParts) do
        part.Color = color
    end
end

-- ─── OWNERSHIP HELPERS ──────────────────────────────────────────────────────
local function ownsColor(category, colorName)
    local raw = player:GetAttribute("Shop_Owned_" .. category) or ""
    if raw == "" then return false end
    for name in raw:gmatch("[^,]+") do
        if name == colorName then return true end
    end
    return false
end

local function getEquipped(category)
    return player:GetAttribute("Shop_Equipped_" .. category) or ""
end

-- ─── BUY CONFIRMATION PANEL (right side of screen) ──────────────────────────
local buyPanel = Instance.new("Frame")
buyPanel.Name                  = "BuyPanel"
buyPanel.Size                  = UDim2.new(0, 220, 0, 180)
buyPanel.Position              = UDim2.new(1, -260, 0.5, -90)
buyPanel.AnchorPoint           = Vector2.new(0, 0.5)
buyPanel.BackgroundColor3      = Color3.fromRGB(20, 24, 38)
buyPanel.BackgroundTransparency = 0.05
buyPanel.BorderSizePixel       = 0
buyPanel.Visible               = false
buyPanel.ZIndex                = 20
buyPanel.Parent                = screenGui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = buyPanel end
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255,210,50); s.Thickness = 2; s.Parent = buyPanel end

-- Preview circle on buy panel
local buyCircle = Instance.new("Frame")
buyCircle.Name              = "BuyCircle"
buyCircle.Size              = UDim2.new(0, 70, 0, 70)
buyCircle.Position          = UDim2.new(0.5, 0, 0, 16)
buyCircle.AnchorPoint       = Vector2.new(0.5, 0)
buyCircle.BackgroundColor3  = Color3.new(1,1,1)
buyCircle.BorderSizePixel   = 0
buyCircle.ZIndex             = 21
buyCircle.Parent            = buyPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = buyCircle end

-- Color name on buy panel
local buyNameLabel = Instance.new("TextLabel")
buyNameLabel.Size                  = UDim2.new(1, -20, 0, 22)
buyNameLabel.Position              = UDim2.new(0, 10, 0, 92)
buyNameLabel.BackgroundTransparency = 1
buyNameLabel.Text                  = ""
buyNameLabel.TextColor3            = Color3.fromRGB(230, 230, 240)
buyNameLabel.Font                  = Enum.Font.GothamBold
buyNameLabel.TextSize              = 16
buyNameLabel.ZIndex                = 21
buyNameLabel.Parent                = buyPanel

-- Buy button
local buyBtn = Instance.new("TextButton")
buyBtn.Name              = "BuyBtn"
buyBtn.Size              = UDim2.new(1, -30, 0, 40)
buyBtn.Position          = UDim2.new(0, 15, 1, -55)
buyBtn.AnchorPoint       = Vector2.new(0, 0)
buyBtn.BackgroundColor3  = Color3.fromRGB(50, 180, 50)
buyBtn.Text              = "BUY"
buyBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
buyBtn.Font              = Enum.Font.GothamBlack
buyBtn.TextSize          = 18
buyBtn.AutoButtonColor   = true
buyBtn.ZIndex            = 21
buyBtn.Parent            = buyPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn end

-- State tracking for pending purchase
local pendingBuy = nil   -- {category, colorName, colorValue}

local function showBuyPanel(category, colorName, colorValue)
    pendingBuy = {category = category, colorName = colorName, colorValue = colorValue}
    buyCircle.BackgroundColor3 = colorValue
    buyNameLabel.Text = colorName
    buyBtn.Text = "BUY — $" .. (category == "DriftVFX" and DRIFT_COST or ITEM_COST)
    buyPanel.Visible = true
    -- Pop-in
    buyPanel.Size = UDim2.new(0, 0, 0, 0)
    TweenService:Create(buyPanel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 220, 0, 180)
    }):Play()
end

local function hideBuyPanel()
    pendingBuy = nil
    buyPanel.Visible = false
end

-- Buy button click
buyBtn.MouseButton1Click:Connect(function()
    if not pendingBuy or not ShopPurchaseFunc then return end
    local cat, cName, cVal = pendingBuy.category, pendingBuy.colorName, pendingBuy.colorValue

    local success, msg = ShopPurchaseFunc:InvokeServer(cat, cName)
    if success then
        local sfx = Instance.new("Sound")
        sfx.SoundId = "rbxassetid://72764897006138"
        sfx.Volume = 0.8
        sfx.Parent = game:GetService("SoundService")
        sfx:Play()
        sfx.Ended:Once(function() sfx:Destroy() end)
        
        -- Auto-equip after purchase
        task.wait(0.1)
        ShopEquipEvent:FireServer(cat, cName)
        task.wait(0.15)
        previewOnDisplay(cat, cVal)
        hideBuyPanel()
        if _refreshItems then _refreshItems() end
    else
        buyBtn.Text = msg or "FAILED"
        buyBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        task.delay(1, function()
            buyBtn.Text = "BUY — $" .. (cat == "DriftVFX" and DRIFT_COST or ITEM_COST)
            buyBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        end)
    end
end)

-- ─── ITEM CARDS ─────────────────────────────────────────────────────────────
local allItemFrames = {}

local function refreshAllItems()
    for _, data in ipairs(allItemFrames) do
        data.updateFunc()
    end
end

local function createColorItem(parent, category, colorDef)
    local colorName  = colorDef.name
    local colorValue = colorDef.color

    local item = Instance.new("Frame")
    item.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
    item.BorderSizePixel  = 0
    item.Parent           = parent
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = item end

    local stroke = Instance.new("UIStroke")
    stroke.Color     = Color3.fromRGB(50, 60, 80)
    stroke.Thickness = 2
    stroke.Parent    = item

    -- Color circle
    local circle = Instance.new("Frame")
    circle.Name              = "ColorCircle"
    circle.Size              = UDim2.new(0, 60, 0, 60)
    circle.Position          = UDim2.new(0.5, 0, 0, 20)
    circle.AnchorPoint       = Vector2.new(0.5, 0)
    circle.BackgroundColor3  = colorValue
    circle.BorderSizePixel   = 0
    circle.ZIndex            = 2
    circle.Parent            = item
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = circle end
    do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(200,200,210); s.Thickness = 2; s.Transparency = 0.5; s.Parent = circle end

    -- Color name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size                  = UDim2.new(1, -10, 0, 18)
    nameLabel.Position              = UDim2.new(0, 5, 0, 88)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text                  = colorName
    nameLabel.TextColor3            = Color3.fromRGB(220, 220, 230)
    nameLabel.Font                  = Enum.Font.GothamBold
    nameLabel.TextSize              = 12
    nameLabel.ZIndex                = 2
    nameLabel.Parent                = item

    local cost = (category == "DriftVFX") and DRIFT_COST or ITEM_COST

    -- Status label
    local priceLabel = Instance.new("TextLabel")
    priceLabel.Name                  = "PriceLabel"
    priceLabel.Size                  = UDim2.new(1, -10, 0, 18)
    priceLabel.Position              = UDim2.new(0, 5, 0, 108)
    priceLabel.BackgroundTransparency = 1
    priceLabel.Text                  = "$" .. cost
    priceLabel.TextColor3            = Color3.fromRGB(255, 200, 40)
    priceLabel.Font                  = Enum.Font.GothamBold
    priceLabel.TextSize              = 12
    priceLabel.ZIndex                = 2
    priceLabel.Parent                = item

    -- Lock overlay (gray cover for unowned items)
    local lockOverlay = Instance.new("Frame")
    lockOverlay.Name                  = "LockOverlay"
    lockOverlay.Size                  = UDim2.fromScale(1, 1)
    lockOverlay.BackgroundColor3      = Color3.fromRGB(80, 80, 80)
    lockOverlay.BackgroundTransparency = 0.5
    lockOverlay.BorderSizePixel       = 0
    lockOverlay.ZIndex                = 5
    lockOverlay.Parent                = item
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = lockOverlay end

    -- Clickable button
    local btn = Instance.new("TextButton")
    btn.Name                  = "ItemButton"
    btn.Size                  = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text                  = ""
    btn.ZIndex                = 10
    btn.Parent                = item

    -- State update
    local function updateState()
        local owned    = ownsColor(category, colorName)
        local equipped = getEquipped(category) == colorName

        if equipped then
            stroke.Color     = Color3.fromRGB(80, 255, 80)
            stroke.Thickness = 3
            lockOverlay.Visible = false
            priceLabel.Text       = "EQUIPPED"
            priceLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
        elseif owned then
            stroke.Color     = Color3.fromRGB(50, 60, 80)
            stroke.Thickness = 2
            lockOverlay.Visible = false
            priceLabel.Text       = "OWNED"
            priceLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
        else
            stroke.Color     = Color3.fromRGB(50, 60, 80)
            stroke.Thickness = 2
            lockOverlay.Visible = true
            priceLabel.Text       = "$" .. cost
            priceLabel.TextColor3 = Color3.fromRGB(255, 200, 40)
        end
    end

    -- Per-category selection tracking (for white outline on locked items)
    -- Uses a shared table keyed by category
    local function clearSelection(cat)
        if _G._shopSelected and _G._shopSelected[cat] then
            local prev = _G._shopSelected[cat]
            if prev.stroke and prev.stroke.Parent then
                if not ownsColor(cat, prev.name) then
                    prev.stroke.Color     = Color3.fromRGB(50, 60, 80)
                    prev.stroke.Thickness = 2
                end
            end
        end
    end

    -- Click: preview + equip or show buy panel
    btn.MouseButton1Click:Connect(function()
        local sfx = Instance.new("Sound")
        sfx.SoundId = "rbxassetid://127183292018512"
        sfx.Volume = 0.5
        sfx.Parent = game:GetService("SoundService")
        sfx:Play()
        sfx.Ended:Once(function() sfx:Destroy() end)

        local owned    = ownsColor(category, colorName)
        local equipped = getEquipped(category) == colorName

        -- Always preview on click
        previewOnDisplay(category, colorValue)

        if equipped then
            -- Already equipped, do nothing extra
            hideBuyPanel()
            clearSelection(category)
        elseif owned then
            -- Owned but not equipped → equip immediately
            hideBuyPanel()
            clearSelection(category)
            ShopEquipEvent:FireServer(category, colorName)
            task.wait(0.15)
            refreshAllItems()
        else
            -- Locked → show white selection outline + buy panel
            clearSelection(category)
            if not _G._shopSelected then _G._shopSelected = {} end
            _G._shopSelected[category] = {name = colorName, stroke = stroke}
            stroke.Color     = Color3.fromRGB(255, 255, 255)
            stroke.Thickness = 3
            showBuyPanel(category, colorName, colorValue)
        end
    end)

    updateState()
    table.insert(allItemFrames, { updateFunc = updateState })
end

-- Populate Base tab (index 1)
for _, cd in ipairs(COLOR_DEFS) do
    createColorItem(contentFrames[1], "Base", cd)
end

-- Populate Cushions tab (index 2)
for _, cd in ipairs(COLOR_DEFS) do
    createColorItem(contentFrames[2], "Cushions", cd)
end

-- Populate Wheels tab (index 3)
for _, cd in ipairs(COLOR_DEFS) do
    createColorItem(contentFrames[3], "Wheels", cd)
end

-- Populate Drift VFX tab (index 4)
for _, cd in ipairs(DRIFT_DEFS) do
    createColorItem(contentFrames[4], "DriftVFX", cd)
end

-- Wire up forward-declared callbacks
_revertPreview = function(suppressSmoke)
    revertDisplayWheelchair()
    hideBuyPanel()
    
    -- Cleanup static drift emitter if changing away from the tab or closing
    if shopWheelchair then
        local prim = shopWheelchair.PrimaryPart or shopWheelchair:FindFirstChild("Metal")
        if prim then
            for _, child in ipairs(prim:GetChildren()) do
                if child.Name == "PreviewDriftEmitters" then child:Destroy() end
            end
        end
    end
    
    -- Re-apply all currently equipped colors so the baseline is the fully customized state
    for _, cat in ipairs({"Base", "Cushions", "Wheels"}) do
        local eq = getEquipped(cat)
        if eq ~= "" then
            for _, cd in ipairs(COLOR_DEFS) do
                if cd.name == eq then
                    previewOnDisplay(cat, cd.color, suppressSmoke)
                    break
                end
            end
        end
    end
    
    -- Only preview equipped DriftVFX if we are actively on the Drift VFX tab (index 4)
    if activeTab == 4 then
        local eq = getEquipped("DriftVFX")
        if eq ~= "" then
            for _, cd in ipairs(DRIFT_DEFS) do
                if cd.name == eq then
                    previewOnDisplay("DriftVFX", cd.color, suppressSmoke)
                    break
                end
            end
        end
    end
end
_refreshItems = refreshAllItems
_previewEquipped = nil -- No longer needed since _revertPreview does it all


local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(1, -40, 0, 50)
closeBtn.Position = UDim2.new(0, 20, 1, -70)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "EXIT SHOP"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 20
closeBtn.Parent = panel
local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 8); btnCorner.Parent = closeBtn


-- ─── SYSTEM LOGIC ───────────────────────────────────────────────────────────
local camera = workspace.CurrentCamera
-- (shopWheelchair, shopCameraPart, fakeAvatar, realPartsHidden hoisted above)

-- Hide parts safely and store their original transparency
local function hideModel(model)
	if not model then return end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") or desc:IsA("Decal") then
			if desc.Transparency < 1 then
				table.insert(realPartsHidden, {part = desc, orig = desc.Transparency})
				desc.Transparency = 1
			end
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			if desc.Enabled then
				table.insert(realPartsHidden, {gui = desc, orig = desc.Enabled})
				desc.Enabled = false
			end
			-- Instantly wipe existing particles/trails off the screen!
			pcall(function() desc:Clear() end)
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			if desc.Enabled then
				table.insert(realPartsHidden, {gui = desc, orig = desc.Enabled})
				desc.Enabled = false
			end
		end
	end
end

local function restoreHiddenParts()
	for _, data in ipairs(realPartsHidden) do
		if data.part and data.part.Parent then
			data.part.Transparency = data.orig
		elseif data.gui and data.gui.Parent then
			data.gui.Enabled = data.orig
		elseif data.seat and data.seat.Parent then
			data.seat.HeadsUpDisplay = data.orig
		end
	end
	realPartsHidden = {}
end

-- Enter Shop
local function openShop()
	if player:GetAttribute("InChallenge") then return end
	player:SetAttribute("InShop", true)
	
	-- Prevent interactions/walking
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then 
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.Velocity = Vector3.zero
			hrp.RotVelocity = Vector3.zero
			hrp.Anchored = true 
		end
		
		local realChair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
		if realChair then
			for _, part in ipairs(realChair:GetDescendants()) do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
					part.Velocity = Vector3.zero
					part.RotVelocity = Vector3.zero
				end
			end
		end
		
		-- Force unequip instantly, completely bypassing the GunController camera transition!
		local currentTool = char:FindFirstChild("AssaultRifle")
		if currentTool then
			player:SetAttribute("ForceInstantUnequip", true)
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum:UnequipTools() end
			task.wait(0.1) -- tiny yield for engine to process unequip
			player:SetAttribute("ForceInstantUnequip", nil)
		end
	end
	
	-- Force unlock mouse (AFTER unequip to guarantee it overrides GunController)
	local UserInputService = game:GetService("UserInputService")
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	
	-- Completely disable player controls to prevent WASD from triggering Wheelchair VFX
	pcall(function()
		local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
		local controls = PlayerModule:GetControls()
		controls:Disable()
	end)
	
	-- Hide speed bar (VehicleSeat HeadsUpDisplay)
	local hum = char and char:FindFirstChild("Humanoid")
	if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
		table.insert(realPartsHidden, {seat = hum.SeatPart, orig = hum.SeatPart.HeadsUpDisplay})
		hum.SeatPart.HeadsUpDisplay = false
	end
	
	-- Hide real character and real wheelchair
	hideModel(char)
	local realChair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
	hideModel(realChair)
	
	-- Move Camera
	local currentCam = workspace.CurrentCamera
	if currentCam and shopCameraPart and shopCameraPart.Parent then
		currentCam.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(currentCam, TweenInfo.new(1, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			CFrame = shopCameraPart.CFrame
		}):Play()
	end
	
	-- Show UI
	screenGui.Enabled = true
	TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0)
	}):Play()

	-- Store display wheelchair originals and refresh item states
	if shopWheelchair then storeDisplayOriginals() end
	if _refreshItems then _refreshItems() end
	selectTab(1, true) -- isOpening = true so smoke appears when opening shop
	
	-- Hide core GUI
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end

-- Exit Shop
local function closeShop()
	-- Hide UI
	local pTween = TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = UDim2.new(0, -400, 0, 0)
	})
	pTween:Play()
	
	-- Wait for UI to hide
	pTween.Completed:Wait()
	screenGui.Enabled = false

	-- Revert display wheelchair completely to original colors
	revertDisplayWheelchair()
	hideBuyPanel()
	
	-- Destroy any active drift preview fountain emitters
	if shopWheelchair then
		local prim = shopWheelchair.PrimaryPart or shopWheelchair:FindFirstChild("Metal")
		if prim then
			for _, child in ipairs(prim:GetChildren()) do
				if child.Name == "PreviewDriftEmitters" then child:Destroy() end
			end
		end
	end
	
	-- Restore Real Character and Wheelchair
	player:SetAttribute("InShop", nil)
	restoreHiddenParts()
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Anchored = false end
	end
	
	-- Return Camera
	local realHrp = char and char:FindFirstChild("HumanoidRootPart")
	if realHrp then
		local lookOffset = (camera.CFrame.Position - realHrp.Position).Unit * 15
		TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(realHrp.Position + lookOffset + Vector3.new(0, 5, 0), realHrp.Position)
		}):Play()
		task.wait(0.8)
	end
	
	camera.CameraType = Enum.CameraType.Custom
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	-- Re-disable the Backpack explicitly so the native hotbar doesn't reappear
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	
	pcall(function()
		local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
		local controls = PlayerModule:GetControls()
		controls:Enable()
	end)
end

-- Force close if player dies
local function hardCloseShop()
	screenGui.Enabled = false
	panel.Position = UDim2.new(0, -400, 0, 0)
	
	-- Revert display wheelchair
	if _revertPreview then _revertPreview() end

	-- Restore the transparent parts so the dead body is actually visible!
	restoreHiddenParts()
	
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Anchored = false end
	end
	
	player:SetAttribute("InShop", nil)
	camera.CameraType = Enum.CameraType.Custom
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	
	pcall(function()
		local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
		local controls = PlayerModule:GetControls()
		controls:Enable()
	end)
end

local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		if screenGui.Enabled then
			hardCloseShop()
		end
	end)
end

local ForceCloseShopEvent = ReplicatedStorage:FindFirstChild("ForceCloseShopEvent")
if not ForceCloseShopEvent then
	ForceCloseShopEvent = Instance.new("BindableEvent")
	ForceCloseShopEvent.Name = "ForceCloseShopEvent"
	ForceCloseShopEvent.Parent = ReplicatedStorage
end
ForceCloseShopEvent.Event:Connect(function()
	if screenGui.Enabled then
		hardCloseShop()
	end
end)

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

closeBtn.MouseButton1Click:Connect(closeShop)

-- ─── INITIALIZATION ─────────────────────────────────────────────────────────
-- Look for the setup in the lobby
task.spawn(function()
	-- Look for the display rig and camera part
	while true do
		for _, obj in ipairs(workspace:GetDescendants()) do
			if not shopWheelchair and obj:IsA("Model") and obj.Name:lower():find("shopdisplaywheel") then
				shopWheelchair = obj
			end
			if not shopCameraPart and obj:IsA("BasePart") and obj.Name:lower():find("shopcamer") then
				shopCameraPart = obj
			end
		end
		
		if not shopWheelchair then
			warn("⏳ ShopController: Still looking for the Display Wheelchair...")
		end
		if not shopCameraPart then
			warn("⏳ ShopController: Still looking for the Camera Part...")
		end
		
		if shopWheelchair and shopCameraPart then
			-- Fix Levitation Bug: Make the giant display wheelchair invisible to raycasts
			-- NOTE: CanQuery = false ONLY disables raycasts (like crawling). Collisions (CanCollide) stay ON!
			for _, part in ipairs(shopWheelchair:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanQuery = false
				end
			end
			break 
		end
		task.wait(2)
	end
	
	print("✅ ShopController: Found Shop setup!")
	
	-- Create a dedicated invisible part for the prompt to avoid ANY VehicleSeat interference
	local promptPart = Instance.new("Part")
	promptPart.Name = "ShopPromptAnchor"
	promptPart.Size = Vector3.new(1, 1, 1) -- Tiny footprint
	promptPart.CFrame = shopWheelchair:GetPivot()
	promptPart.Transparency = 1
	promptPart.CanCollide = false
	promptPart.CanTouch = false
	promptPart.CanQuery = false -- Prevents any physics/raycast interference
	promptPart.Anchored = true
	promptPart.Parent = workspace
	
	local UserInputService = game:GetService("UserInputService")
	
	local promptGui = Instance.new("BillboardGui")
	promptGui.Name = "CustomShopPrompt"
	promptGui.Size = UDim2.new(0, 150, 0, 50)
	promptGui.StudsOffset = Vector3.new(0, 2, 0)
	promptGui.AlwaysOnTop = true
	promptGui.Parent = promptPart
	
	local pFrame = Instance.new("Frame")
	pFrame.Size = UDim2.new(0, 0, 0, 0)
	pFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	pFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	pFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	pFrame.BackgroundTransparency = 0.2
	pFrame.ClipsDescendants = true
	pFrame.Parent = promptGui
	
	local pCorner = Instance.new("UICorner"); pCorner.CornerRadius = UDim.new(0, 8); pCorner.Parent = pFrame
	local pStroke = Instance.new("UIStroke"); pStroke.Color = Color3.fromRGB(100, 255, 100); pStroke.Thickness = 2; pStroke.Parent = pFrame
	
	local pLabel = Instance.new("TextLabel")
	pLabel.Size = UDim2.fromScale(1, 1)
	pLabel.BackgroundTransparency = 1
	pLabel.Text = "[E] Shop"
	pLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pLabel.Font = Enum.Font.GothamBold
	pLabel.TextSize = 20
	pLabel.Parent = pFrame
	
	local promptActive = false
	promptGui.Enabled = false
	
	local function hidePrompt()
		if not promptActive then return end
		promptActive = false
		local tween = TweenService:Create(pFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0)
		})
		tween:Play()
		tween.Completed:Connect(function()
			if not promptActive then promptGui.Enabled = false end
		end)
	end

	local function showPrompt()
		if promptActive then return end
		promptActive = true
		promptGui.Enabled = true
		TweenService:Create(pFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
	end

	-- Heartbeat visibility check (replaces ProximityPrompt distance check)
	RunService.Heartbeat:Connect(function()
		if screenGui.Enabled then
			hidePrompt()
			return
		end
		
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - promptPart.Position).Magnitude
			if dist <= 15 then
				showPrompt()
			else
				hidePrompt()
			end
		else
			hidePrompt()
		end
	end)
	
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- If gameProcessed is true, a native ProximityPrompt (like the wheelchair) handled the 'E' key!
		if gameProcessed or screenGui.Enabled then return end
		if input.KeyCode == Enum.KeyCode.E then
			if promptActive then
				-- Enforce 0.5s cooldown after completing a minigame to block double-trigger
				if tick() - (_G.LastMinigameEnd or 0) < 0.5 then return end
				
				local mg = player.PlayerGui:FindFirstChild("WheelchairMountMinigame")
				if mg and mg.Enabled then return end
				
				openShop()
			end
		end
	end)
	
	-- Automatically disable all prompts globally when shop menu opens
	screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		game:GetService("ProximityPromptService").Enabled = not screenGui.Enabled
	end)
end)
