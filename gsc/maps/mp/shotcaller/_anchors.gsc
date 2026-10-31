#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Records where a human died as an anchor, the same information a kill cam shows everyone.
noteDeath( where )
{
	if ( !isdefined( level.waypoints ) || level.waypoints.size == 0 )
	{
		return;
	}

	index = getNearestWaypoint( where );

	if ( !isdefined( index ) || index < 0 || index >= level.waypoints.size )
	{
		return;
	}

	origin = getWaypointForIndex( index ).origin;

	emit( "anchor", field( "id", "w" + index ) + field( "kind", "death" ) + field( "x", int( origin[ 0 ] ) ) + field( "y", int( origin[ 1 ] ) ) + field( "z", int( origin[ 2 ] ) ) );
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
