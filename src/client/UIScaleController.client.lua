-- UIScaleController.client.lua
-- Applies a dynamic UIScale to every ScreenGui in PlayerGui so the entire
-- game UI scales up on large displays and shrinks on small ones.
--
-- Reference resolution: 1080p height (1080px).
-- Anything taller gets larger UI; anything shorter gets smaller UI.
-- Clamped to [0.45, 2.0] to prevent extremes on tiny phones or 8K monitors.
--
-- Excluded GUIs (full-screen overlays that use scale-based sizing and would
-- lose edge-to-edge coverage if UIScale shrank them):
--   • DamageHitFX  — edge vignette with UDim2.new(1,0,0,px) frames; handled
--                    separately in HealthBarController via ViewportSize.

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local REF_HEIGHT = 1080
local MIN_SCALE  = 0.45
local MAX_SCALE  = 2.0

-- ScreenGui names that must NOT receive UIScale
local BLACKLIST = {
    DamageHitFX = true,
}

-- Track every UIScale we've created: [ScreenGui] = UIScale
local managed = {}

local function getScale()
    local vp = camera.ViewportSize
    if vp.Y <= 0 then return 1 end
    return math.clamp(vp.Y / REF_HEIGHT, MIN_SCALE, MAX_SCALE)
end

local function applyToGui(sg)
    if not sg:IsA("ScreenGui") then return end
    if BLACKLIST[sg.Name] then return end
    if managed[sg] then return end

    local us = sg:FindFirstChildOfClass("UIScale")
    if not us then
        us = Instance.new("UIScale")
        us.Name = "AutoUIScale"
        us.Parent = sg
    end
    us.Scale = getScale()
    managed[sg] = us
end

local function updateAll()
    local s = getScale()
    for sg, us in pairs(managed) do
        if us and us.Parent then
            us.Scale = s
        else
            managed[sg] = nil
        end
    end
end

-- Apply to already-existing ScreenGuis
for _, child in ipairs(playerGui:GetChildren()) do
    applyToGui(child)
end

-- Watch for ScreenGuis added later (other controllers run async)
playerGui.ChildAdded:Connect(function(child)
    task.wait()   -- one frame so the gui is fully initialized
    applyToGui(child)
end)

-- Update whenever the window is resized
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAll)

print("✅ UIScaleController Loaded — scale:", math.floor(getScale() * 100) .. "%")
