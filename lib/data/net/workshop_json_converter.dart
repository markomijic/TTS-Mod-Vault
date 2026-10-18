/// Pure conversion of a Workshop BSON save into the JSON text TTS writes.
/// Port of the transformation in v2 `_downloadAndConvertBson`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:fixnum/fixnum.dart' show Int64;

/// Converts the BSON [bson] of a Workshop item into pretty-printed JSON:
///
/// * top-level binary values are dropped (TTS embeds none in its JSON);
/// * `SaveName` is replaced by [title] when one is given;
/// * `EpochTime` is set to [timeUpdated], inserted as the second key when
///   the document has none (right after `SaveName`, as TTS writes it);
/// * 64-bit integers are written as strings and infinite doubles as
///   `"Infinity"`, both of which `jsonEncode` cannot represent otherwise.
///
/// Throws when [bson] is not a valid BSON document.
String workshopBsonToJson(
  Uint8List bson, {
  required int timeUpdated,
  String? title,
}) {
  final decoded = BsonCodec.deserialize(BsonBinary.from(bson))
    ..removeWhere((_, value) => value is BsonBinary);

  if (title != null && title.isNotEmpty) {
    decoded['SaveName'] = title;
  }

  final Map<String, Object?> ordered;
  if (decoded.containsKey('EpochTime')) {
    decoded['EpochTime'] = timeUpdated;
    ordered = decoded;
  } else {
    ordered = <String, Object?>{};
    final entries = decoded.entries.toList();
    if (entries.isNotEmpty) {
      ordered[entries.first.key] = entries.first.value;
    }
    ordered['EpochTime'] = timeUpdated;
    for (var i = 1; i < entries.length; i++) {
      ordered[entries[i].key] = entries[i].value;
    }
  }

  return _encoder.convert(ordered);
}

final JsonEncoder _encoder = JsonEncoder.withIndent('  ', (Object? value) {
  if (value is Int64) return value.toString();
  if (value is double && value.isInfinite) return 'Infinity';
  return value;
});
