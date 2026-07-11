local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local isCinematicMode = false

-- Function to toggle UI visibility
local function toggleCinematicMode()
    isCinematicMode = not isCinematicMode
    
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    
    -- Iterate through all ScreenGuis and toggle them
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            -- We can store their original state if needed, but for now we just 
            -- toggle the Enabled property. If a script re-enables them, that's fine.
            gui.Enabled = not isCinematicMode
        end
    end
    
    -- Optional: also hide the default Roblox UI (chat, leaderboard, etc)
    local StarterGui = game:GetService("StarterGui")
    if isCinematicMode then
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        end)
    else
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
        end)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Don't trigger if typing in chat
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.L then
        toggleCinematicMode()
    end
end)

print("? CinematicModeController Loaded (Press L to toggle UI)")
