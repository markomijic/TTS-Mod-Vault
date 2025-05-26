class SettingsState {
  final bool useModsListView;
  final bool showTitleOnCards;
  final bool checkForUpdatesOnStart;
  final int concurrentDownloads;

  const SettingsState({
    this.useModsListView = false,
    this.showTitleOnCards = false,
    this.checkForUpdatesOnStart = true,
    this.concurrentDownloads = 5,
  });

  SettingsState copyWith({
    bool? useModsListView,
    bool? showTitleOnCards,
    bool? checkForUpdatesOnStart,
    int? concurrentDownloads,
  }) {
    return SettingsState(
      useModsListView: useModsListView ?? this.useModsListView,
      showTitleOnCards: showTitleOnCards ?? this.showTitleOnCards,
      checkForUpdatesOnStart:
          checkForUpdatesOnStart ?? this.checkForUpdatesOnStart,
      concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useModsListView': useModsListView,
      'showTitleOnCards': showTitleOnCards,
      'checkForUpdatesOnStart': checkForUpdatesOnStart,
      'concurrentDownloads': concurrentDownloads,
    };
  }

  factory SettingsState.fromJson(Map<String, String> json) {
    return SettingsState(
      useModsListView: json['useModsListView'] == "true",
      showTitleOnCards: json['showTitleOnCards'] == "true",
      checkForUpdatesOnStart: json['checkForUpdatesOnStart'] == "true",
      concurrentDownloads:
          int.tryParse(json['concurrentDownloads'] ?? "5") ?? 5,
    );
  }
}
