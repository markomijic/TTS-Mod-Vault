import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_hooks/flutter_hooks.dart' show useScrollController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_list_item.dart';

/// How far beyond the viewport rows are built, in logical pixels.
const ScrollCacheExtent _cacheExtent = ScrollCacheExtent.pixels(300);

/// The mod list: `ListView.builder` over the filtered mods, one
/// [ModsListItem] per mod keyed by its JSON path.
class ModsList extends HookConsumerWidget {
  /// Creates the list for [mods].
  const ModsList({super.key, required this.mods});

  /// The mods to show, already filtered and sorted.
  final List<Mod> mods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useScrollController();
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.only(right: Insets.md, bottom: Insets.sm),
        scrollCacheExtent: _cacheExtent,
        itemExtent: modsListItemExtent,
        itemCount: mods.length,
        itemBuilder: (context, index) {
          final mod = mods[index];
          return ModsListItem(key: ValueKey(mod.jsonPath), mod: mod);
        },
      ),
    );
  }
}
