import 'dart:convert' show json, jsonDecode;

import 'package:flutter/material.dart' show debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box, Hive;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show AudioAssetVisibility;
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
  static const String showAudioAssetsSuffix = '_ShowAudioAssets';
  static const String modsDirKey = 'ModsDir';
  static const String savesDirKey = 'SavesDir';
  static const String backupsDirKey = 'BackupsDir';
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

  Map<String, dynamic>? getSettings() {
    final jsonStr = _appDataBox.get(settingsKey);

    if (jsonStr == null) return null;

    return jsonDecode(jsonStr);
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

  // BACKUPS DIR
  Future<void> saveBackupsDir(String value) async {
    await _appDataBox.put(backupsDirKey, value);
  }

  String? getBackupsDir() {
    return _appDataBox.get(backupsDirKey);
  }

  Future<void> deleteBackupsDir() async {
    await _appDataBox.delete(backupsDirKey);
  }

  // MOD DATA
  String? getModDateTimeStamp(String modName) {
    return _metadataBox.get('$modName$dateTimeStampSuffix');
  }

  Future<void> updateModUrls(
      String jsonFileName, Map<String, String> newUrls) async {
    await _urlsBox.put(jsonFileName, newUrls);
  }

  Map<String, String>? getModUrls(String jsonFileName) {
    final urls = _urlsBox.get(jsonFileName);
    if (urls == null) return null;
    return Map<String, String>.from(urls);
  }

  // Per-mod audio asset preference
  AudioAssetVisibility getModAudioPreference(String modName) {
    final value = _metadataBox.get('$modName$showAudioAssetsSuffix');
    if (value == null) return AudioAssetVisibility.useGlobalSetting;

    return switch (value) {
      'alwaysShow' => AudioAssetVisibility.alwaysShow,
      'alwaysHide' => AudioAssetVisibility.alwaysHide,
      _ => AudioAssetVisibility.useGlobalSetting,
    };
  }

  Future<void> setModAudioPreference(
    String modName,
    AudioAssetVisibility visibility,
  ) async {
    if (visibility == AudioAssetVisibility.useGlobalSetting) {
      // Clear the override - use global setting
      await _metadataBox.delete('$modName$showAudioAssetsSuffix');
    } else {
      // Store the override
      final value = switch (visibility) {
        AudioAssetVisibility.alwaysShow => 'alwaysShow',
        AudioAssetVisibility.alwaysHide => 'alwaysHide',
        AudioAssetVisibility.useGlobalSetting =>
          throw StateError('Should have been deleted'),
      };
      await _metadataBox.put('$modName$showAudioAssetsSuffix', value);
    }
  }

  /* Future<void> deleteMod(String modName) async {
    await Future.wait([
      _metadataBox.delete('$modName$dateTimeStampSuffix'),
      _urlsBox.delete(modName)
    ]);
  } */

  // Bulk operations for better performance with many mods
  Future<void> saveAllModUrlsData(
      Map<String, Map<String, String>> allModData) async {
    await _urlsBox.putAll(allModData);
  }

  Future<void> saveAllModMetadata(Map<String, String> allModMeta) async {
    await _metadataBox.putAll(allModMeta);
  }

  Map<String, Map<String, String>?> getModUrlsBulk(List<String> jsonFileNames) {
    final Map<String, Map<String, String>?> result = {};

    for (final jsonFileName in jsonFileNames) {
      final urls = _urlsBox.get(jsonFileName);
      if (urls == null) {
        result[jsonFileName] = null;
      } else {
        result[jsonFileName] = Map<String, String>.from(urls);
      }
    }

    return result;
  }

  /// Get all mod URLs at once (more efficient than individual getModUrls calls)
  Map<String, Map<String, String>?> getAllModUrls() {
    final allData = _urlsBox.toMap();
    final Map<String, Map<String, String>?> result = {};

    for (final entry in allData.entries) {
      if (entry.value != null) {
        result[entry.key.toString()] = Map<String, String>.from(entry.value);
      } else {
        result[entry.key.toString()] = null;
      }
    }

    return result;
  }

  /// Get all mod date timestamps at once (more efficient than individual getModDateTimeStamp calls)
  Map<String, String?> getAllModDateTimeStamps() {
    final allData = _metadataBox.toMap();
    final Map<String, String?> timestamps = {};

    for (final entry in allData.entries) {
      if (entry.key.endsWith(dateTimeStampSuffix)) {
        // Remove the suffix to get the mod name
        final modName = entry.key.substring(
          0,
          entry.key.length - dateTimeStampSuffix.length,
        );
        timestamps[modName] = entry.value;
      }
    }

    return timestamps;
  }

  /// Get all mod audio preferences at once (more efficient than individual getModAudioPreference calls)
  Map<String, AudioAssetVisibility> getAllModAudioPreferences() {
    final allData = _metadataBox.toMap();
    final Map<String, AudioAssetVisibility> preferences = {};

    for (final entry in allData.entries) {
      if (entry.key.endsWith(showAudioAssetsSuffix)) {
        final modName = entry.key.substring(
          0,
          entry.key.length - showAudioAssetsSuffix.length,
        );

        preferences[modName] = switch (entry.value) {
          'alwaysShow' => AudioAssetVisibility.alwaysShow,
          'alwaysHide' => AudioAssetVisibility.alwaysHide,
          _ => AudioAssetVisibility.useGlobalSetting,
        };
      }
    }

    return preferences;
  }

  Future<void> clearAllModData() async {
    await Hive.box<dynamic>(urlsBox).clear();
    await Hive.box<String>(metadataBox).clear();
  }
}
