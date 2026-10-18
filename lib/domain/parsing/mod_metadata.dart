/// Header metadata (name, save date) and in-place edits of TTS JSON text.
///
/// Ported from v2 `mods_isolates.dart` (`saveNameRegex`, `nicknameRegex`,
/// `extractDateTimeStampFromString`, `renameModSaveNameIsolate`) and
/// `mods.dart` (`_replaceUrlInJsonFile`). Everything here works on text, never
/// on a decoded JSON tree, so a 100 MB mod is handled as cheaply as a 1 KB one.
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:intl/intl.dart' show DateFormat;
import 'package:tts_mod_vault/domain/constants.dart';

// A JSON string value: any run of non-quote, non-backslash characters or
// backslash escapes. Unlike v2's `[^"]*` this does not stop at an escaped
// quote inside the value (`"My \"Great\" Mod"`), which v2 truncated to
// `My \`.
const _jsonStringValue = r'((?:[^"\\]|\\.)*)';

final _saveNameRegex = RegExp('"SaveName"\\s*:\\s*"$_jsonStringValue"');
final _nicknameRegex = RegExp('"Nickname"\\s*:\\s*"$_jsonStringValue"');

// "EpochTime": value pattern (numeric, already in Unix timestamp format)
final _epochRegex = RegExp(r'"EpochTime"\s*:\s*(\d+)');

// "Date":"value" pattern, converted to a Unix timestamp as a fallback
final _dateRegex = RegExp('"Date"\\s*:\\s*"$_jsonStringValue"');

/// Decodes the JSON escapes of a raw string value; returns the raw text when
/// it is not a valid JSON string body.
String _unescape(String raw) {
  if (!raw.contains(r'\')) return raw;
  try {
    return jsonDecode('"$raw"') as String;
  } on FormatException {
    return raw;
  }
}

/// The first `"SaveName"` value in [text] (JSON escapes decoded), or null when
/// the key is absent. Mods and saves carry it on their first line.
String? extractSaveName(String text) {
  final raw = _saveNameRegex.firstMatch(text)?.group(1);
  return raw == null ? null : _unescape(raw);
}

/// The first `"Nickname"` value in [text] (JSON escapes decoded), or null when
/// the key is absent. Used for saved objects, whose `SaveName` is empty and
/// whose only object sits in `ObjectStates`.
String? extractNickname(String text) {
  final raw = _nicknameRegex.firstMatch(text)?.group(1);
  return raw == null ? null : _unescape(raw);
}

/// The mod's save time as Unix seconds, or null if [text] carries neither a
/// numeric `"EpochTime"` nor a parseable `"Date"`.
///
/// `EpochTime` is preferred (it is what TTS writes since 2020 and what Workshop
/// downloads get injected). `Date` is parsed with `M/d/yyyy h:mm:ss a` when it
/// contains AM/PM, otherwise with `MM/dd/yyyy HH:mm:ss`, as local time.
int? extractEpochTime(String text) {
  final epochValue = extractEpochTimeValue(text);
  if (epochValue != null) return epochValue;

  final dateValue = _dateRegex.firstMatch(text)?.group(1);
  if (dateValue != null && dateValue.isNotEmpty) {
    return _dateToUnixSeconds(dateValue);
  }

  return null;
}

/// The first numeric `"EpochTime"` in [text], or null when the key is absent
/// or its value does not parse. Unlike [extractEpochTime] this never falls
/// back to `"Date"`, so a caller that only has the head of a file can tell
/// "found" from "not in this part".
int? extractEpochTimeValue(String text) {
  final epochValue = _epochRegex.firstMatch(text)?.group(1);
  if (epochValue == null || epochValue.isEmpty) return null;
  return int.tryParse(epochValue);
}

int? _dateToUnixSeconds(String dateValue) {
  try {
    // These patterns parse the dates TTS writes into mod files, not UI text,
    // so they stay pinned to en_US whatever language the app is shown in.
    final upper = dateValue.toUpperCase();
    final format = upper.contains('AM') || upper.contains('PM')
        ? DateFormat('M/d/yyyy h:mm:ss a', 'en_US')
        : DateFormat('MM/dd/yyyy HH:mm:ss', 'en_US');

    final dateTime = format.tryParse(dateValue);
    if (dateTime == null) return null;

    return dateTime.millisecondsSinceEpoch ~/ 1000;
  } on Exception {
    return null;
  }
}

/// Replaces the first `"SaveName"` value in [jsonText] with [newName].
///
/// Only the captured value is replaced so the key, spacing and surrounding
/// quotes are preserved; [newName] is JSON-escaped. Returns [jsonText]
/// unchanged when it has no `"SaveName"` property (e.g. saved objects).
String replaceSaveName(String jsonText, String newName) {
  final match = _saveNameRegex.firstMatch(jsonText);
  if (match == null) return jsonText;

  // jsonEncode returns a quoted, escaped string; strip the surrounding quotes
  // to get the inner content that goes between the existing quotes.
  final encoded = jsonEncode(newName);
  final escapedInner = encoded.substring(1, encoded.length - 1);

  // The match always ends with `"<value>"`, so the captured value occupies the
  // range just before the final closing quote. Replacing only that range keeps
  // the key, spacing and quotes intact. (Dart's Match has no per-group offsets.)
  final full = match.group(0)!;
  final oldValue = match.group(1)!;
  final innerStart = match.start + (full.length - 1 - oldValue.length);
  final innerEnd = match.start + full.length - 1;

  return jsonText.replaceRange(innerStart, innerEnd, escapedInner);
}

/// Replaces every occurrence of [oldUrl] in [jsonText] with [newUrl].
///
/// Asset URLs are normalised to the current Steam host when extracted, so the
/// file may still contain [oldUrl] in its legacy `cloud-3.steamusercontent.com`
/// form. When it does, that form is what gets replaced.
String replaceUrl(String jsonText, String oldUrl, String newUrl) {
  final oldUrlAsCloudUrl = oldUrl.startsWith(newSteamUserContentUrl)
      ? oldUrl.replaceFirst(newSteamUserContentUrl, oldCloudUrl)
      : '';

  final targetUrl =
      oldUrlAsCloudUrl.isNotEmpty && jsonText.contains(oldUrlAsCloudUrl)
      ? oldUrlAsCloudUrl
      : oldUrl;

  return jsonText.replaceAll(targetUrl, newUrl);
}
