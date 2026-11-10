#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// Starts the match-flow watchers: the opening banner, the clock warnings, lead changes and match point.
init()
{
	level thread flowEnd();
	level thread flowStart();
	level thread flowClock();
	level thread flowScore();
}

/// Marks the match as over so the flow watchers stop talking.
flowEnd()
{
	level waittill( "game_ended" );

	level.sc_ended = true;
}

/// Gives a human fresh kill, streak and revenge counters for this map.
track()
{
	self.sc_stats = spawnstruct();
	self.sc_stats.streak = 0;
	self.sc_stats.multi = 0;
	self.sc_stats.lastKillAt = -100000;
	self.sc_stats.deathsInRow = 0;
	self.sc_stats.killedBy = -1;
}

/// Entry point from the kill callback: updates whichever of the victim and the attacker is human.
onKill( victim, attacker, weapon, means, hitloc, where )
{
	first = !isdefined( level.sc_firstblood );
	level.sc_firstblood = true;

	victimStreak = streakOf( victim );

	if ( isdefined( victim ) && maps\mp\shotcaller\_hud::isHuman( victim ) )
	{
		victim thread died( attacker );
	}

	if ( isdefined( attacker ) && isplayer( attacker ) && attacker != victim && maps\mp\shotcaller\_hud::isHuman( attacker ) )
	{
		attacker thread killed( victim, weapon, means, hitloc, where, first, victimStreak );
	}
}

/// The streak a player was on before this death, read from the game's own counter.
streakOf( player )
{
	if ( isdefined( player ) && isdefined( player.pers ) && isdefined( player.pers[ "cur_kill_streak" ] ) )
	{
		return player.pers[ "cur_kill_streak" ];
	}

	return 0;
}

/// A human died: end the streak, flash red and note who did it for a later payback.
died( attacker )
{
	self endon( "disconnect" );

	if ( !isdefined( self.sc_stats ) )
	{
		self track();
	}

	s = self.sc_stats;
	lost = s.streak;
	s.streak = 0;
	s.multi = 0;
	s.deathsInRow++;
	s.killedBy = -1;

	if ( isdefined( attacker ) && isplayer( attacker ) && attacker != self )
	{
		s.killedBy = attacker getentitynumber();
	}

	self maps\mp\shotcaller\_hud::streak( 0 );
	self maps\mp\shotcaller\_hud::edgeOff();

	if ( maps\mp\shotcaller\_hud::groupOn( "death" ) )
	{
		self maps\mp\shotcaller\_hud::flash( ( 0.75, 0, 0 ), 0.3, 0.9 );

		if ( lost >= 3 )
		{
			self maps\mp\shotcaller\_hud::banner( "streaklost" );
		}
	}
}

/// A human got a kill: work out everything worth announcing and show the single best banner.
killed( victim, weapon, means, hitloc, where, first, victimStreak )
{
	self endon( "disconnect" );

	if ( !isdefined( self.sc_stats ) )
	{
		self track();
	}

	s = self.sc_stats;
	now = gettime();

	if ( now - s.lastKillAt <= 4500 )
	{
		s.multi++;
	}
	else
	{
		s.multi = 1;
	}

	s.lastKillAt = now;
	s.streak++;
	earlierDeaths = s.deathsInRow;
	s.deathsInRow = 0;

	self maps\mp\shotcaller\_hud::streak( s.streak );

	ids = [];
	ids[ ids.size ] = multiId( s.multi );
	ids[ ids.size ] = streakId( s.streak );
	ids[ ids.size ] = self specialId( victim, means, hitloc, where, first, victimStreak, earlierDeaths );

	if ( isdefined( victim ) && victim getentitynumber() == s.killedBy )
	{
		ids[ ids.size ] = "payback";
		s.killedBy = -1;
	}

	if ( means == "MOD_MELEE" )
	{
		ids[ ids.size ] = "glory";
	}

	self announce( ids );
}

/// Picks the strongest banner among the ids, adds the runner-up as its subtitle and shows it.
announce( ids )
{
	best = "";
	second = "";
	bestPriority = -1;
	secondPriority = -1;

	for ( i = 0; i < ids.size; i++ )
	{
		spec = maps\mp\shotcaller\_hud_theme::spec( ids[ i ] );

		if ( !isdefined( spec ) )
		{
			continue;
		}

		if ( spec.priority > bestPriority )
		{
			second = best;
			secondPriority = bestPriority;
			best = ids[ i ];
			bestPriority = spec.priority;
		}
		else if ( spec.priority > secondPriority )
		{
			second = ids[ i ];
			secondPriority = spec.priority;
		}
	}

	if ( best == "" )
	{
		return;
	}

	spec = maps\mp\shotcaller\_hud_theme::spec( best );

	if ( second != "" && spec.sub == "" )
	{
		runnerUp = maps\mp\shotcaller\_hud_theme::spec( second );
		spec.sub = runnerUp.title;
	}

	if ( maps\mp\shotcaller\_hud::groupOn( spec.group ) )
	{
		self maps\mp\shotcaller\_hud::showBanner( spec, false );
	}
}

/// The multi-kill banner for a number of kills inside the window, or an empty id.
multiId( count )
{
	if ( count >= 5 )
	{
		return "ripandtear";
	}

	if ( count == 4 )
	{
		return "quad";
	}

	if ( count == 3 )
	{
		return "triple";
	}

	if ( count == 2 )
	{
		return "double";
	}

	return "";
}

/// The streak banner when a kills-without-dying total hits a milestone, or an empty id.
streakId( count )
{
	switch ( count )
	{
		case 3: return "spree";
		case 5: return "rampage";
		case 7: return "dominating";
		case 10: return "unstoppable";
		case 15: return "godlike";
		case 20: return "slayer";
	}

	return "";
}

/// The best single-kill banner for how this kill happened, or an empty id.
specialId( victim, means, hitloc, where, first, victimStreak, earlierDeaths )
{
	range = distance( self.origin, where );
	explosive = ( means == "MOD_GRENADE_SPLASH" || means == "MOD_EXPLOSIVE" || means == "MOD_PROJECTILE_SPLASH" || means == "MOD_PROJECTILE" || means == "MOD_GRENADE" );

	if ( first )
	{
		return "firstblood";
	}

	if ( victimStreak >= 5 )
	{
		return "shutdown";
	}

	if ( earlierDeaths >= 4 )
	{
		return "comeback";
	}

	if ( means != "MOD_MELEE" && !explosive && range >= 1800 )
	{
		return "longshot";
	}

	if ( hitloc == "head" || hitloc == "helmet" )
	{
		return "headshot";
	}

	if ( explosive )
	{
		return "explosive";
	}

	if ( means != "MOD_MELEE" && range <= 140 )
	{
		return "pointblank";
	}

	return "";
}

/// The humans currently connected.
humans()
{
	result = [];

	for ( i = 0; i < level.players.size; i++ )
	{
		if ( maps\mp\shotcaller\_hud::isHuman( level.players[ i ] ) )
		{
			result[ result.size ] = level.players[ i ];
		}
	}

	return result;
}

/// Opens the match with a FIGHT banner naming the map and mode.
flowStart()
{
	level waittill( "prematch_over" );

	if ( !maps\mp\shotcaller\_hud::groupOn( "flow" ) )
	{
		return;
	}

	players = humans();

	for ( i = 0; i < players.size; i++ )
	{
		spec = maps\mp\shotcaller\_hud_theme::spec( "fight" );
		spec.sub = maps\mp\shotcaller\_mapnames::label( getdvar( "mapname" ) ) + " - " + maps\mp\shotcaller\_mapnames::gametype( getdvar( "g_gametype" ) );
		players[ i ] maps\mp\shotcaller\_hud::showBanner( spec, false );
	}
}

/// Warns at one minute and thirty seconds, and counts the last ten seconds down on screen.
flowClock()
{
	level waittill( "prematch_over" );

	limit = getdvarfloat( "scr_" + getdvar( "g_gametype" ) + "_timelimit" ) * 60;

	if ( limit <= 0 )
	{
		return;
	}

	started = gettime();
	warnedMinute = false;
	warnedHalf = false;

	for ( ;; )
	{
		wait 1;

		if ( isdefined( level.sc_ended ) )
		{
			return;
		}

		remaining = limit - ( gettime() - started ) / 1000;

		if ( remaining <= 60 && !warnedMinute && limit > 90 )
		{
			warnedMinute = true;
			announceAll( "minute" );
		}

		if ( remaining <= 30 && !warnedHalf && limit > 45 )
		{
			warnedHalf = true;
			announceAll( "half" );
		}

		if ( remaining <= 10 )
		{
			countAll( int( remaining ) + 1 );
		}
	}
}

/// Shows a banner id to every human.
announceAll( id )
{
	players = humans();

	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] maps\mp\shotcaller\_hud::banner( id );
	}
}

/// The score at which the match point banner fires: three kills from the limit, but never below 85 percent of it.
matchPoint( limit )
{
	near = limit - 300;

	if ( near < limit * 0.85 )
	{
		return limit * 0.85;
	}

	return near;
}

/// Shows a banner id to every human with a subtitle made at runtime, such as the real score limit.
announceAllSub( id, sub )
{
	spec = maps\mp\shotcaller\_hud_theme::spec( id );

	if ( !isdefined( spec ) || !maps\mp\shotcaller\_hud::groupOn( spec.group ) )
	{
		return;
	}

	spec.sub = sub;
	players = humans();

	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] maps\mp\shotcaller\_hud::showBanner( spec, false );
	}
}

/// Shows the countdown number to every human.
countAll( n )
{
	players = humans();

	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] maps\mp\shotcaller\_hud::countdown( n );
	}
}

/// Announces lead changes to each human and match point to everyone, polling the team scores once a second.
flowScore()
{
	level waittill( "prematch_over" );

	limit = getdvarint( "scr_" + getdvar( "g_gametype" ) + "_scorelimit" );
	pointShown = false;

	for ( ;; )
	{
		wait 1;

		if ( isdefined( level.sc_ended ) )
		{
			return;
		}

		allies = maps\mp\shotcaller\_telemetry::teamScore( "allies" );
		axis = maps\mp\shotcaller\_telemetry::teamScore( "axis" );
		players = humans();

		for ( i = 0; i < players.size; i++ )
		{
			players[ i ] leadCheck( allies, axis );
		}

		if ( limit > 0 && !pointShown && ( allies >= matchPoint( limit ) || axis >= matchPoint( limit ) ) )
		{
			pointShown = true;
			announceAllSub( "matchpoint", "FIRST TO " + limit );
		}
	}
}

/// Announces when this human's team takes the lead or loses it, ignoring the first few kills.
leadCheck( allies, axis )
{
	team = self.pers[ "team" ];

	if ( team != "allies" && team != "axis" )
	{
		return;
	}

	mine = allies;
	theirs = axis;

	if ( team == "axis" )
	{
		mine = axis;
		theirs = allies;
	}

	state = 0;

	if ( mine > theirs )
	{
		state = 1;
	}
	else if ( mine < theirs )
	{
		state = -1;
	}

	previous = 0;

	if ( isdefined( self.sc_lead ) )
	{
		previous = self.sc_lead;
	}

	self.sc_lead = state;

	if ( state == 1 && previous != 1 && mine >= 300 )
	{
		self maps\mp\shotcaller\_hud::banner( "lead" );
	}
	else if ( state == -1 && previous == 1 )
	{
		self maps\mp\shotcaller\_hud::banner( "leadlost" );
	}
}
