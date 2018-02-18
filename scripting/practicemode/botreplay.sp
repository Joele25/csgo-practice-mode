#define REPLAY_NAME_LENGTH 128
#define REPLAY_ROLE_DESCRIPTION_LENGTH 256
#define REPLAY_ID_LENGTH 16
#define MAX_REPLAY_CLIENTS 5
#define DEFAULT_REPLAY_NAME "unnamed - use .namereplay on me!"

// Ideas:
// 1. ADD A WARNING WHEN YOU NADE TOO EARLY IN THE REPLAY!
// 2. Does practicemode-saved nade data respect cancellation?

// If any data has been changed since load, this should be set.
// All Set* data methods should set this to true.
bool g_UpdatedReplayKv = false;

bool g_RecordingFullReplay = false;
// TODO: find when to reset g_RecordingFullReplayClient
int g_RecordingFullReplayClient = -1;

bool g_StopBotSignal[MAXPLAYERS + 1];

float g_CurrentRecordingStartTime[MAXPLAYERS + 1];
int g_CurrentRecordingRole[MAXPLAYERS + 1];

// TODO: make g_ReplayId per-client
char g_ReplayId[MAXPLAYERS + 1][REPLAY_ID_LENGTH];
int g_ReplayBotClients[MAX_REPLAY_CLIENTS];

int g_CurrentReplayNadeIndex[MAXPLAYERS + 1];
ArrayList g_NadeReplayData[MAXPLAYERS + 1];

public void BotReplay_MapStart() {
  g_BotInit = false;
  delete g_ReplaysKv;
  g_ReplaysKv = new KeyValues("Replays");

  char map[PLATFORM_MAX_PATH];
  GetCleanMapName(map, sizeof(map));

  char replayFile[PLATFORM_MAX_PATH + 1];
  BuildPath(Path_SM, replayFile, sizeof(replayFile), "data/practicemode/replays/%s.cfg", map);
  g_ReplaysKv.ImportFromFile(replayFile);

  for (int i = 0; i <= MaxClients; i++) {
    delete g_NadeReplayData[i];
    g_NadeReplayData[i] = new ArrayList(8);
  }
}

public void BotReplay_MapEnd() {
  MaybeWriteNewReplayData();

  // TODO: re-enable GarbageCollectReplays once it doesn't delete files currently saved in
  // backups files.
  GarbageCollectReplays();
}

public void Replays_OnThrowGrenade(int entity, int client, GrenadeType grenadeType, const float origin[3],
                            const float velocity[3]) {
  if (g_CurrentRecordingRole[client] >= 0) {
    float delay = GetGameTime() - g_CurrentRecordingStartTime[client];
    AddReplayNade(client, grenadeType, delay, origin, velocity);
  }

  if (BotMimic_IsPlayerMimicing(client)) {
    int index = g_CurrentReplayNadeIndex[client];
    int length = g_NadeReplayData[client].Length;
    if (index < length) {
      float delay = 0.0;
      GrenadeType type;
      float nadeOrigin[3];
      float nadeVelocity[3];
      GetReplayNade(client, index, type, delay, nadeOrigin, nadeVelocity);
      TeleportEntity(entity, nadeOrigin, NULL_VECTOR, nadeVelocity);
      g_CurrentReplayNadeIndex[client]++;
    }
  }
}

public bool HasActiveReplay(int client) {
  return ReplayExists(g_ReplayId[client]);
}

public bool IsReplayBot(int client) {
  if (!IsValidClient(client) || !IsFakeClient(client) || IsClientSourceTV(client)) {
    return false;
  }
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    if (g_ReplayBotClients[i] == client) {
      return true;
    }
  }
  return false;
}

public Action Timer_GetBots(Handle timer) {
  g_BotInit = true;

  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    char name[MAX_NAME_LENGTH];
    Format(name, sizeof(name), "Replay Bot %d", i + 1);
    g_ReplayBotClients[i] = GetLiveBot(name);
  }

  return Plugin_Handled;
}

void InitReplayFunctions() {
  ResetData();
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    g_ReplayBotClients[i] = -1;
  }

  ServerCommand("bot_quota_mode normal");
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    ServerCommand("bot_add");
  }

  CreateTimer(0.2, Timer_GetBots);

  g_BotInit = true;
  g_InBotReplayMode = true;
  g_RecordingFullReplay = false;

  // Settings we need to have the mode work
  DisableSettingById("respawning");
  ServerCommand("mp_death_drop_gun 1");
}

public Action Command_Replay(int client, int args) {
  if (!g_InPracticeMode) {
    return Plugin_Handled;
  }

  if (!g_BotMimicLoaded) {
    PM_Message(client, "You need the botmimic plugin loaded to use replay functions.");
    return Plugin_Handled;
  }

  if (!g_CSUtilsLoaded) {
    PM_Message(client, "You need the csutils plugin loaded to use replay functions.");
    return Plugin_Handled;
  }

  if (!g_BotInit) {
    InitReplayFunctions();
  }

  if (HasActiveReplay(client)) {
    GiveReplayEditorMenu(client);
  } else {
    GiveMainReplaysMenu(client);
  }

  return Plugin_Handled;
}

public Action Command_Replays(int client, int args) {
  if (!g_InPracticeMode) {
    return Plugin_Handled;
  }

  if (!g_BotMimicLoaded) {
    PM_Message(client, "You need the botmimic plugin loaded to use replay functions.");
    return Plugin_Handled;
  }

  if (!g_CSUtilsLoaded) {
    PM_Message(client, "You need the csutils plugin loaded to use replay functions.");
    return Plugin_Handled;
  }

  if (!g_BotInit) {
    InitReplayFunctions();
  }

  GiveMainReplaysMenu(client);
  return Plugin_Handled;
}

public Action Command_NameReplay(int client, int args) {
  if (!g_InPracticeMode) {
    return Plugin_Handled;
  }

  if (!HasActiveReplay(client)) {
    return Plugin_Handled;
  }

  char buffer[REPLAY_NAME_LENGTH];
  GetCmdArgString(buffer, sizeof(buffer));
  if (strlen(buffer) == 0) {
    PM_Message(client, "You didn't give a name! Use: .namereplay <name> first.");
  } else {
    PM_Message(client, "Saved replay name.");
    SetReplayName(g_ReplayId[client], buffer);
  }
  return Plugin_Handled;
}

public int GetLargestBotUserId() {
  int largestUserid = -1;
  for (int i = 1; i <= MaxClients; i++) {
    if (IsValidClient(i) && IsFakeClient(i) && !IsClientSourceTV(i)) {
      int userid = GetClientUserId(i);
      if (userid > largestUserid) {
        if (i == g_ReplayBotClients[0] || i == g_ReplayBotClients[1] ||
            i == g_ReplayBotClients[2] || i == g_ReplayBotClients[3] ||
            i == g_ReplayBotClients[4]) {
          continue;
        }
        largestUserid = userid;
      }
    }
  }
  return largestUserid;
}

public int GetLiveBot(const char[] name) {
  int largestUserid = GetLargestBotUserId();
  if (largestUserid == -1) {
    return -1;
  }

  int bot = GetClientOfUserId(largestUserid);
  if (!IsValidClient(bot)) {
    return -1;
  }

  SetClientName(bot, name);
  CS_SwitchTeam(bot, CS_TEAM_T);
  KillBot(bot);
  return bot;
}

public void KillBot(int client) {
  // TODO: get a better default spot to put the bot.
  float botOrigin[3] = {-7000.0, 0.0, 0.0};
  TeleportEntity(client, botOrigin, NULL_VECTOR, NULL_VECTOR);
  ForcePlayerSuicide(client);
}

public void ResetData() {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    g_StopBotSignal[i] = false;
  }
  for (int i = 0; i <= MaxClients; i++) {
    g_CurrentRecordingRole[i] = -1;
    g_ReplayId[i] = "";
  }
}

stock void RunReplay(const char[] id, int exclude = -1) {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    if (i == exclude) {
      continue;
    }

    int bot = g_ReplayBotClients[i];
    if (IsValidClient(bot) && HasRoleRecorded(id, i)) {
      ReplayRole(id, bot, i);
    }
  }
}

void ReplayRole(const char[] id, int client, int role) {
  if (!IsValidClient(client)) {
    return;
  }

  char filepath[PLATFORM_MAX_PATH + 1];
  GetRoleFile(id, role, filepath, sizeof(filepath));
  GetRoleNades(id, role, client);

  g_CurrentReplayNadeIndex[client] = 0;
  CS_RespawnPlayer(client);
  DataPack pack = new DataPack();
  pack.WriteCell(client);
  pack.WriteString(filepath);
  g_StopBotSignal[client] = false;
  g_CurrentReplayNadeIndex[client] = 0;
  RequestFrame(StartReplay, pack);
}

public void StartReplay(DataPack pack) {
  pack.Reset();
  int client = pack.ReadCell();
  char filepath[128];
  pack.ReadString(filepath, sizeof(filepath));

  BMError err = BotMimic_PlayRecordFromFile(client, filepath);
  if (err != BM_NoError) {
    char errString[128];
    BotMimic_GetErrorString(err, errString, sizeof(errString));
    LogError("Error playing record %s on client %d: %s", filepath, client, errString);
  }

  delete pack;
}

public void BotMimic_OnPlayerMimicLoops(int client) {
  if (!g_InPracticeMode) {
    return;
  }

  if (g_StopBotSignal[client]) {
    BotMimic_ResetPlayback(client);
    BotMimic_StopPlayerMimic(client);
    RequestFrame(Timer_DelayKillBot, GetClientSerial(client));
  } else {
    g_StopBotSignal[client] = true;
  }
}

public void Timer_DelayKillBot(int serial) {
  int client = GetClientFromSerial(serial);
  if (IsValidClient(client) && IsPlayerAlive(client)) {
    float zero[3];
    TeleportEntity(client, zero, zero, zero);
    KillBot(client);
  }
}

public void AddReplayNade(int client, GrenadeType type, float delay, const float[3] origin,
                   const float[3] velocity) {
  int index = g_NadeReplayData[client].Push(type);
  g_NadeReplayData[client].Set(index, view_as<int>(delay), 1);
  g_NadeReplayData[client].Set(index, view_as<int>(origin[0]), 2);
  g_NadeReplayData[client].Set(index, view_as<int>(origin[1]), 3);
  g_NadeReplayData[client].Set(index, view_as<int>(origin[2]), 4);
  g_NadeReplayData[client].Set(index, view_as<int>(velocity[0]), 5);
  g_NadeReplayData[client].Set(index, view_as<int>(velocity[1]), 6);
  g_NadeReplayData[client].Set(index, view_as<int>(velocity[2]), 7);
}

public void GetReplayNade(int client, int index, GrenadeType& type, float& delay, float origin[3],
                   float velocity[3]) {
  type = g_NadeReplayData[client].Get(index, 0);
  delay = g_NadeReplayData[client].Get(index, 1);
  origin[0] = g_NadeReplayData[client].Get(index, 2);
  origin[1] = g_NadeReplayData[client].Get(index, 3);
  origin[2] = g_NadeReplayData[client].Get(index, 4);
  velocity[0] = g_NadeReplayData[client].Get(index, 5);
  velocity[1] = g_NadeReplayData[client].Get(index, 6);
  velocity[2] = g_NadeReplayData[client].Get(index, 7);
}

public void CancelAllReplays() {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    int bot = g_ReplayBotClients[i];
    if (IsValidClient(bot) && BotMimic_IsPlayerMimicing(bot)) {
      BotMimic_StopPlayerMimic(bot);
      RequestFrame(Timer_DelayKillBot, GetClientSerial(bot));
    }
  }
}

public bool IsReplayPlaying() {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    int bot = g_ReplayBotClients[i];
    if (IsValidClient(bot) && BotMimic_IsPlayerMimicing(bot)) {
      return true;
    }
  }
  return false;
}
