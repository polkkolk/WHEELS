-- ShopService.server.lua
-- Handles wheelchair shop purchases, equips, color application, and DataStore persistence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local shopStore = DataStoreService:GetDataStore("WheelchairShopV1")

-- Create remotes
local ShopPurchaseFunc = Instance.new("RemoteFunction")
ShopPurchaseFunc.Name = "ShopPurchaseFunc"
ShopPurchaseFunc.Parent = ReplicatedStorage

local ShopEquipEvent = Instance.new("RemoteEvent")
ShopEquipEvent.Name = "ShopEquipEvent"
ShopEquipEvent.Parent = ReplicatedStorage

local ITEM_COST = 100
local DRIFT_COST = 500

-- Color definitions (must match client)
local COLORS = {
	Red           = Color3.fromRGB(200, 30, 30),
	Orange        = Color3.fromRGB(230, 130, 20),
	Yellow        = Color3.fromRGB(255, 210, 50),
	["Dark Green"]  = Color3.fromRGB(30, 120, 30),
	["Light Green"] = Color3.fromRGB(100, 210, 80),
	["Dark Blue"]   = Color3.fromRGB(30, 50, 180),
	["Light Blue"]  = Color3.fromRGB(80, 170, 255),
	Purple        = Color3.fromRGB(130, 50, 180),
	Pink          = Color3.fromRGB(255, 100, 170),
	Brown         = Color3.fromRGB(120, 70, 30),
	Black         = Color3.fromRGB(17, 17, 17),
	White         = Color3.fromRGB(231, 231, 236),
}

local DRIFT_VFX = {
	["Default"] = true,
	["Magic"] = true,
	["Demon"] = true,
	["Bubbles"] = true,
	["Grass"] = true,
}

-- Cushion targets (full list)
local CUSHION_TARGETS = {
	Cushion1 = true, Cushion2 = true, Cushion3 = true, Cushion4 = true,
	Foot_Part1 = true, Foot_Part2 = true, Foot_Part3 = true,
	Handle1 = true, Handle2 = true,
}

local WHEEL_TARGETS = {
	Wheel_Part1 = true, Wheel_Part2 = true,
	Wheel_Part3 = true, Wheel_Part4 = true,
}

-- ─── HELPERS ─────────────────────────────────────────────────────────────────

local function getOwned(plr, category)
	local raw = plr:GetAttribute("Shop_Owned_" .. category) or ""
	if raw == "" then return {} end
	local list = {}
	for name in raw:gmatch("[^,]+") do
		table.insert(list, name)
	end
	return list
end

local function ownsColor(plr, category, colorName)
	for _, n in ipairs(getOwned(plr, category)) do
		if n == colorName then return true end
	end
	return false
end

local function addOwned(plr, category, colorName)
	local owned = getOwned(plr, category)
	table.insert(owned, colorName)
	plr:SetAttribute("Shop_Owned_" .. category, table.concat(owned, ","))
end

-- ─── WHEELCHAIR COLOR APPLICATION ────────────────────────────────────────────

local function storeOriginalColors(chair)
	for _, desc in ipairs(chair:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.Name == "Metal" or CUSHION_TARGETS[desc.Name] or WHEEL_TARGETS[desc.Name] then
				if not desc:GetAttribute("OriginalColor") then
					desc:SetAttribute("OriginalColor", desc.Color)
				end
			end
		end
	end
end

local function applyColor(plr, category, colorName)
	local chair = workspace:FindFirstChild(plr.Name .. "_Wheelchair")
	if not chair then return end
	local color = COLORS[colorName]
	if not color then return end

	if category == "Base" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name == "Metal" then
				desc.Color = color
			end
		end
	elseif category == "Cushions" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and CUSHION_TARGETS[desc.Name] then
				desc.Color = color
			end
		end
	elseif category == "Wheels" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and WHEEL_TARGETS[desc.Name] then
				desc.Color = color
			end
		end
	end
end

local function revertColor(plr, category)
	local chair = workspace:FindFirstChild(plr.Name .. "_Wheelchair")
	if not chair then return end

	if category == "Base" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name == "Metal" then
				local orig = desc:GetAttribute("OriginalColor")
				if orig then desc.Color = orig end
			end
		end
	elseif category == "Cushions" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and CUSHION_TARGETS[desc.Name] then
				local orig = desc:GetAttribute("OriginalColor")
				if orig then desc.Color = orig end
			end
		end
	elseif category == "Wheels" then
		for _, desc in ipairs(chair:GetDescendants()) do
			if desc:IsA("BasePart") and WHEEL_TARGETS[desc.Name] then
				local orig = desc:GetAttribute("OriginalColor")
				if orig then desc.Color = orig end
			end
		end
	end
end

-- ─── DATA PERSISTENCE ────────────────────────────────────────────────────────

local function savePlayerData(plr)
	local key = "shop_" .. plr.UserId
	local data = {
		Owned_Base        = plr:GetAttribute("Shop_Owned_Base") or "White",
		Owned_Cushions    = plr:GetAttribute("Shop_Owned_Cushions") or "Black",
		Owned_Wheels      = plr:GetAttribute("Shop_Owned_Wheels") or "Black",
		Owned_DriftVFX    = plr:GetAttribute("Shop_Owned_DriftVFX") or "Default",
		Equipped_Base     = plr:GetAttribute("Shop_Equipped_Base") or "White",
		Equipped_Cushions = plr:GetAttribute("Shop_Equipped_Cushions") or "Black",
		Equipped_Wheels   = plr:GetAttribute("Shop_Equipped_Wheels") or "Black",
		Equipped_DriftVFX = plr:GetAttribute("Shop_Equipped_DriftVFX") or "Default",
	}
	local ok, err = pcall(function()
		shopStore:SetAsync(key, data)
	end)
	if not ok then warn("[ShopService] Save failed for", plr.Name, err) end
end

local function loadPlayerData(plr)
	local key = "shop_" .. plr.UserId
	local data = nil
	local ok, err = pcall(function()
		data = shopStore:GetAsync(key)
	end)
	if not ok then warn("[ShopService] Load failed for", plr.Name, err) end

	-- Apply defaults: White free for Base, Black free for Cushions
	if not data then
		data = {
			Owned_Base        = "White",
			Owned_Cushions    = "Black",
			Owned_Wheels      = "Black",
			Owned_DriftVFX    = "Default",
			Equipped_Base     = "White",
			Equipped_Cushions = "Black",
			Equipped_Wheels   = "Black",
			Equipped_DriftVFX = "Default",
		}
	end

	-- Ensure defaults are always in owned list
	if not data.Owned_Base or data.Owned_Base == "" then
		data.Owned_Base = "White"
	elseif not data.Owned_Base:find("White") then
		data.Owned_Base = data.Owned_Base .. ",White"
	end

	if not data.Owned_Cushions or data.Owned_Cushions == "" then
		data.Owned_Cushions = "Black"
	elseif not data.Owned_Cushions:find("Black") then
		data.Owned_Cushions = data.Owned_Cushions .. ",Black"
	end

	if not data.Owned_Wheels or data.Owned_Wheels == "" then
		data.Owned_Wheels = "Black"
	elseif not data.Owned_Wheels:find("Black") then
		data.Owned_Wheels = data.Owned_Wheels .. ",Black"
	end

	if not data.Owned_DriftVFX or data.Owned_DriftVFX == "" then
		data.Owned_DriftVFX = "Default"
	elseif not data.Owned_DriftVFX:find("Default") then
		data.Owned_DriftVFX = data.Owned_DriftVFX .. ",Default"
	end
	
	-- Migrate old renamed effects
	if data.Owned_DriftVFX then
		data.Owned_DriftVFX = data.Owned_DriftVFX:gsub("Neon Triangles", "Magic")
		data.Owned_DriftVFX = data.Owned_DriftVFX:gsub("Blood Triangles", "Bubbles")
		data.Owned_DriftVFX = data.Owned_DriftVFX:gsub("Green Triangles", "Grass")
	end
	if data.Equipped_DriftVFX then
		data.Equipped_DriftVFX = data.Equipped_DriftVFX:gsub("Neon Triangles", "Magic")
		data.Equipped_DriftVFX = data.Equipped_DriftVFX:gsub("Blood Triangles", "Bubbles")
		data.Equipped_DriftVFX = data.Equipped_DriftVFX:gsub("Green Triangles", "Grass")
	end

	-- Default equips
	if not data.Equipped_Base or data.Equipped_Base == "" then
		data.Equipped_Base = "White"
	end
	if not data.Equipped_Cushions or data.Equipped_Cushions == "" then
		data.Equipped_Cushions = "Black"
	end
	if not data.Equipped_Wheels or data.Equipped_Wheels == "" then
		data.Equipped_Wheels = "Black"
	end
	if not data.Equipped_DriftVFX or data.Equipped_DriftVFX == "" then
		data.Equipped_DriftVFX = "Default"
	end

	-- Set attributes
	plr:SetAttribute("Shop_Owned_Base",        data.Owned_Base)
	plr:SetAttribute("Shop_Owned_Cushions",    data.Owned_Cushions)
	plr:SetAttribute("Shop_Owned_Wheels",      data.Owned_Wheels)
	plr:SetAttribute("Shop_Owned_DriftVFX",    data.Owned_DriftVFX)
	plr:SetAttribute("Shop_Equipped_Base",     data.Equipped_Base)
	plr:SetAttribute("Shop_Equipped_Cushions", data.Equipped_Cushions)
	plr:SetAttribute("Shop_Equipped_Wheels",   data.Equipped_Wheels)
	plr:SetAttribute("Shop_Equipped_DriftVFX", data.Equipped_DriftVFX)

	print("[ShopService] Loaded data for", plr.Name)
end

-- ─── WHEELCHAIR TRACKING ─────────────────────────────────────────────────────

local function onWheelchairCreated(child)
	if not (child:IsA("Model") and child.Name:find("_Wheelchair")) then return end
	task.wait(0.5)
	storeOriginalColors(child)

	local playerName = child.Name:gsub("_Wheelchair", "")
	local plr = Players:FindFirstChild(playerName)
	if not plr then return end

	local eqBase = plr:GetAttribute("Shop_Equipped_Base") or ""
	if eqBase ~= "" and eqBase ~= "White" then applyColor(plr, "Base", eqBase) end

	local eqCush = plr:GetAttribute("Shop_Equipped_Cushions") or ""
	if eqCush ~= "" and eqCush ~= "Black" then applyColor(plr, "Cushions", eqCush) end

	local eqWheels = plr:GetAttribute("Shop_Equipped_Wheels") or ""
	if eqWheels ~= "" then applyColor(plr, "Wheels", eqWheels) end
end

workspace.ChildAdded:Connect(onWheelchairCreated)
for _, child in ipairs(workspace:GetChildren()) do
	onWheelchairCreated(child)
end

-- ─── PLAYER LIFECYCLE ────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(plr)
	loadPlayerData(plr)
end)

-- Load for players already in game (Studio test edge case)
for _, plr in ipairs(Players:GetPlayers()) do
	if not plr:GetAttribute("Shop_Owned_Base") then
		loadPlayerData(plr)
	end
end

Players.PlayerRemoving:Connect(function(plr)
	savePlayerData(plr)
end)

-- Studio: save on close since PlayerRemoving doesn't fire
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		savePlayerData(plr)
	end
end)

-- ─── PURCHASE ────────────────────────────────────────────────────────────────

ShopPurchaseFunc.OnServerInvoke = function(plr, category, colorName)
	if category == "DriftVFX" then
		if not DRIFT_VFX[colorName] then return false, "Invalid effect" end
	else
		if not COLORS[colorName] then return false, "Invalid color" end
	end
	if category ~= "Base" and category ~= "Cushions" and category ~= "Wheels" and category ~= "DriftVFX" then return false, "Invalid category" end
	if ownsColor(plr, category, colorName) then return false, "Already owned" end

	local ls = plr:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	local cost = (category == "DriftVFX") and DRIFT_COST or ITEM_COST
	if not money or money.Value < cost then return false, "Not enough coins" end

	money.Value = money.Value - cost
	addOwned(plr, category, colorName)

	-- Auto-save after purchase
	task.spawn(savePlayerData, plr)

	return true, "Success"
end

-- ─── EQUIP ───────────────────────────────────────────────────────────────────

ShopEquipEvent.OnServerEvent:Connect(function(plr, category, colorName)
	if category ~= "Base" and category ~= "Cushions" and category ~= "Wheels" and category ~= "DriftVFX" then return end
	if not ownsColor(plr, category, colorName) then return end

	plr:SetAttribute("Shop_Equipped_" .. category, colorName)
	
	if category ~= "DriftVFX" then
		applyColor(plr, category, colorName)
	end

	-- Auto-save after equip
	task.spawn(savePlayerData, plr)
end)

print("✅ ShopService Loaded")
