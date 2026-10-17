/// Extraction of asset URLs from TTS save-file JSON text.
///
/// This is a behaviour-preserving port of v2 `mods_isolates.dart`
/// (`_assetUrlRegex`, `_extractUrlsWithRegex`, `_processUrl`,
/// `extractUrlsFromJsonString`). The comments document hard-won edge cases;
/// every one of them is covered by
/// `test/domain/parsing/url_extraction_test.dart`.
///
/// Two front ends share the same post-processing: the original regex over a
/// decoded [String] ([extractAssetUrls]) and a byte scanner over the raw
/// UTF-8 file content ([extractAssetUrlsFromBytes]) that reproduces the
/// regex's matches without decoding the whole file first. The library
/// refresh uses the byte scanner; on a 68 MB mod it replaces ~170 ms of UTF-8
/// decoding plus ~450 ms of regex scanning with a ~60 ms pass over the bytes.
library;

import 'dart:convert' show Utf8Decoder;
import 'dart:typed_data';

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
Map<String, String> extractAssetUrls(String jsonText) =>
    _finishUrls(_extractUrlsWithRegex(jsonText));

/// [extractAssetUrls] over the raw UTF-8 [bytes] of a mod JSON.
///
/// Returns what `extractAssetUrls(utf8.decode(bytes))` would, without
/// building the decoded text: the scanner walks the bytes once, reproducing
/// the regex's matches exactly (same keys, same whitespace set, same
/// non-overlapping left-to-right semantics; see `_scanUrlsInBytes`), and
/// decodes only the matched values. Like `utf8.decode`, it throws a
/// [FormatException] on malformed UTF-8 anywhere in [bytes] (the scan
/// validates every multi-byte sequence it steps over), so a corrupt file
/// fails the same way it did when the whole text was decoded first.
Map<String, String> extractAssetUrlsFromBytes(Uint8List bytes) =>
    _finishUrls(_scanUrlsInBytes(bytes));

/// Same as [extractAssetUrlsFromBytes] with the [AssetType] resolved for each
/// entry; the byte-level twin of [extractAssetUrlsTyped].
List<AssetUrl> extractAssetUrlsTypedFromBytes(Uint8List bytes) =>
    _typed(extractAssetUrlsFromBytes(bytes));

// Shared second pass: drop file:/ values, split multi-language values, strip
// literal \r\n and rewrite the legacy Steam host.
Map<String, String> _finishUrls(Map<String, String> urls) {
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

List<AssetUrl> _typed(Map<String, String> urls) => [
  for (final entry in urls.entries)
    AssetUrl(
      url: entry.key,
      jsonKey: entry.value,
      // Keys come from the AssetType.jsonKeys set, so this never fails.
      type: AssetType.fromJsonKey(entry.value)!,
    ),
];

// ---------------------------------------------------------------------------
// Byte scanner: `_assetUrlRegex` without the regex.
//
// The regex is  \\*"(KEY)\\*"\s*:\s*\\*"([^"\\]*)  with KEY an alternation of
// `AssetType.jsonKeys`. Observations that make a byte-level twin exact:
//  * A match can only start at a `"` (or at backslashes directly before one,
//    which changes nothing about the captured groups), so only quote
//    positions need to be tried.
//  * KEY is delimited by the `"`/`\` that follows it, so at most one key can
//    match at a position; the alternation's backtracking collapses to a set
//    lookup on the bytes between the quote and the next `"` or `\`.
//  * `"`, `\`, `:` and ASCII whitespace never occur inside a multi-byte UTF-8
//    sequence, so every boundary the regex decides on is a byte boundary.
//  * `\s` (ECMAScript, non-unicode mode) is a fixed set whose non-ASCII
//    members have fixed UTF-8 encodings (`_skipWhitespace`).
//  * `[^"\\]*` ends at the first `"` or `\` or at the end of input, exactly
//    as `_valueEnd` finds it.
//  * `allMatches` resumes after a match's end; the scanner does the same.
// ---------------------------------------------------------------------------

const int _quote = 0x22;
const int _backslash = 0x5C;
const int _colon = 0x3A;

/// `AssetType.jsonKeys` as UTF-8 bytes, grouped by first byte for a cheap
/// reject of the (very common) quotes that do not start an asset key.
final List<List<_KeyBytes>?> _keysByFirstByte = () {
  final table = List<List<_KeyBytes>?>.filled(256, null);
  for (final type in AssetType.values) {
    for (final key in type.jsonKeys) {
      final bytes = Uint8List.fromList(key.codeUnits);
      (table[bytes[0]] ??= []).add(_KeyBytes(key, bytes));
    }
  }
  return table;
}();

final class _KeyBytes {
  const _KeyBytes(this.key, this.bytes);

  final String key;
  final Uint8List bytes;
}

/// Byte-level `_extractUrlsWithRegex`: URL to JSON key, first occurrence
/// order, last key wins for a repeated URL.
Map<String, String> _scanUrlsInBytes(Uint8List bytes) {
  final urls = <String, String>{};
  final n = bytes.length;
  var i = 0;
  while (i < n) {
    // Next quote; non-ASCII bytes on the way are validated as UTF-8.
    while (i < n) {
      final b = bytes[i];
      if (b == _quote) break;
      i += b < 0x80 ? 1 : _utf8SequenceLength(bytes, i, n);
    }
    if (i >= n) break;
    final quote = i;
    i = quote + 1;

    final key = _keyAt(bytes, quote + 1, n);
    if (key == null) continue;

    // KEY \\* "
    var j = quote + 1 + key.bytes.length;
    while (j < n && bytes[j] == _backslash) {
      j++;
    }
    if (j >= n || bytes[j] != _quote) continue;
    // \s* : \s*
    j = _skipWhitespace(bytes, j + 1, n);
    if (j >= n || bytes[j] != _colon) continue;
    j = _skipWhitespace(bytes, j + 1, n);
    // \\* "
    while (j < n && bytes[j] == _backslash) {
      j++;
    }
    if (j >= n || bytes[j] != _quote) continue;
    // ([^"\\]*)
    final valueStart = j + 1;
    final valueEnd = _valueEnd(bytes, valueStart, n);
    if (valueEnd > valueStart) {
      urls[_decodeValue(bytes, valueStart, valueEnd)] = key.key;
    }
    // Resume after the match, like allMatches.
    i = valueEnd;
  }
  return urls;
}

/// The asset key whose bytes sit at [start] followed by `"` or `\`, or null.
_KeyBytes? _keyAt(Uint8List bytes, int start, int n) {
  if (start >= n) return null;
  final candidates = _keysByFirstByte[bytes[start]];
  if (candidates == null) return null;
  for (final candidate in candidates) {
    final keyBytes = candidate.bytes;
    final end = start + keyBytes.length;
    if (end >= n) continue;
    final next = bytes[end];
    if (next != _quote && next != _backslash) continue;
    var matches = true;
    for (var k = 1; k < keyBytes.length; k++) {
      if (bytes[start + k] != keyBytes[k]) {
        matches = false;
        break;
      }
    }
    if (matches) return candidate;
  }
  return null;
}

/// Index of the first `"` or `\` at or after [start], or [n]. Non-ASCII
/// bytes on the way are validated as UTF-8.
int _valueEnd(Uint8List bytes, int start, int n) {
  var i = start;
  while (i < n) {
    final b = bytes[i];
    if (b == _quote || b == _backslash) return i;
    i += b < 0x80 ? 1 : _utf8SequenceLength(bytes, i, n);
  }
  return n;
}

/// Length of the well-formed UTF-8 sequence starting with the non-ASCII
/// lead byte at [i], per the Unicode well-formed byte sequence table (which
/// is also what `utf8.decode` enforces: no overlongs, no surrogates, nothing
/// above U+10FFFF). Throws [FormatException] otherwise.
int _utf8SequenceLength(Uint8List bytes, int i, int n) {
  final lead = bytes[i];
  int length;
  int secondMin = 0x80;
  int secondMax = 0xBF;
  if (lead >= 0xC2 && lead <= 0xDF) {
    length = 2;
  } else if (lead >= 0xE0 && lead <= 0xEF) {
    length = 3;
    if (lead == 0xE0) secondMin = 0xA0;
    if (lead == 0xED) secondMax = 0x9F;
  } else if (lead >= 0xF0 && lead <= 0xF4) {
    length = 4;
    if (lead == 0xF0) secondMin = 0x90;
    if (lead == 0xF4) secondMax = 0x8F;
  } else {
    throw FormatException('Invalid UTF-8 byte', bytes, i);
  }
  if (i + length > n) {
    throw FormatException('Unfinished UTF-8 octet sequence', bytes, i);
  }
  final second = bytes[i + 1];
  if (second < secondMin || second > secondMax) {
    throw FormatException('Invalid UTF-8 continuation byte', bytes, i + 1);
  }
  for (var k = 2; k < length; k++) {
    final b = bytes[i + k];
    if (b < 0x80 || b > 0xBF) {
      throw FormatException('Invalid UTF-8 continuation byte', bytes, i + k);
    }
  }
  return length;
}

/// Skips what the regex `\s` matches: ASCII `\t\n\v\f\r ` plus U+00A0,
/// U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000 and U+FEFF
/// in their UTF-8 forms.
int _skipWhitespace(Uint8List bytes, int start, int n) {
  var i = start;
  while (i < n) {
    final b = bytes[i];
    if (b == 0x20 || (b >= 0x09 && b <= 0x0D)) {
      i++;
    } else if (b == 0xC2 && i + 1 < n && bytes[i + 1] == 0xA0) {
      i += 2; // U+00A0
    } else if (b == 0xE1 &&
        i + 2 < n &&
        bytes[i + 1] == 0x9A &&
        bytes[i + 2] == 0x80) {
      i += 3; // U+1680
    } else if (b == 0xE2 && i + 2 < n) {
      final b1 = bytes[i + 1];
      final b2 = bytes[i + 2];
      final isSpace =
          (b1 == 0x80 &&
              ((b2 >= 0x80 && b2 <= 0x8A) || // U+2000-U+200A
                  b2 == 0xA8 || // U+2028
                  b2 == 0xA9 || // U+2029
                  b2 == 0xAF)) || // U+202F
          (b1 == 0x81 && b2 == 0x9F); // U+205F
      if (!isSpace) return i;
      i += 3;
    } else if (b == 0xE3 &&
        i + 2 < n &&
        bytes[i + 1] == 0x80 &&
        bytes[i + 2] == 0x80) {
      i += 3; // U+3000
    } else if (b == 0xEF &&
        i + 2 < n &&
        bytes[i + 1] == 0xBB &&
        bytes[i + 2] == 0xBF) {
      i += 3; // U+FEFF
    } else {
      return i;
    }
  }
  return i;
}

/// Decodes `bytes[start..end)` (already validated by [_valueEnd]) the way a
/// whole-file `utf8.decode` would have decoded that stretch: pure ASCII goes
/// straight to a one-byte string, and a BOM sequence at [start] is kept (the
/// decoder would strip it, but in the full file it is not at offset 0).
String _decodeValue(Uint8List bytes, int start, int end) {
  var ascii = true;
  for (var i = start; i < end; i++) {
    if (bytes[i] >= 0x80) {
      ascii = false;
      break;
    }
  }
  if (ascii) return String.fromCharCodes(bytes, start, end);
  final text = const Utf8Decoder().convert(bytes, start, end);
  if (end - start >= 3 &&
      bytes[start] == 0xEF &&
      bytes[start + 1] == 0xBB &&
      bytes[start + 2] == 0xBF) {
    return '﻿$text';
  }
  return text;
}

/// Same as [extractAssetUrls] but with the [AssetType] resolved for each entry.
///
/// Order follows [extractAssetUrls] (first occurrence in the text).
List<AssetUrl> extractAssetUrlsTyped(String jsonText) =>
    _typed(extractAssetUrls(jsonText));
