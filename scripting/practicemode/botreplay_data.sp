#define DEFAULT_KEY_LENGTH 64

stock void GiveMainReplaysMenu(int client, int pos = 0) {
  Menu menu = new Menu(ReplaysMenuHandler);
  menu.SetTitle("Replay list");
  menu.AddItem("add_new", "Add new replay");

  CleanupNullReplays();

  char id[REPLAY_ID_LENGTH];
  char name[REPLAY_NAME_LENGTH];
  if (g_ReplaysKv.GotoFirstSubKey()) {
    do {
      g_ReplaysKv.GetSectionName(id, sizeof(id));
      g_ReplaysKv.GetString("name", name, sizeof(name));
      menu.AddItem(id, name);
    } while (g_ReplaysKv.GotoNextKey());
    g_ReplaysKv.GoBack();
  }

  menu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}

public int ReplaysMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char buffer[REPLAY_ID_LENGTH + 1];
    menu.GetItem(param2, buffer, sizeof(buffer));

    if (StrEqual(buffer, "add_new")) {
      IntToString(GetNextReplayId(), g_ReplayId, sizeof(g_ReplayId));
      SetReplayName(g_ReplayId, DEFAULT_REPLAY_NAME);
    } else {
      strcopy(g_ReplayId, sizeof(g_ReplayId), buffer);
    }

    GiveNewReplayMenu(client);
  } else if (action == MenuAction_End) {
    delete menu;
  }
}

public void MaybeWriteNewReplayData() {
  if (g_UpdatedReplayKv) {
    g_ReplaysKv.Rewind();
    BackupReplayData(g_ReplaysKv);

    char map[PLATFORM_MAX_PATH];
    GetCleanMapName(map, sizeof(map));
    char replayFile[PLATFORM_MAX_PATH + 1];
    BuildPath(Path_SM, replayFile, sizeof(replayFile), "data/practicemode/replays/%s.cfg", map);
    DeleteFile(replayFile);
    g_ReplaysKv.ExportToFile(replayFile);

    g_UpdatedReplayKv = false;
  }
}

public void CleanupNullReplays() {
  // TODO: this should go through all replay ids, and delete those that have
  // no name specified and no roles specified.
}

public int GetNextReplayId() {
  int largest = -1;
  char id[REPLAY_ID_LENGTH];
  if (g_ReplaysKv.GotoFirstSubKey()) {
    do {
      g_ReplaysKv.GetSectionName(id, sizeof(id));
      int idvalue = StringToInt(id);
      if (idvalue > largest) {
        largest = idvalue;
      }
    } while (g_ReplaysKv.GotoNextKey());
    g_ReplaysKv.GoBack();
  }
  return largest + 1;
}

public void GetRoleString(int role, char buf[DEFAULT_KEY_LENGTH]) {
  Format(buf, sizeof(buf), "role%d", role + 1);
}

public void DeleteReplay(const char[] id) {
  g_UpdatedReplayKv = true;
  if (g_ReplaysKv.JumpToKey(id)) {
    g_ReplaysKv.DeleteThis();
    g_ReplaysKv.Rewind();
  }
}

public void GetReplayName(const char[] id, char[] buffer, int length) {
  if (g_ReplaysKv.JumpToKey(id)) {
    g_ReplaysKv.GetString("name", buffer, length);
    g_ReplaysKv.GoBack();
  }
}

public void SetReplayName(const char[] id, const char[] newName) {
  g_UpdatedReplayKv = true;
  if (g_ReplaysKv.JumpToKey(id, true)) {
    g_ReplaysKv.SetString("name", newName);
    g_ReplaysKv.GoBack();
  }
  MaybeWriteNewReplayData();
}

public bool HasRoleRecorded(const char[] id, int index) {
  bool ret = false;
  if (g_ReplaysKv.JumpToKey(id)) {
    char role[DEFAULT_KEY_LENGTH];
    GetRoleString(index, role);
    if (g_ReplaysKv.JumpToKey(role)) {
      ret = true;
      g_ReplaysKv.GoBack();
    }
    g_ReplaysKv.GoBack();
  }
  return ret;
}

public bool GetRoleFile(const char[] id, int index, char[] buffer, int len) {
  bool ret = false;
  if (g_ReplaysKv.JumpToKey(id)) {
    char role[DEFAULT_KEY_LENGTH];
    GetRoleString(index, role);
    if (g_ReplaysKv.JumpToKey(role)) {
      ret = true;
      g_ReplaysKv.GetString("file", buffer, len);
      g_ReplaysKv.GoBack();
    }
    g_ReplaysKv.GoBack();
  }
  return ret;
}

public bool SetRoleFile(const char[] id, int index, const char[] filepath) {
  g_UpdatedReplayKv = true;
  bool ret = false;
  if (g_ReplaysKv.JumpToKey(id, true)) {
    char role[DEFAULT_KEY_LENGTH];
    GetRoleString(index, role);
    if (g_ReplaysKv.JumpToKey(role, true)) {
      ret = true;
      g_ReplaysKv.SetString("file", filepath);
      g_ReplaysKv.GoBack();
    }
    g_ReplaysKv.GoBack();
  }
  return ret;
}

public void SetRoleNades(const char[] id, int index, int client) {
  g_UpdatedReplayKv = true;
  ArrayList list = g_NadeReplayData[client];
  if (g_ReplaysKv.JumpToKey(id, true)) {
    char role[DEFAULT_KEY_LENGTH];
    GetRoleString(index, role);
    if (g_ReplaysKv.JumpToKey(role, true) && g_ReplaysKv.JumpToKey("nades", true)) {
      for (int i = 0; i < list.Length; i++) {
        char key[DEFAULT_KEY_LENGTH];
        IntToString(i, key, sizeof(key));
        g_ReplaysKv.JumpToKey(key, true);

        GrenadeType type;
        float delay;
        float origin[3];
        float velocity[3];
        GetReplayNade(client, i, type, delay, origin, velocity);

        char typeString[DEFAULT_KEY_LENGTH];
        GrenadeTypeString(type, typeString, sizeof(typeString));
        g_ReplaysKv.SetVector("grenadeOrigin", origin);
        g_ReplaysKv.SetVector("grenadeVelocity", velocity);
        g_ReplaysKv.SetString("grenadeType", typeString);
        g_ReplaysKv.SetFloat("delay", delay);
        g_ReplaysKv.GoBack();
      }
    }
  }
  g_ReplaysKv.Rewind();
}

public void GetRoleNades(const char[] id, int index, int client) {
  g_NadeReplayData[client].Clear();
  if (g_ReplaysKv.JumpToKey(id, true)) {
    char role[DEFAULT_KEY_LENGTH];
    GetRoleString(index, role);
    if (g_ReplaysKv.JumpToKey(role, true) && g_ReplaysKv.JumpToKey("nades", true)) {
      if (g_ReplaysKv.GotoFirstSubKey()) {
        do {
          GrenadeType type;
          char typeString[DEFAULT_KEY_LENGTH];
          float delay;
          float origin[3];
          float velocity[3];
          g_ReplaysKv.GetVector("grenadeOrigin", origin);
          g_ReplaysKv.GetVector("grenadeVelocity", velocity);
          g_ReplaysKv.GetString("grenadeType", typeString, sizeof(typeString));
          delay = g_ReplaysKv.GetFloat("delay");
          AddReplayNade(client, type, delay, origin, velocity);
        } while (g_ReplaysKv.GotoNextKey());
      }
    }
  }
  g_ReplaysKv.Rewind();
}

// TODO: make this function more generic - it's currently almost a copy of
// BackupGrenadeData in grenadebackups.sp.
public void BackupReplayData(KeyValues kv) {
  char map[PLATFORM_MAX_PATH + 1];
  GetCleanMapName(map, sizeof(map));

  // Delete backups/de_dust2.30.cfg
  // Backup backups/de_dust.29.cfg -> backups/de_dust.30.cfg
  // Backup backups/de_dust.28.cfg -> backups/de_dust.29.cfg
  // ...
  // Backup backups/de_dust.1.cfg -> backups/de_dust.2.cfg
  // Backup de_dust.cfg -> backups/de_dust.1.cfg
  for (int version = kMaxBackupsPerMap; version >= 1; version--) {
    char olderPath[PLATFORM_MAX_PATH + 1];
    BuildPath(Path_SM, olderPath, sizeof(olderPath), "data/practicemode/replays/backups/%s.%d.cfg",
              map, version);

    char newerPath[PLATFORM_MAX_PATH + 1];
    if (version == 1) {
      BuildPath(Path_SM, newerPath, sizeof(newerPath), "data/practicemode/replays/%s.cfg", map);

    } else {
      BuildPath(Path_SM, newerPath, sizeof(newerPath),
                "data/practicemode/replays/backups/%s.%d.cfg", map, version - 1);
    }

    if (version == kMaxBackupsPerMap && FileExists(olderPath)) {
      if (!DeleteFile(olderPath)) {
        LogError("Failed to delete old grenade file %s", olderPath);
      }
    }

    if (FileExists(newerPath)) {
      if (!RenameFile(olderPath, newerPath)) {
        LogError("Failed to rename %s to %s", newerPath, olderPath);
      }
    }
  }
}
