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
      SetReplayName(g_ReplayId, "unnamed - use .namereplay on me!");
      // ResetData();
    } else {
      strcopy(g_ReplayId, sizeof(g_ReplayId), buffer);
    }

    GiveNewReplayMenu(client);
  } else if (action == MenuAction_End) {
    delete menu;
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

public void DeleteReplay(const char[] id) {
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
  if (g_ReplaysKv.JumpToKey(id, true)) {
    g_ReplaysKv.SetString("name", newName);
    g_ReplaysKv.GoBack();
  }
  SaveReplayKv();
}

public bool HasRoleRecorded(const char[] id, int index) {
  bool ret = false;
  if (g_ReplaysKv.JumpToKey(id)) {
    char role[64];
    Format(role, sizeof(role), "role%d", index + 1);
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
    char role[64];
    Format(role, sizeof(role), "role%d", index + 1);
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
  bool ret = false;
  if (g_ReplaysKv.JumpToKey(id, true)) {
    char role[64];
    Format(role, sizeof(role), "role%d", index + 1);
    if (g_ReplaysKv.JumpToKey(role, true)) {
      ret = true;
      g_ReplaysKv.SetString("file", filepath);
      g_ReplaysKv.GoBack();
    }
    g_ReplaysKv.GoBack();
  }
  SaveReplayKv();
  return ret;
}
