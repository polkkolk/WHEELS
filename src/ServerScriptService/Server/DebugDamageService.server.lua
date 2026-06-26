-- DebugDamageService.server.lua
-- Listens for a client request and deals 10 damage to that player (debug only).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local evt = Instance.new("RemoteEvent")
evt.Name = "DebugDamageEvent"
evt.Parent = ReplicatedStorage

evt.OnServerEvent:Connect(function(player)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if hum then
        hum:TakeDamage(10)
    end
end)
