#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the order poller and the once-a-second enforcer.
init()
{
	level.sc_seq = -1;
	level.sc_expires = 0;
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
			case "bot":
				level.sc_bot_orders[ "b" + parts[ 1 ] ] = parsePairs( parts, 2 );
				break;
			case "chat":
				chats += sayLine( parts );
				break;
		}
	}

	if ( level.sc_bot_orders.size == 0 )
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

/// Ends finished missions every second, and reverts the bots to stock behavior once the orders expire.
enforceLoop()
{
	for ( ;; )
	{
		wait 1;

		endMissions();

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

/// Applies the standing skill to every ordered bot, starts any new goal, and returns how many bots had an order.
enforce()
{
	bots = getBotArray();
	applied = 0;

	for ( i = 0; i < bots.size; i++ )
	{
		order = level.sc_bot_orders[ "b" + ( bots[ i ] getentitynumber() ) ];

		if ( !ready( bots[ i ] ) || !isdefined( order ) )
		{
			continue;
		}

		rememberBaseline( bots[ i ] );
		applyOrder( bots[ i ], order );
		applied++;
	}

	return applied;
}

/// Whether Bot Warfare has finished setting up this bot's skill table.
ready( bot )
{
	return isdefined( bot.pers ) && isdefined( bot.pers[ "bots" ] ) && isdefined( bot.pers[ "bots" ][ "skill" ] ) && isdefined( bot.bot );
}

/// Saves a bot's stock skill the first time any order touches it.
rememberBaseline( bot )
{
	if ( !isdefined( bot.sc_skill_baseline ) )
	{
		bot.sc_skill_baseline = bot.pers[ "bots" ][ "skill" ][ "base" ];
	}
}

/// Applies one bot's order: its skill every time, its goal only when the goal is new.
applyOrder( bot, order )
{
	if ( isdefined( order[ "skill" ] ) )
	{
		bot.pers[ "bots" ][ "skill" ][ "base" ] = clampInt( int( order[ "skill" ] ), 1, 7 );
	}

	if ( isdefined( order[ "goal" ] ) && ( !isdefined( bot.sc_goal_sig ) || bot.sc_goal_sig != order[ "goal" ] ) )
	{
		startMission( bot, order[ "goal" ] );
	}
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

/// Starts a timed mission (`w<index>:<radius>:<seconds>`): the bot walks to the anchor and is released when it arrives or time runs out.
startMission( bot, goal )
{
	bot.sc_goal_sig = goal;

	parts = strtok( goal, ":" );

	if ( parts.size < 3 || !isalive( bot ) )
	{
		return;
	}

	origin = maps\mp\shotcaller\_anchors::originOf( parts[ 0 ] );

	if ( !isdefined( origin ) )
	{
		return;
	}

	bot.sc_goal_origin = origin;
	bot.sc_goal_radius = clampInt( int( parts[ 1 ] ), 16, 1000 );
	bot.sc_goal_until = gettime() + clampInt( int( parts[ 2 ] ), 3, 60 ) * 1000;

	bot thread SetScriptGoal( origin, bot.sc_goal_radius );
}

/// Releases every bot whose mission is over: it arrived, ran out of time or died.
endMissions()
{
	bots = getBotArray();

	for ( i = 0; i < bots.size; i++ )
	{
		bot = bots[ i ];

		if ( !isdefined( bot.sc_goal_until ) )
		{
			continue;
		}

		if ( !isalive( bot ) || gettime() > bot.sc_goal_until || distance2d( bot.origin, bot.sc_goal_origin ) <= bot.sc_goal_radius )
		{
			releaseMission( bot );
		}
	}
}

/// Clears a bot's script goal and forgets the mission, so Bot Warfare plays the bot as usual again.
releaseMission( bot )
{
	bot.sc_goal_until = undefined;
	bot.sc_goal_origin = undefined;

	if ( bot HasScriptGoal() )
	{
		bot thread ClearScriptGoal();
	}
}

/// Restores every bot that shotcaller touched to the skill it had before and ends its mission.
revertAll()
{
	bots = getBotArray();

	for ( i = 0; i < bots.size; i++ )
	{
		revertBot( bots[ i ] );
	}
}

/// Restores one bot's stock skill, ends its mission and forgets the last goal.
revertBot( bot )
{
	if ( isdefined( bot.sc_goal_until ) )
	{
		releaseMission( bot );
	}

	bot.sc_goal_sig = undefined;

	if ( isdefined( bot.sc_skill_baseline ) && ready( bot ) )
	{
		bot.pers[ "bots" ][ "skill" ][ "base" ] = bot.sc_skill_baseline;
	}

	bot.sc_skill_baseline = undefined;
}
