import 'package:flutter/material.dart' show debugPrint;
import 'package:tts_mod_vault/src/models/url_replacement_preset.dart'
    show UrlReplacementPreset;
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart'
    show SortOptionEnum;

class SettingsState {
  final bool useModsListView;
  final bool showTitleOnCards;
  final bool checkForUpdatesOnStart;
  final int concurrentDownloads;
  final bool showSavedObjects;
  final bool showBackupState;
  final SortOptionEnum defaultSortOption;
  final bool forceBackupJsonFilename;
  final bool ignoreAudioAssets;
  final List<UrlReplacementPreset> urlReplacementPresets;
  final double assetUrlFontSize;
  final List<String> ignoredSubfolders;

  const SettingsState({
    required this.useModsListView,
    required this.showTitleOnCards,
    required this.checkForUpdatesOnStart,
    required this.concurrentDownloads,
    required this.showSavedObjects,
    required this.showBackupState,
    required this.defaultSortOption,
    required this.forceBackupJsonFilename,
    required this.ignoreAudioAssets,
    required this.urlReplacementPresets,
    required this.assetUrlFontSize,
    required this.ignoredSubfolders,
  });

  factory SettingsState.defaultState() {
    return SettingsState(
      useModsListView: false,
      showTitleOnCards: false,
      checkForUpdatesOnStart: true,
      concurrentDownloads: 5,
      showSavedObjects: false,
      showBackupState: true,
      defaultSortOption: SortOptionEnum.alphabeticalAsc,
      forceBackupJsonFilename: false,
      ignoreAudioAssets: true,
      urlReplacementPresets: const [],
      assetUrlFontSize: 12,
      ignoredSubfolders: const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useModsListView': useModsListView,
      'showTitleOnCards': showTitleOnCards,
      'checkForUpdatesOnStart': checkForUpdatesOnStart,
      'concurrentDownloads': concurrentDownloads,
      'showSavedObjects': showSavedObjects,
      'showBackupState': showBackupState,
      'defaultSortOption': defaultSortOption.label,
      'forceBackupJsonFilename': forceBackupJsonFilename,
      'ignoreAudioAssets': ignoreAudioAssets,
      'urlReplacementPresets':
          urlReplacementPresets.map((p) => p.toJson()).toList(),
      'assetUrlFontSize': assetUrlFontSize,
      'ignoredSubfolders': ignoredSubfolders,
    };
  }

  factory SettingsState.fromJson(Map<String, dynamic> json) {
    return SettingsState(
      useModsListView: _parseBool(json['useModsListView'], false),
      showTitleOnCards: _parseBool(json['showTitleOnCards'], false),
      checkForUpdatesOnStart: _parseBool(json['checkForUpdatesOnStart'], true),
      concurrentDownloads: _parseInt(json['concurrentDownloads'], 5),
      showSavedObjects: _parseBool(json['showSavedObjects'], false),
      showBackupState: _parseBool(json['showBackupState'], true),
      defaultSortOption: _parseSortOptionEnum(
          json['defaultSortOption'], SortOptionEnum.alphabeticalAsc),
      forceBackupJsonFilename:
          _parseBool(json['forceBackupJsonFilename'], false),
      ignoreAudioAssets: _parseBool(json['ignoreAudioAssets'], true),
      urlReplacementPresets: _parsePresetList(json['urlReplacementPresets']),
      assetUrlFontSize: _parseDouble(json['assetUrlFontSize'], 12.0),
      ignoredSubfolders: _parseStringList(json['ignoredSubfolders']),
    );
  }

  static SortOptionEnum _parseSortOptionEnum(
      dynamic value, SortOptionEnum defaultValue) {
    if (value == null) return defaultValue;
    if (value is String) {
      return SortOptionEnum.fromLabel(value);
    }
    return defaultValue;
  }

  static bool _parseBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return defaultValue;
  }

  static int _parseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  static double _parseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  static List<UrlReplacementPreset> _parsePresetList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];

    return value
        .map((item) {
          try {
            if (item is Map<String, dynamic>) {
              return UrlReplacementPreset.fromJson(item);
            }
          } catch (e) {
            debugPrint('Failed to parse preset: $e');
          }
          return null;
        })
        .whereType<UrlReplacementPreset>()
        .toList();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];

    return value.map((item) => item?.toString()).whereType<String>().toList();
  }
}
