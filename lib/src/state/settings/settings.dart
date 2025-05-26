import 'dart:convert' show json;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/provider.dart' show storageProvider;
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Ref ref;

  SettingsNotifier(this.ref) : super(const SettingsState());

  Future<void> initializeSettings() async {
    final settingsJson = ref.read(storageProvider).getSettings();

    if (settingsJson != null) {
      try {
        state = SettingsState.fromJson(settingsJson);
        debugPrint('Loaded settings from json');
      } catch (e) {
        debugPrint('Failed to load settings from json: $e');
        state = SettingsState();
      }
    }

    debugPrint('initializeSettings - ${json.encode(state.toJson())}');
    saveSettings(state);
  }

  Future<void> saveSettings(SettingsState newState) async {
    await ref.read(storageProvider).saveSettings(newState);
  }

  Future<void> resetToDefaultSettings() async {
    state = const SettingsState();
    await saveSettings(state);
  }
}
