/// Reads TTS JSON files from disk: a cheap streamed header read for the
/// library index and a single full read for URL extraction.
///
/// Ported from v2 `mods_isolates.dart` (`_extractInitialModMetadataFromFile`,
/// `_readFileInChunks`, `_processSingleFileOptimized`). Both methods are safe
/// to call from a worker isolate through a top-level wrapper: the only state
/// they touch is the [FileSystem], which defaults to the const
/// [LocalFileSystem].
library;

import 'dart:convert' show LineSplitter, utf8;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/parsing/mod_metadata.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';

/// The metadata the library index needs from the head of a mod JSON.
final class ModHeader {
  /// Creates a header.
  const ModHeader({
    required this.saveName,
    required this.epochTime,
    this.nickname,
  });

  /// Display name: the trimmed `SaveName`, or the file's basename without
  /// extension when the key is missing or empty. Saved objects always use the
  /// basename (as in v2); see [nickname].
  final String saveName;

  /// Save time as Unix seconds (`EpochTime`, else parsed `Date`), or null.
  final int? epochTime;

  /// The first `Nickname` in the file. Only looked up for
  /// [ModType.savedObject]; null for mods and saves.
  final String? nickname;

  @override
  bool operator ==(Object other) =>
      other is ModHeader &&
      other.saveName == saveName &&
      other.epochTime == epochTime &&
      other.nickname == nickname;

  @override
  int get hashCode => Object.hash(saveName, epochTime, nickname);

  @override
  String toString() =>
      'ModHeader($saveName, epochTime: $epochTime, nickname: $nickname)';
}

/// Everything a single full read of a mod JSON yields.
final class ModParseResult {
  /// Creates a parse result.
  const ModParseResult({
    required this.header,
    required this.assets,
    required this.sizeBytes,
    required this.modified,
  });

  /// Header metadata, resolved with the same rules as
  /// [JsonModReader.readHeader].
  final ModHeader header;

  /// All asset URLs in the file, see [extractAssetUrlsTyped].
  final List<AssetUrl> assets;

  /// File size in bytes at read time.
  final int sizeBytes;

  /// File modification time at read time.
  final DateTime modified;

  @override
  String toString() =>
      'ModParseResult($header, ${assets.length} assets, $sizeBytes bytes, '
      'modified: $modified)';
}

/// Reads mod JSON files through a [FileSystem] (tests use `MemoryFileSystem`).
final class JsonModReader {
  /// Creates a reader; [fileSystem] defaults to the real disk.
  const JsonModReader({this.fileSystem = const LocalFileSystem()});

  /// The file system all paths are resolved against.
  final FileSystem fileSystem;

  /// Lines per chunk handed to the header regexes (v2 value).
  static const _headerChunkLines = 10;

  /// Reads only as much of the file at [path] as needed to find the header.
  ///
  /// The file is streamed in chunks of ten lines and the read stops as soon
  /// as both the name and the save time are known, so for a typical mod only
  /// the first few hundred bytes are read. A file missing either key is read
  /// to the end, which is how v2 behaved too.
  Future<ModHeader> readHeader(String path, ModType type) async {
    final file = fileSystem.file(path);
    final baseName = p.basenameWithoutExtension(path);

    String? saveName;
    String? nickname;
    int? epochTime;

    await for (final chunk in _readFileInChunks(file, _headerChunkLines)) {
      if (type == ModType.savedObject) {
        saveName = baseName;
        nickname ??= extractNickname(chunk);
      } else {
        saveName ??= extractSaveName(chunk);
      }
      epochTime ??= extractEpochTime(chunk);

      // If we found everything, we can stop
      final nameDone = type == ModType.savedObject
          ? nickname != null
          : saveName != null;
      if (nameDone && epochTime != null) {
        break;
      }
    }

    return _header(
      type: type,
      baseName: baseName,
      saveName: saveName,
      nickname: nickname,
      epochTime: epochTime,
    );
  }

  /// Reads the whole file at [path] once: header, asset URLs and file stat.
  Future<ModParseResult> readFull(String path, ModType type) async {
    final file = fileSystem.file(path);
    final baseName = p.basenameWithoutExtension(path);

    final text = await file.readAsString();
    // Sync on purpose: this runs on a worker isolate and `avoid_slow_async_io`
    // flags the async variant.
    final stat = file.statSync();

    final isSavedObject = type == ModType.savedObject;
    final header = _header(
      type: type,
      baseName: baseName,
      saveName: isSavedObject ? baseName : extractSaveName(text),
      nickname: isSavedObject ? extractNickname(text) : null,
      epochTime: extractEpochTime(text),
    );

    return ModParseResult(
      header: header,
      assets: extractAssetUrlsTyped(text),
      sizeBytes: stat.size,
      modified: stat.modified,
    );
  }

  static ModHeader _header({
    required ModType type,
    required String baseName,
    required String? saveName,
    required String? nickname,
    required int? epochTime,
  }) {
    final trimmed = (saveName ?? baseName).trim();
    return ModHeader(
      saveName: trimmed.isNotEmpty ? trimmed : baseName,
      epochTime: epochTime,
      nickname: type == ModType.savedObject ? nickname : null,
    );
  }

  static Stream<String> _readFileInChunks(File file, int linesPerChunk) async* {
    final lines = <String>[];
    var lineCount = 0;

    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      lines.add(line);
      lineCount++;

      // When we reach chunk size, yield the chunk and reset
      if (lineCount % linesPerChunk == 0) {
        yield lines.join('\n');
        lines.clear();
      }
    }

    // Yield any remaining lines
    if (lines.isNotEmpty) {
      yield lines.join('\n');
    }
  }
}
