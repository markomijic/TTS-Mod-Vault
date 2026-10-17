/// The shared shape of every multi-mod operation (plan Phase 5): iterate
/// the selected mods, run one inner per-mod operation for each with the
/// same token and log, publish one `bulk.<kind>` progress bar, collect the
/// per-mod outcomes and stop at the next mod boundary when cancelled.
/// Bulk operations never touch the selection.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';

/// What a bulk backup does with a mod that already has a backup
/// (v2 `BulkBackupBehaviorEnum`).
enum BulkBackupBehavior {
  /// Leave the existing backup alone.
  skip,

  /// Write a new archive into the existing backup's folder.
  replace,

  /// Replace only when the existing backup is out of date.
  replaceIfOutOfDate,
}

/// The outcome of one mod inside a bulk operation: the inner operation's
/// [value], or the [error] text when it threw.
final class BulkModOutcome<R> {
  /// Creates an outcome.
  const BulkModOutcome({required this.mod, this.value, this.error});

  /// The mod as it was when its turn came.
  final Mod mod;

  /// The inner result, or null when the step failed.
  final R? value;

  /// Why the step failed, or null.
  final String? error;

  /// Whether the step threw.
  bool get failed => error != null;

  @override
  String toString() => 'BulkModOutcome(${mod.displayName}: ${error ?? value})';
}

/// Base of the per-mod bulk operations.
///
/// Subclasses implement [processMod] (one mod, using the child context
/// they are given so inner progress and cancel checks flow through) and
/// [assemble] (the typed result from [outcomes]). [run] reports
/// `bulk.<bulkKindName>` progress with `done` / `total` mods and the mod's
/// name as detail, re-mapping inner progress into the same bar as a
/// fraction. Between mods the token is checked; a cancelled token stops the
/// loop after the current inner step finishes. A failing inner step is
/// logged with the mod's context and recorded; the loop goes on.
abstract class BulkOperation<R, T> extends Operation<T> {
  /// Creates the operation over [mods].
  BulkOperation({required this.ref, required this.mods});

  /// Supplies the inner operations' collaborators.
  final Ref ref;

  /// The mods to process, in order.
  final List<Mod> mods;

  /// Name used in the progress label (`bulk.<bulkKindName>`) and log lines.
  String get bulkKindName;

  /// The progress label key.
  String get progressLabel => 'bulk.$bulkKindName';

  /// Per-mod outcomes so far, in order.
  @protected
  final List<BulkModOutcome<R>> outcomes = [];

  bool _cancelled = false;

  /// Whether the run was stopped by cancellation.
  bool get wasCancelled => _cancelled;

  @override
  OperationKind get kind => OperationKind.bulk;

  /// Runs the inner step for [mod]. [ctx] is the child context; inner
  /// operations are run with it (`inner.run(ctx)`).
  @protected
  Future<R> processMod(OperationContext ctx, Mod mod);

  /// Builds the typed result from [outcomes].
  @protected
  T assemble({required bool cancelled});

  /// Whether the loop must stop after a step that returned [value] (for
  /// inner operations that report cancellation inside their result instead
  /// of throwing). The token is checked in any case.
  @protected
  bool stopAfter(R value) => false;

  /// Hook run once after the loop, before [assemble] (for example to persist
  /// a chosen folder). Errors here are logged and do not fail the run.
  @protected
  Future<void> finish(OperationContext ctx, {required bool cancelled}) async {}

  /// One-line summary for the log once [result] is assembled.
  @protected
  String summaryMessage(T result);

  @override
  T? cancelledResult() => assemble(cancelled: true);

  /// [mod] as the library state has it now (earlier steps may have changed
  /// its summary or backup), falling back to [mod].
  @protected
  Mod currentMod(Mod mod) =>
      ref.read(libraryControllerProvider).value?.modByPath(mod.jsonPath) ?? mod;

  @override
  Future<T> run(OperationContext ctx) async {
    final log = ctx.log;
    final source = kind.logSource;
    final total = mods.length;
    log.info(
      source,
      'Starting bulk $bulkKindName for $total mod(s)',
      operationId: ctx.operationId,
    );
    for (var i = 0; i < total; i++) {
      if (ctx.isCancelled) {
        _cancelled = true;
        break;
      }
      final mod = mods[i];
      final name = mod.displayName;
      ctx.report(
        OperationProgress(
          kind: kind,
          label: progressLabel,
          done: i,
          total: total,
          fraction: i / total,
          detail: name,
        ),
      );
      final child = OperationContext(
        token: ctx.token,
        log: ctx.log,
        operationId: ctx.operationId,
        onProgress: (inner) => ctx.report(
          OperationProgress(
            kind: kind,
            label: progressLabel,
            done: i,
            total: total,
            fraction: (i + (inner.value ?? 0)) / total,
            detail: inner.detail ?? name,
          ),
        ),
      );
      try {
        final value = await processMod(child, mod);
        outcomes.add(BulkModOutcome<R>(mod: mod, value: value));
        if (stopAfter(value) || ctx.isCancelled) {
          _cancelled = true;
          break;
        }
      } on OperationCancelledException {
        _cancelled = true;
        break;
      } on Object catch (error) {
        // The inner operation already logged the failure with its own
        // context and stack; record it and move on to the next mod.
        outcomes.add(BulkModOutcome<R>(mod: mod, error: error.toString()));
        log.warning(
          source,
          'Bulk $bulkKindName: skipped "$name" after a failure',
          details: error.toString(),
          modPath: mod.jsonPath,
          operationId: ctx.operationId,
        );
      }
    }
    ctx.report(
      OperationProgress(
        kind: kind,
        label: progressLabel,
        done: outcomes.length,
        total: total,
        fraction: total == 0 ? 1 : outcomes.length / total,
        cancelRequested: _cancelled,
      ),
    );
    try {
      await finish(ctx, cancelled: _cancelled);
    } on Object catch (error, stackTrace) {
      log.error(
        source,
        'Bulk $bulkKindName: the final step failed',
        error: error,
        stackTrace: stackTrace,
        operationId: ctx.operationId,
      );
    }
    final result = assemble(cancelled: _cancelled);
    final failed = outcomes.where((o) => o.failed).length;
    final message =
        '${summaryMessage(result)}'
        '${failed == 0 ? '' : ', $failed mod(s) failed'}'
        '${_cancelled ? ' (cancelled after ${outcomes.length}/$total)' : ''}';
    if (_cancelled || failed > 0) {
      log.warning(source, message, operationId: ctx.operationId);
    } else {
      log.success(source, message, operationId: ctx.operationId);
    }
    return result;
  }
}
