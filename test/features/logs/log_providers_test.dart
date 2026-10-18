import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';

void main() {
  late InMemoryKeyValueStore store;
  late AppLog log;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryKeyValueStore();
    log = AppLog(store: LogStore());
    container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appLogProvider.overrideWithValue(log),
      ],
    );
    addTearDown(log.dispose);
  });

  Future<void> settle() => Future<void>.delayed(
    logCoalesceInterval + const Duration(milliseconds: 50),
  );

  group('logEntriesProvider', () {
    test('starts with the store contents', () {
      log.info(LogSource.app, 'before');
      expect(container.read(logEntriesProvider).map((e) => e.message), [
        'before',
      ]);
    });

    test('coalesces a burst of entries into one rebuild', () async {
      var rebuilds = 0;
      container.listen(logEntriesProvider, (_, _) => rebuilds++);

      for (var i = 0; i < 10000; i++) {
        log.info(LogSource.download, 'line $i');
      }
      expect(container.read(logEntriesProvider), isEmpty, reason: 'not yet');

      await settle();

      expect(rebuilds, 1);
      expect(container.read(logEntriesProvider).length, 10000);
      expect(container.read(logEntriesProvider).last.message, 'line 9999');
    });

    test('a second burst after the timer rebuilds again', () async {
      var rebuilds = 0;
      container.listen(logEntriesProvider, (_, _) => rebuilds++);
      log.info(LogSource.app, 'one');
      await settle();
      log.info(LogSource.app, 'two');
      log.info(LogSource.app, 'three');
      await settle();

      expect(rebuilds, 2);
      expect(container.read(logEntriesProvider).length, 3);
    });

    test('flush publishes immediately', () {
      log.info(LogSource.app, 'now');
      container.read(logEntriesProvider.notifier).flush();
      expect(container.read(logEntriesProvider).length, 1);
    });

    test('clear empties the store, the view and the unseen badge', () async {
      log.error(LogSource.download, 'bad');
      await settle();
      expect(container.read(unseenLogCountProvider), 1);

      container.read(logsServiceProvider).clearLogs();

      expect(container.read(logEntriesProvider), isEmpty);
      expect(log.store.length, 0);
      expect(container.read(unseenLogCountProvider), 0);
    });
  });

  group('LogFilter', () {
    LogEntry entry(
      LogLevel level,
      LogSource source,
      String message, {
      String? details,
      String? url,
    }) => LogEntry(
      id: 1,
      time: DateTime(2026),
      level: level,
      source: source,
      message: message,
      details: details,
      url: url,
    );

    test('hides debug unless asked', () {
      final debug = entry(LogLevel.debug, LogSource.debug, 'd');
      expect(LogFilter.all.matches(debug), isFalse);
      expect(const LogFilter(showDebug: true).matches(debug), isTrue);
      expect(
        const LogFilter(levels: {LogLevel.debug}).matches(debug),
        isFalse,
        reason: 'the debug switch wins over the level set',
      );
    });

    test('levels and sources restrict, empty sets do not', () {
      final e = entry(LogLevel.warning, LogSource.backup, 'w');
      expect(LogFilter.all.matches(e), isTrue);
      expect(const LogFilter(levels: {LogLevel.warning}).matches(e), isTrue);
      expect(const LogFilter(levels: {LogLevel.error}).matches(e), isFalse);
      expect(const LogFilter(sources: {LogSource.backup}).matches(e), isTrue);
      expect(
        const LogFilter(sources: {LogSource.download}).matches(e),
        isFalse,
      );
    });

    test('query searches message, details, url and mod path', () {
      final e = entry(
        LogLevel.info,
        LogSource.download,
        'Downloaded file',
        details: 'HTTP 200',
        url: 'https://example.com/Asset.png',
      );
      expect(const LogFilter(query: 'downloaded').matches(e), isTrue);
      expect(const LogFilter(query: 'http 200').matches(e), isTrue);
      expect(const LogFilter(query: 'asset.PNG').matches(e), isTrue);
      expect(const LogFilter(query: 'nope').matches(e), isFalse);
      expect(const LogFilter(query: '  ').isEmpty, isTrue);
    });

    test('equality ignores set order', () {
      expect(
        const LogFilter(levels: {LogLevel.info, LogLevel.error}),
        const LogFilter(levels: {LogLevel.error, LogLevel.info}),
      );
    });
  });

  group('filteredLogEntriesProvider and LogFilterController', () {
    test('follows the filter and the entries', () async {
      log.info(LogSource.app, 'started');
      log.warning(LogSource.download, 'slow download');
      log.error(LogSource.download, 'failed download');
      log.debugLog(LogSource.debug, 'provider rebuilt');
      await settle();

      expect(container.read(filteredLogEntriesProvider).map((e) => e.message), [
        'started',
        'slow download',
        'failed download',
      ]);

      final filter = container.read(logFilterProvider.notifier);
      filter.toggleSource(LogSource.download);
      expect(container.read(filteredLogEntriesProvider).length, 2);

      filter.toggleLevel(LogLevel.error);
      expect(
        container.read(filteredLogEntriesProvider).single.message,
        'failed download',
      );

      filter.setQuery('slow');
      expect(container.read(filteredLogEntriesProvider), isEmpty);

      filter.clear();
      filter.setShowDebug(true);
      expect(container.read(filteredLogEntriesProvider).length, 4);

      filter.toggleSource(LogSource.download);
      filter.toggleSource(LogSource.download);
      expect(container.read(logFilterProvider).sources, isEmpty);
      expect(
        container
            .read(logsServiceProvider)
            .copyVisibleText()
            .split('\n')
            .length,
        4,
      );
    });
  });

  group('unseenLogCountProvider', () {
    test('counts warnings and errors until marked seen', () async {
      expect(container.read(unseenLogCountProvider), 0);
      log.info(LogSource.app, 'fine');
      log.warning(LogSource.app, 'hm');
      log.error(LogSource.app, 'bad');
      await settle();

      expect(container.read(unseenLogCountProvider), 2);

      container.read(logsServiceProvider).markLogsSeen();
      expect(container.read(unseenLogCountProvider), 0);
      expect(log.store.unseenWarningsAndErrors, 0);

      log.error(LogSource.app, 'again');
      await settle();
      expect(container.read(unseenLogCountProvider), 1);
    });
  });

  group('logPanelStateProvider', () {
    test('defaults to collapsed and restores the stored state', () async {
      await store.write(
        LogPanelStateController.storageKey,
        jsonEncode(const LogPanelState(expanded: true, height: 300).toJson()),
      );
      expect(container.read(logPanelStateProvider), LogPanelState.collapsed);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(logPanelStateProvider),
        const LogPanelState(expanded: true, height: 300),
      );
    });

    test('setters persist, clamp and expanding marks logs seen', () async {
      log.error(LogSource.app, 'bad');
      await settle();
      expect(container.read(unseenLogCountProvider), 1);
      final panel = container.read(logPanelStateProvider.notifier);

      await panel.setHeight(5000);
      expect(
        container.read(logPanelStateProvider).height,
        LogPanelState.maxHeight,
      );
      expect(container.read(unseenLogCountProvider), 1);

      await panel.toggle();
      expect(container.read(logPanelStateProvider).expanded, isTrue);
      expect(container.read(unseenLogCountProvider), 0);

      final raw = await store.read(LogPanelStateController.storageKey);
      expect(
        LogPanelState.fromJson(jsonDecode(raw!) as Map<String, Object?>),
        container.read(logPanelStateProvider),
      );
    });

    test('malformed JSON fields keep defaults', () {
      expect(
        LogPanelState.fromJson({'expanded': 'yes', 'height': 'tall'}),
        LogPanelState.collapsed,
      );
      expect(
        LogPanelState.fromJson({'height': 10}).height,
        LogPanelState.minHeight,
      );
    });
  });

  group('logFilePathProvider', () {
    test('is null without a file sink', () {
      expect(container.read(logFilePathProvider), isNull);
    });

    test('is the rotating sink\'s current file', () async {
      final fs = MemoryFileSystem();
      final sink = RotatingFileLogSink(directory: '/logs', fileSystem: fs);
      final fileLog = AppLog(store: LogStore(), sinks: [sink]);
      addTearDown(fileLog.dispose);
      final withFile = ProviderContainer.test(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appLogProvider.overrideWithValue(fileLog),
        ],
      );

      expect(withFile.read(logFilePathProvider), sink.filePath);
      expect(withFile.read(logFilePathProvider), endsWith('vault.log'));
    });
  });
}
