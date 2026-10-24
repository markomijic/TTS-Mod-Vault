/// Checks whether the asset URLs of one mod still answer and stores the dead
/// ones on the mod. Port of v2 `checkModUrlsLive`, with the 2.x domain
/// reachability step (`051741c`) in front.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';
import 'package:tts_mod_vault/data/net/url_checker.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/downloads/application/download_assets_operation.dart'
    show includeAudioFor;
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';

/// Progress label key of the URL check.
const String checkUrlsProgressLabel = 'checking.urls';

/// Progress label key of the domain reachability step.
const String checkDomainsProgressLabel = 'checking.domains';

/// Outcome of a [CheckUrlsOperation].
final class UrlCheckResult {
  /// Creates a result.
  const UrlCheckResult({
    required this.invalidUrls,
    required this.cancelled,
    required this.checked,
    required this.total,
    this.unreachableDomains = const [],
  });

  /// URLs that did not answer. Partial when [cancelled].
  final List<String> invalidUrls;

  /// Hosts that could not be reached at all, sorted. Their URLs were not
  /// checked and are not in [invalidUrls]; while any host is unreachable the
  /// result is not persisted on the mod.
  final List<String> unreachableDomains;

  /// Whether the check was cancelled before every URL was tried; the
  /// partial result is then not persisted on the mod.
  final bool cancelled;

  /// URLs actually checked (those on unreachable hosts are skipped).
  final int checked;

  /// URLs the mod has.
  final int total;

  /// Whether every URL answered.
  bool get allLive =>
      !cancelled && invalidUrls.isEmpty && unreachableDomains.isEmpty;

  @override
  String toString() =>
      'UrlCheckResult(checked=$checked/$total invalid=${invalidUrls.length}'
      '${unreachableDomains.isEmpty ? '' : ' unreachable=${unreachableDomains.length}'}'
      '${cancelled ? ' cancelled' : ''})';
}

/// Partial state of [checkUrlsWithDomains], kept by the calling operation so
/// its `cancelledResult` can report what was found before a cancel.
final class UrlCheckProgress {
  /// URLs found dead so far.
  final List<String> invalid = [];

  /// Hosts found unreachable (set once the domain step finished).
  List<String> unreachableDomains = const [];

  /// URLs checked for liveness so far.
  int checked = 0;

  /// URLs given to the check.
  int total = 0;

  /// The state as a result.
  UrlCheckResult toResult({required bool cancelled}) => UrlCheckResult(
    invalidUrls: List.unmodifiable(invalid),
    unreachableDomains: List.unmodifiable(unreachableDomains),
    cancelled: cancelled,
    checked: checked,
    total: total,
  );
}

/// The two-step check shared by [CheckUrlsOperation] and the post-download
/// validation: first the hosts of [urls] are checked for reachability
/// (progress [checkDomainsProgressLabel]); URLs on unreachable hosts are
/// then skipped and the rest are checked for liveness with [concurrency]
/// workers (progress [checkUrlsProgressLabel]). [onUnreachable] and
/// [onInvalid] are called per finding (for log lines). Persists nothing;
/// returns [into]'s state, `cancelled` when the token fired during either
/// step.
Future<UrlCheckResult> checkUrlsWithDomains(
  OperationContext ctx, {
  required OperationKind kind,
  required List<String> urls,
  required int concurrency,
  required bool forceDomainRefresh,
  required DomainReachabilityChecker domainChecker,
  required UrlChecker urlChecker,
  required UrlCheckProgress into,
  void Function(String domain)? onUnreachable,
  void Function(String url)? onInvalid,
}) async {
  into.total = urls.length;
  final workers = concurrency < 1 ? 1 : concurrency;

  final domains = await domainChecker.checkUrls(
    urls,
    concurrency: workers,
    forceRefresh: forceDomainRefresh,
    token: ctx.token,
    onProgress: (done, total) => ctx.report(
      OperationProgress(
        kind: kind,
        label: checkDomainsProgressLabel,
        done: done,
        total: total,
      ),
    ),
  );
  if (domains.cancelled || ctx.isCancelled) {
    return into.toResult(cancelled: true);
  }
  final unreachable = domains.unreachable;
  into.unreachableDomains = unreachable;
  if (onUnreachable != null) unreachable.forEach(onUnreachable);

  final unreachableSet = unreachable.toSet();
  final toCheck = [
    for (final url in urls)
      if (!unreachableSet.contains(DomainReachabilityChecker.hostOf(url))) url,
  ];
  void publish() => ctx.report(
    OperationProgress(
      kind: kind,
      label: checkUrlsProgressLabel,
      done: into.checked,
      total: toCheck.length,
    ),
  );
  publish();

  var nextIndex = 0;
  await Future.wait(
    List.generate(workers, (_) async {
      while (!ctx.isCancelled && nextIndex < toCheck.length) {
        final url = toCheck[nextIndex++];
        final bool live;
        try {
          live = await urlChecker.isLive(url, token: ctx.token);
        } on OperationCancelledException {
          return;
        }
        if (ctx.isCancelled) return;
        if (!live) {
          into.invalid.add(url);
          onInvalid?.call(url);
        }
        into.checked++;
        publish();
      }
    }),
  );
  return into.toResult(cancelled: ctx.isCancelled);
}

/// Checks every asset URL of [mod] (audio included or not by the same rule
/// as the asset list) with `concurrentDownloads` workers, after checking
/// that their hosts can be reached at all (see [checkUrlsWithDomains]).
/// URLs on unreachable hosts are skipped and not marked invalid. On
/// completion, and only when every host was reachable, the invalid URLs
/// replace the mod's stored list (an empty list clears it), the mod is
/// re-summarised and its asset list invalidated; on cancellation, or with
/// an unreachable host, the result is returned without being persisted.
///
/// With [onlyAsset] (the asset menu's "Check URL") just that URL is checked
/// and its outcome is merged into the stored list: the URL is added when
/// dead and removed when live, the other entries are kept.
final class CheckUrlsOperation extends Operation<UrlCheckResult> {
  /// Creates the operation.
  CheckUrlsOperation({
    required this.ref,
    required this.mod,
    this.onlyAsset,
    this.forceDomainRefresh = true,
  });

  /// Supplies the database, network client and library.
  final Ref ref;

  /// The mod whose URLs are checked.
  final Mod mod;

  /// When set, the one asset to check instead of the whole mod.
  final Asset? onlyAsset;

  /// Whether host results younger than a minute are checked again. The bulk
  /// check passes `false` so mods sharing hosts reuse one result.
  final bool forceDomainRefresh;

  final UrlCheckProgress _progress = UrlCheckProgress();

  @override
  OperationKind get kind => OperationKind.checkUrls;

  @override
  UrlCheckResult? cancelledResult() => _progress.toResult(cancelled: true);

  @override
  Future<UrlCheckResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final modPath = mod.jsonPath;
    final options = await ref
        .read(networkOptionsProvider.notifier)
        .ensureLoaded();
    final ignoreAudio = ref.read(libraryOptionsProvider).ignoreAudioGlobally;
    final onlyAsset = this.onlyAsset;
    final assets = onlyAsset != null
        ? [onlyAsset]
        : await ref
              .read(appDatabaseProvider)
              .libraryQueries
              .assetsForMod(
                modPath,
                includeAudio: includeAudioFor(
                  mod,
                  ignoreAudioGlobally: ignoreAudio,
                ),
              );
    ctx.checkCancelled();

    log.info(
      LogSource.urlCheck,
      'Checking ${assets.length} URL(s) of "${mod.displayName}"',
      modPath: modPath,
      operationId: ctx.operationId,
    );
    ctx.report(
      OperationProgress(
        kind: kind,
        label: checkUrlsProgressLabel,
        total: assets.length,
      ),
    );

    final typeOf = {for (final asset in assets) asset.url: asset.type};
    final result = await checkUrlsWithDomains(
      ctx,
      kind: kind,
      urls: [for (final asset in assets) asset.url],
      concurrency: options.concurrentDownloads,
      forceDomainRefresh: forceDomainRefresh,
      domainChecker: ref.read(domainReachabilityCheckerProvider),
      urlChecker: UrlChecker(dio: ref.read(dioProvider)),
      into: _progress,
      onUnreachable: (domain) => log.warning(
        LogSource.urlCheck,
        'Domain is not reachable: $domain; its URLs were not checked',
        modPath: modPath,
        operationId: ctx.operationId,
      ),
      onInvalid: (url) => log.warning(
        LogSource.urlCheck,
        'URL is not reachable: $url',
        details: 'type: ${typeOf[url]?.folderName}',
        modPath: modPath,
        url: url,
        operationId: ctx.operationId,
      ),
    );

    if (result.cancelled) {
      log.warning(
        LogSource.urlCheck,
        'URL check of "${mod.displayName}" cancelled after '
        '${result.checked}/${assets.length} URL(s); result not saved',
        modPath: modPath,
        operationId: ctx.operationId,
      );
      return result;
    }

    final invalid = result.invalidUrls;
    final unreachable = result.unreachableDomains;
    if (unreachable.isNotEmpty) {
      log.warning(
        LogSource.urlCheck,
        'Checked ${result.checked}/${assets.length} URL(s) of '
        '"${mod.displayName}": ${unreachable.length} domain(s) not '
        'reachable, ${invalid.length} URL(s) not reachable; result not saved',
        details: [...unreachable, ...invalid].join('\n'),
        modPath: modPath,
        operationId: ctx.operationId,
      );
      return result;
    }

    final stored = onlyAsset == null
        ? invalid
        : await _mergeStoredInvalidUrls(modPath, onlyAsset.url, invalid);
    await ref.read(appDatabaseProvider).modsDao.setInvalidUrls(modPath, stored);
    if (ref.mounted) {
      await ref
          .read(libraryControllerProvider.notifier)
          .resummarizeMod(modPath);
    }
    if (ref.mounted) ref.invalidate(modAssetsProvider(modPath));

    final message =
        'Checked ${assets.length} URL(s) of "${mod.displayName}": '
        '${invalid.isEmpty ? 'all reachable' : '${invalid.length} not reachable'}';
    if (invalid.isEmpty) {
      log.success(
        LogSource.urlCheck,
        message,
        modPath: modPath,
        operationId: ctx.operationId,
      );
    } else {
      log.warning(
        LogSource.urlCheck,
        message,
        details: invalid.join('\n'),
        modPath: modPath,
        operationId: ctx.operationId,
      );
    }
    return result;
  }

  /// The mod's stored invalid list with [url] added or removed according
  /// to [invalid] (the single-asset outcome), other entries untouched.
  Future<List<String>> _mergeStoredInvalidUrls(
    String modPath,
    String url,
    List<String> invalid,
  ) async {
    final current = await ref
        .read(appDatabaseProvider)
        .libraryQueries
        .assetsForMod(modPath);
    final stored = <String>[
      for (final asset in current)
        if (asset.invalid && asset.url != url) asset.url,
    ];
    if (invalid.contains(url)) stored.add(url);
    return List<String>.unmodifiable(stored);
  }
}
