/// Looks up a banner style by id: its words, colors, icon, sound and how loud it is. Edit this file to restyle every overlay.
spec( id )
{
	s = spawnstruct();
	s.id = id;
	s.title = "";
	s.sub = "";
	s.icon = "";
	s.sound = "";
	s.priority = 50;
	s.weight = 1.0;
	s.hold = 1.7;
	s.shake = 0;
	s.flash = 0;
	s.group = "kills";
	s.color = ( 1, 0.62, 0.15 );
	s.glow = ( 0.45, 0.05, 0 );
	s.accent = ( 1, 0.3, 0.05 );
	s.flashColor = ( 1, 0.35, 0.05 );

	switch ( id )
	{
		case "double":
			s.title = "DOUBLE KILL";
			s.priority = 60;
			s.weight = 1.1;
			break;
		case "triple":
			s.title = "TRIPLE KILL";
			s.priority = 65;
			s.weight = 1.2;
			s.color = ( 1, 0.45, 0.1 );
			s.sound = "mp_challenge_complete";
			break;
		case "quad":
			s.title = "QUAD KILL";
			s.priority = 70;
			s.weight = 1.3;
			s.color = ( 1, 0.3, 0.08 );
			s.sound = "mp_challenge_complete";
			s.flash = 0.18;
			break;
		case "ripandtear":
			s.title = "RIP AND TEAR";
			s.priority = 95;
			s.weight = 1.55;
			s.hold = 2.5;
			s.color = ( 1, 0.12, 0.05 );
			s.glow = ( 0.7, 0, 0 );
			s.accent = ( 1, 0.05, 0.02 );
			s.sound = "mp_challenge_complete";
			s.shake = 0.35;
			s.flash = 0.3;
			s.flashColor = ( 1, 0.05, 0.02 );
			break;
		case "spree":
			s.title = "KILLING SPREE";
			s.group = "streaks";
			s.priority = 62;
			s.weight = 1.1;
			s.sound = "mp_challenge_complete";
			break;
		case "rampage":
			s.title = "RAMPAGE";
			s.group = "streaks";
			s.priority = 72;
			s.weight = 1.3;
			s.color = ( 1, 0.4, 0.08 );
			s.sound = "mp_challenge_complete";
			s.flash = 0.15;
			break;
		case "dominating":
			s.title = "DOMINATING";
			s.group = "streaks";
			s.priority = 78;
			s.weight = 1.4;
			s.color = ( 1, 0.3, 0.06 );
			s.sound = "mp_challenge_complete";
			s.shake = 0.2;
			s.flash = 0.2;
			break;
		case "unstoppable":
			s.title = "UNSTOPPABLE";
			s.group = "streaks";
			s.priority = 85;
			s.weight = 1.5;
			s.hold = 2.2;
			s.color = ( 1, 0.2, 0.05 );
			s.glow = ( 0.65, 0, 0 );
			s.sound = "mp_challenge_complete";
			s.shake = 0.3;
			s.flash = 0.25;
			break;
		case "godlike":
			s.title = "GODLIKE";
			s.group = "streaks";
			s.priority = 90;
			s.weight = 1.6;
			s.hold = 2.4;
			s.color = ( 1, 0.9, 0.3 );
			s.glow = ( 0.7, 0.3, 0 );
			s.accent = ( 1, 0.8, 0.1 );
			s.sound = "mp_challenge_complete";
			s.shake = 0.35;
			s.flash = 0.3;
			s.flashColor = ( 1, 0.8, 0.2 );
			break;
		case "slayer":
			s.title = "SLAYER OF HELL";
			s.group = "streaks";
			s.priority = 98;
			s.weight = 1.7;
			s.hold = 2.8;
			s.color = ( 1, 0.08, 0.04 );
			s.glow = ( 0.8, 0, 0 );
			s.accent = ( 1, 0.05, 0.02 );
			s.sound = "mp_challenge_complete";
			s.shake = 0.45;
			s.flash = 0.35;
			s.flashColor = ( 1, 0.05, 0.02 );
			break;
		case "firstblood":
			s.title = "FIRST BLOOD";
			s.priority = 88;
			s.weight = 1.35;
			s.color = ( 1, 0.15, 0.08 );
			s.sound = "mp_war_objective_taken";
			s.flash = 0.2;
			s.flashColor = ( 1, 0.05, 0.02 );
			break;
		case "shutdown":
			s.title = "SHUTDOWN";
			s.sub = "STREAK ENDED";
			s.icon = "waypoint_kill";
			s.priority = 80;
			s.weight = 1.3;
			s.color = ( 0.35, 0.9, 1 );
			s.glow = ( 0, 0.2, 0.4 );
			s.accent = ( 0.2, 0.7, 1 );
			s.flashColor = ( 0.2, 0.7, 1 );
			s.flash = 0.15;
			break;
		case "glory":
			s.title = "GLORY KILL";
			s.icon = "killiconmelee";
			s.priority = 75;
			s.weight = 1.3;
			s.color = ( 1, 0.55, 0.05 );
			s.shake = 0.15;
			break;
		case "payback":
			s.title = "PAYBACK";
			s.sub = "REVENGE";
			s.priority = 70;
			s.weight = 1.2;
			s.color = ( 0.85, 0.35, 1 );
			s.glow = ( 0.25, 0, 0.4 );
			s.accent = ( 0.7, 0.2, 1 );
			s.flashColor = ( 0.6, 0.2, 1 );
			s.flash = 0.12;
			break;
		case "longshot":
			s.title = "LONG SHOT";
			s.priority = 55;
			s.weight = 1.1;
			s.color = ( 0.95, 0.95, 0.7 );
			s.accent = ( 0.9, 0.9, 0.5 );
			break;
		case "headshot":
			s.title = "HEADSHOT";
			s.icon = "killiconheadshot";
			s.priority = 52;
			s.weight = 1.0;
			s.hold = 1.2;
			s.color = ( 1, 0.25, 0.1 );
			break;
		case "explosive":
			s.title = "BLOWN APART";
			s.priority = 50;
			s.weight = 1.1;
			s.color = ( 1, 0.5, 0.05 );
			s.shake = 0.2;
			break;
		case "pointblank":
			s.title = "POINT BLANK";
			s.priority = 45;
			s.weight = 1.0;
			s.hold = 1.2;
			break;
		case "comeback":
			s.title = "BACK FROM HELL";
			s.priority = 58;
			s.weight = 1.1;
			s.color = ( 0.5, 1, 0.5 );
			s.glow = ( 0, 0.3, 0 );
			s.accent = ( 0.3, 0.9, 0.3 );
			break;
		case "streaklost":
			s.title = "STREAK LOST";
			s.icon = "killiconsuicide";
			s.group = "death";
			s.priority = 40;
			s.weight = 1.0;
			s.hold = 1.4;
			s.color = ( 0.75, 0.75, 0.75 );
			s.glow = ( 0.2, 0, 0 );
			s.accent = ( 0.6, 0.1, 0.1 );
			s.sound = "mp_war_objective_lost";
			break;
		case "fight":
			s.title = "FIGHT";
			s.group = "flow";
			s.priority = 99;
			s.weight = 1.7;
			s.hold = 1.4;
			s.color = ( 1, 0.2, 0.05 );
			s.glow = ( 0.7, 0, 0 );
			s.accent = ( 1, 0.1, 0.02 );
			s.sound = "mp_war_objective_taken";
			s.shake = 0.3;
			s.flash = 0.35;
			s.flashColor = ( 1, 0.15, 0.02 );
			break;
		case "lead":
			s.title = "TAKE THE LEAD";
			s.group = "flow";
			s.priority = 56;
			s.weight = 1.1;
			s.color = ( 0.5, 1, 0.5 );
			s.glow = ( 0, 0.3, 0 );
			s.accent = ( 0.3, 0.9, 0.3 );
			s.sound = "mp_war_objective_taken";
			break;
		case "leadlost":
			s.title = "LEAD LOST";
			s.group = "flow";
			s.priority = 56;
			s.weight = 1.1;
			s.color = ( 1, 0.3, 0.25 );
			s.sound = "mp_war_objective_lost";
			break;
		case "matchpoint":
			s.title = "MATCH POINT";
			s.sub = "FINAL STRETCH";
			s.group = "flow";
			s.priority = 86;
			s.weight = 1.4;
			s.color = ( 1, 0.9, 0.2 );
			s.glow = ( 0.5, 0.3, 0 );
			s.accent = ( 1, 0.8, 0.1 );
			s.sound = "mp_war_objective_taken";
			s.flash = 0.2;
			s.flashColor = ( 1, 0.8, 0.2 );
			break;
		case "minute":
			s.title = "1 MINUTE LEFT";
			s.group = "flow";
			s.priority = 84;
			s.weight = 1.2;
			s.color = ( 1, 0.85, 0.2 );
			s.accent = ( 1, 0.7, 0.1 );
			break;
		case "half":
			s.title = "30 SECONDS";
			s.group = "flow";
			s.priority = 84;
			s.weight = 1.2;
			s.color = ( 1, 0.5, 0.1 );
			s.sound = "mp_war_objective_lost";
			break;
		default:
			return undefined;
	}

	return s;
}

/// The ids a preview can show, in the order the demo cycles through them.
allIds()
{
	return strtok( "fight,double,triple,quad,ripandtear,spree,rampage,dominating,unstoppable,godlike,slayer,firstblood,shutdown,glory,payback,longshot,headshot,explosive,pointblank,comeback,streaklost,lead,leadlost,matchpoint,minute,half", "," );
}
