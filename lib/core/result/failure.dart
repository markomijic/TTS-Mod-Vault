/// Describes why an operation failed.
///
/// [message] is human readable and safe to show in the UI or a log line.
/// [cause] carries the original error (an exception, a Dio error, ...) and
/// [stackTrace] the trace captured where the failure originated, so a log sink
/// can keep the technical detail without the UI having to know about it.
final class Failure {
  /// Creates a failure with a human readable [message].
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Builds a failure from a caught [error], using its `toString()` as the
  /// message unless [message] is given. A [Failure] passed as [error] is
  /// returned unchanged.
  factory Failure.from(
    Object error, [
    StackTrace? stackTrace,
    String? message,
  ]) {
    if (error is Failure) {
      return error;
    }
    return Failure(
      message ?? error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Human readable description of the failure.
  final String message;

  /// The original error that caused this failure, if any.
  final Object? cause;

  /// Stack trace captured where the failure originated, if any.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      cause == null ? 'Failure($message)' : 'Failure($message, cause: $cause)';
}
