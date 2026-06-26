local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- This script constantly forces YasoMonster2 to have 9999 coins.
-- We will delete this script later as requested.

RunService.Heartbeat:Connect(function()
    local player = Players:FindFirstChild("YasoMonster2")
    if player then
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local money = leaderstats:FindFirstChild("Money")
            if money and money.Value < 9999 then
                money.Value = 9999
            end
        end
        
        local hiddenStats = player:FindFirstChild("HiddenStats")
        if hiddenStats then
            local lifetimeCoins = hiddenStats:FindFirstChild("LifetimeCoins")
            if lifetimeCoins and lifetimeCoins.Value < 9999 then
                lifetimeCoins.Value = 9999
            end
        end
    end
end)
