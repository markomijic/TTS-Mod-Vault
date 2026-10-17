/// The pure text rewrite behind "Update URL prefixes" (v2
/// `updateUrlPrefixesFilesIsolate`, without the file IO).
library;

import 'package:tts_mod_vault/domain/constants.dart';

/// Host of the legacy Steam Cloud URLs, as matched by the v2 special case.
const String legacyCloudHost = 'http://cloud-3.steamusercontent.com';

/// Host of the current Steam user-content URLs, as matched by the v2
/// special case.
const String akamaiHost = 'https://steamusercontent-a.akamaihd.net';

/// Outcome of [applyUrlPrefixes].
final class UpdateUrlPrefixesResult {
  /// Creates a result.
  const UpdateUrlPrefixesResult({
    required this.text,
    required this.updated,
    required this.renames,
  });

  /// The rewritten JSON text ([updated] false: identical to the input).
  final String text;

  /// Whether any replacement was made.
  final bool updated;

  /// `(oldUrl, newUrl)` for every asset URL that matched an old prefix, in
  /// the order the matches were found; the caller renames the cached files.
  /// Empty for the legacy-host special case, which rewrites the text
  /// globally without going through the asset list.
  final List<(String oldUrl, String newUrl)> renames;

  @override
  String toString() =>
      'UpdateUrlPrefixesResult(updated: $updated, renames: ${renames.length})';
}

/// Rewrites the asset URLs of [jsonText] that start with any of
/// [oldPrefixes] to start with [newPrefix] instead, exactly as v2 did:
///
/// * for every asset URL and every old prefix, when the URL starts with the
///   prefix, every occurrence of the whole URL in the text is replaced by
///   the URL with the prefix swapped, and the pair is recorded in
///   [UpdateUrlPrefixesResult.renames];
/// * when an old prefix contains the legacy Steam Cloud host and the new
///   prefix contains the Akamai host, the old prefix itself is replaced
///   globally in the text (no per-URL matching, no renames): the asset URLs
///   are stored host-normalised, so they would never match the legacy
///   prefix, while the file still carries it.
///
/// [assetUrls] are the mod's asset URLs as indexed; an empty list yields no
/// change, like in v2 (the loop never runs). Pure: no IO.
UpdateUrlPrefixesResult applyUrlPrefixes(
  String jsonText, {
  required List<String> oldPrefixes,
  required String newPrefix,
  required Iterable<String> assetUrls,
}) {
  var text = jsonText;
  var updated = false;
  final renames = <(String, String)>[];
  for (final url in assetUrls) {
    for (final oldPrefix in oldPrefixes) {
      if (oldPrefix.contains(legacyCloudHost) &&
          newPrefix.contains(akamaiHost)) {
        text = text.replaceAll(oldPrefix, newPrefix);
        updated = true;
        continue;
      }
      if (url.startsWith(oldPrefix)) {
        final newUrl = url.replaceFirst(oldPrefix, newPrefix);
        text = text.replaceAll(url, newUrl);
        updated = true;
        renames.add((url, newUrl));
      }
    }
  }
  return UpdateUrlPrefixesResult(
    text: text,
    updated: updated,
    renames: List.unmodifiable(renames),
  );
}

/// Splits the "old prefixes" field of the dialog on `|`, trims each part
/// and drops empty ones (`'a | b||'` -> `['a', 'b']`).
List<String> parseOldPrefixes(String input) => [
  for (final part in input.split('|'))
    if (part.trim().isNotEmpty) part.trim(),
];

/// Whether [oldPrefixes] / [newPrefix] trigger the global legacy-host
/// rewrite of [applyUrlPrefixes] (so the UI can explain that no files are
/// renamed in that case).
bool isLegacyHostRewrite(List<String> oldPrefixes, String newPrefix) =>
    newPrefix.contains(akamaiHost) &&
    oldPrefixes.any((prefix) => prefix.contains(legacyCloudHost));

/// Both hosts with their trailing slash, as the domain constants spell them.
const String legacyCloudPrefix = oldCloudUrl;

/// The current host prefix with its trailing slash.
const String akamaiPrefix = newSteamUserContentUrl;
