import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/platform/file_explorer.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/replace_url_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Shows the asset context menu at [globalPosition]. Used by the URL rows
/// and, later, by the PDF thumbnails so both offer the same actions.
Future<void> showAssetContextMenu(
  BuildContext context,
  WidgetRef ref,
  Offset globalPosition,
  Mod mod,
  Asset asset,
) => showAppContextMenu(
  context,
  globalPosition,
  buildAssetContextMenu(context, ref, mod, asset),
);

/// The entries of the asset context menu (2.x `showAssetContextMenu`).
///
/// Live: open URL, copy URL, open file, open in file explorer, replace URL,
/// download (missing files only), check URL, shared with, delete file.
/// Service errors surface as a snack bar with the failure message.
List<MenuEntry> buildAssetContextMenu(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
  Asset asset,
) {
  final l10n = AppLocalizations.of(context);
  // Read synchronously: the menu callbacks run after the row may be gone.
  final service = ref.read(modEditServiceProvider);
  final path = asset.path;

  return [
    MenuAction(
      label: l10n.assetMenuOpenUrl,
      icon: Icons.open_in_browser,
      onPressed: () => _openUrl(context, asset.url),
    ),
    MenuAction(
      label: l10n.assetMenuCopyUrl,
      icon: Icons.content_copy,
      onPressed: () => _copy(context, asset.url),
    ),
    if (path != null) ...[
      MenuAction(
        label: l10n.assetMenuOpenFile,
        icon: Icons.file_open_outlined,
        onPressed: () => _openFile(context, path),
      ),
      MenuAction(
        label: l10n.menuOpenInFileExplorer,
        icon: Icons.folder_open_outlined,
        onPressed: () => _openInFileExplorer(context, path),
      ),
    ],
    const MenuDivider(),
    MenuAction(
      label: l10n.assetMenuReplaceUrl,
      icon: Icons.find_replace,
      onPressed: () => showReplaceUrlDialog(context, mod: mod, asset: asset),
    ),
    if (path == null)
      MenuAction(
        label: l10n.menuDownload,
        icon: Icons.download_outlined,
        onPressed: () => downloadSingleAsset(context, ref, mod, asset),
      ),
    MenuAction(
      label: l10n.assetMenuCheckUrl,
      icon: Icons.link,
      onPressed: () => checkSingleUrl(context, ref, asset.url),
    ),
    MenuAction(
      label: l10n.assetMenuSharedWith,
      icon: Icons.share_outlined,
      onPressed: () => _showSharedWith(context, service, mod, asset),
    ),
    if (path != null) ...[
      const MenuDivider(),
      MenuAction(
        label: l10n.assetMenuDeleteFile,
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: () => _deleteFile(context, service, mod, asset),
      ),
    ],
  ];
}

/// "3 mods, 1 save" from a sharing map, in [ModType] order.
String sharedAssetCounts(
  AppLocalizations l10n,
  Map<ModType, List<String>> sharing,
) => [
  for (final type in ModType.values)
    if (sharing[type] case final names? when names.isNotEmpty)
      type.count(l10n, names.length),
].join(l10n.listSeparator);

Future<void> _openUrl(BuildContext context, String url) async {
  var raw = url.trim();
  if (!raw.contains('://')) raw = 'https://$raw';
  final uri = Uri.tryParse(raw);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri);
    } on Object {
      ok = false;
    }
  }
  if (ok || !context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).couldNotOpenUrl(url));
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).copiedToClipboard);
}

Future<void> _openFile(BuildContext context, String path) async {
  String? reason;
  try {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) reason = result.message;
  } on Object catch (error) {
    reason = error.toString();
  }
  if (reason == null || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFile(reason),
  );
}

Future<void> _openInFileExplorer(BuildContext context, String path) async {
  final ok = await openInFileExplorer(path);
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFileExplorer,
  );
}

Future<void> _showSharedWith(
  BuildContext context,
  ModEditService service,
  Mod mod,
  Asset asset,
) async {
  final sharing = await service.modsSharingAsset(mod, asset);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _SharedWithDialog(sharing: sharing),
  );
}

Future<void> _deleteFile(
  BuildContext context,
  ModEditService service,
  Mod mod,
  Asset asset,
) async {
  final l10n = AppLocalizations.of(context);
  final sharing = await service.modsSharingAsset(mod, asset);
  if (!context.mounted) return;

  final shared = sharing.values.any((names) => names.isNotEmpty);
  final message = shared
      ? l10n.deleteSharedAssetFileMessage(
          l10n.sharedAssetSummary(sharedAssetCounts(l10n, sharing)),
        )
      : l10n.deleteAssetFileMessage(p.basename(asset.path ?? asset.url));
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.deleteAssetFileTitle,
    message: message,
    confirmLabel: l10n.menuDelete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final result = await service.deleteAssetFile(mod, asset);
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    result.when(
      ok: (_) => l10n.assetFileDeleted,
      err: (failure) => failure.message,
    ),
  );
}

/// Lists the mods, saves and saved objects that reference the same file.
class _SharedWithDialog extends StatelessWidget {
  const _SharedWithDialog({required this.sharing});

  final Map<ModType, List<String>> sharing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shared = sharing.values.any((names) => names.isNotEmpty);

    return AppDialog(
      title: l10n.sharedAssetTitle,
      content: shared
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sharedAssetSummary(sharedAssetCounts(l10n, sharing)),
                  ),
                  for (final type in ModType.values)
                    if (sharing[type] case final names?
                        when names.isNotEmpty) ...[
                      Gaps.h16,
                      Text(type.title(l10n), style: theme.textTheme.titleSmall),
                      Gaps.h4,
                      for (final name in names) Text(name),
                    ],
                ],
              ),
            )
          : Text(l10n.sharedAssetNotShared),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
