import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/platform/file_explorer.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_page.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/delete_mod_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/rename_mod_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/save_as_mod_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Steam Workshop item page for a numeric Workshop id.
Uri steamWorkshopPageUri(String id) =>
    Uri.https('steamcommunity.com', '/sharedfiles/filedetails/', {'id': id});

/// Whether [mod] has a numeric Workshop id (the Workshop page can be opened).
bool hasWorkshopId(Mod mod) => int.tryParse(mod.id) != null;

/// Shows the mod context menu at [globalPosition].
///
/// The item list and conditions are 2.x `showModContextMenu`. Live since
/// Phase 1: copy name/filename, open in file explorer, open the Workshop
/// page, open the backup in file explorer. Live since Phase 2: view images,
/// rename, delete, save as mod. Download, update from Workshop, import
/// backup and delete backup still show a "not implemented" snack bar until
/// Phases 3 and 4 replace their callbacks in [buildModContextMenu]; the
/// list itself stays.
Future<void> showModContextMenu(
  BuildContext context,
  WidgetRef ref,
  Offset globalPosition,
  Mod mod,
) => showAppContextMenu(
  context,
  globalPosition,
  buildModContextMenu(context, ref, mod),
);

/// The entries of the mod context menu for [mod].
List<MenuEntry> buildModContextMenu(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
) {
  final l10n = AppLocalizations.of(context);
  final type = mod.ref.type;
  final backup = mod.backup;

  void stub(String label) => _notImplemented(context, label);

  return [
    if (mod.missingCount > 0)
      MenuAction(
        label: l10n.menuDownload,
        icon: Icons.download_outlined,
        onPressed: () => stub(l10n.menuDownload),
      ),
    MenuAction(
      label: l10n.menuViewImages,
      icon: Icons.image_outlined,
      onPressed: () => openImagesViewer(context, mod),
    ),
    MenuAction(
      label: l10n.menuOpenInFileExplorer,
      icon: Icons.folder_open_outlined,
      onPressed: () => _openInFileExplorer(context, mod.jsonPath),
    ),
    if (type == ModType.mod) ...[
      MenuAction(
        label: l10n.menuOpenSteamWorkshopPage,
        icon: Icons.open_in_browser,
        enabled: hasWorkshopId(mod),
        onPressed: () => _openUrl(context, steamWorkshopPageUri(mod.id)),
      ),
      MenuAction(
        label: l10n.menuUpdateFromWorkshop,
        icon: Icons.update,
        onPressed: () => stub(l10n.menuUpdateFromWorkshop),
      ),
    ],
    if (type == ModType.save)
      MenuAction(
        label: l10n.menuSaveAsMod,
        icon: Icons.drive_file_move_outlined,
        onPressed: () => showSaveAsModDialog(context, mod),
      ),
    MenuAction(
      label: l10n.menuCopyName,
      icon: Icons.content_copy,
      onPressed: () => _copy(context, mod.displayName),
    ),
    MenuAction(
      label: l10n.menuCopyFilename,
      icon: Icons.file_copy_outlined,
      onPressed: () => _copy(context, mod.ref.fileName),
    ),
    MenuAction(
      label: l10n.menuRename(type.singular(l10n)),
      icon: Icons.drive_file_rename_outline,
      onPressed: () => showRenameModDialog(context, mod),
    ),
    MenuAction(
      label: l10n.menuDelete,
      icon: Icons.delete_outline,
      destructive: true,
      onPressed: () => showDeleteModDialog(context, ref, mod),
    ),
    if (backup != null) ...[
      const MenuDivider(),
      MenuAction(
        label: l10n.menuImportBackup,
        icon: Icons.unarchive_outlined,
        onPressed: () => stub(l10n.menuImportBackup),
      ),
      MenuAction(
        label: l10n.menuOpenBackupInFileExplorer,
        icon: Icons.folder_open_outlined,
        onPressed: () => _openInFileExplorer(context, backup.path),
      ),
      MenuAction(
        label: l10n.menuCopyBackupFilename,
        icon: Icons.file_copy_outlined,
        onPressed: () =>
            _copy(context, p.basenameWithoutExtension(backup.fileName)),
      ),
      MenuAction(
        label: l10n.menuDeleteBackup,
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: () => stub(l10n.menuDeleteBackup),
      ),
    ],
  ];
}

void _notImplemented(BuildContext context, String label) {
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).notImplementedAction(label),
  );
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).copiedToClipboard);
}

Future<void> _openInFileExplorer(BuildContext context, String path) async {
  final ok = await openInFileExplorer(path);
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFileExplorer,
  );
}

Future<void> _openUrl(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } on Object {
    ok = false;
  }
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenUrl(uri.toString()),
  );
}
