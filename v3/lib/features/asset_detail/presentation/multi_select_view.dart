import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_destination.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_header.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The right panel while two or more mods are selected (2.x
/// `MultiSelectView`): "N mods selected", the names, and the bulk action
/// buttons. The buttons are Phase 5 stubs; "Update mods" is only offered
/// when every selected item is a Workshop mod.
class MultiSelectView extends ConsumerWidget {
  /// Creates the view.
  const MultiSelectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mods = ref.watch(selectedModsProvider);
    final type = ref.watch(selectedModTypeProvider);
    final running = ref.watch(operationRunningProvider);
    final allWorkshopMods = mods.every((mod) => mod.ref.type == ModType.mod);

    void stub(String label) =>
        showAppSnackBar(context, l10n.notImplementedAction(label));

    VoidCallback? action(String label) => running ? null : () => stub(label);

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
                onPressed: action(l10n.menuDownload),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.menuDownload),
              ),
              FilledButton.tonalIcon(
                onPressed: action(l10n.actionBackup),
                icon: const Icon(Icons.archive_outlined),
                label: Text(l10n.actionBackup),
              ),
              FilledButton.tonalIcon(
                onPressed: action(l10n.bulkDownloadAndBackup),
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(l10n.bulkDownloadAndBackup),
              ),
              if (allWorkshopMods)
                FilledButton.tonalIcon(
                  onPressed: action(l10n.bulkUpdateMods),
                  icon: const Icon(Icons.update),
                  label: Text(l10n.bulkUpdateMods),
                ),
              FilledButton.tonalIcon(
                onPressed: action(l10n.actionDeleteAssets),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.actionDeleteAssets),
              ),
              FilledButton.tonalIcon(
                onPressed: action(l10n.bulkCheckUrls),
                icon: const Icon(Icons.link),
                label: Text(l10n.bulkCheckUrls),
              ),
              FilledButton.tonalIcon(
                onPressed: action(l10n.actionUpdateUrls),
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
