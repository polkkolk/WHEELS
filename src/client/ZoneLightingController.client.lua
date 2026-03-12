local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------------------------------------------
-- 🔥 NUCLEAR CLEANUP (runs once on startup)
----------------------------------------------------
Lighting.GlobalShadows = false
Lighting.ExposureCompensation = 0
Lighting.FogEnd = 100000
Lighting.FogStart = 0
Lighting.FogColor = Color3.fromRGB(192, 192, 192)
Lighting.EnvironmentSpecularScale = 0
Lighting.EnvironmentDiffuseScale = 0

for _, obj in ipairs(Lighting:GetChildren()) do
    if obj:IsA("Sky") 
    or obj:IsA("Atmosphere") 
    or obj:IsA("ColorCorrectionEffect") 
    or obj:IsA("SunRaysEffect")
    or obj:IsA("BloomEffect") then
        obj:Destroy()
    end
end

----------------------------------------------------
-- LOBBY = Default Roblox daytime
----------------------------------------------------
local function applyLobbyLighting()
    Lighting.Brightness = 3
    Lighting.ClockTime = 14
    Lighting.Ambient = Color3.fromRGB(138, 138, 138)
    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    Lighting.ColorShift_Top = Color3.new(0, 0, 0)
    Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
    Lighting.EnvironmentSpecularScale = 0
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.GlobalShadows = false
    
    -- Remove starry sky if it exists
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Sky") then obj:Destroy() end
    end
    
    print("🌞 Lobby lighting applied")
end

----------------------------------------------------
-- OBELISKS = Midnight with starry sky
----------------------------------------------------
local function applyObelisksLighting()
    Lighting.Brightness = 5
    Lighting.ClockTime = 0
    Lighting.Ambient = Color3.fromRGB(50, 60, 90)
    Lighting.OutdoorAmbient = Color3.fromRGB(70, 85, 120)
    Lighting.ColorShift_Top = Color3.fromRGB(150, 180, 220)
    Lighting.ColorShift_Bottom = Color3.fromRGB(30, 40, 60)
    Lighting.EnvironmentSpecularScale = 0
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.GlobalShadows = false
    
    -- Remove old sky
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Sky") then obj:Destroy() end
    end
    
    -- Clone from ReplicatedStorage so it doesn't pollute the editor
    local customSky = ReplicatedStorage:FindFirstChild("ObelisksSky")
    if customSky and customSky:IsA("Sky") then
        local skyClone = customSky:Clone()
        skyClone.Parent = Lighting
    else
        -- Fallback if they forgot to move it
        local sky = Instance.new("Sky")
        sky.StarCount = 5000
        sky.SunAngularSize = 0
        sky.MoonAngularSize = 11
        sky.Parent = Lighting
    end
    
    print("🌙 Obelisks lighting applied")
end

----------------------------------------------------
-- Apply lobby lighting RIGHT NOW on startup
----------------------------------------------------
applyLobbyLighting()

----------------------------------------------------
-- Listen to the ACTUAL game round system!
-- No more unreliable distance checking.
----------------------------------------------------
local GameEvent = ReplicatedStorage:WaitForChild("GameEvent", 15)
if GameEvent then
    GameEvent.OnClientEvent:Connect(function(eventName, data)
        if eventName == "round_start" then
            -- data.mapName tells us which map we are on
            if data and data.mapName == "Obelisks" then
                applyObelisksLighting()
            end
        elseif eventName == "round_end" then
            -- Round ended, going back to lobby
            applyLobbyLighting()
        end
    end)
    print("✅ ZoneLightingController: Hooked into GameEvent successfully!")
else
    warn("⚠️ ZoneLightingController: GameEvent not found! Lighting switching will not work.")
end
