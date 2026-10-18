import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Locations of the app's private files (database, log file).
///
/// Resolved from `path_provider`'s application-support directory
/// (`docs/v3-rewrite-plan.md`, section 3.1):
///
///  - Windows: `%APPDATA%\io.github.markomijic\TTS Mod Vault\`
///    (folder names come from `CompanyName`/`ProductName` in `Runner.rc`)
///  - macOS:   `~/Library/Application Support/io.github.markomijic.ttsModVault/`
///  - Linux:   `~/.local/share/tts_mod_vault/`
final class AppPaths {
  const AppPaths({required this.dataDir});

  /// Directory that holds every file below.
  final String dataDir;

  /// The SQLite database (`AppDatabase`).
  String get databaseFile => p.join(dataDir, 'vault.sqlite');

  /// The rotating log file written by the app log's file sink.
  String get logFile => p.join(dataDir, 'vault.log');

  /// Resolves the data directory. [supportDirectory] is injectable for tests.
  static Future<AppPaths> resolve({
    Future<Directory> Function() supportDirectory =
        getApplicationSupportDirectory,
  }) async {
    final dir = await supportDirectory();
    return AppPaths(dataDir: dir.path);
  }

  /// Creates [dataDir] (and parents) if it does not exist yet.
  Future<Directory> ensureExists() =>
      Directory(dataDir).create(recursive: true);
}
