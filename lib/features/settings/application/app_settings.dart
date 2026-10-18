/// The user settings model (plan Phase 5): every field of v2
/// `SettingsState`, same JSON keys, same defaults, so a 2.x settings record
/// decodes unchanged. Theme settings live separately in `ThemeSettings`.
library;

import 'package:flutter/foundation.dart' show ValueGetter;
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

/// The v2 display labels of [ModSortOption] (`SortOptionEnum.label`), used
/// to decode 2.x records and accepted next to the enum names.
const Map<ModSortOption, String> modSortOptionLegacyLabels = {
  ModSortOption.nameAsc: 'A-Z',
  ModSortOption.newest: 'Newest',
  ModSortOption.recentlyUpdated: 'Recently updated',
  ModSortOption.missingAssets: 'Missing assets',
};

/// The v2 display labels of [BackupSortOption] (`BackupSortOptionEnum.label`).
const Map<BackupSortOption, String> backupSortOptionLegacyLabels = {
  BackupSortOption.nameAsc: 'A-Z',
  BackupSortOption.nameDesc: 'Z-A',
  BackupSortOption.sizeDesc: 'Largest',
  BackupSortOption.sizeAsc: 'Smallest',
  BackupSortOption.dateDesc: 'Newest',
  BackupSortOption.dateAsc: 'Oldest',
};

/// Decodes a [ModSortOption] from its enum name or its v2 label; anything
/// else yields [fallback] (v2 `SortOptionEnum.fromLabel`).
ModSortOption modSortOptionFromJson(
  Object? value, {
  ModSortOption fallback = ModSortOption.nameAsc,
}) {
  if (value is! String) return fallback;
  for (final option in ModSortOption.values) {
    if (option.name == value || modSortOptionLegacyLabels[option] == value) {
      return option;
    }
  }
  return fallback;
}

/// Decodes a [BackupSortOption] from its enum name or its v2 label;
/// anything else yields [fallback] (v2 `BackupSortOptionEnum.fromLabel`).
BackupSortOption backupSortOptionFromJson(
  Object? value, {
  BackupSortOption fallback = BackupSortOption.nameAsc,
}) {
  if (value is! String) return fallback;
  for (final option in BackupSortOption.values) {
    if (option.name == value || backupSortOptionLegacyLabels[option] == value) {
      return option;
    }
  }
  return fallback;
}

/// Every user setting except the theme.
///
/// Defaults are the 2.x defaults. [fromJson] is lenient the way v2 was:
/// booleans and numbers may arrive as strings, unknown values fall back to
/// the default, lists drop malformed items.
@immutable
final class AppSettings {
  /// Creates settings; every field defaults to its 2.x default.
  const AppSettings({
    this.useModsListView = false,
    this.useBackupsListView = false,
    this.showTitleOnCards = false,
    this.checkForUpdatesOnStart = true,
    this.concurrentDownloads = defaultConcurrentDownloads,
    this.showSavedObjects = false,
    this.showBackupState = true,
    this.defaultSortOption = ModSortOption.nameAsc,
    this.defaultBackupSortOption = BackupSortOption.nameAsc,
    this.forceBackupJsonFilename = false,
    this.ignoreAudioAssets = true,
    this.allowCustomSavesFolder = false,
    this.urlReplacementPresets = const [],
    this.assetUrlFontSize = defaultAssetUrlFontSize,
    this.ignoredSubfolders = const [],
    this.ignoredDomains = const [],
    this.showPdfThumbnails = false,
    this.locale,
  });

  /// Reads settings from their JSON form (v2 keys).
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings.defaults;
    return AppSettings(
      useModsListView: _bool(json['useModsListView'], d.useModsListView),
      useBackupsListView: _bool(
        json['useBackupsListView'],
        d.useBackupsListView,
      ),
      showTitleOnCards: _bool(json['showTitleOnCards'], d.showTitleOnCards),
      checkForUpdatesOnStart: _bool(
        json['checkForUpdatesOnStart'],
        d.checkForUpdatesOnStart,
      ),
      concurrentDownloads: clampConcurrentDownloads(
        _int(json['concurrentDownloads'], d.concurrentDownloads),
      ),
      showSavedObjects: _bool(json['showSavedObjects'], d.showSavedObjects),
      showBackupState: _bool(json['showBackupState'], d.showBackupState),
      defaultSortOption: modSortOptionFromJson(
        json['defaultSortOption'],
        fallback: d.defaultSortOption,
      ),
      defaultBackupSortOption: backupSortOptionFromJson(
        json['defaultBackupSortOption'],
        fallback: d.defaultBackupSortOption,
      ),
      forceBackupJsonFilename: _bool(
        json['forceBackupJsonFilename'],
        d.forceBackupJsonFilename,
      ),
      ignoreAudioAssets: _bool(json['ignoreAudioAssets'], d.ignoreAudioAssets),
      allowCustomSavesFolder: _bool(
        json['allowCustomSavesFolder'],
        d.allowCustomSavesFolder,
      ),
      urlReplacementPresets: _presets(json['urlReplacementPresets']),
      assetUrlFontSize: clampAssetUrlFontSize(
        _double(json['assetUrlFontSize'], d.assetUrlFontSize),
      ),
      ignoredSubfolders: _strings(json['ignoredSubfolders']),
      ignoredDomains: _strings(json['ignoredDomains']),
      showPdfThumbnails: _bool(json['showPdfThumbnails'], d.showPdfThumbnails),
      locale: _locale(json['locale']),
    );
  }

  /// The 2.x defaults.
  static const AppSettings defaults = AppSettings();

  /// The 2.x default download concurrency.
  static const int defaultConcurrentDownloads = 5;

  /// Upper bound accepted for [concurrentDownloads].
  static const int maxConcurrentDownloads = 20;

  /// The 2.x default URL font size.
  static const double defaultAssetUrlFontSize = 12;

  /// Smallest accepted [assetUrlFontSize].
  static const double minAssetUrlFontSize = 8;

  /// Largest accepted [assetUrlFontSize].
  static const double maxAssetUrlFontSize = 24;

  /// Rows instead of cards on the mod tabs.
  final bool useModsListView;

  /// Rows instead of cards on the Backups tab.
  final bool useBackupsListView;

  /// Show the name band at the bottom of grid cards.
  final bool showTitleOnCards;

  /// Query GitHub for a newer release when the shell appears.
  final bool checkForUpdatesOnStart;

  /// Files downloaded (or URLs checked) at the same time.
  final int concurrentDownloads;

  /// Scan and show `Saves/Saved Objects`.
  final bool showSavedObjects;

  /// Show the backup status badge on cards and rows.
  final bool showBackupState;

  /// Sort order of the mod tabs at startup.
  final ModSortOption defaultSortOption;

  /// Sort order of the Backups tab at startup.
  final BackupSortOption defaultBackupSortOption;

  /// Always put the Workshop id into backup file names (`<name> (<id>)`).
  final bool forceBackupJsonFilename;

  /// Hide audio assets unless a mod overrides it.
  final bool ignoreAudioAssets;

  /// Accept any existing folder as the Saves folder.
  final bool allowCustomSavesFolder;

  /// Saved "Update URLs" replacements.
  final List<UrlReplacementPreset> urlReplacementPresets;

  /// Font size of the URLs in the asset list.
  final double assetUrlFontSize;

  /// Folder names skipped when scanning for mods and saves.
  final List<String> ignoredSubfolders;

  /// Host substrings whose URLs are never downloaded.
  final List<String> ignoredDomains;

  /// Render first-page thumbnails for PDF assets.
  final bool showPdfThumbnails;

  /// UI language as a BCP 47 tag (`de`, `pt-BR`); `null` follows the system.
  final String? locale;

  /// Clamps a download concurrency to `1..maxConcurrentDownloads`.
  static int clampConcurrentDownloads(int value) =>
      value.clamp(1, maxConcurrentDownloads);

  /// Clamps a URL font size to `minAssetUrlFontSize..maxAssetUrlFontSize`.
  static double clampAssetUrlFontSize(double value) =>
      value.clamp(minAssetUrlFontSize, maxAssetUrlFontSize).toDouble();

  /// JSON form (v2 keys; sort options as enum names, which [fromJson] and
  /// the 2.x labels both decode).
  Map<String, Object?> toJson() => {
    'useModsListView': useModsListView,
    'useBackupsListView': useBackupsListView,
    'showTitleOnCards': showTitleOnCards,
    'checkForUpdatesOnStart': checkForUpdatesOnStart,
    'concurrentDownloads': concurrentDownloads,
    'showSavedObjects': showSavedObjects,
    'showBackupState': showBackupState,
    'defaultSortOption': defaultSortOption.name,
    'defaultBackupSortOption': defaultBackupSortOption.name,
    'forceBackupJsonFilename': forceBackupJsonFilename,
    'ignoreAudioAssets': ignoreAudioAssets,
    'allowCustomSavesFolder': allowCustomSavesFolder,
    'urlReplacementPresets': [
      for (final preset in urlReplacementPresets) preset.toJson(),
    ],
    'assetUrlFontSize': assetUrlFontSize,
    'ignoredSubfolders': ignoredSubfolders,
    'ignoredDomains': ignoredDomains,
    'showPdfThumbnails': showPdfThumbnails,
    'locale': locale,
  };

  /// Copy with some fields replaced.
  AppSettings copyWith({
    bool? useModsListView,
    bool? useBackupsListView,
    bool? showTitleOnCards,
    bool? checkForUpdatesOnStart,
    int? concurrentDownloads,
    bool? showSavedObjects,
    bool? showBackupState,
    ModSortOption? defaultSortOption,
    BackupSortOption? defaultBackupSortOption,
    bool? forceBackupJsonFilename,
    bool? ignoreAudioAssets,
    bool? allowCustomSavesFolder,
    List<UrlReplacementPreset>? urlReplacementPresets,
    double? assetUrlFontSize,
    List<String>? ignoredSubfolders,
    List<String>? ignoredDomains,
    bool? showPdfThumbnails,
    ValueGetter<String?>? locale,
  }) => AppSettings(
    useModsListView: useModsListView ?? this.useModsListView,
    useBackupsListView: useBackupsListView ?? this.useBackupsListView,
    showTitleOnCards: showTitleOnCards ?? this.showTitleOnCards,
    checkForUpdatesOnStart:
        checkForUpdatesOnStart ?? this.checkForUpdatesOnStart,
    concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
    showSavedObjects: showSavedObjects ?? this.showSavedObjects,
    showBackupState: showBackupState ?? this.showBackupState,
    defaultSortOption: defaultSortOption ?? this.defaultSortOption,
    defaultBackupSortOption:
        defaultBackupSortOption ?? this.defaultBackupSortOption,
    forceBackupJsonFilename:
        forceBackupJsonFilename ?? this.forceBackupJsonFilename,
    ignoreAudioAssets: ignoreAudioAssets ?? this.ignoreAudioAssets,
    allowCustomSavesFolder:
        allowCustomSavesFolder ?? this.allowCustomSavesFolder,
    urlReplacementPresets: urlReplacementPresets ?? this.urlReplacementPresets,
    assetUrlFontSize: assetUrlFontSize ?? this.assetUrlFontSize,
    ignoredSubfolders: ignoredSubfolders ?? this.ignoredSubfolders,
    ignoredDomains: ignoredDomains ?? this.ignoredDomains,
    showPdfThumbnails: showPdfThumbnails ?? this.showPdfThumbnails,
    locale: locale == null ? this.locale : locale(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.useModsListView == useModsListView &&
          other.useBackupsListView == useBackupsListView &&
          other.showTitleOnCards == showTitleOnCards &&
          other.checkForUpdatesOnStart == checkForUpdatesOnStart &&
          other.concurrentDownloads == concurrentDownloads &&
          other.showSavedObjects == showSavedObjects &&
          other.showBackupState == showBackupState &&
          other.defaultSortOption == defaultSortOption &&
          other.defaultBackupSortOption == defaultBackupSortOption &&
          other.forceBackupJsonFilename == forceBackupJsonFilename &&
          other.ignoreAudioAssets == ignoreAudioAssets &&
          other.allowCustomSavesFolder == allowCustomSavesFolder &&
          _sameList(other.urlReplacementPresets, urlReplacementPresets) &&
          other.assetUrlFontSize == assetUrlFontSize &&
          _sameList(other.ignoredSubfolders, ignoredSubfolders) &&
          _sameList(other.ignoredDomains, ignoredDomains) &&
          other.showPdfThumbnails == showPdfThumbnails &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    useModsListView,
    useBackupsListView,
    showTitleOnCards,
    checkForUpdatesOnStart,
    concurrentDownloads,
    showSavedObjects,
    showBackupState,
    defaultSortOption,
    defaultBackupSortOption,
    forceBackupJsonFilename,
    ignoreAudioAssets,
    allowCustomSavesFolder,
    Object.hashAll(urlReplacementPresets),
    assetUrlFontSize,
    Object.hashAll(ignoredSubfolders),
    Object.hashAll(ignoredDomains),
    showPdfThumbnails,
    locale,
  );

  @override
  String toString() => 'AppSettings(${toJson()})';

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _bool(Object? value, bool fallback) => switch (value) {
    final bool v => v,
    final String s when s.toLowerCase() == 'true' => true,
    final String s when s.toLowerCase() == 'false' => false,
    _ => fallback,
  };

  static int _int(Object? value, int fallback) => switch (value) {
    final int v => v,
    final double v => v.round(),
    final String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static double _double(Object? value, double fallback) => switch (value) {
    final num v => v.toDouble(),
    final String s => double.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static String? _locale(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable([
          for (final item in value)
            if (item != null && item.toString().isNotEmpty) item.toString(),
        ])
      : const [];

  static List<UrlReplacementPreset> _presets(Object? value) => value is List
      ? List.unmodifiable([
          for (final item in value)
            if (item is Map)
              UrlReplacementPreset.fromJson(
                item.map((key, v) => MapEntry(key.toString(), v)),
              ),
        ])
      : const [];
}
