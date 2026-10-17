import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';

/// An entry of a context menu: either a [MenuAction] or a [MenuDivider].
sealed class MenuEntry {
  const MenuEntry();
}

/// A clickable context-menu item.
@immutable
final class MenuAction extends MenuEntry {
  /// Creates an action.
  const MenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.destructive = false,
  });

  /// Item text.
  final String label;

  /// Leading icon.
  final IconData icon;

  /// Called when the item is picked. A null callback disables the item.
  final VoidCallback? onPressed;

  /// Whether the item can be picked.
  final bool enabled;

  /// Styles the item in the error colour.
  final bool destructive;

  bool get _isEnabled => enabled && onPressed != null;
}

/// A horizontal separator between groups of actions.
final class MenuDivider extends MenuEntry {
  /// Creates a divider.
  const MenuDivider();
}

/// Shows a context menu at [globalPosition] and runs the picked action.
///
/// Styling (rounded corners, border, surface colour) comes from
/// `ThemeData.popupMenuTheme`.
Future<void> showAppContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<MenuEntry> entries,
) async {
  if (entries.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );

  final selected = await showMenu<MenuAction>(
    context: context,
    position: position,
    items: [
      for (final entry in entries)
        switch (entry) {
          MenuDivider() => const PopupMenuDivider(),
          MenuAction() => PopupMenuItem<MenuAction>(
            value: entry,
            enabled: entry._isEnabled,
            child: _MenuActionRow(action: entry),
          ),
        },
    ],
  );
  selected?.onPressed?.call();
}

class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({required this.action});

  final MenuAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color? color = !action._isEnabled
        ? theme.disabledColor
        : action.destructive
        ? scheme.error
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(action.icon, size: Insets.lg + Insets.xs, color: color),
        Gaps.w12,
        Flexible(
          child: Text(
            action.label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
