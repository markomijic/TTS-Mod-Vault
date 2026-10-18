import 'dart:async';
import 'dart:io' show Directory;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/startup_timeline_provider.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/bootstrap/startup_timeline.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/legacy/hive_settings_importer.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/startup_state.dart';

export 'package:tts_mod_vault/features/startup/application/startup_state.dart';

/// "Does this directory exist" check used by startup; tests override it so
/// no disk is touched. Defaults to `Directory(path).existsSync()`.
final directoryExistsProvider = Provider<DirectoryExists>(
  (ref) =>
      (path) => Directory(path).existsSync(),
);

/// Drives the start-up sequence; see [StartupState] for the state machine.
final startupControllerProvider =
    AsyncNotifierProvider<StartupController, StartupState>(
      StartupController.new,
    );

/// Checks the stored Mods and Saves folders, lets the user pick them when
/// missing, then hands over to the shell and starts the first library
/// refresh behind it (plan section 9, "No splash in the common case").
///
/// The provider's `AsyncLoading` phase is the [StartupChecking] state; every
/// later state is an `AsyncData`. Errors never surface as `AsyncError`: a
/// failed folder lookup becomes [StartupFailed] so the page can offer a
/// Retry button. A failed library refresh is not a startup failure: the
/// library provider ends as `AsyncError` and the library page shows it.
class StartupController extends AsyncNotifier<StartupState> {
  @override
  Future<StartupState> build() async {
    // Phase 5: a 2.x install's settings and folders are taken over before
    // the folders are checked, so the first start of 3.x lands in the
    // user's library instead of on the folder picker.
    await _importLegacySettings();
    if (!ref.mounted) return const StartupChecking();

    final Directories directories;
    try {
      directories = await ref.read(directoriesProvider.future);
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return const StartupChecking();
      _log.error(
        LogSource.app,
        'Could not read the stored TTS folders',
        error: error,
        stackTrace: stackTrace,
      );
      return StartupFailed(error, stackTrace);
    }
    if (!ref.mounted) return const StartupChecking();
    final exists = ref.read(directoryExistsProvider);
    final modsDirExists = exists(directories.modsDir);
    final savesDirExists = exists(directories.savesDir);

    if (!modsDirExists || !savesDirExists) {
      _log.warning(
        LogSource.app,
        'TTS folders not found, asking the user to locate them',
        details:
            'mods: ${directories.modsDir} (exists: $modsDirExists), '
            'saves: ${directories.savesDir} (exists: $savesDirExists)',
      );
      return StartupNeedsDirectories(
        modsDirExists: modsDirExists,
        savesDirExists: savesDirExists,
      );
    }

    _log.info(
      LogSource.app,
      'Using TTS folders',
      details: 'mods: ${directories.modsDir}, saves: ${directories.savesDir}',
    );
    _startRefresh();
    return const StartupReady();
  }

  /// Validates [picked], persists the resolved folders, shows the shell and
  /// starts the library refresh.
  ///
  /// The Mods and Saves paths may be the folders themselves or a parent that
  /// contains them (the TTS data folder); see `resolveModsDir` and
  /// `resolveSavesDir`. On failure the state stays [StartupNeedsDirectories]
  /// with [StartupNeedsDirectories.error] set.
  Future<void> continueWithDirectories(Directories picked) async {
    final exists = ref.read(directoryExistsProvider);
    final modsDir = resolveModsDir(picked.modsDir, directoryExists: exists);
    final savesDir = resolveSavesDir(
      picked.savesDir,
      allowCustomPath: ref.read(allowCustomSavesFolderSettingProvider),
      directoryExists: exists,
    );

    if (modsDir == null || savesDir == null) {
      final error = switch ((modsDir, savesDir)) {
        (null, null) => StartupDirectoriesError.invalidDirectories,
        (null, _) => StartupDirectoriesError.invalidModsDir,
        _ => StartupDirectoriesError.invalidSavesDir,
      };
      _log.warning(
        LogSource.app,
        'Rejected selected TTS folders',
        details:
            'mods: ${picked.modsDir} (valid: ${modsDir != null}), '
            'saves: ${picked.savesDir} (valid: ${savesDir != null})',
      );
      state = AsyncData(
        StartupNeedsDirectories(
          modsDirExists: modsDir != null,
          savesDirExists: savesDir != null,
          error: error,
        ),
      );
      return;
    }

    final resolved = Directories(
      modsDir: modsDir,
      savesDir: savesDir,
      backupsDir: picked.backupsDir,
    );
    await ref.read(directoriesProvider.notifier).set(resolved);
    if (!ref.mounted) return;
    _log.info(
      LogSource.app,
      'Saved TTS folders',
      details:
          'mods: ${resolved.modsDir}, saves: ${resolved.savesDir}'
          '${resolved.hasBackupsDir ? ', backups: ${resolved.backupsDir}' : ''}',
    );
    // The refresh starts first so the shell's first frame already sees the
    // library provider loading.
    _startRefresh();
    state = const AsyncData(StartupReady());
  }

  /// Runs the whole sequence again from the folder check. After a
  /// [StartupFailed] the stored folders are read again too, since that read
  /// is what failed.
  void retry() {
    _log.info(LogSource.app, 'Retrying startup');
    if (state.value is StartupFailed) ref.invalidate(directoriesProvider);
    ref.invalidateSelf();
  }

  /// Logs the hand-over to the shell and kicks off the first library refresh
  /// without waiting for it. The library provider reports progress and
  /// failures itself; a refresh that throws is only logged here.
  void _startRefresh() {
    final log = _log;
    final timeline = ref.read(startupTimelineProvider)
      ..mark(StartupTimeline.refreshRequested);
    log.info(
      LogSource.app,
      'Refreshing library: sinceMainMs=${timeline.elapsedMs}',
    );
    final library = ref.read(libraryControllerProvider.notifier);
    // `Future.sync` runs `refresh` right away (the library provider is
    // loading before the shell's first frame) and turns a synchronous throw
    // into a failed future.
    unawaited(
      Future<void>.sync(library.refresh)
          .catchError((Object error, StackTrace stackTrace) {
            log.error(
              LogSource.app,
              'Library refresh failed during startup',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
    log.success(
      LogSource.app,
      'Startup complete, showing the shell: sinceMainMs=${timeline.elapsedMs}',
    );
  }

  /// Runs the legacy importer once: when the key-value store has no
  /// settings record yet and [legacyImporterProvider] finds 2.x data, the
  /// settings and folders are written to the new store. The 2.x folder is
  /// deliberately left in place: 2.x keeps working next to 3.x and the user
  /// decides when to remove it (plan D4). Failures are logged and ignored;
  /// startup goes on with the defaults.
  Future<void> _importLegacySettings() async {
    final importer = ref.read(legacyImporterProvider);
    if (importer == null) return;
    try {
      final store = ref.read(keyValueStoreProvider);
      if (await store.read(SettingsController.storageKey) != null) return;
      if (!ref.mounted) return;
      final legacy = await importer.read();
      if (legacy == null || !ref.mounted) return;
      await ref.read(settingsProvider.notifier).update(legacy.settings);
      if (!ref.mounted) return;
      final directories = legacy.directories;
      if (directories != null) {
        await ref.read(directoriesProvider.notifier).set(directories);
        if (!ref.mounted) return;
      }
      _log.info(
        LogSource.app,
        'Imported settings from TTS Mod Vault 2.x',
        details: directories == null
            ? 'no folders were stored'
            : 'mods: ${directories.modsDir}, saves: ${directories.savesDir}'
                  '${directories.hasBackupsDir ? ', backups: ${directories.backupsDir}' : ''}',
      );
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      _log.error(
        LogSource.app,
        'Could not import the TTS Mod Vault 2.x settings; using defaults',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  AppLog get _log => ref.read(appLogProvider);
}
