import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_actions.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/delete_mod_assets_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';
import 'package:tts_mod_vault/features/url_updates/presentation/update_urls_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Bottom of the selected-mod view: the action buttons, or, while an
/// operation runs, the [OperationProgressSlot].
class SelectedModBottomBar extends ConsumerWidget {
  /// Creates the bar for [mod].
  const SelectedModBottomBar({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(operationRunningProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.sm,
        Insets.sm,
      ),
      child: running
          ? const OperationProgressSlot()
          : SelectedModActions(mod: mod),
    );
  }
}

/// The bottom bar's progress slot: the [OperationProgressBar] bound to the
/// operations engine (label, determinate progress, Cancel). While a library
/// refresh runs (not a runner operation) the bar shows its idle placeholder.
class OperationProgressSlot extends StatelessWidget {
  /// Creates the slot.
  const OperationProgressSlot({super.key});

  @override
  Widget build(BuildContext context) =>
      const OperationProgressBar(showWhenIdle: true);
}

/// The per-mod action buttons (2.x `SelectedModActionButtons` plus the
/// items of its overflow menu): "Download all" (disabled when nothing is
/// missing), "Backup", "Check URLs", "Copy missing URLs" (disabled when
/// nothing is missing), "Delete assets" and "Update URLs".
class SelectedModActions extends ConsumerWidget {
  /// Creates the buttons for [mod].
  const SelectedModActions({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final running = ref.watch(operationRunningProvider);

    final scheme = Theme.of(context).colorScheme;
    final missing = mod.missingCount > 0;

    Future<void> copyMissingUrls() async {
      final assets = await ref.read(modAssetsProvider(mod.jsonPath).future);
      if (!context.mounted) return;
      await copyTextToClipboard(context, missingUrlsText(assets));
    }

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        // One prominent action: Download all while assets are missing,
        // otherwise Backup; the rest stay secondary.
        _ActionButton(
          primary: missing,
          onPressed: missing && !running
              ? () => downloadModAssets(context, ref, mod)
              : null,
          icon: Icons.download_outlined,
          label: l10n.actionDownloadAll,
        ),
        _ActionButton(
          primary: !missing,
          onPressed: running ? null : () => backupMod(context, ref, mod),
          icon: Icons.archive_outlined,
          label: l10n.actionBackup,
        ),
        FilledButton.tonalIcon(
          onPressed: running ? null : () => checkModUrls(context, ref, mod),
          icon: const Icon(Icons.link),
          label: Text(l10n.actionCheckUrls),
        ),
        FilledButton.tonalIcon(
          onPressed: mod.missingCount > 0 && !running ? copyMissingUrls : null,
          icon: const Icon(Icons.copy_all),
          label: Text(l10n.actionCopyMissingUrls),
        ),
        FilledButton.tonalIcon(
          onPressed: running
              ? null
              : () => deleteModAssetsWithDialog(context, ref, mod),
          style: FilledButton.styleFrom(foregroundColor: scheme.error),
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.actionDeleteAssets),
        ),
        FilledButton.tonalIcon(
          onPressed: running
              ? null
              : () => updateUrlsWithDialog(context, ref, [mod], bulk: false),
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.actionUpdateUrls),
        ),
      ],
    );
  }
}

/// A filled button: the accent [FilledButton] when [primary], otherwise the
/// grey tonal one.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.primary,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool primary;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        )
      : FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

/// The URLs of the assets of [assets] that are not on disk, one per line,
/// in list order (what "Copy missing URLs" puts on the clipboard; 2.x
/// behaviour).
String missingUrlsText(List<Asset> assets) => [
  for (final asset in assets)
    if (!asset.exists) asset.url,
].join('\n');
