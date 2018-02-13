stock void GiveNewReplayMenu(int client, int pos = 0) {
  Menu menu = new Menu(ReplayMenuHandler);
  char replayName[REPLAY_NAME_LENGTH];
  GetReplayName(g_ReplayId[client], replayName, REPLAY_NAME_LENGTH);

  if (StrEqual(replayName, DEFAULT_REPLAY_NAME, false)) {
    menu.SetTitle("Replay editor");
  } else {
    menu.SetTitle("Replay editor: %s", replayName);
  }

  /* Page 1 */
  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    bool recordedLastRole = true;
    if (i > 0) {
      recordedLastRole = HasRoleRecorded(g_ReplayId[client], i - 1);
    }
    int style = EnabledIf(recordedLastRole);
    if (HasRoleRecorded(g_ReplayId[client], i)) {
      AddMenuIntStyle(menu, i, style, "Change player %d role", i + 1);
    } else {
      AddMenuIntStyle(menu, i, style, "Add player %d role", i + 1);
    }
  }
  menu.AddItem("replay", "Run replay");

  /* Page 2 */
  menu.AddItem("recordall", "Record all player roles at once");
  menu.AddItem("stop", "Stop current replay");
  menu.AddItem("delete", "Delete this replay entirely");

  for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
    char infoString[DEFAULT_MENU_LENGTH];
    Format(infoString, sizeof(infoString), "play %d", i);
    char displayString[DEFAULT_MENU_LENGTH];
    Format(displayString, sizeof(displayString), "Replay player %d role", i + 1);
    menu.AddItem(infoString, displayString, EnabledIf(HasRoleRecorded(g_ReplayId[client], i)));
  }

  menu.ExitButton = true;
  menu.ExitBackButton = true;

  menu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}

void FinishRecording(int client, bool printOnFail) {
  if (g_RecordingFullReplay) {
    for (int i = 0; i <= MaxClients; i++) {
      if (IsPlayer(i) && BotMimic_IsPlayerRecording(i)) {
        BotMimic_StopRecording(client, true /* save */);
      }
    }

  } else {
    if (BotMimic_IsPlayerRecording(client)) {
      BotMimic_StopRecording(client, true /* save */);
    } else if (printOnFail) {
      PM_Message(client, "You aren't recording a playback right now.");
    }
  }
}

public Action Command_FinishRecording(int client, int args) {
  if (!g_InPracticeMode) {
    return Plugin_Handled;
  }
  FinishRecording(client, true);
  return Plugin_Handled;
}

public Action Command_LookAtWeapon(int client, const char[] command, int argc) {
  // TODO: also hook the noclip command as a way to finish recording.
  FinishRecording(client, false);
  return Plugin_Continue;
}

public Action Command_CancelRecording(int client, int args) {
  if (!g_InPracticeMode) {
    return Plugin_Handled;
  }

  if (BotMimic_IsPlayerRecording(client)) {
    BotMimic_StopRecording(client, false /* save */);
  } else {
    PM_Message(client, "You aren't recording a playback right now.");
  }

  return Plugin_Handled;
}

public int ReplayMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char buffer[OPTION_NAME_LENGTH];
    menu.GetItem(param2, buffer, sizeof(buffer));

    ServerCommand("sm_botmimic_snapshotinterval 64");

    if (StrEqual(buffer, "replay")) {
      bool already_playing = false;
      for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && BotMimic_IsPlayerMimicing(i)) {
          already_playing = true;
          break;
        }
      }
      if (already_playing) {
        PM_Message(client, "Wait for the current replay to finish first.");
      } else {
        char replayName[REPLAY_NAME_LENGTH];
        GetReplayName(g_ReplayId[client], replayName, sizeof(replayName));
        PM_MessageToAll("Starting replay: %s", replayName);
        RunCurrentReplay(client);
      }

      GiveNewReplayMenu(client, GetMenuSelectionPosition());

    } else if (StrEqual(buffer, "stop")) {
      for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
        if (IsValidClient(g_ReplayBotClients[i]) &&
            BotMimic_IsPlayerMimicing(g_ReplayBotClients[i])) {
          BotMimic_StopPlayerMimic(g_ReplayBotClients[i]);
          RequestFrame(Timer_DelayKillBot, GetClientSerial(g_ReplayBotClients[i]));
        }
      }
      if (BotMimic_IsPlayerRecording(client)) {
        BotMimic_StopRecording(client, false /* save */);
        PM_Message(client, "Cancelled recording.");
      }
      GiveNewReplayMenu(client, GetMenuSelectionPosition());

    } else if (StrEqual(buffer, "delete")) {
      char replayName[REPLAY_NAME_LENGTH];
      GetReplayName(g_ReplayId[client], replayName, REPLAY_NAME_LENGTH);
      PM_Message(client, "Deleted replay: %s", replayName);
      GiveDeleteConfirmationMenu(client);

    } else if (StrContains(buffer, "play") == 0) {
      // The string shoudl look like "play 2" here, so we pull out the index here.
      int index = StringToInt(buffer[5]);
      int bot = g_ReplayBotClients[index];
      if (IsValidClient(bot) && HasRoleRecorded(g_ReplayId[client], index)) {
        ReplayRole(bot, index);
      }
      GiveNewReplayMenu(client, GetMenuSelectionPosition());

    } else if (StrEqual(buffer, "recordall")) {
      int count = 0;
      for (int i = 0; i <= MaxClients; i++) {
        if (IsPlayer(i) && !BotMimic_IsPlayerRecording(i) && GetClientTeam(i) == CS_TEAM_T) {
          count++;
        }
      }
      if (count == 0) {
        PM_Message(client, "Cannot record a full replay with no players on the T team.");
        return 0;
      }
      if (count >= MAX_REPLAY_CLIENTS) {
        PM_Message(
            client,
            "Cannot record a full replay with %d players on the T team. Only up to %d is supported.",
            count, MAX_REPLAY_CLIENTS);
        return 0;
      }

      int role = 0;
      for (int i = 0; i <= MaxClients; i++) {
        if (IsPlayer(i) && !BotMimic_IsPlayerRecording(i) && GetClientTeam(i) == CS_TEAM_T) {
          StartRecording(i, role, false);
          role++;
        }
      }
      g_RecordingFullReplay = true;
      g_RecordingFullReplayClient = client;
      PM_MessageToAll("Began recording %d-player replay.", count);
      PM_MessageToAll(
          "When any player presses their inspect button (default:f) the recording will stop.");

    } else {
      // Handling for recording players [0, 4]
      for (int i = 0; i < MAX_REPLAY_CLIENTS; i++) {
        char idxString[16];
        IntToString(i, idxString, sizeof(idxString));
        if (StrEqual(buffer, idxString)) {
          if (BotMimic_IsPlayerRecording(client)) {
            PM_Message(client, "Finish your current recording first!");
            GiveMainReplaysMenu(client);
            break;
          }
          StartRecording(client, i);
          RunCurrentReplay(client, i);
          break;
        }
      }
    }

  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    int client = param1;
    GiveMainReplaysMenu(client);

  } else if (action == MenuAction_End) {
    delete menu;
  }

  return 0;
}

public void GiveDeleteConfirmationMenu(int client) {
  char replayName[REPLAY_NAME_LENGTH];
  GetReplayName(g_ReplayId[client], replayName, sizeof(replayName));

  Menu menu = new Menu(DeletionMenuHandler);
  menu.SetTitle("Confirm deletion of replay: %s", replayName);
  menu.ExitButton = false;
  menu.ExitBackButton = false;
  menu.Pagination = MENU_NO_PAGINATION;

  // Add rows of padding to move selection out of "danger zone"
  for (int i = 0; i < 7; i++) {
    menu.AddItem("", "", ITEMDRAW_NOTEXT);
  }

  // Add actual choices
  menu.AddItem("no", "No, keep it");
  menu.AddItem("yes", "Yes, delete this");
  menu.Display(client, MENU_TIME_FOREVER);
}

public int DeletionMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char buffer[OPTION_NAME_LENGTH];
    menu.GetItem(param2, buffer, sizeof(buffer));

    if (StrEqual(buffer, "yes")) {
      char replayName[REPLAY_NAME_LENGTH];
      GetReplayName(g_ReplayId[client], replayName, sizeof(replayName));
      DeleteReplay(g_ReplayId[client]);
      PM_MessageToAll("Deleted replay: %s", replayName);
      GiveMainReplaysMenu(client);
    } else {
      GiveNewReplayMenu(client);
    }

  } else if (action == MenuAction_End) {
    delete menu;
  }

  return 0;
}

stock void StartRecording(int client, int role, bool printCommands = true) {
  if (role < 0 || role >= MAX_REPLAY_CLIENTS) {
    return;
  }

  g_NadeReplayData[client].Clear();
  g_CurrentRecordingRole[client] = role;
  g_CurrentRecordingStartTime[client] = GetGameTime();

  char recordName[128];
  Format(recordName, sizeof(recordName), "Player %d role", role + 1);
  BotMimic_StartRecording(client, recordName, "practicemode");

  if (printCommands) {
    PM_Message(client, "Started recording player %d role.", role + 1);
    PM_Message(client, "Use .finish OR your inspect (default:f) bind to stop.");
  }
}

public Action BotMimic_OnStopRecording(int client, char[] name, char[] category, char[] subdir,
                                char[] path, bool& save) {
  if (g_CurrentRecordingRole[client] >= 0) {
    if (!save) {
      // We only handle the not-saving case here because BotMimic_OnRecordSaved below
      // is handling the saving case.
      PM_Message(client, "Cancelled recording player role %d", g_CurrentRecordingRole[client] + 1);
      g_CurrentRecordingRole[client] = -1;
      GiveNewReplayMenu(client);
    }
  }

  return Plugin_Continue;
}

public void BotMimic_OnRecordSaved(int client, char[] name, char[] category, char[] subdir, char[] file) {
  if (g_CurrentRecordingRole[client] >= 0) {
    SetRoleFile(g_ReplayId[client], g_CurrentRecordingRole[client], file);
    SetRoleNades(g_ReplayId[client], g_CurrentRecordingRole[client], client);
    PM_Message(client, "Finished recording player role %d", g_CurrentRecordingRole[client] + 1);

    g_CurrentRecordingRole[client] = -1;

    if (!g_RecordingFullReplay || g_RecordingFullReplayClient == client) {
      GiveNewReplayMenu(client);
    }

    MaybeWriteNewReplayData();
  }
}
