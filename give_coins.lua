local Players = game:GetService("Players")
local player = Players:FindFirstChild("YasoMonster2")

if player then
    local leaderstats = player:FindFirstChild("leaderstats")
    local hiddenStats = player:FindFirstChild("HiddenStats")
    
    if leaderstats then
        local money = leaderstats:FindFirstChild("Money")
        if money then
            money.Value = money.Value + 9999
            print("Gave 9999 coins to YasoMonster2 via leaderstats.Money!")
        end
    end
    
    if hiddenStats then
        local lifetimeCoins = hiddenStats:FindFirstChild("LifetimeCoins")
        if lifetimeCoins then
            lifetimeCoins.Value = lifetimeCoins.Value + 9999
            print("Updated LifetimeCoins for YasoMonster2!")
        end
    end
else
    print("Could not find YasoMonster2 in the server.")
end
