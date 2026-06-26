local GameConfig = {}

GameConfig.Maps = {
	{
		name = "Obelisks",
		spawnsFolder = "ObelisksSpawns",
	},
}

GameConfig.Gamemodes = {
	{
		name = "Free For All",
		description = "Most kills wins!",
		duration = 300,
		minPlayers = 1,
		teamBattle = false,
	},
	{
		name = "Team Battle",
		description = "Red vs Blue — most team kills wins!",
		duration = 300,
		minPlayers = 1,
		teamBattle = true,
	},
}

-- Timing (seconds)
GameConfig.IntermissionTime = 30
GameConfig.VotingTime = 10
GameConfig.LeaderboardShowTime = 15

return GameConfig
