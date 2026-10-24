import 'dart:io' show File;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/app/widgets/selectable_card_frame.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_badges.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_interaction_region.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show BadgeBackdrop, formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Size of the zip icon on the tile.
const double _tileIconSize = 56;

/// Decoded width of the cover art; cards are at most 240 px wide.
const int _thumbnailCacheWidth = 320;

/// One backup in the grid: the cover art of the mod it matches (as in
/// 2.x; a zip icon tile when there is none), the match badge top-right and
/// a bottom band with the file name, size, folder and modification date.
class BackupGridCard extends ConsumerWidget {
  /// Creates the card for [backup].
  const BackupGridCard({super.key, required this.backup});

  /// The backup shown.
  final Backup backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final matchingPath = backup.matchingModPath;
    final imagePath = matchingPath == null
        ? null
        : ref.watch(
            libraryControllerProvider.select(
              (s) => s.value?.modByPath(matchingPath)?.imagePath,
            ),
          );
    final tile = ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(
        Icons.folder_zip_outlined,
        size: _tileIconSize,
        color: scheme.onSurfaceVariant,
      ),
    );
    return BackupInteractionRegion(
      backup: backup,
      builder: (context, hovered, selected) => SelectableCardFrame(
        hovered: hovered,
        selected: selected,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath == null)
              tile
            else
              Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                cacheWidth: _thumbnailCacheWidth,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => tile,
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
