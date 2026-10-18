import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_interaction_region.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_context_menu.dart';

/// Builds the visual of a grid card or list row given whether the pointer
/// is over it and whether the mod is selected.
typedef ModInteractionBuilder = ItemInteractionBuilder;

/// [ItemInteractionRegion] bound to [selectionProvider] and the mod context
/// menu: left click selects the mod, Ctrl/Cmd + left click toggles it in
/// the multi-selection, right click selects it and opens the menu.
class ModInteractionRegion extends ConsumerWidget {
  /// Creates the region for [mod].
  const ModInteractionRegion({
    super.key,
    required this.mod,
    required this.builder,
  });

  /// The mod this card or row shows.
  final Mod mod;

  /// Builds the visual.
  final ModInteractionBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = mod.jsonPath;
    final selection = ref.read(selectionProvider.notifier);
    return ItemInteractionRegion(
      selected: selectionProvider.select((s) => s.contains(path)),
      onSelect: () => selection.select(path),
      onToggle: () => selection.toggle(path),
      onContextMenu: (position) =>
          showModContextMenu(context, ref, position, mod),
      builder: builder,
    );
  }
}
