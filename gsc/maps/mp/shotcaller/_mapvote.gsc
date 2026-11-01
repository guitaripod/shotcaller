#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the end-of-match vote: sets its dvars and waits for the match to end.
init()
{
	defaults();

	level thread watchEnd();
}

/// Sets the vote dvars that the server config has not set.
defaults()
{
	names = strtok( "sc_vote,sc_vote_choices,sc_vote_seconds,sc_vote_delay", "," );
	values = strtok( "1,4,10,2", "," );

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

	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] thread session( list, getdvarint( "sc_vote_seconds" ), true );
	}

	wait getdvarint( "sc_vote_seconds" ) + 0.3;

	counts = tally( list );

	decide( list, counts );
	level notify( "sc_vote_over" );
	wait 1.8;
	level.sc_voting = undefined;
}

/// The maps the vote offers: the game master's pick first, then random maps from the pool that are not the current one.
candidates()
{
	pool = pool();
	current = getdvar( "mapname" );
	list = [];
	gm = getdvar( "sc_gm_pick" );

	if ( gm != "" && gm != current )
	{
		list[ list.size ] = gm;
	}

	rest = [];

	for ( i = 0; i < pool.size; i++ )
	{
		if ( pool[ i ] != current && !contains( list, pool[ i ] ) && !contains( rest, pool[ i ] ) )
		{
			rest[ rest.size ] = pool[ i ];
		}
	}

	rest = shuffle( rest );
	limit = getdvarint( "sc_vote_choices" );

	for ( i = 0; i < rest.size && list.size < limit; i++ )
	{
		list[ list.size ] = rest[ i ];
	}

	return list;
}

/// The maps eligible for the vote: the explicit pool dvar if set, otherwise every map in the server's rotation.
pool()
{
	explicit = getdvar( "sc_vote_pool" );

	if ( explicit != "" )
	{
		return strtok( explicit, " " );
	}

	maps = [];
	tokens = strtok( getdvar( "sv_mapRotation" ), " " );

	for ( i = 0; i < tokens.size - 1; i++ )
	{
		if ( tokens[ i ] == "map" )
		{
			maps[ maps.size ] = tokens[ i + 1 ];
		}
	}

	return maps;
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

/// Runs the vote screen for one player: builds it, moves the cursor on Fire and Aim, locks a vote on Use, and tears it down.
session( list, seconds, real )
{
	self endon( "disconnect" );

	self maps\mp\shotcaller\_hud::clear();
	self freezeControls( false );
	self closeMenu();
	self closeInGameMenu();

	ui = self build( list );
	self.sc_choice = undefined;
	cursor = 0;
	deadline = gettime() + seconds * 1000;
	lastFire = false;
	lastAim = false;

	self refresh( ui, list, cursor );

	while ( gettime() < deadline && ( !real || !isdefined( level.sc_vote_winner ) ) )
	{
		fire = self attackButtonPressed();
		aim = self adsButtonPressed();
		moved = false;

		if ( fire && !lastFire )
		{
			cursor = ( cursor + 1 ) % list.size;
			moved = true;
		}

		if ( aim && !lastAim )
		{
			cursor = ( cursor + list.size - 1 ) % list.size;
			moved = true;
		}

		if ( self useButtonPressed() || self meleeButtonPressed() )
		{
			if ( !isdefined( self.sc_choice ) || self.sc_choice != cursor )
			{
				self.sc_choice = cursor;
				moved = true;
			}
		}

		lastFire = fire;
		lastAim = aim;

		ui.timer setValue( int( ( deadline - gettime() ) / 1000 ) + 1 );

		if ( moved || ( gettime() % 1000 ) < 60 )
		{
			self refresh( ui, list, cursor );
		}

		wait 0.05;
	}

	if ( real )
	{
		level waittill( "sc_vote_over" );
		self showWinner( ui, list );
		wait 1.6;
	}

	self teardown( ui );
}

/// Builds the vote screen elements and returns them as one struct.
build( list )
{
	ui = spawnstruct();
	ui.dim = self maps\mp\shotcaller\_hud::shaderElem( "black", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 40 );
	ui.dim.alpha = 0.9;
	ui.title = self maps\mp\shotcaller\_hud::textElem( "hudbig", 1.4, "center", "middle", "left", "middle", -230, -140, 45 );
	ui.title setText( "VOTE FOR THE NEXT MAP" );
	ui.title.color = ( 1, 0.4, 0.08 );
	ui.title.glowColor = ( 0.55, 0, 0 );
	ui.title.glowAlpha = 1;
	ui.title.alpha = 1;
	ui.timer = self maps\mp\shotcaller\_hud::textElem( "hudbig", 2.2, "center", "middle", "right", "middle", 230, -140, 45 );
	ui.timer.color = ( 1, 0.85, 0.3 );
	ui.timer.alpha = 1;
	ui.rule = self maps\mp\shotcaller\_hud::shaderElem( "white", 460, 2, "center", "middle", "center", "middle", 0, -116, 45 );
	ui.rule.color = ( 1, 0.3, 0.05 );
	ui.rule.alpha = 0.9;
	ui.hint = self maps\mp\shotcaller\_hud::textElem( "objective", 1.05, "center", "middle", "center", "middle", 0, 150, 45 );
	ui.hint setText( "FIRE: NEXT     AIM: PREVIOUS     USE: VOTE" );
	ui.hint.color = ( 0.75, 0.75, 0.75 );
	ui.hint.alpha = 1;
	ui.rows = [];

	for ( i = 0; i < list.size; i++ )
	{
		y = -78 + i * 52;
		row = spawnstruct();
		row.bg = self maps\mp\shotcaller\_hud::shaderElem( "white", 460, 44, "center", "middle", "center", "middle", 0, y, 41 );
		row.bg.color = ( 0.03, 0.03, 0.03 );
		row.bg.alpha = 0.6;
		row.index = self maps\mp\shotcaller\_hud::textElem( "hudbig", 1.5, "center", "middle", "left", "middle", -212, y, 46 );
		row.index setValue( i + 1 );
		row.index.color = ( 1, 0.45, 0.1 );
		row.index.alpha = 1;
		row.name = self maps\mp\shotcaller\_hud::textElem( "hudbig", 1.2, "center", "middle", "left", "middle", -170, y, 46 );
		row.name setText( maps\mp\shotcaller\_mapnames::label( list[ i ] ) );
		row.name.alpha = 1;
		row.count = self maps\mp\shotcaller\_hud::textElem( "bigfixed", 1.5, "center", "middle", "right", "middle", 214, y, 46 );
		row.count.alpha = 1;
		ui.rows[ i ] = row;
	}

	ui.tag = undefined;

	if ( list.size > 0 && getdvar( "sc_gm_pick" ) != "" && list[ 0 ] == getdvar( "sc_gm_pick" ) )
	{
		ui.tag = self maps\mp\shotcaller\_hud::textElem( "objective", 0.95, "center", "middle", "right", "middle", 150, -78, 46 );
		ui.tag setText( "GAME MASTER PICK" );
		ui.tag.color = ( 1, 0.6, 0.15 );
		ui.tag.alpha = 1;
	}

	return ui;
}

/// Repaints the rows: cursor row orange, the voted row green, both gold, and the live vote counts.
refresh( ui, list, cursor )
{
	counts = tally( list );

	for ( i = 0; i < list.size; i++ )
	{
		row = ui.rows[ i ];
		voted = isdefined( self.sc_choice ) && self.sc_choice == i;
		row.count setValue( counts[ i ] );
		row.bg.alpha = 0.6;
		row.bg.color = ( 0.03, 0.03, 0.03 );
		row.name.color = ( 0.9, 0.9, 0.9 );

		if ( i == cursor )
		{
			row.bg.color = ( 0.55, 0.14, 0.02 );
			row.bg.alpha = 0.9;
			row.name.color = ( 1, 1, 1 );
		}

		if ( voted )
		{
			row.bg.color = ( 0.08, 0.42, 0.1 );
			row.bg.alpha = 0.9;
			row.name.color = ( 0.75, 1, 0.75 );
		}

		if ( voted && i == cursor )
		{
			row.bg.color = ( 0.7, 0.5, 0.05 );
		}
	}
}

/// Holds the result on screen: the winning row in gold and the title naming the next map.
showWinner( ui, list )
{
	best = level.sc_vote_winner;

	if ( !isdefined( best ) || best < 0 )
	{
		ui.title setText( "NO VOTES: ROTATION CONTINUES" );
		return;
	}

	for ( i = 0; i < list.size; i++ )
	{
		if ( i != best )
		{
			ui.rows[ i ].bg.alpha = 0.25;
			ui.rows[ i ].name.alpha = 0.4;
			ui.rows[ i ].count.alpha = 0.4;
			ui.rows[ i ].index.alpha = 0.4;
		}
	}

	ui.rows[ best ].bg.color = ( 0.85, 0.6, 0.05 );
	ui.rows[ best ].bg.alpha = 0.95;
	ui.rows[ best ].name.color = ( 1, 1, 1 );
	ui.title setText( "NEXT MAP" );
	ui.title.color = ( 1, 0.85, 0.3 );
	ui.timer.alpha = 0;
	ui.hint.alpha = 0;
}

/// Destroys every vote screen element.
teardown( ui )
{
	ui.dim destroy();
	ui.title destroy();
	ui.timer destroy();
	ui.rule destroy();
	ui.hint destroy();

	if ( isdefined( ui.tag ) )
	{
		ui.tag destroy();
	}

	for ( i = 0; i < ui.rows.size; i++ )
	{
		ui.rows[ i ].bg destroy();
		ui.rows[ i ].index destroy();
		ui.rows[ i ].name destroy();
		ui.rows[ i ].count destroy();
	}
}

/// Shows the vote screen for a few seconds on a living match, for judging its look; nothing is decided.
preview()
{
	list = candidates();

	if ( list.size < 2 )
	{
		return;
	}

	self session( list, 12, false );
}
