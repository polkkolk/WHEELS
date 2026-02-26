local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local tool = script.Parent
if not tool:IsA("Tool") then
    -- Wait until parented to a tool? Or assume this is placed inside one.
    -- For now, we assume this script is inside StarterPlayerScripts and binds to the tool by name?
    -- No, standalone script should be INSIDE the tool for portability.
    -- But since we are syncing via Rojo, we can't easily place it "inside" a tool that doesn't exist.
    -- So we will make it a Controller that looks for "PortedRifle".
end

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

-- CONFIG (From BattleGunsFFA)
local Config = {
    Name = "Experimental AR",
    Bullets = 30,
    RPM = 600,
    Spread = 0.5, -- Degrees
    SpreadADS = 0.1,
    RecoilX = function() return (math.random() - 0.5) * 1 end,
    RecoilY = 2,
    SpringRecoil = 5,
    OTS_Offset = Vector3.new(2.5, 0.5, 1.0)
}

-- STATE
local ammo = Config.Bullets
local reloading = false
local lastFire = 0
local equipped = false

-- SPRING MODULE (Simplified Port)
local Spring = {}
Spring.__index = Spring
function Spring.new(mass, force, damping, speed)
    local self = setmetatable({}, Spring)
    self.Target = Vector3.new()
    self.Position = Vector3.new()
    self.Velocity = Vector3.new()
    self.Mass = mass or 5
    self.Force = force or 50
    self.Damping = damping or 4
    self.Speed = speed or 4
    return self
end
function Spring:Shove(force)
    self.Velocity = self.Velocity + force
end
function Spring:Update(dt)
    local scaledDt = math.min(dt, 0.1) * self.Speed
    local acceleration = (self.Target - self.Position) * self.Force / self.Mass
    acceleration = acceleration - self.Velocity * self.Damping
    self.Velocity = self.Velocity + acceleration * scaledDt
    self.Position = self.Position + self.Velocity * scaledDt
    return self.Position
end

local recoilSpring = Spring.new(5, 50, 4, 4)

-- FIRE LOGIC (Ported from RaycastWeapon.luau)
local function Fire()
    if ammo <= 0 or reloading then return end
    local now = tick()
    if now - lastFire < 60 / Config.RPM then return end
    lastFire = now
    
    ammo = ammo - 1
    
    -- Recoil Impulses
    recoilSpring:Shove(Vector3.new(Config.RecoilY, Config.RecoilX(), Config.SpringRecoil) * 0.016)
    
    -- Spread Math (The Golden Nugget)
    local spreadRadius = math.rad(Config.Spread)
    local randomAngle = math.random() * 2 * math.pi
    local randomRadius = math.sqrt(math.random()) * spreadRadius
    local spreadX = math.cos(randomAngle) * randomRadius
    local spreadY = math.sin(randomAngle) * randomRadius
    
    local origin = camera.CFrame.Position
    local dirBase = camera.CFrame.LookVector * 1000 -- Range
    
    -- Apply Spread
    local spreadDir = (CFrame.new(origin, origin + dirBase) * CFrame.Angles(spreadY, spreadX, 0)).LookVector * 1000
    
    -- Raycast
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local result = workspace:Raycast(origin, spreadDir, params)
    
    -- Visual Debug (User wanted "try it out")
    if result then
        local p = Instance.new("Part")
        p.Size = Vector3.new(0.2, 0.2, 0.2)
        p.Color = Color3.fromRGB(255, 0, 0)
        p.Material = Enum.Material.Neon
        p.Anchored = true
        p.CanCollide = false
        p.Position = result.Position
        p.Parent = workspace
        game:GetService("Debris"):AddItem(p, 1)
        
        -- Sever Event (We reuse GunFireEvent if exists, or just print)
        local ev = ReplicatedStorage:FindFirstChild("GunFireEvent")
        if ev then ev:FireServer(origin, spreadDir, result.Instance) end
    end
end

-- UPDATE LOOP
RunService.RenderStepped:Connect(function(dt)
    if not equipped then return end
    
    -- Update Recoil Spring
    local recoilVal = recoilSpring:Update(dt)
    -- Apply Camera Offset (Visual Recoil)
    -- camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(recoilVal.X), math.rad(recoilVal.Y), 0)
    -- Actually, user wants OTS. 
    -- We can add recoil to camera rotation.
    -- Warning: Touching Camera.CFrame in RenderStepped fights with Default Camera.
    -- Better to tween Humanoid.CameraOffset?
end)

-- EQUIP LOGIC
local function onEquip(t)
    equipped = true
    print("🧪 Experimental Rifle Equipped")
    
    -- OTS
    local h = player.Character:FindFirstChild("Humanoid")
    if h then
        TweenService:Create(h, TweenInfo.new(0.5), {CameraOffset = Config.OTS_Offset}):Play()
    end
    
    -- Bind Input
    ContextActionService:BindAction("ExpFire", function(_, state)
        if state == Enum.UserInputState.Begin then
            Fire()
        end
    end, false, Enum.UserInputType.MouseButton1)
end

local function onUnequip()
    equipped = false
    -- Reset OTS
    local h = player.Character:FindFirstChild("Humanoid")
    if h then
        TweenService:Create(h, TweenInfo.new(0.5), {CameraOffset = Vector3.zero}):Play()
    end
    ContextActionService:UnbindAction("ExpFire")
end

-- DETECTION
player.CharacterAdded:Connect(function(c)
    c.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and child.Name == "PortedRifle" then
            onEquip(child)
        end
    end)
    c.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child.Name == "PortedRifle" then
            onUnequip()
        end
    end)
end)

-- INITIAL
if player.Character then
    local t = player.Character:FindFirstChild("PortedRifle")
    if t then onEquip(t) end
end
