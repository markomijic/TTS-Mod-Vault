import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

void main() {
  late InMemoryKeyValueStore store;
  late AppLog log;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryKeyValueStore();
    log = AppLog(store: LogStore());
    container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appLogProvider.overrideWithValue(log),
      ],
    );
    addTearDown(log.dispose);
  });

  test('defaults to following the system and decodes junk as null', () {
    expect(AppSettings.defaults.locale, isNull);
    expect(AppSettings.fromJson(const {'locale': 5}).locale, isNull);
    expect(AppSettings.fromJson(const {'locale': '  '}).locale, isNull);
    expect(AppSettings.fromJson(const {'locale': 'pt-BR'}).locale, 'pt-BR');
  });

  test('copyWith can set and clear the locale', () {
    final set = AppSettings.defaults.copyWith(locale: () => 'de');
    expect(set.locale, 'de');
    expect(set.copyWith(showPdfThumbnails: true).locale, 'de');
    expect(set.copyWith(locale: () => null).locale, isNull);
  });

  test('the locale persists and reset returns to the system default', () async {
    final controller = container.read(settingsProvider.notifier);
    await controller.update(AppSettings.defaults.copyWith(locale: () => 'de'));

    final raw = await store.read(SettingsController.storageKey);
    final stored = jsonDecode(raw!) as Map<String, Object?>;
    expect(stored['locale'], 'de');
    expect(container.read(localeSettingProvider)?.languageCode, 'de');

    await controller.reset();
    expect(container.read(settingsProvider).locale, isNull);
    expect(container.read(localeSettingProvider), isNull);
  });
}
