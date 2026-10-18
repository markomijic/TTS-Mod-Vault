import 'package:material_ui/material_ui.dart';

/// Spacing scale. Use these instead of literal paddings.
abstract final class Insets {
  /// 4 logical pixels.
  static const double xs = 4;

  /// 8 logical pixels.
  static const double sm = 8;

  /// 12 logical pixels.
  static const double md = 12;

  /// 16 logical pixels.
  static const double lg = 16;

  /// 24 logical pixels.
  static const double xl = 24;
}

/// Fixed-size gaps for use between children of rows and columns.
abstract final class Gaps {
  /// Horizontal gap of [Insets.xs].
  static const SizedBox w4 = SizedBox(width: Insets.xs);

  /// Horizontal gap of [Insets.sm].
  static const SizedBox w8 = SizedBox(width: Insets.sm);

  /// Horizontal gap of [Insets.md].
  static const SizedBox w12 = SizedBox(width: Insets.md);

  /// Horizontal gap of [Insets.lg].
  static const SizedBox w16 = SizedBox(width: Insets.lg);

  /// Horizontal gap of [Insets.xl].
  static const SizedBox w24 = SizedBox(width: Insets.xl);

  /// Vertical gap of [Insets.xs].
  static const SizedBox h4 = SizedBox(height: Insets.xs);

  /// Vertical gap of [Insets.sm].
  static const SizedBox h8 = SizedBox(height: Insets.sm);

  /// Vertical gap of [Insets.md].
  static const SizedBox h12 = SizedBox(height: Insets.md);

  /// Vertical gap of [Insets.lg].
  static const SizedBox h16 = SizedBox(height: Insets.lg);

  /// Vertical gap of [Insets.xl].
  static const SizedBox h24 = SizedBox(height: Insets.xl);
}
