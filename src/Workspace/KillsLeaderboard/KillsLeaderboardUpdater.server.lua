local DataStoreService = game:GetService("DataStoreService")
local ds = DataStoreService:GetOrderedDataStore("KillsLeaderboard")

local gui = script.Parent:WaitForChild("Backing"):WaitForChild("LbGui")
local bg  = gui:WaitForChild("Frame")

local function get(prefix, i) return bg:FindFirstChild(prefix .. i) end

local function refresh()
	local ok, pages = pcall(function() return ds:GetSortedAsync(false, 10) end)
	if not ok or not pages then return end
	local data = pages:GetCurrentPage()
	for i = 1, 10 do
		local entry = data[i]
		local nameL = get("Name", i)
		local winsL = get("Wins", i)
		if nameL then nameL.Text = entry and entry.key or "---" end
		if winsL then winsL.Text = entry and (tostring(entry.value) .. " K") or "— K" end
	end
end

while true do
	pcall(refresh)
	task.wait(60)
end
