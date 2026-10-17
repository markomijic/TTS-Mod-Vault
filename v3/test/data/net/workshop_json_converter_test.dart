// workshopBsonToJson on BSON documents built with package:bson.

import 'dart:convert';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/net/workshop_json_converter.dart';

Uint8List bsonOf(Map<String, Object?> document) =>
    Uint8List.fromList(BsonCodec.serialize(document).byteList);

void main() {
  test('inserts EpochTime as the second key after SaveName', () {
    final json = workshopBsonToJson(
      bsonOf({
        'SaveName': 'My Mod',
        'GameMode': 'Chess',
        'ObjectStates': <Object?>[],
      }),
      timeUpdated: 1700000000,
    );
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded.keys.toList(), [
      'SaveName',
      'EpochTime',
      'GameMode',
      'ObjectStates',
    ]);
    expect(decoded['EpochTime'], 1700000000);
    expect(decoded['SaveName'], 'My Mod');
    // Pretty printed with two spaces.
    expect(json, startsWith('{\n  "SaveName": "My Mod",\n  "EpochTime": '));
  });

  test('updates an existing EpochTime in place', () {
    final json = workshopBsonToJson(
      bsonOf({'SaveName': 'x', 'GameMode': 'y', 'EpochTime': 5}),
      timeUpdated: 1700000000,
    );
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded.keys.toList(), ['SaveName', 'GameMode', 'EpochTime']);
    expect(decoded['EpochTime'], 1700000000);
  });

  test('overrides SaveName with the Steam title when given', () {
    final json = workshopBsonToJson(
      bsonOf({'SaveName': 'old', 'GameMode': 'y'}),
      timeUpdated: 1,
      title: 'Steam Title',
    );
    expect(
      (jsonDecode(json) as Map<String, Object?>)['SaveName'],
      'Steam Title',
    );
    final kept = workshopBsonToJson(
      bsonOf({'SaveName': 'old'}),
      timeUpdated: 1,
      title: '',
    );
    expect((jsonDecode(kept) as Map<String, Object?>)['SaveName'], 'old');
  });

  test('drops top-level binary values', () {
    final json = workshopBsonToJson(
      bsonOf({
        'SaveName': 'x',
        'Blob': BsonBinary.from([1, 2, 3]),
        'GameMode': 'y',
      }),
      timeUpdated: 1,
    );
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded.containsKey('Blob'), isFalse);
    expect(decoded.keys.toList(), ['SaveName', 'EpochTime', 'GameMode']);
  });

  test('writes 64-bit integers as strings and infinities as "Infinity"', () {
    final json = workshopBsonToJson(
      bsonOf({
        'SaveName': 'x',
        'Big': Int64.parseInt('9007199254740993'),
        'Nested': {
          'Inf': double.infinity,
          'NegInf': double.negativeInfinity,
          'List': [double.infinity, 1.5],
        },
      }),
      timeUpdated: 1,
    );
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded['Big'], '9007199254740993');
    final nested = decoded['Nested'] as Map<String, Object?>;
    expect(nested['Inf'], 'Infinity');
    expect(nested['NegInf'], 'Infinity');
    expect(nested['List'], ['Infinity', 1.5]);
  });

  test('rejects bytes that are not a BSON document', () {
    expect(
      () => workshopBsonToJson(Uint8List.fromList([1, 2]), timeUpdated: 1),
      throwsA(anything),
    );
  });
}
