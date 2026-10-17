import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';
import 'package:tts_mod_vault/core/logging/log_store.dart';

void main() {
  group('LogStore', () {
    test('rejects a capacity below one', () {
      expect(() => LogStore(capacity: 0), throwsArgumentError);
    });

    test('appends entries with monotonic ids and returns them', () {
      final store = LogStore();
      final a = store.info(LogSource.app, 'a');
      final b = store.warning(LogSource.app, 'b');
      expect(a.id, 1);
      expect(b.id, 2);
      expect(store.entries.map((e) => e.message), ['a', 'b']);
      expect(store.length, 2);
      expect(store.last, same(b));
    });

    test('evicts the oldest entries beyond capacity', () {
      final store = LogStore(capacity: 3);
      for (var i = 1; i <= 5; i++) {
        store.info(LogSource.library, 'm$i');
      }
      expect(store.length, 3);
      expect(store.entries.map((e) => e.message), ['m3', 'm4', 'm5']);
      expect(store.entries.map((e) => e.id), [3, 4, 5]);
    });

    test('ids keep increasing after eviction and clear', () {
      final store = LogStore(capacity: 2);
      store.info(LogSource.app, 'a');
      store.info(LogSource.app, 'b');
      store.info(LogSource.app, 'c');
      store.clear();
      expect(store.entries, isEmpty);
      expect(store.info(LogSource.app, 'd').id, 4);
    });

    test('entries is a snapshot and unmodifiable', () {
      final store = LogStore()..info(LogSource.app, 'a');
      final snapshot = store.entries;
      store.info(LogSource.app, 'b');
      expect(snapshot.length, 1);
      expect(() => snapshot.add(snapshot.first), throwsUnsupportedError);
    });

    test('counts unseen warnings and errors until markSeen', () {
      final store = LogStore();
      store.info(LogSource.app, 'i');
      store.success(LogSource.app, 's');
      store.debugLog(LogSource.debug, 'd');
      expect(store.unseenWarningsAndErrors, 0);

      store.warning(LogSource.download, 'w');
      store.error(LogSource.download, 'e');
      expect(store.unseenWarningsAndErrors, 2);

      store.markSeen();
      expect(store.unseenWarningsAndErrors, 0);

      store.error(LogSource.download, 'e2');
      expect(store.unseenWarningsAndErrors, 1);
      store.clear();
      expect(store.unseenWarningsAndErrors, 0);
    });

    test('level shortcuts set the level and pass context through', () {
      final store = LogStore();
      final entry = store.error(
        LogSource.workshop,
        'failed',
        details: 'd',
        modPath: 'p',
        url: 'u',
        operationId: 'o',
      );
      expect(entry.level, LogLevel.error);
      expect(entry.source, LogSource.workshop);
      expect(entry.details, 'd');
      expect(entry.modPath, 'p');
      expect(entry.url, 'u');
      expect(entry.operationId, 'o');
      expect(store.info(LogSource.app, 'x').level, LogLevel.info);
      expect(store.success(LogSource.app, 'x').level, LogLevel.success);
      expect(store.warning(LogSource.app, 'x').level, LogLevel.warning);
      expect(store.debugLog(LogSource.app, 'x').level, LogLevel.debug);
    });

    test('log accepts an explicit time', () {
      final store = LogStore();
      final time = DateTime(2026, 3, 4);
      expect(
        store.log(LogLevel.info, LogSource.app, 'x', time: time).time,
        time,
      );
    });

    test('onEntry delivers entries synchronously in order', () async {
      final store = LogStore();
      final seen = <int>[];
      final subscription = store.onEntry.listen((e) => seen.add(e.id));
      store.info(LogSource.app, 'a');
      store.info(LogSource.app, 'b');
      expect(seen, [1, 2], reason: 'sync broadcast');
      await subscription.cancel();
      store.info(LogSource.app, 'c');
      expect(seen, [1, 2]);
    });

    test('dispose closes the stream but logging still works', () async {
      final store = LogStore();
      await store.dispose();
      expect(store.info(LogSource.app, 'after').message, 'after');
      expect(store.length, 1);
    });
  });
}
