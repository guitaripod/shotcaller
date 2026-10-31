/// Truncates the event log so every map starts a fresh file, then records the match header.
open()
{
	filewrite( eventsPath(), "", "write" );

	emit( "hello", field( "v", level.sc_version ) + field( "map", getdvar( "mapname" ) ) + field( "gametype", getdvar( "g_gametype" ) ) + field( "slots", getdvar( "sv_maxclients" ) ) );
}

/// Path of the event log, relative to the scriptdata directory.
eventsPath()
{
	return "shotcaller/events.log";
}

/// Appends one event line: millisecond timestamp, event type, then the pre-built key=value fields.
emit( type, fields )
{
	filewrite( eventsPath(), gettime() + "|" + type + fields + "\n", "append" );
}

/// Builds one `|key=value` field with the value made safe for the wire format.
field( key, value )
{
	return "|" + key + "=" + clean( value + "" );
}

/// Replaces the characters the wire format reserves so a player name cannot forge a field.
clean( text )
{
	out = "";

	for ( i = 0; i < text.size; i++ )
	{
		c = getsubstr( text, i, i + 1 );

		if ( c == "|" || c == "=" || c == "\n" || c == "\r" || c == "\t" )
		{
			c = " ";
		}

		out += c;
	}

	return out;
}
