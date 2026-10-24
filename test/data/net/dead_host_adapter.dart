// A dio adapter that makes one fake host behave like a host that is down,
// for the domain reachability tests (a real refused port takes about 2 s
// per attempt on Windows).

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// The host [DeadHostAdapter] fails.
const String deadHost = 'dead.test';

/// Fails every request to [deadHost] with a connection error; everything
/// else goes to a real [IOHttpClientAdapter].
final class DeadHostAdapter implements HttpClientAdapter {
  /// Creates the adapter.
  DeadHostAdapter() : _inner = IOHttpClientAdapter();

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.host == deadHost) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'host is down',
      );
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
