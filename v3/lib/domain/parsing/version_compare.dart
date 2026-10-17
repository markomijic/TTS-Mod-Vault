/// Semantic-ish version comparison for the in-app update check.
/// Port of v2 `_checkIfLatestVersionIsNewer`, made tolerant of real tag names.
library;

final _leadingDigits = RegExp(r'^\d+');

/// Parses `v3.1.0-dev+4` style strings into numeric components.
///
/// A leading `v`/`V` is dropped, each dot-separated component contributes its
/// leading digits (so `0-dev` and `2+1` count as 0 and 2) and a component
/// without digits counts as 0. Missing components are padded with zeros by
/// the caller.
List<int> _parseVersion(String version) {
  var text = version.trim();
  if (text.startsWith('v') || text.startsWith('V')) {
    text = text.substring(1);
  }
  return [
    for (final part in text.split('.'))
      int.tryParse(_leadingDigits.stringMatch(part.trim()) ?? '') ?? 0,
  ];
}

/// Whether [latest] is a strictly newer version than [current].
///
/// Components are compared numerically left to right; a missing component is
/// 0, so `3.0` equals `3.0.0`. Pre-release and build suffixes are ignored
/// (`3.0.0-dev` compares as `3.0.0`). Never throws.
bool isNewerVersion(String current, String latest) {
  final currentParts = _parseVersion(current);
  final latestParts = _parseVersion(latest);

  final length = currentParts.length > latestParts.length
      ? currentParts.length
      : latestParts.length;

  for (var i = 0; i < length; i++) {
    final c = i < currentParts.length ? currentParts[i] : 0;
    final l = i < latestParts.length ? latestParts[i] : 0;
    if (l > c) return true;
    if (l < c) return false;
  }
  return false;
}
