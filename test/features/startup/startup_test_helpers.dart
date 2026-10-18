// Test doubles expose counters and recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/app.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';

/// Platform name matching the host so `package:path` normalisation in the
/// rules agrees with the paths built here.
final String testPlatform = Platform.isWindows ? 'windows' : 'linux';

/// A fake home folder for [testPlatform].
final String testHome = Platform.isWindows
    ? r'C:\Users\tester'
    : '/home/tester';

/// The default TTS directories for [testPlatform] / [testHome].
final Directories testDefaults = defaultDirectories(
  platform: testPlatform,
  home: testHome,
  directoryExists: (_) => false,
);

/// A second TTS data folder the user "picks" in tests.
final String pickedTts = p.join(testHome, 'Games', 'Tabletop Simulator');

/// `pickedTts/Mods`.
final String pickedMods = p.join(pickedTts, 'Mods');

/// `pickedTts/Saves`.
final String pickedSaves = p.join(pickedTts, 'Saves');

/// `pickedTts/Backups`.
final String pickedBackups = p.join(pickedTts, 'Backups');

/// Library controller double: `refresh` completes immediately, or throws for
/// the first [failures] calls.
class FakeLibraryController extends LibraryController {
  FakeLibraryController({this.failures = 0});

  /// How many more `refresh` calls should throw.
  int failures;

  /// Number of `refresh` calls so far.
  int refreshCalls = 0;

  @override
  Future<LibraryState> build() async => LibraryState.empty;

  @override
  Future<void> refresh({bool clearCache = false}) async {
    refreshCalls++;
    if (failures > 0) {
      failures--;
      throw Exception('boom');
    }
  }
}

/// Startup controller double whose `build` returns the given states in
/// order (the last one repeats) and records `continueWithDirectories` calls.
class FixedStartupController extends StartupController {
  FixedStartupController(this.states) : assert(states.isNotEmpty, 'empty');

  /// States returned by successive builds.
  final List<StartupState> states;

  /// Arguments of every `continueWithDirectories` call.
  final List<Directories> continued = [];

  int _builds = 0;

  @override
  Future<StartupState> build() async {
    final index = _builds < states.length ? _builds : states.length - 1;
    _builds++;
    return states[index];
  }

  @override
  Future<void> continueWithDirectories(Directories picked) async {
    continued.add(picked);
  }
}

/// Picker double returning [results] in order (null = user cancelled).
class FakeDirectoryPicker implements DirectoryPicker {
  FakeDirectoryPicker(this.results);

  final List<String?> results;

  /// Dialog titles passed to each call.
  final List<String?> titles = [];

  /// Initial directories passed to each call.
  final List<String?> initialDirectories = [];

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    titles.add(dialogTitle);
    initialDirectories.add(initialDirectory);
    return results.isEmpty ? null : results.removeAt(0);
  }
}

/// The overrides every startup test needs.
List<Override> startupOverrides({
  required Set<String> existing,
  InMemoryKeyValueStore? store,
  LibraryController Function()? library,
}) => [
  keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
  appLogProvider.overrideWithValue(AppLog(store: LogStore())),
  platformNameProvider.overrideWithValue(testPlatform),
  userHomeProvider.overrideWithValue(testHome),
  directoryExistsProvider.overrideWithValue(existing.contains),
  libraryControllerProvider.overrideWith(library ?? FakeLibraryController.new),
];

/// Completes with the first startup state (current or future) that satisfies
/// [test].
Future<StartupState> waitForStartupState(
  ProviderContainer container,
  bool Function(StartupState state) test, {
  Duration timeout = const Duration(seconds: 5),
}) {
  final completer = Completer<StartupState>();
  final subscription = container.listen<AsyncValue<StartupState>>(
    startupControllerProvider,
    (previous, next) {
      final value = next.value;
      if (value != null && test(value) && !completer.isCompleted) {
        completer.complete(value);
      }
    },
    fireImmediately: true,
  );
  return completer.future.timeout(timeout).whenComplete(subscription.close);
}

/// Pumps the real [App] (theme, localisations, [StartupPage] home) with
/// [overrides] at a desktop window size.
Future<void> pumpStartupApp(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: overrides,
      child: const App(),
    ),
  );
  // Not pumpAndSettle: an indeterminate progress indicator never settles.
  // A few timed frames let the async store reads, the Checking state's
  // indicator delay, the AnimatedSwitcher and the sidebar animation finish.
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}
