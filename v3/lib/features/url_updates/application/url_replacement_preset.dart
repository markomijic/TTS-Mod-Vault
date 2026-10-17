/// A saved "old prefix(es) -> new prefix" pair of the Update URLs dialog
/// (v2 `UrlReplacementPreset`). Stored inside the settings JSON.
library;

import 'package:meta/meta.dart';

/// A named URL prefix replacement the user can pick instead of typing.
///
/// [oldUrl] may hold several `|`-separated prefixes (see
/// `parseOldPrefixes`); [newUrl] is the single replacement prefix.
@immutable
final class UrlReplacementPreset {
  /// Creates a preset.
  const UrlReplacementPreset({
    required this.label,
    required this.oldUrl,
    required this.newUrl,
  });

  /// Reads a preset from its JSON form; missing fields become empty strings
  /// (v2 behaviour).
  factory UrlReplacementPreset.fromJson(Map<String, Object?> json) =>
      UrlReplacementPreset(
        label: switch (json['label']) {
          final String value => value,
          _ => '',
        },
        oldUrl: switch (json['oldUrl']) {
          final String value => value,
          _ => '',
        },
        newUrl: switch (json['newUrl']) {
          final String value => value,
          _ => '',
        },
      );

  /// Display name in the preset list.
  final String label;

  /// The prefix(es) to replace.
  final String oldUrl;

  /// The replacement prefix.
  final String newUrl;

  /// Whether every field is blank (such presets are dropped on save).
  bool get isBlank =>
      label.trim().isEmpty && oldUrl.trim().isEmpty && newUrl.trim().isEmpty;

  /// JSON form (same keys as v2).
  Map<String, Object?> toJson() => {
    'label': label,
    'oldUrl': oldUrl,
    'newUrl': newUrl,
  };

  /// Copy with some fields replaced.
  UrlReplacementPreset copyWith({
    String? label,
    String? oldUrl,
    String? newUrl,
  }) => UrlReplacementPreset(
    label: label ?? this.label,
    oldUrl: oldUrl ?? this.oldUrl,
    newUrl: newUrl ?? this.newUrl,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrlReplacementPreset &&
          other.label == label &&
          other.oldUrl == oldUrl &&
          other.newUrl == newUrl;

  @override
  int get hashCode => Object.hash(label, oldUrl, newUrl);

  @override
  String toString() => 'UrlReplacementPreset($label: $oldUrl -> $newUrl)';
}
