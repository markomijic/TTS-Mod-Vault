import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/features/library/application/refresh_progress.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';
import 'package:tts_mod_vault/features/startup/presentation/select_directories_view.dart';

import 'startup_test_helpers.dart';

void main() {
  testWidgets('loading state shows the indeterminate progress message', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        startupControllerProvider.overrideWith(
          () => FixedStartupController(const [StartupLoading()]),
        ),
      ],
    );

    expect(find.byType(ProgressMessage), findsOneWidget);
    expect(find.text('Loading library…'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('loading state shows phase and counts from refresh progress', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        startupControllerProvider.overrideWith(
          () => FixedStartupController(const [StartupLoading()]),
        ),
        refreshProgressProvider.overrideWithValue(
          const RefreshProgress(
            phase: LibraryRefreshPhase.parsing,
            done: 12,
            total: 99,
          ),
        ),
      ],
    );

    final progress = tester.widget<ProgressMessage>(
      find.byType(ProgressMessage),
    );
    expect(progress.value, closeTo(12 / 99, 0.0001));
    expect(find.text('12 of 99'), findsOneWidget);
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
    expect(find.byType(ProgressMessage), findsNothing);
  });

  testWidgets('real controller: existing folders end in the shell', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: startupOverrides(
        existing: {testDefaults.modsDir, testDefaults.savesDir},
      ),
    );

    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('real controller: missing folders show the selection view', (
    tester,
  ) async {
    await pumpStartupApp(
      tester,
      overrides: startupOverrides(existing: {testDefaults.modsDir}),
    );

    expect(find.byType(SelectDirectoriesView), findsOneWidget);
  });
}
