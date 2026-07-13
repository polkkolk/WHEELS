-- MonetizationService.server.lua
-- Handles Roblox Developer Product purchases and validates receipts

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local PRODUCT_MAP = {
	[3609550136] = 250,  -- 150 Robux
	[3609550195] = 500,  -- 290 Robux
	[3609550233] = 1000, -- 550 Robux
	[3609550278] = 5000, -- 2500 Robux
}

-- Function to safely award coins directly to the player's data values
local function grantCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local hiddenStats = player:FindFirstChild("HiddenStats")
	
	if ls and hiddenStats then
		local money = ls:FindFirstChild("Money")
		local lifetimeCoins = hiddenStats:FindFirstChild("LifetimeCoins")
		
		if money then
			money.Value = money.Value + amount
		end
		
		if lifetimeCoins then
			lifetimeCoins.Value = lifetimeCoins.Value + amount
		end
		
		-- Play a nice cha-ching sound for the player locally
		local pGui = player:FindFirstChild("PlayerGui")
		if pGui then
			local sfx = Instance.new("Sound")
			sfx.SoundId = "rbxassetid://1347140027" -- Classic cha-ching
			sfx.Volume = 1
			sfx.Parent = pGui
			sfx:Play()
			sfx.Ended:Connect(function()
				sfx:Destroy()
			end)
		end
		
		print("[MonetizationService] Granted " .. amount .. " coins to " .. player.Name)
		return true
	end
	return false
end

-- Hook into MarketplaceService to process the purchase receipt securely
local function processReceipt(receiptInfo)
	-- receiptInfo contains PlayerId, ProductId, PurchaseId, CurrencySpent, PlaceIdWherePurchased
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		-- Player left the game before the receipt could be processed.
		-- Return NotProcessedYet so Roblox tries again when they rejoin!
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Verify this is one of our Coin products
	local coinsToAward = PRODUCT_MAP[productId]
	if coinsToAward then
		local success = grantCoins(player, coinsToAward)
		
		if success then
			-- Tell Roblox we successfully granted the item so they can charge the user
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			-- If grantCoins fails (e.g., stats haven't loaded yet), do not charge them yet!
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	
	-- If it's a product ID we don't recognize, just grant it anyway so the transaction closes.
	warn("[MonetizationService] Unknown Product ID purchased:", productId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Set the callback
MarketplaceService.ProcessReceipt = processReceipt

print("✅ MonetizationService Loaded")
