/// In-app update notice: compares the running version with the latest
/// GitHub release.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/github_releases_client.dart';
import 'package:tts_mod_vault/domain/parsing/version_compare.dart';

/// The GitHub releases endpoint queried by [updateCheckProvider];
/// overridable in tests.
final githubReleasesApiUrlProvider = Provider<String>(
  (ref) => githubLatestReleaseUrl,
);

/// The running app's version (`PackageInfo.version`); overridable in tests.
final currentAppVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// The newer version available on GitHub, or `null` when the app is up to
/// date or the check failed. Lazy: nothing is requested until something
/// watches it (the startup flow wires the notice in later).
final updateCheckProvider = FutureProvider<String?>((ref) async {
  final current = await ref.watch(currentAppVersionProvider.future);
  final latest = await latestReleaseVersion(
    ref.watch(dioProvider),
    apiUrl: ref.watch(githubReleasesApiUrlProvider),
  );
  if (latest == null) return null;
  return isNewerVersion(current, latest) ? latest : null;
});
