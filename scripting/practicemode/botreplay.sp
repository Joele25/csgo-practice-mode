#define REPLAY_NAME_LENGTH 128
#define REPLAY_ID_LENGTH 16
#define MAX_REPLAY_CLIENTS 5

// Ideas:
// 1. Remove local storage and always go the KV structure?
// 2. When starting a replay, give it a temp name, and then they can rename it later?

bool g_StopBotSignal[MAXPLAYERS + 1];

float g_CurrentRecordingStartTime = 0.0;
int g_CurrentRecordingRole = -1;

char g_ReplayId[REPLAY_ID_LENGTH];
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
  SaveReplayKv();
  GarbageCollectReplays();
}

public void Replays_OnThrowGrenade(int entity, int client, GrenadeType grenadeType, const float origin[3],
                            const float velocity[3]) {
  if (g_CurrentRecordingRole >= 0) {
    float delay = GetGameTime() - g_CurrentRecordingStartTime;
    for (int i = 0; i <= MaxClients; i++) {
      AddReplayNade(i, grenadeType, delay, origin, velocity);
    }
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
    } else {
      LogError("Tried replaying index=%d nade on %L, but list only size=%d", index, client, length);
    }
  }
}

public void SaveReplayKv() {
  char map[PLATFORM_MAX_PATH];
  GetCleanMapName(map, sizeof(map));
  char replayFile[PLATFORM_MAX_PATH + 1];
  BuildPath(Path_SM, replayFile, sizeof(replayFile), "data/practicemode/replays/%s.cfg", map);
  DeleteFile(replayFile);
  g_ReplaysKv.ExportToFile(replayFile);
}

public bool HasActiveReplay() {
  return strlen(g_ReplayId) > 0;
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
    char name[64];
    Format(name, sizeof(name), "Replay Bot %d", i + 1);
    g_ReplayBotClients[i] = GetLiveBot(name);
  }

  // if (IsValidClient(g_ReplayBotClients[MAX_REPLAY_CLIENTS - 1])) {
  //   int largestUserid = GetClientUserId(g_ReplayBotClients[MAX_REPLAY_CLIENTS - 1]);
  //   for (int i = 1; i <= MaxClients; i++) {
  //     if (IsValidClient(i) && IsFakeClient(i) && !IsClientSourceTV(i)) {
  //       int userid = GetClientUserId(i);
  //       if (userid > largestUserid) {
  //         KickClient(i);
  //       }
  //     }
  //   }
  // }

  return Plugin_Handled;
}

void InitReplayFunctions() {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    g_ReplayBotClients[i] = -1;
  }

  int numHumans = 0;
  for (int i = 0; i <= MAXPLAYERS; i++) {
    if (IsPlayer(i)) {
      numHumans++;
    }
  }
  for (int i = 0; i < MAX_REPLAY_CLIENTS + numHumans; i++) {
    ServerCommand("bot_add");
  }

  CreateTimer(0.2, Timer_GetBots);

  g_BotInit = true;
  g_InBotReplayMode = true;
  g_CurrentRecordingRole = -1;

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

  if (HasActiveReplay()) {
    GiveNewReplayMenu(client);
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

  if (strlen(g_ReplayId) == 0) {
    return Plugin_Handled;
  }

  char buffer[REPLAY_NAME_LENGTH];
  GetCmdArgString(buffer, sizeof(buffer));
  if (strlen(buffer) == 0) {
    PM_Message(client, "You didn't give a name! Use: .namereplay <name> first.");
  } else {
    PM_Message(client, "Saved replay name.");
    SetReplayName(g_ReplayId, buffer);
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
  g_ReplayId = "";
  g_CurrentRecordingRole = -1;

  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    g_StopBotSignal[i] = false;
  }
}

stock void RunCurrentReplay(int exclude = -1) {
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    if (i == exclude) {
      continue;
    }

    int bot = g_ReplayBotClients[i];
    if (IsValidClient(bot) && HasRoleRecorded(g_ReplayId, i)) {
      char filepath[PLATFORM_MAX_PATH + 1];
      GetRoleFile(g_ReplayId, i, filepath, sizeof(filepath));
      PlayRecord(bot, filepath);
    }
  }
}

void PlayRecord(int client, const char[] filepath) {
  if (!IsValidClient(client)) {
    return;
  }

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
    LogError("Error playing record %s on client %d", filepath, client);
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

public void GarbageCollectReplays() {
  // TODO: when bot replay keyvalue files are backed up this will also have to
  // check older versions before garbage collecting.
  ArrayList replaysInUse = new ArrayList(PLATFORM_MAX_PATH + 1);
  if (g_ReplaysKv.GotoFirstSubKey()) {
    do {
      for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
        char role[64];
        Format(role, sizeof(role), "role%d", i + 1);
        if (g_ReplaysKv.JumpToKey(role)) {
          char buffer[PLATFORM_MAX_PATH + 1];
          g_ReplaysKv.GetString("file", buffer, sizeof(buffer));
          replaysInUse.PushString(buffer);
          g_ReplaysKv.GoBack();
        }
      }
    } while (g_ReplaysKv.GotoNextKey());
    g_ReplaysKv.GoBack();
  }

  char path[PLATFORM_MAX_PATH + 1];
  ArrayList loadedRecords = BotMimic_GetLoadedRecordList();  // Don't close this.
  for (int i = 0; i < loadedRecords.Length; i++) {
    loadedRecords.GetString(i, path, sizeof(path));
    if (FindStringInList(replaysInUse, sizeof(path), path) == -1) {
      BotMimic_DeleteRecord(path);
    }
  }

  delete replaysInUse;
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
