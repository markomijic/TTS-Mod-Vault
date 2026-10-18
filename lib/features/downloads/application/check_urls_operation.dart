/// Checks whether the asset URLs of one mod still answer and stores the dead
/// ones on the mod. Port of v2 `checkModUrlsLive`.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
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

/// Outcome of a [CheckUrlsOperation].
final class UrlCheckResult {
  /// Creates a result.
  const UrlCheckResult({
    required this.invalidUrls,
    required this.cancelled,
    required this.checked,
    required this.total,
  });

  /// URLs that did not answer. Partial when [cancelled].
  final List<String> invalidUrls;

  /// Whether the check was cancelled before every URL was tried; the
  /// partial result is then not persisted on the mod.
  final bool cancelled;

  /// URLs actually checked.
  final int checked;

  /// URLs the mod has.
  final int total;

  /// Whether every URL answered.
  bool get allLive => !cancelled && invalidUrls.isEmpty;

  @override
  String toString() =>
      'UrlCheckResult(checked=$checked/$total invalid=${invalidUrls.length}'
      '${cancelled ? ' cancelled' : ''})';
}

/// Checks every asset URL of [mod] (audio included or not by the same rule
/// as the asset list) with `concurrentDownloads` workers. On completion the
/// invalid URLs replace the mod's stored list (an empty list clears it), the
/// mod is re-summarised and its asset list invalidated; on cancellation the
/// partial result is returned without being persisted.
///
/// With [onlyAsset] (the asset menu's "Check URL") just that URL is checked
/// and its outcome is merged into the stored list: the URL is added when
/// dead and removed when live, the other entries are kept.
final class CheckUrlsOperation extends Operation<UrlCheckResult> {
  /// Creates the operation.
  CheckUrlsOperation({required this.ref, required this.mod, this.onlyAsset});

  /// Supplies the database, network client and library.
  final Ref ref;

  /// The mod whose URLs are checked.
  final Mod mod;

  /// When set, the one asset to check instead of the whole mod.
  final Asset? onlyAsset;

  final List<String> _invalid = [];
  int _checked = 0;
  int _total = 0;

  @override
  OperationKind get kind => OperationKind.checkUrls;

  @override
  UrlCheckResult? cancelledResult() => UrlCheckResult(
    invalidUrls: List.unmodifiable(_invalid),
    cancelled: true,
    checked: _checked,
    total: _total,
  );

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
    _total = assets.length;

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

    final checker = UrlChecker(dio: ref.read(dioProvider));
    var nextIndex = 0;
    void publish() => ctx.report(
      OperationProgress(
        kind: kind,
        label: checkUrlsProgressLabel,
        done: _checked,
        total: assets.length,
      ),
    );

    final workerCount = options.concurrentDownloads < 1
        ? 1
        : options.concurrentDownloads;
    await Future.wait(
      List.generate(workerCount, (_) async {
        while (!ctx.isCancelled && nextIndex < assets.length) {
          final asset = assets[nextIndex++];
          final bool live;
          try {
            live = await checker.isLive(asset.url, token: ctx.token);
          } on OperationCancelledException {
            return;
          }
          if (ctx.isCancelled) return;
          if (!live) {
            _invalid.add(asset.url);
            log.warning(
              LogSource.urlCheck,
              'URL is not reachable: ${asset.url}',
              details: 'type: ${asset.type.folderName}',
              modPath: modPath,
              url: asset.url,
              operationId: ctx.operationId,
            );
          }
          _checked++;
          publish();
        }
      }),
    );

    if (ctx.isCancelled) {
      log.warning(
        LogSource.urlCheck,
        'URL check of "${mod.displayName}" cancelled after $_checked/'
        '${assets.length} URL(s); result not saved',
        modPath: modPath,
        operationId: ctx.operationId,
      );
      return cancelledResult()!;
    }

    final invalid = List<String>.unmodifiable(_invalid);
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
    return UrlCheckResult(
      invalidUrls: invalid,
      cancelled: false,
      checked: _checked,
      total: assets.length,
    );
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
