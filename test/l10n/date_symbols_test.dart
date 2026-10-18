import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;

/// The app never calls `initializeDateFormatting`: the material_ui localization
/// delegates load the `intl` date symbols of the locale they are built for.
/// If that ever stops being true, `formatModDate` would silently fall back to
/// English for every language, so pin it here.
void main() {
  testWidgets('the Material delegates make a locale formattable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: [Locale('en'), Locale('de')],
        home: SizedBox(),
      ),
    );
    await tester.pumpAndSettle();

    expect(DateFormat.localeExists('de'), isTrue);
    final date = DateTime(2024, 3, 5, 9, 15);
    expect(formatModDate('de', date), contains('Mär'));
  });
}
