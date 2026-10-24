import 'package:material_ui/material_ui.dart';

/// The neutral colours of the Apple-style theme and the helpers that turn a
/// user-picked accent into one that is readable on them.
///
/// Surfaces are neutral greys modelled on Apple's semantic system colours
/// (window and content backgrounds, labels, separators); the only chroma in
/// the chrome comes from the accent, which is reserved for primary actions,
/// selection and focus.
@immutable
final class ApplePalette {
  const ApplePalette._({
    required this.brightness,
    required this.content,
    required this.contentLowest,
    required this.sidebar,
    required this.raised,
    required this.control,
    required this.controlStrong,
    required this.selected,
    required this.label,
    required this.secondaryLabel,
    required this.border,
    required this.separator,
    required this.red,
    required this.orange,
    required this.green,
    required this.blue,
  });

  /// The palette for [brightness].
  factory ApplePalette.of(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  /// Light appearance.
  static const ApplePalette light = ApplePalette._(
    brightness: Brightness.light,
    content: Color(0xFFFFFFFF),
    contentLowest: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF2F2F5),
    raised: Color(0xFFF5F5F7),
    control: Color(0xFFE9E9EE),
    controlStrong: Color(0xFFDCDCE1),
    selected: Color(0xFFFFFFFF),
    label: Color(0xFF1D1D1F),
    secondaryLabel: Color(0xFF5E5E63),
    border: Color(0xFFC7C7CC),
    separator: Color(0xFFE3E3E8),
    red: Color(0xFFFF3B30),
    orange: Color(0xFFFF9500),
    green: Color(0xFF34C759),
    blue: Color(0xFF007AFF),
  );

  /// Dark appearance.
  static const ApplePalette dark = ApplePalette._(
    brightness: Brightness.dark,
    content: Color(0xFF19191B),
    contentLowest: Color(0xFF121214),
    sidebar: Color(0xFF212123),
    raised: Color(0xFF29292C),
    control: Color(0xFF323235),
    controlStrong: Color(0xFF3E3E42),
    selected: Color(0xFF58585D),
    label: Color(0xFFF5F5F7),
    secondaryLabel: Color(0xFFA1A1A6),
    border: Color(0xFF55555A),
    separator: Color(0xFF333336),
    red: Color(0xFFFF453A),
    orange: Color(0xFFFF9F0A),
    green: Color(0xFF30D158),
    blue: Color(0xFF0A84FF),
  );

  /// Which appearance this palette belongs to.
  final Brightness brightness;

  /// Content background: lists, grids, panels.
  final Color content;

  /// The deepest background (behind content in dark mode).
  final Color contentLowest;

  /// Sidebar (source list) background.
  final Color sidebar;

  /// Floating layer: dialogs, menus, popovers.
  final Color raised;

  /// Fill of a push button, search field or segmented track.
  final Color control;

  /// Pressed or emphasised control fill.
  final Color controlStrong;

  /// The selected segment of a segmented control.
  final Color selected;

  /// Primary label (body text).
  final Color label;

  /// Secondary label (captions, meta text).
  final Color secondaryLabel;

  /// Control borders.
  final Color border;

  /// Hairline separators.
  final Color separator;

  /// System red.
  final Color red;

  /// System orange.
  final Color orange;

  /// System green.
  final Color green;

  /// System blue.
  final Color blue;

  /// WCAG contrast for body text, before any increase from the contrast
  /// setting.
  static const double textContrast = 4.5;

  /// WCAG relative-luminance contrast ratio of two opaque colours (1..21).
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// [color] darkened (light appearance) or lightened (dark appearance) in
  /// small steps until it reaches [minimum] contrast against every colour
  /// in [backgrounds]. Hue and saturation are kept.
  Color readable(
    Color color,
    List<Color> backgrounds, {
    double minimum = textContrast,
  }) {
    bool ok(Color c) => backgrounds.every((b) => contrast(c, b) >= minimum);
    var hsl = HSLColor.fromColor(color);
    final step = brightness == Brightness.light ? -0.01 : 0.01;
    while (!ok(hsl.toColor())) {
      final next = (hsl.lightness + step).clamp(0.0, 1.0);
      if (next == hsl.lightness) break;
      hsl = hsl.withLightness(next);
    }
    return hsl.toColor();
  }

  /// The text colour on an accent [fill]: white, as Apple uses on its
  /// accent fills, unless it drops below 3:1 (the WCAG level for bold and
  /// large text, which button labels are); then the primary label.
  Color onFill(Color fill) {
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF1D1D1F);
    return contrast(white, fill) >= 3 ? white : black;
  }

  /// [color] laid over [base] at [opacity], as an opaque colour.
  static Color tint(Color color, Color base, double opacity) =>
      Color.alphaBlend(color.withValues(alpha: opacity), base);
}
