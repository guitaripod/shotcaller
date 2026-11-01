#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the end-of-match vote: sets its dvars and waits for the match to end.
init()
{
	defaults();
	holdTheMap();

	level thread watchEnd();
}

/// Sets the vote dvars that the server config has not set.
defaults()
{
	names = strtok( "sc_vote,sc_vote_choices,sc_vote_seconds,sc_vote_delay,sc_vote_sens,sc_vote_font", "," );
	values = strtok( "1,60,12,2,6,0.9", "," );

	for ( i = 0; i < names.size; i++ )
	{
		if ( getdvar( names[ i ] ) == "" )
		{
			setdvar( names[ i ], values[ i ] );
		}
	}

	if ( getdvar( "sc_vote_pool" ) == "" )
	{
		setdvar( "sc_vote_pool", "" );
	}

	remember();

	setdvar( "sc_gm_pick", "" );
}

/// Waits for the match to end, then runs the vote if anyone is there to take part and the vote is on.
watchEnd()
{
	level waittill( "game_ended" );

	players = maps\mp\shotcaller\_hud_events::humans();

	if ( !getdvarint( "sc_vote" ) || players.size == 0 )
	{
		decide( candidates(), [] );
		return;
	}

	wait getdvarfloat( "sc_vote_delay" );

	list = candidates();

	if ( list.size < 2 )
	{
		return;
	}


	level.sc_voting = true;
	level.sc_vote_list = list;
	level.sc_vote_version = 0;
	gm = gmIndex( list );

	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] thread session( list, gm, getdvarint( "sc_vote_seconds" ), true );
	}

	wait getdvarint( "sc_vote_seconds" ) + 0.3;

	counts = tally( list );

	decide( list, counts );
	level notify( "sc_vote_over" );
	wait 1.8;
	level.sc_voting = undefined;
}

/// Keeps the server on this map after the match ends long enough for the vote, its result and a moment to read it. The end-of-match code reads this at the end, so it is set at the start.
holdTheMap()
{
	needed = int( getdvarfloat( "sc_vote_delay" ) + getdvarint( "sc_vote_seconds" ) + 4.5 );

	if ( !isdefined( level.postRoundTime ) || level.postRoundTime < needed )
	{
		level.postRoundTime = needed;
	}
}

/// The position of the game master's pick in the list, or -1 when it made none.
gmIndex( list )
{
	gm = getdvar( "sc_gm_pick" );

	for ( i = 0; i < list.size; i++ )
	{
		if ( gm != "" && list[ i ] == gm )
		{
			return i;
		}
	}

	return -1;
}

/// The maps the vote offers: every map in the pool except the current one, in the order players know them.
candidates()
{
	pool = pool();
	current = getdvar( "mapname" );
	list = [];
	known = maps\mp\shotcaller\_mapnames::order();

	for ( i = 0; i < known.size; i++ )
	{
		if ( known[ i ] != current && contains( pool, known[ i ] ) )
		{
			list[ list.size ] = known[ i ];
		}
	}

	for ( i = 0; i < pool.size; i++ )
	{
		if ( pool[ i ] != current && !contains( list, pool[ i ] ) )
		{
			list[ list.size ] = pool[ i ];
		}
	}

	limit = getdvarint( "sc_vote_choices" );

	while ( list.size > limit )
	{
		list[ list.size - 1 ] = undefined;
	}

	return list;
}

/// The maps eligible for the vote: the explicit pool dvar if set, otherwise every map the rotation has shown so far.
pool()
{
	explicit = getdvar( "sc_vote_pool" );

	if ( explicit != "" )
	{
		return strtok( explicit, " " );
	}

	return strtok( getdvar( "sc_vote_seen" ), " " );
}

/// Adds the current map and every map still queued in the rotation to the remembered pool, because the engine drains the rotation as it plays.
remember()
{
	seen = strtok( getdvar( "sc_vote_seen" ), " " );
	found = [];
	found[ 0 ] = getdvar( "mapname" );
	sources = [];
	sources[ 0 ] = getdvar( "sv_mapRotation" );
	sources[ 1 ] = getdvar( "sv_mapRotationCurrent" );

	for ( s = 0; s < sources.size; s++ )
	{
		tokens = strtok( sources[ s ], " " );

		for ( i = 0; i < tokens.size - 1; i++ )
		{
			if ( tokens[ i ] == "map" )
			{
				found[ found.size ] = tokens[ i + 1 ];
			}
		}
	}

	text = getdvar( "sc_vote_seen" );

	for ( i = 0; i < found.size; i++ )
	{
		if ( found[ i ] != "" && !contains( seen, found[ i ] ) )
		{
			seen[ seen.size ] = found[ i ];
			text += " " + found[ i ];
		}
	}

	setdvar( "sc_vote_seen", text );
}

/// Whether an array of strings holds a value.
contains( list, value )
{
	for ( i = 0; i < list.size; i++ )
	{
		if ( list[ i ] == value )
		{
			return true;
		}
	}

	return false;
}

/// Shuffles an array of strings in place and returns it.
shuffle( list )
{
	for ( i = list.size - 1; i > 0; i-- )
	{
		j = randomint( i + 1 );
		held = list[ i ];
		list[ i ] = list[ j ];
		list[ j ] = held;
	}

	return list;
}

/// Counts every human's current choice into one total per offered map.
tally( list )
{
	counts = [];

	for ( i = 0; i < list.size; i++ )
	{
		counts[ i ] = 0;
	}

	players = maps\mp\shotcaller\_hud_events::humans();

	for ( p = 0; p < players.size; p++ )
	{
		choice = players[ p ].sc_choice;

		if ( isdefined( choice ) && choice >= 0 && choice < list.size )
		{
			counts[ choice ]++;
		}
	}

	return counts;
}

/// Picks the winner, sets it as the next map and records the result; with no votes the game master's pick stands.
decide( list, counts )
{
	if ( list.size == 0 )
	{
		return;
	}

	best = -1;
	bestCount = 0;
	ties = [];

	for ( i = 0; i < counts.size; i++ )
	{
		if ( counts[ i ] > bestCount )
		{
			bestCount = counts[ i ];
			ties = [];
			ties[ 0 ] = i;
		}
		else if ( counts[ i ] == bestCount && bestCount > 0 )
		{
			ties[ ties.size ] = i;
		}
	}

	if ( ties.size > 0 )
	{
		best = ties[ randomint( ties.size ) ];
	}
	else if ( getdvar( "sc_gm_pick" ) != "" && list[ 0 ] == getdvar( "sc_gm_pick" ) )
	{
		best = 0;
	}

	level.sc_vote_winner = best;

	if ( counts.size > 0 )
	{
		emit( "vote", field( "winner", winnerId( list, best ) ) + field( "choices", joined( list ) ) + field( "counts", joined( counts ) ) );
	}

	if ( best >= 0 )
	{
		setdvar( "sv_mapRotationCurrent", "gametype " + getdvar( "g_gametype" ) + " map " + list[ best ] );
	}
}

/// The winning map id, or an empty string when nobody voted and there is no recommendation.
winnerId( list, best )
{
	if ( best < 0 )
	{
		return "";
	}

	return list[ best ];
}

/// Joins an array into one comma separated string.
joined( list )
{
	out = "";

	for ( i = 0; i < list.size; i++ )
	{
		if ( i > 0 )
		{
			out += ",";
		}

		out += list[ i ];
	}

	return out;
}

/// Runs the vote screen for one player: the mouse moves a cursor over the grid and a click votes for the map under it.
session( list, gm, seconds, real )
{
	self endon( "disconnect" );

	self maps\mp\shotcaller\_hud::clear();
	self freezeControls( false );
	self closeMenu();
	self closeInGameMenu();

	ui = self maps\mp\shotcaller\_votegrid::build( list, gm );
	pointer = self maps\mp\shotcaller\_votegrid::pointer( ui );
	self.sc_choice = undefined;

	if ( real )
	{
		self maps\mp\shotcaller\_votegrid::takeLook( pointer );
	}

	deadline = gettime() + seconds * 1000;
	lastClick = false;
	seen = -1;
	sens = getdvarfloat( "sc_vote_sens" );

	while ( gettime() < deadline && ( !real || !isdefined( level.sc_vote_winner ) ) )
	{
		if ( real )
		{
			self maps\mp\shotcaller\_votegrid::mouse( pointer, ui.grid, sens );
		}
		else
		{
			maps\mp\shotcaller\_votegrid::sweep( pointer, ui.grid, gettime() );
		}

		click = self attackButtonPressed() || self useButtonPressed() || self meleeButtonPressed();

		if ( click && !lastClick )
		{
			self vote( pointer.hover );
		}

		lastClick = click;
		self maps\mp\shotcaller\_votegrid::paint( ui, pointer, self.sc_choice );
		ui.timer setValue( int( ( deadline - gettime() ) / 1000 ) + 1 );

		if ( !isdefined( level.sc_vote_version ) || level.sc_vote_version != seen || !real )
		{
			seen = 0;

			if ( isdefined( level.sc_vote_version ) )
			{
				seen = level.sc_vote_version;
			}

			maps\mp\shotcaller\_votegrid::showCounts( ui, tally( list ) );
		}

		wait 0.05;
	}

	if ( real )
	{
		level waittill( "sc_vote_over" );
		maps\mp\shotcaller\_votegrid::showCounts( ui, tally( list ) );
		maps\mp\shotcaller\_votegrid::showWinner( ui, level.sc_vote_winner );
		maps\mp\shotcaller\_votegrid::hidePointer( pointer );
		wait 1.6;
		self maps\mp\shotcaller\_votegrid::giveBackLook();
	}

	self maps\mp\shotcaller\_votegrid::dropPointer( pointer );
	maps\mp\shotcaller\_votegrid::teardown( ui );
}

/// Records a click on a tile: votes for it, or withdraws the vote when it is already this player's choice.
vote( index )
{
	if ( index < 0 )
	{
		return;
	}

	if ( isdefined( self.sc_choice ) && self.sc_choice == index )
	{
		self.sc_choice = undefined;
	}
	else
	{
		self.sc_choice = index;
	}

	level.sc_vote_version++;
}

/// Shows the vote screen for a few seconds on a living match with a scripted cursor, for judging its look; nothing is decided.
preview()
{
	list = candidates();

	if ( list.size < 2 )
	{
		return;
	}

	self session( list, gmIndex( list ), 12, false );
}
