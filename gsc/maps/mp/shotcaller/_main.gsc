#include maps\mp\bots\_bot_utility;

/// Starts shotcaller: opens the event log, then wires telemetry and the order poller into the running match.
init()
{
	level.sc_version = "0.1.0";

	defaultDvar( "sc_enabled", 1 );
	defaultDvar( "sc_snapshot_ms", 5000 );
	defaultDvar( "sc_poll_ms", 1000 );

	if ( !getdvarint( "sc_enabled" ) )
	{
		return;
	}

	maps\mp\shotcaller\_log::open();
	maps\mp\shotcaller\_hud::precache();

	level thread maps\mp\shotcaller\_telemetry::init();
	level thread maps\mp\shotcaller\_orders::init();
	level thread maps\mp\shotcaller\_hud::init();
	level thread maps\mp\shotcaller\_hud_events::init();
	level thread maps\mp\shotcaller\_mapvote::init();

	println( "shotcaller " + level.sc_version + " ready" );
}

/// Sets a dvar only when the server config has not already defined it.
defaultDvar( name, value )
{
	if ( getdvar( name ) == "" )
	{
		setdvar( name, value );
	}
}
