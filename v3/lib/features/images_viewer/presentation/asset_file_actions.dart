import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
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
