/// Runs a zip task (writer or extractor) on a dedicated isolate that streams
/// per-entry progress back to the caller and honours a cooperative cancel.
///
/// `WorkerPool.run` returns one result per task and cannot report progress
/// while the task runs, and `package:archive` cannot append to a zip stream
/// across tasks (closing the encoder writes the central directory), so a
/// backup or an import of thousands of entries would show nothing for
/// minutes. This helper spawns one short-lived isolate per zip job, as v2's
/// `_backupIsolate` did, with a typed protocol: the isolate first sends a
/// command port, then a [ZipProgress] after every entry, then exactly one
/// done or failed message. Cancellation is requested through the command
/// port and polled by the task between entries; an entry that is being
/// compressed or inflated finishes first.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';

/// Progress of a zip task: [done] entries processed out of [total], and the
/// name of the entry that just finished (null for the initial snapshot).
final class ZipProgress {
  /// Creates a snapshot.
  const ZipProgress({required this.done, required this.total, this.entryName});

  /// Entries processed so far (written, extracted or skipped).
  final int done;

  /// Entries in total.
  final int total;

  /// Zip entry name just processed.
  final String? entryName;

  @override
  String toString() =>
      'ZipProgress($done/$total${entryName == null ? '' : ' $entryName'})';
}

/// Receives every [ZipProgress] a task reports.
typedef ZipProgressCallback = void Function(ZipProgress progress);

/// Polled by a task between entries; `true` asks it to stop.
typedef ZipCancelCheck = bool Function();

/// Signature of the core routines the isolate runs: a request in, a result
/// out, with optional progress and cancel hooks.
typedef ZipTaskBody<Q, R> = Future<R> Function(
  Q request, {
  ZipProgressCallback? onProgress,
  ZipCancelCheck? isCancelled,
});

/// Message handed to a zip isolate entry point.
final class ZipIsolateArgs<Q> {
  /// Creates the arguments.
  const ZipIsolateArgs(this.request, this.replyTo);

  /// The task's request.
  final Q request;

  /// Port the isolate reports through.
  final SendPort replyTo;
}

/// Raised on the caller's side when the isolate failed with an error that
/// could not be sent back as is; [message] is the error's description and
/// [remoteStackTrace] the trace captured in the isolate.
final class ZipIsolateException implements Exception {
  /// Creates the exception.
  const ZipIsolateException(this.message, {this.remoteStackTrace});

  /// Description of the error raised in the isolate.
  final String message;

  /// Stack trace captured in the isolate, when available.
  final String? remoteStackTrace;

  @override
  String toString() => 'ZipIsolateException: $message';
}

const _cancelCommand = 'cancel';

final class _ZipIsolateDone {
  const _ZipIsolateDone(this.result);

  final Object? result;
}

final class _ZipIsolateFailed {
  const _ZipIsolateFailed({
    required this.message,
    required this.cancelled,
    required this.stackTrace,
  });

  final String message;
  final bool cancelled;
  final String stackTrace;
}

/// The isolate side of the protocol: entry points call this with their
/// [args] and the core routine [body]. It publishes the command port,
/// forwards progress, runs the body and reports its result or failure.
///
/// An [OperationCancelledException] thrown by the body is reported as a
/// cancellation, every other error as a failure with its description.
Future<void> runZipIsolateBody<Q, R>(
  ZipIsolateArgs<Q> args,
  ZipTaskBody<Q, R> body,
) async {
  final commands = ReceivePort();
  var cancelled = false;
  commands.listen((message) {
    if (message == _cancelCommand) cancelled = true;
  });
  args.replyTo.send(commands.sendPort);
  try {
    final result = await body(
      args.request,
      onProgress: args.replyTo.send,
      isCancelled: () => cancelled,
    );
    args.replyTo.send(_ZipIsolateDone(result));
  } on OperationCancelledException catch (error, stackTrace) {
    args.replyTo.send(
      _ZipIsolateFailed(
        message: error.reason?.toString() ?? 'Cancelled',
        cancelled: true,
        stackTrace: stackTrace.toString(),
      ),
    );
  } catch (error, stackTrace) {
    args.replyTo.send(
      _ZipIsolateFailed(
        message: error.toString(),
        cancelled: false,
        stackTrace: stackTrace.toString(),
      ),
    );
  } finally {
    commands.close();
  }
}

/// Spawns an isolate running [entryPoint] (a top-level function that calls
/// [runZipIsolateBody]) with [request] and returns the task's result.
///
/// [onProgress] receives every progress message on the caller's isolate.
/// Cancelling [token] forwards a cancel request; the task stops after the
/// entry in flight and the returned future fails with
/// [OperationCancelledException]. Any other failure in the isolate surfaces
/// as [ZipIsolateException].
Future<R> runZipIsolate<Q, R>(
  void Function(ZipIsolateArgs<Q> args) entryPoint,
  Q request, {
  ZipProgressCallback? onProgress,
  CancellationToken? token,
  String debugName = 'zip-task',
}) async {
  token?.throwIfCancelled();
  final replies = ReceivePort();
  final exit = ReceivePort();
  final errors = ReceivePort();
  final completer = Completer<R>();
  SendPort? commands;
  var cancelRequested = false;

  void requestCancel() {
    cancelRequested = true;
    commands?.send(_cancelCommand);
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (!completer.isCompleted) completer.completeError(error, stackTrace);
  }

  replies.listen((message) {
    switch (message) {
      case SendPort():
        commands = message;
        if (cancelRequested) message.send(_cancelCommand);
      case ZipProgress():
        onProgress?.call(message);
      case _ZipIsolateDone(:final result):
        if (!completer.isCompleted) completer.complete(result as R);
      case _ZipIsolateFailed():
        fail(
          message.cancelled
              ? OperationCancelledException(message.message)
              : ZipIsolateException(
                  message.message,
                  remoteStackTrace: message.stackTrace,
                ),
          StackTrace.fromString(message.stackTrace),
        );
    }
  });
  exit.listen((_) {
    fail(const ZipIsolateException('Zip isolate exited without a result'));
  });
  errors.listen((message) {
    final parts = message is List ? message : const <Object?>[];
    fail(
      ZipIsolateException(
        parts.isNotEmpty ? '${parts[0]}' : 'Zip isolate failed',
        remoteStackTrace: parts.length > 1 ? '${parts[1]}' : null,
      ),
    );
  });

  final removeCancelListener = token?.onCancel((_) => requestCancel()) ?? () {};
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<ZipIsolateArgs<Q>>(
      entryPoint,
      ZipIsolateArgs<Q>(request, replies.sendPort),
      onExit: exit.sendPort,
      onError: errors.sendPort,
      debugName: debugName,
    );
    return await completer.future;
  } finally {
    removeCancelListener();
    replies.close();
    exit.close();
    errors.close();
    // The isolate exits on its own once the body returns; this only covers
    // a body that never reports (a bug), so no handle is left open.
    isolate?.kill();
  }
}
