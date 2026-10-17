/// One-shot import of the 2.x settings (plan section 3.1, decision D4).
///
/// v2 kept everything in Hive boxes under `<Documents>/TTS Mod Vault/`.
/// Only the `AppData` box matters: the settings JSON under
/// `TTSModVaultSettings` and the three folder paths. The mod index is not
/// migrated; v3 rebuilds it on the first start.
///
/// `hive_ce_flutter` stays a dependency for this file alone; remove both
/// in 3.1.
library;

import 'dart:convert';

import 'package:file/file.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Hive;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';

/// What was found in the 2.x store.
@immutable
final class LegacySettings {
  /// Creates the record.
  const LegacySettings({required this.settings, required this.directories});

  /// The 2.x settings (defaults where the record had no settings JSON).
  final AppSettings settings;

  /// The 2.x folders, or null when the Mods or Saves folder was not stored.
  final Directories? directories;

  @override
  String toString() =>
      'LegacySettings(directories: $directories, settings: $settings)';
}

/// Reads and removes a previous major version's settings.
abstract interface class LegacySettingsImporter {
  /// Whether legacy data is present without opening it.
  bool get exists;

  /// Reads the legacy settings, or null when there are none. Must not
  /// delete anything.
  Future<LegacySettings?> read();

  /// Deletes the legacy data. Called by the importer's user once the
  /// settings have been written to the new store.
  Future<void> deleteLegacyData();
}

/// Imports from the v2 Hive `AppData` box in `<documentsDir>/TTS Mod Vault`.
final class HiveSettingsImporter implements LegacySettingsImporter {
  /// Creates an importer for the user's [documentsDir]. [fs] is used for
  /// the existence checks and the deletion; Hive itself reads through
  /// `dart:io`, so [fs] must be the real disk outside of pure unit tests.
  HiveSettingsImporter({required this.fs, required this.documentsDir});

  /// v2's folder name under Documents (`Hive.initFlutter('TTS Mod Vault')`).
  static const String legacyFolderName = 'TTS Mod Vault';

  /// v2's box holding settings and folders.
  static const String appDataBox = 'AppData';

  /// v2's settings key inside [appDataBox].
  static const String settingsKey = 'TTSModVaultSettings';

  /// v2's folder keys inside [appDataBox].
  static const String modsDirKey = 'ModsDir';

  /// See [modsDirKey].
  static const String savesDirKey = 'SavesDir';

  /// See [modsDirKey].
  static const String backupsDirKey = 'BackupsDir';

  /// The file system used for existence checks and deletion.
  final FileSystem fs;

  /// The user's Documents folder.
  final String documentsDir;

  /// `<documentsDir>/TTS Mod Vault`.
  String get legacyDir => p.join(documentsDir, legacyFolderName);

  /// The box file Hive writes (names are lower-cased on disk; the
  /// original spelling is checked too for case-sensitive file systems).
  List<String> get boxFileCandidates => [
    p.join(legacyDir, '${appDataBox.toLowerCase()}.hive'),
    p.join(legacyDir, '$appDataBox.hive'),
  ];

  @override
  bool get exists =>
      boxFileCandidates.any((path) => fs.file(path).existsSync());

  @override
  Future<LegacySettings?> read() async {
    if (!exists) return null;
    final box = await Hive.openBox<String>(appDataBox, path: legacyDir);
    try {
      final settingsJson = box.get(settingsKey);
      final modsDir = box.get(modsDirKey);
      final savesDir = box.get(savesDirKey);
      final backupsDir = box.get(backupsDirKey);
      return LegacySettings(
        settings: _decodeSettings(settingsJson),
        directories: modsDir == null || savesDir == null
            ? null
            : Directories(
                modsDir: modsDir,
                savesDir: savesDir,
                backupsDir: backupsDir ?? '',
              ),
      );
    } finally {
      await box.close();
    }
  }

  @override
  Future<void> deleteLegacyData() async {
    final dir = fs.directory(legacyDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// The settings record decoded with the v2 keys and labels; defaults
  /// when absent or unreadable (v2 did the same on a bad record).
  static AppSettings _decodeSettings(String? raw) {
    if (raw == null) return AppSettings.defaults;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, Object?>
          ? AppSettings.fromJson(json)
          : AppSettings.defaults;
    } on FormatException {
      return AppSettings.defaults;
    }
  }
}

/// The importer the startup sequence runs once, or null when there is
/// nothing to import from (tests, and until `main.dart` overrides it with
/// `HiveSettingsImporter(fs: const LocalFileSystem(), documentsDir:
/// (await getApplicationDocumentsDirectory()).path)`). Deliberately not
/// resolved here: a default that reached into the real Documents folder
/// would delete a developer's 2.x data from a test run.
final legacyImporterProvider = Provider<LegacySettingsImporter?>((ref) => null);
