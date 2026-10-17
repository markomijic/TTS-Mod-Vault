import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the results dialog.
const double _dialogWidth = 700;

/// Summary of a download batch that did not finish cleanly (port of v2
/// `showDownloadResultsDialog`): the counts, a cancellation note, and
/// every failed request with its asset type, URL and HTTP status or error.
/// The Copy button puts [downloadResultsText] on the clipboard.
class DownloadResultsDialog extends StatelessWidget {
  /// Creates the dialog for [result].
  const DownloadResultsDialog({super.key, required this.result});

  /// The batch shown.
  final DownloadBatchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final failed = result.failed.toList();

    return AppDialog(
      title: l10n.downloadResultsTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(downloadSummaryText(l10n, result)),
            if (result.wasCancelled) ...[
              Gaps.h8,
              Text(
                l10n.downloadResultsCancelledNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.assetInvalid,
                ),
              ),
            ],
            if (failed.isNotEmpty) ...[
              Gaps.h16,
              Text(
                l10n.downloadResultsFailedHeading,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.assetMissing,
                ),
              ),
              Gaps.h8,
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: failed.length,
                  itemBuilder: (context, index) =>
                      _FailedOutcomeRow(outcome: failed[index]),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              copyTextToClipboard(context, downloadResultsText(l10n, result)),
          icon: const Icon(Icons.copy),
          label: Text(l10n.copy),
        ),
      ],
    );
  }
}

/// "Downloaded 3 of 5 files, 2 failed" (skipped and cancelled counts are
/// appended when non-zero).
String downloadSummaryText(AppLocalizations l10n, DownloadBatchResult r) {
  final parts = [
    l10n.downloadResultsSummary(r.downloadedCount, r.total),
    if (r.failedCount > 0) l10n.downloadResultsFailed(r.failedCount),
    if (r.skippedCount > 0) l10n.downloadResultsSkipped(r.skippedCount),
    if (r.cancelledCount > 0) l10n.downloadResultsCancelled(r.cancelledCount),
  ];
  return parts.join(l10n.listSeparator);
}

/// The failure description of [outcome]: HTTP status, error text or the
/// HTML-page note.
String downloadFailureText(AppLocalizations l10n, DownloadOutcome outcome) {
  final parts = <String>[
    if (outcome.status == DownloadStatus.htmlErrorPage)
      l10n.downloadStatusHtmlErrorPage,
    if (outcome.httpStatus case final status?) l10n.httpStatusLabel(status),
    if (outcome.error case final error? when error.trim().isNotEmpty) error,
  ];
  return parts.isEmpty ? l10n.downloadStatusFailed : parts.join(' – ');
}

/// Plain-text form of the dialog for the clipboard.
String downloadResultsText(AppLocalizations l10n, DownloadBatchResult r) {
  final buffer = StringBuffer(downloadSummaryText(l10n, r));
  if (r.wasCancelled) buffer.write('\n${l10n.downloadResultsCancelledNote}');
  final failed = r.failed.toList();
  if (failed.isNotEmpty) {
    buffer.write('\n\n${l10n.downloadResultsFailedHeading}');
    for (final outcome in failed) {
      buffer.write(
        '\n[${outcome.type.label(l10n)}] ${outcome.url}'
        '\n    ${downloadFailureText(l10n, outcome)}',
      );
    }
  }
  return buffer.toString();
}

class _FailedOutcomeRow extends StatelessWidget {
  const _FailedOutcomeRow({required this.outcome});

  final DownloadOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '${outcome.type.label(l10n)}: ${outcome.url}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            downloadFailureText(l10n, outcome),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
