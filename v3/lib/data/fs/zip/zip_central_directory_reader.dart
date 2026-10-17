import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:file/file.dart' show FileSystem, RandomAccessFile;
import 'package:file/local.dart' show LocalFileSystem;

/// Reads only the central directory from a ZIP file to extract filenames
/// without reading the entire file into memory or spawning external processes.
///
/// Ported verbatim from v2; the file is opened through `package:file` so the
/// reader can be tested on a `MemoryFileSystem`.
///
/// ZIP format reference: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
class ZipCentralDirectoryReader {
  static const int _eocdSignature = 0x06054b50;
  static const int _centralDirSignature = 0x02014b50;
  static const int _zip64EocdLocatorSignature = 0x07064b50;
  static const int _zip64EocdSignature = 0x06064b50;

  /// EOCD is 22 bytes minimum; max zip comment is 65535 bytes.
  static const int _eocdMinSize = 22;
  static const int _eocdMaxSearchSize = 22 + 65535;

  /// Returns the list of file entry names from the zip central directory.
  /// Does NOT read file data — only the structural metadata at the end of
  /// the file. Backslashes in entry names are normalised to `/`.
  ///
  /// Throws a `FileSystemException` when the file cannot be opened; returns
  /// an empty list for a file that is not a readable ZIP archive.
  static Future<List<String>> readFileNames(String zipPath) =>
      readFileNamesWith(zipPath, const LocalFileSystem());

  /// [readFileNames] against an arbitrary [FileSystem].
  static Future<List<String>> readFileNamesWith(
    String zipPath,
    FileSystem fs,
  ) async {
    final raf = await fs.file(zipPath).open();
    try {
      final fileLength = await raf.length();
      if (fileLength < _eocdMinSize) {
        return []; // Too small to be a valid zip
      }
      return await _readFileNamesFromRaf(raf, fileLength);
    } finally {
      await raf.close();
    }
  }

  static Future<List<String>> _readFileNamesFromRaf(
    RandomAccessFile raf,
    int fileLength,
  ) async {
    // Step 1: Find the End of Central Directory record
    final eocd = await _findEOCD(raf, fileLength);
    if (eocd == null) return [];

    var centralDirOffset = eocd.centralDirOffset;
    var centralDirSize = eocd.centralDirSize;
    var totalEntries = eocd.totalEntries;

    // Step 2: Handle ZIP64 if needed (values at their 32-bit max)
    if (centralDirOffset == 0xFFFFFFFF ||
        centralDirSize == 0xFFFFFFFF ||
        totalEntries == 0xFFFF) {
      final zip64 = await _readZip64EOCD(raf, eocd.eocdPosition);
      if (zip64 != null) {
        centralDirOffset = zip64.centralDirOffset;
        centralDirSize = zip64.centralDirSize;
        totalEntries = zip64.totalEntries;
      }
    }

    // Step 3: Read the entire central directory in one I/O operation
    await raf.setPosition(centralDirOffset);
    final centralDirBytes = await raf.read(centralDirSize);

    // Step 4: Parse central directory entries to extract filenames
    return _parseCentralDirectory(centralDirBytes, totalEntries);
  }

  static Future<_EOCDInfo?> _findEOCD(
    RandomAccessFile raf,
    int fileLength,
  ) async {
    // Search backwards from end of file for the EOCD signature.
    final searchSize = fileLength < _eocdMaxSearchSize
        ? fileLength
        : _eocdMaxSearchSize;

    final startPos = fileLength - searchSize;
    await raf.setPosition(startPos);
    final bytes = await raf.read(searchSize);
    final byteData = ByteData.sublistView(bytes);

    // Scan backwards for signature 0x06054b50
    for (var i = bytes.length - _eocdMinSize; i >= 0; i--) {
      if (byteData.getUint32(i, Endian.little) == _eocdSignature) {
        // Validate: comment length should match remaining bytes
        final commentLength = byteData.getUint16(i + 20, Endian.little);
        if (i + _eocdMinSize + commentLength == bytes.length) {
          return _EOCDInfo(
            totalEntries: byteData.getUint16(i + 10, Endian.little),
            centralDirSize: byteData.getUint32(i + 12, Endian.little),
            centralDirOffset: byteData.getUint32(i + 16, Endian.little),
            eocdPosition: startPos + i,
          );
        }
      }
    }
    return null;
  }

  static Future<_Zip64EOCDInfo?> _readZip64EOCD(
    RandomAccessFile raf,
    int eocdPosition,
  ) async {
    // ZIP64 EOCD Locator is 20 bytes, immediately before the EOCD
    if (eocdPosition < 20) return null;

    await raf.setPosition(eocdPosition - 20);
    final locatorBytes = await raf.read(20);
    final locatorData = ByteData.sublistView(locatorBytes);

    if (locatorData.getUint32(0, Endian.little) != _zip64EocdLocatorSignature) {
      return null;
    }

    final zip64EocdOffset = locatorData.getUint64(8, Endian.little);

    // Read ZIP64 EOCD record (56 bytes minimum)
    await raf.setPosition(zip64EocdOffset);
    final eocd64Bytes = await raf.read(56);
    final eocd64Data = ByteData.sublistView(eocd64Bytes);

    if (eocd64Data.getUint32(0, Endian.little) != _zip64EocdSignature) {
      return null;
    }

    return _Zip64EOCDInfo(
      totalEntries: eocd64Data.getUint64(32, Endian.little),
      centralDirSize: eocd64Data.getUint64(40, Endian.little),
      centralDirOffset: eocd64Data.getUint64(48, Endian.little),
    );
  }

  static List<String> _parseCentralDirectory(
    Uint8List bytes,
    int expectedEntries,
  ) {
    final names = <String>[];
    var offset = 0;
    final byteData = ByteData.sublistView(bytes);

    while (offset + 46 <= bytes.length) {
      // Verify central directory entry signature
      if (byteData.getUint32(offset, Endian.little) != _centralDirSignature) {
        break;
      }

      final fileNameLength = byteData.getUint16(offset + 28, Endian.little);
      final extraFieldLength = byteData.getUint16(offset + 30, Endian.little);
      final commentLength = byteData.getUint16(offset + 32, Endian.little);

      // Extract filename
      if (offset + 46 + fileNameLength <= bytes.length) {
        final nameBytes = bytes.sublist(
          offset + 46,
          offset + 46 + fileNameLength,
        );
        final name = String.fromCharCodes(nameBytes);
        // Normalize backslashes to forward slashes
        names.add(name.replaceAll(r'\', '/'));
      }

      // Move to next entry
      offset += 46 + fileNameLength + extraFieldLength + commentLength;
    }

    return names;
  }
}

class _EOCDInfo {
  _EOCDInfo({
    required this.totalEntries,
    required this.centralDirSize,
    required this.centralDirOffset,
    required this.eocdPosition,
  });

  final int totalEntries;
  final int centralDirSize;
  final int centralDirOffset;
  final int eocdPosition;
}

class _Zip64EOCDInfo {
  _Zip64EOCDInfo({
    required this.totalEntries,
    required this.centralDirSize,
    required this.centralDirOffset,
  });

  final int totalEntries;
  final int centralDirSize;
  final int centralDirOffset;
}
