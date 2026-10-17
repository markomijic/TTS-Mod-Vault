import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show ProviderListenable;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart';

/// Builds the visual of a grid card or list row given whether the pointer
/// is over it and whether the item is selected.
typedef ItemInteractionBuilder = Widget Function(
  BuildContext context,
  bool hovered,
  bool selected,
);

/// Pointer handling shared by the grid cards and list rows of every tab.
///
/// - left click calls [onSelect], Ctrl/Cmd + left click [onToggle], right
///   click [onSelect] and then [onContextMenu] with the pointer position;
/// - nothing happens while [operationRunningProvider] is true;
/// - [selected] is a `select`-narrowed listenable (`s.contains(path)`), so a
///   selection change rebuilds only the items whose state flipped.
class ItemInteractionRegion extends HookConsumerWidget {
  /// Creates the region.
  const ItemInteractionRegion({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    required this.onContextMenu,
    required this.builder,
  });

  /// Whether this item is selected.
  final ProviderListenable<bool> selected;

  /// Selects exactly this item.
  final VoidCallback onSelect;

  /// Adds or removes this item from the multi-selection.
  final VoidCallback onToggle;

  /// Opens the context menu at the given global position.
  final ValueChanged<Offset> onContextMenu;

  /// Builds the visual.
  final ItemInteractionBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final isSelected = ref.watch(selected);

    void onPointerDown(PointerDownEvent event) {
      if (ref.read(operationRunningProvider)) return;
      if (event.buttons == kSecondaryButton) {
        onSelect();
        onContextMenu(event.position);
      } else if (event.buttons == kPrimaryButton) {
        final keyboard = HardwareKeyboard.instance;
        if (keyboard.isControlPressed || keyboard.isMetaPressed) {
          onToggle();
        } else {
          onSelect();
        }
      }
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: Listener(
        onPointerDown: onPointerDown,
        child: builder(context, hovered.value, isSelected),
      ),
    );
  }
}
