import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

void main() {
  group('AppSettings', () {
    test('defaults match 2.x', () {
      const s = AppSettings.defaults;
      expect(s.useModsListView, isFalse);
      expect(s.useBackupsListView, isFalse);
      expect(s.showTitleOnCards, isFalse);
      expect(s.checkForUpdatesOnStart, isTrue);
      expect(s.concurrentDownloads, 5);
      expect(s.showSavedObjects, isFalse);
      expect(s.showBackupState, isTrue);
      expect(s.defaultSortOption, ModSortOption.nameAsc);
      expect(s.defaultBackupSortOption, BackupSortOption.nameAsc);
      expect(s.forceBackupJsonFilename, isFalse);
      expect(s.ignoreAudioAssets, isTrue);
      expect(s.checkAfterDownload, isTrue);
      expect(s.allowCustomSavesFolder, isFalse);
      expect(s.urlReplacementPresets, isEmpty);
      expect(s.assetUrlFontSize, 12);
      expect(s.ignoredSubfolders, isEmpty);
      expect(s.ignoredDomains, isEmpty);
      expect(s.showPdfThumbnails, isFalse);
    });

    test('round-trips through JSON with every field changed', () {
      const original = AppSettings(
        useModsListView: true,
        useBackupsListView: true,
        showTitleOnCards: true,
        checkForUpdatesOnStart: false,
        concurrentDownloads: 8,
        showSavedObjects: true,
        showBackupState: false,
        defaultSortOption: ModSortOption.missingAssets,
        defaultBackupSortOption: BackupSortOption.dateAsc,
        forceBackupJsonFilename: true,
        ignoreAudioAssets: false,
        allowCustomSavesFolder: true,
        urlReplacementPresets: [
          UrlReplacementPreset(
            label: 'a',
            oldUrl: 'http://a/',
            newUrl: 'https://b/',
          ),
        ],
        assetUrlFontSize: 16,
        ignoredSubfolders: ['Old', 'Queued'],
        ignoredDomains: ['pastebin.com'],
        checkAfterDownload: false,
        showPdfThumbnails: true,
      );

      final decoded = AppSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
    });

    test('decodes a 2.x record: display labels and stringly typed values', () {
      final decoded = AppSettings.fromJson({
        'useModsListView': 'true',
        'checkForUpdatesOnStart': 'false',
        'concurrentDownloads': '3',
        'defaultSortOption': 'Recently updated',
        'defaultBackupSortOption': 'Largest',
        'assetUrlFontSize': 14,
        'urlReplacementPresets': [
          {'label': 'Steam', 'oldUrl': 'http://x/', 'newUrl': 'https://y/'},
          'garbage',
        ],
        'ignoredSubfolders': ['Old', null, ''],
        'ignoredDomains': ['a.com'],
      });

      expect(decoded.useModsListView, isTrue);
      expect(decoded.checkForUpdatesOnStart, isFalse);
      expect(decoded.concurrentDownloads, 3);
      expect(decoded.defaultSortOption, ModSortOption.recentlyUpdated);
      expect(decoded.defaultBackupSortOption, BackupSortOption.sizeDesc);
      expect(decoded.assetUrlFontSize, 14);
      expect(decoded.urlReplacementPresets, [
        const UrlReplacementPreset(
          label: 'Steam',
          oldUrl: 'http://x/',
          newUrl: 'https://y/',
        ),
      ]);
      expect(decoded.ignoredSubfolders, ['Old']);
      expect(decoded.ignoredDomains, ['a.com']);
    });

    test('every 2.x sort label maps onto an option', () {
      for (final entry in modSortOptionLegacyLabels.entries) {
        expect(modSortOptionFromJson(entry.value), entry.key);
        expect(modSortOptionFromJson(entry.key.name), entry.key);
      }
      for (final entry in backupSortOptionLegacyLabels.entries) {
        expect(backupSortOptionFromJson(entry.value), entry.key);
        expect(backupSortOptionFromJson(entry.key.name), entry.key);
      }
      expect(modSortOptionFromJson('nonsense'), ModSortOption.nameAsc);
      expect(modSortOptionFromJson(7), ModSortOption.nameAsc);
      expect(backupSortOptionFromJson(null), BackupSortOption.nameAsc);
    });

    test('malformed fields fall back to defaults and ranges are clamped', () {
      final decoded = AppSettings.fromJson({
        'useModsListView': 1,
        'concurrentDownloads': 99,
        'assetUrlFontSize': 'huge',
        'defaultSortOption': ['A-Z'],
        'urlReplacementPresets': 'none',
        'ignoredSubfolders': 'Old',
      });

      expect(decoded.useModsListView, isFalse);
      expect(decoded.concurrentDownloads, AppSettings.maxConcurrentDownloads);
      expect(decoded.assetUrlFontSize, 12);
      expect(decoded.defaultSortOption, ModSortOption.nameAsc);
      expect(decoded.urlReplacementPresets, isEmpty);
      expect(decoded.ignoredSubfolders, isEmpty);
      expect(
        AppSettings.fromJson({'concurrentDownloads': 0}).concurrentDownloads,
        1,
      );
      expect(AppSettings.fromJson({'assetUrlFontSize': 2}).assetUrlFontSize, 8);
    });

    test('copyWith replaces only the given fields', () {
      const base = AppSettings.defaults;
      final copy = base.copyWith(
        showPdfThumbnails: true,
        concurrentDownloads: 2,
      );
      expect(copy.showPdfThumbnails, isTrue);
      expect(copy.concurrentDownloads, 2);
      expect(copy.copyWith(), copy);
      expect(copy, isNot(base));
    });
  });
}
