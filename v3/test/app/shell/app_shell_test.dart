// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/presentation/library_page.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/workshop/presentation/download_workshop_mods_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

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

/// Folders of a library that has a backups folder set.
final Directories shellDirectories = Directories(
  modsDir: p.join('C:', 'TTS', 'Mods'),
  savesDir: p.join('C:', 'TTS', 'Saves'),
  backupsDir: p.join('C:', 'TTS', 'Backups'),
);

class _FixedDirectoriesController extends DirectoriesController {
  @override
  Future<Directories> build() async => shellDirectories;
}

/// Pumps [AppShell] on its own (no startup flow) inside a themed, localised
/// `MaterialApp` at desktop size.
Future<InMemoryKeyValueStore> pumpShell(
  WidgetTester tester, {
  InMemoryKeyValueStore? store,
  SpyLibraryController? library,
}) async {
  final kv = store ?? InMemoryKeyValueStore();
  final spy = library ?? SpyLibraryController();
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(kv),
        libraryControllerProvider.overrideWith(() => spy),
        directoriesProvider.overrideWith(_FixedDirectoriesController.new),
        // No GitHub release check in widget tests.
        checkForUpdatesOnStartProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: AppTheme.build(settings, Brightness.light),
        darkTheme: AppTheme.build(settings, Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppShell(),
      ),
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

const List<String> sidebarLabels = [
  'Refresh',
  'Cleanup',
  'Import backups',
  'Import JSON',
  'Download Workshop mods',
  'Help',
  'Settings',
];

void main() {
  testWidgets('renders the action groups collapsed with tooltips and the '
      'library page', (tester) async {
    await pumpShell(tester);

    expect(find.byType(VaultSidebar), findsOneWidget);
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    for (final label in sidebarLabels) {
      expect(inSidebar(find.byTooltip(label)), findsOneWidget, reason: label);
      // Collapsed form shows no labels.
      expect(inSidebar(find.text(label)), findsNothing, reason: label);
    }
    // No destinations: the tabs live in the page's type selector.
    expect(inSidebar(find.byTooltip('Mods')), findsNothing);
    expect(inSidebar(find.byTooltip('Backups')), findsNothing);
    // One divider between the two action groups, one before the footer.
    expect(inSidebar(find.byType(Divider)), findsNWidgets(2));

    expect(find.byType(LibraryPage), findsOneWidget);
    final selector = find.byType(SegmentedButton<LibraryTab>);
    expect(selector, findsOneWidget);
    for (final tab in ['Mods', 'Saves', 'Backups']) {
      expect(
        find.descendant(of: selector, matching: find.text(tab)),
        findsOneWidget,
        reason: tab,
      );
    }
  });

  testWidgets('chevron toggles labels and persists the flag', (tester) async {
    final store = await pumpShell(tester);

    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();

    expect(sidebarWidth(tester), VaultSidebar.extendedWidth);
    for (final label in sidebarLabels) {
      expect(inSidebar(find.text(label)), findsOneWidget, reason: label);
    }
    expect(await store.read(SidebarController.storageKey), 'true');

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();

    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    expect(inSidebar(find.text('Refresh')), findsNothing);
    expect(await store.read(SidebarController.storageKey), 'false');
  });

  testWidgets('starts extended when the stored flag says so', (tester) async {
    final store = InMemoryKeyValueStore();
    await store.write(SidebarController.storageKey, 'true');

    await pumpShell(tester, store: store);

    expect(sidebarWidth(tester), VaultSidebar.extendedWidth);
    expect(inSidebar(find.text('Refresh')), findsOneWidget);
  });

  testWidgets('hovering the sidebar does not change its width', (tester) async {
    await pumpShell(tester);
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

    await gesture.moveTo(
      tester.getCenter(inSidebar(find.byTooltip('Refresh'))),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(sidebarWidth(tester), VaultSidebar.collapsedWidth);
    // Still no labels (the hovered item's tooltip is not a label).
    expect(inSidebar(find.text('Cleanup')), findsNothing);
  });

  testWidgets('unwired footer items show the not-implemented snack bar', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(inSidebar(find.byTooltip('Help')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Not implemented yet'), findsOneWidget);
  });

  testWidgets('Download Workshop mods opens its dialog', (tester) async {
    await pumpShell(tester);

    await tester.tap(inSidebar(find.byTooltip('Download Workshop mods')));
    await tester.pumpAndSettle();

    expect(find.byType(DownloadWorkshopModsDialog), findsOneWidget);
    expect(
      find.text('Save to: ${shellDirectories.workshopDir}'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadWorkshopModsDialog), findsNothing);
  });

  testWidgets('Refresh asks for confirmation and passes the checkbox', (
    tester,
  ) async {
    final library = SpyLibraryController();
    await pumpShell(tester, library: library);

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
