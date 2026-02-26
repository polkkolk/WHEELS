local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

player.CharacterAdded:Connect(function(char)
	character = char
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.H then
		-- Find the dummy
		local dummy = workspace:FindFirstChild("TargetDummy")
		if not dummy then 
			warn("No TargetDummy found in workspace!")
			return 
		end
		
		local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
		if not dummyRoot then return end
		
		local targetPos = dummyRoot.Position + Vector3.new(0, 35, 0) -- 35 studs up (enough for crush)
		
		-- Teleport Logic (Check if seated)
		local humanoid = character:FindFirstChild("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		
		if humanoid and rootPart then
			if humanoid.SeatPart then
				-- If seated, move the entire wheelchair assembly
				local seat = humanoid.SeatPart
				local chairModel = seat.Parent
				if chairModel and chairModel:IsA("Model") then
					chairModel:PivotTo(CFrame.new(targetPos))
					-- Reset velocities so they fall straight down
					for _, part in ipairs(chairModel:GetDescendants()) do
						if part:IsA("BasePart") then
							part.AssemblyLinearVelocity = Vector3.new(0, -10, 0) -- slight push down? Or zero? Zero is safer.
							part.AssemblyAngularVelocity = Vector3.zero
						end
					end
				end
			else
				-- Not seated, move character
				character:PivotTo(CFrame.new(targetPos))
				rootPart.AssemblyLinearVelocity = Vector3.zero
			end
		end
		print("Teleported above Dummy! Falling...")
	end
end)
