$content = Get-Content -Path "c:\Users\Agent\Downloads\WHEELS-main\src\client\WheelchairController.client.lua" -Raw
$startIdx = $content.IndexOf("local function crashEject(")
$endIdx = $content.IndexOf("local function setupCharacter(newChar)")

if ($startIdx -eq -1 -or $endIdx -eq -1) {
    Write-Host "Markers not found"
    exit 1
}

$properContent = @"
local isCrawling = false
local function startCrawling()
    if isCrawling then return end
    isCrawling = true
    print("Starting Crawl System")
    
    if not humanoid.SeatPart then
        game:GetService("ProximityPromptService").Enabled = true
    end
    
    local animScript = character:FindFirstChild("Animate")
    if animScript then animScript.Disabled = true end
    
    for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do t:Stop() end
    
    if collisionLoop then collisionLoop:Disconnect(); collisionLoop = nil end
    
    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = humanoid
    end
    humanoid.PlatformStand = false
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    humanoid.WalkSpeed = 4
    humanoid.HipHeight = 0.5
    humanoid.AutoRotate = true
    
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    humanoid:ChangeState(Enum.HumanoidStateType.Running)
    
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://90172706246576"
    local track = humanoid:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:Play()
    track:AdjustSpeed(1)
    
    local crawlAtt = rootPart:FindFirstChild("CrawlAttachment")
    if not crawlAtt then
        crawlAtt = Instance.new("Attachment")
        crawlAtt.Name = "CrawlAttachment"
        crawlAtt.Parent = rootPart
    end
    
    local crawlMover = rootPart:FindFirstChild("CrawlMover")
    if not crawlMover then
        crawlMover = Instance.new("LinearVelocity")
        crawlMover.Name = "CrawlMover"
        crawlMover.Attachment0 = crawlAtt
        crawlMover.MaxForce = 100000 
        crawlMover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        crawlMover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        crawlMover.MaxAxesForce = Vector3.new(100000, 0, 100000)
        crawlMover.RelativeTo = Enum.ActuatorRelativeTo.World
        crawlMover.Parent = rootPart
    end
    
    local crawlTorque = rootPart:FindFirstChild("CrawlTorque")
    if not crawlTorque then
        crawlTorque = Instance.new("AlignOrientation")
        crawlTorque.Name = "CrawlTorque"
        crawlTorque.Attachment0 = crawlAtt
        crawlTorque.Mode = Enum.OrientationAlignmentMode.OneAttachment
        crawlTorque.MaxTorque = math.huge
        crawlTorque.Responsiveness = 40
        crawlTorque.Parent = rootPart
    end
    
    humanoid.AutoRotate = false
    
    local crawlLoop
    crawlLoop = RunService.Heartbeat:Connect(function()
        if humanoid.SeatPart then
            print("Remount Detected - Stopping Crawl")
            isCrawling = false
            if crawlLoop then crawlLoop:Disconnect() end
            if crawlMover then crawlMover:Destroy() end
            if crawlTorque then crawlTorque:Destroy() end
            if crawlAtt then crawlAtt:Destroy() end
            track:Stop()
            if animScript then animScript.Disabled = false end
            ragdollActivated = false
            humanoid.WalkSpeed = 16
            humanoid.HipHeight = 0
            humanoid.AutoRotate = true
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            local cam2 = workspace.CurrentCamera
            if cam2 then cam2.CameraSubject = humanoid end
            return
        end
        
        local md = humanoid.MoveDirection
        if md.Magnitude > 0.1 then
            track:AdjustSpeed(1)
            crawlMover.VectorVelocity = md * 2.5
            crawlTorque.CFrame = CFrame.lookAt(Vector3.zero, md)
        else
            track:AdjustSpeed(0)
            crawlMover.VectorVelocity = Vector3.zero
            crawlTorque.CFrame = CFrame.lookAt(Vector3.zero, rootPart.CFrame.LookVector)
        end
        
        if not _G._crawlDbg then _G._crawlDbg = 0 end
        _G._crawlDbg = _G._crawlDbg + 1
        if _G._crawlDbg % 30 == 0 then
            local currentVel = rootPart.AssemblyLinearVelocity
        end
    end)
end

local function crashEject(seat, rootPart, vel, speed, fwd, right, reason)
    if not CrashEjectEvent then return seat:Sit(nil) end
    if seat and seat:GetAttribute("_Teleporting") then return end
    local chair = workspace:FindFirstChild(player.Name .. "_Wheelchair")
    if chair then
        local vSeat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
        if vSeat and vSeat:GetAttribute("_Teleporting") then return end
    end
    
    local flatVel = Vector3.new(vel.X, 0, vel.Z)
    local flingVelocity
    local speedFactor = [math]::Clamp(speed / 50, 0.3, 1.5)
    
    if reason == "wall" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = -flingDir * 6 * speedFactor + Vector3.new(0, 8 * speedFactor, 0)
    elseif reason == "tilt" then
        local sideDir = right * (math.random() > 0.5 and 1 or -1)
        flingVelocity = sideDir * 5 * speedFactor + Vector3.new(0, 4 * speedFactor, 0)
    elseif reason == "velocity" then
        local flingDir = flatVel.Magnitude > 1 and flatVel.Unit or fwd
        flingVelocity = -flingDir * 6 * speedFactor + Vector3.new(0, 8 * speedFactor, 0)
    else
        flingVelocity = Vector3.new(0, 4, 0)
    end
    
    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = rootPart
    end

    if moveForce then moveForce.MaxForce = 0 end
    if turnForce then turnForce.MaxTorque = 0 end
    if sideForce then sideForce.Force = Vector3.zero end
    if dragForce then dragForce.Force = Vector3.zero end
    currentSpeed = 0
    
    if humanoid then
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            track:Stop()
        end
    end
    
    CrashEjectEvent:FireServer({
        reason = reason,
        flingVelocity = flingVelocity,
        speed = speed,
    })
    
    humanoid:UnequipTools()
    
    local collisionLoop
    local ragdollActivated = false
    collisionLoop = RunService.Stepped:Connect(function()
        if not humanoid then
            if collisionLoop then collisionLoop:Disconnect() end
            return
        end
        if humanoid.PlatformStand then
            ragdollActivated = true
            local cam = workspace.CurrentCamera
            if cam then cam.CameraSubject = rootPart end
        end
        if ragdollActivated and not humanoid.PlatformStand then
            startCrawling()
        end
    end)
end

"@

# Wait, the string contains "$", we need to be careful with PS escaping.
# No, it doesn't contain variables.
# Oh, wait, the "math.clamp" was replaced by "[math]::Clamp" in my copy paste! Let me fix that!
$properContent = $properContent.Replace("[math]::Clamp", "math.clamp")

$newContent = $content.Substring(0, $startIdx) + $properContent + "`n`n" + $content.Substring($endIdx)

Set-Content -Path "c:\Users\Agent\Downloads\WHEELS-main\src\client\WheelchairController.client.lua" -Value $newContent
Write-Host "Success!"
