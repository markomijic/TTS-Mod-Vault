// Minimal themed, localised app for widget tests of pages and dialogs that
// do not need the full Mods page.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Pumps [home] inside a themed, localised `MaterialApp` at a desktop
/// window size and lets the first frame settle. Uses [container] when given,
/// otherwise a fresh test container with [overrides]. Returns the container
/// so tests can read providers.
Future<ProviderContainer> pumpThemedApp(
  WidgetTester tester, {
  required Widget home,
  ProviderContainer? container,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scope = container ?? ProviderContainer.test(overrides: overrides);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: AppTheme.build(settings, Brightness.light),
        darkTheme: AppTheme.build(settings, Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scope;
}
