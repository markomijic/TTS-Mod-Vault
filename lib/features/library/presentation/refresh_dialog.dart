import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Asks "Refresh all data?" with the "clear cache" checkbox and, when
/// confirmed, refreshes the library. Shared by the sidebar's Refresh
/// action and the F5 shortcut of the library page; completes when the
/// refresh has been started (or the dialog was cancelled).
Future<void> showRefreshDialog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final clearCache = await showConfirmDialogWithCheckbox(
    context,
    title: l10n.refreshDialogTitle,
    checkboxLabel: l10n.refreshClearCacheLabel,
    checkboxInfo: l10n.refreshClearCacheInfo,
    confirmLabel: l10n.actionRefresh,
  );
  if (clearCache == null || !context.mounted) return;
  await ref
      .read(libraryControllerProvider.notifier)
      .refresh(clearCache: clearCache);
}
