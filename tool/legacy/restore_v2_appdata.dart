// Developer tool: rebuilds the TTS Mod Vault 2.x Hive `AppData` box from the
// settings v3 holds in its kv store, so a 2.x install keeps its settings.
//
// Usage (from v3/):  dart run tool/legacy/restore_v2_appdata.dart
//
// Reads `%APPDATA%\io.github.markomijic\TTS Mod Vault\vault.sqlite` (kv keys
// `settings` and `directories`) and writes `%USERPROFILE%\Documents\TTS Mod
// Vault\appdata.hive` with the 2.x keys and value formats. Never touches the
// TTS library. Refuses to overwrite an existing box.
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _sortLabels = {
  'nameAsc': 'A-Z',
  'newest': 'Newest',
  'recentlyUpdated': 'Recently updated',
  'missingAssets': 'Missing assets',
};
const _backupSortLabels = {
  'nameAsc': 'A-Z',
  'nameDesc': 'Z-A',
  'sizeDesc': 'Largest',
  'sizeAsc': 'Smallest',
  'dateDesc': 'Newest',
  'dateAsc': 'Oldest',
};

Future<void> main(List<String> args) async {
  final appData = Platform.environment['APPDATA']!;
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!;
  final dbPath = p.join(
    appData,
    'io.github.markomijic',
    'TTS Mod Vault',
    'vault.sqlite',
  );
  final legacyDir = p.join(home, 'Documents', 'TTS Mod Vault');

  if (File(p.join(legacyDir, 'appdata.hive')).existsSync() ||
      File(p.join(legacyDir, 'AppData.hive')).existsSync()) {
    stderr.writeln(
      'A 2.x AppData box already exists in $legacyDir; nothing done.',
    );
    exitCode = 1;
    return;
  }

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  String? read(String key) {
    final rows = db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  final settingsJson = read('settings');
  final directoriesJson = read('directories');
  db.close();
  if (settingsJson == null) {
    stderr.writeln('No settings in $dbPath; nothing to restore.');
    exitCode = 1;
    return;
  }

  final settings = Map<String, Object?>.from(jsonDecode(settingsJson) as Map);
  settings['defaultSortOption'] =
      _sortLabels[settings['defaultSortOption']] ?? 'A-Z';
  settings['defaultBackupSortOption'] =
      _backupSortLabels[settings['defaultBackupSortOption']] ?? 'A-Z';

  Directory(legacyDir).createSync(recursive: true);
  Hive.init(legacyDir);
  final box = await Hive.openBox<String>('AppData');
  await box.put('TTSModVaultSettings', jsonEncode(settings));
  if (directoriesJson != null) {
    final dirs = Map<String, Object?>.from(jsonDecode(directoriesJson) as Map);
    await box.put('ModsDir', dirs['modsDir'] as String);
    await box.put('SavesDir', dirs['savesDir'] as String);
    final backups = dirs['backupsDir'] as String? ?? '';
    if (backups.isNotEmpty) await box.put('BackupsDir', backups);
  }
  await box.close();
  stdout.writeln('Restored 2.x AppData box in $legacyDir');
  stdout.writeln('settings: ${jsonEncode(settings)}');
}
