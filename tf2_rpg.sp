
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <topmenus>

#include <chat-processor>

#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf2items_giveweapon>

#define KILLME_NAME "[  ★  ] Kill Me"

#define TF_DEATHFLAG_MINIBOSS (1 << 9)

char g_currentMusic[256];

bool g_block[MAXPLAYERS + 1];
int g_respawnMarkers[MAXPLAYERS + 1]= {INVALID_ENT_REFERENCE, ...};

int g_botDifficulty = 1;
TFTeam g_botTeam = TFTeam_Blue;
TFTeam g_humanTeam = TFTeam_Red;

TopMenu g_RPGTopMenu;
TopMenuObject g_RPGSkillMenu;
TopMenuObject g_RPGStetMenu;

KeyValues g_kvMusicPath;
KeyValues g_kvRPGData[MAXPLAYERS + 1];
KeyValues g_kvSkillInfo;

bool g_bProtoBuf;

public void OnPluginStart()
{
	g_bProtoBuf = GetUserMessageType() == UM_Protobuf;

	HookEvent("player_spawn", Event_OnPlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Pre);
	HookEvent("teamplay_round_start", Event_OnRoundStart, EventHookMode_Post);
	HookEvent("teamplay_round_win", Event_OnRoundEnd, EventHookMode_Post);
	
	HookEvent("player_connect", Event_BroadcastDisable, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_BroadcastDisable, EventHookMode_Pre);
	HookEvent("player_team", 	Event_BroadcastDisable, EventHookMode_Pre);
	
	HookEvent("player_changename", Event_OnPlayerChangeName, EventHookMode_Pre);
	
	HookEvent("teamplay_point_captured", Event_OnPointCaptured, EventHookMode_Pre);
	
	RegConsoleCmd("sm_rpg", Cmd_RPGMenu);
	RegConsoleCmd("sm_rpgmenu", Cmd_RPGMenu);
	RegConsoleCmd("sm_menu", Cmd_RPGMenu);
	
	CreateTimer(1.0, Timer_Z, _, TIMER_REPEAT);
	CreateTimer(20.0, Timer_AutoSave, _, TIMER_REPEAT);
	CreateTimer(60.0, Timer_Advert, _, TIMER_REPEAT);
	
	g_RPGTopMenu = new TopMenu(Handler_RPGTopMenu);
	
	g_RPGSkillMenu = g_RPGTopMenu.AddCategory("Skill", Handler_RPGTopMenu);
	g_RPGStetMenu = g_RPGTopMenu.AddCategory("Stet", Handler_RPGTopMenu);
	
	g_RPGTopMenu.AddItem("health", Handler_StetMenu, g_RPGStetMenu);
	g_RPGTopMenu.AddItem("power", Handler_StetMenu, g_RPGStetMenu);
	g_RPGTopMenu.AddItem("luck", Handler_StetMenu, g_RPGStetMenu);
	
	RegConsoleCmd("sm_refresh_skill_info", Cmd_RefreshSkillInfo);
	
	g_kvMusicPath = new KeyValues("music_path");
	g_kvMusicPath.ImportFromFile("addons/sourcemod/configs/tf2_rpg/music_data.cfg");
	
	g_kvSkillInfo = new KeyValues("skill_data");
	g_kvSkillInfo.ImportFromFile("addons/sourcemod/configs/tf2_rpg/skill_data.cfg");
	
	if (g_kvSkillInfo.GotoFirstSubKey())
	{
		char skillName[128];
		do
		{
			g_kvSkillInfo.GetSectionName(skillName, sizeof(skillName));
			
			g_RPGTopMenu.AddItem(skillName, Handler_SkillMenu, g_RPGSkillMenu);
		}
		while
			g_kvSkillInfo.GotoNextKey();
			
		g_kvSkillInfo.GoBack();
	}
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	Format(name, MAXLENGTH_NAME, "{green}[Lv.%d]{aqua} %s", RPG_GetLevel(author), name);
	//Format(message, MAXLENGTH_MESSAGE, "{blue}%s", message);
	return Plugin_Changed;
}

public Action Cmd_RefreshSkillInfo(int client, int args)
{
	delete g_kvSkillInfo;
	
	g_kvSkillInfo = new KeyValues("skill_data");
	g_kvSkillInfo.ImportFromFile("addons/sourcemod/configs/tf2_rpg/skill_data.cfg");
	
	if (g_kvSkillInfo.GotoFirstSubKey())
	{
		char skillName[128];
		do
		{
			g_kvSkillInfo.GetSectionName(skillName, sizeof(skillName));
			
			g_RPGTopMenu.AddItem(skillName, Handler_SkillMenu, g_RPGSkillMenu);
		}
		while
			g_kvSkillInfo.GotoNextKey();
			
		g_kvSkillInfo.GoBack();
	}
}
	
public void OnMapStart()
{
	char buffer[256];
	for (int i=1; i<=12; i++)
	{
		Format(buffer, sizeof(buffer), "vo/mvm_wave_start%02d.mp3", i);
		PrecacheSound(buffer);
	}
	
	if (g_kvMusicPath.GotoFirstSubKey(false))
	{
		char musicPath[256];
		do
		{
			g_kvMusicPath.GetString(NULL_STRING, musicPath, sizeof(musicPath));
			
			PrecacheSound(musicPath);
			Format(buffer, sizeof(buffer), "sound/%s", musicPath);
			AddFileToDownloadsTable(buffer);
		}
		while
			g_kvMusicPath.GotoNextKey();
	}
	g_kvMusicPath.GoBack();
}

public void OnConfigsExecuted()
{
	ServerCommand("tf_bot_quota 0");
	ServerCommand("tf_bot_kick all");
	
	ServerCommand("tf_allow_server_hibernation 0");
	
	ServerCommand("tf_bot_difficulty 3");
	ServerCommand("tf_bot_join_after_player 0");
	ServerCommand("tf_bot_keep_class_after_death 0");
	ServerCommand("tf_bot_force_class random")
	ServerCommand("tf_bot_auto_vacate 0");
	ServerCommand("sm_cvar tf_bot_reevaluate_class_in_spawnroom 0");
	ServerCommand("sm_cvar tf_bot_offense_must_push_time -1");
	ServerCommand("mp_scrambleteams_auto 0");
	ServerCommand("sm_cvar spec_freeze_time -1");
	ServerCommand("sv_vote_issue_nextlevel_allowed 0");
	ServerCommand("sv_vote_issue_scramble_teams_allowed 0");
	ServerCommand("sm_cvar tf_dropped_weapon_lifetime 0")
	
	ForceSettings();
}

void ForceSettings()
{
	ServerCommand("mp_teams_unbalance_limit 0");
	if (g_humanTeam == TFTeam_Red)
		ServerCommand("mp_humans_must_join_team red");
	else
		ServerCommand("mp_humans_must_join_team blue");
	ServerCommand("mp_respawnwavetime 500");
	ServerCommand("mp_autoteambalance 0");
}

public void OnClientPutInServer(int client)
{
	RefreshSlots();
	g_block[client] = false;
	
	char buffer[256];
	GetRPGDataPath(client, buffer, sizeof(buffer));
	
	if (g_kvRPGData[client] != null)
		delete g_kvRPGData[client];
	
	g_kvRPGData[client] = new KeyValues("rpg_data")
	g_kvRPGData[client].ImportFromFile(buffer);
}

public void OnClientDisconnect(int client)
{
	if (g_respawnMarkers[client] != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(g_respawnMarkers[client], "Kill");
		g_respawnMarkers[client] = INVALID_ENT_REFERENCE;
	}
	
	if (!IsClientInGame(client))
		return;
	
	char buffer[256];
	GetRPGDataPath(client, buffer, sizeof(buffer));
	g_kvRPGData[client].ExportToFile(buffer);
	
	delete g_kvRPGData[client];
}

public void OnClientDisconnect_Post(int client)
{
	RefreshSlots();
}

void RefreshSlots()
{
	int slots = 10;
	int botCount = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (IsFakeClient(i))
			botCount++;
	}
	
	ServerCommand("sv_visiblemaxplayers %d", slots + botCount);
	ServerCommand("sm_reserved_slots 0");
	//ServerCommand("sm_reserved_slots %d", 100 - slots - botCount)
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	PrintToChatAll("\x01 \x0700FFFF[봇 난이도]\x07FFFFFF %d", g_botDifficulty);
	
	ForceSettings();
	
	AddBot(KILLME_NAME, g_botTeam);
	LoadBots(g_botDifficulty);
	
	char buffer[128];
	Format(buffer, sizeof(buffer), "vo/mvm_wave_start%02d.mp3", GetRandomInt(1,12));
	EmitSoundToAll(buffer);
	
	Format(buffer, sizeof(buffer), "level_%d", g_botDifficulty);
	
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		StopSound(i, SNDCHAN_STATIC, g_currentMusic);
	}
	
	char sound[128];
	g_kvMusicPath.GetString(buffer, sound, sizeof(sound));
	EmitSoundToAll(sound, .channel = SNDCHAN_STATIC, .level = SNDLEVEL_NONE, .flags = SND_CHANGEVOL, .volume = 0.5);
	strcopy(g_currentMusic, sizeof(g_currentMusic), sound);
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	TFTeam winnerTeam = view_as<TFTeam>(event.GetInt("team"));
	if (winnerTeam == g_botTeam)
		g_botDifficulty = g_botDifficulty > 1 ? g_botDifficulty - 1 : g_botDifficulty;
	else if (winnerTeam == g_humanTeam)
		g_botDifficulty++;
	
	KickAllBots();
}

GiveWeapon(float time, int client, int weapon)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(weapon);
	CreateTimer(time, Timer_GiveWeapon, pack);
}

public Action Timer_GiveWeapon(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int weapon = pack.ReadCell();
	
	delete pack;

	if (client == 0)
		return Plugin_Continue;

	TF2Items_GiveWeapon(client, weapon);
	return Plugin_Continue;
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	TF2Attrib_RemoveAll(client);
	if (!IsPlayerAlive(client))
		return;
	
	if (IsFakeClient(client))
	{
		char botName[MAX_NAME_LENGTH];
		GetClientName(client, botName, sizeof(botName));
		if (StrEqual(botName, "[Helper] Medic"))
		{
			FakeClientCommand(client, "joinclass medic");
			TF2Attrib_SetByName(client, "heal rate bonus", 5.0);
			TF2Attrib_SetByName(client, "overheal decay bonus", 1.0);
			TF2Attrib_SetByName(client, "ubercharge rate bonus", 2.0);
			GiveWeapon(0.1, client, 35);
		}
		if (StrEqual(botName, "[Helper] Engineer"))
		{
			FakeClientCommand(client, "joinclass engineer");
			TF2Attrib_SetByName(client, "engy building health bonus", 10.0);
			TF2Attrib_SetByName(client, "engy sentry fire rate increased", 0.5);
			TF2Attrib_SetByName(client, "engy sentry radius increased", 100.0);
			TF2Attrib_SetByName(client, "engy dispenser radius increased", 10.0);
			TF2Attrib_SetByName(client, "maxammo metal increased", 100.0);
			TF2Attrib_SetByName(client, "Construction rate increased", 100.0);
		}

		if (StrEqual(botName, "[Rapid] Kid Commander"))
		{
			FakeClientCommand(client, "joinclass soldier");
		}
		
		if (StrEqual(botName, "[Broken Love] Mad Doctor"))
		{
			FakeClientCommand(client, "joinclass medic");
			TF2Attrib_SetByName(client, "heal rate bonus", 5.0);
			TF2Attrib_SetByName(client, "ubercharge rate bonus", 10.0);
			GiveWeapon(0.2, client, 35);
		}

		if (StrEqual(botName, KILLME_NAME))
		{
			TF2Attrib_SetByName(client, "damage bonus", 0.95 + 0.05 * g_botDifficulty);
			TF2Attrib_SetByName(client, "dmg bonus vs buildings", 0.95 + 0.05 * g_botDifficulty);
			TF2Attrib_SetByName(client, "max health additive bonus", 9999.0);
			TF2_AddCondition(client, TFCond_TeleportedGlow, TFCondDuration_Infinite, 0);
			
			switch (TF2_GetPlayerClass(client))
			{
				case TFClass_Engineer:
				{
					TF2Attrib_SetByName(client, "engy sentry radius increased", 100.0);
					TF2Attrib_SetByName(client, "engy dispenser radius increased", 5.0);
					TF2Attrib_SetByName(client, "maxammo metal increased", 100.0);
					TF2Attrib_SetByName(client, "Construction rate increased", 100.0);
				}
				case TFClass_Medic:
				{
					TF2Items_GiveWeapon(client, 35); // The Kritzkrieg
				}
			}
			
			TF2Items_GiveWeapon(client, 423); // Saxxy
		}
		
		if (StrContains(botName, "[]") == 0)
		{
			TF2Attrib_SetByName(client, "damage bonus", 0.45 + 0.05 * g_botDifficulty);
			TF2Attrib_SetByName(client, "dmg bonus vs buildings", 0.45 + 0.05 * g_botDifficulty);
			
			char classList[][] = {"scout", "soldier", "pyro", "demoman", "heavy", "engineer", "medic", "sniper", "spy"};
			for (int i=0; i<sizeof(classList); i++)
			{
				if (StrContains(botName, classList[i], false) != -1)
				{
					if (StrEqual(classList[i], "heavy"))
						FakeClientCommand(client, "joinclass heavyweapons");
					else
						FakeClientCommand(client, "joinclass %s", classList[i]);
				}
			}
			
			if (StrContains(botName, "engineer", false) != -1)
			{
				TF2Attrib_SetByName(client, "engy sentry radius increased", 100.0);
				TF2Attrib_SetByName(client, "engy dispenser radius increased", 5.0);
				TF2Attrib_SetByName(client, "maxammo metal increased", 10.0);
				//TF2Attrib_SetByName(client, "Construction rate increased", 10.0);
				//SetEntProp(client, Prop_Data, "m_iAmmo", 1000, 4, 3);
			}
		}
	}
	else
	{
		if (g_respawnMarkers[client] != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(g_respawnMarkers[client], "Kill");
			g_respawnMarkers[client] = INVALID_ENT_REFERENCE;
		}
		
		int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
		float moreHealth = 0.0;
		
		moreHealth += maxHealth * g_kvRPGData[client].GetNum("health", 0) * 0.025;
		TF2Attrib_SetByName(client, "max health additive bonus", moreHealth);
		
		TF2Attrib_SetByName(client, "mod see enemy health", 1.0);
		TF2Attrib_SetByName(client, "damage bonus", 1.0 + g_kvRPGData[client].GetNum("damage", 0) * 0.01);
		
		g_kvSkillInfo.Rewind();
		if (g_kvSkillInfo.GotoFirstSubKey())
		{
			int skill;
			char skillName[128];
			do
			{
				g_kvSkillInfo.GetSectionName(skillName, sizeof(skillName));
			
				skill = g_kvRPGData[client].GetNum(skillName, 0);
				if (skill > 0)
				{
					char attribute_name[32];
					Skill_GetAttributeName(skillName, attribute_name, sizeof(attribute_name));
					char attribute_type[32];
					Skill_GetAttributeType(skillName, attribute_type, sizeof(attribute_type));
					float value = Skill_GetAttributeValue(skillName);
					
					ArrayList targetList = new ArrayList(1);
					
					char attribute_weapon[32];
					g_kvSkillInfo.GetString("attribute_weapon", attribute_weapon, sizeof(attribute_weapon), "");
					if (attribute_weapon[0] == EOS)
					{
						targetList.Push(client);
					}
					else
					{
						if (StrEqual(attribute_weapon, "all"))
						{
							for (int i=0; i<=2; i++)
								targetList.Push(GetPlayerWeaponSlot(client, i));
						}
						else if (StrEqual(attribute_weapon, "primary"))
							targetList.Push(GetPlayerWeaponSlot(client, 0));
						else if (StrEqual(attribute_weapon, "secondary"))
							targetList.Push(GetPlayerWeaponSlot(client, 1));
					}
					
					for (int i=0; i<targetList.Length; i++)
					{
						int target = targetList.Get(i);
						if (StrEqual(attribute_type, "percentage"))
							TF2Attrib_SetByName(target, attribute_name, 1.0 + (skill * value));
						else if (StrEqual(attribute_type, "additive"))
							TF2Attrib_SetByName(target, attribute_name, skill * value);
					}
				}
			}
			while
				g_kvSkillInfo.GotoNextKey();
				
			g_kvSkillInfo.GoBack();
		}
	}
	
	TF2_RegeneratePlayer(client);
}

public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	int death_flags = event.GetInt("death_flags");
	
	TFClassType class = TF2_GetPlayerClass(client)
	float respawnTime = 5.0;
		
	if (IsFakeClient(client))
	{
		respawnTime = 20.0;
		
		char botName[MAX_NAME_LENGTH];
		GetClientName(client, botName, sizeof(botName));
		if (StrEqual(botName, KILLME_NAME))
		{
			TF2_SetPlayerClass(client, view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer))), false, false);
		}
		
		if (StrContains(botName, "[]") == 0)
		{
			event.BroadcastDisabled = true;
			
			if (attacker > 0)
				event.FireToClient(attacker);
			if (assister > 0)
				event.FireToClient(assister);
			
			respawnTime = 2.5;
			if (class == TFClass_Engineer ||
				class == TFClass_Sniper ||
				class == TFClass_Spy)
				respawnTime = 6.0;
		}
	}
	else
	{
		respawnTime = 5.0;
	
		int clientTeam = GetClientTeam(client);
		int reviveMarker = CreateEntityByName("entity_revive_marker");

		if (reviveMarker != -1)
		{
			SetEntPropEnt(reviveMarker, Prop_Send, "m_hOwner", client); // client index 
			SetEntProp(reviveMarker, Prop_Send, "m_nSolidType", 2); 
			SetEntProp(reviveMarker, Prop_Send, "m_usSolidFlags", 8); 
			SetEntProp(reviveMarker, Prop_Send, "m_fEffects", 16); 
			SetEntProp(reviveMarker, Prop_Send, "m_iTeamNum", clientTeam); // client team 
			SetEntProp(reviveMarker, Prop_Send, "m_CollisionGroup", 1); 
			SetEntProp(reviveMarker, Prop_Send, "m_bSimulatedEveryTick", 1);
			SetEntDataEnt2(client, FindSendPropInfo("CTFPlayer", "m_nForcedSkin")+4, reviveMarker);
			SetEntProp(reviveMarker, Prop_Send, "m_nBody", view_as<int>(TF2_GetPlayerClass(client)) - 1); // character hologram that is shown
			SetEntProp(reviveMarker, Prop_Send, "m_nSequence", 1); 
			SetEntPropFloat(reviveMarker, Prop_Send, "m_flPlaybackRate", 1.0);
			SetEntProp(reviveMarker, Prop_Data, "m_iInitialTeamNum", clientTeam);
			SDKHook(reviveMarker, SDKHook_SetTransmit, Transmit_ReviveMaker);
			g_respawnMarkers[client] = EntIndexToEntRef(client);
		}
	}
	
	int rewardXP = RoundToFloor(g_botDifficulty * 0.34);
	if (rewardXP < 1)
		rewardXP = 1;
	
	if (attacker > 0 && !IsFakeClient(attacker))
	{
		if (client != attacker)
		{
			RPG_AddXP(attacker, rewardXP);
		}
	}
	
	if (assister > 0 && !IsFakeClient(assister))
		RPG_AddXP(assister, rewardXP);
			
	CreateTimer(respawnTime, Timer_Respawn, GetClientUserId(client));
}

public Action Transmit_ReviveMaker(int reviveMaker, int client)
{
	if (GetEntProp(reviveMaker, Prop_Send, "m_iTeamNum") == GetClientTeam(client))
	{
		if (TF2_GetPlayerClass(client) == TFClass_Medic)
			return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action Event_BroadcastDisable(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;

	return Plugin_Handled;
}

public void Event_OnPointCaptured(Event event, const char[] name, bool dontBroadcast)
{
	TFTeam team = view_as<TFTeam>(event.GetInt("team")); 
	int cp = event.GetInt("cp");
	char cappers[MAXPLAYERS + 1];
	event.GetString("cappers", cappers, MAXPLAYERS);
	if (team == g_humanTeam)
	{
		int rewardXP = cp == 3 ? 8 : 5;
		rewardXP += g_botDifficulty;
		
		int capperSize = strlen(cappers);
		for (int i=0; i<capperSize; i++)
		{
			if (IsFakeClient(cappers[i]))
				continue;
			
			RPG_AddXP(cappers[i], rewardXP);
		}
	}
}

public Action Event_OnPlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (g_block[client])
	{
		g_block[client] = false;
		return Plugin_Continue;
	}
		
	char oldName[64];
	char newName[64];
	
	event.GetString("oldname", oldName, sizeof(oldName));
	event.GetString("newName", newName, sizeof(newName));
	
	if (IsFakeClient(client))
	{
		event.BroadcastDisabled = true;
		dontBroadcast = true;
		
		g_block[client] = true;
		SetClientName(client, oldName);
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if (IsFakeClient(client))
	{
		char botName[64];
		GetClientName(client, botName, sizeof(botName));
		
		if (StrEqual(botName, KILLME_NAME) && condition == TFCond_TeleportedGlow)
			TF2_AddCondition(client, TFCond_TeleportedGlow, TFCondDuration_Infinite, 0);
	}
}


public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool& result)
{
	if (!IsFakeClient(client))
	{
		if (g_kvRPGData[client].GetNum("luck", 0) >= GetRandomInt(1, 100))
		{
			result = true;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

void AddBot(const char[] name, TFTeam team)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		char iName[MAX_NAME_LENGTH];
		GetClientName(i, iName, sizeof(iName));
		
		if (StrEqual(iName, name))
		{
			if (!IsFakeClient(i))
				ServerCommand("kickid %d", GetClientUserId(i));
			return;
		}
	}
	
	char teamName[32];
	switch (team)
	{
		case TFTeam_Red:
			strcopy(teamName, sizeof(teamName), "red");
		case TFTeam_Blue:
			strcopy(teamName, sizeof(teamName), "blue");
	}
	
	ServerCommand("tf_bot_add \"%s\" %s", 
								name,
								teamName);
}

LoadBots(int difficulty)
{
	switch (difficulty)
	{
		case 1:
		{
			AddBot("[Helper] Engineer", 			g_humanTeam);
			AddBot("[Helper] Medic", 				g_humanTeam);

			AddBot("[] Scout 1", 			g_botTeam);
			
			AddBot("[] Soldier 1", 			g_botTeam);
			AddBot("[] Soldier 2", 			g_botTeam);
			AddBot("[] Soldier 3", 			g_botTeam);
			
			AddBot("[] Pyro 1", 			g_botTeam);
			AddBot("[] Pyro 2", 			g_botTeam);
			AddBot("[] Pyro 3", 			g_botTeam);
			
			AddBot("[] Demoman 1", 			g_botTeam);
			AddBot("[] Demoman 2", 			g_botTeam);
			
			AddBot("[] Heavy 1", 			g_botTeam);
			AddBot("[] Heavy 2", 			g_botTeam);
			
			AddBot("[] Engineer 1", 		g_botTeam);
			AddBot("[] Engineer 2", 		g_botTeam);
			
			AddBot("[] Medic 1", 			g_botTeam);
			AddBot("[] Medic 2", 			g_botTeam);
			
			AddBot("[] Sniper 1", 			g_botTeam);
			AddBot("[] Sniper 2", 			g_botTeam);
			
			AddBot("[] Spy 1", 				g_botTeam);
			AddBot("[] Spy 2", 				g_botTeam);
		}
		case 2:
		{
			AddBot("[] Scout 1", 			g_botTeam);
			AddBot("[] Scout 2", 			g_botTeam);
			
			AddBot("[] Soldier 1", 			g_botTeam);
			AddBot("[] Soldier 2", 			g_botTeam);
			AddBot("[] Soldier 3", 			g_botTeam);
			AddBot("[] Soldier 4", 			g_botTeam);
			
			AddBot("[] Pyro 1", 			g_botTeam);
			AddBot("[] Pyro 2", 			g_botTeam);
			AddBot("[] Pyro 3", 			g_botTeam);
			
			AddBot("[] Demoman 1", 			g_botTeam);
			AddBot("[] Demoman 2", 			g_botTeam);
			
			AddBot("[] Heavy 1", 			g_botTeam);
			AddBot("[] Heavy 2", 			g_botTeam);
			
			AddBot("[] Engineer 1", 		g_botTeam);
			AddBot("[] Engineer 2", 		g_botTeam);
			
			AddBot("[] Medic 1", 			g_botTeam);
			AddBot("[] Medic 2", 			g_botTeam);
			
			AddBot("[] Sniper 1", 			g_botTeam);
			AddBot("[] Sniper 2", 			g_botTeam);
			
			AddBot("[] Spy 1", 				g_botTeam);
			AddBot("[] Spy 2", 				g_botTeam);
		}
		case 3:
		{
			AddBot("[Broken Love] Mad Doctor", 	g_botTeam);
			
			AddBot("[] Scout 1", 			g_botTeam);
			AddBot("[] Scout 2", 			g_botTeam);
			
			AddBot("[] Soldier 1", 			g_botTeam);
			AddBot("[] Soldier 2", 			g_botTeam);
			AddBot("[] Soldier 3", 			g_botTeam);
			
			AddBot("[] Pyro 1", 			g_botTeam);
			AddBot("[] Pyro 2", 			g_botTeam);
			
			AddBot("[] Demoman 1", 			g_botTeam);
			AddBot("[] Demoman 2", 			g_botTeam);
			
			AddBot("[] Heavy 1", 			g_botTeam);
			AddBot("[] Heavy 2", 			g_botTeam);
			AddBot("[] Heavy 3", 			g_botTeam);
			
			AddBot("[] Engineer 1", 		g_botTeam);
			AddBot("[] Engineer 2", 		g_botTeam);
			
			AddBot("[] Medic 1", 			g_botTeam);
			AddBot("[] Medic 2", 			g_botTeam);
			
			AddBot("[] Sniper 1", 			g_botTeam);
			AddBot("[] Sniper 2", 			g_botTeam);
			
			AddBot("[] Spy 1", 				g_botTeam);
			AddBot("[] Spy 2", 				g_botTeam);
		}
		default:
		{
			AddBot("[] Scout 1", 			g_botTeam);
			AddBot("[] Scout 2", 			g_botTeam);
			
			AddBot("[] Soldier 1", 			g_botTeam);
			AddBot("[] Soldier 2", 			g_botTeam);
			AddBot("[] Soldier 3", 			g_botTeam);
			AddBot("[] Soldier 4", 			g_botTeam);
			
			AddBot("[] Pyro 1", 			g_botTeam);
			AddBot("[] Pyro 2", 			g_botTeam);
			AddBot("[] Pyro 3", 			g_botTeam);
			
			AddBot("[] Demoman 1", 			g_botTeam);
			AddBot("[] Demoman 2", 			g_botTeam);
			
			AddBot("[] Heavy 1", 			g_botTeam);
			AddBot("[] Heavy 2", 			g_botTeam);
			
			AddBot("[] Engineer 1", 		g_botTeam);
			AddBot("[] Engineer 2", 		g_botTeam);
			
			AddBot("[] Medic 1", 			g_botTeam);
			AddBot("[] Medic 2", 			g_botTeam);
			
			AddBot("[] Sniper 1", 			g_botTeam);
			AddBot("[] Sniper 2", 			g_botTeam);
			
			AddBot("[] Spy 1", 				g_botTeam);
			AddBot("[] Spy 2", 				g_botTeam);
			
		}
	}
}

void KickAllBots(bool withoutKillMe = true)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		char name[MAX_NAME_LENGTH];
		GetClientName(i, name, sizeof(name));
		
		if (withoutKillMe && StrEqual(name, KILLME_NAME))
			continue;
		
		ServerCommand("tf_bot_kick \"%s\"", name);
	}
}

public void OnGameFrame()
{
	int index = -1;
	
	char buildName[][] = {"obj_sentrygun", "obj_dispenser", "obj_teleporter"};
	for (int i=0; i<sizeof(buildName); i++)
	{
		index = -1;
		while ((index = FindEntityByClassname(index, buildName[i])) != -1)
		{
			int owner = GetEntPropEnt(index, Prop_Send, "m_hBuilder");
			if (owner == -1)
				continue;
			
			if (IsFakeClient(owner))
			{
				char ownerName[MAX_NAME_LENGTH];
				GetClientName(owner, ownerName, sizeof(ownerName));
				if (StrEqual(ownerName, "[Inventor] Stain"))
					SetEntProp(index, Prop_Send, "m_iUpgradeMetal", 999);
			}
		}
	}
}

public Action Cmd_RPGMenu(int client, int args)
{
	g_RPGTopMenu.Display(client, TopMenuPosition_Start);
	return Plugin_Handled;
}

public Action Timer_Respawn(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client == 0)
		return Plugin_Continue;
	
	TF2_RespawnPlayer(client);
	return Plugin_Continue;
}

public Action Timer_Z(Handle timer)
{
	for (int client=1; client<=MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
		
		if (IsFakeClient(client))
			continue;
		
		Client_PrintKeyHintText(client, "%d 레벨\n \n%d/%d 경험치\n%d 스킬 포인트\n%d 스텟 포인트",
								RPG_GetLevel(client),
								RPG_GetXP(client), RPG_GetRequireXP(client),
								RPG_GetSkillPoint(client),
								RPG_GetStetPoint(client));
	}
	
	EmitSoundToAll(g_currentMusic, .channel = SNDCHAN_STATIC, .level = SNDLEVEL_NONE, .flags = SND_CHANGEVOL, .volume = 0.5);
	
	return Plugin_Continue;
}

public Action Timer_AutoSave(Handle timer)
{
	for (int client=1; client<=MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
		 
		char buffer[256];
		GetRPGDataPath(client, buffer, sizeof(buffer));
		g_kvRPGData[client].ExportToFile(buffer);
	}
}

public Action Timer_Advert(Handle timer)
{
	PrintToChatAll("\x01 \x04[Advert]\x01 !menu를 통해 RPG 메뉴를 이용할 수 있습니다.");
}

public void Handler_RPGTopMenu(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "＠ RPG Menu");
		
		case TopMenuAction_DisplayOption:
		{
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			
			if (StrEqual(name, "skill", false))
				Format(buffer, maxlength, "스킬");
			else if (StrEqual(name, "stet", false))
				Format(buffer, maxlength, "스텟");
		}
	}
}

public void Handler_StetMenu(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "＠ StetMenu");
		
		
		case TopMenuAction_DisplayOption:
		{
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			
			if (StrEqual(name, "health", false))
			{
				Format(buffer, maxlength, "체력 %d / 2.5％+",
											g_kvRPGData[param].GetNum("health", 0));
			}
			else if (StrEqual(name, "power", false))
			{
				Format(buffer, maxlength, "근력 %d / 1％+",
											g_kvRPGData[param].GetNum("power", 0));
			}
			else if (StrEqual(name, "luck", false))
			{
				Format(buffer, maxlength, "운 %d / 1％+",
											g_kvRPGData[param].GetNum("luck", 0));
			}
		}
		
		case TopMenuAction_DrawOption:
		{
			if (RPG_GetStetPoint(param) <= 0)
				buffer[0] = ITEMDRAW_DISABLED;
		}
		
		case TopMenuAction_SelectOption:
		{
			if (RPG_GetStetPoint(param) <= 0)
				return;
			
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			g_kvRPGData[param].SetNum(name, g_kvRPGData[param].GetNum(name, 0) + 1);
			RPG_SetStetPoint(param, RPG_GetStetPoint(param) - 1);
			
			g_RPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

public void Handler_SkillMenu(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "＠ Skill Menu");
		
		
		case TopMenuAction_DisplayOption:
		{
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			
			char showName[128];
			Skill_GetName(name, showName, sizeof(showName));
			
			Format(buffer, maxlength, "%s[%d/%d] - Lv.%d, %dSP",
								showName, g_kvRPGData[param].GetNum(name, 0), Skill_GetMaxLevel(name), 
								Skill_GetRequireLevel(param, name), Skill_GetRequireSkillPoint(param, name));
		}
		
		case TopMenuAction_DrawOption:
		{
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			
			if (RPG_GetLevel(param)			< Skill_GetRequireLevel(param, name) ||
				RPG_GetSkillPoint(param) 	< Skill_GetRequireSkillPoint(param, name) ||
				g_kvRPGData[param].GetNum(name, 0) >= Skill_GetMaxLevel(name))
				buffer[0] = ITEMDRAW_DISABLED;
		}
		
		case TopMenuAction_SelectOption:
		{
			char name[32];
			topmenu.GetObjName(topobj_id, name, sizeof(name));
			
			if (RPG_GetLevel(param)			< Skill_GetRequireLevel(param, name) ||
				RPG_GetSkillPoint(param) 	< Skill_GetRequireSkillPoint(param, name) ||
				g_kvRPGData[param].GetNum(name, 0) >= Skill_GetMaxLevel(name))
				return;
			
			RPG_SetSkillPoint(param, RPG_GetSkillPoint(param) - Skill_GetRequireSkillPoint(param, name));
			g_kvRPGData[param].SetNum(name, g_kvRPGData[param].GetNum(name, 0) + 1);
			
			g_RPGTopMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

int RPG_GetLevel(int client)
{
	return g_kvRPGData[client].GetNum("level", 1);
}

void RPG_SetLevel(int client, int level)
{
	g_kvRPGData[client].SetNum("level", level);
}

int RPG_GetXP(int client)
{
	return g_kvRPGData[client].GetNum("xp", 0);
}

void RPG_SetXP(int client, int value)
{
	g_kvRPGData[client].SetNum("xp", value);
	
	int reqXP = RPG_GetRequireXP(client);
	if (value >= reqXP)
	{
		value -= reqXP;
		
		int nextLevel = RPG_GetLevel(client) + 1;
		RPG_SetLevel(client, nextLevel);
		RPG_SetXP(client, value);
		RPG_SetSkillPoint(client, RPG_GetSkillPoint(client) + 1);
		RPG_SetStetPoint(client, RPG_GetStetPoint(client) + 1);
		
		PrintToChatAll(" \x03[Level UP]\x0C %N 님이\x01 %d로 레벨업 하셨습니다.", client, nextLevel);
	}
}

void RPG_AddXP(int client, int value)
{
	RPG_SetXP(client, RPG_GetXP(client) + value);
}

int RPG_GetRequireXP(int client)
{
	int level = RPG_GetLevel(client);
	float value = 1.0 + (0.1 * (level - 1));
	int reqXP = RoundToFloor(level * 1.0);
	
	return reqXP;
}

int RPG_GetSkillPoint(int client)
{
	return g_kvRPGData[client].GetNum("skillpoint", 1);
}

void RPG_SetSkillPoint(int client, int value)
{
	g_kvRPGData[client].SetNum("skillpoint", value);
}

int RPG_GetStetPoint(int client)
{
	return g_kvRPGData[client].GetNum("stetpoint", 1);
}

void RPG_SetStetPoint(int client, int value)
{
	g_kvRPGData[client].SetNum("stetpoint", value);
}

void GetRPGDataPath(int client, char[] buffer, int maxlength)
{
	Format(buffer, maxlength, "addons/sourcemod/data/tf2_rpg/%d.txt", GetSteamAccountID(client));
}

bool Skill_GetName(const char[] name, char[] buffer, int maxlength)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return false;
	}
		
	g_kvSkillInfo.GetString("name", buffer, maxlength);
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return true;
}

bool Skill_GetAttributeName(const char[] name, char[] buffer, int maxlength)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return false;
	}
	
	g_kvSkillInfo.GetString("attribute_name", buffer, maxlength);
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return true;
}

bool Skill_GetAttributeType(const char[] name, char[] buffer, int maxlength)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return false;
	}
	
	g_kvSkillInfo.GetString("attribute_type", buffer, maxlength);
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return true;
}

float Skill_GetAttributeValue(const char[] name)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return -1.0;
	}
	
	float value = g_kvSkillInfo.GetFloat("attribute_value", 0.0);
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return value;
}

int Skill_GetMaxLevel(const char[] name)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return 0;
	}
		
	int value = g_kvSkillInfo.GetNum("maxLevel", 1);
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return value;
}

int Skill_GetRequireSkillPoint(int client, const char[] name)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return -1;
	}
	
	int value = g_kvSkillInfo.GetNum("skp", 1) + (g_kvRPGData[client].GetNum(name, 0) * g_kvSkillInfo.GetNum("next_skp", 0));
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return value;
}

int Skill_GetRequireLevel(int client, const char[] name)
{
	char secName[64];
	g_kvSkillInfo.GetSectionName(secName, sizeof(secName));
	if (!StrEqual(name, secName))
	{
		if (!g_kvSkillInfo.JumpToKey(name))
			return -1;
	}
	
	int value = g_kvSkillInfo.GetNum("reqLevel", 1) + (g_kvRPGData[client].GetNum(name, 0) * g_kvSkillInfo.GetNum("next_reqLevel", 0));
	if (!StrEqual(name, secName)) g_kvSkillInfo.Rewind();
	
	return value;
}

stock bool Client_PrintKeyHintText(int client, const char[] format, any ...)
{
	static Handle userMessage;
	userMessage = StartMessageOne("KeyHintText", client);

	if (userMessage == INVALID_HANDLE) {
		return false;
	}

	decl String:buffer[254];

	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);

	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
		&& GetUserMessageType() == UM_Protobuf) {

		PbAddString(userMessage, "hints", buffer);
	}
	else {
		BfWriteByte(userMessage, 1);
		BfWriteString(userMessage, buffer);
	}

	EndMessage();

	return true;
}