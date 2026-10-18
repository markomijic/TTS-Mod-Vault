import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';

/// A persistent pool of long-lived isolates for CPU-bound work (JSON
/// parsing, hashing, zip reading, image decoding) that must not block the UI
/// isolate.
///
/// Compared with `Isolate.run` per call, the isolates are spawned once and
/// reused, which matters when thousands of small tasks are scheduled during
/// a library refresh.
///
/// Usage:
/// ```dart
/// final pool = WorkerPool();
/// await pool.start();
/// final parsed = await pool.run(parseModJson, modPath, token: token);
/// await pool.dispose();
/// ```
///
/// Rules for tasks:
/// * [run] sends the task function itself to the worker isolate, so it must
///   be a **top-level or static function**, never a closure capturing state.
///   The argument and the result must be sendable between isolates
///   (primitives, collections of them, plain objects without closures or
///   platform handles).
/// * Each worker executes one request at a time; requests are dispatched
///   FIFO to the first idle worker. A task scheduled on a single-worker pool
///   therefore completes in submission order.
/// * Cancellation is cooperative: a cancelled task that is still queued fails
///   immediately with [OperationCancelledException]. **A task that is already
///   running on a worker cannot be interrupted**; its result is discarded
///   when it finishes and the returned future has already failed. Pass the
///   token into the task argument if the task itself can check it.
/// * Errors thrown by a task are rethrown to the caller as the original error
///   type when that error object can be sent between isolates; otherwise the
///   caller receives a [RemoteError] whose description is the error's
///   `toString()`.
final class WorkerPool {
  /// Creates a pool with [size] workers (default: processor count minus two,
  /// at least two). No isolate is spawned until [start] or the first [run].
  WorkerPool({int? size, this.debugName = 'worker'})
    : size = size ?? max(Platform.numberOfProcessors - 2, 2) {
    if (this.size < 1) {
      throw ArgumentError.value(size, 'size', 'must be at least 1');
    }
  }

  /// Number of worker isolates in the pool.
  final int size;

  /// Prefix for the isolates' debug names (`<debugName>-<index>`).
  final String debugName;
  final List<_Worker> _workers = [];
  final Queue<_Job<Object?>> _queue = Queue();
  Future<void>? _starting;
  bool _disposed = false;
  int _nextWorkerIndex = 0;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Number of tasks waiting for a free worker.
  int get queuedTaskCount => _queue.length;

  /// Number of tasks currently executing on a worker.
  int get runningTaskCount => _workers.where((w) => w.current != null).length;

  /// Spawns the worker isolates. Safe to call more than once; [run] calls it
  /// implicitly if needed.
  Future<void> start() {
    _checkNotDisposed();
    return _starting ??= _spawnAll();
  }

  Future<void> _spawnAll() async {
    final spawned = await Future.wait(
      List.generate(size, (_) => _spawnWorker()),
    );
    if (_disposed) {
      for (final worker in spawned) {
        worker.kill();
      }
      return;
    }
    _workers.addAll(spawned);
    _pump();
  }

  Future<_Worker> _spawnWorker() async {
    final index = _nextWorkerIndex++;
    final worker = _Worker(onResponse: _onResponse, onExit: _onWorkerExit);
    await worker.spawn('$debugName-$index');
    return worker;
  }

  /// Executes `task(arg)` on a worker isolate and returns its result.
  ///
  /// [task] must be a top-level or static function (see class docs). When
  /// [token] is cancelled while the task is still queued, the future fails
  /// with [OperationCancelledException]; a running task is left to finish.
  Future<R> run<A, R>(
    FutureOr<R> Function(A arg) task,
    A arg, {
    CancellationToken? token,
  }) {
    _checkNotDisposed();
    if (token != null && token.isCancelled) {
      return Future<R>.error(
        OperationCancelledException(token.cancelReason),
        StackTrace.current,
      );
    }
    final job = _Job<R>(task, arg);
    _queue.add(job);
    if (token != null) {
      final remove = token.onCancel((reason) {
        if (job.state == _JobState.queued) {
          _queue.remove(job);
          job.fail(OperationCancelledException(reason), StackTrace.current);
        }
      });
      job.completer.future.whenComplete(remove).ignore();
    }
    if (_starting == null) {
      // Lazily spawn the isolates; any spawn error fails the queued jobs.
      start().catchError(_failQueued);
    } else {
      _pump();
    }
    return job.completer.future;
  }

  /// Runs [task] for every element of [args] and returns the results in the
  /// same order.
  ///
  /// At most [maxConcurrency] tasks are queued or running at once (default:
  /// the pool [size]), so a very long list does not flood the queue. If any
  /// task fails, the remaining queued tasks are cancelled and the returned
  /// future fails with the first error; tasks already running finish on
  /// their own. [token] cancels the whole batch.
  Future<List<R>> runAll<A, R>(
    FutureOr<R> Function(A arg) task,
    List<A> args, {
    CancellationToken? token,
    int? maxConcurrency,
  }) async {
    if (args.isEmpty) {
      return <R>[];
    }
    final concurrency = max(1, min(maxConcurrency ?? size, args.length));
    final batchToken = token == null
        ? CancellationToken()
        : CancellationToken.linked(token);
    final results = List<R?>.filled(args.length, null);
    Object? firstError;
    StackTrace? firstStackTrace;
    var nextIndex = 0;

    Future<void> drain() async {
      while (nextIndex < args.length && firstError == null) {
        final index = nextIndex++;
        try {
          results[index] = await run(task, args[index], token: batchToken);
        } catch (error, stackTrace) {
          if (firstError == null) {
            firstError = error;
            firstStackTrace = stackTrace;
            batchToken.cancel('batch failed');
          }
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => drain()));
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
    return List<R>.generate(args.length, (i) => results[i] as R);
  }

  /// Shuts the pool down: queued tasks fail with
  /// [OperationCancelledException], worker isolates are killed immediately
  /// and the tasks they were running fail the same way. Calling it again is a
  /// no-op; [run] and [start] throw [StateError] afterwards.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _failQueued(
      const OperationCancelledException('WorkerPool disposed'),
      StackTrace.current,
    );
    for (final worker in _workers) {
      worker.current?.fail(
        const OperationCancelledException('WorkerPool disposed'),
        StackTrace.current,
      );
      worker.current = null;
      worker.kill();
    }
    _workers.clear();
    // Let an in-progress start() settle so its isolates get killed too.
    final starting = _starting;
    if (starting != null) {
      await starting.catchError((_) {});
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('WorkerPool has been disposed');
    }
  }

  void _failQueued(Object error, StackTrace stackTrace) {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().fail(error, stackTrace);
    }
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    for (final worker in _workers) {
      if (_queue.isEmpty) {
        return;
      }
      if (worker.current == null) {
        worker.dispatch(_queue.removeFirst());
      }
    }
  }

  void _onResponse(_Worker worker, _Response response) {
    final job = worker.current;
    worker.current = null;
    if (job != null && job.id == response.id) {
      if (response.isError) {
        job.fail(
          response.error!,
          response.stackTrace == null
              ? StackTrace.empty
              : StackTrace.fromString(response.stackTrace!),
        );
      } else {
        job.complete(response.result);
      }
    }
    _pump();
  }

  void _onWorkerExit(_Worker worker) {
    if (_disposed || !_workers.remove(worker)) {
      return;
    }
    final job = worker.current;
    worker.current = null;
    job?.fail(
      RemoteError('Worker isolate exited unexpectedly', ''),
      StackTrace.current,
    );
    // Keep the pool at full strength.
    _spawnWorker()
        .then((replacement) {
          if (_disposed) {
            replacement.kill();
            return;
          }
          _workers.add(replacement);
          _pump();
        })
        .catchError(_failQueued);
  }
}

enum _JobState { queued, running, done }

final class _Job<R> {
  _Job(this.task, this.arg) : id = _nextId++;

  static int _nextId = 0;

  final int id;
  final Function task;
  final Object? arg;
  final Completer<R> completer = Completer<R>();
  _JobState state = _JobState.queued;

  void complete(Object? value) {
    if (state == _JobState.done) {
      return;
    }
    state = _JobState.done;
    completer.complete(value as R);
  }

  void fail(Object error, StackTrace stackTrace) {
    if (state == _JobState.done) {
      return;
    }
    state = _JobState.done;
    completer.completeError(error, stackTrace);
  }
}

final class _Worker {
  _Worker({required this.onResponse, required this.onExit});

  final void Function(_Worker worker, _Response response) onResponse;
  final void Function(_Worker worker) onExit;

  final ReceivePort _receivePort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  late final StreamSubscription<Object?> _subscription;
  late final StreamSubscription<Object?> _exitSubscription;
  Isolate? _isolate;
  SendPort? _sendPort;
  bool _killed = false;

  _Job<Object?>? current;

  Future<void> spawn(String debugName) async {
    final handshake = Completer<SendPort>();
    _subscription = _receivePort.listen((message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) {
          handshake.complete(message);
        }
      } else if (message is _Response) {
        onResponse(this, message);
      }
    });
    _exitSubscription = _exitPort.listen((_) {
      if (!_killed) {
        _killed = true;
        _closePorts();
        onExit(this);
      }
    });
    try {
      _isolate = await Isolate.spawn<SendPort>(
        _workerMain,
        _receivePort.sendPort,
        debugName: debugName,
        errorsAreFatal: false,
        onExit: _exitPort.sendPort,
      );
      _sendPort = await handshake.future;
    } catch (_) {
      kill();
      rethrow;
    }
  }

  void dispatch(_Job<Object?> job) {
    current = job;
    job.state = _JobState.running;
    try {
      _sendPort!.send(_Request(job.id, job.task, job.arg));
    } catch (error, stackTrace) {
      // Task function or argument is not sendable (closure, native handle).
      current = null;
      job.fail(
        ArgumentError(
          'WorkerPool.run: the task function and its argument must be '
          'sendable between isolates (use a top-level or static function '
          'and plain data). Underlying error: $error',
        ),
        stackTrace,
      );
    }
  }

  void kill() {
    if (_killed) {
      return;
    }
    _killed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _closePorts();
  }

  void _closePorts() {
    _subscription.cancel().ignore();
    _exitSubscription.cancel().ignore();
    _receivePort.close();
    _exitPort.close();
  }
}

final class _Request {
  const _Request(this.id, this.task, this.arg);

  final int id;
  final Function task;
  final Object? arg;
}

final class _Response {
  const _Response.ok(this.id, this.result)
    : error = null,
      stackTrace = null,
      isError = false;

  const _Response.failed(this.id, this.error, this.stackTrace)
    : result = null,
      isError = true;

  final int id;
  final Object? result;
  final Object? error;
  final String? stackTrace;
  final bool isError;
}

/// Entry point of each worker isolate: answers every [_Request] with exactly
/// one [_Response].
Future<void> _workerMain(SendPort replyTo) async {
  final port = ReceivePort();
  replyTo.send(port.sendPort);
  await for (final message in port) {
    if (message is! _Request) {
      continue;
    }
    _Response response;
    try {
      final dynamic pending = Function.apply(message.task, [message.arg]);
      final Object? result = await pending;
      response = _Response.ok(message.id, result);
    } catch (error, stackTrace) {
      response = _Response.failed(message.id, error, stackTrace.toString());
    }
    try {
      replyTo.send(response);
    } catch (sendError, sendStackTrace) {
      // Result or error object is not sendable: fall back to a description.
      final description = response.isError
          ? response.error.toString()
          : 'Task result of type ${response.result.runtimeType} cannot be '
                'sent between isolates: $sendError';
      replyTo.send(
        _Response.failed(
          message.id,
          RemoteError(
            description,
            response.isError
                ? (response.stackTrace ?? '')
                : sendStackTrace.toString(),
          ),
          response.stackTrace ?? sendStackTrace.toString(),
        ),
      );
    }
  }
}
