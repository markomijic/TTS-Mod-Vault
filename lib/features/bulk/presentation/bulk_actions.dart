/// The bulk entry points the bulk actions menu and the multi-select view
/// call (plan Phase 5): confirm with counts, run on the `BulkService`
/// through [OperationUi.launch], then a summary snack bar, or a results
/// dialog when something failed.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_backup_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_delete_assets_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_failures_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_validation_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

export 'package:tts_mod_vault/features/url_updates/presentation/update_urls_dialog.dart'
    show updateUrlsWithDialog;

/// "12 mods" / "1 save": the count of [mods] with the noun of their type
/// (bulk targets always share one type: one tab, one selection).
String bulkModsLabel(AppLocalizations l10n, List<Mod> mods) =>
    mods.first.ref.type.count(l10n, mods.length);

/// Downloads the missing files of [mods] after a confirmation.
Future<void> runBulkDownload(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(bulkServiceProvider);
  final label = bulkModsLabel(l10n, mods);

  final confirmed = await showConfirmDialog(
    context,
    title: l10n.bulkDownloadConfirmTitle,
    message: l10n.bulkDownloadConfirmMessage(label),
    confirmLabel: l10n.menuDownload,
  );
  if (!confirmed || !ui.mounted) return;

  final result = await ui.launch(() => service.downloadMods(mods));
  if (result == null || !ui.mounted) return;

  var summary = l10n.bulkDownloadDone(result.downloadedFiles, label);
  if (result.failedFiles > 0) {
    summary = l10n.bulkFilesFailedSuffix(summary, result.failedFiles);
  }
  if (result.cancelled) {
    summary = l10n.bulkCancelledSuffix(
      summary,
      result.modsProcessed,
      mods.length,
    );
  }
  await _report(
    ui,
    title: l10n.menuDownload,
    summary: summary,
    failures: [
      for (final outcome in result.outcomes)
        if (outcome.failed)
          (name: outcome.mod.displayName, detail: outcome.error)
        else if (outcome.value case final value? when value.failedCount > 0)
          (
            name: outcome.mod.displayName,
            detail: l10n.bulkFilesFailedDetail(value.failedCount),
          ),
    ],
  );
  if (!ui.mounted) return;
  await showDownloadValidationResults(ui, result.validations);
}

/// Backs up [mods] with the choices of the [BulkBackupDialog]; with
/// [downloadFirst] each mod's missing files are downloaded before its
/// backup is written.
Future<void> runBulkBackup(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods, {
  bool downloadFirst = false,
}) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(bulkServiceProvider);
  final label = bulkModsLabel(l10n, mods);
  final title = downloadFirst ? l10n.bulkDownloadAndBackup : l10n.actionBackup;

  final choice = await showBulkBackupDialog(
    context,
    title: title,
    message: downloadFirst
        ? l10n.bulkDownloadAndBackupMessage(label)
        : l10n.bulkBackupMessage(label),
  );
  if (choice == null || !ui.mounted) return;

  if (downloadFirst) {
    final result = await ui.launch(
      () => service.downloadAndBackupMods(
        mods,
        folder: choice.folder,
        behavior: choice.behavior,
        postBackupDeletion: choice.postBackupDeletion,
        setAsDefaultFolder: choice.setAsDefaultFolder,
      ),
    );
    if (result == null || !ui.mounted) return;
    var summary = l10n.bulkDownloadAndBackupDone(
      result.downloadedFiles,
      result.backedUp,
    );
    if (result.failedFiles > 0) {
      summary = l10n.bulkFilesFailedSuffix(summary, result.failedFiles);
    }
    if (result.skipped > 0) {
      summary = l10n.bulkSkippedSuffix(summary, result.skipped);
    }
    if (result.filesDeleted > 0) {
      summary = l10n.bulkFilesDeletedSuffix(summary, result.filesDeleted);
    }
    if (result.cancelled) {
      summary = l10n.bulkCancelledSuffix(
        summary,
        result.modsProcessed,
        mods.length,
      );
    }
    await _report(
      ui,
      title: title,
      summary: summary,
      failures: [
        for (final outcome in result.outcomes)
          if (outcome.failed)
            (name: outcome.mod.displayName, detail: outcome.error)
          else if (outcome.value case final value?
              when value.download.failedCount > 0)
            (
              name: outcome.mod.displayName,
              detail: l10n.bulkFilesFailedDetail(value.download.failedCount),
            ),
      ],
    );
    if (!ui.mounted) return;
    await showDownloadValidationResults(ui, result.validations);
    return;
  }

  final result = await ui.launch(
    () => service.backupMods(
      mods,
      folder: choice.folder,
      behavior: choice.behavior,
      postBackupDeletion: choice.postBackupDeletion,
      setAsDefaultFolder: choice.setAsDefaultFolder,
    ),
  );
  if (result == null || !ui.mounted) return;
  var summary = l10n.bulkBackupDone(result.backedUp);
  if (result.skipped > 0) {
    summary = l10n.bulkSkippedSuffix(summary, result.skipped);
  }
  if (result.filesDeleted > 0) {
    summary = l10n.bulkFilesDeletedSuffix(summary, result.filesDeleted);
  }
  if (result.deleteFailed > 0) {
    summary = l10n.deleteFailedSuffix(summary, result.deleteFailed);
  }
  if (result.cancelled) {
    summary = l10n.bulkCancelledSuffix(
      summary,
      result.modsProcessed,
      mods.length,
    );
  }
  await _report(
    ui,
    title: title,
    summary: summary,
    failures: _failedOutcomes(result.outcomes),
  );
}

/// Deletes the cached files of [mods] in the scope the
/// [BulkDeleteAssetsDialog] returns.
Future<void> runBulkDeleteAssets(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(bulkServiceProvider);
  final label = bulkModsLabel(l10n, mods);

  final scope = await showBulkDeleteAssetsDialog(
    context,
    message: l10n.bulkDeleteAssetsMessage(label),
  );
  if (scope == null || !ui.mounted) return;

  final result = await ui.launch(
    () => service.deleteModAssets(mods, scope: scope),
  );
  if (result == null || !ui.mounted) return;
  var summary = l10n.deleteAssetsDone(result.filesDeleted);
  if (result.deleteFailed > 0) {
    summary = l10n.deleteFailedSuffix(summary, result.deleteFailed);
  }
  if (result.cancelled) {
    summary = l10n.bulkCancelledSuffix(
      summary,
      result.modsProcessed,
      mods.length,
    );
  }
  await _report(
    ui,
    title: l10n.actionDeleteAssets,
    summary: summary,
    failures: _failedOutcomes(result.outcomes),
  );
}

/// Checks every asset URL of [mods] after a confirmation and shows the
/// [BulkUrlCheckResultsDialog].
Future<void> runBulkCheckUrls(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(bulkServiceProvider);

  final confirmed = await showConfirmDialog(
    context,
    title: l10n.bulkCheckUrlsTitle,
    message: l10n.bulkCheckUrlsMessage(bulkModsLabel(l10n, mods)),
    confirmLabel: l10n.actionCheckUrls,
  );
  if (!confirmed || !ui.mounted) return;

  final result = await ui.launch(() => service.checkUrls(mods));
  if (result == null || !ui.mounted) return;
  await ui.showAppDialog<void>(
    (_) => BulkUrlCheckResultsDialog(result: result),
  );
}

/// Updates [mods] from the Steam Workshop after the confirmation with the
/// "Force update" option, then shows the [WorkshopUpdateResultsDialog].
Future<void> runBulkUpdateWorkshop(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(bulkServiceProvider);

  final force = await showConfirmDialogWithCheckbox(
    context,
    title: l10n.workshopUpdateConfirmTitle,
    message: mods.length == 1
        ? l10n.workshopUpdateConfirmOne(mods.single.displayName)
        : l10n.workshopUpdateConfirmMany(mods.length),
    checkboxLabel: l10n.workshopForceUpdate,
    checkboxInfo: l10n.workshopForceUpdateInfo,
    confirmLabel: l10n.workshopUpdateAction,
  );
  if (force == null || !ui.mounted) return;

  final result = await ui.launch(
    () => service.updateWorkshopMods(mods, force: force),
  );
  if (result == null || !ui.mounted) return;
  await ui.showAppDialog<void>(
    (_) => WorkshopUpdateResultsDialog(result: result),
  );
}

List<BulkFailure> _failedOutcomes<R>(List<BulkModOutcome<R>> outcomes) => [
  for (final outcome in outcomes)
    if (outcome.failed) (name: outcome.mod.displayName, detail: outcome.error),
];

/// A snack bar with [summary], or the [BulkFailuresDialog] when there are
/// [failures].
Future<void> _report(
  OperationUi ui, {
  required String title,
  required String summary,
  required List<BulkFailure> failures,
}) async {
  if (failures.isEmpty) {
    ui.showSnackBar(summary);
    return;
  }
  await ui.showAppDialog<void>(
    (_) =>
        BulkFailuresDialog(title: title, summary: summary, failures: failures),
  );
}
