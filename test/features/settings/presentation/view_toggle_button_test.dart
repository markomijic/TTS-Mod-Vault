// The toolbar view toggles write the list/grid choice into Settings.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/view_toggle_button.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

import '../../images_viewer/themed_app.dart';

void main() {
  late InMemoryKeyValueStore store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryKeyValueStore();
    final log = AppLog(store: LogStore());
    addTearDown(log.dispose);
    container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appLogProvider.overrideWithValue(log),
      ],
    );
  });

  testWidgets('the mods toggle flips useModsListView', (tester) async {
    await pumpThemedApp(
      tester,
      container: container,
      home: const Scaffold(body: ViewToggleButton()),
    );
    expect(find.byTooltip('Show as list'), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    final settings = container.read(settingsProvider);
    expect(settings.useModsListView, isTrue);
    expect(settings.useBackupsListView, isFalse);
    expect(find.byTooltip('Show as grid'), findsOneWidget);
    expect(
      await store.read(SettingsController.storageKey),
      contains('"useModsListView":true'),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).useModsListView, isFalse);
  });

  testWidgets('the backups toggle flips useBackupsListView only', (
    tester,
  ) async {
    await pumpThemedApp(
      tester,
      container: container,
      home: const Scaffold(body: ViewToggleButton(backups: true)),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    final settings = container.read(settingsProvider);
    expect(settings.useBackupsListView, isTrue);
    expect(settings.useModsListView, isFalse);
  });

  testWidgets('follows a change made through the settings', (tester) async {
    await pumpThemedApp(
      tester,
      container: container,
      home: const Scaffold(body: ViewToggleButton()),
    );

    await container
        .read(settingsProvider.notifier)
        .update(const AppSettings(useModsListView: true));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show as grid'), findsOneWidget);
  });
}
