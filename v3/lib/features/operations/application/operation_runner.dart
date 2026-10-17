/// The single [OperationRunner] of plan section 4.5: owns "is anything
/// running", the current progress and the one cancellation token.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';

export 'package:tts_mod_vault/features/operations/application/operation.dart';

/// What the runner is doing right now.
final class OperationState {
  /// Creates a state. [operationId] and [kind] are set while an operation
  /// runs; [progress] is its latest report (null before the first one).
  const OperationState({
    this.operationId,
    this.kind,
    this.progress,
    this.cancelRequested = false,
  });

  /// Nothing running.
  static const OperationState idle = OperationState();

  /// Id of the running operation, or null.
  final String? operationId;

  /// Kind of the running operation, or null.
  final OperationKind? kind;

  /// Latest progress report of the running operation, or null.
  final OperationProgress? progress;

  /// Whether [OperationRunner.cancel] was called for the running operation.
  final bool cancelRequested;

  /// Whether an operation is running.
  bool get isRunning => operationId != null;

  /// Copy with some fields replaced.
  OperationState copyWith({
    String? operationId,
    OperationKind? kind,
    OperationProgress? progress,
    bool? cancelRequested,
  }) => OperationState(
    operationId: operationId ?? this.operationId,
    kind: kind ?? this.kind,
    progress: progress ?? this.progress,
    cancelRequested: cancelRequested ?? this.cancelRequested,
  );

  @override
  bool operator ==(Object other) =>
      other is OperationState &&
      other.operationId == operationId &&
      other.kind == kind &&
      other.progress == progress &&
      other.cancelRequested == cancelRequested;

  @override
  int get hashCode => Object.hash(operationId, kind, progress, cancelRequested);

  @override
  String toString() => isRunning
      ? 'OperationState($operationId, $progress'
            '${cancelRequested ? ', cancelRequested' : ''})'
      : 'OperationState.idle';
}

/// Runs one [Operation] at a time and publishes its progress.
final operationRunnerProvider =
    NotifierProvider<OperationRunner, OperationState>(OperationRunner.new);

/// Whether the runner has an operation in flight. The shell's
/// `operationRunningProvider` ORs this with the library refresh.
final anyOperationRunningProvider = Provider<bool>(
  (ref) => ref.watch(operationRunnerProvider.select((s) => s.isRunning)),
);

/// Executes operations sequentially: [run] rejects a second operation while
/// one is in flight, gives each run a fresh [CancellationToken], logs
/// start / finish / cancellation / failure under the kind's log source with
/// the operation id, and always returns to [OperationState.idle].
class OperationRunner extends Notifier<OperationState> {
  CancellationToken? _token;
  String? _runningId;

  @override
  OperationState build() => OperationState.idle;

  /// Runs [op] and returns its result.
  ///
  /// Throws [StateError] when another operation is running. An
  /// [OperationCancelledException] thrown by the operation is turned into
  /// `op.cancelledResult()` when that is non-null, otherwise rethrown; any
  /// other error is logged and rethrown. The state is cleared in every case.
  Future<T> run<T>(Operation<T> op) async {
    if (_runningId != null) {
      throw StateError('An operation is already running');
    }
    final log = ref.read(appLogProvider);
    final token = CancellationToken();
    final id = op.id;
    final source = op.kind.logSource;
    _token = token;
    _runningId = id;
    state = OperationState(operationId: id, kind: op.kind);
    final stopwatch = Stopwatch()..start();
    log.info(source, 'Started ${op.kind.name}', operationId: id);

    final ctx = OperationContext(
      token: token,
      log: log,
      operationId: id,
      onProgress: (progress) {
        if (!ref.mounted || _runningId != id) return;
        state = state.copyWith(
          progress: progress.copyWith(
            cancelRequested: progress.cancelRequested || token.isCancelled,
          ),
        );
      },
    );

    try {
      final result = await op.run(ctx);
      log.info(
        source,
        'Finished ${op.kind.name}'
        '${token.isCancelled ? ' (cancelled)' : ''} '
        'in ${stopwatch.elapsedMilliseconds} ms',
        operationId: id,
      );
      return result;
    } on OperationCancelledException {
      log.warning(
        source,
        'Cancelled ${op.kind.name} after ${stopwatch.elapsedMilliseconds} ms',
        operationId: id,
      );
      final fallback = op.cancelledResult();
      if (fallback != null) return fallback;
      rethrow;
    } catch (error, stackTrace) {
      log.error(
        source,
        'Failed ${op.kind.name} after ${stopwatch.elapsedMilliseconds} ms',
        error: error,
        stackTrace: stackTrace,
        operationId: id,
      );
      rethrow;
    } finally {
      if (_runningId == id) {
        _runningId = null;
        _token = null;
        if (ref.mounted) state = OperationState.idle;
      }
    }
  }

  /// Requests cancellation of the running operation (no-op when idle). The
  /// operation finishes on its own once it notices the token.
  void cancel() {
    final token = _token;
    if (token == null) return;
    token.cancel('Cancelled by user');
    if (!ref.mounted || !state.isRunning) return;
    state = state.copyWith(
      cancelRequested: true,
      progress: state.progress?.copyWith(cancelRequested: true),
    );
  }
}
