local GameConfig = {
	-- General
	MinPlayersToStart = 2,
	IntermissionTime = 15,      -- Seconds between rounds

	-- Modes
	DefaultMode = "FFA",        -- "FFA" or "TDM"

	-- Free-For-All
	FFA = {
		KillTarget = 25,
		TimeLimit = 300,            -- 5 minutes
	},

	-- Team Deathmatch
	TDM = {
		KillTarget = 50,
		TimeLimit = 420,            -- 7 minutes
		Teams = {
			{
				Name = "Red",
				Color = Color3.fromRGB(255, 60, 60),
				SpawnColor = BrickColor.new("Bright red"),
			},
			{
				Name = "Blue",
				Color = Color3.fromRGB(60, 120, 255),
				SpawnColor = BrickColor.new("Bright blue"),
			},
		},
	},
}

return GameConfig
