-- PistolBuilder.server.lua
-- Builds a functional Pistol Tool (like the AR in GunService) and places it in StarterPack

local Players = game:GetService("Players")

local function buildPistolTool()
    local t = Instance.new("Tool")
    t.Name = "Pistol"
    t.RequiresHandle = true
    t.CanBeDropped = false
    t.GripPos = Vector3.new(0, -0.1, 0.2)
    t.GripForward = Vector3.new(0, 0, -1)
    t.GripRight = Vector3.new(1, 0, 0)
    t.GripUp = Vector3.new(0, 1, 0)

    -- COLORS
    local slideColor  = Color3.fromRGB(40, 40, 44)
    local frameColor  = Color3.fromRGB(50, 50, 54)
    local gripColor   = Color3.fromRGB(35, 35, 38)
    local accentColor = Color3.fromRGB(60, 60, 65)
    local darkColor   = Color3.fromRGB(20, 20, 22)

    local baseCF = CFrame.new(0, 0, 0)

    -- Helper: create a part
    local function makePart(name, size, cf, color, material)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.CFrame = cf
        p.Color = color or slideColor
        p.Material = material or Enum.Material.SmoothPlastic
        p.Anchored = false
        p.CanCollide = false
        p.Parent = t
        return p
    end

    -- Helper: weld a part to the handle
    local function weldTo(part, handle)
        local w = Instance.new("WeldConstraint")
        w.Part0 = handle
        w.Part1 = part
        w.Parent = handle
    end

    -- ═══════════════════════════════════════════
    -- HANDLE (Invisible, at grip position)
    -- ═══════════════════════════════════════════
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.2, 0.55, 0.26)
    handle.Transparency = 1
    handle.CanCollide = false
    handle.Anchored = false
    handle.CFrame = baseCF * CFrame.new(0, -0.42, 0.28) * CFrame.Angles(math.rad(-8), 0, 0)
    handle.Parent = t

    -- ═══════════════════════════════════════════
    -- PISTOL BUILD (Compact Semi-Auto — M1911 / Glock Style)
    -- ═══════════════════════════════════════════

    -- 1. SLIDE (top part — the main upper body)
    local slide = makePart("Slide",
        Vector3.new(0.24, 0.22, 1.1),
        baseCF * CFrame.new(0, 0.11, 0),
        slideColor, Enum.Material.SmoothPlastic)
    weldTo(slide, handle)

    -- Slide serrations (rear grip cuts on slide)
    local serrationsR = makePart("SlideSerrationR",
        Vector3.new(0.02, 0.16, 0.25),
        baseCF * CFrame.new(0.13, 0.11, 0.3),
        darkColor, Enum.Material.DiamondPlate)
    weldTo(serrationsR, handle)

    local serrationsL = makePart("SlideSerrationL",
        Vector3.new(0.02, 0.16, 0.25),
        baseCF * CFrame.new(-0.13, 0.11, 0.3),
        darkColor, Enum.Material.DiamondPlate)
    weldTo(serrationsL, handle)

    -- 2. FRAME / LOWER RECEIVER (main body below slide)
    local frame = makePart("Frame",
        Vector3.new(0.22, 0.14, 0.9),
        baseCF * CFrame.new(0, -0.07, 0.05),
        frameColor, Enum.Material.SmoothPlastic)
    weldTo(frame, handle)

    -- Accessory rail (under the frame, front)
    local rail = makePart("AccessoryRail",
        Vector3.new(0.16, 0.04, 0.3),
        baseCF * CFrame.new(0, -0.16, -0.2),
        accentColor, Enum.Material.Metal)
    weldTo(rail, handle)

    -- 3. BARREL (short, extends from front of slide)
    local barrel = makePart("Barrel",
        Vector3.new(0.1, 0.1, 0.25),
        baseCF * CFrame.new(0, 0.06, -0.65),
        Color3.fromRGB(55, 55, 60), Enum.Material.Metal)
    weldTo(barrel, handle)

    -- Barrel bore (inner dark circle visual)
    local bore = makePart("BarrelBore",
        Vector3.new(0.06, 0.06, 0.03),
        baseCF * CFrame.new(0, 0.06, -0.78),
        darkColor, Enum.Material.Metal)
    weldTo(bore, handle)

    -- 4. GRIP / HANDLE VISUAL (angled down from the frame)
    local grip = makePart("GripVisual",
        Vector3.new(0.2, 0.55, 0.26),
        baseCF * CFrame.new(0, -0.42, 0.28) * CFrame.Angles(math.rad(-8), 0, 0),
        gripColor, Enum.Material.SmoothPlastic)
    weldTo(grip, handle)

    -- Grip texture (stippled rubber area)
    local gripTexFront = makePart("GripTextureFront",
        Vector3.new(0.21, 0.3, 0.02),
        baseCF * CFrame.new(0, -0.42, 0.15) * CFrame.Angles(math.rad(-8), 0, 0),
        Color3.fromRGB(28, 28, 30), Enum.Material.DiamondPlate)
    weldTo(gripTexFront, handle)

    local gripTexBack = makePart("GripTextureBack",
        Vector3.new(0.21, 0.3, 0.02),
        baseCF * CFrame.new(0, -0.42, 0.41) * CFrame.Angles(math.rad(-8), 0, 0),
        Color3.fromRGB(28, 28, 30), Enum.Material.DiamondPlate)
    weldTo(gripTexBack, handle)

    -- 5. TRIGGER GUARD
    local trigGuardFront = makePart("TrigGuardFront",
        Vector3.new(0.06, 0.08, 0.03),
        baseCF * CFrame.new(0, -0.18, -0.05),
        frameColor, Enum.Material.Metal)
    weldTo(trigGuardFront, handle)

    local trigGuardBottom = makePart("TrigGuardBottom",
        Vector3.new(0.06, 0.03, 0.28),
        baseCF * CFrame.new(0, -0.23, 0.08),
        frameColor, Enum.Material.Metal)
    weldTo(trigGuardBottom, handle)

    -- 6. TRIGGER
    local trigger = makePart("Trigger",
        Vector3.new(0.03, 0.1, 0.03),
        baseCF * CFrame.new(0, -0.14, 0.06) * CFrame.Angles(math.rad(-15), 0, 0),
        accentColor, Enum.Material.Metal)
    weldTo(trigger, handle)

    -- 7. MAGAZINE BASEPLATE (visible at bottom of grip)
    local magBase = makePart("MagBaseplate",
        Vector3.new(0.18, 0.04, 0.24),
        baseCF * CFrame.new(0, -0.72, 0.28) * CFrame.Angles(math.rad(-8), 0, 0),
        accentColor, Enum.Material.Metal)
    weldTo(magBase, handle)

    -- 8. FRONT SIGHT
    local frontSight = makePart("FrontSight",
        Vector3.new(0.04, 0.06, 0.04),
        baseCF * CFrame.new(0, 0.25, -0.42),
        darkColor, Enum.Material.Metal)
    weldTo(frontSight, handle)

    -- Front sight dot (white/luminous)
    local frontDot = makePart("FrontSightDot",
        Vector3.new(0.02, 0.02, 0.02),
        baseCF * CFrame.new(0, 0.28, -0.42),
        Color3.fromRGB(220, 255, 220), Enum.Material.Neon)
    weldTo(frontDot, handle)

    -- 9. REAR SIGHT
    local rearSightL = makePart("RearSightL",
        Vector3.new(0.03, 0.06, 0.04),
        baseCF * CFrame.new(-0.06, 0.25, 0.38),
        darkColor, Enum.Material.Metal)
    weldTo(rearSightL, handle)

    local rearSightR = makePart("RearSightR",
        Vector3.new(0.03, 0.06, 0.04),
        baseCF * CFrame.new(0.06, 0.25, 0.38),
        darkColor, Enum.Material.Metal)
    weldTo(rearSightR, handle)

    -- Rear sight dots
    local rearDotL = makePart("RearDotL",
        Vector3.new(0.02, 0.02, 0.02),
        baseCF * CFrame.new(-0.06, 0.28, 0.38),
        Color3.fromRGB(220, 255, 220), Enum.Material.Neon)
    weldTo(rearDotL, handle)

    local rearDotR = makePart("RearDotR",
        Vector3.new(0.02, 0.02, 0.02),
        baseCF * CFrame.new(0.06, 0.28, 0.38),
        Color3.fromRGB(220, 255, 220), Enum.Material.Neon)
    weldTo(rearDotR, handle)

    -- 10. EJECTION PORT (right side of slide)
    local ejectionPort = makePart("EjectionPort",
        Vector3.new(0.02, 0.1, 0.18),
        baseCF * CFrame.new(0.13, 0.12, 0.05),
        darkColor, Enum.Material.Metal)
    weldTo(ejectionPort, handle)

    -- 11. SLIDE RELEASE LEVER (left side)
    local slideRelease = makePart("SlideRelease",
        Vector3.new(0.02, 0.04, 0.1),
        baseCF * CFrame.new(-0.12, 0.0, -0.05),
        accentColor, Enum.Material.Metal)
    weldTo(slideRelease, handle)

    -- 12. HAMMER (rear of slide, for M1911 style)
    local hammer = makePart("Hammer",
        Vector3.new(0.06, 0.1, 0.06),
        baseCF * CFrame.new(0, 0.18, 0.54) * CFrame.Angles(math.rad(-30), 0, 0),
        darkColor, Enum.Material.Metal)
    weldTo(hammer, handle)

    -- 13. BEAVER TAIL (grip safety area at top rear)
    local beaverTail = makePart("BeaverTail",
        Vector3.new(0.2, 0.06, 0.1),
        baseCF * CFrame.new(0, -0.02, 0.5),
        frameColor, Enum.Material.SmoothPlastic)
    weldTo(beaverTail, handle)

    -- ═══════════════════════════════════════════
    -- MUZZLE VFX (Same pattern as AR, slightly smaller)
    -- ═══════════════════════════════════════════

    -- Invisible part at barrel tip
    local muzzle = makePart("MuzzlePart",
        Vector3.new(0.08, 0.08, 0.08),
        baseCF * CFrame.new(0, 0.06, -0.82),
        slideColor)
    muzzle.Transparency = 1
    weldTo(muzzle, handle)

    -- Muzzle Attachment on Handle (for flash & smoke particles)
    local muzzleAtt = Instance.new("Attachment")
    muzzleAtt.Name = "Muzzle"
    muzzleAtt.CFrame = CFrame.new(0, 0.06, -0.82) * CFrame.Angles(0, math.rad(180), 0)
    muzzleAtt.Parent = handle

    -- 1. Muzzle Light (Instant flash)
    local flashLight = Instance.new("PointLight")
    flashLight.Name = "FlashLight"
    flashLight.Color = Color3.fromRGB(255, 220, 170)
    flashLight.Range = 10
    flashLight.Brightness = 0 -- Start OFF
    flashLight.Shadows = false
    flashLight.Parent = muzzleAtt

    -- 2. Muzzle Flash Particles (Directional forward flash)
    local flashEmitter = Instance.new("ParticleEmitter")
    flashEmitter.Name = "FlashEmitter"
    flashEmitter.Texture = "rbxassetid://6490035152" -- Sharp star/flare
    flashEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)),
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 200, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 20))
    })
    flashEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3), -- Slightly smaller than AR
        NumberSequenceKeypoint.new(1, 0)
    })
    flashEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    flashEmitter.Lifetime = NumberRange.new(0.03, 0.05)
    flashEmitter.Speed = NumberRange.new(12, 25) -- Slightly less than AR
    flashEmitter.SpreadAngle = Vector2.new(8, 8)
    flashEmitter.Rate = 0
    flashEmitter.LightEmission = 1
    flashEmitter.LightInfluence = 0
    flashEmitter.RotSpeed = NumberRange.new(-500, 500)
    flashEmitter.Rotation = NumberRange.new(0, 360)
    flashEmitter.Parent = muzzleAtt

    -- 3. Smoke/Gas Emitter (subtle wisp exiting barrel)
    local smokeEmitter = Instance.new("ParticleEmitter")
    smokeEmitter.Name = "SmokeEmitter"
    smokeEmitter.Texture = "rbxassetid://1084981836" -- Soft smoke puff
    smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(160, 160, 160))
    smokeEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1), -- Slightly smaller than AR
        NumberSequenceKeypoint.new(1, 0.45)
    })
    smokeEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(1, 1)
    })
    smokeEmitter.Lifetime = NumberRange.new(0.1, 0.25)
    smokeEmitter.Speed = NumberRange.new(4, 10) -- Slightly less than AR
    smokeEmitter.SpreadAngle = Vector2.new(10, 10)
    smokeEmitter.Rate = 0
    smokeEmitter.LightEmission = 0.2
    smokeEmitter.RotSpeed = NumberRange.new(-100, 100)
    smokeEmitter.Rotation = NumberRange.new(0, 360)
    smokeEmitter.Parent = muzzleAtt

    -- ═══════════════════════════════════════════
    -- PLACE TOOL
    -- ═══════════════════════════════════════════
    t.Parent = game.StarterPack

    -- Clone to all current players' Backpacks
    for _, p in ipairs(Players:GetPlayers()) do
        if not p.Backpack:FindFirstChild("Pistol") then
            t:Clone().Parent = p.Backpack
        end
    end

    print("🔫 Pistol tool built and placed in StarterPack")
    return t
end

buildPistolTool()
