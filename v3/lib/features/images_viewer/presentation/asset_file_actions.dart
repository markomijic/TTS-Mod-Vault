import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/platform/file_explorer.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The last path segment of [url], used as a short caption for an asset
/// tile: `https://host/ugc/123/ABC/` yields `ABC`. Query strings and
/// trailing slashes are ignored; a URL without a usable segment is returned
/// unchanged.
String urlTail(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url;
  for (final segment in uri.pathSegments.reversed) {
    if (segment.isNotEmpty) return segment;
  }
  return url;
}

/// Opens the file at [path] with the OS default application; a snack bar
/// reports failure. Port of 2.x `openFile`.
Future<void> openAssetFile(BuildContext context, String path) async {
  final normalized = p.normalize(path);
  var ok = false;
  try {
    final result = await OpenFilex.open(normalized);
    ok = result.type == ResultType.done;
  } on Object {
    ok = false;
  }
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFile(normalized),
  );
}

/// Shows the small menu shared by PDF thumbnails and image tiles: open the
/// file, reveal it in the file explorer, copy the URL. The file actions are
/// disabled when the asset is not on disk.
Future<void> showAssetFileMenu(
  BuildContext context,
  Offset globalPosition,
  Asset asset,
) {
  final l10n = AppLocalizations.of(context);
  final path = asset.path;
  return showAppContextMenu(context, globalPosition, [
    MenuAction(
      label: l10n.assetMenuOpenFile,
      icon: Icons.file_open_outlined,
      onPressed: path == null ? null : () => openAssetFile(context, path),
    ),
    MenuAction(
      label: l10n.menuOpenInFileExplorer,
      icon: Icons.folder_open_outlined,
      onPressed: path == null ? null : () => _reveal(context, path),
    ),
    MenuAction(
      label: l10n.assetMenuCopyUrl,
      icon: Icons.link,
      onPressed: () => _copy(context, asset.url),
    ),
  ]);
}

Future<void> _reveal(BuildContext context, String path) async {
  final ok = await openInFileExplorer(path);
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFileExplorer,
  );
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).copiedToClipboard);
}
