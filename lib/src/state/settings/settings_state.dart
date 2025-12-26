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
}
