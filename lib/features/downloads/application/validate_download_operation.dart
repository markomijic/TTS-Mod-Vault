/// Checks, after a download, why the files of a mod that are still missing
/// could not be fetched. Port of 2.x `validateModAfterDownload` (`051741c`).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';
import 'package:tts_mod_vault/data/net/url_checker.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/downloads/application/check_urls_operation.dart';
import 'package:tts_mod_vault/features/downloads/application/download_assets_operation.dart'
    show includeAudioFor;
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';

/// Outcome of a [ValidateDownloadOperation].
final class DownloadValidationResult {
  /// Creates a result.
  const DownloadValidationResult({
    required this.mod,
    this.unreachableDomains = const [],
    this.invalidUrls = const [],
    this.cancelled = false,
  });

  /// The validated mod.
  final Mod mod;

  /// Hosts of still-missing files that could not be reached, sorted. Their
  /// URLs were not judged.
  final List<String> unreachableDomains;

  /// Still-missing URLs on reachable hosts that do not answer.
  final List<String> invalidUrls;

  /// Whether the check was cancelled; the lists are then empty and nothing
  /// was saved.
  final bool cancelled;

  /// Whether the result is worth showing.
  bool get hasIssues =>
      !cancelled && (unreachableDomains.isNotEmpty || invalidUrls.isNotEmpty);

  @override
  String toString() =>
      'DownloadValidationResult(${mod.displayName}: '
      'unreachable=${unreachableDomains.length} invalid=${invalidUrls.length}'
      '${cancelled ? ' cancelled' : ''})';
}

/// After a download of [mod]: runs the files that are still missing through
/// [checkUrlsWithDomains] (host results younger than a minute are reused,
/// so a bulk run checks each host once). When every host answered, the dead
/// URLs replace the mod's stored invalid list; when nothing is missing the
/// stored list is cleared. Saved objects are skipped like in 2.x. A
/// cancelled check returns an empty, cancelled result and saves nothing.
final class ValidateDownloadOperation
    extends Operation<DownloadValidationResult> {
  /// Creates the operation.
  ValidateDownloadOperation({required this.ref, required this.mod});

  /// Supplies the database, network client and library.
  final Ref ref;

  /// The mod that was just downloaded.
  final Mod mod;

  final UrlCheckProgress _progress = UrlCheckProgress();

  @override
  OperationKind get kind => OperationKind.checkUrls;

  @override
  DownloadValidationResult? cancelledResult() =>
      DownloadValidationResult(mod: mod, cancelled: true);

  @override
  Future<DownloadValidationResult> run(OperationContext ctx) async {
    if (mod.ref.type == ModType.savedObject) {
      return DownloadValidationResult(mod: mod);
    }
    final log = ctx.log;
    final modPath = mod.jsonPath;
    final db = ref.read(appDatabaseProvider);
    final options = await ref
        .read(networkOptionsProvider.notifier)
        .ensureLoaded();
    final ignoreAudio = ref.read(libraryOptionsProvider).ignoreAudioGlobally;
    final assets = await db.libraryQueries.assetsForMod(
      modPath,
      includeAudio: includeAudioFor(mod, ignoreAudioGlobally: ignoreAudio),
    );
    ctx.checkCancelled();

    final missing = {
      for (final asset in assets)
        if (!asset.exists) asset.url,
    }.toList();
    if (missing.isEmpty) {
      if (assets.any((asset) => asset.invalid)) {
        await _store(modPath, const []);
      }
      return DownloadValidationResult(mod: mod);
    }

    log.info(
      LogSource.urlCheck,
      'Checking ${missing.length} file(s) of "${mod.displayName}" that are '
      'still missing after the download',
      modPath: modPath,
      operationId: ctx.operationId,
    );
    final result = await checkUrlsWithDomains(
      ctx,
      kind: kind,
      urls: missing,
      concurrency: options.concurrentDownloads,
      forceDomainRefresh: false,
      domainChecker: ref.read(domainReachabilityCheckerProvider),
      urlChecker: UrlChecker(dio: ref.read(dioProvider)),
      into: _progress,
      onUnreachable: (domain) => log.warning(
        LogSource.urlCheck,
        'Domain is not reachable: $domain; its missing files were not '
        'marked invalid',
        modPath: modPath,
        operationId: ctx.operationId,
      ),
      onInvalid: (url) => log.warning(
        LogSource.urlCheck,
        'URL is not reachable: $url',
        modPath: modPath,
        url: url,
        operationId: ctx.operationId,
      ),
    );
    if (result.cancelled) {
      log.warning(
        LogSource.urlCheck,
        'Download check of "${mod.displayName}" cancelled; result not saved',
        modPath: modPath,
        operationId: ctx.operationId,
      );
      return DownloadValidationResult(mod: mod, cancelled: true);
    }

    if (result.unreachableDomains.isEmpty) {
      await _store(modPath, result.invalidUrls);
    }
    log.info(
      LogSource.urlCheck,
      'Download check of "${mod.displayName}": '
      '${result.unreachableDomains.length} domain(s) not reachable, '
      '${result.invalidUrls.length} invalid URL(s)'
      '${result.unreachableDomains.isEmpty ? '' : '; result not saved'}',
      modPath: modPath,
      operationId: ctx.operationId,
    );
    return DownloadValidationResult(
      mod: mod,
      unreachableDomains: result.unreachableDomains,
      invalidUrls: result.invalidUrls,
    );
  }

  Future<void> _store(String modPath, List<String> invalid) async {
    await ref
        .read(appDatabaseProvider)
        .modsDao
        .setInvalidUrls(modPath, invalid);
    if (ref.mounted) {
      await ref
          .read(libraryControllerProvider.notifier)
          .resummarizeMod(modPath);
    }
    if (ref.mounted) ref.invalidate(modAssetsProvider(modPath));
  }
}
