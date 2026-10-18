// OperationRunner: one at a time, progress, cancel, state cleared, logging.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

/// Blocks until [gate] completes, reporting progress on the way; honours
/// cancellation through the context token.
final class _GatedOperation extends Operation<String> {
  _GatedOperation({
    this.gate,
    this.kindValue = OperationKind.downloadAssets,
    this.fallback,
    this.failWith,
  });

  final Completer<void>? gate;
  final OperationKind kindValue;
  final String? fallback;
  final Object? failWith;
  OperationContext? context;

  @override
  OperationKind get kind => kindValue;

  @override
  String? cancelledResult() => fallback;

  @override
  Future<String> run(OperationContext ctx) async {
    context = ctx;
    ctx.report(
      OperationProgress(kind: kind, label: 'step.one', done: 1, total: 4),
    );
    if (failWith != null) throw failWith!;
    final gate = this.gate;
    if (gate != null) {
      await Future.any([gate.future, ctx.token.whenCancelled]);
      ctx.checkCancelled();
    }
    ctx.report(
      OperationProgress(kind: kind, label: 'step.two', done: 4, total: 4),
    );
    return 'done';
  }
}

void main() {
  late AppLog log;
  late ProviderContainer container;

  setUp(() {
    log = AppLog(store: LogStore());
    container = ProviderContainer.test(
      overrides: [appLogProvider.overrideWithValue(log)],
    );
    addTearDown(log.dispose);
  });

  OperationRunner runner() => container.read(operationRunnerProvider.notifier);
  OperationState state() => container.read(operationRunnerProvider);

  test('starts idle', () {
    expect(state(), OperationState.idle);
    expect(state().isRunning, isFalse);
    expect(container.read(anyOperationRunningProvider), isFalse);
  });

  test('runs an operation, publishes progress and returns to idle', () async {
    final gate = Completer<void>();
    final op = _GatedOperation(gate: gate);
    final states = <OperationState>[];
    container.listen(operationRunnerProvider, (_, next) => states.add(next));

    final pending = runner().run(op);
    await Future<void>.delayed(Duration.zero);
    expect(state().isRunning, isTrue);
    expect(state().operationId, op.id);
    expect(state().kind, OperationKind.downloadAssets);
    expect(state().progress?.label, 'step.one');
    expect(state().progress?.value, 0.25);
    expect(container.read(anyOperationRunningProvider), isTrue);

    gate.complete();
    expect(await pending, 'done');
    expect(state(), OperationState.idle);
    expect(container.read(anyOperationRunningProvider), isFalse);
    expect(states.last, OperationState.idle);
    expect(states.any((s) => s.progress?.label == 'step.two'), isTrue);

    final messages = log.store.entries.map((e) => e.message).toList();
    expect(messages.first, 'Started downloadAssets');
    expect(messages.last, startsWith('Finished downloadAssets in'));
    expect(log.store.entries.first.operationId, op.id);
    expect(log.store.entries.first.source, LogSource.download);
  });

  test('rejects a second operation while one runs', () async {
    final gate = Completer<void>();
    final first = runner().run(_GatedOperation(gate: gate));
    await Future<void>.delayed(Duration.zero);
    expect(
      () => runner().run(_GatedOperation()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'An operation is already running',
        ),
      ),
    );
    gate.complete();
    await first;
    // Free again afterwards.
    expect(await runner().run(_GatedOperation()), 'done');
  });

  test('cancel sets cancelRequested, cancels the token and uses the typed '
      'cancellation result', () async {
    final op = _GatedOperation(gate: Completer<void>(), fallback: 'partial');
    final pending = runner().run(op);
    await Future<void>.delayed(Duration.zero);

    runner().cancel();
    expect(state().cancelRequested, isTrue);
    expect(state().progress?.cancelRequested, isTrue);
    expect(op.context!.token.isCancelled, isTrue);

    expect(await pending, 'partial');
    expect(state(), OperationState.idle);
    expect(
      log.store.entries.map((e) => e.message),
      contains(startsWith('Cancelled downloadAssets')),
    );
    expect(log.store.entries.last.level, LogLevel.warning);
  });

  test('cancellation without a typed result rethrows', () async {
    final pending = runner().run(_GatedOperation(gate: Completer<void>()));
    await Future<void>.delayed(Duration.zero);
    runner().cancel();
    await expectLater(pending, throwsA(isA<OperationCancelledException>()));
    expect(state(), OperationState.idle);
  });

  test('cancel while idle is a no-op', () {
    runner().cancel();
    expect(state(), OperationState.idle);
  });

  test(
    'a failing operation is logged, rethrown and the state cleared',
    () async {
      await expectLater(
        runner().run(
          _GatedOperation(
            kindValue: OperationKind.updateWorkshop,
            failWith: StateError('kaput'),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(state(), OperationState.idle);
      final failure = log.store.entries.last;
      expect(failure.level, LogLevel.error);
      expect(failure.source, LogSource.workshop);
      expect(failure.message, startsWith('Failed updateWorkshop'));
      expect(failure.details, contains('kaput'));
    },
  );

  test(
    'progress reported after cancellation carries cancelRequested',
    () async {
      final gate = Completer<void>();
      final op = _GatedOperation(gate: gate);
      final pending = runner().run(op);
      await Future<void>.delayed(Duration.zero);
      op.context!.token.cancel();
      op.context!.report(
        const OperationProgress(
          kind: OperationKind.downloadAssets,
          label: 'late',
          done: 2,
          total: 4,
        ),
      );
      expect(state().progress?.label, 'late');
      expect(state().progress?.cancelRequested, isTrue);
      gate.complete();
      await expectLater(pending, throwsA(isA<OperationCancelledException>()));
    },
  );

  test('operation ids are unique and carry the kind', () {
    final a = _GatedOperation();
    final b = _GatedOperation(kindValue: OperationKind.checkUrls);
    expect(a.id, isNot(b.id));
    expect(a.id, startsWith('downloadAssets#'));
    expect(b.id, startsWith('checkUrls#'));
  });

  test('OperationProgress.value prefers fraction, then done/total', () {
    const kind = OperationKind.backup;
    expect(
      const OperationProgress(kind: kind, label: 'x', fraction: 0.4).value,
      0.4,
    );
    expect(
      const OperationProgress(kind: kind, label: 'x', done: 1, total: 2).value,
      0.5,
    );
    expect(const OperationProgress(kind: kind, label: 'x').value, isNull);
    expect(
      const OperationProgress(kind: kind, label: 'x', fraction: 1.7).value,
      1.0,
    );
  });

  test('every kind maps to a log source', () {
    for (final kind in OperationKind.values) {
      expect(kind.logSource, isA<LogSource>());
    }
    expect(OperationKind.checkUrls.logSource, LogSource.urlCheck);
    expect(OperationKind.importBackup.logSource, LogSource.import);
    expect(OperationKind.deleteAssets.logSource, LogSource.cleanup);
  });
}
