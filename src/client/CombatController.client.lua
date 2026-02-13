--[[
	CombatController.client.lua
	Client-side weapon firing, aiming, visual effects (tracers, muzzle flash, hit markers).
	Input → RemoteEvent → Server validates → Server replicates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatConfig"))
local CombatState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatState"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

----------------------------------------------------------------------
-- REMOTE REFERENCES
----------------------------------------------------------------------
local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local FireEvent = CombatRemotes:WaitForChild("FireWeapon")
local ReplicateShot = CombatRemotes:WaitForChild("ReplicateShot")
local HitConfirm = CombatRemotes:WaitForChild("HitConfirm")
local ReloadEvent = CombatRemotes:WaitForChild("ReloadWeapon")
local AmmoUpdate = CombatRemotes:WaitForChild("AmmoUpdate")

----------------------------------------------------------------------
-- LOCAL STATE
----------------------------------------------------------------------
local isFiring = false
local lastFireTime = 0
local currentAmmo = Config.Weapon.MagSize
local maxAmmo = Config.Weapon.MagSize
local isReloading = false

----------------------------------------------------------------------
-- TRACER VISUAL
----------------------------------------------------------------------
local function createTracer(origin, hitPos, color)
	local distance = (hitPos - origin).Magnitude
	local midpoint = (origin + hitPos) / 2

	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = color or Config.TracerColor
	tracer.Size = Vector3.new(Config.TracerWidth, Config.TracerWidth, distance)
	tracer.CFrame = CFrame.lookAt(midpoint, hitPos)
	tracer.Transparency = 0.3
	tracer.Parent = workspace

	-- Fade out
	task.spawn(function()
		for i = 1, 6 do
			task.wait(0.016)
			tracer.Transparency = 0.3 + (i / 6) * 0.7
			tracer.Size = Vector3.new(
				Config.TracerWidth * (1 - i/8),
				Config.TracerWidth * (1 - i/8),
				distance
			)
		end
		tracer:Destroy()
	end)
end

----------------------------------------------------------------------
-- MUZZLE FLASH
----------------------------------------------------------------------
local function createMuzzleFlash(origin, direction)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 100)
	flash.Size = Vector3.new(0.6, 0.6, 0.8)
	flash.Shape = Enum.PartType.Ball
	flash.CFrame = CFrame.lookAt(origin, origin + direction)
	flash.Transparency = 0.2
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 50)
	light.Brightness = 3
	light.Range = 10
	light.Parent = flash

	Debris:AddItem(flash, Config.MuzzleFlashDuration)
end

----------------------------------------------------------------------
-- HIT MARKER EFFECT
----------------------------------------------------------------------
local hitMarkerGui = nil

local function showHitMarker(isHeadshot)
	if not hitMarkerGui then
		hitMarkerGui = Instance.new("ScreenGui")
		hitMarkerGui.Name = "HitMarkerGui"
		hitMarkerGui.IgnoreGuiInset = true
		hitMarkerGui.Parent = player.PlayerGui
	end

	-- Clear old markers
	for _, child in ipairs(hitMarkerGui:GetChildren()) do
		child:Destroy()
	end

	local color = isHeadshot and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 255, 255)
	local size = isHeadshot and 28 or 22

	-- Create X-shaped hit marker from 4 lines
	for i = 1, 4 do
		local line = Instance.new("Frame")
		line.Name = "HitLine" .. i
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.fromOffset(3, size)
		line.BackgroundColor3 = color
		line.BorderSizePixel = 0
		line.Parent = hitMarkerGui

		local angles = {45, -45, 135, -135}
		line.Rotation = angles[i]
	end

	-- Fade out
	task.spawn(function()
		task.wait(Config.HitMarkerDuration)
		if hitMarkerGui then
			for _, child in ipairs(hitMarkerGui:GetChildren()) do
				child:Destroy()
			end
		end
	end)
end

----------------------------------------------------------------------
-- FIRE WEAPON
----------------------------------------------------------------------
local function getAimDirection()
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	-- Add slight random spread
	local spreadRad = math.rad(Config.Weapon.Spread)
	local rx = (math.random() - 0.5) * 2 * spreadRad
	local ry = (math.random() - 0.5) * 2 * spreadRad

	local spreadCF = CFrame.Angles(rx, ry, 0)
	local direction = (spreadCF * CFrame.new(Vector3.zero, ray.Direction)).LookVector

	return ray.Origin, direction
end

local function fireWeapon()
	if isReloading then return end
	if currentAmmo <= 0 then
		-- Auto-reload
		ReloadEvent:FireServer()
		return
	end

	local now = os.clock()
	if now - lastFireTime < Config.Weapon.FireRate then return end
	lastFireTime = now

	local origin, direction = getAimDirection()

	-- Get muzzle position (in front of character)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Muzzle is slightly above and in front of the wheelchair
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local muzzleOrigin
	if seat and seat.Parent and seat.Parent.PrimaryPart then
		local primary = seat.Parent.PrimaryPart
		muzzleOrigin = primary.Position + primary.CFrame.LookVector * 2 + Vector3.new(0, 2, 0)
	else
		muzzleOrigin = rootPart.Position + Vector3.new(0, 2, 0)
	end

	-- Direction from muzzle to aim point
	local aimRay = workspace:Raycast(origin, direction * 1000, RaycastParams.new())
	local aimPoint = aimRay and aimRay.Position or (origin + direction * 1000)
	local fireDirection = (aimPoint - muzzleOrigin).Unit

	-- Local visual feedback (instant)
	createMuzzleFlash(muzzleOrigin, fireDirection)

	-- Local ammo decrement (server will sync)
	currentAmmo = math.max(0, currentAmmo - 1)

	-- Tell server
	FireEvent:FireServer(muzzleOrigin, fireDirection)
end

----------------------------------------------------------------------
-- INPUT
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFiring = true
	elseif input.KeyCode == Enum.KeyCode.R then
		ReloadEvent:FireServer()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFiring = false
	end
end)

-- Continuous fire loop
RunService.Heartbeat:Connect(function()
	if isFiring then
		fireWeapon()
	end
end)

----------------------------------------------------------------------
-- SERVER EVENTS
----------------------------------------------------------------------

-- Replicated shots from OTHER players (visual only)
ReplicateShot.OnClientEvent:Connect(function(shooter, origin, hitPos)
	if shooter == player then return end -- Already showed our own

	local color = Config.TracerColor
	-- Enemy tracers slightly different tint
	local shooterTeam = shooter:GetAttribute("Team")
	local myTeam = player:GetAttribute("Team")
	if shooterTeam and myTeam and shooterTeam ~= myTeam and shooterTeam ~= "None" then
		color = Color3.fromRGB(255, 80, 80) -- Red for enemy
	end

	createTracer(origin, hitPos, color)
end)

-- Hit confirmation
HitConfirm.OnClientEvent:Connect(function(isHeadshot, damage)
	showHitMarker(isHeadshot)
end)

-- Update shared state for HUD
CombatState.Ammo = currentAmmo
CombatState.MaxAmmo = maxAmmo
CombatState.Reloading = isReloading

-- Keep state in sync on ammo changes
AmmoUpdate.OnClientEvent:Connect(function(ammo, mag, reloading)
	currentAmmo = ammo
	maxAmmo = mag
	isReloading = reloading or false
	CombatState.Ammo = currentAmmo
	CombatState.MaxAmmo = maxAmmo
	CombatState.Reloading = isReloading
end)

print("✅ CombatController loaded")
