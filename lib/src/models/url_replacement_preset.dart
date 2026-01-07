class UrlReplacementPreset {
  final String label;
  final String oldUrl;
  final String newUrl;

  const UrlReplacementPreset({
    required this.label,
    required this.oldUrl,
    required this.newUrl,
  });

  UrlReplacementPreset copyWith({
    String? label,
    String? oldUrl,
    String? newUrl,
  }) {
    return UrlReplacementPreset(
      label: label ?? this.label,
      oldUrl: oldUrl ?? this.oldUrl,
      newUrl: newUrl ?? this.newUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'oldUrl': oldUrl,
      'newUrl': newUrl,
    };
  }

  factory UrlReplacementPreset.fromJson(Map<String, dynamic> json) {
    return UrlReplacementPreset(
      label: json['label'] as String? ?? '',
      oldUrl: json['oldUrl'] as String? ?? '',
      newUrl: json['newUrl'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrlReplacementPreset &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          oldUrl == other.oldUrl &&
          newUrl == other.newUrl;

  @override
  int get hashCode => label.hashCode ^ oldUrl.hashCode ^ newUrl.hashCode;
}
