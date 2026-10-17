import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';
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
/// items of its overflow menu). "Download all" (disabled when nothing is
/// missing) and "Check URLs" are live; Backup, Delete assets and Update
/// URLs are Phase 4–5 stubs showing the "not implemented" snack bar.
class SelectedModActions extends ConsumerWidget {
  /// Creates the buttons for [mod].
  const SelectedModActions({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final running = ref.watch(operationRunningProvider);

    void stub(String label) =>
        showAppSnackBar(context, l10n.notImplementedAction(label));

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        FilledButton.tonalIcon(
          onPressed: mod.missingCount > 0 && !running
              ? () => downloadModAssets(context, ref, mod)
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
          onPressed: running ? null : () => checkModUrls(context, ref, mod),
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
