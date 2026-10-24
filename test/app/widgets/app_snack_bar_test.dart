import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';

void main() {
  Future<void> openDialogAndSnack(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: snackBarsAboveRoutes,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  content: TextButton(
                    onPressed: () => showAppSnackBar(dialogContext, 'Oops'),
                    child: const Text('Fail'),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fail'));
    await tester.pumpAndSettle();
  }

  testWidgets('a snack bar shown from a dialog paints above the dialog', (
    tester,
  ) async {
    await openDialogAndSnack(tester);

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    // Hit-testable means nothing (the dialog's barrier) is painted over it.
    expect(snackBar.hitTestable(), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('the snack bar outlives the dialog it was shown from', (
    tester,
  ) async {
    await openDialogAndSnack(tester);
    Navigator.of(tester.element(find.text('Fail'))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Oops'), findsOneWidget);
  });
}
