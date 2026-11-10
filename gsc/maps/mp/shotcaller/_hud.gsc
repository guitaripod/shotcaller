#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

/// How many kill cards stay in the column at once, newest at the bottom.
cardCount()
{
	return 3;
}

/// The left edge of the column in the 640x480 HUD space, clear of the minimap and the crosshair.
columnX()
{
	return 22;
}

/// The vertical gap between two stacked kill cards.
cardPitch()
{
	return 40;
}

/// The y of the newest card, on the left of the screen clear of the minimap and the score.
cardBaseY()
{
	return 84;
}

/// The y of a card at one age step, where 0 is the newest.
cardY( age )
{
	return cardBaseY() - age * cardPitch();
}

/// The y of the streak chip, a little above the oldest card slot.
chipY()
{
	return cardY( cardCount() ) - 6;
}

/// Shrinks a font so a string fits the card, given the width of one character in that font at scale 1.
fitFont( base, chars, room, perChar )
{
	fitted = room / ( chars * perChar );

	if ( fitted >= base )
	{
		return base;
	}

	if ( fitted < base * 0.74 )
	{
		return base * 0.74;
	}

	return fitted;
}

/// Precaches every shader the overlays and the vote screen draw; must run before the level's first wait.
precache()
{
	shaders = strtok( "white,black,gradient,gradient_fadein,gradient_top,gradient_bottom,line_horizontal,killiconheadshot,killiconmelee,killiconsuicide,waypoint_kill", "," );

	for ( i = 0; i < shaders.size; i++ )
	{
		precacheShader( shaders[ i ] );
	}
}

/// Sets the overlay dvars that the server config has not set, so each group can be switched off or tuned on its own.
defaults()
{
	names = strtok( "sc_hud,sc_hud_kills,sc_hud_streaks,sc_hud_flow,sc_hud_death,sc_hud_widgets,sc_hud_sound,sc_hud_shake", "," );

	for ( i = 0; i < names.size; i++ )
	{
		if ( getdvar( names[ i ] ) == "" )
		{
			setdvar( names[ i ], 1 );
		}
	}

	if ( getdvar( "sc_hud_scale" ) == "" )
	{
		setdvar( "sc_hud_scale", 1 );
	}

	if ( getdvar( "sc_hud_preview" ) == "" )
	{
		setdvar( "sc_hud_preview", "" );
	}
}

/// Starts the per-player overlay lifecycle and the preview command.
init()
{
	defaults();

	level thread onConnect();
	level thread previewLoop();
}

/// Gives every human that connects an overlay state and starts their event tracking.
onConnect()
{
	for ( ;; )
	{
		level waittill( "connected", player );

		if ( isHuman( player ) )
		{
			player thread maps\mp\shotcaller\_hud_events::track();
		}
	}
}

/// Whether this player is a human the overlays are for.
isHuman( player )
{
	return isdefined( player ) && isplayer( player ) && !player is_bot();
}

/// Whether the master switch and this group's switch are both on.
groupOn( group )
{
	return getdvarint( "sc_hud" ) && getdvarint( "sc_hud_" + group );
}

/// The user's size multiplier for every overlay, kept within a sane range.
scale()
{
	value = getdvarfloat( "sc_hud_scale" );

	if ( value < 0.5 )
	{
		return 0.5;
	}

	if ( value > 2 )
	{
		return 2;
	}

	return value;
}

/// Creates one hidden HUD element with its alignment and layer.
elem( horz, vert, alignx, aligny, x, y, sort )
{
	e = newClientHudElem( self );
	e.horzAlign = horz;
	e.vertAlign = vert;
	e.alignX = alignx;
	e.alignY = aligny;
	e.x = x;
	e.y = y;
	e.sort = sort;
	e.alpha = 0;
	e.foreground = true;
	e.hideWhenInMenu = !isdefined( level.sc_voting );

	return e;
}

/// Creates a hidden text element in a font.
textElem( font, size, horz, vert, alignx, aligny, x, y, sort )
{
	e = self elem( horz, vert, alignx, aligny, x, y, sort );
	e.font = font;
	e.fontScale = size;

	return e;
}

/// Creates a hidden shader element.
shaderElem( shader, w, h, horz, vert, alignx, aligny, x, y, sort )
{
	e = self elem( horz, vert, alignx, aligny, x, y, sort );
	e setShader( shader, w, h );

	return e;
}

/// Builds this player's overlay elements the first time they are needed and returns them.
ensure()
{
	if ( isdefined( self.sc_hud ) )
	{
		return self.sc_hud;
	}

	h = spawnstruct();
	h.priority = 0;
	h.lockUntil = 0;
	h.elems = [];
	h.cards = [];
	self.sc_hud = h;
	h.flash = self track( self shaderElem( "white", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 5 ) );
	h.glow = self track( self shaderElem( "white", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 4 ) );

	for ( i = 0; i < cardCount(); i++ )
	{
		h.cards[ i ] = self buildCard( i );
	}

	h.chip = self buildChip();
	h.count = self track( self textElem( "bigfixed", 3.8, "center", "middle", "center", "middle", 0, -132, 24 ) );
	h.count.color = ( 1, 0.42, 0.1 );
	h.count.glowColor = ( 0.6, 0, 0 );
	h.count.glowAlpha = 1;
	h.countPlate = self track( self shaderElem( "black", 86, 70, "center", "middle", "center", "middle", 0, -132, 23 ) );
	h.countLabel = self track( self textElem( "objective", 0.55, "center", "middle", "center", "middle", 0, -164, 24 ) );
	h.countLabel setText( "SECONDS" );
	h.countLabel.color = ( 0.9, 0.86, 0.78 );
	self.sc_hud = h;

	return h;
}

/// Keeps one element in the player's element list so clear() can free everything at once.
track( e )
{
	h = self.sc_hud;
	h.elems[ h.elems.size ] = e;

	return e;
}

/// Makes one kill card: plate, accent bar, icon, title, subtitle and chain chip, all stacked on the column.
buildCard( i )
{
	y = cardY( 0 );
	x = columnX();
	r = spawnstruct();
	r.i = i;
	r.age = 0;
	r.live = false;
	r.plate = self track( self shaderElem( "black", 1, 36, "left", "middle", "left", "middle", x, y, 30 + i ) );
	r.bar = self track( self shaderElem( "white", 4, 36, "left", "middle", "left", "middle", x, y, 33 + i ) );
	r.icon = self track( self shaderElem( "white", 18, 18, "left", "middle", "left", "middle", x + 14, y, 34 + i ) );
	r.title = self track( self textElem( "hudbig", 1.1, "left", "middle", "left", "middle", x + 16, y - 7, 35 + i ) );
	r.sub = self track( self textElem( "objective", 0.62, "left", "middle", "left", "middle", x + 16, y + 10, 35 + i ) );

	return r;
}

/// Makes the persistent streak chip: a label, the count and a bar that fills toward the next milestone.
buildChip()
{
	y = chipY();
	x = columnX();
	c = spawnstruct();
	c.plate = self track( self shaderElem( "black", 122, 26, "left", "middle", "left", "middle", x, y, 26 ) );
	c.label = self track( self textElem( "objective", 0.58, "left", "middle", "left", "middle", x + 12, y, 27 ) );
	c.value = self track( self textElem( "bigfixed", 1.35, "left", "middle", "right", "middle", x + 110, y, 27 ) );
	c.bar = self track( self shaderElem( "white", 110, 2, "left", "middle", "left", "middle", x + 6, y + 9, 28 ) );
	c.label setText( "STREAK" );

	return c;
}

/// Destroys every overlay element so the full screen is free, for example for the map vote.
clear()
{
	if ( !isdefined( self.sc_hud ) )
	{
		return;
	}

	self notify( "sc_banner" );
	self notify( "sc_edge_off" );

	for ( i = 0; i < cardCount(); i++ )
	{
		self notify( "sc_card" + i );
	}

	h = self.sc_hud;

	for ( i = 0; i < h.elems.size; i++ )
	{
		h.elems[ i ] destroy();
	}

	self.sc_hud = undefined;
}

/// Shows a banner by id unless its group is off or a stronger banner is still up.
banner( id )
{
	spec = maps\mp\shotcaller\_hud_theme::spec( id );

	if ( !isdefined( spec ) || !groupOn( spec.group ) )
	{
		return;
	}

	self showBanner( spec, false );
}

/// Plays a banner spec on this player, replacing a weaker one and ignoring the group switches when forced.
showBanner( spec, force )
{
	h = self ensure();

	if ( !force && gettime() < h.lockUntil && spec.priority < h.priority )
	{
		return;
	}

	h.priority = spec.priority;
	h.lockUntil = gettime() + 900;

	self pushCard( spec );
	self playBannerEffects( spec );
}

/// Adds a card at the bottom of the column, slides the older ones up and drops the oldest.
pushCard( spec )
{
	h = self ensure();
	free = undefined;

	for ( i = 0; i < cardCount(); i++ )
	{
		r = h.cards[ i ];

		if ( !r.live )
		{
			if ( !isdefined( free ) )
			{
				free = r;
			}

			continue;
		}

		r.age = r.age + 1;

		if ( r.age >= cardCount() )
		{
			self retireCard( r );
			free = r;
		}
		else
		{
			self dimCard( r, r.age );
		}
	}

	if ( !isdefined( free ) )
	{
		return;
	}

	self fillCard( free, spec );
	free.age = 0;
	free.live = true;
	self notify( "sc_card" + free.i );
	self thread animateCard( spec, free );
}

/// Writes a banner spec into a card's elements, sizes the card to its text and leaves it invisible for the animation.
fillCard( r, spec )
{
	k = scale();
	hasSub = spec.sub != "";
	hasIcon = spec.icon != "";
	left = 16;
	textX = columnX() + left;

	if ( hasIcon )
	{
		left = 38;
		textX = columnX() + left;
	}

	ts = ( 1.3 + 0.28 * ( spec.weight - 1 ) ) * k;
	ss = 0.66 * k;
	room = spec.title.size * 13.2 * ts;

	if ( hasSub && spec.sub.size * 8.4 * ss > room )
	{
		room = spec.sub.size * 8.4 * ss;
	}

	if ( room > 200 )
	{
		room = 200;
	}

	r.w = left + room + 22;

	if ( r.w < 120 )
	{
		r.w = 120;
	}

	r.h = int( 34 + 10 * ( spec.weight - 1 ) );
	up = int( r.h * 0.24 );
	r.plate setShader( "black", 1, r.h );
	r.plate.color = ( 0, 0, 0 );
	r.plate.alpha = 0;
	r.plate.x = columnX();
	r.plate.y = cardY( 0 );
	r.bar setShader( "white", 4, r.h + 20 );
	r.bar.color = spec.accent;
	r.bar.alpha = 0;
	r.bar.x = columnX();
	r.bar.y = cardY( 0 );
	r.icon.x = columnX() + 14;
	r.icon.y = cardY( 0 );
	r.icon.alpha = 0;

	if ( hasIcon )
	{
		r.icon setShader( spec.icon, 18, 18 );
		r.icon.color = spec.color;
	}

	r.title.x = textX;
	r.title.y = cardY( 0 ) - up;
	r.title setText( spec.title );
	r.title.color = ( 0.98, 0.96, 0.91 );

	if ( spec.weight >= 1.35 )
	{
		r.title.color = spec.color;
	}

	r.title.glowColor = spec.glow;
	r.title.glowAlpha = 0.55;
	r.title.fontScale = fitFont( ts, spec.title.size, room, 13.2 );
	r.title.alpha = 0;
	r.titleY = 0 - up;

	r.sub.x = textX;
	r.sub.y = cardY( 0 ) + int( r.h * 0.26 );
	r.sub.alpha = 0;
	r.sub.color = ( 0.86, 0.81, 0.73 );

	if ( hasSub )
	{
		r.sub setText( spec.sub );
		r.sub.fontScale = fitFont( ss, spec.sub.size, room, 8.4 );
	}

	if ( !hasSub )
	{
		r.title.y = cardY( 0 );
		r.titleY = 0;
	}
}

/// Brings one card in: the plate wipes open, the accent bar slams down and the text lands a frame later.
animateCard( spec, r )
{
	self endon( "disconnect" );
	self endon( "sc_card" + r.i );

	k = scale();
	w = r.w;
	ts = r.title.fontScale;
	hasSub = spec.sub != "";

	r.plate.alpha = 0.72;
	r.bar.alpha = 1;

	wait 0.05;

	r.plate scaleOverTime( 0.11, int( w ), r.h );
	r.bar scaleOverTime( 0.13, int( 4 + 2 * ( spec.weight - 1 ) ), r.h + 8 );
	r.title.fontScale = ts * 1.4;
	r.title changeFontScaleOverTime( 0.12 );
	r.title.fontScale = ts;

	if ( spec.icon != "" )
	{
		r.icon fadeOverTime( 0.08 );
		r.icon.alpha = 1;
	}

	r.title fadeOverTime( 0.06 );
	r.title.alpha = 1;

	wait 0.04;

	if ( hasSub )
	{
		r.sub fadeOverTime( 0.1 );
		r.sub.alpha = 1;
	}

	wait spec.hold;

	r.plate fadeOverTime( 0.3 );
	r.plate.alpha = 0;
	r.bar fadeOverTime( 0.3 );
	r.bar.alpha = 0;
	r.icon fadeOverTime( 0.3 );
	r.icon.alpha = 0;
	r.title fadeOverTime( 0.3 );
	r.title.alpha = 0;
	r.sub fadeOverTime( 0.3 );
	r.sub.alpha = 0;
	wait 0.32;
	r.live = false;
}

/// Moves a card up one slot, dims it and lets it fade out on its own so the column reads as a short log.
dimCard( r, age )
{
	self notify( "sc_card" + r.i );
	self thread fadeCard( r, age );
}

/// Slides a card to its new slot, keeps a little of it on screen, then fades it away.
fadeCard( r, age )
{
	self endon( "disconnect" );
	self endon( "sc_card" + r.i );

	y = cardY( age );
	r.plate moveOverTime( 0.16 );
	r.plate.y = y;
	r.bar moveOverTime( 0.16 );
	r.bar.y = y;
	r.icon moveOverTime( 0.16 );
	r.icon.y = y;
	r.title moveOverTime( 0.16 );
	r.title.y = y + r.titleY;
	r.sub moveOverTime( 0.16 );
	r.sub.y = y + 8;
	r.plate fadeOverTime( 0.16 );
	r.plate.alpha = 0.48;
	r.bar fadeOverTime( 0.16 );
	r.bar.alpha = 0.5;
	r.icon fadeOverTime( 0.16 );
	r.icon.alpha = 0.55;
	r.title fadeOverTime( 0.16 );
	r.title.alpha = 0.72;
	r.sub fadeOverTime( 0.16 );
	r.sub.alpha = 0.55;
	wait 1.8;

	r.plate fadeOverTime( 0.35 );
	r.plate.alpha = 0;
	r.bar fadeOverTime( 0.35 );
	r.bar.alpha = 0;
	r.icon fadeOverTime( 0.35 );
	r.icon.alpha = 0;
	r.title fadeOverTime( 0.35 );
	r.title.alpha = 0;
	r.sub fadeOverTime( 0.35 );
	r.sub.alpha = 0;
	wait 0.4;
	r.live = false;
}

/// Hides a card at once when a fourth event needs its slot.
retireCard( r )
{
	self notify( "sc_card" + r.i );
	r.live = false;
	r.plate.alpha = 0;
	r.bar.alpha = 0;
	r.icon.alpha = 0;
	r.title.alpha = 0;
	r.sub.alpha = 0;
}

/// The extras that go with a banner: screen flash, camera shake and a sound, each behind its own switch.
playBannerEffects( spec )
{
	if ( spec.flash > 0 )
	{
		self flash( spec.flashColor, spec.flash, 0.55 );
	}

	if ( spec.shake > 0 && getdvarint( "sc_hud_shake" ) )
	{
		earthquake( spec.shake, 0.6, self.origin, 800 );
	}

	if ( spec.sound != "" && getdvarint( "sc_hud_sound" ) )
	{
		self playLocalSound( spec.sound );
	}
}

/// Flashes a full-screen tint that fades out.
flash( color, alpha, seconds )
{
	h = self ensure();

	h.flash.color = color;
	h.flash.alpha = alpha;
	h.flash fadeOverTime( seconds );
	h.flash.alpha = 0;
}

/// The color the streak chip and its bar take at a given streak.
streakColor( count )
{
	if ( count >= 15 )
	{
		return ( 1, 0.1, 0.02 );
	}

	if ( count >= 10 )
	{
		return ( 1, 0.24, 0.05 );
	}

	if ( count >= 5 )
	{
		return ( 1, 0.42, 0.08 );
	}

	return ( 1, 0.62, 0.15 );
}

/// The next streak milestone, which the chip bar fills toward.
streakTarget( count )
{
	if ( count < 3 )
	{
		return 3;
	}

	if ( count < 5 )
	{
		return 5;
	}

	if ( count < 7 )
	{
		return 7;
	}

	if ( count < 10 )
	{
		return 10;
	}

	if ( count < 15 )
	{
		return 15;
	}

	if ( count < 20 )
	{
		return 20;
	}

	return 25;
}

/// Updates the streak chip, and starts or stops the red edge glow that marks a hot streak.
streak( count )
{
	if ( !groupOn( "widgets" ) )
	{
		return;
	}

	h = self ensure();
	c = h.chip;

	if ( count < 2 )
	{
		c.plate.alpha = 0;
		c.label.alpha = 0;
		c.value.alpha = 0;
		c.bar.alpha = 0;
		self edgeOff();
		return;
	}

	color = self streakColor( count );
	c.plate.alpha = 0.45;
	c.label.alpha = 0.8;
	c.value.alpha = 1;
	c.value setValue( count );
	c.value.color = color;
	c.value.fontScale = 1.7;
	c.value changeFontScaleOverTime( 0.18 );
	c.value.fontScale = 1.35;
	c.bar.color = color;
	c.bar.alpha = 0.9;
	target = self streakTarget( count );
	c.bar scaleOverTime( 0.2, int( 110 * count / target ), 2 );

	if ( count >= 5 && !isdefined( self.sc_edge ) )
	{
		self.sc_edge = true;
		self thread edgeGlow();
	}
}

/// Pulses a faint red tint over the whole screen until the streak ends, so a hot streak feels hot.
edgeGlow()
{
	self endon( "disconnect" );
	self endon( "sc_edge_off" );

	h = self.sc_hud;
	h.glow.color = ( 1, 0.04, 0.02 );

	for ( ;; )
	{
		h.glow fadeOverTime( 0.8 );
		h.glow.alpha = 0.09;
		wait 0.8;
		h.glow fadeOverTime( 0.8 );
		h.glow.alpha = 0.02;
		wait 0.8;
	}
}

/// Ends the streak glow so a later streak can start it again.
edgeOff()
{
	self notify( "sc_edge_off" );
	self.sc_edge = undefined;

	if ( isdefined( self.sc_hud ) )
	{
		self.sc_hud.glow.alpha = 0;
	}
}

/// Shows one big countdown number low on the screen for the last seconds of the match, or hides it at zero.
countdown( n )
{
	if ( !groupOn( "flow" ) )
	{
		return;
	}

	h = self ensure();

	if ( n <= 0 )
	{
		h.count.alpha = 0;
		h.countLabel.alpha = 0;
		h.countPlate.alpha = 0;
		return;
	}

	h.countPlate.alpha = 0.5;
	h.count setValue( n );
	h.count.alpha = 1;
	h.count.fontScale = 4.6 * scale();
	h.count changeFontScaleOverTime( 0.28 );
	h.count.fontScale = 3.8 * scale();
	h.countLabel.alpha = 0.8;
}

/// Watches the preview dvar and plays what it names on every human, so a style can be judged without playing for it.
previewLoop()
{
	for ( ;; )
	{
		wait 0.5;

		name = getdvar( "sc_hud_preview" );

		if ( name == "" )
		{
			continue;
		}

		setdvar( "sc_hud_preview", "" );
		level thread preview( name );
	}
}

/// Plays a named preview on every human: a banner id, `all`, `streak`, `countdown` or `vote`.
preview( name )
{
	players = level.players;

	for ( i = 0; i < players.size; i++ )
	{
		if ( isHuman( players[ i ] ) )
		{
			players[ i ] thread previewOne( name );
		}
	}
}

/// Plays one preview on one player.
previewOne( name )
{
	self endon( "disconnect" );

	if ( name == "all" )
	{
		ids = maps\mp\shotcaller\_hud_theme::allIds();

		for ( i = 0; i < ids.size; i++ )
		{
			self showBanner( maps\mp\shotcaller\_hud_theme::spec( ids[ i ] ), true );
			wait 2.4;
		}
	}
	else if ( name == "streak" )
	{
		for ( n = 1; n <= 8; n++ )
		{
			self streak( n );
			wait 0.8;
		}

		self streak( 0 );
		self edgeOff();
	}
	else if ( name == "kills" )
	{
		for ( n = 1; n <= 6; n++ )
		{
			hitloc = "torso_upper";

			if ( n % 2 == 0 )
			{
				hitloc = "head";
			}

			self maps\mp\shotcaller\_hud_events::killed( undefined, "m4a1_mp", "MOD_RIFLE_BULLET", hitloc, self.origin + ( 400, 0, 0 ), false, 0 );
			wait 1.1;
		}

		self streak( 0 );
		self edgeOff();
	}
	else if ( name == "edge" )
	{
		self streak( 6 );
		wait 8;
		self streak( 0 );
		self edgeOff();
	}
	else if ( name == "countdown" )
	{
		for ( n = 10; n >= 0; n-- )
		{
			self countdown( n );
			wait 1;
		}
	}
	else if ( name == "vote" )
	{
		self maps\mp\shotcaller\_mapvote::preview();
	}
	else
	{
		spec = maps\mp\shotcaller\_hud_theme::spec( name );

		if ( isdefined( spec ) )
		{
			self showBanner( spec, true );
		}
	}
}
