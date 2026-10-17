import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/delayed_progress.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('shows nothing before the delay and the message after', (
    tester,
  ) async {
    await pump(tester, const DelayedProgressMessage(message: 'Loading'));

    expect(find.byType(ProgressMessage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Loading'), findsNothing);

    await tester.pump(
      libraryLoadingIndicatorDelay - const Duration(milliseconds: 1),
    );
    expect(find.byType(ProgressMessage), findsNothing);

    await tester.pump(const Duration(milliseconds: 2));
    expect(find.byType(ProgressMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
  });

  testWidgets('the default delay is 400 ms', (tester) async {
    expect(libraryLoadingIndicatorDelay, const Duration(milliseconds: 400));
  });

  testWidgets('a custom delay is honoured and the content can change while '
      'visible', (tester) async {
    await pump(
      tester,
      const DelayedProgressMessage(
        message: 'Scanning',
        delay: Duration(seconds: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(ProgressMessage), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Scanning'), findsOneWidget);

    // New message: stays visible, no second delay.
    await pump(
      tester,
      const DelayedProgressMessage(
        message: 'Parsing',
        value: 0.5,
        detail: '1 of 2',
        delay: Duration(seconds: 1),
      ),
    );
    expect(find.text('Parsing'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.5,
    );
  });

  testWidgets('a zero delay shows the message at once', (tester) async {
    await pump(
      tester,
      const DelayedProgressMessage(message: 'Now', delay: Duration.zero),
    );
    expect(find.text('Now'), findsOneWidget);
  });

  testWidgets('unmounting before the delay cancels the timer', (tester) async {
    await pump(tester, const DelayedProgressMessage(message: 'Loading'));
    await tester.pump(const Duration(milliseconds: 100));

    await pump(tester, const SizedBox.shrink());
    // Would fail with a pending timer if the effect did not cancel it.
    await tester.pump(libraryLoadingIndicatorDelay);
    expect(find.byType(ProgressMessage), findsNothing);
  });
}
