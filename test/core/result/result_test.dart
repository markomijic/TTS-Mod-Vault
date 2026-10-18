import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/result/result.dart';

void main() {
  group('Result', () {
    test('Ok exposes value and reports isOk', () {
      const Result<int> result = Ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('Err exposes failure and reports isErr', () {
      const failure = Failure('nope');
      const Result<int> result = Err(failure);
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, same(failure));
    });

    test('factory constructors build the matching subtype', () {
      expect(const Result<int>.ok(1), isA<Ok<int>>());
      expect(const Result<int>.err(Failure('x')), isA<Err<int>>());
    });

    test('map transforms Ok and passes Err through', () {
      const Result<int> ok = Ok(2);
      const Result<int> err = Err(Failure('bad'));
      expect(ok.map((v) => v * 10), const Ok<int>(20));
      expect(ok.map((v) => 'v$v'), const Ok<String>('v2'));
      final mappedErr = err.map((v) => v * 10);
      expect(mappedErr, isA<Err<int>>());
      expect(mappedErr.failureOrNull?.message, 'bad');
    });

    test('flatMap chains and short-circuits', () {
      Result<int> half(int v) =>
          v.isEven ? Ok(v ~/ 2) : Err(Failure('$v is odd'));
      expect(const Ok<int>(8).flatMap(half).flatMap(half), const Ok<int>(2));
      expect(
        const Ok<int>(6).flatMap(half).flatMap(half).failureOrNull?.message,
        '3 is odd',
      );
    });

    test('when folds both branches', () {
      String describe(Result<int> r) =>
          r.when(ok: (v) => 'ok $v', err: (f) => 'err ${f.message}');
      expect(describe(const Ok(1)), 'ok 1');
      expect(describe(const Err(Failure('boom'))), 'err boom');
    });

    test('getOrElse returns value or fallback', () {
      expect(const Ok<int>(5).getOrElse((_) => -1), 5);
      expect(const Err<int>(Failure('x')).getOrElse((_) => -1), -1);
    });

    test('guard wraps a value', () async {
      final result = await Result.guard(() async => 'done');
      expect(result, const Ok<String>('done'));
    });

    test('guard wraps a thrown error with cause and stack trace', () async {
      final result = await Result.guard<int>(
        () => throw const FormatException('malformed'),
      );
      expect(result.isErr, isTrue);
      final failure = result.failureOrNull!;
      expect(failure.cause, isA<FormatException>());
      expect(failure.stackTrace, isNotNull);
      expect(failure.message, contains('malformed'));
    });

    test('guard uses the onError mapper', () async {
      final result = await Result.guard<int>(
        () => throw StateError('internal'),
        onError: (e, st) => Failure('Friendly message', cause: e),
      );
      expect(result.failureOrNull?.message, 'Friendly message');
      expect(result.failureOrNull?.cause, isA<StateError>());
    });

    test('Ok and Err have value equality', () {
      expect(const Ok<int>(1), const Ok<int>(1));
      expect(const Ok<int>(1), isNot(const Ok<int>(2)));
      const failure = Failure('same');
      expect(const Err<int>(failure), const Err<int>(failure));
    });
  });

  group('Failure', () {
    test('from keeps an existing Failure', () {
      const failure = Failure('x');
      expect(Failure.from(failure), same(failure));
    });

    test('from uses toString as message by default', () {
      final failure = Failure.from(ArgumentError('bad arg'));
      expect(failure.message, contains('bad arg'));
      expect(failure.cause, isA<ArgumentError>());
    });

    test('toString includes cause when present', () {
      expect(const Failure('m').toString(), 'Failure(m)');
      expect(const Failure('m', cause: 'c').toString(), 'Failure(m, cause: c)');
    });
  });
}
