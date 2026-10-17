/// The operation abstraction of plan section 4.5: a unit of long-running,
/// cancellable work (downloads, URL checks, backups, Workshop updates) that
/// reports progress through an [OperationContext] and is executed by the
/// `OperationRunner`, one at a time.
library;

import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';

/// What kind of work an [Operation] does; drives the log source and lets the
/// UI pick icons and labels.
enum OperationKind {
  /// Download missing asset files of a mod.
  downloadAssets,

  /// Check whether a mod's asset URLs are still live.
  checkUrls,

  /// Download Workshop mods by id.
  downloadWorkshop,

  /// Re-download Workshop mods that have a newer version on Steam.
  updateWorkshop,

  /// Create `.ttsmod` backups.
  backup,

  /// Import `.ttsmod` backups.
  importBackup,

  /// Orphaned-asset cleanup.
  cleanup,

  /// Delete cached asset files.
  deleteAssets,

  /// Rewrite asset URLs in mod files.
  updateUrls,

  /// A composite of several per-mod operations.
  bulk;

  /// The log source entries of this kind are filed under.
  LogSource get logSource => switch (this) {
    OperationKind.downloadAssets => LogSource.download,
    OperationKind.checkUrls => LogSource.urlCheck,
    OperationKind.downloadWorkshop ||
    OperationKind.updateWorkshop => LogSource.workshop,
    OperationKind.backup => LogSource.backup,
    OperationKind.importBackup => LogSource.import,
    OperationKind.cleanup || OperationKind.deleteAssets => LogSource.cleanup,
    OperationKind.updateUrls || OperationKind.bulk => LogSource.library,
  };
}

/// A progress snapshot published by an operation.
///
/// [label] is a machine key the UI maps to a localised string (for example
/// `downloading.images`, `checking.urls`, `workshop.downloading`); [detail]
/// is free text shown as-is (a URL, a mod name). [fraction] is the overall
/// completion in `0..1` when known, otherwise `done / total` is used; a
/// progress with `total == 0` and no fraction is indeterminate.
final class OperationProgress {
  /// Creates a snapshot.
  const OperationProgress({
    required this.kind,
    required this.label,
    this.done = 0,
    this.total = 0,
    this.fraction,
    this.cancelRequested = false,
    this.detail,
  });

  /// Kind of the operation reporting.
  final OperationKind kind;

  /// Label key for the UI.
  final String label;

  /// Items completed so far.
  final int done;

  /// Items in total (0 when unknown).
  final int total;

  /// Overall completion in `0..1`, when finer than [done] / [total].
  final double? fraction;

  /// Whether the user asked for cancellation and the operation is winding
  /// down.
  final bool cancelRequested;

  /// Free-text detail (a URL, a mod name).
  final String? detail;

  /// The completion to show: [fraction] when given, else `done / total`,
  /// else `null` (indeterminate).
  double? get value {
    final fraction = this.fraction;
    if (fraction != null) return fraction.clamp(0.0, 1.0);
    if (total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  /// Copy with some fields replaced.
  OperationProgress copyWith({
    OperationKind? kind,
    String? label,
    int? done,
    int? total,
    double? fraction,
    bool? cancelRequested,
    String? detail,
  }) => OperationProgress(
    kind: kind ?? this.kind,
    label: label ?? this.label,
    done: done ?? this.done,
    total: total ?? this.total,
    fraction: fraction ?? this.fraction,
    cancelRequested: cancelRequested ?? this.cancelRequested,
    detail: detail ?? this.detail,
  );

  @override
  bool operator ==(Object other) =>
      other is OperationProgress &&
      other.kind == kind &&
      other.label == label &&
      other.done == done &&
      other.total == total &&
      other.fraction == fraction &&
      other.cancelRequested == cancelRequested &&
      other.detail == detail;

  @override
  int get hashCode =>
      Object.hash(kind, label, done, total, fraction, cancelRequested, detail);

  @override
  String toString() =>
      'OperationProgress(${kind.name} $label $done/$total'
      '${fraction == null ? '' : ' ${(fraction! * 100).toStringAsFixed(0)}%'}'
      '${cancelRequested ? ' cancelRequested' : ''}'
      '${detail == null ? '' : ' $detail'})';
}

/// What an [Operation] gets from the runner: the cancellation token, the log,
/// its id and a progress sink.
final class OperationContext {
  /// Creates a context. [onProgress] receives every [report].
  OperationContext({
    required this.token,
    required this.log,
    required this.operationId,
    required this.onProgress,
  });

  /// Cancellation signal; forwarded to Dio cancel tokens and worker tasks.
  final CancellationToken token;

  /// The application log; entries should carry [operationId].
  final AppLog log;

  /// Identifier of this run, for log correlation.
  final String operationId;

  /// Sink that receives every [report]; the runner's state update.
  final void Function(OperationProgress progress) onProgress;

  /// Publishes a progress snapshot.
  void report(OperationProgress progress) => onProgress(progress);

  /// Throws [OperationCancelledException] when [token] is cancelled.
  void checkCancelled() => token.throwIfCancelled();

  /// Whether cancellation was requested.
  bool get isCancelled => token.isCancelled;
}

int _nextOperationNumber = 0;

/// Produces a unique operation id: `<kind>#<n>`.
String newOperationId(OperationKind kind) =>
    '${kind.name}#${++_nextOperationNumber}';

/// A unit of cancellable work with a typed result.
///
/// Implementations do all their IO in [run], check `ctx.token` at await
/// boundaries, report progress through `ctx.report` and log through
/// `ctx.log`. Bulk operations compose per-mod operations by calling their
/// [run] with the same context.
abstract class Operation<T> {
  /// Creates the operation.
  Operation();

  /// Unique id of this operation instance (assigned lazily from [kind]).
  late final String id = newOperationId(kind);

  /// What this operation does.
  OperationKind get kind;

  /// Performs the work.
  Future<T> run(OperationContext ctx);

  /// The result to return when [run] threw [OperationCancelledException],
  /// for operations whose result model can express cancellation. The
  /// default `null` makes the runner rethrow the exception.
  T? cancelledResult() => null;
}
