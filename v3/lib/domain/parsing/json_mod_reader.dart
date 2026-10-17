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
import 'dart:typed_data';

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

  /// Bytes of the file head decoded for the header regexes in [readFull].
  static const int headerPrefixBytes = 64 * 1024;

  /// Reads the whole file at [path] once: header, asset URLs and file stat.
  ///
  /// The file is read as bytes and never decoded as a whole: the URLs come
  /// from [extractAssetUrlsFromBytes] and the header regexes run on a decoded
  /// prefix of [headerPrefixBytes] (cut at a line break, so a match found
  /// there is complete and is the first in the file). Only when the prefix
  /// lacks the name or `EpochTime` is the whole file decoded, which is what
  /// v2 and the earlier `readAsString` implementation always did. Malformed
  /// UTF-8 anywhere in the file still fails it with the same
  /// [FileSystemException] `readAsString` threw.
  Future<ModParseResult> readFull(String path, ModType type) async {
    final file = fileSystem.file(path);
    final baseName = p.basenameWithoutExtension(path);

    final bytes = await file.readAsBytes();
    // Sync on purpose: this runs on a worker isolate and `avoid_slow_async_io`
    // flags the async variant.
    final stat = file.statSync();

    final isSavedObject = type == ModType.savedObject;
    final List<AssetUrl> assets;
    String? saveName;
    String? nickname;
    int? epochTime;
    try {
      assets = extractAssetUrlsTypedFromBytes(bytes);
      final prefix = _decodeHeaderPrefix(bytes);
      saveName = isSavedObject ? null : extractSaveName(prefix);
      nickname = isSavedObject ? extractNickname(prefix) : null;
      epochTime = extractEpochTimeValue(prefix);
      final nameFound = isSavedObject ? nickname != null : saveName != null;
      if (!nameFound || epochTime == null) {
        final text = utf8.decode(bytes);
        if (isSavedObject) {
          nickname ??= extractNickname(text);
        } else {
          saveName ??= extractSaveName(text);
        }
        epochTime ??= extractEpochTime(text);
      }
    } on FormatException {
      // Same exception `File.readAsString` raises for undecodable bytes.
      throw FileSystemException(
        "Failed to decode data using encoding '${utf8.name}'",
        path,
      );
    }
    final header = _header(
      type: type,
      baseName: baseName,
      saveName: isSavedObject ? baseName : saveName,
      nickname: nickname,
      epochTime: epochTime,
    );

    return ModParseResult(
      header: header,
      assets: assets,
      sizeBytes: stat.size,
      modified: stat.modified,
    );
  }

  /// The decoded head of [bytes]: the whole content when it is short, else
  /// everything before the last line break within [headerPrefixBytes].
  /// Ending at a line break guarantees that a header match inside the prefix
  /// is not cut short (`"EpochTime": 17` for `170000`). A long first line
  /// without any break (minified JSON) yields an empty prefix, which sends
  /// the caller to the full decode.
  static String _decodeHeaderPrefix(Uint8List bytes) {
    if (bytes.length <= headerPrefixBytes) return utf8.decode(bytes);
    final end = bytes.lastIndexOf(0x0A, headerPrefixBytes);
    if (end <= 0) return '';
    return utf8.decoder.convert(bytes, 0, end);
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
