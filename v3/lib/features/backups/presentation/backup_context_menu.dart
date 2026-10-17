import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Shows the backup context menu at [globalPosition].
///
/// The items are 2.x `showBackupContextMenu`: import backup, open in file
/// explorer, copy filename, delete backup. Open and copy are live; import
/// and delete show the "not implemented" snack bar until Phase 4 replaces
/// their callbacks in [buildBackupContextMenu].
Future<void> showBackupContextMenu(
  BuildContext context,
  WidgetRef ref,
  Offset globalPosition,
  Backup backup,
) => showAppContextMenu(
  context,
  globalPosition,
  buildBackupContextMenu(context, backup),
);

/// The entries of the backup context menu for [backup].
List<MenuEntry> buildBackupContextMenu(BuildContext context, Backup backup) {
  final l10n = AppLocalizations.of(context);
  return [
    MenuAction(
      label: l10n.menuImportBackup,
      icon: Icons.unarchive_outlined,
      onPressed: () => showNotImplemented(context, l10n.menuImportBackup),
    ),
    MenuAction(
      label: l10n.menuOpenInFileExplorer,
      icon: Icons.folder_open_outlined,
      onPressed: () => revealInFileExplorer(context, backup.path),
    ),
    MenuAction(
      label: l10n.menuCopyFilename,
      icon: Icons.file_copy_outlined,
      onPressed: () => copyTextToClipboard(context, backupCopyName(backup)),
    ),
    MenuAction(
      label: l10n.menuDeleteBackup,
      icon: Icons.delete_outline,
      destructive: true,
      onPressed: () => showNotImplemented(context, l10n.menuDeleteBackup),
    ),
  ];
}

/// What "Copy filename" puts on the clipboard: the file name without its
/// `.ttsmod` extension (2.x behaviour).
String backupCopyName(Backup backup) =>
    p.basenameWithoutExtension(backup.fileName);
