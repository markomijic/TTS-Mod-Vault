/// Latest-release lookup on GitHub for the in-app update notice.
library;

import 'package:dio/dio.dart';

/// The releases endpoint of the TTS Mod Vault repository.
const String githubLatestReleaseUrl =
    'https://api.github.com/repos/markomijic/TTS-Mod-Vault/releases/latest';

/// Returns the tag of the latest GitHub release without its leading `v`
/// (`v3.1.0` -> `3.1.0`), or `null` on any failure (network error, non-200
/// status, unexpected body). Never throws.
Future<String?> latestReleaseVersion(
  Dio dio, {
  String apiUrl = githubLatestReleaseUrl,
}) async {
  try {
    final response = await dio.get<Map<String, Object?>>(
      apiUrl,
      options: Options(
        responseType: ResponseType.json,
        headers: {'Accept': 'application/vnd.github+json'},
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    if (response.statusCode != 200) return null;
    final tag = response.data?['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    final version = tag.startsWith('v') || tag.startsWith('V')
        ? tag.substring(1)
        : tag;
    return version.isEmpty ? null : version;
  } on Object {
    return null;
  }
}
