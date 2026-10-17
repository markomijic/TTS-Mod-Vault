import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/app.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';
import 'package:tts_mod_vault/features/startup/presentation/select_directories_view.dart';
import 'package:tts_mod_vault/features/startup/presentation/startup_page.dart';

import 'startup_test_helpers.dart';

void main() {
  testWidgets('checking state is blank at first and shows the indicator '
      'only after the delay', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          ...startupOverrides(existing: const {}),
          startupControllerProvider.overrideWith(
            () => FixedStartupController(const [StartupChecking()]),
          ),
        ],
        child: const App(),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(ProgressMessage), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AppShell), findsNothing);

    await tester.pump(
      startupCheckingIndicatorDelay - const Duration(milliseconds: 50),
    );
    expect(find.byType(ProgressMessage), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ProgressMessage), findsOneWidget);
    expect(find.text('Checking folders…'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('needs-directories state shows the folder selection view', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        startupControllerProvider.overrideWith(
          () => FixedStartupController(const [
            StartupNeedsDirectories(
              modsDirExists: false,
              savesDirExists: false,
            ),
          ]),
        ),
      ],
    );

    expect(find.byType(SelectDirectoriesView), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('failed state shows the error and Retry re-runs the controller', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        startupControllerProvider.overrideWith(
          () => FixedStartupController([
            StartupFailed(Exception('boom'), StackTrace.empty),
            const StartupReady(),
          ]),
        ),
      ],
    );

    expect(find.byType(ErrorMessage), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(ErrorMessage), findsNothing);
  });

  testWidgets('ready state shows the app shell', (tester) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        startupControllerProvider.overrideWith(
          () => FixedStartupController(const [StartupReady()]),
        ),
      ],
    );

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(ErrorMessage), findsNothing);
    expect(find.byType(SelectDirectoriesView), findsNothing);
  });

  testWidgets('real controller: existing folders show the shell on the '
      'first frame after the check', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: startupOverrides(
          existing: {testDefaults.modsDir, testDefaults.savesDir},
        ),
        child: const App(),
      ),
    );
    // The store read and the folder check are microtasks; one frame later
    // the shell is already building, well inside the indicator delay.
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(ProgressMessage), findsNothing);

    // Let the sidebar animation finish so no timers are left pending.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('real controller: missing folders show the selection view', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: startupOverrides(existing: {testDefaults.modsDir}),
    );

    expect(find.byType(SelectDirectoriesView), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
