$content = Get-Content -Path "c:\Users\Agent\Downloads\WHEELS-main\src\client\WheelchairController.client.lua" -Raw

$startCrawlingCode = @"
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
        crawlTorque.MaxTorque = [math]::pow(10, 8)
        crawlTorque.Responsiveness = 40
        crawlTorque.Parent = rootPart
    end
    
    humanoid.AutoRotate = false
    
    local crawlLoop
    local RunService = game:GetService("RunService")
    crawlLoop = RunService.Heartbeat:Connect(function()
        if humanoid.SeatPart or humanoid.Health <= 0 then
            print("Remount or Death Detected - Stopping Crawl")
            isCrawling = false
            if crawlLoop then crawlLoop:Disconnect() end
            if crawlMover then crawlMover:Destroy() end
            if crawlTorque then crawlTorque:Destroy() end
            if crawlAtt then crawlAtt:Destroy() end
            track:Stop()
            if animScript then animScript.Disabled = false end
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
    end)
end

-- SIM 46.0: Crash eject function (unified ejection with ragdoll fling)
"@

$content = $content.Replace("-- SIM 46.0: Crash eject function (unified ejection with ragdoll fling)", $startCrawlingCode)

$setupCode = @"
    spawn(function()
        while humanoid and humanoid.Parent do
            updatePrompts()
            if humanoid.Health > 0 and humanoid.SeatPart == nil and not isCrawling and not humanoid.PlatformStand and humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
                startCrawling()
            end
            task.wait(0.1)
        end
    end)
"@

$targetLoop = @"
    spawn(function()
        while humanoid and humanoid.Parent do
            updatePrompts()
            task.wait(0.1)
        end
    end)
"@

$content = $content.Replace($targetLoop, $setupCode)

# Now remove the redundant collisionLoop from crashEject so they don't conflict
# Find the start of "local collisionLoop" and the end of "CrashEjectEvent:FireServer"
$idx1 = $content.IndexOf("local collisionLoop`r`n    local ragdollActivated = false`r`n    collisionLoop = RunService.Stepped:Connect(function()")
if ($idx1 ~= -1) {
    $idx2 = $content.IndexOf("CrashEjectEvent:FireServer({", $idx1)
    if ($idx2 ~= -1) {
        $content = $content.Substring(0, $idx1) + $content.Substring($idx2)
    }
}

Set-Content -Path "c:\Users\Agent\Downloads\WHEELS-main\src\client\WheelchairController.client.lua" -Value $content
Write-Host "Re-applied guaranteed crawl!"
