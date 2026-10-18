import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart'
    show ImportBackupsResult, ImportFileResult;
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 700;

/// How one archive of an import ended.
enum ImportFileStatus {
  /// Extracted (possibly with some files failing).
  imported,

  /// The user chose Cancel in the JSON conflict dialog.
  skipped,

  /// The import threw.
  failed,

  /// The run was cancelled before this archive.
  notProcessed,
}

/// One line of the [ImportResultsDialog].
final class ImportFileLine {
  /// Creates a line.
  const ImportFileLine({
    required this.path,
    required this.status,
    required this.detail,
  });

  /// The archive.
  final String path;

  /// How it ended.
  final ImportFileStatus status;

  /// Localised explanation.
  final String detail;

  /// File name of the archive.
  String get fileName => p.basename(path);
}

/// Summary of a backup import that did not finish cleanly: the counts, a
/// cancellation note, and one line per archive with its outcome. The Copy
/// button puts [importResultsText] on the clipboard.
class ImportResultsDialog extends StatelessWidget {
  /// Creates the dialog for [result]; [paths] are the archives asked for,
  /// so the ones not reached after a cancel can be listed.
  const ImportResultsDialog({
    super.key,
    required this.result,
    required this.paths,
  });

  /// The import's outcome.
  final ImportBackupsResult result;

  /// Every archive the import was started with.
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final lines = importFileLines(l10n, result, paths);

    return AppDialog(
      title: l10n.importResultsTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(importSummaryText(l10n, lines)),
            if (result.cancelled) ...[
              Gaps.h8,
              Text(
                l10n.importResultsCancelledNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.assetInvalid,
                ),
              ),
            ],
            Gaps.h16,
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lines.length,
                itemBuilder: (context, index) =>
                    _ImportLineRow(line: lines[index]),
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
          onPressed: () =>
              copyTextToClipboard(context, importResultsText(l10n, lines)),
          icon: const Icon(Icons.copy),
          label: Text(l10n.copy),
        ),
      ],
    );
  }
}

/// One [ImportFileLine] per path in [paths], in order.
List<ImportFileLine> importFileLines(
  AppLocalizations l10n,
  ImportBackupsResult result,
  List<String> paths,
) {
  final byPath = <String, ImportFileResult>{
    for (final r in result.results) p.normalize(r.path): r,
  };
  return [
    for (final path in paths) _lineFor(l10n, path, byPath[p.normalize(path)]),
  ];
}

ImportFileLine _lineFor(
  AppLocalizations l10n,
  String path,
  ImportFileResult? file,
) {
  if (file == null) {
    return ImportFileLine(
      path: path,
      status: ImportFileStatus.notProcessed,
      detail: l10n.importStatusNotProcessed,
    );
  }
  final error = file.error;
  if (error != null) {
    return ImportFileLine(
      path: path,
      status: ImportFileStatus.failed,
      detail: l10n.importStatusFailed(error),
    );
  }
  final outcome = file.result;
  if (outcome == null || outcome.cancelled) {
    return ImportFileLine(
      path: path,
      status: ImportFileStatus.skipped,
      detail: l10n.importStatusSkipped,
    );
  }
  final assets = l10n.assetFilesCount(outcome.assetsExtracted);
  final base = outcome.jsonSkipped
      ? l10n.importStatusImportedKeptJson(assets)
      : l10n.importStatusImported(assets);
  return ImportFileLine(
    path: path,
    status: ImportFileStatus.imported,
    detail: outcome.failed == 0
        ? base
        : '$base${l10n.listSeparator}'
              '${l10n.importStatusFilesFailed(outcome.failed)}',
  );
}

/// "Imported 2 of 4 backups, 1 failed, 1 skipped".
String importSummaryText(AppLocalizations l10n, List<ImportFileLine> lines) {
  var imported = 0;
  var failed = 0;
  var skipped = 0;
  for (final line in lines) {
    switch (line.status) {
      case ImportFileStatus.imported:
        imported++;
      case ImportFileStatus.failed:
        failed++;
      case ImportFileStatus.skipped:
      case ImportFileStatus.notProcessed:
        skipped++;
    }
  }
  final parts = [
    l10n.importResultsSummary(imported, lines.length),
    if (failed > 0) l10n.importResultsFailed(failed),
    if (skipped > 0) l10n.importResultsSkipped(skipped),
  ];
  return parts.join(l10n.listSeparator);
}

/// Plain-text form of the dialog for the clipboard.
String importResultsText(AppLocalizations l10n, List<ImportFileLine> lines) {
  final buffer = StringBuffer(importSummaryText(l10n, lines));
  for (final line in lines) {
    buffer.write('\n${line.fileName}\n    ${line.detail}');
  }
  return buffer.toString();
}

class _ImportLineRow extends StatelessWidget {
  const _ImportLineRow({required this.line});

  final ImportFileLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = VaultColors.of(context);
    final color = switch (line.status) {
      ImportFileStatus.imported => colors.assetPresent,
      ImportFileStatus.failed => colors.assetMissing,
      ImportFileStatus.skipped ||
      ImportFileStatus.notProcessed => theme.colorScheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(line.fileName, style: theme.textTheme.bodyMedium),
          Text(
            line.detail,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
