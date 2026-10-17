import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Asks for confirmation and deletes [mod] (its JSON and image; asset files
/// are kept). The outcome is shown in a snack bar. Port of the 2.x
/// `deleteMod` context-menu branch.
Future<void> showDeleteModDialog(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
) async {
  final l10n = AppLocalizations.of(context);
  // Read before the first await: the ref may be unmounted afterwards.
  final service = ref.read(modEditServiceProvider);

  final confirmed = await showConfirmDialog(
    context,
    title: l10n.deleteModTitle(mod.ref.type.singular(l10n)),
    message: l10n.deleteModMessage(mod.displayName, mod.ref.fileName),
    confirmLabel: l10n.menuDelete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final result = await service.deleteMod(mod);
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    result.when(
      ok: (_) => l10n.deletedMod(mod.displayName),
      err: (failure) => failure.message,
    ),
  );
}
