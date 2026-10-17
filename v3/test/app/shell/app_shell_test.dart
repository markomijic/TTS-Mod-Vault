// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/app.dart';
import 'package:tts_mod_vault/app/shell/placeholders.dart';
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_page.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';

/// Startup double that skips the folder check and library refresh so the
/// shell renders immediately.
class _ReadyStartupController extends StartupController {
  @override
  Future<StartupState> build() async => const StartupReady();
}

/// Library double: an empty, already-refreshed library and a record of
/// `refresh` calls (no IO).
class SpyLibraryController extends LibraryController {
  final List<bool> refreshCalls = [];

  @override
  FutureOr<LibraryState> build() => LibraryState(lastRefresh: DateTime(2024));

  @override
  Future<void> refresh({bool clearCache = false}) async {
    refreshCalls.add(clearCache);
  }
}

Future<InMemoryKeyValueStore> pumpApp(
  WidgetTester tester, {
  InMemoryKeyValueStore? store,
  SpyLibraryController? library,
}) async {
  final kv = store ?? InMemoryKeyValueStore();
  final spy = library ?? SpyLibraryController();
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(kv),
        startupControllerProvider.overrideWith(_ReadyStartupController.new),
        libraryControllerProvider.overrideWith(() => spy),
      ],
      child: const App(),
    ),
  );
  // Let the async store reads complete and the width animation settle.
  await tester.pumpAndSettle();
  return kv;
}

Finder inSidebar(Finder matching) =>
    find.descendant(of: find.byType(VaultSidebar), matching: matching);

double sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(VaultSidebar)).width;

void main() {
  testWidgets('renders both destinations collapsed with tooltips', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(VaultSidebar), findsOneWidget);
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    expect(inSidebar(find.byTooltip('Mods')), findsOneWidget);
    expect(inSidebar(find.byTooltip('Backups')), findsOneWidget);
    expect(inSidebar(find.byTooltip('Refresh')), findsOneWidget);
    expect(inSidebar(find.byTooltip('Settings')), findsOneWidget);
    // Collapsed form shows no labels.
    expect(inSidebar(find.text('Backups')), findsNothing);
    expect(find.byType(ModsPage), findsOneWidget);
  });

  testWidgets('switching to Backups shows the Backups placeholder', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(inSidebar(find.byTooltip('Backups')));
    await tester.pumpAndSettle();

    expect(find.byType(BackupsPage), findsOneWidget);
    expect(find.byType(ModsPage), findsNothing);
    expect(find.text('Backups'), findsOneWidget);

    await tester.tap(inSidebar(find.byTooltip('Mods')));
    await tester.pumpAndSettle();
    expect(find.byType(ModsPage), findsOneWidget);
  });

  testWidgets('chevron toggles labels and persists the flag', (tester) async {
    final store = await pumpApp(tester);

    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();

    expect(sidebarWidth(tester), VaultSidebar.extendedWidth);
    expect(inSidebar(find.text('Mods')), findsOneWidget);
    expect(inSidebar(find.text('Backups')), findsOneWidget);
    expect(inSidebar(find.text('Download Workshop mods')), findsOneWidget);
    expect(inSidebar(find.text('Help')), findsOneWidget);
    expect(await store.read(SidebarController.storageKey), 'true');

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();

    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    expect(inSidebar(find.text('Backups')), findsNothing);
    expect(await store.read(SidebarController.storageKey), 'false');
  });

  testWidgets('starts extended when the stored flag says so', (tester) async {
    final store = InMemoryKeyValueStore();
    await store.write(SidebarController.storageKey, 'true');

    await pumpApp(tester, store: store);

    expect(sidebarWidth(tester), VaultSidebar.extendedWidth);
    expect(inSidebar(find.text('Mods')), findsOneWidget);
  });

  testWidgets('hovering the sidebar does not change its width', (tester) async {
    await pumpApp(tester);
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byType(VaultSidebar)));
    await tester.pump();
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);

    // Long enough for any delayed hover expansion to have kicked in.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);

    await gesture.moveTo(tester.getCenter(inSidebar(find.byTooltip('Mods'))));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    expect(inSidebar(find.text('Backups')), findsNothing);
  });

  testWidgets('action items show the not-implemented snack bar', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(inSidebar(find.byTooltip('Cleanup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Not implemented yet'), findsOneWidget);
  });

  testWidgets('Refresh asks for confirmation and passes the checkbox', (
    tester,
  ) async {
    final library = SpyLibraryController();
    await pumpApp(tester, library: library);

    await tester.tap(inSidebar(find.byTooltip('Refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh all data?'), findsOneWidget);
    expect(find.text('Clear Vault cache'), findsOneWidget);

    // Cancel does nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.refreshCalls, isEmpty);

    // Confirm without the checkbox: a plain refresh.
    await tester.tap(inSidebar(find.byTooltip('Refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();
    expect(library.refreshCalls, [false]);

    // Confirm with the checkbox: clear the cache.
    await tester.tap(inSidebar(find.byTooltip('Refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();
    expect(library.refreshCalls, [false, true]);
  });
}
