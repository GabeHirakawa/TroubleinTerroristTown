#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <ttt_shop>
#include <ttt>
#include <config_loader>
#include <CustomPlayerSkins>

#define SHORT_NAME "tag"
#define LONG_NAME "TA-Grenade"
#define PLUGIN_NAME TTT_PLUGIN_NAME ... " - TA-Grenade"

int g_iTPrice = 0;
int g_iTCount = 0;
int g_iTPCount[MAXPLAYERS + 1] =  { 0, ... };

bool g_bPlayerIsTagged[MAXPLAYERS + 1] = { false, ... };

float g_fTaggingEndTime[MAXPLAYERS + 1] = { 0.0, ... };

float g_fTagrenadeRange = 0.0;
float g_fTagrenadeTime = 0.0;

bool g_bShowPlayersBehindWalls = false;

char g_sConfigFile[PLATFORM_MAX_PATH] = "";

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = "Bara, zipcore & Neuro Toxin",
	description = TTT_PLUGIN_DESCRIPTION,
	version = TTT_PLUGIN_VERSION,
	url = TTT_PLUGIN_URL
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("TTT_TAGrenade", Native_TAGrenade);
	RegPluginLibrary("ttt_tagrenade");
	return APLRes_Success;
}

public void OnPluginStart()
{
	TTT_IsGameCSGO();
	
	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/tagrenade.cfg");

	Config_Setup("TTT-TAGrenade", g_sConfigFile);
	
	g_iTPrice = Config_LoadInt("tag_traitor_price", 9000, "The amount of credits for tagrenade costs as traitor. 0 to disable.");
	g_iTCount = Config_LoadInt("tag_traitor_count", 1, "The amount of usages for tagrenade per round as innocent. 0 to disable.");
	g_fTagrenadeRange = Config_LoadFloat("tag_tagrenade_distance", 1000.0, "Sets the proximity in which the tactical grenade will tag an opponent.");
	g_fTagrenadeTime = Config_LoadFloat("tag_tagrenade_time", 3.5, "How long a player is tagged for in seconds.");
	g_bShowPlayersBehindWalls = Config_LoadBool("tag_players_behind_walls", true, "Tag players behind a wall?");
	
	Config_Done();
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("tagrenade_detonate", OnTagrenadeDetonate);
}

public void OnClientDisconnect(int client)
{
	ResetTAG(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(TTT_IsClientValid(client))
		ResetTAG(client);
}

public void OnAllPluginsLoaded()
{
	TTT_RegisterCustomItem(SHORT_NAME, LONG_NAME, g_iTPrice, TTT_TEAM_TRAITOR);
}

public Action TTT_OnItemPurchased(int client, const char[] itemshort)
{
	if(TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if(StrEqual(itemshort, SHORT_NAME, false))
		{
			int role = TTT_GetClientRole(client);
			
			if(role == TTT_TEAM_TRAITOR && g_iTPCount[client] >= g_iTCount)
				return Plugin_Stop; // TODO: Add message
				
			GivePlayerItem(client, "weapon_tagrenade");
			
			g_iTPCount[client]++;
		}
	}
	return Plugin_Continue;
}

public void OnTagrenadeDetonate(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	Handle pack = CreateDataPack();
	WritePackCell(pack, userid);
	WritePackCell(pack, GetEventInt(event, "entityid"));
	WritePackFloat(pack, GetEventFloat(event, "x"));
	WritePackFloat(pack, GetEventFloat(event, "y"));
	WritePackFloat(pack, GetEventFloat(event, "z"));
	CreateTimer(0.0, OnGetTagrenadeTimes, pack);
}

public Action OnGetTagrenadeTimes(Handle timer, any data)
{
	Handle pack = view_as<Handle>(data);
	ResetPack(pack);
	
	int client = GetClientOfUserId(ReadPackCell(pack));
	if (client == 0)
	{
		CloseHandle(pack);
		return Plugin_Continue;
	}
	
	int entity = ReadPackCell(pack);
	
	float position[3];
	float targetposition[3];
	float distance;
	
	position[0] = ReadPackFloat(pack);
	position[1] = ReadPackFloat(pack);
	position[2] = ReadPackFloat(pack);
	CloseHandle(pack);
	
	LoopValidClients(target)
	{
		// Ignore bots
		if(IsFakeClient(client))
			continue;
		
		// Ignore death players
		if(!IsPlayerAlive(client))
			continue;
		
		// Don't hit self
		if (client == target)
			continue;
		
		// Ignore players without role
		if (TTT_GetClientRole(client) < TTT_TEAM_INNOCENT)
			continue;
			
		// Remove game tagging (not FFA compatible)
		SetEntPropFloat(target, Prop_Send, "m_flDetectedByEnemySensorTime", 0.0);
		
		// Check distance
		GetClientEyePosition(target, targetposition);
		distance = GetVectorDistance(position, targetposition);
		
		// Not in range
		if (distance > g_fTagrenadeRange)
			continue;
		
		// Visible?
		if(g_bShowPlayersBehindWalls)
		{
			Handle trace = TR_TraceRayFilterEx(position, targetposition, MASK_VISIBLE, RayType_EndPoint, OnTraceForTagrenade, entity);
			if (TR_DidHit(trace) && TR_GetEntityIndex(trace) == target)
				g_fTaggingEndTime[target] = GetGameTime() + g_fTagrenadeTime;
			CloseHandle(trace);
		}
		else
			g_fTaggingEndTime[target] = GetGameTime() + g_fTagrenadeTime;
	}
	return Plugin_Continue;
}

public bool OnTraceForTagrenade(int entity, int contentsMask, any tagrenade)
{
	if (entity == tagrenade)
		return false;
	return true;
}

float GetPlayerTagEndTime(int client)
{
	return g_fTaggingEndTime[client];
}

void ResetTAG(int client)
{
	g_iTPCount[client] = 0;
	g_fTaggingEndTime[client] = 0.0
	g_bPlayerIsTagged[client] = false;
}

public int Native_TAGrenade(Handle plugin, int numParams)
{
	int target = GetNativeCell(1);
	
	if(GetGameTime() < GetPlayerTagEndTime(target))
		return true;
	return false;
}