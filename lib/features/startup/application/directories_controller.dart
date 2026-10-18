import 'dart:convert';
import 'dart:io' show Platform;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';

/// Key under which [Directories] is persisted in the key-value store.
const directoriesStorageKey = 'directories';

/// Platform name used by [defaultDirectories], overridable in tests.
final platformNameProvider = Provider<String>((ref) {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  return 'linux';
});

/// User home directory, overridable in tests.
final userHomeProvider = Provider<String>((ref) {
  final env = Platform.environment;
  return (Platform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
});

/// The TTS folders the app works with (mods, saves, optional backups).
///
/// Loaded from the key-value store on first read; when nothing is stored the
/// per-OS TTS defaults are used. Callers must validate that the folders exist
/// before scanning (see `resolveModsDir`/`resolveSavesDir`).
final directoriesProvider =
    AsyncNotifierProvider<DirectoriesController, Directories>(
      DirectoriesController.new,
    );

/// Owns the persisted [Directories] value.
class DirectoriesController extends AsyncNotifier<Directories> {
  @override
  Future<Directories> build() async {
    final stored = await ref
        .read(keyValueStoreProvider)
        .read(directoriesStorageKey);
    if (stored != null) {
      try {
        final json = jsonDecode(stored);
        if (json is Map<String, Object?>) return Directories.fromJson(json);
      } on FormatException {
        // Fall through to defaults.
      }
    }
    return defaultDirectories(
      platform: ref.read(platformNameProvider),
      home: ref.read(userHomeProvider),
    );
  }

  /// Replaces and persists the directories.
  ///
  /// Waits for a pending [build] first so its result cannot overwrite the new
  /// value after the fact.
  Future<void> set(Directories directories) async {
    if (state.isLoading) {
      try {
        await future;
      } on Object {
        // Defaults failed to load; the explicit value below wins anyway.
      }
    }
    state = AsyncData(directories);
    await ref
        .read(keyValueStoreProvider)
        .write(directoriesStorageKey, jsonEncode(directories.toJson()));
  }

  /// Convenience for changing only the backups folder.
  Future<void> setBackupsDir(String backupsDir) async {
    final current = state.value ?? await future;
    await set(current.copyWith(backupsDir: backupsDir));
  }
}
