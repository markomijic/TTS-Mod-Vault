import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_actions.dart'
    show importBackupsFromPicker;
import 'package:tts_mod_vault/features/bulk/presentation/bulk_actions.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_targets.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Runs a bulk action on [mods].
typedef BulkAction = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
);

/// The bulk actions menu (plan Phase 5): a header stating the targets
/// ("12 mods (current filters)" / "3 mods (selection)"), then Download,
/// Backup, Download & backup, Update from Workshop (only when every target
/// is a Workshop mod with a numeric id), Delete assets, Check URLs,
/// Update URLs, and Import backups. Items are disabled while an operation
/// runs or when there is no target. [builder] renders the anchor.
class BulkActionsMenu extends ConsumerWidget {
  /// Creates the menu.
  const BulkActionsMenu({super.key, required this.builder});

  /// Builds the anchor; call `controller.open()` to show the menu.
  final MenuAnchorChildBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = ref.watch(bulkTargetsProvider);
    final running = ref.watch(operationRunningProvider);
    final type = ref.watch(selectedModTypeProvider);
    final enabled = !running && targets.count > 0;
    final label = type.count(l10n, targets.count);

    VoidCallback? act(BulkAction action) =>
        enabled ? () => action(context, ref, targets.mods) : null;

    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.sm,
            Insets.md,
            Insets.xs,
          ),
          child: Text(
            targets.fromSelection
                ? l10n.bulkTargetsSelection(label)
                : l10n.bulkTargetsFiltered(label),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.download_outlined),
          onPressed: act(runBulkDownload),
          child: Text(l10n.menuDownload),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.archive_outlined),
          onPressed: act(runBulkBackup),
          child: Text(l10n.actionBackup),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.cloud_download_outlined),
          onPressed: act(
            (context, ref, mods) =>
                runBulkBackup(context, ref, mods, downloadFirst: true),
          ),
          child: Text(l10n.bulkDownloadAndBackup),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.update),
          onPressed: targets.allWorkshopMods
              ? act(runBulkUpdateWorkshop)
              : null,
          child: Text(l10n.menuUpdateFromWorkshop),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: act(runBulkDeleteAssets),
          child: Text(l10n.actionDeleteAssets),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.link),
          onPressed: act(runBulkCheckUrls),
          child: Text(l10n.bulkCheckUrls),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: act(
            (context, ref, mods) =>
                updateUrlsWithDialog(context, ref, mods, bulk: true),
          ),
          child: Text(l10n.actionUpdateUrls),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.unarchive_outlined),
          onPressed: running
              ? null
              : () => importBackupsFromPicker(context, ref),
          child: Text(l10n.actionImportBackups),
        ),
      ],
      builder: builder,
    );
  }
}
