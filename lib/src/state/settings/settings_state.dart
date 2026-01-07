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
  final bool enableTtsModdersFeatures;
  final bool showSavedObjects;
  final bool showBackupState;
  final SortOptionEnum defaultSortOption;
  final bool forceBackupJsonFilename;
  final bool ignoreAudioAssets;
  final List<UrlReplacementPreset> urlReplacementPresets;

  const SettingsState({
    this.useModsListView = false,
    this.showTitleOnCards = false,
    this.checkForUpdatesOnStart = true,
    this.concurrentDownloads = 5,
    this.enableTtsModdersFeatures = false,
    this.showSavedObjects = false,
    this.showBackupState = true,
    this.defaultSortOption = SortOptionEnum.alphabeticalAsc,
    this.forceBackupJsonFilename = false,
    this.ignoreAudioAssets = true,
    this.urlReplacementPresets = const [],
  });

  SettingsState copyWith({
    bool? useModsListView,
    bool? showTitleOnCards,
    bool? checkForUpdatesOnStart,
    int? concurrentDownloads,
    bool? enableTtsModdersFeatures,
    bool? showSavedObjects,
    bool? showBackupState,
    SortOptionEnum? defaultSortOption,
    bool? forceBackupJsonFilename,
    bool? ignoreAudioAssets,
    List<UrlReplacementPreset>? urlReplacementPresets,
  }) {
    return SettingsState(
      useModsListView: useModsListView ?? this.useModsListView,
      showTitleOnCards: showTitleOnCards ?? this.showTitleOnCards,
      checkForUpdatesOnStart:
          checkForUpdatesOnStart ?? this.checkForUpdatesOnStart,
      concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
      enableTtsModdersFeatures:
          enableTtsModdersFeatures ?? this.enableTtsModdersFeatures,
      showSavedObjects: showSavedObjects ?? this.showSavedObjects,
      showBackupState: showBackupState ?? this.showBackupState,
      defaultSortOption: defaultSortOption ?? this.defaultSortOption,
      forceBackupJsonFilename:
          forceBackupJsonFilename ?? this.forceBackupJsonFilename,
      ignoreAudioAssets: ignoreAudioAssets ?? this.ignoreAudioAssets,
      urlReplacementPresets:
          urlReplacementPresets ?? this.urlReplacementPresets,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useModsListView': useModsListView,
      'showTitleOnCards': showTitleOnCards,
      'checkForUpdatesOnStart': checkForUpdatesOnStart,
      'concurrentDownloads': concurrentDownloads,
      'enableTtsModdersFeatures': enableTtsModdersFeatures,
      'showSavedObjects': showSavedObjects,
      'showBackupState': showBackupState,
      'defaultSortOption': defaultSortOption.label,
      'forceBackupJsonFilename': forceBackupJsonFilename,
      'ignoreAudioAssets': ignoreAudioAssets,
      'urlReplacementPresets':
          urlReplacementPresets.map((p) => p.toJson()).toList(),
    };
  }

  factory SettingsState.fromJson(Map<String, dynamic> json) {
    return SettingsState(
      useModsListView: _parseBool(json['useModsListView'], false),
      showTitleOnCards: _parseBool(json['showTitleOnCards'], false),
      checkForUpdatesOnStart: _parseBool(json['checkForUpdatesOnStart'], true),
      concurrentDownloads: _parseInt(json['concurrentDownloads'], 5),
      enableTtsModdersFeatures:
          _parseBool(json['enableTtsModdersFeatures'], false),
      showSavedObjects: _parseBool(json['showSavedObjects'], false),
      showBackupState: _parseBool(json['showBackupState'], true),
      defaultSortOption: _parseSortOptionEnum(
          json['defaultSortOption'], SortOptionEnum.alphabeticalAsc),
      forceBackupJsonFilename:
          _parseBool(json['forceBackupJsonFilename'], false),
      ignoreAudioAssets: _parseBool(json['ignoreAudioAssets'], true),
      urlReplacementPresets: _parsePresetList(json['urlReplacementPresets']),
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
}
