printl("Activating Hard 20")

MutationOptions <- {
	ActiveChallenge = 1

	cm_SpecialRespawnInterval = 15
	cm_MaxSpecials = 20
	cm_BaseSpecialLimit = 4
	cm_DominatorLimit = 20
}

MutationState <- {
	MutationError = null
	SITypesAvailable = [null, null, null, null, null, null]
	SITypeCounts = [0, 0, 0, 0, 0, 0]
	SISlotsAvailable = MutationOptions.cm_MaxSpecials
	SISlotsActive = 0
	SIThreshold = ceil( MutationOptions.cm_MaxSpecials / 2 )
	Survivors = {}
	BattlefieldActivated = false
}

function OnGameEvent_round_start( params ) {
	terror_player_manager <- Entities.FindByClassname( null, "terror_player_manager" )

	for (local director, scope; director = Entities.FindByClassname( director, "info_director" );) {
		director.ValidateScriptScope()
		scope = director.GetScriptScope()
		scope.InputPanicEvent <- OnPanicEvent
		scope.InputScriptedPanicEvent <- OnPanicEvent
		scope.InputForcePanicEvent <- OnPanicEvent
	}

	for (local car_alarm; car_alarm = Entities.FindByClassname( car_alarm, "prop_car_alarm" );) // ignoring dynamic spawns
		EntityOutputs.AddOutput( car_alarm, "OnCarAlarmStart", "!self", "RunScriptCode", "g_ModeScript.OnPanicEvent()", 0.0, 1 )
}

function OnGameEvent_player_left_safe_area( params ) {
	// since entity indexes from 1 to maxplayers are reserved for player entities
	local maxplayers = Entities.FindByClassname( null, "cs_team_manager" ).GetEntityIndex() - 1

	if (maxplayers < DirectorOptions.cm_MaxSpecials + 10) { // extra 10 slots for the survivors, tanks and l4d1 survivors
		SessionState.MutationError = "MutationError:\x01 requirements not met: host is missing Metamod:Source and/or L4DToolZ"
		ClientPrint( null, 5, SessionState.MutationError )
	}

	AddTimer( null, 60, function () {
		foreach (idx, status in SessionState.SITypesAvailable) {
			if (status == null)
				SessionState.SITypesAvailable[ idx ] = true
		}
	} )
}

function OnGameEvent_player_spawn( params ) {
	local player = GetPlayerFromUserID( params.userid )

	if (NetProps.GetPropInt( player, "m_iTeamNum" ) == 2) {
		if (!player.IsDead() && !player.IsDying()) // incorrect if jointeam 1 was used while dead
			SessionState.Survivors[ params.userid ] <- player
		return
	}

	local zombieType = player.GetZombieType()
	if (zombieType > 6) // spectators don't trigger player_spawn, but if they did, they would still normally be skipped with this
		return
	local idx = zombieType - 1

	SessionState.SITypesAvailable[ idx ] = false
	AddTimer( "UnlockSIType" + zombieType, 20, function () SessionState.SITypesAvailable[ idx ] = true )
	SessionState.SITypeCounts[ idx ]++
	SessionState.SISlotsAvailable--
	SessionState.SISlotsActive++

	local specialPos = player.GetOrigin()
	if (Entities.FindByClassnameWithin( null, "info_zombie_spawn", specialPos, 10 ) != null)
		return

	if (SessionState.SISlotsActive >= SessionState.SIThreshold && SessionState.SISlotsAvailable > 0
		&& SessionState.SITypeCounts[ idx ] < SessionOptions.cm_BaseSpecialLimit)
		ZSpawn( {type = zombieType} )
}

function OnGameEvent_player_death( params ) {
	if (!("userid" in params))
		return

	local player = GetPlayerFromUserID( params.userid )

	if (player.IsSurvivor()) {
		delete SessionState.Survivors[ params.userid ]
		return
	}

	local zombieType = player.GetZombieType()
	if (zombieType > 6)
		return

	SessionState.SITypeCounts[ zombieType - 1 ]--
	AddTimer( null, 15, function () SessionState.SISlotsAvailable++ )
	SessionState.SISlotsActive--
}

function OnGameEvent_player_bot_replace( params ) {
	if (params.player in SessionState.Survivors)
		delete SessionState.Survivors[ params.player ]
}

function OnGameEvent_player_disconnect( params ) {
	if (params.userid in SessionState.Survivors)
		delete SessionState.Survivors[ params.userid ]
}

local timers = {}

function AddTimer( name, delay, func ) {
	if (!name || name == "")
		name = UniqueString()

	local timer = {Delay = delay, Func = func, LastTime = Time()}
	timers[ name ] <- timer
}

const BATTLEFIELD = 256

function AreAllSurvivorsInBattlefieldArea() {
	foreach (surv in SessionState.Survivors) {
		if (!(surv.GetLastKnownArea().GetSpawnAttributes() & BATTLEFIELD))
			return false
	}
	return true
}

function IsAnySurvivorInBattlefieldArea() {
	foreach (surv in SessionState.Survivors) {
		if (surv.GetLastKnownArea().GetSpawnAttributes() & BATTLEFIELD)
			return true
	}
	return false
}

function OnPanicEvent() {
	if (g_ModeScript.IsAnySurvivorInBattlefieldArea())
		SessionState.BattlefieldActivated = true

	return true // because Input[InputName] hooks expect a return
}

function Update() {
	local curtime = Time()

	foreach (name, timer in timers) {
		if (curtime - timer.LastTime >= timer.Delay) {
			delete timers[ name ]
			timer.Func()
		}
	}

	if (SessionState.SISlotsActive >= SessionState.SIThreshold && SessionState.SISlotsAvailable > 0
		&& NetProps.GetPropInt( terror_player_manager, "m_tempoState" ) < 2
		&& (!Director.IsTankInPlay() || Director.IsAnySurvivorBypassingTank())
		&& (!Director.AreAllSurvivorsInFinaleArea() || Director.IsFinale())
		&& (!AreAllSurvivorsInBattlefieldArea() || SessionState.BattlefieldActivated)) {
		local idxs = []

		foreach (idx, status in SessionState.SITypesAvailable) {
			if (status)
				idxs.append( idx )
		}

		if (idxs.len() > 0) {
			local idx = idxs[ RandomInt( 0, idxs.len() - 1 ) ]

			if (SessionState.SITypeCounts[ idx ] < SessionOptions.cm_BaseSpecialLimit)
				ZSpawn( {type = idx + 1} )
		}
	}
}