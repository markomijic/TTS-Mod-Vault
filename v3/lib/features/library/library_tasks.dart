/// Worker-pool tasks of the library feature: parsing mod JSONs on worker
/// isolates. The directory scanners live in `data/fs/fs_tasks.dart`.
///
/// Every entry point is a top-level function with one plain, isolate-sendable
/// argument and a plain result, as `WorkerPool.run` requires.
library;

import 'dart:io' show File;

import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/parsing/json_mod_reader.dart';

/// One mod JSON to parse: its path and the [ModType] it is reported as.
typedef ModFileToParse = ({String jsonPath, ModType type});

/// One asset URL of a parsed mod, in the shape `ModsDao.upsertMods` takes.
typedef ParsedAsset = ({String url, String assetKey, AssetType type});

/// Input of [parseModFiles]: a batch of files read by one worker.
///
/// The caller decides the batch size (see `LibraryController` for the
/// adaptive rule); the task reads the files one after another.
final class ParseModsRequest {
  /// Creates a request for [files].
  const ParseModsRequest({required this.files});

  /// Files to parse, in the order the results are returned.
  final List<ModFileToParse> files;
}

/// Result of parsing one mod JSON with `JsonModReader.readFull`.
///
/// When reading or parsing failed, [error] holds the problem's description
/// and the other fields carry placeholder values (empty name, no assets,
/// zero stat); the batch itself never fails because of one file.
final class ParsedMod {
  /// Creates a parse result.
  const ParsedMod({
    required this.jsonPath,
    required this.type,
    required this.saveName,
    required this.epochTime,
    required this.sizeBytes,
    required this.mtimeMs,
    required this.assets,
    this.error,
  });

  /// Builds the placeholder result for a file that could not be read.
  const ParsedMod.failed({
    required this.jsonPath,
    required this.type,
    required String this.error,
  }) : saveName = '',
       epochTime = null,
       sizeBytes = 0,
       mtimeMs = 0,
       assets = const [];

  /// Path exactly as given in the request.
  final String jsonPath;

  /// Type exactly as given in the request.
  final ModType type;

  /// Display name resolved by the reader (`SaveName`, else the basename).
  final String saveName;

  /// Save time in Unix seconds, or null when the JSON carries no date.
  final int? epochTime;

  /// File size in bytes at read time.
  final int sizeBytes;

  /// File mtime in milliseconds since epoch at read time.
  final int mtimeMs;

  /// Every asset URL found in the file, with its JSON key and type.
  final List<ParsedAsset> assets;

  /// Why the file could not be parsed, or null on success.
  final String? error;

  /// Whether the file was parsed successfully.
  bool get isOk => error == null;

  @override
  String toString() => error == null
      ? 'ParsedMod($jsonPath, $saveName, ${assets.length} assets)'
      : 'ParsedMod($jsonPath, error: $error)';
}

/// Parses every file of [req] with `JsonModReader.readFull` and returns one
/// [ParsedMod] per file in request order. Per-file failures are captured in
/// `ParsedMod.error`; the function itself does not throw for them.
///
/// Worker entry point for `WorkerPool.run`.
Future<List<ParsedMod>> parseModFiles(ParseModsRequest req) async {
  const reader = JsonModReader();
  final results = <ParsedMod>[];
  for (final file in req.files) {
    try {
      final parsed = await reader.readFull(file.jsonPath, file.type);
      results.add(
        ParsedMod(
          jsonPath: file.jsonPath,
          type: file.type,
          saveName: parsed.header.saveName,
          epochTime: parsed.header.epochTime,
          sizeBytes: parsed.sizeBytes,
          mtimeMs: parsed.modified.millisecondsSinceEpoch,
          assets: [
            for (final asset in parsed.assets)
              (url: asset.url, assetKey: asset.jsonKey, type: asset.type),
          ],
        ),
      );
    } catch (error) {
      results.add(
        ParsedMod.failed(
          jsonPath: file.jsonPath,
          type: file.type,
          error: error.toString(),
        ),
      );
    }
  }
  return results;
}

/// Finds the sibling image of the mod JSON at [jsonPath]: `<dir>/<name>.png`
/// is preferred over `<dir>/Thumbnails/<name>.png` (the rule of
/// `scanModFiles`, applied to one file). Returns the normalised path or null.
///
/// Worker entry point used when a single mod is refreshed; a full scan gets
/// the image path from the directory listing instead.
String? findModImagePath(String jsonPath) {
  final dir = p.dirname(jsonPath);
  final name = p.basenameWithoutExtension(jsonPath);
  for (final candidate in [
    p.join(dir, '$name.png'),
    p.join(dir, ttsThumbnailsFolder, '$name.png'),
  ]) {
    if (File(candidate).existsSync()) return p.normalize(candidate);
  }
  return null;
}
