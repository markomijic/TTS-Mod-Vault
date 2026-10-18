/// Worker-pool task of the URL prefix update: reads a mod JSON, applies
/// [applyUrlPrefixes] and writes the result back, all on the worker so a
/// 100 MB file never crosses the isolate boundary.
library;

import 'package:file/local.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_prefix_rules.dart';

/// Argument of [rewriteUrlPrefixesInFile]. Plain data, sendable to a worker.
final class UrlPrefixFileRequest {
  /// Creates a request.
  const UrlPrefixFileRequest({
    required this.jsonPath,
    required this.oldPrefixes,
    required this.newPrefix,
    required this.assetUrls,
  });

  /// The mod JSON to rewrite.
  final String jsonPath;

  /// Prefixes to replace.
  final List<String> oldPrefixes;

  /// The replacement prefix.
  final String newPrefix;

  /// The mod's asset URLs as indexed.
  final List<String> assetUrls;
}

/// Result of [rewriteUrlPrefixesInFile].
final class UrlPrefixFileResult {
  /// Creates a result.
  const UrlPrefixFileResult({required this.updated, required this.renames});

  /// Whether the file was rewritten.
  final bool updated;

  /// `(oldUrl, newUrl)` pairs whose cached files may need renaming.
  final List<(String oldUrl, String newUrl)> renames;
}

/// Reads `req.jsonPath`, applies the prefix rules and, when the text
/// changed, writes it back preserving the file's creation time. Throws on
/// IO errors; the caller logs them with the mod's context.
Future<UrlPrefixFileResult> rewriteUrlPrefixesInFile(
  UrlPrefixFileRequest req,
) async {
  const fs = LocalFileSystem();
  final text = await fs.file(req.jsonPath).readAsString();
  final result = applyUrlPrefixes(
    text,
    oldPrefixes: req.oldPrefixes,
    newPrefix: req.newPrefix,
    assetUrls: req.assetUrls,
  );
  final changed = result.updated && result.text != text;
  if (changed) {
    await fs.writeStringPreservingCreationTime(req.jsonPath, result.text);
  }
  return UrlPrefixFileResult(updated: changed, renames: result.renames);
}
