local model = script.Parent
local animationController = model:WaitForChild("AnimationController")

---------------------------------------------------------------------
-- 🕒 EASY TIMING TWEAKS
-- I added a 0.2 second delay across the board! 
-- Feel free to tweak these exact decimals to push them later/earlier
---------------------------------------------------------------------
local SPARK_WINDOWS = {
	{2.2, 3.2}, -- Window 1 (Delayed by 200 milliseconds)
	{5.2, 6.2}, -- Window 2 
	{8.2, 9.2}, -- Window 3
}

local SPARK_DENSITY = 250 -- Lots of sparks!
---------------------------------------------------------------------

-- 1. Load and start the animation
local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://115055813837263"
local track = animationController:LoadAnimation(anim)
track.Looped = true
track.Priority = Enum.AnimationPriority.Action
track:Play()

-- 2. Find Gripper3 and Gripper4
local gripper3 = nil
local gripper4 = nil

for _, part in ipairs(model:GetDescendants()) do
	if part:IsA("BasePart") then
		if part.Name == "Gripper3" then gripper3 = part end
		if part.Name == "Gripper4" then gripper4 = part end
	end
end

if not gripper3 or not gripper4 then
	warn("RobotScript: Could not find Gripper3 or Gripper4! Check spelling.")
	return
end

-- 3. Create ONE Floating Spark Attachment (Which we will teleport constantly)
local att = Instance.new("Attachment")
att.Name = "RobotSparkAttachment"
att.Parent = workspace.Terrain 

local sparks = Instance.new("ParticleEmitter")
sparks.Name = "RobotSparks"
sparks.Texture = "rbxassetid://241594419"
sparks.Orientation = Enum.ParticleOrientation.FacingCamera
sparks.LightEmission = 1
sparks.LightInfluence = 0
sparks.Brightness = 5
sparks.ZOffset = 2
sparks.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 100)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
})
sparks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 0)
})
sparks.VelocityInheritance = 0.8
sparks.Lifetime = NumberRange.new(0.3, 0.5)
sparks.Rate = SPARK_DENSITY
sparks.Speed = NumberRange.new(10, 20) -- Slowed down so they don't fly past the grippers too fast
sparks.SpreadAngle = Vector2.new(45, 45)
sparks.Acceleration = Vector3.new(0, -30, 0)
sparks.Drag = 2
sparks.EmissionDirection = Enum.NormalId.Top
sparks.Enabled = false
sparks.Parent = att

local glow = Instance.new("ParticleEmitter")
glow.Name = "RobotSparks_Glow"
glow.Texture = "rbxassetid://243527266"
glow.Orientation = Enum.ParticleOrientation.FacingCamera
glow.LightEmission = 0.5
glow.VelocityInheritance = 0.3
glow.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(1, 1)
})
glow.Color = ColorSequence.new(Color3.fromRGB(255, 100, 50))
glow.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.7),
	NumberSequenceKeypoint.new(1, 0.3)
})
glow.Lifetime = NumberRange.new(0.1, 0.2)
glow.Rate = SPARK_DENSITY / 2
glow.Speed = NumberRange.new(5, 10)
glow.Drag = 5
glow.Acceleration = Vector3.new(0, 5, 0)
glow.Enabled = false
glow.Parent = att

local weldSound = Instance.new("Sound")
weldSound.Name = "WeldSound"
weldSound.Volume = 0.5
weldSound.RollOffMaxDistance = 100
weldSound.RollOffMinDistance = 15
weldSound.RollOffMode = Enum.RollOffMode.InverseTapered
weldSound.Parent = att

local WELD_SOUNDS = {
	"rbxassetid://6215849605",
	"rbxassetid://5724656469"
}

-- 4. Sync loop: Update the location to perfectly distribute sparks, and toggle windows
local RunService = game:GetService("RunService")
local isSparkingCurrently = false

RunService.Heartbeat:Connect(function()
	if not track.IsPlaying then return end
	local pos = track.TimePosition

	-----------------------------------------------------------------------------------
	-- 🪄 THE MAGIC: 
	-- Lerp() calculates a point anywhere from 0% (Gripper3) to 100% (Gripper4).
	-- By using math.random(), every single frame the Spark Emitter teleports to a 
	-- wildly different random spot exactly along the invisible line between them!
	-----------------------------------------------------------------------------------
	att.WorldPosition = gripper3.Position:Lerp(gripper4.Position, math.random())

	local shouldSpark = false

	-- Check if current time is inside ANY of the windows
	for _, window in ipairs(SPARK_WINDOWS) do
		if pos >= window[1] and pos <= window[2] then
			shouldSpark = true
			break
		end
	end

	-- Toggle sparks to match the timing windows
	if isSparkingCurrently ~= shouldSpark then
		isSparkingCurrently = shouldSpark
		sparks.Enabled = shouldSpark
		glow.Enabled = shouldSpark
		
		if shouldSpark then
			weldSound.SoundId = WELD_SOUNDS[math.random(1, #WELD_SOUNDS)]
			weldSound:Play()
		else
			weldSound:Stop()
		end
	end
end)
