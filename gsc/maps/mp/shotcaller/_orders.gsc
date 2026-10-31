#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the order poller and the once-a-second enforcer.
init()
{
	level.sc_seq = -1;
	level.sc_expires = 0;
	level.sc_team_orders = [];
	level.sc_bot_orders = [];
	level.sc_chat_at = [];

	level thread pollLoop();
	level thread enforceLoop();
}

/// Path of the order file, relative to the scriptdata directory.
ordersPath()
{
	return "shotcaller/orders.txt";
}

/// Reads the order file on an interval and ingests it whenever its sequence number changes.
pollLoop()
{
	for ( ;; )
	{
		wait getdvarint( "sc_poll_ms" ) / 1000;

		if ( !fileexists( ordersPath() ) )
		{
			continue;
		}

		lines = strtok( fileread( ordersPath() ), "\n" );

		if ( lines.size == 0 )
		{
			continue;
		}

		seq = headerInt( lines[ 0 ], "seq" );

		if ( seq >= 0 && seq != level.sc_seq )
		{
			ingest( lines, seq );
		}
	}
}

/// Parses a `key|value` header line and returns the integer value when the key matches, otherwise -1.
headerInt( line, key )
{
	parts = strtok( line, "|" );

	if ( parts.size == 2 && parts[ 0 ] == key )
	{
		return int( parts[ 1 ] );
	}

	return -1;
}

/// Replaces the active orders with the ones in the file, applies them at once and acknowledges the sequence.
ingest( lines, seq )
{
	level.sc_seq = seq;

	if ( !forThisMap( lines ) )
	{
		return;
	}

	level.sc_team_orders = [];
	level.sc_bot_orders = [];
	level.sc_expires = gettime() + 30000;

	chats = 0;

	for ( i = 1; i < lines.size; i++ )
	{
		parts = strtok( lines[ i ], "|" );

		if ( parts.size < 2 )
		{
			continue;
		}

		switch ( parts[ 0 ] )
		{
			case "ttl":
				level.sc_expires = gettime() + int( parts[ 1 ] );
				break;
			case "seq":
			case "map":
				break;
			case "team":
				level.sc_team_orders[ parts[ 1 ] ] = parsePairs( parts, 2 );
				break;
			case "bot":
				level.sc_bot_orders[ "b" + parts[ 1 ] ] = parsePairs( parts, 2 );
				break;
			case "chat":
				chats += sayLine( parts );
				break;
		}
	}

	if ( level.sc_team_orders.size == 0 && level.sc_bot_orders.size == 0 )
	{
		revertAll();
	}

	applied = enforce();

	emit( "ack", field( "seq", seq ) + field( "bots", applied ) + field( "chats", chats ) );
}

/// Whether the order file names the map that is running, so orders written for the previous map are ignored.
forThisMap( lines )
{
	for ( i = 1; i < lines.size; i++ )
	{
		parts = strtok( lines[ i ], "|" );

		if ( parts.size == 2 && parts[ 0 ] == "map" )
		{
			return parts[ 1 ] == getdvar( "mapname" );
		}
	}

	return false;
}

/// Turns the key=value tokens from a start index onward into an array keyed by name.
parsePairs( parts, start )
{
	pairs = [];

	for ( i = start; i < parts.size; i++ )
	{
		kv = strtok( parts[ i ], "=" );

		if ( kv.size == 2 )
		{
			pairs[ kv[ 0 ] ] = kv[ 1 ];
		}
	}

	return pairs;
}

/// Makes one bot say a line, at most once per ten seconds per bot, and returns 1 when it spoke.
sayLine( parts )
{
	if ( parts.size < 4 )
	{
		return 0;
	}

	bot = botBySlot( parts[ 1 ] );

	if ( !isdefined( bot ) )
	{
		return 0;
	}

	last = level.sc_chat_at[ "b" + parts[ 1 ] ];

	if ( isdefined( last ) && gettime() - last < 10000 )
	{
		return 0;
	}

	level.sc_chat_at[ "b" + parts[ 1 ] ] = gettime();

	text = getsubstr( parts[ 3 ], 0, 100 );

	if ( parts[ 2 ] == "team" )
	{
		bot sayteam( text );
	}
	else
	{
		bot sayall( text );
	}

	return 1;
}

/// Finds a connected bot by its slot number string.
botBySlot( slot )
{
	bots = getBotArray();

	for ( i = 0; i < bots.size; i++ )
	{
		if ( ( bots[ i ] getentitynumber() + "" ) == slot )
		{
			return bots[ i ];
		}
	}

	return undefined;
}

/// Re-applies the active orders every second and reverts the bots to stock behavior once they expire.
enforceLoop()
{
	for ( ;; )
	{
		wait 1;

		if ( level.sc_seq < 0 )
		{
			continue;
		}

		if ( gettime() > level.sc_expires )
		{
			revertAll();
			level.sc_seq = -1;
			emit( "expired", "" );
			continue;
		}

		enforce();
	}
}

/// Applies the merged team and bot orders to every bot and returns how many bots had any order.
enforce()
{
	bots = getBotArray();
	applied = 0;

	for ( i = 0; i < bots.size; i++ )
	{
		if ( !ready( bots[ i ] ) )
		{
			continue;
		}

		merged = mergedOrders( bots[ i ] );

		if ( merged.size == 0 )
		{
			continue;
		}

		rememberBaseline( bots[ i ] );
		applyOrders( bots[ i ], merged );
		applied++;
	}

	return applied;
}

/// Whether Bot Warfare has finished setting up this bot's skill and behavior tables.
ready( bot )
{
	return isdefined( bot.pers ) && isdefined( bot.pers[ "bots" ] ) && isdefined( bot.pers[ "bots" ][ "skill" ] ) && isdefined( bot.pers[ "bots" ][ "behavior" ] );
}

/// A bot's effective orders: its team's orders overlaid with its own.
mergedOrders( bot )
{
	merged = [];
	team = bot.pers[ "team" ];

	if ( isdefined( team ) && isdefined( level.sc_team_orders[ team ] ) )
	{
		merged = overlay( merged, level.sc_team_orders[ team ] );
	}

	slot = "b" + ( bot getentitynumber() );

	if ( isdefined( level.sc_bot_orders[ slot ] ) )
	{
		merged = overlay( merged, level.sc_bot_orders[ slot ] );
	}

	return merged;
}

/// Copies every key of the top array onto the base array.
overlay( base, top )
{
	keys = getarraykeys( top );

	for ( i = 0; i < keys.size; i++ )
	{
		base[ keys[ i ] ] = top[ keys[ i ] ];
	}

	return base;
}

/// Names of the integer behavior knobs shotcaller may set, each a percentage from zero to one hundred.
behaviorKeys()
{
	return strtok( "strafe,nade,sprint,camp,follow,crouch,jump", "," );
}

/// Saves a bot's stock skill and behavior values the first time any order touches it.
rememberBaseline( bot )
{
	if ( isdefined( bot.sc_baseline ) )
	{
		return;
	}

	bot.sc_baseline = [];
	bot.sc_baseline[ "skill" ] = bot.pers[ "bots" ][ "skill" ][ "base" ];

	keys = behaviorKeys();

	for ( i = 0; i < keys.size; i++ )
	{
		bot.sc_baseline[ keys[ i ] ] = bot.pers[ "bots" ][ "behavior" ][ keys[ i ] ];
	}
}

/// Applies one merged order set to a bot, clamping every value into its legal range.
applyOrders( bot, orders )
{
	keys = getarraykeys( orders );

	for ( i = 0; i < keys.size; i++ )
	{
		applyOne( bot, keys[ i ], orders[ keys[ i ] ] );
	}
}

/// Applies a single key: the skill level, one behavior percentage or the goal anchor.
applyOne( bot, key, value )
{
	if ( key == "skill" )
	{
		bot.pers[ "bots" ][ "skill" ][ "base" ] = clampInt( int( value ), 1, 7 );
	}
	else if ( key == "goal" )
	{
		applyGoal( bot, value );
	}
	else if ( isBehaviorKey( key ) )
	{
		bot.pers[ "bots" ][ "behavior" ][ key ] = clampInt( int( value ), 0, 100 );
	}
}

/// Whether a key names one of the behavior percentages.
isBehaviorKey( key )
{
	keys = behaviorKeys();

	for ( i = 0; i < keys.size; i++ )
	{
		if ( keys[ i ] == key )
		{
			return true;
		}
	}

	return false;
}

/// Clamps an integer into an inclusive range.
clampInt( value, low, high )
{
	if ( value < low )
	{
		return low;
	}

	if ( value > high )
	{
		return high;
	}

	return value;
}

/// Sends a living bot to an anchor (`w<index>:<radius>`), or clears its goal on `clear`.
applyGoal( bot, value )
{
	if ( value == "clear" )
	{
		if ( bot HasScriptGoal() )
		{
			bot thread ClearScriptGoal();
		}

		return;
	}

	parts = strtok( value, ":" );
	origin = maps\mp\shotcaller\_anchors::originOf( parts[ 0 ] );

	if ( !isdefined( origin ) || !isalive( bot ) )
	{
		return;
	}

	radius = 150;

	if ( parts.size > 1 )
	{
		radius = clampInt( int( parts[ 1 ] ), 16, 1000 );
	}

	if ( !bot HasScriptGoal() || distance2d( bot GetScriptGoal(), origin ) > 16 )
	{
		bot thread SetScriptGoal( origin, radius );
	}
}

/// Restores every bot that shotcaller touched to the skill and behavior it had before.
revertAll()
{
	bots = getBotArray();

	for ( i = 0; i < bots.size; i++ )
	{
		revertBot( bots[ i ] );
	}
}

/// Restores one bot's saved baseline and clears its goal.
revertBot( bot )
{
	if ( !isdefined( bot.sc_baseline ) || !ready( bot ) )
	{
		return;
	}

	bot.pers[ "bots" ][ "skill" ][ "base" ] = bot.sc_baseline[ "skill" ];

	keys = behaviorKeys();

	for ( i = 0; i < keys.size; i++ )
	{
		bot.pers[ "bots" ][ "behavior" ][ keys[ i ] ] = bot.sc_baseline[ keys[ i ] ];
	}

	if ( bot HasScriptGoal() )
	{
		bot thread ClearScriptGoal();
	}

	bot.sc_baseline = undefined;
}
