#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts every telemetry source: kill hook, join and leave watcher, periodic snapshots and the match end.
init()
{
	level thread hookCallbacks();
	level thread watchConnections();
	level thread snapshotLoop();
	level thread watchMatchEnd();
}

/// Wraps the kill callback one frame after Bot Warfare so both wrappers stay in the chain.
hookCallbacks()
{
	level waittill( "prematch_over" );
	wait 0.1;

	level.sc_prevcallbackplayerkilled = level.callbackplayerkilled;
	level.callbackplayerkilled = ::onPlayerKilled;
}

/// Kill callback: records the kill, then hands over to the previous callback unchanged.
onPlayerKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration )
{
	level thread logKill( self, eAttacker, sWeapon, sMeansOfDeath, self.origin );

	self [[ level.sc_prevcallbackplayerkilled ]]( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration );
}

/// Emits a kill event with both sides and the victim's death position, and notes human deaths as anchors.
logKill( victim, attacker, weapon, means, where )
{
	if ( !isdefined( victim ) )
	{
		return;
	}

	fields = playerFields( "v", victim ) + field( "w", weapon ) + field( "mod", means );
	fields += field( "x", int( where[ 0 ] ) ) + field( "y", int( where[ 1 ] ) ) + field( "z", int( where[ 2 ] ) );

	if ( isdefined( attacker ) && isplayer( attacker ) && attacker != victim )
	{
		fields += playerFields( "a", attacker );
	}

	emit( "kill", fields );

	if ( !victim is_bot() )
	{
		maps\mp\shotcaller\_anchors::noteDeath( where );
	}
}

/// The identity fields of one player under a one-letter prefix: slot, name, team, bot flag.
playerFields( prefix, player )
{
	team = "none";

	if ( isdefined( player.pers ) && isdefined( player.pers[ "team" ] ) )
	{
		team = player.pers[ "team" ];
	}

	return field( prefix + "n", player getentitynumber() ) + field( prefix, player.name ) + field( prefix + "t", team ) + field( prefix + "b", boolInt( player is_bot() ) );
}

/// Maps a boolean onto the 0 or 1 the wire format uses.
boolInt( value )
{
	if ( value )
	{
		return 1;
	}

	return 0;
}

/// Emits join and leave events for every connection, including bots.
watchConnections()
{
	for ( ;; )
	{
		level waittill( "connected", player );

		emit( "join", playerFields( "p", player ) );
		player thread watchLeave();
	}
}

/// Emits the leave event when this player disconnects.
watchLeave()
{
	name = self.name;
	slot = self getentitynumber();
	bot = boolInt( self is_bot() );

	self waittill( "disconnect" );

	emit( "leave", field( "pn", slot ) + field( "p", name ) + field( "pb", bot ) );
}

/// Emits a scoreboard snapshot on a fixed interval.
snapshotLoop()
{
	for ( ;; )
	{
		wait getdvarint( "sc_snapshot_ms" ) / 1000;

		emitSnapshot();
	}
}

/// Emits team scores and the humans and bots head count, then one line per connected player.
emitSnapshot()
{
	humans = 0;
	bots = 0;

	for ( i = 0; i < level.players.size; i++ )
	{
		if ( level.players[ i ] is_bot() )
		{
			bots++;
		}
		else
		{
			humans++;
		}
	}

	emit( "snap", field( "allies", teamScore( "allies" ) ) + field( "axis", teamScore( "axis" ) ) + field( "humans", humans ) + field( "bots", bots ) );

	for ( i = 0; i < level.players.size; i++ )
	{
		emit( "p", playerStatFields( level.players[ i ] ) );
	}
}

/// One player's scoreboard line: identity, kills, deaths, score, bot skill and whether they are alive.
playerStatFields( player )
{
	fields = playerFields( "p", player ) + field( "k", pers( player, "kills" ) ) + field( "d", pers( player, "deaths" ) ) + field( "s", pers( player, "score" ) );
	fields += field( "alive", boolInt( isalive( player ) ) );

	if ( player is_bot() && isdefined( player.pers[ "bots" ] ) && isdefined( player.bot ) )
	{
		fields += botFields( player );
	}

	return fields;
}

/// A bot's current skill, the camp and sprint percentages it is running with and whether it has a goal.
botFields( bot )
{
	fields = field( "skill", bot.pers[ "bots" ][ "skill" ][ "base" ] );
	fields += field( "camp", bot.pers[ "bots" ][ "behavior" ][ "camp" ] );
	fields += field( "sprint", bot.pers[ "bots" ][ "behavior" ][ "sprint" ] );
	fields += field( "goal", boolInt( bot HasScriptGoal() ) );

	return fields;
}

/// Reads one persistent counter, treating a missing value as zero.
pers( player, key )
{
	if ( isdefined( player.pers ) && isdefined( player.pers[ key ] ) )
	{
		return player.pers[ key ];
	}

	return 0;
}

/// A team's score, or zero before the game has set one up.
teamScore( team )
{
	if ( isdefined( game[ "teamScores" ] ) && isdefined( game[ "teamScores" ][ team ] ) )
	{
		return game[ "teamScores" ][ team ];
	}

	return 0;
}

/// Emits the final scores when the match ends, after one last snapshot.
watchMatchEnd()
{
	level waittill( "game_ended" );

	emitSnapshot();
	emit( "end", field( "allies", teamScore( "allies" ) ) + field( "axis", teamScore( "axis" ) ) );
}
