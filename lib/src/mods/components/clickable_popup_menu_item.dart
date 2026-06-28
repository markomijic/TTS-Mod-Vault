import 'package:flutter/material.dart';

/// A [PopupMenuItem] that defaults [mouseCursor] to [SystemMouseCursors.click]
/// so menu entries show a pointer cursor on hover.
///
/// Use this in place of [PopupMenuItem] for all popup/context menu entries.
class ClickablePopupMenuItem<T> extends PopupMenuItem<T> {
  const ClickablePopupMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    super.height,
    super.padding,
    super.labelTextStyle,
    super.mouseCursor = SystemMouseCursors.click,
    required super.child,
  });
}
