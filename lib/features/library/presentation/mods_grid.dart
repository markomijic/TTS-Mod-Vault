import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_hooks/flutter_hooks.dart' show useScrollController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';

/// Widest a card gets; the delegate fits as many as the width allows.
const double _maxCardExtent = 240;

/// How far beyond the viewport cards are built, in logical pixels.
const ScrollCacheExtent _cacheExtent = ScrollCacheExtent.pixels(400);

/// The mod grid: `GridView.builder` over the filtered mods, one
/// [ModsGridCard] per mod keyed by its JSON path.
class ModsGrid extends HookConsumerWidget {
  /// Creates the grid for [mods].
  const ModsGrid({super.key, required this.mods});

  /// The mods to show, already filtered and sorted.
  final List<Mod> mods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: GridView.builder(
        controller: controller,
        padding: const EdgeInsets.only(right: Insets.md, bottom: Insets.sm),
        scrollCacheExtent: _cacheExtent,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _maxCardExtent,
          mainAxisSpacing: Insets.sm,
          crossAxisSpacing: Insets.sm,
        ),
        itemCount: mods.length,
        itemBuilder: (context, index) {
          final mod = mods[index];
          return ModsGridCard(key: ValueKey(mod.jsonPath), mod: mod);
        },
      ),
    );
  }
}
