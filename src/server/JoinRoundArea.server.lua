-- JoinRoundArea.server.lua
-- Visuals removed per user request (using HUD join button instead).
-- This script only ensures JoinRoundAreaEvent BindableEvent exists
-- (kept for backward compatibility with GameService listener).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local joinEvent = ReplicatedStorage:FindFirstChild("JoinRoundAreaEvent")
if not joinEvent then
    joinEvent = Instance.new("BindableEvent")
    joinEvent.Name = "JoinRoundAreaEvent"
    joinEvent.Parent = ReplicatedStorage
end

-- Also remove any leftover disc/zone from previous runs
local existingZone = workspace:FindFirstChild("JoinRoundZone")
if existingZone then existingZone:Destroy() end

-- Remove leftover billboard text from the PLAY/JOIN ROUND part
local centerPart = workspace:FindFirstChild("PLAY/JOIN ROUND")
if centerPart then
    local bd = centerPart:FindFirstChildOfClass("BillboardGui")
    if bd then bd:Destroy() end
end

print("[JoinRoundArea] Visuals removed. Using HUD JOIN button.")
