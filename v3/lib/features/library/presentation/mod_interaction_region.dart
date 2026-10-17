import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_destination.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_context_menu.dart';

/// Builds the visual of a grid card or list row given whether the pointer
/// is over it and whether the mod is selected.
typedef ModInteractionBuilder = Widget Function(
  BuildContext context,
  bool hovered,
  bool selected,
);

/// Pointer handling shared by grid cards and list rows.
///
/// - left click selects the mod, Ctrl/Cmd + left click toggles it in the
///   multi-selection, right click selects it and opens the context menu;
/// - nothing happens while [operationRunningProvider] is true;
/// - the selection is watched through `select((s) => s.contains(path))`, so
///   a selection change rebuilds only the cards whose state flipped.
class ModInteractionRegion extends HookConsumerWidget {
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
    final hovered = useState(false);
    final path = mod.jsonPath;
    final selected = ref.watch(
      selectionProvider.select((s) => s.contains(path)),
    );

    void onPointerDown(PointerDownEvent event) {
      if (ref.read(operationRunningProvider)) return;
      final selection = ref.read(selectionProvider.notifier);
      if (event.buttons == kSecondaryButton) {
        selection.select(path);
        showModContextMenu(context, ref, event.position, mod);
      } else if (event.buttons == kPrimaryButton) {
        final keyboard = HardwareKeyboard.instance;
        if (keyboard.isControlPressed || keyboard.isMetaPressed) {
          selection.toggle(path);
        } else {
          selection.select(path);
        }
      }
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: Listener(
        onPointerDown: onPointerDown,
        child: builder(context, hovered.value, selected),
      ),
    );
  }
}
