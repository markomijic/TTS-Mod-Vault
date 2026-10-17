// NetworkOptions JSON round trip and controller persistence.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';

void main() {
  group('NetworkOptions', () {
    test('defaults match v2', () {
      const options = NetworkOptions();
      expect(options.concurrentDownloads, 5);
      expect(options.ignoredDomains, isEmpty);
      expect(options, NetworkOptions.defaults);
    });

    test('round-trips through JSON', () {
      const options = NetworkOptions(
        concurrentDownloads: 8,
        ignoredDomains: ['example.com', 'cdn.test'],
      );
      final restored = NetworkOptions.fromJson(
        jsonDecode(jsonEncode(options.toJson())) as Map<String, Object?>,
      );
      expect(restored, options);
      expect(restored.hashCode, options.hashCode);
    });

    test('fromJson falls back to defaults on malformed fields', () {
      final options = NetworkOptions.fromJson({
        'concurrentDownloads': 'many',
        'ignoredDomains': ['ok', 3, '  ', ' trimmed '],
      });
      expect(options.concurrentDownloads, 5);
      expect(options.ignoredDomains, ['ok', 'trimmed']);
      expect(
        NetworkOptions.fromJson({'concurrentDownloads': 0}).concurrentDownloads,
        5,
      );
      expect(
        NetworkOptions.fromJson({'concurrentDownloads': 999})
            .concurrentDownloads,
        NetworkOptions.maxConcurrent,
      );
    });
  });

  group('NetworkOptionsController', () {
    late InMemoryKeyValueStore store;
    late ProviderContainer container;

    setUp(() {
      store = InMemoryKeyValueStore();
      container = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
    });

    test('starts with defaults and persists changes', () async {
      expect(container.read(networkOptionsProvider), NetworkOptions.defaults);
      await container
          .read(networkOptionsProvider.notifier)
          .setConcurrentDownloads(3);
      await container.read(networkOptionsProvider.notifier).setIgnoredDomains([
        ' a.com ',
        '',
        'b.com',
      ]);
      final options = container.read(networkOptionsProvider);
      expect(options.concurrentDownloads, 3);
      expect(options.ignoredDomains, ['a.com', 'b.com']);
      final stored = await store.read(NetworkOptionsController.storageKey);
      expect(
        NetworkOptions.fromJson(jsonDecode(stored!) as Map<String, Object?>),
        options,
      );
    });

    test('restores the stored value', () async {
      await store.write(
        NetworkOptionsController.storageKey,
        jsonEncode(
          const NetworkOptions(
            concurrentDownloads: 2,
            ignoredDomains: ['x.org'],
          ).toJson(),
        ),
      );
      final options = await container
          .read(networkOptionsProvider.notifier)
          .ensureLoaded();
      expect(options.concurrentDownloads, 2);
      expect(options.ignoredDomains, ['x.org']);
    });

    test('clamps the concurrency', () async {
      await container
          .read(networkOptionsProvider.notifier)
          .setConcurrentDownloads(0);
      expect(container.read(networkOptionsProvider).concurrentDownloads, 1);
      await container
          .read(networkOptionsProvider.notifier)
          .setConcurrentDownloads(500);
      expect(
        container.read(networkOptionsProvider).concurrentDownloads,
        NetworkOptions.maxConcurrent,
      );
    });

    test('a corrupt record keeps the defaults', () async {
      await store.write(NetworkOptionsController.storageKey, '{not json');
      final options = await container
          .read(networkOptionsProvider.notifier)
          .ensureLoaded();
      expect(options, NetworkOptions.defaults);
    });
  });
}
