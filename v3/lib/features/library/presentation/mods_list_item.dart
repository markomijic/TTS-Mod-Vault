import 'dart:io' show File;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_interaction_region.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

/// Thumbnail edge length.
const double _thumbnailSize = 40;

/// Decoded thumbnail width (2x for HiDPI).
const int _thumbnailCacheWidth = 80;

/// Width of the selection / hover border.
const double _borderWidth = 2;

/// Duration of the border colour animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Fixed row height; `ModsList` uses it as `itemExtent`.
const double modsListItemExtent = _thumbnailSize + 2 * Insets.sm + Insets.xs;

/// One mod as a list row: thumbnail, name and folder, missing count, audio
/// and backup icons, modification date. Port of 2.x `ModsListItem`.
class ModsListItem extends ConsumerWidget {
  /// Creates the row for [mod].
  const ModsListItem({super.key, required this.mod});

  /// The mod shown.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackupState = ref.watch(showBackupStateSettingProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSave = mod.ref.type == ModType.save;

    return ModInteractionRegion(
      mod: mod,
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
              _Thumbnail(mod: mod),
              Gaps.w12,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSave
                          ? '${mod.displayName} - ${mod.ref.fileName}'
                          : mod.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      mod.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Gaps.w12,
              MissingCountBadge(mod: mod),
              if (mod.missingCount > 0) Gaps.w12,
              AudioBadge(mod: mod),
              if (mod.summary.hasAudio) Gaps.w8,
              BackupStatusBadge(mod: mod, visible: showBackupState),
              if (showBackupState && mod.backupStatus != BackupStatus.none)
                Gaps.w12,
              Text(
                modDateFormat.format(mod.modified),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.mod});

  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imagePath = mod.imagePath;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.extension_outlined, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(Insets.xs),
      child: SizedBox.square(
        dimension: _thumbnailSize,
        child: imagePath == null
            ? placeholder
            : Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                cacheWidth: _thumbnailCacheWidth,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}
