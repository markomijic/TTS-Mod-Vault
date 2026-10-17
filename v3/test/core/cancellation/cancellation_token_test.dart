import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('starts active and becomes cancelled once', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
      expect(token.cancelReason, isNull);

      token.cancel('first');
      expect(token.isCancelled, isTrue);
      expect(token.cancelReason, 'first');

      token.cancel('second');
      expect(token.cancelReason, 'first', reason: 'first reason is kept');
    });

    test('throwIfCancelled throws only after cancel, carrying the reason', () {
      final token = CancellationToken();
      expect(token.throwIfCancelled, returnsNormally);
      token.cancel('user');
      expect(
        token.throwIfCancelled,
        throwsA(
          isA<OperationCancelledException>().having(
            (e) => e.reason,
            'reason',
            'user',
          ),
        ),
      );
    });

    test('whenCancelled completes on cancel', () async {
      final token = CancellationToken();
      var completed = false;
      unawaited(token.whenCancelled.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      token.cancel();
      await token.whenCancelled;
      expect(completed, isTrue);
    });

    test(
      'onCancel listeners run synchronously in order and can be removed',
      () {
        final token = CancellationToken();
        final calls = <String>[];
        token.onCancel((r) => calls.add('a:$r'));
        final removeB = token.onCancel((r) => calls.add('b:$r'));
        token.onCancel((r) => calls.add('c:$r'));
        removeB();

        token.cancel('x');
        expect(calls, ['a:x', 'c:x']);
      },
    );

    test('onCancel on an already cancelled token runs immediately', () {
      final token = CancellationToken()..cancel('done');
      Object? seen;
      final remove = token.onCancel((r) => seen = r);
      expect(seen, 'done');
      expect(remove, returnsNormally);
    });

    test('linked child cancels with its parent and shares the reason', () {
      final parent = CancellationToken();
      final child = CancellationToken.linked(parent);
      expect(child.isCancelled, isFalse);

      parent.cancel('parent gone');
      expect(child.isCancelled, isTrue);
      expect(child.cancelReason, 'parent gone');
    });

    test('cancelling a linked child leaves the parent active', () {
      final parent = CancellationToken();
      final child = CancellationToken.linked(parent);

      child.cancel('only child');
      expect(child.isCancelled, isTrue);
      expect(parent.isCancelled, isFalse);

      // Parent cancelling later must not overwrite the child's reason.
      parent.cancel('later');
      expect(child.cancelReason, 'only child');
    });

    test('linking to an already cancelled parent yields a cancelled child', () {
      final parent = CancellationToken()..cancel('early');
      final child = CancellationToken.linked(parent);
      expect(child.isCancelled, isTrue);
      expect(child.cancelReason, 'early');
    });

    test('OperationCancelledException toString mentions the reason', () {
      expect(
        const OperationCancelledException().toString(),
        'OperationCancelledException',
      );
      expect(
        const OperationCancelledException('why').toString(),
        'OperationCancelledException: why',
      );
    });
  });
}
