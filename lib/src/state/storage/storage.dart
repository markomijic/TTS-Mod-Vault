import 'package:flutter/material.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesWithCache, SharedPreferencesWithCacheOptions;
import 'dart:convert' show json, jsonDecode, jsonEncode;

import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;

class Storage {
  late final SharedPreferencesWithCache _prefs;
  bool _initialized = false;

  // Constants for storage keys
  static const String updatedTimeSuffix = 'UpdatedTime';
  static const String listsSuffix = 'Lists';
  static const String ttsDirKey = 'TTSDir';
  static const String settingsKey = 'TTSModVaultSettings';

  Future<void> initializeStorage() async {
    debugPrint("initializeStorage");

    if (!_initialized) {
      final SharedPreferencesWithCache prefsWithCache =
          await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

      _prefs = prefsWithCache;
      _initialized = true;
    }
  }

  // SETTINGS

  Future<void> saveSettings(SettingsState state) async {
    if (!_initialized) await initializeStorage();
    final settingsJson = json.encode(state.toJson());
    await _prefs.setString(settingsKey, settingsJson);
  }

  Map<String, String>? getSettings() {
    if (!_initialized) return null;
    final jsonStr = _prefs.getString(settingsKey);
    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> deleteSettings() async {
    if (!_initialized) await initializeStorage();
    await _prefs.remove(settingsKey);
  }

  // TTS DIR

  Future<void> saveTtsDir(String value) async {
    if (!_initialized) await initializeStorage();
    await _prefs.setString(ttsDirKey, value);
  }

  String? getTtsDir() {
    if (!_initialized) return null;
    return _prefs.getString(ttsDirKey);
  }

  Future<void> deleteTTSDir() async {
    if (!_initialized) await initializeStorage();
    await _prefs.remove(ttsDirKey);
  }

  // MOD DATA

  Future<void> saveMod(String modName, String value) async {
    if (!_initialized) await initializeStorage();
    return await _prefs.setString(modName, value);
  }

  Future<void> saveModUpdateTime(String modName, int timestamp) async {
    if (!_initialized) await initializeStorage();
    return await _prefs.setInt('$modName$updatedTimeSuffix', timestamp);
  }

  Future<void> saveModMap(String modName, Map<String, String> data) async {
    if (!_initialized) await initializeStorage();
    return await _prefs.setString('$modName$listsSuffix', jsonEncode(data));
  }

  String? getModName(String modName) {
    if (!_initialized) return null;
    return _prefs.getString(modName);
  }

  int? getModUpdateTime(String modName) {
    if (!_initialized) return null;
    return _prefs.getInt('$modName$updatedTimeSuffix');
  }

  Map<String, String>? getModAssetLists(String jsonFileName) {
    if (!_initialized) return null;
    final jsonStr = _prefs.getString('$jsonFileName$listsSuffix');
    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> saveModData(
    String modName,
    int updateTime,
    Map<String, String> data,
  ) async {
    if (!_initialized) await initializeStorage();

    await Future.wait([
      saveMod(modName, modName),
      saveModUpdateTime(modName, updateTime),
      saveModMap(modName, data)
    ]);
  }

  Future<void> deleteMod(String modName) async {
    if (!_initialized) await initializeStorage();

    await Future.wait([
      _prefs.remove(modName),
      _prefs.remove('$modName$updatedTimeSuffix'),
      _prefs.remove('$modName$listsSuffix')
    ]);
  }
}
