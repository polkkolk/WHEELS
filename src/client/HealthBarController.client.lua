-- HealthBarController.client.lua
-- Premium health bar with ghost-lag bar, hit flash, layered gradients, wind streaks.

local Players         = game:GetService("Players")
local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Disable Roblox's built-in low-health vignette and default health bar
task.spawn(function()
    -- Wait for the core gui to be ready
    while not pcall(function()
        game:GetService("StarterGui"):SetCore("ResetButtonCallback", true)
    end) do task.wait() end
    pcall(function()
        game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
    end)
end)

-- ─── DEBUG KEY (J = deal 10 damage) ─────────────────────────────────────────
local debugEvt = ReplicatedStorage:WaitForChild("DebugDamageEvent", 10)
if debugEvt then
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.J then
            debugEvt:FireServer()
        end
    end)
end

-- ─── COLORS ──────────────────────────────────────────────────────────────────
local function lerpC(a, b, t)
    return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
end

local C_GREEN    = Color3.fromRGB(45,  235, 85)
local C_ORANGE   = Color3.fromRGB(255, 145,  0)
local C_RED      = Color3.fromRGB(210,  25, 25)

local function barColor(pct)
    if pct >= 0.5 then return lerpC(C_ORANGE, C_GREEN,  (pct-0.5)/0.5)
    else               return lerpC(C_RED,    C_ORANGE,  pct/0.5)
    end
end

-- Slightly darker shade of the main color for the gradient bottom
local function darkShade(c, amt)
    return Color3.new(math.max(0,c.R-amt), math.max(0,c.G-amt), math.max(0,c.B-amt))
end

-- ─── LAYOUT CONSTANTS ────────────────────────────────────────────────────────
local W, H   = 480, 32
local CORNER = UDim.new(0, H/2)
local PAD    = -56    -- Y offset from screen bottom

-- ─── SCREEN GUI ──────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "HealthBarGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.DisplayOrder   = 8
sg.Parent         = playerGui

-- ─── DAMAGE HIT FX GUI ───────────────────────────────────────────────────────
-- Separate fullscreen gui so it sits above everything, including the health bar
local fxGui = Instance.new("ScreenGui")
fxGui.Name           = "DamageHitFX"
fxGui.ResetOnSpawn   = false
fxGui.IgnoreGuiInset = true
fxGui.DisplayOrder   = 20
fxGui.Parent         = playerGui

-- 4 thin red edge frames (top, bottom, left, right) — vignette flash on hit
local function makeEdge(anchor, pos, size)
    local f = Instance.new("Frame")
    f.AnchorPoint       = anchor
    f.Position          = pos
    f.Size              = size
    f.BackgroundColor3  = Color3.fromRGB(200, 0, 0)
    f.BackgroundTransparency = 1   -- invisible at rest
    f.BorderSizePixel   = 0
    f.ZIndex            = 20
    f.Parent            = fxGui
    return f
end

local edgeTop    = makeEdge(Vector2.new(0,0), UDim2.new(0,0,0,0),   UDim2.new(1,0,0,60))
local edgeBot    = makeEdge(Vector2.new(0,1), UDim2.new(0,0,1,0),   UDim2.new(1,0,0,60))
local edgeLeft   = makeEdge(Vector2.new(0,0), UDim2.new(0,0,0,0),   UDim2.new(0,60,1,0))
local edgeRight  = makeEdge(Vector2.new(1,0), UDim2.new(1,0,0,0),   UDim2.new(0,60,1,0))
local edges = {edgeTop, edgeBot, edgeLeft, edgeRight}

-- DamageHitFX is excluded from UIScaleController (the scale=1 dimension must
-- stay full-screen). Instead we scale the pixel thickness proportionally.
local function updateEdgeThickness()
    local vp = workspace.CurrentCamera.ViewportSize
    local px = math.clamp(math.round(60 * vp.Y / 1080), 20, 120)
    edgeTop.Size   = UDim2.new(1, 0, 0, px)
    edgeBot.Size   = UDim2.new(1, 0, 0, px)
    edgeLeft.Size  = UDim2.new(0, px, 1, 0)
    edgeRight.Size = UDim2.new(0, px, 1, 0)
end
updateEdgeThickness()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateEdgeThickness)

-- Fade edges through a UIGradient so color bleeds inward and is transparent in centre
local function addEdgeGrad(frame, rotation)
    local g = Instance.new("UIGradient")
    g.Rotation = rotation
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),    -- opaque at edge
        NumberSequenceKeypoint.new(1, 1),    -- fully transparent inward
    })
    g.Parent = frame
end
addEdgeGrad(edgeTop,   180)
addEdgeGrad(edgeBot,   0)
addEdgeGrad(edgeLeft,  90)
addEdgeGrad(edgeRight, 270)

local vignetteTweens = {}
local function triggerVignette()
    -- Cancel any running fade
    for _, tw in ipairs(vignetteTweens) do tw:Cancel() end
    vignetteTweens = {}
    -- Snap edges to very faint red
    for _, e in ipairs(edges) do e.BackgroundTransparency = 0.82 end
    -- Fade back to invisible over 0.45s
    local fadeInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, e in ipairs(edges) do
        local tw = TweenService:Create(e, fadeInfo, { BackgroundTransparency = 1 })
        tw:Play()
        table.insert(vignetteTweens, tw)
    end
end

-- ─── SCREEN SHAKE ────────────────────────────────────────────────────────────
-- Directly jitters the camera CFrame at a priority AFTER all other camera
-- controllers (GunController binds at Camera+1, we bind at Camera+10).
-- This shakes the actual rendered image, not the character.
local shakeDecay = 0
local SHAKE_INTENSITY = 1.5   -- studs of max offset
local SHAKE_DURATION  = 1     -- decay rate (1 = ~1s shake duration)

RunService:BindToRenderStep("DamageScreenShake", Enum.RenderPriority.Camera.Value + 10, function(dt)
    if shakeDecay <= 0 then return end
    shakeDecay = math.max(0, shakeDecay - dt * SHAKE_DURATION)
    local r = shakeDecay * SHAKE_INTENSITY
    local cam = workspace.CurrentCamera
    cam.CFrame = cam.CFrame * CFrame.new(
        (math.random() - 0.5) * 2 * r,
        (math.random() - 0.5) * 2 * r,
        0
    )
end)

local function triggerShake(intensity)
    shakeDecay = math.max(shakeDecay, intensity)
end

-- Root anchor
local root = Instance.new("Frame")
root.Name               = "Root"
root.AnchorPoint        = Vector2.new(0.5, 1)
root.Position           = UDim2.new(0.5, 0, 1, PAD)
root.Size               = UDim2.new(0, W+40, 0, H+40)
root.BackgroundTransparency = 1
root.Parent             = sg

-- Outer diffuse glow (very soft, just 12px oversized, low opacity)
local glowFrame = Instance.new("Frame")
glowFrame.Name              = "Glow"
glowFrame.AnchorPoint       = Vector2.new(0.5, 0.5)
glowFrame.Position          = UDim2.new(0.5, 0, 0.5, 0)
glowFrame.Size              = UDim2.new(0, W+22, 0, H+22)
glowFrame.BackgroundColor3  = C_GREEN
glowFrame.BackgroundTransparency = 0.74
glowFrame.BorderSizePixel   = 0
glowFrame.ZIndex            = 1
glowFrame.Parent            = root
do local c=Instance.new("UICorner"); c.CornerRadius=CORNER; c.Parent=glowFrame end

-- Track (dark recessed background)
local track = Instance.new("Frame")
track.Name              = "Track"
track.AnchorPoint       = Vector2.new(0.5, 0.5)
track.Position          = UDim2.new(0.5, 0, 0.5, 0)
track.Size              = UDim2.new(0, W, 0, H)
track.BackgroundColor3  = Color3.fromRGB(14, 14, 18)
track.BorderSizePixel   = 0
track.ClipsDescendants  = false   -- let ghost bar sit inside without clipping issues
track.ZIndex            = 2
track.Parent            = root
do local c=Instance.new("UICorner"); c.CornerRadius=CORNER; c.Parent=track end

-- Track inner border
do
    local s=Instance.new("UIStroke")
    s.Color=Color3.fromRGB(50,50,60); s.Thickness=1.2
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=track
end

-- GHOST / lag bar (shows old health, slowly catches up — the hallmark of a premium HP bar)
local ghost = Instance.new("Frame")
ghost.Name              = "Ghost"
ghost.AnchorPoint       = Vector2.new(0, 0.5)
ghost.Position          = UDim2.new(0, 0, 0.5, 0)
ghost.Size              = UDim2.new(1, 0, 1, 0)
ghost.BackgroundColor3  = Color3.fromRGB(255, 210, 60)  -- warm amber "damage lag" color
ghost.BackgroundTransparency = 0.45
ghost.BorderSizePixel   = 0
ghost.ClipsDescendants  = true
ghost.ZIndex            = 3
ghost.Parent            = track
do local c=Instance.new("UICorner"); c.CornerRadius=CORNER; c.Parent=ghost end

-- Dark right-edge taper on ghost so it blends into the dark track
do
    local taper = Instance.new("UIGradient")
    taper.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
        ColorSequenceKeypoint.new(0.80, Color3.new(1,1,1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.1,0.1,0.1)),
    })
    taper.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.85, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    taper.Parent = ghost
end

-- MAIN fill (clips streaks; sits on top of ghost)
local fill = Instance.new("Frame")
fill.Name              = "Fill"
fill.AnchorPoint       = Vector2.new(0, 0.5)
fill.Position          = UDim2.new(0, 0, 0.5, 0)
fill.Size              = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3  = C_GREEN
fill.BorderSizePixel   = 0
fill.ClipsDescendants  = true
fill.ZIndex            = 4
fill.Parent            = track
do local c=Instance.new("UICorner"); c.CornerRadius=CORNER; c.Parent=fill end

-- Fill: vertical gradient (lighter top, slightly darker bottom for 3-D roundness)
local fillGrad = Instance.new("UIGradient")
fillGrad.Rotation = 90
fillGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),       -- fully opaque at top-center
    NumberSequenceKeypoint.new(0.45, 0.05),
    NumberSequenceKeypoint.new(1, 0.22),    -- slightly transparent at bottom
})
fillGrad.Parent = fill

-- Crisp 2px specular highlight at very top edge of fill
local topLine = Instance.new("Frame")
topLine.Size               = UDim2.new(0.90, 0, 0, 2)
topLine.AnchorPoint        = Vector2.new(0.5, 0)
topLine.Position           = UDim2.new(0.5, 0, 0, 2)
topLine.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
topLine.BackgroundTransparency = 0.35
topLine.BorderSizePixel    = 0
topLine.ZIndex             = 6
topLine.Parent             = fill
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=topLine end

-- Inner bottom shadow strip (sells the "channel" depth)
local botShadow = Instance.new("Frame")
botShadow.AnchorPoint       = Vector2.new(0.5, 1)
botShadow.Position          = UDim2.new(0.5, 0, 1, -1)
botShadow.Size              = UDim2.new(1, 0, 0, 4)
botShadow.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
botShadow.BackgroundTransparency = 0.55
botShadow.BorderSizePixel   = 0
botShadow.ZIndex            = 6
botShadow.Parent            = fill

-- ─── WIND / LIGHT STREAKS ────────────────────────────────────────────────────
-- Thin white bars at varied Y, height, width, speed. They drift left→right
-- continuously, clipped inside fill so they never bleed into the empty track.
-- These are CLEARLY visible white lines, not subtle bands.
local SDEFS = {
--  yScale  hPx  wScale  alpha  speed(sc/s)  startX
    {0.16,   3,   0.14,   0.25,  0.060,  -0.20},
    {0.40,   2,   0.08,   0.22,  0.040,   0.30},
    {0.60,   3,   0.18,   0.28,  0.078,  -0.55},
    {0.78,   2,   0.10,   0.20,  0.033,   0.65},
    {0.26,   1,   0.06,   0.18,  0.091,   0.85},
    {0.88,   2,   0.22,   0.26,  0.052,  -0.05},
    {0.50,   1,   0.07,   0.20,  0.067,   0.50},
    {0.70,   3,   0.12,   0.24,  0.045,  -0.35},
}

local streaks = {}
for i, d in ipairs(SDEFS) do
    local s = Instance.new("Frame")
    s.Name               = "SK"..i
    s.AnchorPoint        = Vector2.new(0, 0.5)
    s.Position           = UDim2.new(d[6], 0, d[1], 0)
    s.Size               = UDim2.new(d[3], 0, 0, d[2])
    s.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
    s.BackgroundTransparency = d[4]
    s.BorderSizePixel    = 0
    s.ZIndex             = 7
    s.Parent             = fill
    do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=s end
    streaks[i] = {f=s, x=d[6], spd=d[5], w=d[3], ba=d[4], ph=i*1.1}
end

-- Track current fill pct for streak culling
local currentPct = 1

RunService.RenderStepped:Connect(function(dt)
    local t = tick()
    -- How many streaks should be visible at this fill level?
    -- Scale 0→1 maps to 0→8, minimum 1 when bar has any health
    local maxVisible = currentPct > 0 and math.ceil(currentPct * #streaks) or 0

    for i, sk in ipairs(streaks) do
        if i > maxVisible then
            -- Hide this streak entirely - too many for the current bar size
            sk.f.BackgroundTransparency = 1
        else
            sk.x = sk.x + sk.spd * dt
            if sk.x > 1.04 then sk.x = -sk.w - 0.04 end
            local a = math.clamp(sk.ba + math.sin(t*0.6+sk.ph)*0.05, 0, 1)
            sk.f.Position = UDim2.new(sk.x, 0, sk.f.Position.Y.Scale, 0)
            sk.f.BackgroundTransparency = a
        end
    end
end)

-- ─── HP LABEL ────────────────────────────────────────────────────────────────
-- Centered on the TRACK (stays readable even at 1 HP)
local hpLabel = Instance.new("TextLabel")
hpLabel.Name               = "HPLabel"
hpLabel.AnchorPoint        = Vector2.new(0.5, 0.5)
hpLabel.Position           = UDim2.new(0.5, 0, 0.5, 0)
hpLabel.Size               = UDim2.new(1, 0, 1, 0)
hpLabel.BackgroundTransparency = 1
hpLabel.Font               = Enum.Font.GothamBlack
hpLabel.TextSize           = 14
hpLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
hpLabel.TextStrokeTransparency = 0.3
hpLabel.TextStrokeColor3   = Color3.fromRGB(0, 0, 0)
hpLabel.ZIndex             = 12
hpLabel.Parent             = track

-- ─── DAMAGE FLASH + HIT FX ──────────────────────────────────────────────────
-- Bar fill flashes white; edge vignette briefly appears; camera shakes very slightly
local function flashHit()
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    triggerVignette()          -- VERY subtle red screen edge
    triggerShake(0.18)         -- Noticeable but not excessive shake (0.18 studs max)
end

-- ─── GHOST BAR LOGIC ─────────────────────────────────────────────────────────
local ghostTween   = nil
local GHOST_DELAY  = 0.55   -- seconds before ghost starts catching up
local GHOST_TIME   = 0.90   -- seconds ghost takes to drain

-- ─── MAIN UPDATE ─────────────────────────────────────────────────────────────
local tFill, tColor, tGlow

local function updateHealth(hp, maxHp, prevPct)
    local pct    = math.clamp(hp / maxHp, 0, 1)
    local col    = barColor(pct)
    local isDmg  = prevPct and pct < prevPct

    -- Cancel running tweens
    if tFill  then tFill:Cancel()  end
    if tColor then tColor:Cancel() end
    if tGlow  then tGlow:Cancel()  end

    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    -- Ghost bar: only moves when taking damage
    if isDmg then
        -- Ghost stays at OLD width while fill snaps forward
        -- then slowly drains after a delay
        if ghostTween then ghostTween:Cancel() end
        task.delay(GHOST_DELAY, function()
            ghostTween = TweenService:Create(ghost,
                TweenInfo.new(GHOST_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = UDim2.new(pct, 0, 1, 0) }
            )
            ghostTween:Play()
        end)

        flashHit()
    else
        -- Healing: ghost bar also jumps to match instantly
        if ghostTween then ghostTween:Cancel() end
        ghost.Size = UDim2.new(pct, 0, 1, 0)
    end

    -- Main fill tween
    tFill  = TweenService:Create(fill, info, { Size = UDim2.new(pct, 0, 1, 0) })
    tColor = TweenService:Create(fill, info, { BackgroundColor3 = col })
    tGlow  = TweenService:Create(glowFrame, info, { BackgroundColor3 = col })
    tFill:Play(); tColor:Play(); tGlow:Play()

    hpLabel.Text = tostring(math.ceil(hp))
    currentPct = pct

    return pct
end

-- ─── CHARACTER HOOK ──────────────────────────────────────────────────────────
local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    local lastPct = 1

    -- Sync on spawn
    lastPct = updateHealth(hum.Health, hum.MaxHealth, nil)

    hum.HealthChanged:Connect(function(hp)
        local prev = lastPct
        lastPct = updateHealth(hp, hum.MaxHealth, prev)
    end)

    hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        lastPct = updateHealth(hum.Health, hum.MaxHealth, nil)
    end)
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- ─── SHOP VISIBILITY ─────────────────────────────────────────────────────────
-- Hide both the health bar and the damage FX overlay while the shop is open.
local function applyShopVisibility(inShop)
    sg.Enabled    = not inShop
    fxGui.Enabled = not inShop
end

player:GetAttributeChangedSignal("InShop"):Connect(function()
    applyShopVisibility(player:GetAttribute("InShop") == true)
end)

-- Apply immediately on load in case player somehow starts in shop state
applyShopVisibility(player:GetAttribute("InShop") == true)
