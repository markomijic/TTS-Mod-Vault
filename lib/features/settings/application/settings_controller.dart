/// The settings store (plan Phase 5): one `AppSettings` persisted in the
/// key-value store under [SettingsController.storageKey], plus the bridge
/// that keeps the older per-feature option providers in step.
///
/// Which option providers are derived from Settings now:
///
/// * `libraryOptionsProvider` (`LibraryOptions`: `ignoredSubfolders`,
///   `includeSavedObjects`, `ignoreAudioGlobally`, `forceBackupIdInName`)
///   and `networkOptionsProvider` (`NetworkOptions`: `concurrentDownloads`,
///   `ignoredDomains`) are **fed from Settings**: every [update] pushes the
///   matching fields into them (they still persist their own copy under
///   their own keys so the library refresh can start before Settings has
///   loaded). Edit them through Settings, not through their own setters.
/// * `libraryViewOptionsProvider` and `assetUrlFontSizeProvider`
///   (presentation-owned) are **not bridged yet**: the toolbar toggles write
///   them directly and would be clobbered by a one-way push. Their
///   consumers should switch to the `settingsProvider.select(...)`
///   providers below ([useModsListViewSettingProvider], ...) in the Phase 6
///   polish, after which those two classes can go.
library;

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';
import 'package:tts_mod_vault/l10n/locale_tags.dart';

export 'package:tts_mod_vault/features/settings/application/app_settings.dart';

/// What the UI has to do after a settings change (v2's settings dialog
/// re-ran `loadModsData` after some changes; the controller only reports).
@immutable
final class SettingsChangeEffects {
  /// Creates the effects.
  const SettingsChangeEffects({
    required this.needsLibraryRefresh,
    required this.hidesSavedObjects,
  });

  /// No consequence.
  static const SettingsChangeEffects none = SettingsChangeEffects(
    needsLibraryRefresh: false,
    hidesSavedObjects: false,
  );

  /// Computes the effects of going from [previous] to [next]:
  /// [needsLibraryRefresh] when a field the refresh pipeline bakes into the
  /// index or the state changed (`ignoreAudioAssets`, `showSavedObjects`,
  /// `ignoredSubfolders`, `forceBackupJsonFilename`); [hidesSavedObjects]
  /// when saved objects were just switched off (v2 then reset the shown
  /// type to mods and cleared the multi-selection).
  factory SettingsChangeEffects.between(
    AppSettings previous,
    AppSettings next,
  ) => SettingsChangeEffects(
    needsLibraryRefresh:
        previous.ignoreAudioAssets != next.ignoreAudioAssets ||
        previous.showSavedObjects != next.showSavedObjects ||
        previous.forceBackupJsonFilename != next.forceBackupJsonFilename ||
        !_sameStrings(previous.ignoredSubfolders, next.ignoredSubfolders),
    hidesSavedObjects: previous.showSavedObjects && !next.showSavedObjects,
  );

  /// The library must be re-indexed for the change to show.
  final bool needsLibraryRefresh;

  /// Saved objects were switched off; a Saved Objects tab must be left.
  final bool hidesSavedObjects;

  @override
  bool operator ==(Object other) =>
      other is SettingsChangeEffects &&
      other.needsLibraryRefresh == needsLibraryRefresh &&
      other.hidesSavedObjects == hidesSavedObjects;

  @override
  int get hashCode => Object.hash(needsLibraryRefresh, hidesSavedObjects);

  @override
  String toString() =>
      'SettingsChangeEffects(needsLibraryRefresh: $needsLibraryRefresh, '
      'hidesSavedObjects: $hidesSavedObjects)';

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Holds the current [AppSettings], persists changes and bridges the
/// library and network option providers.
///
/// Starts with [AppSettings.defaults] and swaps in the stored record when
/// the store answers, unless something was changed in the meantime; code
/// that must not run with provisional defaults awaits [ensureLoaded].
final class SettingsController extends Notifier<AppSettings> {
  /// Store key under which the settings JSON lives. Its absence is what
  /// the legacy importer treats as "first run of 3.x".
  static const String storageKey = 'settings';

  bool _touched = false;
  late Future<void> _loaded;

  /// Waits until the stored settings have been read (or found absent) and
  /// returns the current settings.
  Future<AppSettings> ensureLoaded() async {
    await _loaded;
    return state;
  }

  @override
  AppSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _loaded = _restore(store);
    return AppSettings.defaults;
  }

  Future<void> _restore(KeyValueStore store) async {
    final String? raw;
    try {
      raw = await store.read(storageKey);
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        ref
            .read(appLogProvider)
            .error(
              LogSource.settings,
              'Could not read the stored settings; using defaults',
              error: error,
              stackTrace: stackTrace,
            );
      }
      return;
    }
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        state = AppSettings.fromJson(json);
        await _bridge(state);
      } else {
        _warnCorrupt('not a JSON object');
      }
    } on FormatException catch (error) {
      _warnCorrupt(error.message);
    }
  }

  void _warnCorrupt(String detail) {
    if (!ref.mounted) return;
    ref
        .read(appLogProvider)
        .warning(
          LogSource.settings,
          'Stored settings are corrupt; using defaults until the next save',
          details: detail,
        );
  }

  /// Replaces the settings, persists them, pushes the derived fields into
  /// the library and network option providers and returns what the UI must
  /// do about the change. Values outside their range are clamped; blank URL
  /// presets are dropped (as v2's dialog did).
  Future<SettingsChangeEffects> update(AppSettings settings) async {
    final previous = state;
    final next = _normalize(settings);
    _touched = true;
    state = next;
    try {
      await ref
          .read(keyValueStoreProvider)
          .write(storageKey, jsonEncode(next.toJson()));
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        ref
            .read(appLogProvider)
            .error(
              LogSource.settings,
              'Could not save the settings',
              error: error,
              stackTrace: stackTrace,
            );
      }
      rethrow;
    }
    if (!ref.mounted) return SettingsChangeEffects.none;
    await _bridge(next);
    final effects = SettingsChangeEffects.between(previous, next);
    if (ref.mounted && previous != next) {
      ref
          .read(appLogProvider)
          .info(
            LogSource.settings,
            'Settings saved'
            '${effects.needsLibraryRefresh ? ' (library refresh required)' : ''}',
            details: _describeChanges(previous, next),
          );
    }
    return effects;
  }

  /// Restores the 2.x defaults.
  Future<SettingsChangeEffects> reset() => update(AppSettings.defaults);

  /// The effects of changing the current settings to [next] without
  /// applying them (for a dialog that wants to warn first).
  SettingsChangeEffects effectsOf(AppSettings next) =>
      SettingsChangeEffects.between(state, _normalize(next));

  /// Pushes the fields the library refresh and the downloads read from
  /// their own providers. Writes only when something differs so a restore
  /// does not churn the store.
  Future<void> _bridge(AppSettings settings) async {
    final libraryController = ref.read(libraryOptionsProvider.notifier);
    final library = await libraryController.ensureLoaded();
    if (!ref.mounted) return;
    final nextLibrary = library.copyWith(
      ignoredSubfolders: List.unmodifiable(settings.ignoredSubfolders),
      includeSavedObjects: settings.showSavedObjects,
      ignoreAudioGlobally: settings.ignoreAudioAssets,
      forceBackupIdInName: settings.forceBackupJsonFilename,
    );
    if (nextLibrary != library) await libraryController.set(nextLibrary);
    if (!ref.mounted) return;

    final networkController = ref.read(networkOptionsProvider.notifier);
    final network = await networkController.ensureLoaded();
    if (!ref.mounted) return;
    final nextNetwork = network.copyWith(
      concurrentDownloads: settings.concurrentDownloads,
      ignoredDomains: List.unmodifiable(settings.ignoredDomains),
    );
    if (nextNetwork != network) await networkController.set(nextNetwork);
  }

  static AppSettings _normalize(AppSettings settings) => settings.copyWith(
    concurrentDownloads: AppSettings.clampConcurrentDownloads(
      settings.concurrentDownloads,
    ),
    assetUrlFontSize: AppSettings.clampAssetUrlFontSize(
      settings.assetUrlFontSize,
    ),
    urlReplacementPresets: List.unmodifiable([
      for (final preset in settings.urlReplacementPresets)
        if (!preset.isBlank) preset,
    ]),
    ignoredSubfolders: List.unmodifiable([
      for (final folder in settings.ignoredSubfolders)
        if (folder.trim().isNotEmpty) folder.trim(),
    ]),
    ignoredDomains: List.unmodifiable([
      for (final domain in settings.ignoredDomains)
        if (domain.trim().isNotEmpty) domain.trim(),
    ]),
  );

  static String _describeChanges(AppSettings previous, AppSettings next) {
    final before = previous.toJson();
    final after = next.toJson();
    return [
      for (final key in after.keys)
        if (jsonEncode(before[key]) != jsonEncode(after[key]))
          '$key: ${jsonEncode(before[key])} -> ${jsonEncode(after[key])}',
    ].join('\n');
  }
}

/// Provides the current [AppSettings].
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

// --- field selectors ------------------------------------------------------
//
// Cheap per-field providers for widgets and services that only care about
// one setting; they rebuild only when that field changes.

/// `AppSettings.useModsListView`.
final useModsListViewSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.useModsListView)),
);

/// `AppSettings.useBackupsListView`.
final useBackupsListViewSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.useBackupsListView)),
);

/// `AppSettings.showTitleOnCards`.
final showTitleOnCardsSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.showTitleOnCards)),
);

/// `AppSettings.showBackupState`.
final showBackupStateSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.showBackupState)),
);

/// `AppSettings.checkForUpdatesOnStart` (replaces the placeholder
/// `checkForUpdatesOnStartProvider` of the update notice).
final checkForUpdatesOnStartSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.checkForUpdatesOnStart)),
);

/// `AppSettings.allowCustomSavesFolder` (replaces the placeholder
/// `allowCustomSavesFolderProvider` of the startup controller).
final allowCustomSavesFolderSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.allowCustomSavesFolder)),
);

/// `AppSettings.showPdfThumbnails`.
final showPdfThumbnailsSettingProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.showPdfThumbnails)),
);

/// `AppSettings.locale` as a [Locale]; English when none is chosen.
final localeSettingProvider = Provider<Locale>(
  (ref) =>
      localeFromTag(ref.watch(settingsProvider.select((s) => s.locale))) ??
      const Locale('en'),
);

/// `AppSettings.assetUrlFontSize`.
final assetUrlFontSizeSettingProvider = Provider<double>(
  (ref) => ref.watch(settingsProvider.select((s) => s.assetUrlFontSize)),
);

/// `AppSettings.defaultSortOption`.
final defaultModSortSettingProvider = Provider<ModSortOption>(
  (ref) => ref.watch(settingsProvider.select((s) => s.defaultSortOption)),
);

/// `AppSettings.defaultBackupSortOption`.
final defaultBackupSortSettingProvider = Provider<BackupSortOption>(
  (ref) => ref.watch(settingsProvider.select((s) => s.defaultBackupSortOption)),
);

/// `AppSettings.urlReplacementPresets`.
final urlReplacementPresetsProvider = Provider<List<UrlReplacementPreset>>(
  (ref) => ref.watch(settingsProvider.select((s) => s.urlReplacementPresets)),
);
