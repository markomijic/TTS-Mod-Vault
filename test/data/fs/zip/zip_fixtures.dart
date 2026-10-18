// Builds ZIP archives in memory for the zip reader/counter tests.
//
// `package:archive` normalises entry names to `/` and only writes ZIP64
// structures for entries above 4 GB, so two fixtures byte-patch its output:
// [withBackslashNames] swaps separators inside entry names, and [toZip64]
// replaces the end-of-central-directory record with a ZIP64 EOCD record,
// its locator and an EOCD whose 32-bit fields are saturated. Both keep the
// local headers and the central directory produced by the encoder intact.

import 'dart:convert' show latin1;
import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:archive/archive.dart';

/// Encodes [files] (name -> bytes) and [directories] as a ZIP, optionally
/// with an archive [comment].
Uint8List buildZip(
  Map<String, List<int>> files, {
  List<String> directories = const [],
  String? comment,
}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  for (final dir in directories) {
    archive.add(ArchiveFile.directory(dir));
  }
  archive.comment = comment;
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Rewrites every occurrence of each name in [names] (which must use `/`)
/// to its backslash form, in both the local headers and the central
/// directory. Lengths are unchanged so all offsets stay valid.
Uint8List withBackslashNames(Uint8List zip, List<String> names) {
  var out = zip;
  for (final name in names) {
    out = _replaceAll(
      out,
      latin1.encode(name),
      latin1.encode(name.replaceAll('/', r'\')),
    );
  }
  return out;
}

/// Converts a comment-less ZIP into a ZIP64 archive: the central directory
/// is kept, followed by a ZIP64 EOCD record, a ZIP64 EOCD locator and an
/// EOCD whose entry count and central directory size/offset are saturated.
Uint8List toZip64(Uint8List zip) {
  const eocdSize = 22;
  final eocd = ByteData.sublistView(zip, zip.length - eocdSize);
  if (eocd.getUint32(0, Endian.little) != 0x06054b50) {
    throw ArgumentError('input does not end with a plain EOCD record');
  }
  final totalEntries = eocd.getUint16(10, Endian.little);
  final cdSize = eocd.getUint32(12, Endian.little);
  final cdOffset = eocd.getUint32(16, Endian.little);
  final zip64EocdOffset = cdOffset + cdSize;

  final zip64Eocd = ByteData(56)
    ..setUint32(0, 0x06064b50, Endian.little)
    ..setUint64(4, 44, Endian.little) // size of the remaining record
    ..setUint16(12, 45, Endian.little) // version made by
    ..setUint16(14, 45, Endian.little) // version needed
    ..setUint32(16, 0, Endian.little) // this disk
    ..setUint32(20, 0, Endian.little) // disk with the central directory
    ..setUint64(24, totalEntries, Endian.little)
    ..setUint64(32, totalEntries, Endian.little)
    ..setUint64(40, cdSize, Endian.little)
    ..setUint64(48, cdOffset, Endian.little);

  final locator = ByteData(20)
    ..setUint32(0, 0x07064b50, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint64(8, zip64EocdOffset, Endian.little)
    ..setUint32(16, 1, Endian.little);

  final saturatedEocd = ByteData(eocdSize)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, 0xFFFF, Endian.little)
    ..setUint16(10, 0xFFFF, Endian.little)
    ..setUint32(12, 0xFFFFFFFF, Endian.little)
    ..setUint32(16, 0xFFFFFFFF, Endian.little)
    ..setUint16(20, 0, Endian.little);

  return Uint8List.fromList([
    ...zip.sublist(0, zip64EocdOffset),
    ...zip64Eocd.buffer.asUint8List(),
    ...locator.buffer.asUint8List(),
    ...saturatedEocd.buffer.asUint8List(),
  ]);
}

Uint8List _replaceAll(Uint8List data, List<int> from, List<int> to) {
  assert(from.length == to.length, 'replacement must keep the length');
  final out = Uint8List.fromList(data);
  for (var i = 0; i + from.length <= out.length; i++) {
    var match = true;
    for (var j = 0; j < from.length; j++) {
      if (out[i + j] != from[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      out.setRange(i, i + to.length, to);
      i += from.length - 1;
    }
  }
  return out;
}
