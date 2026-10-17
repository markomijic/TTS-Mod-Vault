import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';

import 'startup_test_helpers.dart';

void main() {
  late FakeLibraryController library;

  ProviderContainer createContainer({
    required Set<String> existing,
    InMemoryKeyValueStore? store,
    int libraryFailures = 0,
  }) {
    library = FakeLibraryController(failures: libraryFailures);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: startupOverrides(
        existing: existing,
        store: store,
        library: () => library,
      ),
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'both default folders exist: Loading, then Ready after refresh',
    () async {
      final container = createContainer(
        existing: {testDefaults.modsDir, testDefaults.savesDir},
      );

      final seen = <StartupState>[];
      container.listen<AsyncValue<StartupState>>(startupControllerProvider, (
        previous,
        next,
      ) {
        final value = next.value;
        if (value != null) seen.add(value);
      }, fireImmediately: true);

      await waitForStartupState(container, (state) => state is StartupReady);

      expect(seen.first, const StartupLoading());
      expect(seen.last, const StartupReady());
      expect(library.refreshCalls, 1);
    },
  );

  test('missing Saves folder: NeedsDirectories with the right flags', () async {
    final container = createContainer(existing: {testDefaults.modsDir});

    final state = await container.read(startupControllerProvider.future);

    expect(
      state,
      const StartupNeedsDirectories(modsDirExists: true, savesDirExists: false),
    );
    expect(library.refreshCalls, 0);
  });

  test('missing Mods folder: NeedsDirectories with the right flags', () async {
    final container = createContainer(existing: {testDefaults.savesDir});

    final state = await container.read(startupControllerProvider.future);

    expect(
      state,
      const StartupNeedsDirectories(modsDirExists: false, savesDirExists: true),
    );
  });

  test('stored directories are used instead of the defaults', () async {
    final store = InMemoryKeyValueStore();
    await store.write(
      directoriesStorageKey,
      '{"modsDir":"${_json(pickedMods)}","savesDir":"${_json(pickedSaves)}"}',
    );
    final container = createContainer(
      existing: {pickedMods, pickedSaves},
      store: store,
    );

    final state = await waitForStartupState(
      container,
      (state) => state is StartupReady,
    );

    expect(state, const StartupReady());
  });

  group('continueWithDirectories', () {
    test('a parent folder containing Mods and Saves resolves to the children '
        'and is persisted', () async {
      final store = InMemoryKeyValueStore();
      final container = createContainer(
        existing: {pickedTts, pickedMods, pickedSaves, pickedBackups},
        store: store,
      );
      await container.read(startupControllerProvider.future);

      await container
          .read(startupControllerProvider.notifier)
          .continueWithDirectories(
            Directories(
              modsDir: pickedTts,
              savesDir: pickedTts,
              backupsDir: pickedBackups,
            ),
          );

      expect(
        container.read(startupControllerProvider).value,
        const StartupReady(),
      );
      expect(
        container.read(directoriesProvider).value,
        Directories(
          modsDir: pickedMods,
          savesDir: pickedSaves,
          backupsDir: pickedBackups,
        ),
      );
      expect(await store.read(directoriesStorageKey), isNotNull);
      expect(library.refreshCalls, 1);
    });

    test('the Mods and Saves folders themselves are accepted', () async {
      final container = createContainer(
        existing: {pickedTts, pickedMods, pickedSaves},
      );
      await container.read(startupControllerProvider.future);

      await container
          .read(startupControllerProvider.notifier)
          .continueWithDirectories(
            Directories(modsDir: pickedMods, savesDir: pickedSaves),
          );

      expect(
        container.read(directoriesProvider).value,
        Directories(modsDir: pickedMods, savesDir: pickedSaves),
      );
      expect(
        container.read(startupControllerProvider).value,
        const StartupReady(),
      );
    });

    test(
      'an invalid Mods folder keeps NeedsDirectories with an error',
      () async {
        final container = createContainer(existing: {pickedTts, pickedSaves});
        await container.read(startupControllerProvider.future);
        final before = container.read(directoriesProvider).value;

        await container
            .read(startupControllerProvider.notifier)
            .continueWithDirectories(
              Directories(modsDir: pickedTts, savesDir: pickedTts),
            );

        expect(
          container.read(startupControllerProvider).value,
          const StartupNeedsDirectories(
            modsDirExists: false,
            savesDirExists: true,
            error: StartupDirectoriesError.invalidModsDir,
          ),
        );
        expect(container.read(directoriesProvider).value, before);
        expect(library.refreshCalls, 0);
      },
    );

    test('an invalid Saves folder is reported as such', () async {
      final container = createContainer(existing: {pickedTts, pickedMods});
      await container.read(startupControllerProvider.future);

      await container
          .read(startupControllerProvider.notifier)
          .continueWithDirectories(
            Directories(modsDir: pickedTts, savesDir: pickedTts),
          );

      expect(
        container.read(startupControllerProvider).value,
        const StartupNeedsDirectories(
          modsDirExists: true,
          savesDirExists: false,
          error: StartupDirectoriesError.invalidSavesDir,
        ),
      );
    });

    test('both invalid is reported as such', () async {
      final container = createContainer(existing: {pickedTts});
      await container.read(startupControllerProvider.future);

      await container
          .read(startupControllerProvider.notifier)
          .continueWithDirectories(
            Directories(modsDir: pickedTts, savesDir: pickedTts),
          );

      expect(
        container.read(startupControllerProvider).value,
        const StartupNeedsDirectories(
          modsDirExists: false,
          savesDirExists: false,
          error: StartupDirectoriesError.invalidDirectories,
        ),
      );
    });

    test('any existing Saves folder is accepted when custom saves folders '
        'are allowed', () async {
      final custom = '$pickedTts-custom-saves';
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          ...startupOverrides(existing: {pickedTts, pickedMods, custom}),
          allowCustomSavesFolderProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await container.read(startupControllerProvider.future);

      await container
          .read(startupControllerProvider.notifier)
          .continueWithDirectories(
            Directories(modsDir: pickedTts, savesDir: custom),
          );

      expect(
        container.read(directoriesProvider).value,
        Directories(modsDir: pickedMods, savesDir: custom),
      );
    });
  });

  group('failure and retry', () {
    test('a throwing refresh ends in Failed with the error', () async {
      final container = createContainer(
        existing: {testDefaults.modsDir, testDefaults.savesDir},
        libraryFailures: 1,
      );

      final state = await waitForStartupState(
        container,
        (state) => state is StartupFailed,
      );

      expect(state, isA<StartupFailed>());
      expect((state as StartupFailed).error.toString(), contains('boom'));
      expect(container.read(startupControllerProvider).hasError, isFalse);
    });

    test('retry re-runs the sequence and recovers', () async {
      final container = createContainer(
        existing: {testDefaults.modsDir, testDefaults.savesDir},
        libraryFailures: 1,
      );
      await waitForStartupState(container, (state) => state is StartupFailed);

      container.read(startupControllerProvider.notifier).retry();
      final state = await waitForStartupState(
        container,
        (state) => state is StartupReady,
      );

      expect(state, const StartupReady());
      expect(library.refreshCalls, 2);
    });

    test(
      'a library controller that fails in build also ends in Failed',
      () async {
        final container = ProviderContainer(
          retry: (retryCount, error) => null,
          overrides: [
            ...startupOverrides(
              existing: {testDefaults.modsDir, testDefaults.savesDir},
              library: _BuildFailingLibraryController.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = await waitForStartupState(
          container,
          (state) => state is StartupFailed,
        );

        expect((state as StartupFailed).error.toString(), contains('scan'));
      },
    );
  });
}

/// Escapes a path for embedding in a JSON string literal.
String _json(String path) => path.replaceAll(r'\', r'\\');

class _BuildFailingLibraryController extends LibraryController {
  @override
  Future<LibraryState> build() async => throw StateError('scan failed');

  @override
  Future<void> refresh({bool clearCache = false}) async {}
}
