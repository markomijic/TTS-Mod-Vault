import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/features/bulk/presentation/bulk_actions_menu.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_targets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// "Bulk actions (N)" where N is the number of mods the actions would
/// apply to: the selection when two or more are selected, otherwise every
/// mod that passes the current search and filters. Opens the
/// [BulkActionsMenu]; disabled while an operation runs.
class BulkActionsButton extends ConsumerWidget {
  /// Creates the button.
  const BulkActionsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(bulkTargetsProvider.select((t) => t.count));
    final running = ref.watch(operationRunningProvider);

    return BulkActionsMenu(
      builder: (context, controller, _) => FilledButton.tonalIcon(
        onPressed: running
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.checklist),
        label: Text(l10n.bulkActions(count)),
      ),
    );
  }
}
