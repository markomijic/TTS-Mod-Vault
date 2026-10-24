import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';

/// Width of the selection ring.
const double _ringWidth = 3;

/// Gap between the ring and the card.
const double _ringGap = 2;

/// Duration of the ring and lift animations.
const Duration _duration = Duration(milliseconds: 150);

/// How much a hovered card grows.
const double _hoverScale = 1.02;

/// The frame of a grid card: [child] clipped to [AppTheme.cardRadius],
/// with an accent ring set 2 px off the card when [selected] (as in
/// Photos and Finder), and a faint ring plus a small lift when [hovered].
///
/// The ring space is always reserved, so selecting a card never shifts
/// its content.
class SelectableCardFrame extends StatelessWidget {
  /// Creates the frame.
  const SelectableCardFrame({
    super.key,
    required this.hovered,
    required this.selected,
    required this.child,
  });

  /// Whether the pointer is over the card.
  final bool hovered;

  /// Whether the card is selected.
  final bool selected;

  /// The card content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const inset = _ringWidth + _ringGap;
    return AnimatedScale(
      scale: hovered && !selected ? _hoverScale : 1,
      duration: _duration,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: _duration,
        padding: const EdgeInsets.all(inset),
        decoration: BoxDecoration(
          border: Border.all(
            width: _ringWidth,
            color: selected
                ? scheme.primary
                : hovered
                ? scheme.outline
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius + inset),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: child,
        ),
      ),
    );
  }
}
