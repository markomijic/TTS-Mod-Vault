// Pumps the `AppShell` (sidebar + library page) with the library
// presentation fixtures and extra overrides, for the sidebar wiring tests
// of the Phase 4 actions (Cleanup, Import backups, Import JSON).

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

import '../../library/presentation/presentation_test_harness.dart';

/// Builds a container for the shell: the library page overrides (fixture
/// directories, in-memory store, no asset reads) serving [state], no GitHub
/// release check, plus [overrides].
ProviderContainer shellContainer(
  LibraryState state, {
  List<Override> overrides = const [],
}) => ProviderContainer.test(
  overrides: [
    ...libraryPageOverrides(library: () => SpyLibraryController(state)),
    checkForUpdatesOnStartProvider.overrideWithValue(false),
    ...overrides,
  ],
);

/// Pumps [AppShell] inside a themed, localised `MaterialApp` at desktop
/// size with the providers of [container] and lets the first frame settle.
Future<void> pumpShell(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  await tester.pumpAndSettle();
}

/// The collapsed sidebar item with tooltip [label].
Finder sidebarItem(String label) => find.descendant(
  of: find.byType(VaultSidebar),
  matching: find.byTooltip(label),
);

/// Taps the sidebar item [label] and lets the UI settle.
Future<void> tapSidebar(WidgetTester tester, String label) async {
  await tester.tap(sidebarItem(label));
  await tester.pumpAndSettle();
}
