#include maps\mp\bots\_bot_utility;
#include maps\mp\shotcaller\_log;

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
	h.flash = self shaderElem( "white", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 5 );
	h.glow = self shaderElem( "white", 640, 480, "fullscreen", "fullscreen", "left", "top", 0, 0, 4 );
	h.strip = self shaderElem( "black", 40, 68, "fullscreen", "middle", "center", "middle", 320, -100, 20 );
	h.lineTop = self shaderElem( "white", 40, 2, "fullscreen", "middle", "center", "middle", 320, -134, 21 );
	h.lineBottom = self shaderElem( "white", 40, 2, "fullscreen", "middle", "center", "middle", 320, -66, 21 );
	h.icon = self shaderElem( "white", 36, 36, "center", "middle", "center", "middle", -280, -100, 31 );
	h.title = self textElem( "hudbig", 1.9, "center", "middle", "center", "middle", 0, -100, 30 );
	h.sub = self textElem( "objective", 1.4, "center", "middle", "center", "middle", 0, -78, 30 );
	h.streakLabel = self textElem( "objective", 1.15, "right", "middle", "right", "middle", -22, -36, 12 );
	h.streakValue = self textElem( "hudbig", 2.4, "right", "middle", "right", "middle", -22, -8, 12 );
	h.count = self textElem( "hudbig", 3.2, "center", "middle", "center", "middle", 0, -176, 22 );
	h.streakLabel setText( "KILL STREAK" );
	h.streakLabel.color = ( 1, 0.55, 0.15 );
	h.streakValue.color = ( 1, 0.3, 0.06 );
	h.streakValue.glowColor = ( 0.5, 0, 0 );
	h.streakValue.glowAlpha = 1;
	h.count.color = ( 1, 0.25, 0.08 );
	h.count.glowColor = ( 0.6, 0, 0 );
	h.count.glowAlpha = 1;
	self.sc_hud = h;

	return h;
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

	h = self.sc_hud;
	h.flash destroy();
	h.glow destroy();
	h.strip destroy();
	h.lineTop destroy();
	h.lineBottom destroy();
	h.icon destroy();
	h.title destroy();
	h.sub destroy();
	h.streakLabel destroy();
	h.streakValue destroy();
	h.count destroy();

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

	self notify( "sc_banner" );
	self thread playBanner( spec );
}

/// Animates one banner: the strip opens, the title slams in, the subtitle follows, then everything fades.
playBanner( spec )
{
	self endon( "disconnect" );
	self endon( "sc_banner" );

	h = self.sc_hud;
	k = scale() * spec.weight;
	hasSub = spec.sub != "";
	titleY = -100;

	if ( hasSub )
	{
		titleY = -112;
	}

	h.strip setShader( "black", 40, 68 );
	h.strip.alpha = 0.62;
	h.strip.color = ( 0.05, 0, 0 );
	h.lineTop setShader( "white", 40, 2 );
	h.lineTop.color = spec.accent;
	h.lineTop.alpha = 0.95;
	h.lineBottom setShader( "white", 40, 2 );
	h.lineBottom.color = spec.accent;
	h.lineBottom.alpha = 0.95;

	h.title.y = titleY;
	h.title.color = spec.color;
	h.title.glowColor = spec.glow;
	h.title.glowAlpha = 1;
	h.title.fontScale = 4.4 * k * 0.6;
	h.title.alpha = 0;
	h.title setText( spec.title );

	h.sub.alpha = 0;
	h.sub.color = ( 0.95, 0.9, 0.85 );

	if ( hasSub )
	{
		h.sub setText( spec.sub );
	}

	h.icon.alpha = 0;

	if ( spec.icon != "" )
	{
		h.icon setShader( spec.icon, 40, 40 );
		h.icon.color = spec.color;
	}

	wait 0.05;

	h.strip scaleOverTime( 0.16, 640, 68 );
	h.lineTop scaleOverTime( 0.16, 640, 2 );
	h.lineBottom scaleOverTime( 0.16, 640, 2 );
	h.title changeFontScaleOverTime( 0.12 );
	h.title.fontScale = 2.5 * k * 0.6;
	h.title fadeOverTime( 0.12 );
	h.title.alpha = 1;

	self playBannerEffects( spec );

	if ( spec.icon != "" )
	{
		h.icon fadeOverTime( 0.2 );
		h.icon.alpha = 1;
	}

	if ( hasSub )
	{
		wait 0.1;
		h.sub fadeOverTime( 0.25 );
		h.sub.alpha = 0.95;
	}

	wait spec.hold;

	h.strip fadeOverTime( 0.4 );
	h.strip.alpha = 0;
	h.lineTop fadeOverTime( 0.4 );
	h.lineTop.alpha = 0;
	h.lineBottom fadeOverTime( 0.4 );
	h.lineBottom.alpha = 0;
	h.title fadeOverTime( 0.4 );
	h.title.alpha = 0;
	h.sub fadeOverTime( 0.4 );
	h.sub.alpha = 0;
	h.icon fadeOverTime( 0.4 );
	h.icon.alpha = 0;

	wait 0.45;
	h.priority = 0;
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

/// Updates the kill streak widget, and starts or stops the red edge glow that marks a hot streak.
streak( count )
{
	if ( !groupOn( "widgets" ) )
	{
		return;
	}

	h = self ensure();

	if ( count < 2 )
	{
		h.streakLabel.alpha = 0;
		h.streakValue.alpha = 0;
		self edgeOff();
		return;
	}

	h.streakLabel.alpha = 0.9;
	h.streakValue.alpha = 1;
	h.streakValue setValue( count );
	h.streakValue.fontScale = 3.4;
	h.streakValue changeFontScaleOverTime( 0.2 );
	h.streakValue.fontScale = 2.4;

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

/// Shows one big countdown number for the last seconds of the match, or hides it when the number is zero.
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
		return;
	}

	h.count setValue( n );
	h.count.alpha = 1;
	h.count.fontScale = 4.4;
	h.count changeFontScaleOverTime( 0.3 );
	h.count.fontScale = 3.2;
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
