// Shared fixtures for the mod dialog tests. `ModEditService` is a final
// class and cannot be faked, so the dialogs are driven against the real
// service: a temporary TTS library on disk, an in-memory database and the
// real library controller (see `library_test_harness.dart`).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

import '../../../images_viewer/themed_app.dart';
import '../../library_test_harness.dart';

/// A temp library plus a container indexing it.
final class DialogFixture {
  DialogFixture._(this.library, this.container);

  /// Creates the library and the container (the same wiring as
  /// `makeLibraryContainer`, plus [overrides]); both are torn down with the
  /// test.
  static DialogFixture create({List<Override> overrides = const []}) {
    final library = TempLibrary.create();
    addTearDown(library.delete);
    final db = AppDatabase(NativeDatabase.memory());
    final pool = WorkerPool(size: 2, debugName: 'dialog-test');
    final log = AppLog(store: LogStore());
    final container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workerPoolProvider.overrideWithValue(pool),
        appLogProvider.overrideWithValue(log),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        directoriesProvider.overrideWith(
          () => FixedDirectoriesController(library.directories),
        ),
        ...overrides,
      ],
    );
    addTearDown(() async {
      await pool.dispose();
      await db.close();
      await log.dispose();
    });
    return DialogFixture._(library, container);
  }

  /// The temporary TTS folders.
  final TempLibrary library;

  /// Container with the real library controller and edit service.
  final ProviderContainer container;

  /// Re-indexes the library (with real async, see [runUntil]) and returns
  /// the mod at [jsonPath].
  Future<Mod> indexed(WidgetTester tester, String jsonPath) async {
    final state = await tester.runAsync(() => refreshLibrary(container));
    return state!.modByPath(jsonPath)!;
  }

  /// The mod at [jsonPath] in the current state, or null when gone.
  Mod? current(String jsonPath) =>
      container.read(libraryControllerProvider).value?.modByPath(jsonPath);
}

/// Pumps a page with one "open" button that runs [open] inside
/// [fixture]'s container, taps it and lets the dialog settle.
Future<void> pumpAndOpenDialog(
  WidgetTester tester,
  DialogFixture fixture, {
  required Future<void> Function(BuildContext context, WidgetRef ref) open,
}) async {
  await pumpThemedApp(
    tester,
    container: fixture.container,
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: FilledButton(
            onPressed: () => open(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Runs [action] with real async enabled (the service does file IO and
/// uses the worker pool, which never complete under the widget tester's
/// fake async), pumps frames until [done] holds or [timeout] passes, then
/// lets the fake-async frame queue settle (route transitions).
Future<void> runUntil(
  WidgetTester tester,
  Future<void> Function() action,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  await tester.runAsync(() async {
    await action();
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // A duration is needed: without it the fake clock stands still and
      // route transitions (the dialog closing) never finish.
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: 'timed out waiting for the UI to settle');
  });
  await tester.pumpAndSettle();
}

/// Whether no [AlertDialog] is on screen.
bool noDialog() => find.byType(AlertDialog).evaluate().isEmpty;

/// The [TextField] whose label is [label].
Finder fieldLabelled(String label) => find.widgetWithText(TextField, label);

/// The current text of the field labelled [label].
String fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(fieldLabelled(label)).controller!.text;

/// Whether the [FilledButton] labelled [label] is enabled.
bool buttonEnabled(WidgetTester tester, String label) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, label))
    .enabled;
