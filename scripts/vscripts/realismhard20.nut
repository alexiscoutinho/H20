printl("Activating Realism Hard 20")

MutationOptions <- {
	ActiveChallenge = 1

	cm_SpecialRespawnInterval = 15
	cm_MaxSpecials = 20
	cm_BaseSpecialLimit = 4

	DominatorLimit = 20
}

function OnGameEvent_player_left_safe_area( params ) {
	// since entity indexes from 1 to maxplayers are reserved for player entities
	local maxplayers = Entities.FindByClassname( null, "cs_team_manager" ).GetEntityIndex() - 1

	if (maxplayers < DirectorOptions.cm_MaxSpecials + 10) // extra 10 slots for the survivors, tanks and l4d1 survivors
		ClientPrint( null, 5, "MutationError:\x01 requirements not met: host is missing Metamod:Source and/or L4DToolZ" )
}