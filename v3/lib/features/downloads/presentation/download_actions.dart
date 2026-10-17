/// The download and URL-check entry points the buttons and menus call:
/// start the operation on the [DownloadsService], then show the result
/// (a snack bar for a clean download, a results dialog otherwise).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider, WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/url_checker.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';

/// Downloads every missing file of [mod].
Future<void> downloadModAssets(BuildContext context, WidgetRef ref, Mod mod) =>
    _runDownload(context, ref, (service) => service.downloadMod(mod));

/// Downloads the missing files of [type] of [mod].
Future<void> downloadModAssetsOfType(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
  AssetType type,
) => _runDownload(context, ref, (service) => service.downloadType(mod, type));

/// Downloads one missing [asset] of [mod].
Future<void> downloadSingleAsset(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
  Asset asset,
) => _runDownload(context, ref, (service) => service.downloadAsset(mod, asset));

/// Checks every asset URL of [mod] and shows the [UrlCheckResultsDialog].
Future<void> checkModUrls(BuildContext context, WidgetRef ref, Mod mod) async {
  final ui = OperationUi.of(context);
  final service = ref.read(downloadsServiceProvider);
  final result = await ui.launch(() => service.checkUrls(mod));
  if (result == null || !ui.mounted) return;
  await ui.showAppDialog<void>(
    (_) => UrlCheckResultsDialog(mod: mod, result: result),
  );
}

/// Answers whether one URL is reachable.
typedef SingleUrlCheck = Future<bool> Function(String url);

/// The quick single-URL check behind the asset menu's "Check URL": a HEAD /
/// ranged GET through [UrlChecker]. Not a runner operation (one request
/// needs no progress bar or cancel). Tests override it with a stub.
final singleUrlCheckProvider = Provider<SingleUrlCheck>((ref) {
  final checker = UrlChecker(dio: ref.watch(dioProvider));
  return checker.isLive;
});

/// Checks one URL right away through [singleUrlCheckProvider] and reports
/// with a snack bar. Port of v2's "Check URL" menu item.
Future<void> checkSingleUrl(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final ui = OperationUi.of(context);
  final live = await ref.read(singleUrlCheckProvider)(url);
  if (!ui.mounted) return;
  ui.showSnackBar(
    live ? ui.l10n.urlCheckSingleValid : ui.l10n.urlCheckSingleInvalid,
  );
}

Future<void> _runDownload(
  BuildContext context,
  WidgetRef ref,
  Future<DownloadBatchResult> Function(DownloadsService service) start,
) async {
  final ui = OperationUi.of(context);
  final service = ref.read(downloadsServiceProvider);
  final result = await ui.launch(() => start(service));
  if (result == null || !ui.mounted) return;
  if (result.failedCount == 0 && !result.wasCancelled) {
    ui.showSnackBar(ui.l10n.downloadedFilesCount(result.downloadedCount));
    return;
  }
  await ui.showAppDialog<void>((_) => DownloadResultsDialog(result: result));
}
