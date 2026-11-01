/// The display name of a map: the stock name where there is one, otherwise the id tidied up.
label( map )
{
	switch ( map )
	{
		case "mp_afghan": return "AFGHAN";
		case "mp_boneyard": return "SCRAPYARD";
		case "mp_brecourt": return "WASTELAND";
		case "mp_checkpoint": return "KARACHI";
		case "mp_derail": return "DERAIL";
		case "mp_estate": return "ESTATE";
		case "mp_estate_tropical": return "ESTATE TROPICAL";
		case "mp_favela": return "FAVELA";
		case "mp_fav_tropical": return "FAVELA TROPICAL";
		case "mp_highrise": return "HIGHRISE";
		case "mp_invasion": return "INVASION";
		case "mp_nightshift": return "SKIDROW";
		case "mp_quarry": return "QUARRY";
		case "mp_rundown": return "RUNDOWN";
		case "mp_rust": return "RUST";
		case "mp_rust_long": return "RUST LONG";
		case "mp_subbase": return "SUB BASE";
		case "mp_terminal": return "TERMINAL";
		case "mp_underpass": return "UNDERPASS";
		case "mp_storm_spring": return "STORM";
		case "mp_crash_tropical": return "CRASH TROPICAL";
		case "mp_crash_snow": return "CRASH SNOW";
		case "mp_nuked": return "NUKETOWN";
		case "mp_shipment": return "SHIPMENT";
		case "mp_shipment_long": return "SHIPMENT LONG";
		case "mp_alpha": return "LOCKDOWN";
		case "mp_bravo": return "MISSION";
		case "mp_dome": return "DOME";
		case "mp_paris": return "RESISTANCE";
		case "mp_plaza2": return "ARKADEN";
		case "mp_seatown": return "SEATOWN";
		case "mp_underground": return "UNDERGROUND";
		case "mp_village": return "VILLAGE";
		case "mp_hardhat": return "HARDHAT";
		case "mp_carentan": return "CHINATOWN";
		case "mp_backlot": return "BACKLOT";
		case "mp_bloc": return "BLOC";
		case "mp_bloc_sh": return "BLOC SH";
		case "mp_bog_sh": return "BOG";
		case "mp_broadcast": return "BROADCAST";
		case "mp_cargoship": return "WET WORK";
		case "mp_cargoship_sh": return "WET WORK SH";
		case "mp_citystreets": return "DISTRICT";
		case "mp_convoy": return "AMBUSH";
		case "mp_countdown": return "COUNTDOWN";
		case "mp_cross_fire": return "CROSSFIRE";
		case "mp_farm": return "DOWNPOUR";
		case "mp_firingrange": return "FIRING RANGE";
		case "mp_killhouse": return "KILLHOUSE";
		case "mp_pipeline": return "PIPELINE";
		case "mp_showdown": return "SHOWDOWN";
	}

	return tidy( map );
}

/// Turns an unknown map id into display text: the mp_ prefix dropped, underscores spaced and upper-cased.
tidy( map )
{
	name = map;

	if ( name.size > 3 && getsubstr( name, 0, 3 ) == "mp_" )
	{
		name = getsubstr( name, 3, name.size );
	}

	out = "";

	for ( i = 0; i < name.size; i++ )
	{
		c = getsubstr( name, i, i + 1 );

		if ( c == "_" )
		{
			c = " ";
		}

		out += c;
	}

	return toUpper( out );
}

/// The display name of a game type id.
gametype( id )
{
	switch ( id )
	{
		case "war": return "TEAM DEATHMATCH";
		case "dm": return "FREE FOR ALL";
		case "dom": return "DOMINATION";
		case "sd": return "SEARCH AND DESTROY";
		case "sab": return "SABOTAGE";
		case "koth": return "HEADQUARTERS";
		case "ctf": return "CAPTURE THE FLAG";
		case "oneflag": return "ONE FLAG";
		case "arena": return "ARENA";
		case "gtnw": return "GLOBAL THERMONUCLEAR WAR";
		case "vip": return "VIP";
		case "oic": return "ONE IN THE CHAMBER";
		case "gg": return "GUN GAME";
	}

	return toUpper( id );
}

/// The name as it appears in the vote grid, where a column is narrow: the full name with "TROPICAL" cut short.
shortLabel( map )
{
	switch ( map )
	{
		case "mp_estate_tropical": return "ESTATE TROP";
		case "mp_fav_tropical": return "FAVELA TROP";
		case "mp_crash_tropical": return "CRASH TROP";
	}

	return label( map );
}

/// Every known map id in display order, sorted by the name players see.
order()
{
	ids = strtok( "mp_afghan,mp_convoy,mp_plaza2,mp_backlot,mp_bloc,mp_bloc_sh,mp_bog_sh,mp_broadcast,mp_carentan,mp_countdown,mp_crash_snow,mp_crash_tropical,mp_cross_fire,mp_derail,mp_citystreets,mp_dome,mp_farm,mp_estate,mp_estate_tropical,mp_favela,mp_fav_tropical,mp_firingrange,mp_hardhat,mp_highrise,mp_invasion,mp_checkpoint,mp_killhouse,mp_alpha,mp_bravo,mp_nuked,mp_pipeline,mp_quarry,mp_paris,mp_rundown,mp_rust,mp_rust_long,mp_boneyard,mp_seatown,mp_shipment,mp_shipment_long,mp_showdown,mp_nightshift,mp_storm_spring,mp_subbase,mp_terminal,mp_underground,mp_underpass,mp_village,mp_brecourt,mp_cargoship,mp_cargoship_sh", "," );

	return ids;
}
