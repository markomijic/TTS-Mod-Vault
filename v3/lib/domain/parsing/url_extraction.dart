/// Regex-based extraction of asset URLs from TTS save-file JSON text.
///
/// This is a behaviour-preserving port of v2 `mods_isolates.dart`
/// (`_assetUrlRegex`, `_extractUrlsWithRegex`, `_processUrl`,
/// `extractUrlsFromJsonString`). The comments document hard-won edge cases;
/// every one of them is covered by
/// `test/domain/parsing/url_extraction_test.dart`.
library;

import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

/// One asset URL found in a mod JSON together with the property it came from.
final class AssetUrl {
  /// Creates an [AssetUrl]; [type] must correspond to [jsonKey].
  const AssetUrl({
    required this.url,
    required this.jsonKey,
    required this.type,
  });

  /// The URL exactly as it will be requested (host already normalised).
  final String url;

  /// The JSON property name the URL was the value of (e.g. `MeshURL`).
  final String jsonKey;

  /// The asset category derived from [jsonKey].
  final AssetType type;

  @override
  bool operator ==(Object other) =>
      other is AssetUrl &&
      other.url == url &&
      other.jsonKey == jsonKey &&
      other.type == type;

  @override
  int get hashCode => Object.hash(url, jsonKey, type);

  @override
  String toString() => 'AssetUrl($jsonKey: $url)';
}

// Two branches:
// 1. Anything with a scheme (https://, steam://, s3://, ...) is taken verbatim
//    up to a {, } or " - TTS treats the value as an opaque URL it just fetches,
//    so we must accept hosts that aren't domain-shaped (e.g. https://something,
//    raw IPs, ports, query strings).
// 2. Scheme-less but domain-shaped values (e.g. www.example.com/path).
// The {}/" exclusion still lets us split multi-language values like
// {en}https://a.com{fr}https://b.com and strip the {en} prefixes.
final _urlRegex = RegExp(
  r'[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^{}"]+|[a-zA-Z0-9.-]+\.[a-z]{2,}(?:\/[^{}"]*)?',
  caseSensitive: false,
);

// Literal backslash-r / backslash-n sequences (two characters each) that some
// mods carry inside URL values; TTS ignores them, so do we.
final _literalCrLf = RegExp(r'\\[rn]');

// Single combined regex built once from all AssetType json keys.
// - alternation of every asset key in one pass (group 1 = key)
// - \\* before each quote tolerates escaped JSON embedded in Lua scripts
//   (e.g. \"MeshURL\": \"https://...\" spawned at runtime via spawnObjectJSON)
// - value capture (group 2) stops at the first " or \, i.e. the quote or the
//   \" that closes the value
final _assetUrlRegex = (() {
  final assetKeys = [for (final value in AssetType.values) ...value.jsonKeys]
      .map(RegExp.escape)
      .join('|');

  // Case-sensitive on purpose: TTS keys are exact (`URL`, not `url`).
  return RegExp('\\\\*"($assetKeys)\\\\*"\\s*:\\s*\\\\*"([^"\\\\]*)');
})();

// Fast regex-based URL extraction using exact AssetType json keys.
// Matches both plain JSON ("MeshURL": "...") and asset URLs embedded as escaped
// JSON inside Lua scripts (\"MeshURL\": \"...\") in a single pass.
Map<String, String> _extractUrlsWithRegex(String jsonString) {
  final urls = <String, String>{};

  for (final match in _assetUrlRegex.allMatches(jsonString)) {
    final key = match.group(1);
    final url = match.group(2);
    if (key != null && url != null && url.isNotEmpty) {
      urls[url] = key;
    }
  }

  return urls;
}

// Separates one url into multiple entries and/or removes {prefix} such as {en}
// Example input urlKey:
// {en}https://www.en-example.com{fr}https://www.fr-example.com
Map<String, String> _processUrl(String urlKey, String value) {
  final matches = _urlRegex.allMatches(urlKey);

  final urls = matches.map((m) => m.group(0)).nonNulls.toList();

  final finalUrls = <String, String>{};
  for (final url in urls) {
    // Remove literal \r and \n
    final trimmedUrl = url.replaceAll(_literalCrLf, '');
    finalUrls[trimmedUrl] = value;
  }

  return finalUrls;
}

/// Extracts every asset URL from the raw text of a TTS JSON file.
///
/// Returns a map of URL to the JSON property name it was found under (one of
/// [AssetType.jsonKeys]). The text is never parsed as JSON: a single regex
/// pass handles both plain JSON and asset URLs embedded as escaped JSON in Lua
/// scripts. `file:/` values are skipped, `{en}`-style language prefixes are
/// dropped (splitting the value into one entry per language), literal `\r`
/// and `\n` sequences are removed and the legacy Steam Cloud host is rewritten
/// via [normalizeSteamUrl]. When the same URL appears under several keys the
/// last key wins, as in v2.
Map<String, String> extractAssetUrls(String jsonText) {
  final urls = _extractUrlsWithRegex(jsonText);

  final finalUrls = <String, String>{};

  for (final url in urls.entries) {
    if (url.key.startsWith('file:/')) {
      continue;
    }

    final processedUrls = _processUrl(url.key, url.value);
    finalUrls.addAll(processedUrls);
  }

  return finalUrls.map((key, value) => MapEntry(normalizeSteamUrl(key), value));
}

/// Same as [extractAssetUrls] but with the [AssetType] resolved for each entry.
///
/// Order follows [extractAssetUrls] (first occurrence in the text).
List<AssetUrl> extractAssetUrlsTyped(String jsonText) => [
  for (final entry in extractAssetUrls(jsonText).entries)
    AssetUrl(
      url: entry.key,
      jsonKey: entry.value,
      // Keys come from the AssetType.jsonKeys alternation, so this never fails.
      type: AssetType.fromJsonKey(entry.value)!,
    ),
];
