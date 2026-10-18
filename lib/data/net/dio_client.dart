import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Connect timeout shared by every request.
const Duration dioConnectTimeout = Duration(seconds: 15);

/// The one [Dio] instance of the app: 15 s connect timeout, redirects
/// followed, no cookie handling. Closed with the container. Clients take a
/// `Dio` through their constructor, so tests build their own.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(connectTimeout: dioConnectTimeout, followRedirects: true),
  );
  ref.onDispose(dio.close);
  return dio;
});
