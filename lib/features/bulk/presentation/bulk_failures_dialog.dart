import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 700;

/// Corner radius of a failure row.
const double _rowRadius = 4;

/// Alpha of the error tint behind a failure row.
const double _rowTint = 0.12;

/// One mod that failed inside a bulk operation: its name and the reason.
typedef BulkFailure = ({String name, String? detail});

/// Shown after a bulk download, backup, deletion or URL update when some
/// mods failed: the summary the snack bar would have shown, then every
/// failed mod with its error. Copy puts [bulkFailuresText] on the
/// clipboard.
class BulkFailuresDialog extends StatelessWidget {
  /// Creates the dialog.
  const BulkFailuresDialog({
    super.key,
    required this.title,
    required this.summary,
    required this.failures,
  });

  /// The action's name.
  final String title;

  /// Counts of the whole run.
  final String summary;

  /// The failed mods.
  final List<BulkFailure> failures;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);

    return AppDialog(
      title: title,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            Gaps.h16,
            Text(
              l10n.bulkFailedHeading(failures.length),
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.assetMissing,
              ),
            ),
            Gaps.h8,
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: failures.length,
                itemBuilder: (context, index) =>
                    _FailureRow(failure: failures[index]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.tonalIcon(
          onPressed: () => copyTextToClipboard(
            context,
            bulkFailuresText(title, summary, failures),
          ),
          icon: const Icon(Icons.copy),
          label: Text(l10n.copy),
        ),
      ],
    );
  }
}

/// Plain-text form of the dialog for the clipboard.
String bulkFailuresText(
  String title,
  String summary,
  List<BulkFailure> failures,
) {
  final buffer = StringBuffer()
    ..writeln(title)
    ..writeln(summary);
  for (final failure in failures) {
    buffer
      ..writeln()
      ..write(failure.name);
    if (failure.detail case final detail? when detail.isNotEmpty) {
      buffer
        ..writeln()
        ..write('    $detail');
    }
  }
  return buffer.toString();
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.failure});

  final BulkFailure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Insets.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xs,
      ),
      decoration: BoxDecoration(
        color: colors.assetMissing.withValues(alpha: _rowTint),
        borderRadius: BorderRadius.circular(_rowRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.name, style: theme.textTheme.bodyMedium),
          if (failure.detail case final detail? when detail.isNotEmpty)
            SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
