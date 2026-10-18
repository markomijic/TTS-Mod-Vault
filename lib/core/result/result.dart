import 'dart:async';

import 'package:tts_mod_vault/core/result/failure.dart';

export 'package:tts_mod_vault/core/result/failure.dart';

/// Outcome of an operation that can fail in an expected way: either [Ok]
/// carrying a value of type [T], or [Err] carrying a [Failure].
///
/// Use it for failures the caller is expected to handle (a missing file, a
/// 404, invalid JSON). Programming errors should still be thrown.
///
/// ```dart
/// final result = await readSettings();
/// final text = result.when(
///   ok: (settings) => settings.name,
///   err: (failure) => 'Could not load settings: ${failure.message}',
/// );
/// ```
sealed class Result<T> {
  const Result();

  /// Creates a successful result.
  const factory Result.ok(T value) = Ok<T>;

  /// Creates a failed result.
  const factory Result.err(Failure failure) = Err<T>;

  /// Runs [body] and wraps its value in [Ok], or any thrown error in [Err].
  ///
  /// [onError] can turn the caught error into a tailored [Failure]; by
  /// default [Failure.from] is used.
  static Future<Result<T>> guard<T>(
    FutureOr<T> Function() body, {
    Failure Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return Ok<T>(await body());
    } catch (error, stackTrace) {
      return Err<T>(
        onError?.call(error, stackTrace) ?? Failure.from(error, stackTrace),
      );
    }
  }

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// The value when [isOk], otherwise `null`.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The failure when [isErr], otherwise `null`.
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  /// Folds both cases into a single value.
  U when<U>({
    required U Function(T value) ok,
    required U Function(Failure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };

  /// Transforms the value of an [Ok]; an [Err] passes through unchanged.
  Result<U> map<U>(U Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok<U>(transform(value)),
    Err<T>(:final failure) => Err<U>(failure),
  };

  /// Chains another fallible step onto an [Ok]; an [Err] passes through.
  Result<U> flatMap<U>(Result<U> Function(T value) next) => switch (this) {
    Ok<T>(:final value) => next(value),
    Err<T>(:final failure) => Err<U>(failure),
  };

  /// The value when [isOk], or the result of [orElse] for the failure.
  T getOrElse(T Function(Failure failure) orElse) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final failure) => orElse(failure),
  };
}

/// Successful [Result] carrying a [value].
final class Ok<T> extends Result<T> {
  /// Creates a successful result.
  const Ok(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// Failed [Result] carrying a [failure].
final class Err<T> extends Result<T> {
  /// Creates a failed result.
  const Err(this.failure);

  /// Why the operation failed.
  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
