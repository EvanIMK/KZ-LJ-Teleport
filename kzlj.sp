#include <sourcemod>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <gokz/core>
#include <kztimer>

#pragma semicolon 1
#pragma newdecls required

Database g_DB = null;

char gS_CurrentMap[64];

bool gB_GOKZ = false;
bool gB_KZTimer = false;

public Plugin myinfo =
{
	name = "LJ Room Teleport",
	author = "Evan",
	description = "Teleport to LJ room",
	version = "1.0",
	url = "imkservers.com"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_lj", Command_LJ, "Teleports to LJ room");
	RegConsoleCmd("sm_ljroom", Command_LJ, "Teleports to LJ room");

	RegAdminCmd("sm_setlj", Command_SetLJ, ADMFLAG_GENERIC, "Set the teleport for the LJ room");
	RegAdminCmd("sm_deletelj", Command_DeleteLJ, ADMFLAG_GENERIC, "Delete the teleport for the LJ room");
	RegAdminCmd("sm_dellj", Command_DeleteLJ, ADMFLAG_GENERIC, "Delete the teleport for the LJ room");

	SQL_DBConnect();
}

public void OnMapStart()
{
	GetCurrentMap(gS_CurrentMap, sizeof(gS_CurrentMap));
}

public void OnAllPluginsLoaded()
{
	gB_GOKZ = LibraryExists("gokz-core");
	gB_KZTimer = LibraryExists("KZTimer");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		gB_GOKZ = true;
	}
	else if (StrEqual(name, "KZTimer"))
	{
		gB_KZTimer = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		gB_GOKZ = false;
	}
	else if (StrEqual(name, "KZTimer"))
	{
		gB_KZTimer = false;
	}
}

public Action Command_LJ(int client, int args)
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT * FROM `ljroom` WHERE map = '%s'", gS_CurrentMap);
	g_DB.Query(SQL_GetLJ_Callback, sQuery, GetClientSerial(client));
}

public Action Command_SetLJ(int client, int args)
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT * FROM `ljroom` WHERE map = '%s'", gS_CurrentMap);
	g_DB.Query(SQL_CreateLJ_Callback, sQuery, GetClientSerial(client));
}

public Action Command_DeleteLJ(int client, int args)
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `ljroom` WHERE map = '%s'", gS_CurrentMap);
	g_DB.Query(SQL_DeleteLJ_Callback, sQuery, GetClientSerial(client));
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Table could not be created. Reason: %s", error);
		return;
	}
}

public void SQL_CreateLJ_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	if (results.RowCount > 0)
	{
		if (IsValidClient(client))
		{
			PrintToChat(client, "LJ teleport already exists. Delete the existing one before creating a new one.");
		}

		return;
	}

	float origin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);

	float angle[3];
	GetClientEyeAngles(client, angle);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `ljroom` VALUES('%s', %.2f, %.2f, %.2f, %.2f, %.2f);", gS_CurrentMap, origin[0], origin[1], origin[2], angle[0], angle[1]);

	g_DB.Query(SQL_CreateLJ2_Callback, sQuery, GetClientSerial(client));
}

public void SQL_CreateLJ2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	if (results == null)
	{
		return;
	}

	if (IsValidClient(client))
	{
		PrintToChat(client, "LJ teleport successfully created.");
	}
}

public void SQL_GetLJ_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	if (results.RowCount == 0 || results == null)
	{
		if (IsValidClient(client))
		{
			PrintToChat(client, "This map does not have a LJ room.");
		}

		return;
	}

	float origin[3];
	float angle[3];

	while (results.FetchRow())
	{
		// Is this really necessary? OnMapStart sets this regardless
		results.FetchString(0, gS_CurrentMap, sizeof(gS_CurrentMap));

		origin[0] = results.FetchFloat(1);
		origin[1] = results.FetchFloat(2);
		origin[2] = results.FetchFloat(3);

		angle[0] = results.FetchFloat(4);
		angle[1] = results.FetchFloat(5);
	}

	if (IsValidClient(client))
	{
		if (gB_GOKZ == true)
		{
			GOKZ_StopTimer(client);
			TeleportEntity(client, origin, angle, NULL_VECTOR);
		}

		if (gB_KZTimer == true)
		{
			KZTimer_StopTimer(client);
			TeleportEntity(client, origin, angle, NULL_VECTOR);
		}
	}
}

public void SQL_DeleteLJ_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	if (results == null)
	{
		LogError("Deletion failed. Reason: %s", error);
		return;
	}

	if (IsValidClient(client))
	{
		PrintToChat(client, "Successfully deleted LJ teleport.");
	}
}

void SQL_DBConnect()
{
	g_DB = GetTimerDatabaseHandle();

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `ljroom`(map VARCHAR(30) NOT NULL PRIMARY KEY, `x` FLOAT(8) NOT NULL, `y` FLOAT(8) NOT NULL, `z` FLOAT(8) NOT NULL, `x1` FLOAT(8) NOT NULL, `y1` FLOAT(8) NOT NULL);");

	g_DB.Query(SQL_CreateTable_Callback, sQuery);
}

stock Database GetTimerDatabaseHandle()
{
	// This is techincally not even needed, just provides a more helpful(?) message
	// -- SQL_Connect would throw on non-existent database configuration
	if (!SQL_CheckConfig("kzlj"))
	{
		SetFailState("\"kzlj\" section is missing from databases.cfg");
	}

	char error[256];
	Database db = SQL_Connect("kzlj", true, error, sizeof(error));

	if (db == null || error[0] != '\0')
	{
		SetFailState("Failed to connect to database. Reason: %s", error);
	}

	return db;
}
