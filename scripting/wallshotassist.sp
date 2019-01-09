/*
        __
     .-'  |
    /   <\|
   /     \'
   |_.- o-o
   / C  -._)\
  /',        |
 |   `-,_,__,'
 (,,)====[_]=|
   '.   ____/
    | -|-|_
    |____)_) 
*/

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

#define PI 3.1415926535

//#define DEBUG_LINES
#if defined DEBUG_LINES
	#include <smlib>
#endif

#undef REQUIRE_PLUGIN
#include <updater>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_DESCRIPTION "Tool to assist with wallshot timing and location"
#define UPDATE_URL_BASE "http://raw.github.com/laurirasanen/WallshotAssist"
#define UPDATE_URL_BRANCH "master"
#define UPDATE_URL_FILE "updatefile.txt"

int g_iBeamSprite;
int g_iHaloSprite;

bool g_bEnabled[MAXPLAYERS+1];
bool g_bLateLoad;

char g_URLMap[256];

public Plugin myinfo =
{
	name = "Wallshot Assist",
	author = "Larry",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://jump.tf/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() 
{
	CreateConVar("sm_wallshotassist_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_wsa", cmdWSA);

	Format(g_URLMap, sizeof(g_URLMap), "%s/master/%s", UPDATE_URL_BASE, UPDATE_URL_FILE);
	if (LibraryExists("updater")) 
	{
		Updater_AddPlugin(g_URLMap);
	}
	else
	{
		LogMessage("updater not found. Wallshot Assist will not update automatically.");
	}

	if (g_bLateLoad) 
	{
		PrintToChatAll("\x01\x03WSA Reloaded");
	}
}

public int Updater_OnPluginUpdated() 
{
	LogMessage("Wallshot Assist update complete.");
	ReloadPlugin();
}

public void OnMapStart() 
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laser.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
}

public void OnMapEnd() {
	for (int i = 0; i < MaxClients; i++) {
		g_bEnabled[i] = false;
	}
}

public void OnClientDisconnect(int client) {
	g_bEnabled[client] = false;
}

public Action cmdWSA(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	g_bEnabled[client] = !g_bEnabled[client];
	PrintToChat(client, "\x01[\x03WSA\x01] Wallshot assist\x03 %s", g_bEnabled[client] ? "enabled" : "disabled");
	return Plugin_Handled;
}

public void OnGameFrame()
{
	for(int client = 1; client < MaxClients; client++)
	{
		if (client < MaxClients &&
		IsClientConnected(client) &&
		IsClientInGame(client) &&
		!IsFakeClient(client) &&
		(GetClientTeam(client) == TFTeam_Blue || GetClientTeam(client) == TFTeam_Red) &&
		g_bEnabled[client])
		{
			int ticksToRocketHit;
			float vEyePos[3];
			float vEyeAng[3];
			float vEnd[3];
			float vPlane[3];
			float vMaxs[3];

			GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);
			GetClientEyePosition(client, vEyePos);
			GetClientEyeAngles(client, vEyeAng);

			TR_TraceRayFilter(vEyePos, vEyeAng, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
			if (TR_DidHit(INVALID_HANDLE)) 
			{
				TR_GetEndPosition(vEnd, INVALID_HANDLE);
				TR_GetPlaneNormal(INVALID_HANDLE, vPlane);
				ticksToRocketHit = GetTicksTillRocketHit(client, vEnd, vEyeAng, vEyePos);
			}
			else
				continue;

			float m_vecAbsOrigin[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", m_vecAbsOrigin);
			float vVelocity[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vVelocity);

			// don't draw on ramps
			if(vPlane[2] > 0.7 || vPlane[2] < -0.7)
				continue;
			// don't draw if distance greater than 2 seconds
			if(GetVectorDistance(m_vecAbsOrigin, vEnd) > 2*1100)
				continue;

			// player position when rocket would hit
			float vFuturePos[3];
			for(int i=0; i<3; i++)
			{
				vFuturePos[i] = m_vecAbsOrigin[i] + vVelocity[i]*ticksToRocketHit/66.66666666;
			}
			// gravity 800/s^2 = 0.18/t
			vFuturePos[2] += DistanceFromAcceleration(vVelocity[2]/66.66666666, -0.18, ticksToRocketHit);


			// get direction to plane now and in future
			float vOldDirection[3];
			SubtractVectors(vEnd, m_vecAbsOrigin, vOldDirection);
			float vFutureDirection[3];
			SubtractVectors(vEnd, vFuturePos, vFutureDirection);

			// compare dot products to see if
			// we would pass through the plane
			float oldDot = GetVectorDotProduct(vOldDirection, vPlane);
			float futureDot = GetVectorDotProduct(vFutureDirection, vPlane);

			// future position is on the other side of the plane from old pos
			if((oldDot <= 0 && futureDot > 0) || (oldDot >= 0 && futureDot < 0))
			{				
				// project to plane
				float futureDistance = GetVectorDotProduct(vPlane, vFutureDirection);
				float vDepenetration[3];
				for(int i = 0; i < 3; i++)
					vDepenetration[i] = vPlane[i];
				ScaleVector(vDepenetration, futureDistance);
				AddVectors(vFuturePos, vDepenetration, vFuturePos);
			}

			// get distance to plane
			SubtractVectors(vEnd, vFuturePos, vFutureDirection);
			float signedDistance = GetVectorDotProduct(vPlane, vFutureDirection);

			// get closest point on plane
			float vTranslation[3];
			for(int i = 0; i < 3; i++)
				vTranslation[i] = vPlane[i];
			ScaleVector(vTranslation, signedDistance);
			float vClosestPoint[3];
			AddVectors(vFuturePos, vTranslation, vClosestPoint);

			// don't bother drawing if we're nowhere near rocket
			if(GetVectorDistance(vFuturePos, vClosestPoint) > 500.0)
				continue;
			// don't draw if we're not aiming anywhere near
			if(GetVectorDistance(vClosestPoint, vEnd) > 500.0)
				continue;

			// draw circle lower than player origin so you can see it better
			vClosestPoint[2] -= 20.0;
			vFuturePos[2] -= 20.0;
			DrawCircle(vClosestPoint, vPlane, 20.0, 0.122, client, GetVectorDistance(vFuturePos, vClosestPoint));

			// debug stuff
			#if defined DEBUG_LINES
				// player box
				float vPlayerMins[3];
				float vPlayerMaxs[3];
				for(int i = 0; i < 3; i++)
				{
					vPlayerMins[i] = vFuturePos[i];
					vPlayerMaxs[i] = vFuturePos[i];
				}
				vPlayerMins[0] -= 24.0;
				vPlayerMins[1] -= 24.0;
				vPlayerMaxs[0] += 24.0;
				vPlayerMaxs[1] += 24.0;
				vPlayerMaxs[2] += 72.0;
				Effect_DrawBeamBoxToClient(client, vPlayerMins, vPlayerMaxs, g_iBeamSprite, g_iBeamSprite, 0, 0, 0.1, 0.2, 0.2, 0, 0.0, { 255, 0, 0, 255 }, 0);

				// rocket line
				DrawLineToClient(client, vEyePos, vEnd, 0.2, { 0, 255, 255, 255 });
			#endif
		}
	}
}

bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles
	int entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;
}

// modified from nolem's speedshotassist
// https://github.com/arispoloway/SpeedshotAssist/blob/master/scripting/speedshotassist.sp#L129
int GetTicksTillRocketHit(int client, float vEnd[3], float vEyeAng[3], float vEyePos[3]) 
{
	// rockets fire from below, and in the case of stock,
	// from to the right of weapon position
	// https://github.com/csnxs/source-2007/blob/master/src_main/game/shared/tf2/weapon_rocketlauncher.cpp#L168
	//vEyePos[2] -= 8.0;

	// FIXME:
	// rocket should fire from the right of the weapon position, not eye position
	// also it doesnt work

	/*char sWeaponName[64];
	GetClientWeapon(client, sWeaponName, sizeof(sWeaponName));
	// TODO:
	// weapon names
	if(StrEqual(sWeaponName, "tf_weapon_rocketlauncher"))
	{
		float vUp[3] = { 0.0, 0.0, 1.0 };
		float vRight[3];
		GetVectorCrossProduct(vEyeAng, vUp, vRight);
		NormalizeVector(vRight, vRight);
		ScaleVector(vRight, 12.0);
		for(int i = 0; i < 3; i++)
			vEyePos[i] += vRight[i]*12;
	}*/

	float distance = SquareRoot(Pow(vEnd[0]-vEyePos[0], 2.0) + Pow(vEnd[1]-vEyePos[1], 2.0) + Pow(vEnd[2]-vEyePos[2], 2.0));

	// rocket speed 1100/s = 16.5/t
	int ticks = RoundToFloor((distance) / 16.5);
	return ticks;
}

// modified from
// https://github.com/arispoloway/SpeedshotAssist/blob/master/scripting/speedshotassist.sp#L224
void DrawCircle(float vecLocation[3], float normal[3], float radius, float angleIncr, int client, float distance) {
	float angle;
	float xy;
	float z;

	float pos1[3];
	float pos2[3];

	float vRight[3];
	GetVectorCrossProduct(normal, vecLocation, vRight);
	NormalizeVector(vRight, vRight);

	//Create the start position for the first part of the beam
	pos2 = vecLocation;
	pos2[0] += radius*vRight[0];
	pos2[1] += radius*vRight[1];

	int RGBA[4];
	float lowerThreshold = 20.0;
	float upperThreshold = 110.0;
	if(distance > upperThreshold)
	{
		RGBA[0] = 255;
		RGBA[1] = 255 - RoundToFloor(distance) < 0 ? 0 : 255 - RoundToFloor(distance);
	}
	else if(distance < lowerThreshold)
	{
		RGBA[0] = RoundToFloor(distance*2.0) > 255 ? 255 : RoundToFloor(distance*2.0);
		RGBA[1] = 255;
	}
	else
	{
		RGBA[0] = RoundToFloor(distance);
		RGBA[1] = 255 - RoundToFloor(distance);
	}

	RGBA[2] = 0;
	RGBA[3] = 255;

	while (angle <= 2 * (PI + angleIncr)) {
		xy = radius * Cosine(angle);
		z = radius * Sine(angle);

		pos1 = vecLocation;
		pos1[0] += xy*vRight[0];
		pos1[1] += xy*vRight[1];
		pos1[2] += z;

		TE_SetupBeamPoints(pos1, pos2, g_iBeamSprite, g_iHaloSprite, 0, 0, 0.1, 2.0, 2.0, 5, 10.0, RGBA, 5);
		TE_SendToClient(client);

		pos2 = pos1;

		angle += angleIncr;
	}
}


float DistanceFromAcceleration(float velocity, float acceleration, int ticks) 
{
	float distance;
	for(int i = 0; i < ticks; i++)
	{
		velocity += acceleration;
		distance += velocity;
	}

	return distance;
}

void DrawLineToClient(int client, float vStart[3], float vEnd[3], float thickness, int rgba[4]) 
{
	// origin, end, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed
	TE_SetupBeamPoints(vStart, vEnd, g_iBeamSprite, g_iHaloSprite, 0, 0, 0.1, thickness, thickness, 5, 10.0, rgba, 5);
	TE_SendToClient(client);
}