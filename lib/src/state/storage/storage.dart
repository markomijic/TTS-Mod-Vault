import 'dart:convert' show json, jsonDecode;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesWithCache, SharedPreferencesWithCacheOptions;
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;

class Storage {
  late final SharedPreferencesWithCache _prefs;
  late Box<dynamic> _modDataBox;
  late Box<String> _modMetaBox;
  late Box<String> _appDataBox; // For TTS dir and settings backup
  bool _initialized = false;

  // Constants for storage keys
  static const String dateTimeStampSuffix = 'DateTimeStamp';
  static const String ttsDirKey = 'TTSDir';
  static const String settingsKey = 'TTSModVaultSettings';

  // Hive box names
  static const String modDataBox = 'mod_data_maps';
  static const String modMetaBox = 'mod_metadata';
  static const String appDataBox = 'app_data';

  Future<void> initializeStorage() async {
    debugPrint("initializeStorage");

    if (!_initialized) {
      // Initialize SharedPreferences for settings and TTS dir
      final SharedPreferencesWithCache prefsWithCache =
          await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      _prefs = prefsWithCache;

      // Initialize Hive boxes for mod data and app data backup
      _modDataBox = await Hive.openBox<dynamic>(modDataBox);
      _modMetaBox = await Hive.openBox<String>(modMetaBox);
      _appDataBox = await Hive.openBox<String>(appDataBox);

      _initialized = true;
    }
  }

  // SETTINGS (Keep in SharedPreferences)

  Future<void> saveSettings(SettingsState state) async {
    if (!_initialized) await initializeStorage();
    final settingsJson = json.encode(state.toJson());
    await _prefs.setString(settingsKey, settingsJson);
    // Also save to Hive as backup
    await _appDataBox.put(settingsKey, settingsJson);
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
    // Also remove from Hive backup
    await _appDataBox.delete(settingsKey);
  }

  // TTS DIR (Keep in SharedPreferences)

  Future<void> saveTtsDir(String value) async {
    if (!_initialized) await initializeStorage();
    await _prefs.setString(ttsDirKey, value);
    // Also save to Hive as backup
    await _appDataBox.put(ttsDirKey, value);
  }

  String? getTtsDir() {
    if (!_initialized) return null;
    return _prefs.getString(ttsDirKey);
  }

  Future<void> deleteTTSDir() async {
    if (!_initialized) await initializeStorage();
    await _prefs.remove(ttsDirKey);
    // Also remove from Hive backup
    await _appDataBox.delete(ttsDirKey);
  }

  // MOD DATA (Move to Hive)

  Future<void> saveModDateTimeStamp(String modName, String timestamp) async {
    if (!_initialized) await initializeStorage();
    await _modMetaBox.put('$modName$dateTimeStampSuffix', timestamp);
  }

  Future<void> saveModMap(String modName, Map<String, String> data) async {
    if (!_initialized) await initializeStorage();
    await _modDataBox.put(modName, data);
  }

  String? getModDateTimeStamp(String modName) {
    if (!_initialized) return null;
    return _modMetaBox.get('$modName$dateTimeStampSuffix');
  }

  Map<String, String>? getModAssetLists(String jsonFileName) {
    if (!_initialized) return null;
    final data = _modDataBox.get(jsonFileName);
    if (data == null) return null;
    return Map<String, String>.from(data);
  }

  Future<void> saveModData(
    String modName,
    String dateTimeStamp,
    Map<String, String> data,
  ) async {
    if (!_initialized) await initializeStorage();

    await Future.wait([
      saveModDateTimeStamp(modName, dateTimeStamp),
      saveModMap(modName, data)
    ]);
  }

  Future<void> deleteMod(String modName) async {
    if (!_initialized) await initializeStorage();

    await Future.wait([
      _modMetaBox.delete('$modName$dateTimeStampSuffix'),
      _modDataBox.delete(modName)
    ]);
  }

  // Bulk operations for better performance with many mods
  Future<void> saveAllModUrlsData(
      Map<String, Map<String, String>> allModData) async {
    if (!_initialized) await initializeStorage();
    await _modDataBox.putAll(allModData);
  }

  Future<void> saveAllModMetadata(Map<String, String> allModMeta) async {
    if (!_initialized) await initializeStorage();
    await _modMetaBox.putAll(allModMeta);
  }

  // Get all mod names for bulk operations
  List<String> getAllModNames() {
    if (!_initialized) return [];
    return _modDataBox.keys.cast<String>().toList();
  }

  // Clear all mod data (for testing)
  Future<void> clearAllModData() async {
    if (!_initialized) await initializeStorage();

    await Hive.deleteBoxFromDisk(modDataBox);
    await Hive.deleteBoxFromDisk(modMetaBox);

    // Reopen the boxes (they'll be empty)
    _modDataBox = await Hive.openBox<dynamic>(modDataBox);
    _modMetaBox = await Hive.openBox<String>(modMetaBox);
  }
}
