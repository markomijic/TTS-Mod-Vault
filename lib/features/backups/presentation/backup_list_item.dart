import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_badges.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_interaction_region.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Thumbnail edge length.
const double _thumbnailSize = 40;

/// Width of the selection / hover border.
const double _borderWidth = 2;

/// Duration of the border colour animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Fixed row height; `BackupsList` uses it as `itemExtent`.
const double backupListItemExtent = _thumbnailSize + 2 * Insets.sm + Insets.xs;

/// One backup as a list row: zip icon, file name and folder, size, match
/// badge and modification date.
class BackupListItem extends StatelessWidget {
  /// Creates the row for [backup].
  const BackupListItem({super.key, required this.backup});

  /// The backup shown.
  final Backup backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final localeName = AppLocalizations.of(context).localeName;

    return BackupInteractionRegion(
      backup: backup,
      builder: (context, hovered, selected) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs / 2),
        child: AnimatedContainer(
          duration: _borderDuration,
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer
                : hovered
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainer,
            border: Border.all(
              width: _borderWidth,
              color: selected ? scheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(Insets.sm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.sm - _borderWidth,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Insets.xs),
                child: SizedBox.square(
                  dimension: _thumbnailSize,
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.folder_zip_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Gaps.w12,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backup.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      backup.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: detailStyle,
                    ),
                  ],
                ),
              ),
              Gaps.w12,
              Text(backup.fileSizeLabel, style: detailStyle),
              Gaps.w12,
              BackupMatchBadge(backup: backup),
              Gaps.w12,
              Text(
                formatModDate(localeName, backup.modified),
                style: detailStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
