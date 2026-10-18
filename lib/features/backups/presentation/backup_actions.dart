/// The backup entry points the buttons and menus call (plan Phase 4):
/// create a backup of a mod, import `.ttsmod` archives, delete and rename
/// a backup. Each one starts on the `BackupService`, then shows the result
/// through [OperationUi] so it survives the launching widget being swapped
/// for the progress bar.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/import_results_dialog.dart';
import 'package:tts_mod_vault/features/backups/presentation/json_conflict_dialog.dart';
import 'package:tts_mod_vault/features/backups/presentation/rename_backup_dialog.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';

/// What the user picked in the "backup already exists" dialog.
enum BackupLocationChoice {
  /// Open the folder picker and write the backup elsewhere.
  selectNewFolder,

  /// Overwrite the existing archive.
  replace,
}

// --- create ---------------------------------------------------------------

/// Backs up [mod] (2.x single-mod backup flow):
///
/// * no backups folder and no current backup → folder picker, then a
///   confirmation with "use this folder as the default backups folder";
/// * the archive already exists at the target, or the mod's current backup
///   lives in another folder → Cancel / Select new folder / Replace;
/// * then `createBackup` on the runner, and a snack bar with the file name
///   or the error.
///
/// [targetDir] pre-selects the folder (the bulk flows pass the one folder
/// they picked for every mod).
Future<void> backupMod(
  BuildContext context,
  WidgetRef ref,
  Mod mod, {
  String? targetDir,
}) async {
  // Read everything before the first await: the launching widget is
  // replaced by the progress bar once the operation starts.
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(backupServiceProvider);
  final picker = ref.read(directoryPickerProvider);
  final directories = ref.read(directoriesProvider.notifier);

  Future<String?> pickFolder(String? initial) async {
    try {
      final picked = await picker.pickDirectory(
        dialogTitle: l10n.backupPickFolderTitle,
        initialDirectory: initial == null || initial.isEmpty ? null : initial,
      );
      return picked == null ? null : p.normalize(picked);
    } on Object {
      ui.showSnackBar(l10n.couldNotOpenFolderPicker);
      return null;
    }
  }

  var chosenDir = targetDir;
  var setAsDefault = false;
  var keepBoth = false;
  var replaceConfirmed = false;
  BackupTarget target;
  while (true) {
    target = await service.backupTargetFor(mod, chosenDir: chosenDir);
    if (!ui.mounted) return;

    if (target.dir.isEmpty) {
      final picked = await pickFolder(null);
      if (picked == null || !ui.mounted) return;
      final useAsDefault = await _confirmFolder(ui, mod, picked);
      if (useAsDefault == null || !ui.mounted) return;
      setAsDefault = useAsDefault;
      chosenDir = picked;
      continue;
    }

    if (replaceConfirmed) break;

    final BackupLocationChoice? choice;
    if (target.replacesExisting) {
      choice = await _askLocation(
        ui,
        title: l10n.backupExistsTitle,
        message: l10n.backupExistsMessage(target.fileName, target.dir),
      );
    } else if (target.currentBackupElsewhere && !keepBoth) {
      choice = await _askLocation(
        ui,
        title: l10n.backupElsewhereTitle,
        message: l10n.backupElsewhereMessage(
          mod.displayName,
          target.currentBackup!.path,
        ),
      );
      if (choice == BackupLocationChoice.replace) {
        // Replace the current backup where it lives.
        chosenDir = p.dirname(target.currentBackup!.path);
        replaceConfirmed = true;
        continue;
      }
    } else {
      break;
    }
    if (choice == null || !ui.mounted) return;
    if (choice == BackupLocationChoice.replace) break;
    final picked = await pickFolder(target.dir);
    if (picked == null || !ui.mounted) return;
    chosenDir = picked;
    keepBoth = true;
  }

  final BackupResult? result;
  try {
    result = await ui.launch(
      () => service.createBackup(mod, targetDir: target.dir),
    );
  } on Object catch (error) {
    ui.showSnackBar(l10n.backupFailed(error.toString()));
    return;
  }
  if (result == null) return;
  if (setAsDefault) await directories.setBackupsDir(target.dir);
  ui.showSnackBar(l10n.backupCreated(result.backup.fileName));
}

/// "Back up to this folder?" with the default-folder checkbox; null when
/// cancelled.
Future<bool?> _confirmFolder(OperationUi ui, Mod mod, String folder) {
  if (!ui.mounted) return Future.value();
  final l10n = ui.l10n;
  return showConfirmDialogWithCheckbox(
    ui.context,
    title: l10n.backupToFolderTitle,
    message: l10n.backupToFolderMessage(mod.displayName, folder),
    checkboxLabel: l10n.backupSetDefaultFolder,
    checkboxInfo: l10n.backupSetDefaultFolderInfo,
    confirmLabel: l10n.actionBackup,
  );
}

Future<BackupLocationChoice?> _askLocation(
  OperationUi ui, {
  required String title,
  required String message,
}) {
  if (!ui.mounted) return Future.value();
  final l10n = ui.l10n;
  return showChoiceDialog<BackupLocationChoice>(
    ui.context,
    title: title,
    message: message,
    choices: [
      DialogChoice(
        label: l10n.backupSelectNewFolder,
        value: BackupLocationChoice.selectNewFolder,
      ),
      DialogChoice(
        label: l10n.backupReplace,
        value: BackupLocationChoice.replace,
        destructive: true,
      ),
    ],
  );
}

// --- import ---------------------------------------------------------------

/// Sidebar "Import backups": picks `.ttsmod` files (starting in the
/// backups folder) and imports them.
Future<void> importBackupsFromPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final ui = OperationUi.of(context);
  final service = ref.read(backupServiceProvider);
  final picker = ref.read(filePickerServiceProvider);
  final backupsDir = ref.read(directoriesProvider).value?.backupsDir;

  final List<String> paths;
  try {
    paths = await picker.pickTtsmodFiles(
      dialogTitle: ui.l10n.importBackupsPickTitle,
      initialDirectory: backupsDir == null || backupsDir.isEmpty
          ? null
          : backupsDir,
    );
  } on Object {
    ui.showSnackBar(ui.l10n.couldNotOpenFilePicker);
    return;
  }
  if (paths.isEmpty || !ui.mounted) return;
  await runImportBackups(ui, service, paths);
}

/// Imports one [backup] (backups tab, mod context menu). The JSON goes to
/// the folder of the matching mod when there is one, so a mod moved into a
/// sub-folder is not duplicated; [targetJsonDir] overrides that.
Future<void> importBackup(
  BuildContext context,
  WidgetRef ref,
  Backup backup, {
  String? targetJsonDir,
}) {
  final ui = OperationUi.of(context);
  final service = ref.read(backupServiceProvider);
  final matching = backup.matchingModPath;
  return runImportBackups(
    ui,
    service,
    [backup.path],
    targetJsonDir:
        targetJsonDir ?? (matching == null ? null : p.dirname(matching)),
  );
}

/// Imports [backups] one after another (the "Import selected" button).
/// Each archive resolves its own JSON folder.
Future<void> importBackups(
  BuildContext context,
  WidgetRef ref,
  List<Backup> backups,
) {
  if (backups.isEmpty) return Future.value();
  final ui = OperationUi.of(context);
  final service = ref.read(backupServiceProvider);
  return runImportBackups(ui, service, [for (final b in backups) b.path]);
}

/// Runs `importBackups` on [service] for [paths], answering JSON conflicts
/// with [showJsonConflictDialog], then shows the [ImportResultsDialog] when
/// any archive failed or was skipped and a snack bar otherwise.
Future<void> runImportBackups(
  OperationUi ui,
  BackupService service,
  List<String> paths, {
  String? targetJsonDir,
}) async {
  final l10n = ui.l10n;
  final ImportBackupsResult? result;
  try {
    result = await ui.launch(
      () => service.importBackups(
        paths,
        targetJsonDir: targetJsonDir,
        onJsonConflict: (conflict) => ui.mounted
            ? showJsonConflictDialog(ui.context, conflict)
            : Future.value(JsonConflictChoice.cancel),
      ),
    );
  } on Object catch (error) {
    ui.showSnackBar(l10n.importFailed(error.toString()));
    return;
  }
  if (result == null || !ui.mounted) return;
  if (importNeedsReport(result, paths)) {
    await ui.showAppDialog<void>(
      (_) => ImportResultsDialog(result: result!, paths: paths),
    );
    return;
  }
  ui.showSnackBar(l10n.importedBackupsCount(result.imported));
}

/// Whether [result] has anything the snack bar cannot say: a failed or
/// skipped archive, a cancelled run or archives not reached.
bool importNeedsReport(ImportBackupsResult result, List<String> paths) =>
    result.cancelled ||
    result.results.length < paths.length ||
    result.results.any((r) => !r.succeeded);

// --- delete / rename ------------------------------------------------------

/// Asks for confirmation and deletes [backup]; the outcome is a snack bar.
Future<void> deleteBackupWithConfirm(
  BuildContext context,
  WidgetRef ref,
  Backup backup,
) async {
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(backupServiceProvider);
  final confirmed = await showConfirmDialog(
    ui.context,
    title: l10n.deleteBackupTitle,
    message: l10n.deleteBackupMessage(backup.fileName),
    confirmLabel: l10n.menuDelete,
    destructive: true,
  );
  if (!confirmed || !ui.mounted) return;
  final result = await service.deleteBackup(backup);
  if (!ui.mounted) return;
  ui.showSnackBar(
    result.when(
      ok: (_) => l10n.deletedBackup(backup.fileName),
      err: (failure) => failure.message,
    ),
  );
}

/// Opens the [RenameBackupDialog] for [backup]; completes when it closes.
Future<void> renameBackupWithDialog(BuildContext context, Backup backup) =>
    showDialog<void>(
      context: context,
      builder: (_) => RenameBackupDialog(backup: backup),
    );
