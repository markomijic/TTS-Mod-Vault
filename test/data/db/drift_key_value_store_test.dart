import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/drift_key_value_store.dart';

void main() {
  late AppDatabase db;
  late KeyValueStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftKeyValueStore(db);
  });
  tearDown(() => db.close());

  test('read of a missing key returns null', () async {
    expect(await store.read('missing'), isNull);
  });

  test('write then read round-trips the value', () async {
    await store.write('theme', '{"mode":"dark"}');
    expect(await store.read('theme'), '{"mode":"dark"}');
  });

  test('write overwrites an existing value', () async {
    await store.write('k', 'first');
    await store.write('k', 'second');
    expect(await store.read('k'), 'second');

    final count = await db
        .customSelect('SELECT COUNT(*) AS n FROM kv')
        .getSingle();
    expect(count.read<int>('n'), 1);
  });

  test('delete removes the key and is a no-op for missing keys', () async {
    await store.write('k', 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('keys are independent', () async {
    await store.write('a', '1');
    await store.write('b', '2');
    await store.delete('a');
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), '2');
  });

  test('empty string values are stored, not treated as null', () async {
    await store.write('empty', '');
    expect(await store.read('empty'), '');
  });
}
