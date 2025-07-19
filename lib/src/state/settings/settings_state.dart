class SettingsState {
  final bool useModsListView;
  final bool showTitleOnCards;
  final bool checkForUpdatesOnStart;
  final int concurrentDownloads;
  final bool enableTtsModdersFeatures;
  final bool showSavedObjects;
  final bool showBackupState;

  const SettingsState({
    this.useModsListView = false,
    this.showTitleOnCards = false,
    this.checkForUpdatesOnStart = true,
    this.concurrentDownloads = 5,
    this.enableTtsModdersFeatures = false,
    this.showSavedObjects = false,
    this.showBackupState = true,
  });

  SettingsState copyWith({
    bool? useModsListView,
    bool? showTitleOnCards,
    bool? checkForUpdatesOnStart,
    int? concurrentDownloads,
    bool? enableTtsModdersFeatures,
    bool? showSavedObjects,
    bool? showBackupState,
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
    );
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
