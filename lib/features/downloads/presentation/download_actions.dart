/// The download and URL-check entry points the buttons and menus call:
/// start the operation on the [DownloadsService], then show the result
/// (a snack bar for a clean download, a results dialog otherwise).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_validation_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';

/// Downloads every missing file of [mod], then checks the files still
/// missing (2.x `051741c`) and shows a [DownloadValidationDialog] when a
/// host was unreachable or a URL is dead.
Future<void> downloadModAssets(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
) async {
  final ui = OperationUi.of(context);
  final result = await _runDownload(
    context,
    ref,
    (service) => service.downloadMod(mod),
  );
  if (result == null || result.wasCancelled || !ui.mounted) return;
  final validation = await ui.launch(
    () => ref.read(downloadsServiceProvider).validateDownload(mod),
  );
  if (validation == null || !ui.mounted) return;
  await showDownloadValidationResults(ui, [validation]);
}

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

/// Checks one [asset] URL of [mod] as a one-asset runner operation (so it
/// shows in the progress bar, can be cancelled and updates the stored
/// invalid flag) and reports with a snack bar. Port of v2's "Check URL"
/// menu item; a cancelled check says nothing.
Future<void> checkSingleUrl(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
  Asset asset,
) async {
  final ui = OperationUi.of(context);
  final service = ref.read(downloadsServiceProvider);
  final result = await ui.launch(() => service.checkUrl(mod, asset));
  if (result == null || result.cancelled || !ui.mounted) return;
  ui.showSnackBar(
    result.unreachableDomains.isNotEmpty
        ? ui.l10n.urlCheckSingleUnreachable
        : result.invalidUrls.isEmpty
        ? ui.l10n.urlCheckSingleValid
        : ui.l10n.urlCheckSingleInvalid,
  );
}

/// Runs a download and reports it; returns its result, or null when it did
/// not run or the widget went away.
Future<DownloadBatchResult?> _runDownload(
  BuildContext context,
  WidgetRef ref,
  Future<DownloadBatchResult> Function(DownloadsService service) start,
) async {
  final ui = OperationUi.of(context);
  final service = ref.read(downloadsServiceProvider);
  final result = await ui.launch(() => start(service));
  if (result == null || !ui.mounted) return null;
  if (result.failedCount == 0 && !result.wasCancelled) {
    ui.showSnackBar(ui.l10n.downloadedFilesCount(result.downloadedCount));
    return result;
  }
  await ui.showAppDialog<void>((_) => DownloadResultsDialog(result: result));
  return result;
}
