import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';

// Tasks must be top-level functions so they can be sent to a worker isolate.

int square(int value) => value * value;

Future<int> sleepThenReturn(int millis) async {
  await Future<void>.delayed(Duration(milliseconds: millis));
  return millis;
}

int throwFormat(String message) => throw FormatException(message);

int throwState(int code) => throw StateError('state $code');

/// Error object that cannot be sent between isolates because it holds a
/// port.
final class _Unsendable {
  _Unsendable();

  /// Ports can never cross an isolate boundary.
  final ReceivePort port = ReceivePort();

  @override
  String toString() => 'Unsendable error';
}

int throwUnsendable(int _) => throw _Unsendable();

Object returnUnsendable(int _) => _Unsendable();

String isolateName(int _) => Isolate.current.debugName ?? '';

void main() {
  group('WorkerPool', () {
    late WorkerPool pool;

    tearDown(() async {
      await pool.dispose();
    });

    test('default size is at least two', () {
      pool = WorkerPool();
      expect(pool.size, greaterThanOrEqualTo(2));
    });

    test('rejects a size below one', () {
      pool = WorkerPool(size: 1);
      expect(() => WorkerPool(size: 0), throwsArgumentError);
    });

    test('runs a task and returns its result', () async {
      pool = WorkerPool(size: 2);
      await pool.start();
      expect(await pool.run(square, 7), 49);
    });

    test('starts lazily on first run', () async {
      pool = WorkerPool(size: 1);
      expect(await pool.run(square, 3), 9);
    });

    test('start is idempotent', () async {
      pool = WorkerPool(size: 2);
      await pool.start();
      await pool.start();
      expect(await pool.run(square, 2), 4);
    });

    test('a single worker completes tasks in submission order', () async {
      pool = WorkerPool(size: 1);
      await pool.start();
      final completionOrder = <int>[];
      final futures = [
        pool.run(sleepThenReturn, 60),
        pool.run(sleepThenReturn, 30),
        pool.run(sleepThenReturn, 5),
      ].map((f) => f.then(completionOrder.add));
      await Future.wait(futures);
      expect(completionOrder, [60, 30, 5]);
    });

    test('uses the configured number of isolates', () async {
      pool = WorkerPool(size: 2, debugName: 'test-pool');
      await pool.start();
      final names = await pool.runAll(
        isolateName,
        List<int>.generate(20, (i) => i),
      );
      expect(names.toSet(), {'test-pool-0', 'test-pool-1'});
    });

    test('propagates the original error type and message', () async {
      pool = WorkerPool(size: 1);
      await expectLater(
        pool.run(throwFormat, 'bad input'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'bad input',
          ),
        ),
      );
      await expectLater(pool.run(throwState, 7), throwsStateError);
      // The worker is still usable afterwards.
      expect(await pool.run(square, 5), 25);
    });

    test('propagates a stack trace from the worker', () async {
      pool = WorkerPool(size: 1);
      StackTrace? trace;
      try {
        await pool.run(throwFormat, 'x');
      } on FormatException catch (_, st) {
        trace = st;
      }
      expect(trace.toString(), contains('throwFormat'));
    });

    test(
      'unsendable errors arrive as RemoteError with the description',
      () async {
        pool = WorkerPool(size: 1);
        await expectLater(
          pool.run(throwUnsendable, 0),
          throwsA(
            isA<RemoteError>().having(
              (e) => e.toString(),
              'description',
              contains('Unsendable error'),
            ),
          ),
        );
      },
    );

    test('unsendable results fail instead of hanging', () async {
      pool = WorkerPool(size: 1);
      await expectLater(pool.run(returnUnsendable, 0), throwsA(isA<Error>()));
      expect(await pool.run(square, 2), 4);
    });

    test('an unsendable task (closure) fails fast', () async {
      pool = WorkerPool(size: 1);
      await pool.start();
      final captured = DateTime.now();
      await expectLater(
        pool.run((int v) => v + captured.millisecond, 1),
        throwsArgumentError,
      );
      expect(await pool.run(square, 2), 4);
    });

    test(
      'handles 200 small tasks on a 2-worker pool, results in order',
      () async {
        pool = WorkerPool(size: 2);
        final args = List<int>.generate(200, (i) => i);
        final results = await pool.runAll(square, args);
        expect(results, args.map(square).toList());
        expect(pool.queuedTaskCount, 0);
        expect(pool.runningTaskCount, 0);
      },
    );

    test('runAll with bounded concurrency keeps the queue short', () async {
      pool = WorkerPool(size: 2);
      await pool.start();
      final args = List<int>.generate(50, (i) => i);
      final future = pool.runAll(square, args, maxConcurrency: 3);
      await Future<void>.delayed(Duration.zero);
      expect(
        pool.queuedTaskCount + pool.runningTaskCount,
        lessThanOrEqualTo(3),
      );
      expect(await future, args.map(square).toList());
    });

    test('runAll on an empty list returns an empty list', () async {
      pool = WorkerPool(size: 1);
      expect(await pool.runAll(square, <int>[]), isEmpty);
    });

    test('runAll fails with the first error and cancels the rest', () async {
      pool = WorkerPool(size: 1);
      final args = List<int>.generate(30, (i) => i);
      await expectLater(pool.runAll(throwState, args), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pool.queuedTaskCount, 0);
    });

    test(
      'a cancelled queued task fails fast while the running one finishes',
      () async {
        pool = WorkerPool(size: 1);
        await pool.start();
        final token = CancellationToken();
        final running = pool.run(sleepThenReturn, 300);
        final queued = pool.run(sleepThenReturn, 1, token: token);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(pool.queuedTaskCount, 1);

        final stopwatch = Stopwatch()..start();
        token.cancel('user cancelled');
        await expectLater(
          queued,
          throwsA(
            isA<OperationCancelledException>().having(
              (e) => e.reason,
              'reason',
              'user cancelled',
            ),
          ),
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
        expect(pool.queuedTaskCount, 0);
        expect(await running, 300);
      },
    );

    test(
      'a task scheduled with an already cancelled token never runs',
      () async {
        pool = WorkerPool(size: 1);
        final token = CancellationToken()..cancel();
        await expectLater(
          pool.run(square, 1, token: token),
          throwsA(isA<OperationCancelledException>()),
        );
        expect(pool.queuedTaskCount, 0);
      },
    );

    test('cancelling after completion is harmless', () async {
      pool = WorkerPool(size: 1);
      final token = CancellationToken();
      expect(await pool.run(square, 3, token: token), 9);
      expect(token.cancel, returnsNormally);
    });

    test(
      'dispose fails queued and running tasks and rejects new work',
      () async {
        pool = WorkerPool(size: 1);
        await pool.start();
        final running = pool.run(sleepThenReturn, 500);
        final queued = pool.run(square, 1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Attach the expectations before disposing so the synchronous
        // failures are observed rather than reported as unhandled.
        final runningFails = expectLater(
          running,
          throwsA(isA<OperationCancelledException>()),
        );
        final queuedFails = expectLater(
          queued,
          throwsA(isA<OperationCancelledException>()),
        );
        await pool.dispose();
        expect(pool.isDisposed, isTrue);
        await runningFails;
        await queuedFails;
        expect(() => pool.run(square, 1), throwsStateError);
        expect(pool.start, throwsStateError);
        // Second dispose is a no-op.
        await pool.dispose();
      },
    );

    test('dispose before start completes cleanly', () async {
      pool = WorkerPool(size: 2);
      await pool.dispose();
      expect(pool.isDisposed, isTrue);
    });

    test('dispose while starting kills the spawned isolates', () async {
      pool = WorkerPool(size: 2);
      final starting = pool.start();
      await pool.dispose();
      await starting;
      expect(pool.runningTaskCount, 0);
    });
  });
}
