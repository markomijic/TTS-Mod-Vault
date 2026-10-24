// CheckDomainsOperation through the DomainCheckService: the hosts of Mods
// and Saves (excluded domains included, saved objects left out), progress,
// log lines and cancellation.

@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_labels.dart';
import 'package:tts_mod_vault/features/settings/application/check_domains_operation.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../data/db/db_test_helpers.dart';
import '../downloads/downloads_test_harness.dart';

void main() {
  late DownloadsHarness h;
  late _FakeHostsAdapter adapter;

  setUp(() async {
    h = await DownloadsHarness.create();
    adapter = _FakeHostsAdapter(IOHttpClientAdapter());
    h.dio.httpClientAdapter = adapter;
    await h.db.modsDao.upsertMods([
      modUpsert(
        'a',
        assets: [
          image('http://dead.test/a.png'),
          image('https://Alive.test/b.png'),
          image(h.server.url('/png')),
        ],
      ),
      modUpsert(
        'b',
        type: ModType.save,
        assets: [image('https://alive.test/c.png'), pdf('http://zzz.test/r')],
      ),
      modUpsert(
        'c',
        type: ModType.savedObject,
        assets: [image('https://object.test/o.png')],
      ),
    ]);
  });

  DomainCheckService service() => h.container.read(domainCheckServiceProvider);

  test('checks every host of Mods and Saves, excluded ones included', () async {
    await h.container.read(networkOptionsProvider.notifier).setIgnoredDomains([
      'alive.test',
    ]);
    final progress = h.recordProgress();

    final result = await service().checkAllModAndSaveDomains();

    expect(result.cancelled, isFalse);
    expect(result.domains, [
      (domain: '127.0.0.1', reachable: true),
      (domain: 'alive.test', reachable: true),
      (domain: 'dead.test', reachable: false),
      (domain: 'zzz.test', reachable: false),
    ]);
    expect(adapter.hosts, isNot(contains('object.test')));

    expect(progress.map((p) => p.label).toSet(), {'checking.domains'});
    expect(progress.every((p) => p.kind == OperationKind.checkDomains), isTrue);
    expect(progress.last.done, 4);
    expect(progress.last.total, 4);
    expect(h.runnerState, OperationState.idle);

    final messages = [
      for (final e in h.log.store.entries)
        if (e.source == LogSource.urlCheck) e.message,
    ];
    expect(messages, contains('Domain is not reachable: dead.test'));
    expect(messages, contains('Domain is not reachable: zzz.test'));
    final summary = h.log.store.entries.lastWhere(
      (e) => e.message.startsWith('Checked 4 domain(s)'),
    );
    expect(summary.level, LogLevel.warning);
    expect(summary.details, 'dead.test\nzzz.test');
  });

  test('the progress label reads "Checked N/M domains"', () {
    final l10n = AppLocalizationsEn();
    OperationProgress at(int done, int total) => OperationProgress(
      kind: OperationKind.checkDomains,
      label: 'checking.domains',
      done: done,
      total: total,
    );
    expect(operationProgressText(l10n, at(3, 12)), 'Checked 3/12 domains');
    expect(operationProgressText(l10n, at(0, 0)), 'Checking domains...');
    expect(OperationKind.checkDomains.logSource, LogSource.urlCheck);
  });

  test('bypasses the checker cache', () async {
    await service().checkAllModAndSaveDomains();
    final first = adapter.hosts.where((host) => host == 'alive.test').length;
    await service().checkAllModAndSaveDomains();
    expect(
      adapter.hosts.where((host) => host == 'alive.test').length,
      first * 2,
    );
  });

  test('all reachable logs a success summary', () async {
    adapter.dead.clear();
    final result = await service().checkAllModAndSaveDomains();
    expect(result.unreachable, isEmpty);
    final summary = h.log.store.entries.lastWhere(
      (e) => e.message.startsWith('Checked'),
    );
    expect(summary.level, LogLevel.success);
  });

  test('cancelling returns a cancelled result and logs no verdict', () async {
    adapter.slow.add('alive.test');
    final future = service().checkAllModAndSaveDomains();
    await adapter.slowRequestSeen.future;
    h.container.read(operationRunnerProvider.notifier).cancel();

    final result = await future;
    expect(result.cancelled, isTrue);
    expect(h.runnerState, OperationState.idle);
    final messages = [for (final e in h.log.store.entries) e.message];
    expect(
      messages.where((m) => m.startsWith('Domain is not reachable')),
      isEmpty,
    );
    expect(messages.any((m) => m.startsWith('Domain check cancelled')), isTrue);
  });
}

/// Fails requests to [dead] hosts at connection level, answers 200 for the
/// other `.test` hosts, holds [slow] hosts until cancelled and passes the
/// rest (the loopback server) through.
final class _FakeHostsAdapter implements HttpClientAdapter {
  _FakeHostsAdapter(this._inner);

  final HttpClientAdapter _inner;
  final Set<String> dead = {'dead.test', 'zzz.test'};
  final Set<String> slow = {};
  final List<String> hosts = [];
  final Completer<void> slowRequestSeen = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    hosts.add(host);
    if (slow.contains(host)) {
      if (!slowRequestSeen.isCompleted) slowRequestSeen.complete();
      await cancelFuture;
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    if (dead.contains(host)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'host is down',
      );
    }
    if (host.endsWith('.test')) return ResponseBody.fromString('', 200);
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
