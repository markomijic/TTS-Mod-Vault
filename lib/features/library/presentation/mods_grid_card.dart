import 'dart:io' show File;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_interaction_region.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

/// Decoded width of card thumbnails; cards are at most 200 px wide.
const int _thumbnailCacheWidth = 256;

/// Width of the selection / hover border.
const double _borderWidth = 3;

/// Duration of the border colour animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Icon shown on image-less cards when the title band carries the name.
const double _placeholderIconSize = 48;

/// One mod in the grid: the save's image (or a surface tile with the name),
/// the backup badge top-right, the missing count bottom-left and the audio
/// icon bottom-right. Port of 2.x `ModsGridCard` without the sync file
/// check: the image is shown when `Mod.imagePath` is set and falls back to
/// the tile when the file cannot be decoded.
class ModsGridCard extends ConsumerWidget {
  /// Creates the card for [mod].
  const ModsGridCard({super.key, required this.mod});

  /// The mod shown.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTitleOnCards = ref.watch(showTitleOnCardsSettingProvider);
    final showBackupState = ref.watch(showBackupStateSettingProvider);
    final scheme = Theme.of(context).colorScheme;
    final showTitleBand = showTitleOnCards || mod.ref.type == ModType.save;

    return ModInteractionRegion(
      mod: mod,
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
              _CardImage(mod: mod, showName: !showTitleBand),
              if (showTitleBand)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _TitleBand(mod: mod),
                ),
              Positioned(
                top: Insets.xs,
                right: Insets.xs,
                child: _Overlay(
                  child: BackupStatusBadge(mod: mod, visible: showBackupState),
                ),
              ),
              Positioned(
                left: Insets.xs,
                bottom: showTitleBand ? null : Insets.xs,
                top: showTitleBand ? Insets.xs : null,
                child: _Overlay(child: MissingCountBadge(mod: mod)),
              ),
              if (mod.summary.hasAudio)
                Positioned(
                  right: Insets.xs,
                  bottom: showTitleBand ? null : Insets.xs,
                  top: showTitleBand ? Insets.xs + Insets.xl : null,
                  child: _Overlay(child: AudioBadge(mod: mod)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a badge in a [BadgeBackdrop] unless the badge rendered nothing.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final renders = switch (child) {
      BackupStatusBadge(:final mod, :final visible) =>
        visible && mod.backupStatus != BackupStatus.none,
      MissingCountBadge(:final mod) => mod.missingCount > 0,
      AudioBadge(:final mod) => mod.summary.hasAudio,
      _ => true,
    };
    if (!renders) return const SizedBox.shrink();
    return BadgeBackdrop(child: child);
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.mod, required this.showName});

  final Mod mod;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final imagePath = mod.imagePath;
    final tile = _NameTile(mod: mod, showName: showName);
    if (imagePath == null) return tile;
    return Image.file(
      File(imagePath),
      fit: BoxFit.cover,
      cacheWidth: _thumbnailCacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => tile,
    );
  }
}

class _NameTile extends StatelessWidget {
  const _NameTile({required this.mod, required this.showName});

  final Mod mod;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Center(
          child: showName
              ? Text(
                  mod.displayName,
                  maxLines: 5,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                )
              : Icon(
                  Icons.extension_outlined,
                  size: _placeholderIconSize,
                  color: scheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

class _TitleBand extends StatelessWidget {
  const _TitleBand({required this.mod});

  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSave = mod.ref.type == ModType.save;
    return ColoredBox(
      // A dark scrim over the artwork in both appearances.
      color: Colors.black.withValues(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            isSave
                ? '${mod.ref.fileName}\n${mod.displayName}'
                : mod.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
