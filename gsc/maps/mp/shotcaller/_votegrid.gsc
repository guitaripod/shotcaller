/// Draws the map vote as a grid of every map with a mouse cursor.
///
/// The game allows only a few dozen HUD elements per player and about as many shared ones, so a
/// tile per map is impossible. Each grid column is one text element holding its maps one per line, and
/// a single highlight bar is moved to the map under the cursor. The mouse is read as view angle: the
/// player is put back in the playing state, where the view turns freely and the end-of-match scoreboard
/// is not drawn, and the angles are put back to the centre every frame so the turn since the last frame
/// is the mouse motion.

/// Chooses the grid shape for a number of maps: columns filled top to bottom, left to right.
layout( count )
{
	g = spawnstruct();
	g.count = count;
	g.cols = 7;

	if ( count <= 6 )
	{
		g.cols = 1;
	}
	else if ( count <= 20 )
	{
		g.cols = 4;
	}
	else if ( count <= 36 )
	{
		g.cols = 5;
	}

	g.rows = int( ( count + g.cols - 1 ) / g.cols );
	g.w = 90;
	g.h = 12 * getdvarfloat( "sc_vote_font" );
	g.width = g.cols * g.w;
	g.height = g.rows * g.h;
	g.left = 0 - g.width / 2;
	g.top = -150 + ( 8 - g.rows ) * g.h / 2;

	return g;
}

/// The horizontal centre of a map's cell.
tileX( g, index )
{
	return g.left + int( index / g.rows ) * g.w + g.w / 2;
}

/// The vertical centre of a map's cell.
tileY( g, index )
{
	return g.top + ( index % g.rows ) * g.h + g.h / 2;
}

/// The map under a point, or -1 outside the grid or past the last map.
tileAt( g, x, y )
{
	dx = x - g.left;
	dy = y - g.top;

	if ( dx < 0 || dy < 0 || dx >= g.width || dy >= g.height )
	{
		return -1;
	}

	index = int( dx / g.w ) * g.rows + int( dy / g.h );

	if ( index >= g.count )
	{
		return -1;
	}

	return index;
}

/// The names of the maps in one column, one per line.
columnText( list, g, col )
{
	text = "";
	first = col * g.rows;

	for ( i = first; i < first + g.rows && i < list.size; i++ )
	{
		if ( i > first )
		{
			text += "\n";
		}

		text += maps\mp\shotcaller\_mapnames::shortLabel( list[ i ] );
	}

	return text;
}

/// Builds this player's vote screen: backdrop, title, timer, the map columns, highlights and the game master's mark.
build( list, gm )
{
	ui = spawnstruct();
	ui.list = list;
	ui.grid = layout( list.size );
	g = ui.grid;

	ui.dim = self maps\mp\shotcaller\_hud::shaderElem( "black", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 40 );
	ui.dim.alpha = 0.96;
	ui.title = self maps\mp\shotcaller\_hud::textElem( "hudbig", 1.3, "center", "middle", "left", "middle", -300, -207, 45 );
	ui.title setText( "VOTE FOR THE NEXT MAP" );
	ui.title.color = ( 1, 0.4, 0.08 );
	ui.title.glowColor = ( 0.55, 0, 0 );
	ui.title.glowAlpha = 1;
	ui.title.alpha = 1;
	ui.timer = self maps\mp\shotcaller\_hud::textElem( "hudbig", 2, "center", "middle", "right", "middle", 300, -207, 45 );
	ui.timer.color = ( 1, 0.85, 0.3 );
	ui.timer.alpha = 1;
	ui.rule = self maps\mp\shotcaller\_hud::shaderElem( "white", 604, 2, "center", "middle", "center", "middle", 0, -185, 45 );
	ui.rule.color = ( 1, 0.3, 0.05 );
	ui.rule.alpha = 0.9;
	ui.hoverName = self maps\mp\shotcaller\_hud::textElem( "hudbig", 1.7, "center", "middle", "center", "middle", 0, 12, 45 );
	ui.hoverName.color = ( 1, 0.62, 0.2 );
	ui.hoverName.glowColor = ( 0.5, 0.1, 0 );
	ui.hoverName.glowAlpha = 1;
	ui.hoverSub = self maps\mp\shotcaller\_hud::textElem( "objective", 1.05, "center", "middle", "center", "middle", 0, 44, 45 );
	ui.hoverSub.color = ( 0.85, 0.85, 0.85 );
	ui.hint = self maps\mp\shotcaller\_hud::textElem( "objective", 1, "center", "middle", "center", "middle", 0, 190, 45 );
	ui.hint setText( "MOVE THE MOUSE    CLICK A MAP TO VOTE    CLICK IT AGAIN TO WITHDRAW" );
	ui.hint.color = ( 0.75, 0.75, 0.75 );
	ui.hint.alpha = 1;
	ui.board = self maps\mp\shotcaller\_hud::textElem( "objective", 1.1, "center", "middle", "center", "middle", 0, 150, 45 );
	ui.board.color = ( 1, 0.8, 0.25 );
	ui.board.alpha = 1;
	ui.gm = gm;
	ui.shown = "";
	ui.counts = [];
	ui.named = -2;
	ui.hoverBox = self maps\mp\shotcaller\_hud::shaderElem( "white", g.w - 4, int( g.h ), "center", "middle", "center", "middle", 0, 0, 43 );
	ui.hoverBox.color = ( 1, 0.4, 0.06 );
	ui.mineBox = self maps\mp\shotcaller\_hud::shaderElem( "white", g.w - 4, int( g.h ), "center", "middle", "center", "middle", 0, 0, 42 );
	ui.mineBox.color = ( 0.1, 0.65, 0.18 );
	ui.cols = [];

	for ( c = 0; c < g.cols; c++ )
	{
		col = self maps\mp\shotcaller\_hud::textElem( "objective", getdvarfloat( "sc_vote_font" ), "center", "middle", "left", "top", g.left + c * g.w + 6, g.top, 46 );
		col setText( columnText( list, g, c ) );
		col.color = ( 0.9, 0.9, 0.9 );
		col.alpha = 1;
		ui.cols[ c ] = col;
	}

	if ( gm >= 0 )
	{
		ui.gmBar = self maps\mp\shotcaller\_hud::shaderElem( "white", g.w - 4, 2, "center", "middle", "center", "middle", tileX( g, gm ), tileY( g, gm ) + g.h / 2 - 1, 44 );
		ui.gmBar.color = ( 1, 0.78, 0.15 );
		ui.gmBar.alpha = 1;
		ui.note = self maps\mp\shotcaller\_hud::textElem( "objective", 1, "center", "middle", "center", "middle", 0, 112, 45 );
		ui.note setText( "GAME MASTER PICK: " + maps\mp\shotcaller\_mapnames::label( list[ gm ] ) );
		ui.note.color = ( 1, 0.78, 0.15 );
		ui.note.alpha = 1;
	}

	return ui;
}

/// Shows the leading maps and their votes on one line.
showCounts( ui, counts )
{
	ui.counts = counts;
	best = [];
	text = "";

	for ( round = 0; round < 3; round++ )
	{
		top = -1;

		for ( i = 0; i < counts.size; i++ )
		{
			if ( counts[ i ] > 0 && !inList( best, i ) && ( top < 0 || counts[ i ] > counts[ top ] ) )
			{
				top = i;
			}
		}

		if ( top < 0 )
		{
			break;
		}

		best[ best.size ] = top;
		text += maps\mp\shotcaller\_mapnames::label( ui.list[ top ] ) + " " + counts[ top ] + "     ";
	}

	if ( text == "" )
	{
		text = "NO VOTES YET";
	}

	if ( text != ui.shown )
	{
		ui.shown = text;
		ui.board setText( text );
	}
}

/// Whether a number is in an array.
inList( list, value )
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

/// Holds the result on screen: the winning map lit in gold and the title naming the next map.
showWinner( ui, best )
{
	ui.timer.alpha = 0;
	ui.hint.alpha = 0;
	ui.hoverName.alpha = 0;
	ui.hoverSub.alpha = 0;
	ui.hoverBox.alpha = 0;
	ui.mineBox.alpha = 0;

	if ( isdefined( ui.note ) )
	{
		ui.note.alpha = 0;
		ui.gmBar.alpha = 0;
	}

	if ( best < 0 )
	{
		ui.title setText( "NO VOTES: ROTATION CONTINUES" );
		return;
	}

	for ( c = 0; c < ui.cols.size; c++ )
	{
		ui.cols[ c ].alpha = 0.3;
	}

	ui.hoverBox setShader( "white", ui.grid.w - 4, int( ui.grid.h ) );
	ui.hoverBox.x = tileX( ui.grid, best );
	ui.hoverBox.y = tileY( ui.grid, best );
	ui.hoverBox.color = ( 0.85, 0.6, 0.05 );
	ui.hoverBox.alpha = 0.9;
	ui.title setText( "NEXT MAP: " + maps\mp\shotcaller\_mapnames::label( ui.list[ best ] ) );
	ui.title.color = ( 1, 0.85, 0.3 );
}

/// Destroys this player's vote screen.
teardown( ui )
{
	ui.dim destroy();
	ui.title destroy();
	ui.timer destroy();
	ui.rule destroy();
	ui.hint destroy();
	ui.board destroy();
	ui.hoverName destroy();
	ui.hoverSub destroy();
	ui.hoverBox destroy();
	ui.mineBox destroy();

	for ( c = 0; c < ui.cols.size; c++ )
	{
		ui.cols[ c ] destroy();
	}

	if ( isdefined( ui.note ) )
	{
		ui.note destroy();
		ui.gmBar destroy();
	}
}

/// Creates this player's cursor: a white cross with a dark outline.
pointer( ui )
{
	p = spawnstruct();
	p.x = 0;
	p.y = ui.grid.top + ui.grid.height / 2;
	p.hover = -1;
	p.yaw = 0;
	p.shadowH = self maps\mp\shotcaller\_hud::shaderElem( "white", 18, 4, "center", "middle", "center", "middle", 0, 0, 90 );
	p.shadowV = self maps\mp\shotcaller\_hud::shaderElem( "white", 4, 18, "center", "middle", "center", "middle", 0, 0, 90 );
	p.barH = self maps\mp\shotcaller\_hud::shaderElem( "white", 14, 2, "center", "middle", "center", "middle", 0, 0, 91 );
	p.barV = self maps\mp\shotcaller\_hud::shaderElem( "white", 2, 14, "center", "middle", "center", "middle", 0, 0, 91 );
	p.shadowH.color = ( 0, 0, 0 );
	p.shadowV.color = ( 0, 0, 0 );
	p.shadowH.alpha = 0.85;
	p.shadowV.alpha = 0.85;
	p.barH.alpha = 1;
	p.barV.alpha = 1;
	self placeCursor( p );

	return p;
}

/// Hides this player's cursor.
hidePointer( p )
{
	p.shadowH.alpha = 0;
	p.shadowV.alpha = 0;
	p.barH.alpha = 0;
	p.barV.alpha = 0;
}

/// Destroys this player's cursor.
dropPointer( p )
{
	p.shadowH destroy();
	p.shadowV destroy();
	p.barH destroy();
	p.barV destroy();
}

/// Moves the cursor elements to the pointer position.
placeCursor( p )
{
	p.shadowH.x = p.x;
	p.shadowH.y = p.y;
	p.shadowV.x = p.x;
	p.shadowV.y = p.y;
	p.barH.x = p.x;
	p.barH.y = p.y;
	p.barV.x = p.x;
	p.barV.y = p.y;
}

/// Puts the player where the view turns freely, which also hides the end-of-match scoreboard, and silences the weapon so a click does not fire it.
takeLook( p )
{
	self disableWeapons();
	self.sessionstate = "playing";
	p.yaw = 0;
	self setPlayerAngles( ( 0, p.yaw, 0 ) );
}

/// Gives the player back the state the end of the match put them in.
giveBackLook()
{
	self.sessionstate = "intermission";
}

/// Moves the cursor by the mouse motion since the last frame, then centres the view again.
mouse( p, g, sens )
{
	if ( self.sessionstate != "playing" )
	{
		self.sessionstate = "playing";
		self setPlayerAngles( ( 0, p.yaw, 0 ) );
		return;
	}

	a = self getPlayerAngles();
	turn = a[ 1 ] - p.yaw;

	if ( turn > 180 )
	{
		turn -= 360;
	}
	else if ( turn < -180 )
	{
		turn += 360;
	}

	self setPlayerAngles( ( 0, p.yaw, 0 ) );
	p.x = clampTo( p.x - turn * sens, -316, 316 );
	p.y = clampTo( p.y + a[ 0 ] * sens, -236, 236 );
}

/// Keeps a number between two bounds.
clampTo( value, low, high )
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

/// Plays a scripted sweep over the grid in place of the mouse, for previews where the player is still in a match.
sweep( p, g, now )
{
	t = now / 1000;
	p.x = sin( t * 40 ) * ( g.width / 2 - 6 );
	p.y = g.top + g.height / 2 + cos( t * 31 ) * ( g.height / 2 - 4 );
}

/// Paints the hover highlight under the cursor and the highlight on this player's vote.
paint( ui, p, vote )
{
	g = ui.grid;
	hover = tileAt( g, p.x, p.y );
	ui.hoverBox.alpha = 0;

	if ( hover >= 0 )
	{
		ui.hoverBox.x = tileX( g, hover );
		ui.hoverBox.y = tileY( g, hover );
		ui.hoverBox.alpha = 0.42;
	}

	ui.mineBox.alpha = 0;

	if ( isdefined( vote ) && vote >= 0 )
	{
		ui.mineBox.x = tileX( g, vote );
		ui.mineBox.y = tileY( g, vote );
		ui.mineBox.alpha = 0.5;
	}

	self nameHover( ui, hover );
	p.hover = hover;
	self placeCursor( p );
}

/// Shows the hovered map's name large with its vote count; clears the label over a gap.
nameHover( ui, hover )
{
	votes = 0;

	if ( hover >= 0 && hover < ui.counts.size )
	{
		votes = ui.counts[ hover ];
	}

	key = hover * 1000 + votes;

	if ( key == ui.named )
	{
		return;
	}

	ui.named = key;
	ui.hoverName.alpha = 0;
	ui.hoverSub.alpha = 0;

	if ( hover < 0 )
	{
		return;
	}

	ui.hoverName setText( maps\mp\shotcaller\_mapnames::label( ui.list[ hover ] ) );
	ui.hoverName.alpha = 1;
	ui.hoverSub setText( votesLabel( votes ) );
	ui.hoverSub.alpha = 1;
}

/// The words for a vote count.
votesLabel( votes )
{
	if ( votes == 0 )
	{
		return "NO VOTES YET";
	}

	if ( votes == 1 )
	{
		return "1 VOTE";
	}

	return votes + " VOTES";
}
