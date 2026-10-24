import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_badges.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_interaction_region.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show BadgeBackdrop, formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the selection / hover border.
const double _borderWidth = 3;

/// Duration of the border colour animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Size of the zip icon on the tile.
const double _tileIconSize = 56;

/// One backup in the grid: a zip icon tile, the match badge top-right and a
/// bottom band with the file name, size, folder and modification date.
class BackupGridCard extends StatelessWidget {
  /// Creates the card for [backup].
  const BackupGridCard({super.key, required this.backup});

  /// The backup shown.
  final Backup backup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BackupInteractionRegion(
      backup: backup,
      builder: (context, hovered, selected) => AnimatedContainer(
        duration: _borderDuration,
        decoration: BoxDecoration(
          border: Border.all(
            width: _borderWidth,
            color: selected
                ? scheme.primary
                : hovered
                ? scheme.outline
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            AppTheme.cardRadius - _borderWidth,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Icon(
                  Icons.folder_zip_outlined,
                  size: _tileIconSize,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _InfoBand(backup: backup),
              ),
              Positioned(
                top: Insets.xs,
                right: Insets.xs,
                child: BadgeBackdrop(child: BackupMatchBadge(backup: backup)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBand extends StatelessWidget {
  const _InfoBand({required this.backup});

  final Backup backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailStyle = theme.textTheme.labelSmall?.copyWith(
      color: Colors.white,
    );
    final localeName = AppLocalizations.of(context).localeName;
    return ColoredBox(
      // A dark scrim over the artwork in both appearances.
      color: Colors.black.withValues(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              backup.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${backup.fileSizeLabel} · ${backup.folder}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
            Text(
              formatModDate(localeName, backup.modified),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
          ],
        ),
      ),
    );
  }
}
