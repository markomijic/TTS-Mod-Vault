import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_labels.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 700;

/// Height cap of the preview and warnings lists.
const double _listMaxHeight = 320;

/// How many candidate paths the preview lists at most.
const int cleanupPreviewLimit = 200;

/// Confirms a cleanup: the candidate count and total size, that the files
/// are deleted permanently, an expandable preview (the first
/// [cleanupPreviewLimit] paths grouped by asset type, legacy duplicates
/// marked with their surviving twin) and the scan's warnings. Pops with
/// true on Delete.
class CleanupConfirmDialog extends StatelessWidget {
  /// Creates the dialog for [scan].
  const CleanupConfirmDialog({super.key, required this.scan});

  /// The scan to confirm.
  final CleanupScan scan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = VaultColors.of(context);
    final candidates = scan.candidates;
    final shown = candidates.take(cleanupPreviewLimit).toList();

    return AppDialog(
      title: l10n.cleanupTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cleanupMessage(
                candidates.length,
                formatByteSize(l10n, scan.totalBytes),
              ),
            ),
            Gaps.h8,
            Text(
              l10n.cleanupPermanentNote,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.assetMissing,
              ),
            ),
            Gaps.h8,
            ExpansionTile(
              title: Text(
                shown.length == candidates.length
                    ? l10n.cleanupPreviewAll(candidates.length)
                    : l10n.cleanupPreviewFirst(shown.length, candidates.length),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: Insets.sm),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _listMaxHeight),
                  child: _CandidateList(candidates: shown),
                ),
              ],
            ),
            if (scan.warnings.isNotEmpty)
              ExpansionTile(
                title: Text(
                  l10n.cleanupWarnings(scan.warnings.length),
                  style: TextStyle(color: colors.logWarning),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: Insets.sm),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _listMaxHeight,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: scan.warnings.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Insets.xs,
                        ),
                        child: SelectableText(
                          scan.warnings[index],
                          style: theme.textTheme.bodySmall,
                        ),
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
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
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

/// Candidate paths grouped by asset type (the scan order), legacy
/// duplicates marked.
class _CandidateList extends StatelessWidget {
  const _CandidateList({required this.candidates});

  final List<CleanupCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = <Widget>[];
    AssetType? currentType;
    for (final candidate in candidates) {
      if (candidate.type != currentType) {
        currentType = candidate.type;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm, bottom: Insets.xs),
            child: Text(
              candidate.type.label(l10n),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final twin = candidate.twinPath;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(candidate.path, style: theme.textTheme.bodySmall),
              if (candidate.reason == CleanupReason.legacyDuplicate &&
                  twin != null)
                Text(
                  l10n.cleanupLegacyDuplicate(p.basename(twin)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return ListView(shrinkWrap: true, children: rows);
  }
}
