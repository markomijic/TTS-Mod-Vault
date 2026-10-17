import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_destination.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
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

/// Placeholder shown in place of the buttons while an operation runs.
///
/// Phase 3 replaces this with the operation progress bar (status text,
/// determinate progress and a Cancel button driven by the operations
/// engine); keep the name so the swap is a one-line change in
/// [SelectedModBottomBar].
class OperationProgressSlot extends StatelessWidget {
  /// Creates the placeholder.
  const OperationProgressSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        Gaps.h8,
        Text(l10n.operationInProgress, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The per-mod action buttons (2.x `SelectedModActionButtons` plus the
/// items of its overflow menu). Every action is a Phase 3–5 stub showing
/// the "not implemented" snack bar; "Download all" is disabled when
/// nothing is missing.
class SelectedModActions extends StatelessWidget {
  /// Creates the buttons for [mod].
  const SelectedModActions({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    void stub(String label) =>
        showAppSnackBar(context, l10n.notImplementedAction(label));

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        FilledButton.tonalIcon(
          onPressed: mod.missingCount > 0
              ? () => stub(l10n.actionDownloadAll)
              : null,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.actionDownloadAll),
        ),
        FilledButton.tonalIcon(
          onPressed: () => stub(l10n.actionBackup),
          icon: const Icon(Icons.archive_outlined),
          label: Text(l10n.actionBackup),
        ),
        FilledButton.tonalIcon(
          onPressed: () => stub(l10n.actionCheckUrls),
          icon: const Icon(Icons.link),
          label: Text(l10n.actionCheckUrls),
        ),
        FilledButton.tonalIcon(
          onPressed: () => stub(l10n.actionDeleteAssets),
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.actionDeleteAssets),
        ),
        FilledButton.tonalIcon(
          onPressed: () => stub(l10n.actionUpdateUrls),
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.actionUpdateUrls),
        ),
      ],
    );
  }
}
