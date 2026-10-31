#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the anchor sources: curated camp spots at map start and team home areas once spawning settles.
init()
{
	level thread emitCampAnchors();
	level thread emitHomeAnchors();
}

/// Waits for Bot Warfare to load the waypoint graph, giving up after thirty seconds.
waitForWaypoints()
{
	for ( i = 0; i < 60; i++ )
	{
		if ( isdefined( level.waypoints ) && level.waypoints.size > 0 )
		{
			return true;
		}

		wait 0.5;
	}

	return false;
}

/// Emits the map's curated camp waypoints, thinned to at most sixty evenly spaced anchors.
emitCampAnchors()
{
	if ( !waitForWaypoints() )
	{
		return;
	}

	camps = getWaypointsOfType( "camp" );
	step = 1;

	if ( camps.size > 60 )
	{
		step = int( camps.size / 60 ) + 1;
	}

	for ( i = 0; i < camps.size; i += step )
	{
		emitAnchor( camps[ i ], "camp", "none" );
	}
}

/// Emits one home anchor per team as soon as that team has someone alive, checking every two seconds for up to two minutes.
emitHomeAnchors()
{
	level waittill( "prematch_over" );

	level.sc_home = [];

	for ( i = 0; i < 60 && level.sc_home.size < 2; i++ )
	{
		wait 2;

		if ( waitForWaypoints() )
		{
			tryTeamHome( "allies" );
			tryTeamHome( "axis" );
		}
	}
}

/// Emits the home anchor of one team that has not been done yet, and marks it done once it has someone alive.
tryTeamHome( team )
{
	if ( isdefined( level.sc_home[ team ] ) )
	{
		return;
	}

	sum = ( 0, 0, 0 );
	count = 0;

	for ( i = 0; i < level.players.size; i++ )
	{
		player = level.players[ i ];

		if ( isalive( player ) && isdefined( player.pers[ "team" ] ) && player.pers[ "team" ] == team )
		{
			sum += player.origin;
			count++;
		}
	}

	if ( count == 0 )
	{
		return;
	}

	emitAnchor( getNearestWaypoint( sum / count ), "home", team );
	level.sc_home[ team ] = true;
}

/// Records where a human died as an anchor, the same information a kill cam shows everyone.
noteDeath( where )
{
	if ( !isdefined( level.waypoints ) || level.waypoints.size == 0 )
	{
		return;
	}

	emitAnchor( getNearestWaypoint( where ), "death", "none" );
}

/// Emits one anchor event for a waypoint index.
emitAnchor( index, kind, team )
{
	if ( !isdefined( index ) || index < 0 || index >= level.waypoints.size )
	{
		return;
	}

	origin = getWaypointForIndex( index ).origin;

	emit( "anchor", field( "id", "w" + index ) + field( "kind", kind ) + field( "team", team ) + field( "x", int( origin[ 0 ] ) ) + field( "y", int( origin[ 1 ] ) ) + field( "z", int( origin[ 2 ] ) ) );
}

/// Resolves an anchor id of the form w<index> to its origin, or undefined when it is not a valid waypoint.
originOf( id )
{
	if ( !isdefined( level.waypoints ) || id.size < 2 || getsubstr( id, 0, 1 ) != "w" )
	{
		return undefined;
	}

	index = int( getsubstr( id, 1, id.size ) );

	if ( index < 0 || index >= level.waypoints.size )
	{
		return undefined;
	}

	return getWaypointForIndex( index ).origin;
}
