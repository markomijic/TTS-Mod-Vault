// Round trip against a real Hive box in a temp directory: what 2.x wrote
// (settings JSON with display labels, folder strings) is what 3.x reads.

import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Hive;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/legacy/hive_settings_importer.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';

void main() {
  late Directory documents;
  late HiveSettingsImporter importer;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('ttsmv_documents_');
    importer = HiveSettingsImporter(
      fs: const LocalFileSystem(),
      documentsDir: documents.path,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  /// Writes the `AppData` box the way v2's `Storage` did.
  Future<void> writeLegacyBox(Map<String, String> values) async {
    final box = await Hive.openBox<String>(
      HiveSettingsImporter.appDataBox,
      path: importer.legacyDir,
    );
    await box.putAll(values);
    await box.close();
  }

  test('no legacy folder: nothing to import', () async {
    expect(importer.exists, isFalse);
    expect(await importer.read(), isNull);
    await importer.deleteLegacyData();
  });

  test('reads settings and folders written by 2.x', () async {
    final v2Settings = {
      'useModsListView': true,
      'useBackupsListView': false,
      'showTitleOnCards': true,
      'checkForUpdatesOnStart': false,
      'concurrentDownloads': 7,
      'showSavedObjects': true,
      'showBackupState': false,
      'defaultSortOption': 'Newest',
      'defaultBackupSortOption': 'Oldest',
      'forceBackupJsonFilename': true,
      'ignoreAudioAssets': false,
      'allowCustomSavesFolder': true,
      'urlReplacementPresets': [
        {
          'label': 'Steam',
          'oldUrl': 'http://cloud-3.steamusercontent.com/',
          'newUrl': 'https://steamusercontent-a.akamaihd.net/',
        },
      ],
      'assetUrlFontSize': 14.0,
      'ignoredSubfolders': ['Old'],
      'ignoredDomains': ['pastebin.com'],
      'showPdfThumbnails': true,
    };
    final mods = p.join(documents.path, 'TTS', 'Mods');
    final saves = p.join(documents.path, 'TTS', 'Saves');
    final backups = p.join(documents.path, 'Backups');
    await writeLegacyBox({
      HiveSettingsImporter.settingsKey: jsonEncode(v2Settings),
      HiveSettingsImporter.modsDirKey: mods,
      HiveSettingsImporter.savesDirKey: saves,
      HiveSettingsImporter.backupsDirKey: backups,
    });
    expect(
      File(p.join(importer.legacyDir, 'appdata.hive')).existsSync(),
      isTrue,
      reason: 'Hive lower-cases box file names',
    );

    expect(importer.exists, isTrue);
    final legacy = await importer.read();

    expect(legacy, isNotNull);
    expect(
      legacy!.directories,
      Directories(modsDir: mods, savesDir: saves, backupsDir: backups),
    );
    final s = legacy.settings;
    expect(s.useModsListView, isTrue);
    expect(s.showTitleOnCards, isTrue);
    expect(s.checkForUpdatesOnStart, isFalse);
    expect(s.concurrentDownloads, 7);
    expect(s.showSavedObjects, isTrue);
    expect(s.showBackupState, isFalse);
    expect(s.defaultSortOption, ModSortOption.newest);
    expect(s.defaultBackupSortOption, BackupSortOption.dateAsc);
    expect(s.forceBackupJsonFilename, isTrue);
    expect(s.ignoreAudioAssets, isFalse);
    expect(s.allowCustomSavesFolder, isTrue);
    expect(s.urlReplacementPresets.single.label, 'Steam');
    expect(s.assetUrlFontSize, 14);
    expect(s.ignoredSubfolders, ['Old']);
    expect(s.ignoredDomains, ['pastebin.com']);
    expect(s.showPdfThumbnails, isTrue);
    // Reading leaves the data in place.
    expect(importer.exists, isTrue);
  });

  test('folders are null when Mods or Saves is missing; settings default '
      'when absent', () async {
    await writeLegacyBox({
      HiveSettingsImporter.modsDirKey: p.join(documents.path, 'Mods'),
    });

    final legacy = await importer.read();

    expect(legacy, isNotNull);
    expect(legacy!.directories, isNull);
    expect(legacy.settings, AppSettings.defaults);
  });

  test('a corrupt settings JSON yields the defaults', () async {
    await writeLegacyBox({HiveSettingsImporter.settingsKey: '{not json'});

    final legacy = await importer.read();

    expect(legacy!.settings, AppSettings.defaults);
  });

  test('deleteLegacyData removes the whole 2.x folder', () async {
    await writeLegacyBox({HiveSettingsImporter.settingsKey: '{}'});
    File(p.join(importer.legacyDir, 'modurls.hive')).writeAsBytesSync([1]);
    await importer.read();

    await importer.deleteLegacyData();

    expect(Directory(importer.legacyDir).existsSync(), isFalse);
    expect(importer.exists, isFalse);
    expect(documents.existsSync(), isTrue, reason: 'only our folder goes');
  });
}
