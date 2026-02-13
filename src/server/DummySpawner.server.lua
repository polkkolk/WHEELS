--[[
	DummySpawner.server.lua
	Spawns a row of NPC test dummies with Humanoids for combat testing.
	Each dummy has full health and can be damaged by the hitscan system.
	They respawn after being killed.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DUMMY_COUNT = 5
local SPACING = 12
local SPAWN_ORIGIN = Vector3.new(0, 5, -40) -- Row in front of spawn
local RESPAWN_DELAY = 4

----------------------------------------------------------------------
-- BUILD A DUMMY CHARACTER (R15-style with parts the raycast can hit)
----------------------------------------------------------------------
local function createDummy(index)
	local model = Instance.new("Model")
	model.Name = "TestDummy_" .. index

	-- Torso / HumanoidRootPart
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Anchored = true
	rootPart.CanCollide = true
	rootPart.BrickColor = BrickColor.new("Medium stone grey")
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Parent = model

	-- Head (for headshot detection)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.Anchored = true
	head.CanCollide = true
	head.BrickColor = BrickColor.new("Bright yellow")
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model

	-- Face decal
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	-- Left Arm
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1, 2, 1)
	leftArm.Anchored = true
	leftArm.CanCollide = false
	leftArm.BrickColor = BrickColor.new("Bright yellow")
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.Parent = model

	-- Right Arm
	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1, 2, 1)
	rightArm.Anchored = true
	rightArm.CanCollide = false
	rightArm.BrickColor = BrickColor.new("Bright yellow")
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.Parent = model

	-- Left Leg
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1, 2, 1)
	leftLeg.Anchored = true
	leftLeg.CanCollide = false
	leftLeg.BrickColor = BrickColor.new("Dark green")
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.Parent = model

	-- Right Leg
	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1, 2, 1)
	rightLeg.Anchored = true
	rightLeg.CanCollide = false
	rightLeg.BrickColor = BrickColor.new("Dark green")
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.Parent = model

	-- Humanoid (so CombatService detects hits)
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = model

	-- Billboard health display above head
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthDisplay"
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	hpLabel.TextStrokeTransparency = 0.3
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextSize = 18
	hpLabel.Text = "100 HP"
	hpLabel.Parent = billboard

	-- Simple wheelchair base for visual
	local seat = Instance.new("Part")
	seat.Name = "WheelchairSeat"
	seat.Size = Vector3.new(2.5, 0.4, 2.5)
	seat.Anchored = true
	seat.CanCollide = true
	seat.BrickColor = BrickColor.new("Really black")
	seat.Material = Enum.Material.Metal
	seat.Parent = model

	-- Wheels (visual only)
	for _, side in ipairs({-1, 1}) do
		local wheel = Instance.new("Part")
		wheel.Name = side == -1 and "LeftWheel" or "RightWheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(0.4, 2.2, 2.2)
		wheel.Anchored = true
		wheel.CanCollide = false
		wheel.BrickColor = BrickColor.new("Dark stone grey")
		wheel.Material = Enum.Material.Metal
		wheel.Parent = model
	end

	-- Back handle
	local backHandle = Instance.new("Part")
	backHandle.Name = "BackHandle"
	backHandle.Size = Vector3.new(2, 2, 0.3)
	backHandle.Anchored = true
	backHandle.CanCollide = false
	backHandle.BrickColor = BrickColor.new("Dark stone grey")
	backHandle.Material = Enum.Material.Metal
	backHandle.Parent = model

	model.PrimaryPart = rootPart
	return model
end

----------------------------------------------------------------------
-- POSITION ALL PARTS RELATIVE TO ROOT
----------------------------------------------------------------------
local function positionDummy(model, worldPos)
	local root = model.PrimaryPart
	root.CFrame = CFrame.new(worldPos)

	-- Head above torso
	model.Head.CFrame = CFrame.new(worldPos + Vector3.new(0, 2, 0))

	-- Arms on sides
	model["Left Arm"].CFrame = CFrame.new(worldPos + Vector3.new(-1.5, 0, 0))
	model["Right Arm"].CFrame = CFrame.new(worldPos + Vector3.new(1.5, 0, 0))

	-- Legs below
	model["Left Leg"].CFrame = CFrame.new(worldPos + Vector3.new(-0.5, -2, 0))
	model["Right Leg"].CFrame = CFrame.new(worldPos + Vector3.new(0.5, -2, 0))

	-- Wheelchair seat under character
	model.WheelchairSeat.CFrame = CFrame.new(worldPos + Vector3.new(0, -1.2, 0))

	-- Wheels on sides of seat
	model.LeftWheel.CFrame = CFrame.new(worldPos + Vector3.new(-1.5, -1.2, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	model.RightWheel.CFrame = CFrame.new(worldPos + Vector3.new(1.5, -1.2, 0))
		* CFrame.Angles(0, 0, math.rad(90))

	-- Back handle behind seat
	model.BackHandle.CFrame = CFrame.new(worldPos + Vector3.new(0, 0.5, -1.2))
end

----------------------------------------------------------------------
-- SPAWN & RESPAWN LOGIC
----------------------------------------------------------------------
local dummies = {}

local function spawnDummy(index)
	local xOffset = (index - math.ceil(DUMMY_COUNT / 2)) * SPACING
	local pos = SPAWN_ORIGIN + Vector3.new(xOffset, 0, 0)

	local dummy = createDummy(index)
	positionDummy(dummy, pos)
	dummy.Parent = workspace

	-- Track HP display
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	local hpLabel = dummy:FindFirstChild("Head")
		and dummy.Head:FindFirstChild("HealthDisplay")
		and dummy.Head.HealthDisplay:FindFirstChild("HPLabel")

	-- Update HP billboard when damaged
	if humanoid and hpLabel then
		humanoid.HealthChanged:Connect(function(newHealth)
			hpLabel.Text = math.ceil(newHealth) .. " HP"
			if newHealth <= 0 then
				hpLabel.Text = "💀"
				hpLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			elseif newHealth <= 30 then
				hpLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif newHealth <= 60 then
				hpLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
			else
				hpLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			end
		end)
	end

	-- Respawn on death
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(RESPAWN_DELAY)
			if dummy and dummy.Parent then
				dummy:Destroy()
			end
			dummies[index] = spawnDummy(index)
		end)
	end

	return dummy
end

-- Spawn the row
for i = 1, DUMMY_COUNT do
	dummies[i] = spawnDummy(i)
end

print("✅ DummySpawner loaded — " .. DUMMY_COUNT .. " test dummies spawned")
