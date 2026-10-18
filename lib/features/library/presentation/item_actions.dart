/// Small actions shared by the mod and backup context menus and panels.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/platform/file_explorer.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Shows the "not implemented" snack bar for the action called [label].
void showNotImplemented(BuildContext context, String label) {
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).notImplementedAction(label),
  );
}

/// Puts [text] on the clipboard and confirms with a snack bar.
Future<void> copyTextToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppSnackBar(context, AppLocalizations.of(context).copiedToClipboard);
}

/// Reveals [path] in the OS file manager; a failure shows a snack bar.
Future<void> revealInFileExplorer(BuildContext context, String path) async {
  final ok = await openInFileExplorer(path);
  if (ok || !context.mounted) return;
  showAppSnackBar(
    context,
    AppLocalizations.of(context).couldNotOpenFileExplorer,
  );
}
