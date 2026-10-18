import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_header.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_actions.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_targets.dart'
    show isUpdatableWorkshopMod;
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The right panel while two or more mods are selected (2.x
/// `MultiSelectView`): "N mods selected", the names, and the bulk action
/// buttons, which run the same flows as the bulk actions menu on the
/// selected mods. "Update mods" is only offered when every selected item
/// is a Workshop mod with a numeric id.
class MultiSelectView extends ConsumerWidget {
  /// Creates the view.
  const MultiSelectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mods = ref.watch(selectedModsProvider);
    final type = ref.watch(selectedModTypeProvider);
    final running = ref.watch(operationRunningProvider);
    final allWorkshopMods =
        mods.isNotEmpty && mods.every(isUpdatableWorkshopMod);

    VoidCallback? action(
      Future<void> Function(BuildContext, WidgetRef, List<Mod>) run,
    ) => running ? null : () => run(context, ref, mods);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedModHeader(
          title: l10n.selectedCount(mods.length, type.plural(l10n)),
          showHelp: false,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.sm,
            ),
            itemCount: mods.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Text(
                mods[index].displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.sm,
            Insets.sm,
            Insets.sm,
          ),
          child: Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: action(runBulkDownload),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.menuDownload),
              ),
              FilledButton.tonalIcon(
                onPressed: action(runBulkBackup),
                icon: const Icon(Icons.archive_outlined),
                label: Text(l10n.actionBackup),
              ),
              FilledButton.tonalIcon(
                onPressed: action(
                  (context, ref, mods) =>
                      runBulkBackup(context, ref, mods, downloadFirst: true),
                ),
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(l10n.bulkDownloadAndBackup),
              ),
              if (allWorkshopMods)
                FilledButton.tonalIcon(
                  onPressed: action(runBulkUpdateWorkshop),
                  icon: const Icon(Icons.update),
                  label: Text(l10n.bulkUpdateMods),
                ),
              FilledButton.tonalIcon(
                onPressed: action(runBulkDeleteAssets),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.actionDeleteAssets),
              ),
              FilledButton.tonalIcon(
                onPressed: action(runBulkCheckUrls),
                icon: const Icon(Icons.link),
                label: Text(l10n.bulkCheckUrls),
              ),
              FilledButton.tonalIcon(
                onPressed: action(
                  (context, ref, mods) =>
                      updateUrlsWithDialog(context, ref, mods, bulk: true),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.actionUpdateUrls),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
