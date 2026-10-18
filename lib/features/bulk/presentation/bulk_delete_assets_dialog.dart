import 'package:flutter_hooks/flutter_hooks.dart' show HookWidget, useState;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart'
    show DeleteAssetsScope;
import 'package:tts_mod_vault/features/bulk/presentation/bulk_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 520;

/// Shows the [BulkDeleteAssetsDialog]; null when cancelled.
Future<DeleteAssetsScope?> showBulkDeleteAssetsDialog(
  BuildContext context, {
  required String message,
}) => showDialog<DeleteAssetsScope>(
  context: context,
  builder: (_) => BulkDeleteAssetsDialog(message: message),
);

/// Port of 2.x `BulkDeleteDialog`: how many mods are affected, a scope
/// radio (keep shared files / delete them too, with the shared-files
/// warning) and a permanence warning. Pops with the scope on Delete.
class BulkDeleteAssetsDialog extends HookWidget {
  /// Creates the dialog.
  const BulkDeleteAssetsDialog({super.key, required this.message});

  /// First line, stating how many mods are affected.
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = VaultColors.of(context);
    final scope = useState(DeleteAssetsScope.exclusiveOnly);

    return AppDialog(
      title: l10n.actionDeleteAssets,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            Gaps.h16,
            Text(l10n.bulkDeleteScopeLabel, style: theme.textTheme.titleSmall),
            Gaps.h4,
            RadioGroup<DeleteAssetsScope>(
              groupValue: scope.value,
              onChanged: (value) {
                if (value != null) scope.value = value;
              },
              child: Column(
                children: [
                  for (final option in DeleteAssetsScope.values)
                    RadioListTile<DeleteAssetsScope>(
                      value: option,
                      title: Text(option.title(l10n)),
                      secondary: option == DeleteAssetsScope.all
                          ? Tooltip(
                              message: l10n.sharedFilesWarning,
                              child: Icon(
                                Icons.warning_amber_rounded,
                                color: colors.logWarning,
                              ),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            Gaps.h16,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.logWarning),
                Gaps.w8,
                Expanded(
                  child: Text(
                    l10n.bulkDeleteWarning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(scope.value),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.menuDelete),
        ),
      ],
    );
  }
}
