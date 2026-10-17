// The one-shot 2.x import at startup: runs only when the store has no
// settings yet, writes settings and folders, logs one line, deletes the
// legacy data, and never fails startup.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/legacy/hive_settings_importer.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';

import 'startup_test_helpers.dart';

final class _FakeImporter implements LegacySettingsImporter {
  _FakeImporter(this.data, {this.throwOnRead = false});

  final LegacySettings? data;
  final bool throwOnRead;
  int reads = 0;
  int deletes = 0;

  @override
  bool get exists => data != null;

  @override
  Future<LegacySettings?> read() async {
    reads++;
    if (throwOnRead) throw StateError('box is locked');
    return data;
  }

  @override
  Future<void> deleteLegacyData() async => deletes++;
}

void main() {
  late InMemoryKeyValueStore store;

  ProviderContainer createContainer(
    _FakeImporter importer, {
    required Set<String> existing,
  }) {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        ...startupOverrides(existing: existing, store: store),
        legacyImporterProvider.overrideWithValue(importer),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Iterable<String> messages(ProviderContainer container, LogLevel level) =>
      container
          .read(appLogProvider)
          .store
          .entries
          .where((e) => e.level == level)
          .map((e) => e.message);

  setUp(() => store = InMemoryKeyValueStore());

  test('imports settings and folders on the first start, then deletes the '
      '2.x data', () async {
    final importer = _FakeImporter(
      LegacySettings(
        settings: const AppSettings(
          ignoreAudioAssets: false,
          showSavedObjects: true,
          concurrentDownloads: 3,
        ),
        directories: Directories(
          modsDir: pickedMods,
          savesDir: pickedSaves,
          backupsDir: pickedBackups,
        ),
      ),
    );
    final container = createContainer(
      importer,
      existing: {pickedMods, pickedSaves},
    );

    final state = await container.read(startupControllerProvider.future);

    expect(state, const StartupReady(), reason: 'the imported folders exist');
    expect(importer.reads, 1);
    expect(importer.deletes, 1);
    expect(await store.read(SettingsController.storageKey), isNotNull);
    final settings = container.read(settingsProvider);
    expect(settings.ignoreAudioAssets, isFalse);
    expect(settings.showSavedObjects, isTrue);
    expect(settings.concurrentDownloads, 3);
    expect(
      container.read(directoriesProvider).value,
      Directories(
        modsDir: pickedMods,
        savesDir: pickedSaves,
        backupsDir: pickedBackups,
      ),
    );
    expect(await store.read(directoriesStorageKey), isNotNull);
    expect(container.read(libraryOptionsProvider).ignoreAudioGlobally, isFalse);
    expect(
      messages(container, LogLevel.info),
      contains('Imported settings from TTS Mod Vault 2.x'),
    );
  });

  test('does nothing when settings are already stored', () async {
    await store.write(
      SettingsController.storageKey,
      '{"showPdfThumbnails":true}',
    );
    final importer = _FakeImporter(
      LegacySettings(
        settings: const AppSettings(useModsListView: true),
        directories: Directories(modsDir: pickedMods, savesDir: pickedSaves),
      ),
    );
    final container = createContainer(
      importer,
      existing: {testDefaults.modsDir, testDefaults.savesDir},
    );

    await container.read(startupControllerProvider.future);

    expect(importer.reads, 0);
    expect(importer.deletes, 0);
    expect(container.read(directoriesProvider).value, testDefaults);
    expect(
      (await container.read(settingsProvider.notifier).ensureLoaded())
          .showPdfThumbnails,
      isTrue,
    );
  });

  test('no legacy data: nothing written, nothing deleted', () async {
    final importer = _FakeImporter(null);
    final container = createContainer(
      importer,
      existing: {testDefaults.modsDir, testDefaults.savesDir},
    );

    await container.read(startupControllerProvider.future);

    expect(importer.reads, 1);
    expect(importer.deletes, 0);
    expect(await store.read(SettingsController.storageKey), isNull);
  });

  test('settings without folders: folders stay at the defaults', () async {
    final importer = _FakeImporter(
      const LegacySettings(
        settings: AppSettings(useModsListView: true),
        directories: null,
      ),
    );
    final container = createContainer(
      importer,
      existing: {testDefaults.modsDir, testDefaults.savesDir},
    );

    await container.read(startupControllerProvider.future);

    expect(container.read(settingsProvider).useModsListView, isTrue);
    expect(container.read(directoriesProvider).value, testDefaults);
    expect(importer.deletes, 1);
  });

  test('an importer failure is logged and startup goes on', () async {
    final importer = _FakeImporter(
      const LegacySettings(settings: AppSettings.defaults, directories: null),
      throwOnRead: true,
    );
    final container = createContainer(
      importer,
      existing: {testDefaults.modsDir, testDefaults.savesDir},
    );

    final state = await container.read(startupControllerProvider.future);

    expect(state, const StartupReady());
    expect(importer.deletes, 0);
    expect(
      messages(container, LogLevel.error),
      contains(startsWith('Could not import the TTS Mod Vault 2.x settings')),
    );
  });

  test('the default importer provider is null (no disk access in tests)', () {
    final container = ProviderContainer.test();
    expect(container.read(legacyImporterProvider), isNull);
  });
}
