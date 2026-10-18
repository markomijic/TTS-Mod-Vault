import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

void main() {
  late InMemoryKeyValueStore store;
  late AppLog log;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryKeyValueStore();
    log = AppLog(store: LogStore());
    container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appLogProvider.overrideWithValue(log),
      ],
    );
    addTearDown(log.dispose);
  });

  SettingsController controller() => container.read(settingsProvider.notifier);
  Iterable<String> messagesAt(LogLevel level) =>
      log.store.entries.where((e) => e.level == level).map((e) => e.message);

  test('starts with defaults and restores the stored record', () async {
    await store.write(
      SettingsController.storageKey,
      jsonEncode(const AppSettings(showPdfThumbnails: true).toJson()),
    );

    expect(container.read(settingsProvider), AppSettings.defaults);
    final loaded = await controller().ensureLoaded();

    expect(loaded.showPdfThumbnails, isTrue);
    expect(container.read(settingsProvider), loaded);
  });

  test('a corrupt record keeps defaults and logs a warning', () async {
    await store.write(SettingsController.storageKey, '{not json');

    final loaded = await controller().ensureLoaded();

    expect(loaded, AppSettings.defaults);
    expect(
      messagesAt(LogLevel.warning),
      contains(startsWith('Stored settings are corrupt')),
    );
  });

  test(
    'update persists under "settings" and bridges the option providers',
    () async {
      await controller().ensureLoaded();
      const next = AppSettings(
        ignoredSubfolders: ['Old'],
        showSavedObjects: true,
        ignoreAudioAssets: false,
        forceBackupJsonFilename: true,
        concurrentDownloads: 9,
        ignoredDomains: ['pastebin.com'],
        useModsListView: true,
      );

      final effects = await controller().update(next);

      expect(container.read(settingsProvider), next);
      final raw = await store.read(SettingsController.storageKey);
      expect(
        AppSettings.fromJson(jsonDecode(raw!) as Map<String, Object?>),
        next,
      );
      expect(
        container.read(libraryOptionsProvider),
        const LibraryOptions(
          ignoredSubfolders: ['Old'],
          includeSavedObjects: true,
          ignoreAudioGlobally: false,
          forceBackupIdInName: true,
        ),
      );
      expect(
        container.read(networkOptionsProvider),
        const NetworkOptions(
          concurrentDownloads: 9,
          ignoredDomains: ['pastebin.com'],
        ),
      );
      expect(await store.read(LibraryOptionsController.storageKey), isNotNull);
      expect(await store.read(NetworkOptionsController.storageKey), isNotNull);
      expect(effects.needsLibraryRefresh, isTrue);
      expect(effects.hidesSavedObjects, isFalse);
      expect(
        messagesAt(LogLevel.info),
        contains('Settings saved (library refresh required)'),
      );
      expect(container.read(useModsListViewSettingProvider), isTrue);
    },
  );

  test('restoring a stored record bridges too', () async {
    await store.write(
      SettingsController.storageKey,
      jsonEncode(
        const AppSettings(
          ignoreAudioAssets: false,
          concurrentDownloads: 2,
        ).toJson(),
      ),
    );

    await controller().ensureLoaded();
    // The bridge awaits the option controllers' own restores.
    await container.read(libraryOptionsProvider.notifier).ensureLoaded();
    await container.read(networkOptionsProvider.notifier).ensureLoaded();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(libraryOptionsProvider).ignoreAudioGlobally, isFalse);
    expect(container.read(networkOptionsProvider).concurrentDownloads, 2);
  });

  test('a late restore does not clobber an update', () async {
    await store.write(
      SettingsController.storageKey,
      jsonEncode(const AppSettings(showTitleOnCards: true).toJson()),
    );

    await controller().update(const AppSettings(useBackupsListView: true));
    await controller().ensureLoaded();

    final state = container.read(settingsProvider);
    expect(state.useBackupsListView, isTrue);
    expect(state.showTitleOnCards, isFalse, reason: 'user change wins');
  });

  test('update normalises: clamps, trims and drops blank presets', () async {
    await controller().update(
      const AppSettings(
        concurrentDownloads: 50,
        assetUrlFontSize: 1,
        urlReplacementPresets: [
          UrlReplacementPreset(label: ' ', oldUrl: '', newUrl: ''),
          UrlReplacementPreset(label: 'Keep', oldUrl: 'a', newUrl: 'b'),
        ],
        ignoredSubfolders: [' Old ', ''],
        ignoredDomains: ['', ' x.com'],
      ),
    );

    final state = container.read(settingsProvider);
    expect(state.concurrentDownloads, AppSettings.maxConcurrentDownloads);
    expect(state.assetUrlFontSize, AppSettings.minAssetUrlFontSize);
    expect(state.urlReplacementPresets.map((p) => p.label), ['Keep']);
    expect(state.ignoredSubfolders, ['Old']);
    expect(state.ignoredDomains, ['x.com']);
    expect(container.read(urlReplacementPresetsProvider).length, 1);
  });

  test('reset restores the defaults and reports the effects', () async {
    await controller().update(const AppSettings(showSavedObjects: true));

    final effects = await controller().reset();

    expect(container.read(settingsProvider), AppSettings.defaults);
    expect(effects.needsLibraryRefresh, isTrue);
    expect(effects.hidesSavedObjects, isTrue);
    expect(container.read(libraryOptionsProvider), LibraryOptions.defaults);
  });

  group('SettingsChangeEffects', () {
    const base = AppSettings.defaults;

    test('view-only changes need nothing', () {
      final effects = SettingsChangeEffects.between(
        base,
        base.copyWith(
          useModsListView: true,
          showTitleOnCards: true,
          concurrentDownloads: 3,
          defaultSortOption: ModSortOption.newest,
          assetUrlFontSize: 20,
          checkForUpdatesOnStart: false,
        ),
      );
      expect(effects, SettingsChangeEffects.none);
    });

    test('audio, saved objects, ignored subfolders and forced id need a '
        'refresh', () {
      expect(
        SettingsChangeEffects.between(
          base,
          base.copyWith(ignoreAudioAssets: false),
        ).needsLibraryRefresh,
        isTrue,
      );
      expect(
        SettingsChangeEffects.between(
          base,
          base.copyWith(showSavedObjects: true),
        ).needsLibraryRefresh,
        isTrue,
      );
      expect(
        SettingsChangeEffects.between(
          base,
          base.copyWith(ignoredSubfolders: ['Old']),
        ).needsLibraryRefresh,
        isTrue,
      );
      expect(
        SettingsChangeEffects.between(
          base,
          base.copyWith(forceBackupJsonFilename: true),
        ).needsLibraryRefresh,
        isTrue,
      );
    });

    test('hidesSavedObjects only when switching them off', () {
      final on = base.copyWith(showSavedObjects: true);
      expect(SettingsChangeEffects.between(on, base).hidesSavedObjects, isTrue);
      expect(
        SettingsChangeEffects.between(base, on).hidesSavedObjects,
        isFalse,
      );
    });

    test('effectsOf previews without applying', () async {
      await controller().ensureLoaded();
      final effects = controller().effectsOf(
        base.copyWith(ignoreAudioAssets: false),
      );
      expect(effects.needsLibraryRefresh, isTrue);
      expect(container.read(settingsProvider), base);
    });
  });
}
