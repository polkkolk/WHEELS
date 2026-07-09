local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GameEvent = ReplicatedStorage:WaitForChild("GameEvent")

local LOBBY_MUSIC_ID = "rbxassetid://137573587477809"
local MAX_VOLUME = 0.1

-- Map-specific music configs
local ROUND_MUSIC_CONFIGS = {
    ["Obelisks"] = { id = "rbxassetid://107439279224689", vol = 0.5 },
}

-- Create the Sound Objects
local lobbyMusic = Instance.new("Sound")
lobbyMusic.Name = "LobbyMusic"
lobbyMusic.SoundId = LOBBY_MUSIC_ID
lobbyMusic.Looped = true
lobbyMusic.Volume = 0
lobbyMusic.Parent = game:GetService("SoundService")

local roundMusic = Instance.new("Sound")
roundMusic.Name = "RoundMusic"
roundMusic.Looped = true
roundMusic.Volume = 0
roundMusic.Parent = game:GetService("SoundService")

local currentTween = nil
local currentRoundTween = nil

local function fadeMusic(soundObj, targetVolume, newSoundId, tweenVarName)
    local activeTween = (tweenVarName == "lobby") and currentTween or currentRoundTween
    if activeTween then activeTween:Cancel() end
    
    if newSoundId and soundObj.SoundId ~= newSoundId then
        soundObj:Stop()
        soundObj.SoundId = newSoundId
    end
    
    if targetVolume > 0 and not soundObj.IsPlaying and soundObj.SoundId ~= "" then
        soundObj:Play()
    end
    
    local newTween = TweenService:Create(soundObj, TweenInfo.new(1.5), {Volume = targetVolume})
    newTween:Play()
    
    if tweenVarName == "lobby" then
        currentTween = newTween
    else
        currentRoundTween = newTween
    end
    
    if targetVolume == 0 then
        newTween.Completed:Once(function(state)
            if state == Enum.PlaybackState.Completed and soundObj.Volume == 0 then
                soundObj:Stop()
            end
        end)
    end
end

-- Assume we start in the lobby
fadeMusic(lobbyMusic, MAX_VOLUME, nil, "lobby")

GameEvent.OnClientEvent:Connect(function(eventName, data)
    if eventName == "intermission" or eventName == "voting" or eventName == "lobby_return" then
        fadeMusic(lobbyMusic, MAX_VOLUME, nil, "lobby")
        fadeMusic(roundMusic, 0, nil, "round")
    elseif eventName == "round_start" then
        fadeMusic(lobbyMusic, 0, nil, "lobby")
        local mapName = data and data.mapName or ""
        local config = ROUND_MUSIC_CONFIGS[mapName]
        if config then
            fadeMusic(roundMusic, config.vol, config.id, "round")
        else
            fadeMusic(roundMusic, 0, nil, "round")
        end
    end
end)
