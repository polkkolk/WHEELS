-- HotbarController.client.lua
-- Custom weapon hotbar inspired by INK GAME's clean, dark, glowing UI style.
-- Replaces the default Roblox backpack with a sleek bottom-center hotbar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════
local SLOT_SIZE = 38
local SLOT_PADDING = 6
local SLOT_CORNER_RADIUS = 6
local HOTBAR_BOTTOM_OFFSET = 4

local WEAPONS = {
    { name = "AssaultRifle", displayName = "M4A1",   key = "1", keyCode = Enum.KeyCode.One },
    { name = "Pistol",       displayName = "PISTOL", key = "2", keyCode = Enum.KeyCode.Two },
}

-- Colors
local C_SLOT_BG         = Color3.fromRGB(12, 14, 22)
local C_SLOT_BG_HOVER   = Color3.fromRGB(22, 26, 40)
local C_SLOT_BORDER     = Color3.fromRGB(40, 45, 65)
local C_SLOT_SELECTED   = Color3.fromRGB(255, 210, 50)   -- Gold highlight when equipped
local C_SLOT_LOCKED     = Color3.fromRGB(255, 60, 60)    -- Red when crawling-blocked
local C_KEY_TEXT         = Color3.fromRGB(140, 150, 175)
local C_KEY_TEXT_ACTIVE  = Color3.fromRGB(255, 210, 50)
local C_NAME_TEXT        = Color3.fromRGB(200, 205, 220)
local C_NAME_TEXT_ACTIVE = Color3.fromRGB(255, 255, 255)

-- ═══════════════════════════════════════════
-- BUILD SCREEN GUI
-- ═══════════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name = "CustomHotbar"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 5
sg.Parent = playerGui

-- Container frame (bottom center)
local totalWidth = (#WEAPONS * SLOT_SIZE) + ((#WEAPONS - 1) * SLOT_PADDING)
local container = Instance.new("Frame")
container.Name = "HotbarContainer"
container.Size = UDim2.new(0, totalWidth + 12, 0, SLOT_SIZE + 12)
container.Position = UDim2.new(0.5, 0, 1, -HOTBAR_BOTTOM_OFFSET)
container.AnchorPoint = Vector2.new(0.5, 1)
container.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = sg

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 16)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(35, 40, 60)
containerStroke.Thickness = 1.5
containerStroke.Transparency = 0.3
containerStroke.Parent = container

-- Subtle inner gradient
local containerGrad = Instance.new("UIGradient")
containerGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 35)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 10, 18)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 22, 35)),
})
containerGrad.Rotation = 0
containerGrad.Parent = container

-- ═══════════════════════════════════════════
-- BUILD SLOTS
-- ═══════════════════════════════════════════
local slots = {}

for i, weaponInfo in ipairs(WEAPONS) do
    local slotFrame = Instance.new("Frame")
    slotFrame.Name = "Slot_" .. weaponInfo.name
    slotFrame.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
    slotFrame.Position = UDim2.new(0, 6 + ((i - 1) * (SLOT_SIZE + SLOT_PADDING)), 0, 6)
    slotFrame.BackgroundColor3 = C_SLOT_BG
    slotFrame.BorderSizePixel = 0
    slotFrame.Parent = container

    local slotCorner = Instance.new("UICorner")
    slotCorner.CornerRadius = UDim.new(0, SLOT_CORNER_RADIUS)
    slotCorner.Parent = slotFrame

    local slotStroke = Instance.new("UIStroke")
    slotStroke.Name = "SelectionStroke"
    slotStroke.Color = C_SLOT_BORDER
    slotStroke.Thickness = 2
    slotStroke.Parent = slotFrame

    -- Inner glow (subtle gradient)
    local innerGlow = Instance.new("UIGradient")
    innerGlow.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 35, 55)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 22)),
    })
    innerGlow.Rotation = 90
    innerGlow.Parent = slotFrame

    -- Viewport for 3D weapon preview
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "WeaponPreview"
    viewport.Size = UDim2.new(1, -4, 1, -12)
    viewport.Position = UDim2.new(0, 2, 0, 0)
    viewport.BackgroundTransparency = 1
    viewport.Parent = slotFrame

    -- Weapon name label (bottom of slot)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "WeaponName"
    nameLabel.Size = UDim2.new(1, 0, 0, 10)
    nameLabel.Position = UDim2.new(0, 0, 1, -10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = weaponInfo.displayName
    nameLabel.TextColor3 = C_NAME_TEXT
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 8
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = slotFrame

    -- Keybind badge (top-left corner)
    local keyBadge = Instance.new("Frame")
    keyBadge.Name = "KeyBadge"
    keyBadge.Size = UDim2.new(0, 14, 0, 14)
    keyBadge.Position = UDim2.new(0, 2, 0, 2)
    keyBadge.BackgroundColor3 = Color3.fromRGB(25, 28, 42)
    keyBadge.BorderSizePixel = 0
    keyBadge.ZIndex = 3
    keyBadge.Parent = slotFrame

    local keyBadgeCorner = Instance.new("UICorner")
    keyBadgeCorner.CornerRadius = UDim.new(0, 3)
    keyBadgeCorner.Parent = keyBadge

    local keyBadgeStroke = Instance.new("UIStroke")
    keyBadgeStroke.Color = Color3.fromRGB(60, 65, 85)
    keyBadgeStroke.Thickness = 1
    keyBadgeStroke.Parent = keyBadge

    local keyLabel = Instance.new("TextLabel")
    keyLabel.Name = "KeyLabel"
    keyLabel.Size = UDim2.fromScale(1, 1)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Text = weaponInfo.key
    keyLabel.TextColor3 = C_KEY_TEXT
    keyLabel.Font = Enum.Font.GothamBlack
    keyLabel.TextSize = 10
    keyLabel.ZIndex = 4
    keyLabel.Parent = keyBadge

    -- Clickable button overlay
    local clickBtn = Instance.new("TextButton")
    clickBtn.Name = "ClickButton"
    clickBtn.Size = UDim2.fromScale(1, 1)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.ZIndex = 10
    clickBtn.Parent = slotFrame

    -- Hover effects
    clickBtn.MouseEnter:Connect(function()
        if not slots[i].selected then
            TweenService:Create(slotFrame, TweenInfo.new(0.15), {
                BackgroundColor3 = C_SLOT_BG_HOVER
            }):Play()
        end
    end)

    clickBtn.MouseLeave:Connect(function()
        if not slots[i].selected then
            TweenService:Create(slotFrame, TweenInfo.new(0.15), {
                BackgroundColor3 = C_SLOT_BG
            }):Play()
        end
    end)

    -- Store slot data
    slots[i] = {
        frame = slotFrame,
        stroke = slotStroke,
        viewport = viewport,
        nameLabel = nameLabel,
        keyLabel = keyLabel,
        keyBadge = keyBadge,
        clickBtn = clickBtn,
        weaponInfo = weaponInfo,
        selected = false,
    }
end

-- ═══════════════════════════════════════════
-- 3D WEAPON PREVIEW (ViewportFrame)
-- ═══════════════════════════════════════════
local function populateViewport(slot)
    -- Clear old contents
    for _, child in ipairs(slot.viewport:GetChildren()) do
        child:Destroy()
    end

    local weaponName = slot.weaponInfo.name
    local sourceTool = game:GetService("StarterPack"):FindFirstChild(weaponName)
        or (player.Backpack and player.Backpack:FindFirstChild(weaponName))
        or (player.Character and player.Character:FindFirstChild(weaponName))

    if not sourceTool then return end

    -- Clone visible parts into the viewport
    local vpModel = Instance.new("Model")
    vpModel.Name = "PreviewModel"

    local handlePart = nil
    for _, part in ipairs(sourceTool:GetDescendants()) do
        if part:IsA("BasePart") and part.Transparency < 1 then
            local clone = part:Clone()
            -- Remove scripts, constraints, etc.
            for _, c in ipairs(clone:GetDescendants()) do
                if c:IsA("Script") or c:IsA("LocalScript") or c:IsA("Constraint")
                    or c:IsA("ParticleEmitter") or c:IsA("PointLight") or c:IsA("Sound") then
                    c:Destroy()
                end
            end
            clone.Anchored = true
            clone.CanCollide = false
            clone.Parent = vpModel
            if part.Name == "Handle" or (not handlePart) then
                handlePart = clone
            end
        end
    end

    if not handlePart then vpModel:Destroy() return end

    vpModel.PrimaryPart = handlePart
    vpModel.Parent = slot.viewport

    -- Camera for viewport
    local vpCam = Instance.new("Camera")
    vpCam.FieldOfView = 50

    -- Position the camera to frame the weapon nicely
    local cf = handlePart.CFrame
    local modelSize = vpModel:GetExtentsSize()
    local maxDim = math.max(modelSize.X, modelSize.Y, modelSize.Z)
    local dist = maxDim * 1.4

    vpCam.CFrame = cf * CFrame.new(0, 0.2, dist) * CFrame.Angles(0, 0, 0)
    vpCam.Parent = slot.viewport
    slot.viewport.CurrentCamera = vpCam
end

-- Populate viewports after tools load
task.spawn(function()
    task.wait(2)
    for _, slot in ipairs(slots) do
        populateViewport(slot)
    end
end)

-- ═══════════════════════════════════════════
-- SELECTION STATE
-- ═══════════════════════════════════════════
local function updateSlotVisuals()
    local char = player.Character
    local currentTool = char and char:FindFirstChildOfClass("Tool")
    local equippedName = currentTool and currentTool.Name or ""

    local isCrawling = char and char.PrimaryPart and char.PrimaryPart:FindFirstChild("CrawlMover")

    for i, slot in ipairs(slots) do
        local isEquipped = (equippedName == slot.weaponInfo.name)
        local isBlocked = isCrawling and slot.weaponInfo.name ~= "Pistol"
        slot.selected = isEquipped

        local targetStrokeColor, targetBG, targetKeyColor, targetNameColor

        if isEquipped then
            targetStrokeColor = C_SLOT_SELECTED
            targetBG = Color3.fromRGB(30, 28, 10)
            targetKeyColor = C_KEY_TEXT_ACTIVE
            targetNameColor = C_NAME_TEXT_ACTIVE
        elseif isBlocked then
            targetStrokeColor = C_SLOT_LOCKED
            targetBG = Color3.fromRGB(25, 12, 12)
            targetKeyColor = Color3.fromRGB(180, 60, 60)
            targetNameColor = Color3.fromRGB(180, 100, 100)
        else
            targetStrokeColor = C_SLOT_BORDER
            targetBG = C_SLOT_BG
            targetKeyColor = C_KEY_TEXT
            targetNameColor = C_NAME_TEXT
        end

        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(slot.stroke, tweenInfo, { Color = targetStrokeColor }):Play()
        TweenService:Create(slot.frame, tweenInfo, { BackgroundColor3 = targetBG }):Play()

        -- Stroke thickness: thicker when selected
        slot.stroke.Thickness = isEquipped and 2.5 or 2

        -- Update text colors (instant, no tween needed)
        slot.keyLabel.TextColor3 = targetKeyColor
        slot.nameLabel.TextColor3 = targetNameColor

        -- Viewport transparency for blocked weapons
        slot.viewport.ImageTransparency = isBlocked and 0.6 or 0
    end
end

-- ═══════════════════════════════════════════
-- CLICK HANDLERS (mirror the keybind behavior in GunController)
-- ═══════════════════════════════════════════
-- GunController already handles the key presses, but we also want clicks on the hotbar
-- to trigger weapon switches. We simulate the key press by using the existing equipWeapon flow.
-- Since equipWeapon is local to GunController, we use a BindableEvent to communicate.

local HotbarEquipEvent = ReplicatedStorage:FindFirstChild("HotbarEquipEvent")
if not HotbarEquipEvent then
    HotbarEquipEvent = Instance.new("BindableEvent")
    HotbarEquipEvent.Name = "HotbarEquipEvent"
    HotbarEquipEvent.Parent = ReplicatedStorage
end

for i, slot in ipairs(slots) do
    slot.clickBtn.MouseButton1Click:Connect(function()
        HotbarEquipEvent:Fire(slot.weaponInfo.name)
    end)
end

-- ═══════════════════════════════════════════
-- VISIBILITY: Hide hotbar in shop / during duels
-- ═══════════════════════════════════════════
local function updateHotbarVisibility()
    local inShop = player:GetAttribute("InShop")
    container.Visible = not inShop
end

player:GetAttributeChangedSignal("InShop"):Connect(updateHotbarVisibility)
updateHotbarVisibility()

-- ═══════════════════════════════════════════
-- UPDATE LOOP (lightweight, just checks equipped state)
-- ═══════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    updateSlotVisuals()
end)

-- Re-populate viewports when character respawns (tools re-enter StarterPack/Backpack)
player.CharacterAdded:Connect(function()
    task.wait(2)
    for _, slot in ipairs(slots) do
        populateViewport(slot)
    end
end)

print("✅ HotbarController Loaded — Custom weapon hotbar active")
