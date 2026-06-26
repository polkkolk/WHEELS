local Players = game:GetService("Players")

local function enforceBlocky(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	-- 🛡️ HARD RESET: Force standard proportions and limbs
	local description = humanoid:GetAppliedDescription()
	
	-- 1. RESET ALL BODY PARTS TO 0 (Default R15 Block)
	-- We specifically DO NOT reset the Head to 0. Many modern avatars use "Dynamic Heads" 
	-- where the face is baked into the Head mesh. Forcing Head=0 deletes their dynamic face 
	-- and forces the default Roblox smile. Preserving the Head preserves their face!
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0
	
	-- 2. FORCE CLASSIC SCALING
	description.BodyTypeScale = 0
	description.ProportionScale = 0 -- Corrected from ProportionsScale
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	
	-- 3. APPLY (Ensures parts are replaced)
	humanoid:ApplyDescription(description)
	
	-- 4. SECOND PASS: Catch late-loading bundles (Roblox sometimes overrides)
	task.delay(2, function()
		if character and character.Parent and humanoid and humanoid.Parent then
			humanoid:ApplyDescription(description)
		end
	end)
	
	print("🛡️ AvatarService: Blocky Enforcement applied to", character.Name)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait for appearance to fully anchor before we swap it
		task.wait(0.5)
		enforceBlocky(character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Cleanup for existing players (useful during studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		enforceBlocky(player.Character)
	end
	onPlayerAdded(player)
end
