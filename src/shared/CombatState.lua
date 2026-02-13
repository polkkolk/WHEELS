--[[
	CombatState.lua (Shared ModuleScript)
	Shared state between CombatController and HUDController.
	Replaces _G.CombatState for safe cross-script communication.
]]

local CombatState = {
	Ammo = 30,
	MaxAmmo = 30,
	Reloading = false,
}

return CombatState
