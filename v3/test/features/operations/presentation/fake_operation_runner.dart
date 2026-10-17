// A runner double for widget tests: serves a fixed state and records
// `cancel` calls without running anything.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

/// Serves [initial] and flips `cancelRequested` on [cancel].
final class FakeOperationRunner extends OperationRunner {
  FakeOperationRunner([this.initial = OperationState.idle]);

  /// State returned by `build`.
  final OperationState initial;

  /// How often `cancel` was called.
  int cancelCalls = 0;

  @override
  OperationState build() => initial;

  /// Replaces the state (simulates a progress report).
  void publish(OperationState value) => state = value;

  @override
  void cancel() {
    cancelCalls++;
    if (!state.isRunning) return;
    state = state.copyWith(
      cancelRequested: true,
      progress: state.progress?.copyWith(cancelRequested: true),
    );
  }
}

/// A running state for [kind] with [progress].
OperationState runningState(OperationProgress progress) => OperationState(
  operationId: '${progress.kind.name}#test',
  kind: progress.kind,
  progress: progress,
);
