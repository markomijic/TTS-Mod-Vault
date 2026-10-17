import 'dart:async';
import 'dart:io' show Directory;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/startup_timeline_provider.dart';
import 'package:tts_mod_vault/bootstrap/startup_timeline.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/startup_state.dart';

export 'package:tts_mod_vault/features/startup/application/startup_state.dart';

/// "Does this directory exist" check used by startup; tests override it so
/// no disk is touched. Defaults to `Directory(path).existsSync()`.
final directoryExistsProvider = Provider<DirectoryExists>(
  (ref) =>
      (path) => Directory(path).existsSync(),
);

/// Whether any existing folder is accepted as the Saves folder (the
/// "custom saves folder" setting). Placeholder until settings land in
/// Phase 5; always false for now.
final allowCustomSavesFolderProvider = Provider<bool>((ref) => false);

/// Drives the start-up sequence; see [StartupState] for the state machine.
final startupControllerProvider =
    AsyncNotifierProvider<StartupController, StartupState>(
      StartupController.new,
    );

/// Port of 2.x `SplashPage`: check the stored Mods and Saves folders, let the
/// user pick them when missing, refresh the library, hand over to the shell.
///
/// The provider's `AsyncLoading` phase is the [StartupChecking] state; every
/// later state is an `AsyncData`. Errors never surface as `AsyncError`: a
/// failed library refresh becomes [StartupFailed] so the page can offer a
/// Retry button.
class StartupController extends AsyncNotifier<StartupState> {
  @override
  Future<StartupState> build() async {
    final directories = await ref.read(directoriesProvider.future);
    final exists = ref.read(directoryExistsProvider);
    final modsDirExists = exists(directories.modsDir);
    final savesDirExists = exists(directories.savesDir);

    // TODO(v3): Phase 3 adds the GitHub release check here (v2 ran it in
    // SplashPage between settings init and the folder check).

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
    // The refresh runs after build has settled so the Loading state is
    // observable before Ready/Failed replace it.
    unawaited(Future<void>(_load));
    return const StartupLoading();
  }

  /// Validates [picked], persists the resolved folders and loads the library.
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
      allowCustomPath: ref.read(allowCustomSavesFolderProvider),
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
    state = const AsyncData(StartupLoading());
    await ref.read(directoriesProvider.notifier).set(resolved);
    if (!ref.mounted) return;
    _log.info(
      LogSource.app,
      'Saved TTS folders',
      details:
          'mods: ${resolved.modsDir}, saves: ${resolved.savesDir}'
          '${resolved.hasBackupsDir ? ', backups: ${resolved.backupsDir}' : ''}',
    );
    await _load();
  }

  /// Runs the whole sequence again from the folder check.
  void retry() {
    _log.info(LogSource.app, 'Retrying startup');
    ref.invalidateSelf();
  }

  Future<void> _load() async {
    if (!ref.mounted) return;
    state = const AsyncData(StartupLoading());
    final timeline = ref.read(startupTimelineProvider)
      ..mark(StartupTimeline.refreshRequested);
    _log.info(
      LogSource.app,
      'Refreshing library: sinceMainMs=${timeline.elapsedMs}',
    );
    try {
      await ref.read(libraryControllerProvider.notifier).refresh();
      await ref.read(libraryControllerProvider.future);
      if (!ref.mounted) return;
      _log.success(LogSource.app, 'Startup complete');
      state = const AsyncData(StartupReady());
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      _log.error(
        LogSource.app,
        'Library refresh failed during startup',
        error: error,
        stackTrace: stackTrace,
      );
      state = AsyncData(StartupFailed(error, stackTrace));
    }
  }

  AppLog get _log => ref.read(appLogProvider);
}
