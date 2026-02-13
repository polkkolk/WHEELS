local CombatConfig = {
	-- Health
	MaxHealth = 100,
	HealthRegenRate = 5,        -- HP per second
	HealthRegenDelay = 4,       -- Seconds after last damage before regen starts

	-- Primary Blaster
	Weapon = {
		Name = "Blaster",
		Damage = 18,
		HeadshotMultiplier = 1.5,
		FireRate = 0.15,            -- Seconds between shots (6.67 shots/sec)
		ProjectileSpeed = 500,      -- Studs/sec (visual tracer speed)
		MaxRange = 1000,            -- Studs (long range hitscan)
		MagSize = 30,
		ReloadTime = 2.0,           -- Seconds
		Spread = 0.5,               -- Degrees of random cone spread (tight aim)
	},

	-- Respawn
	RespawnDelay = 3,           -- Seconds before respawn
	SpawnProtection = 2.5,      -- Seconds of invincibility after spawn

	-- Visual
	TracerColor = Color3.fromRGB(255, 200, 50),
	TracerWidth = 0.25,
	MuzzleFlashDuration = 0.08,
	HitMarkerDuration = 0.25,
}

return CombatConfig
