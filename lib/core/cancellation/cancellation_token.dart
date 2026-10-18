import 'dart:async';

/// Thrown by [CancellationToken.throwIfCancelled] and by APIs that abandon
/// work because their token was cancelled.
final class OperationCancelledException implements Exception {
  /// Creates the exception with an optional [reason] (the one passed to
  /// [CancellationToken.cancel]).
  const OperationCancelledException([this.reason]);

  /// Why the operation was cancelled, if a reason was given.
  final Object? reason;

  @override
  String toString() => reason == null
      ? 'OperationCancelledException'
      : 'OperationCancelledException: $reason';
}

/// Cooperative cancellation signal shared by an operation and the code it
/// drives (downloads, worker tasks, file scans).
///
/// Cancellation is one-way and permanent: once [cancel] has been called,
/// [isCancelled] stays `true`. Work that wants to honour the token calls
/// [throwIfCancelled] at its await boundaries, or bridges to another
/// mechanism through [whenCancelled] / [onCancel]; for a dio `CancelToken`:
///
/// ```dart
/// final dioToken = CancelToken();
/// final remove = token.onCancel((reason) => dioToken.cancel(reason));
/// try {
///   await dio.get(url, cancelToken: dioToken);
/// } finally {
///   remove();
/// }
/// ```
///
/// Tokens can be chained with [CancellationToken.linked]: the child cancels
/// when its parent does, while cancelling the child leaves the parent intact.
final class CancellationToken {
  /// Creates a fresh, not cancelled token.
  CancellationToken();

  /// Creates a token that is cancelled as soon as [parent] is (with the same
  /// reason). Cancelling the returned token does not affect [parent].
  factory CancellationToken.linked(CancellationToken parent) {
    final child = CancellationToken();
    final removeParentListener = parent.onCancel(child.cancel);
    // Once the child is cancelled on its own, it no longer needs the parent.
    child.onCancel((_) => removeParentListener());
    return child;
  }

  final Completer<void> _completer = Completer<void>();
  List<void Function(Object? reason)>? _listeners = [];
  Object? _reason;
  bool _isCancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// The reason passed to [cancel], or `null`.
  Object? get cancelReason => _reason;

  /// Completes when the token is cancelled. Never completes for a token that
  /// is never cancelled, so do not `await` it without a competing future.
  Future<void> get whenCancelled => _completer.future;

  /// Cancels the token. Calling it again is a no-op (the first [reason] is
  /// kept). Listeners registered with [onCancel] run synchronously, in
  /// registration order.
  void cancel([Object? reason]) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _reason = reason;
    final listeners = _listeners;
    _listeners = null;
    _completer.complete();
    if (listeners != null) {
      for (final listener in listeners) {
        listener(reason);
      }
    }
  }

  /// Registers [callback] to run when the token is cancelled. If it already
  /// is, [callback] runs immediately. Returns a function that unregisters
  /// the callback; calling it after cancellation is harmless.
  void Function() onCancel(void Function(Object? reason) callback) {
    final listeners = _listeners;
    if (listeners == null) {
      callback(_reason);
      return () {};
    }
    listeners.add(callback);
    return () => _listeners?.remove(callback);
  }

  /// Throws [OperationCancelledException] if the token is cancelled.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException(_reason);
    }
  }

  @override
  String toString() =>
      'CancellationToken(${_isCancelled ? 'cancelled' : 'active'})';
}
