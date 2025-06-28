import 'dart:convert' show json, jsonDecode;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;
import 'package:tts_mod_vault/src/state/settings/settings_state.dart'
    show SettingsState;

class Storage {
  bool _initialized = false;
  late Box<dynamic> _urlsBox;
  late Box<String> _metadataBox;
  late Box<String> _appDataBox;

  // Boxes
  static const String urlsBox = 'ModUrls';
  static const String metadataBox = 'ModMetadata';
  static const String appDataBox = 'AppData';

  // Keys
  static const String dateTimeStampSuffix = 'DateTimeStamp';
  static const String modsDirKey = 'ModsDir';
  static const String savesDirKey = 'SavesDir';
  static const String settingsKey = 'TTSModVaultSettings';

  Future<void> initializeStorage() async {
    debugPrint("initializeStorage");

    if (!_initialized) {
      _urlsBox = await Hive.openBox<dynamic>(urlsBox);
      _metadataBox = await Hive.openBox<String>(metadataBox);
      _appDataBox = await Hive.openBox<String>(appDataBox);

      _initialized = true;
    }
  }

  // SETTINGS
  Future<void> saveSettings(SettingsState state) async {
    final settingsJson = json.encode(state.toJson());

    await _appDataBox.put(settingsKey, settingsJson);
  }

  Map<String, String>? getSettings() {
    final jsonStr = _appDataBox.get(settingsKey);

    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> deleteSettings() async {
    await _appDataBox.delete(settingsKey);
  }

  // MODS DIR
  Future<void> saveModsDir(String value) async {
    await _appDataBox.put(modsDirKey, value);
  }

  String? getModsDir() {
    return _appDataBox.get(modsDirKey);
  }

  Future<void> deleteModsDir() async {
    await _appDataBox.delete(modsDirKey);
  }

  // SAVES DIR
  Future<void> saveSavesDir(String value) async {
    await _appDataBox.put(savesDirKey, value);
  }

  String? getSavesDir() {
    return _appDataBox.get(savesDirKey);
  }

  Future<void> deleteSavesDir() async {
    await _appDataBox.delete(savesDirKey);
  }

  // MOD DATA (Move to Hive)

  Future<void> saveModDateTimeStamp(String modName, String timestamp) async {
    await _metadataBox.put('$modName$dateTimeStampSuffix', timestamp);
  }

  Future<void> saveModMap(String modName, Map<String, String> data) async {
    await _urlsBox.put(modName, data);
  }

  String? getModDateTimeStamp(String modName) {
    return _metadataBox.get('$modName$dateTimeStampSuffix');
  }

  Map<String, String>? getModUrls(String jsonFileName) {
    final urls = _urlsBox.get(jsonFileName);
    if (urls == null) return null;
    return Map<String, String>.from(urls);
  }

  Future<void> saveModData(
    String modName,
    String dateTimeStamp,
    Map<String, String> data,
  ) async {
    await Future.wait([
      saveModDateTimeStamp(modName, dateTimeStamp),
      saveModMap(modName, data)
    ]);
  }

  Future<void> deleteMod(String modName) async {
    await Future.wait([
      _metadataBox.delete('$modName$dateTimeStampSuffix'),
      _urlsBox.delete(modName)
    ]);
  }

  // Bulk operations for better performance with many mods
  Future<void> saveAllModUrlsData(
      Map<String, Map<String, String>> allModData) async {
    await _urlsBox.putAll(allModData);
  }

  Future<void> saveAllModMetadata(Map<String, String> allModMeta) async {
    await _metadataBox.putAll(allModMeta);
  }

  // Get all mod names for bulk operations
  List<String> getAllModNames() {
    return _urlsBox.keys.cast<String>().toList();
  }

  // Clear all mod data (for testing)
  Future<void> clearAllModData() async {
    await Hive.deleteBoxFromDisk(urlsBox);
    await Hive.deleteBoxFromDisk(metadataBox);

    // Reopen the boxes (they'll be empty)
    _urlsBox = await Hive.openBox<dynamic>(urlsBox);
    _metadataBox = await Hive.openBox<String>(metadataBox);
  }
}
