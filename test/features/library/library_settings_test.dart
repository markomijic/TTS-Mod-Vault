import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';

void main() {
  group('LibraryOptions', () {
    test('defaults match 2.x', () {
      const options = LibraryOptions.defaults;
      expect(options.ignoredSubfolders, isEmpty);
      expect(options.includeSavedObjects, isFalse);
      expect(options.ignoreAudioGlobally, isTrue);
      expect(options.forceBackupIdInName, isFalse);
    });

    test('round-trips through JSON', () {
      const original = LibraryOptions(
        ignoredSubfolders: ['Old', 'Queued'],
        includeSavedObjects: true,
        ignoreAudioGlobally: false,
        forceBackupIdInName: true,
      );
      final decoded = LibraryOptions.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
    });

    test('malformed fields fall back to defaults', () {
      final decoded = LibraryOptions.fromJson({
        'ignoredSubfolders': 'Old',
        'includeSavedObjects': 'yes',
        'ignoreAudioGlobally': 0,
        'forceBackupIdInName': null,
      });
      expect(decoded, LibraryOptions.defaults);
      final partial = LibraryOptions.fromJson({
        'ignoredSubfolders': ['Old', 7, ''],
      });
      expect(partial.ignoredSubfolders, ['Old']);
    });
  });

  group('LibraryOptionsController', () {
    late InMemoryKeyValueStore store;
    late ProviderContainer container;

    setUp(() {
      store = InMemoryKeyValueStore();
      container = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
    });

    test('restores the stored value', () async {
      await store.write(
        LibraryOptionsController.storageKey,
        jsonEncode(const LibraryOptions(includeSavedObjects: true).toJson()),
      );
      expect(container.read(libraryOptionsProvider), LibraryOptions.defaults);
      final loaded = await container
          .read(libraryOptionsProvider.notifier)
          .ensureLoaded();
      expect(loaded.includeSavedObjects, isTrue);
      expect(container.read(libraryOptionsProvider), loaded);
    });

    test('ignores a corrupt record', () async {
      await store.write(LibraryOptionsController.storageKey, '{not json');
      final loaded = await container
          .read(libraryOptionsProvider.notifier)
          .ensureLoaded();
      expect(loaded, LibraryOptions.defaults);
    });

    test('setters persist and a late restore does not clobber them', () async {
      await store.write(
        LibraryOptionsController.storageKey,
        jsonEncode(const LibraryOptions(forceBackupIdInName: true).toJson()),
      );
      final notifier = container.read(libraryOptionsProvider.notifier);
      await notifier.setIgnoreAudioGlobally(false);
      await notifier.setIgnoredSubfolders(['Old']);
      await notifier.ensureLoaded();

      final state = container.read(libraryOptionsProvider);
      expect(state.ignoreAudioGlobally, isFalse);
      expect(state.ignoredSubfolders, ['Old']);
      expect(state.forceBackupIdInName, isFalse, reason: 'user change wins');
      final raw = await store.read(LibraryOptionsController.storageKey);
      expect(
        LibraryOptions.fromJson(jsonDecode(raw!) as Map<String, Object?>),
        state,
      );
    });
  });
}
