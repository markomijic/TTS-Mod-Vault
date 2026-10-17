import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

/// True while a long-running operation (library refresh, download, URL
/// check, Workshop download, backup, cleanup, ...) is in progress; the
/// sidebar disables its items and the mod cards ignore clicks meanwhile.
///
/// A library refresh is not a runner operation, so this ORs the library
/// controller's loading flag with the [OperationRunner] state.
final operationRunningProvider = Provider<bool>(
  (ref) =>
      ref.watch(libraryControllerProvider.select((s) => s.isLoading)) ||
      ref.watch(operationRunnerProvider.select((s) => s.isRunning)),
);
