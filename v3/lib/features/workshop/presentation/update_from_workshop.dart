/// "Update from Steam Workshop": confirm (with a "Force update" option),
/// run `WorkshopService.updateMods`, show the results.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Asks for confirmation, then updates [mods] from the Steam Workshop and
/// shows the [WorkshopUpdateResultsDialog]. Nothing happens when [mods] is
/// empty or the user cancels.
Future<void> updateModsFromWorkshop(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods,
) async {
  if (mods.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final force = await showConfirmDialogWithCheckbox(
    context,
    title: l10n.workshopUpdateConfirmTitle,
    message: mods.length == 1
        ? l10n.workshopUpdateConfirmOne(mods.single.displayName)
        : l10n.workshopUpdateConfirmMany(mods.length),
    checkboxLabel: l10n.workshopForceUpdate,
    checkboxInfo: l10n.workshopForceUpdateInfo,
    confirmLabel: l10n.workshopUpdateAction,
  );
  if (force == null || !context.mounted) return;

  final ui = OperationUi.of(context);
  final service = ref.read(workshopServiceProvider);
  final result = await ui.launch(() => service.updateMods(mods, force: force));
  if (result == null || !ui.mounted) return;
  await ui.showAppDialog<void>(
    (_) => WorkshopUpdateResultsDialog(result: result),
  );
}
