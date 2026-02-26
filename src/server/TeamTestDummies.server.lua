-- TeamTestDummies.server.lua
-- Spawns two persistent test dummies (RedTeamDummy, BlueTeamDummy) for team testing.
-- They sit in wheelchairs near the arena spawn area and auto-respawn when killed.

local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")

local WHEELCHAIR_NAME = "WheelchairRig"
local RESPAWN_DELAY   = 6  -- seconds before dummy respawns

-- Dummy definitions: name and torso color.
-- Spawn position is read from a Part in Workspace with the same name.
local DUMMY_DEFS = {
	{ name = "RedTeamDummy",  color = BrickColor.new("Bright red")  },
	{ name = "BlueTeamDummy", color = BrickColor.new("Bright blue") },
}

local function getSpawnCFrame(defName)
	local marker = workspace:FindFirstChild(defName)
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	warn("TeamTestDummies: No spawn Part named '" .. defName .. "' found in Workspace — using origin")
	return CFrame.new(0, 5, 0)
end

local function getVehicleRig()
	local ss = ServerStorage:FindFirstChild("ServerAssets")
	if ss then
		local rig = ss:FindFirstChild(WHEELCHAIR_NAME)
		if rig then return rig end
	end
	return ServerStorage:FindFirstChild(WHEELCHAIR_NAME)
end

local function weldModel(model, primaryPart)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= primaryPart then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primaryPart
			w.Part1 = part
			w.Parent = primaryPart
		end
	end
end

local function buildDummy(def)
	-- Read spawn position FIRST before touching anything in Workspace
	local spawnCF = getSpawnCFrame(def.name)

	-- Remove existing dummy Model only (NOT the BasePart spawn marker)
	local existing = workspace:FindFirstChild(def.name)
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end

	-- Build character model
	local dummy = Instance.new("Model")
	dummy.Name = def.name

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Parent = dummy

	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 1.6, 1)
	torso.BrickColor = def.color
	torso.Parent = dummy
	local tw = Instance.new("WeldConstraint"); tw.Part0 = hrp; tw.Part1 = torso; tw.Parent = hrp

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.BrickColor = BrickColor.new("Light orange")
	head.Parent = dummy
	local hw = Instance.new("WeldConstraint"); hw.Part0 = hrp; hw.Part1 = head; hw.Parent = hrp


	-- NO built-in nametag here — TeamIndicatorController handles team labels client-side
	-- (prevents the label being visible to enemy team)

	-- Humanoid
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.DisplayName = def.name
	hum.Parent = dummy

	dummy.PrimaryPart = hrp
	dummy.Parent = workspace

	-- Wheelchair
	local rigTemplate = getVehicleRig()
	if rigTemplate then
		local chair = rigTemplate:Clone()
		chair.Name = def.name .. "_Wheelchair"
		chair.Parent = workspace

		local seat = chair:FindFirstChildWhichIsA("VehicleSeat", true)
		local pp = chair.PrimaryPart or seat

		if pp then
			weldModel(chair, pp)
			chair:PivotTo(spawnCF)
			dummy:PivotTo(spawnCF * CFrame.new(0, 1, 0))

			task.delay(0.5, function()
				if seat and hum and hum.Health > 0 then
					seat:Sit(hum)
				end
			end)
		end

		-- Cleanup chair on death
		hum.Died:Connect(function()
			task.delay(RESPAWN_DELAY, function()
				if chair and chair.Parent then chair:Destroy() end
			end)
		end)
	else
		dummy:PivotTo(spawnCF)
	end

	-- Auto-respawn on death
	hum.Died:Connect(function()
		print("TestDummy", def.name, "died — respawning in", RESPAWN_DELAY, "s")
		task.delay(RESPAWN_DELAY, function()
			if dummy and dummy.Parent then dummy:Destroy() end
			task.wait(0.5)
			buildDummy(def)
		end)
	end)

	print("Spawned test dummy:", def.name, "at", def.spawnPos)
	return dummy
end

-- Spawn both dummies on server start
task.wait(3) -- wait for other services to initialise
for _, def in ipairs(DUMMY_DEFS) do
	buildDummy(def)
end

print("✅ TeamTestDummies loaded")
