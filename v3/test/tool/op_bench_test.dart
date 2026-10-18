// End-to-end test of `tool/bench/op_bench.dart` through its Dart API on a
// small stress library: refresh (cold, then warm), backup-one, import of
// that backup into a second library and a cleanup dry run. The scenarios
// build on each other, so they run in declaration order inside one group.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/bench/op_bench.dart';
import '../../tool/stress_library.dart';
import 'stress_source_fixture.dart';

void main() {
  late Directory temp;
  late String libraryA;
  late String libraryB;
  late String dataA;
  late String dataB;
  late String backups;
  late String forbidden;
  late List<String> cwdBefore;
  late String archive;

  List<String> cwdListing() =>
      Directory.current.listSync().map((e) => p.basename(e.path)).toList()
        ..sort();

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('ttsmv_op_bench_');
    final source = writeStressSource(temp);
    libraryA = p.join(temp.path, 'libA');
    libraryB = p.join(temp.path, 'libB');
    dataA = p.join(temp.path, 'dataA');
    dataB = p.join(temp.path, 'dataB');
    backups = p.join(temp.path, 'backups');
    forbidden = p.join(temp.path, 'Documents');
    await generateStressLibrary(
      sourceModsDir: source,
      outDir: libraryA,
      mods: 5,
      presentFraction: 0.5,
      forbiddenRoots: [forbidden],
    );
    // Same ids, no cached files: the import target.
    await generateStressLibrary(
      sourceModsDir: source,
      outDir: libraryB,
      mods: 2,
      presentFraction: 0,
      forbiddenRoots: [forbidden],
    );
    cwdBefore = cwdListing();
  });

  tearDownAll(() {
    expect(cwdListing(), cwdBefore, reason: 'nothing written to the cwd');
    for (final data in [dataA, dataB]) {
      final names = Directory(data)
          .listSync()
          .map((e) => p.basename(e.path))
          .toSet();
      expect(
        names.difference({
          'vault.sqlite',
          'vault.sqlite-wal',
          'vault.sqlite-shm',
          'vault.log',
        }),
        isEmpty,
        reason: 'only the database and the log live in the data folder',
      );
      expect(names, contains('vault.log'));
    }
    expect(Directory(forbidden).existsSync(), isFalse);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ScenarioRequest request(
    BenchScenario scenario, {
    String? library,
    String? data,
    String? backupsDir,
    String? ttsmod,
    String? mod,
    bool cold = false,
    bool dryRun = false,
  }) => ScenarioRequest(
    libraryDir: library ?? libraryA,
    dataDir: data ?? dataA,
    scenario: scenario,
    backupsDir: backupsDir,
    ttsmodPath: ttsmod,
    modId: mod,
    cold: cold,
    dryRun: dryRun,
    workerPoolSize: 2,
  );

  void expectSane(ScenarioResult result) {
    expect(result.elapsedMs, greaterThanOrEqualTo(0));
    expect(result.memory.baselineRss, greaterThan(0));
    expect(
      result.memory.peakRss,
      greaterThanOrEqualTo(result.memory.baselineRss),
    );
    expect(result.memory.samples, greaterThanOrEqualTo(2));
    expect(result.memory.maxRssAtEnd, greaterThan(0));
    final json = result.toJson();
    expect(json['scenario'], result.scenario.cliName);
    expect(json['jit'], isTrue);
    expect(json['memory'], isA<Map<String, Object?>>());
  }

  group('scenarios', () {
    test('refresh: cold then warm', () async {
      final lines = <String>[];
      final cold = await runScenario(
        request(BenchScenario.refresh, cold: true),
        log: lines.add,
        forbiddenRoots: [forbidden],
      );
      expectSane(cold);
      expect(cold.setupRefreshMs, isNull);
      expect(cold.details['mods'], 5);
      expect(cold.details['scanned'], 5);
      expect(cold.details['parsed'], 5);
      expect(cold.details['durationMs'], isA<int>());
      expect(cold.details.keys, contains('scanMs'));
      expect(cold.warnings, isEmpty);
      expect(File(p.join(dataA, 'vault.sqlite')).existsSync(), isTrue);

      final warm = await runScenario(
        request(BenchScenario.refresh),
        forbiddenRoots: [forbidden],
      );
      expectSane(warm);
      expect(warm.details['scanned'], 5);
      expect(warm.details['parsed'], 0, reason: 'nothing changed');
    });

    test('backup-one writes the archive into the backups folder', () async {
      final result = await runScenario(
        request(
          BenchScenario.backupOne,
          backupsDir: backups,
          mod: '$firstGeneratedId',
        ),
        forbiddenRoots: [forbidden],
      );
      expectSane(result);
      expect(result.setupRefreshMs, isNotNull);
      expect(result.details['modId'], '$firstGeneratedId');
      // Template 111: 5 scheme URLs + 1 legacy duplicate key -> 6 assets
      // in the index, round(5 * .5) = 3 of them on disk.
      expect(result.details['assetsPresent'], 3);
      expect(result.details['assetCount'], 3);
      expect(result.details['skipped'], 0);
      archive = result.details['archive']! as String;
      expect(p.isWithin(backups, archive), isTrue);
      expect(File(archive).existsSync(), isTrue);
      expect(result.details['archiveBytes'], File(archive).lengthSync());
    });

    test('import restores the archive into the second library', () async {
      final result = await runScenario(
        request(
          BenchScenario.import,
          library: libraryB,
          data: dataB,
          ttsmod: archive,
        ),
        forbiddenRoots: [forbidden],
      );
      expectSane(result);
      expect(result.details['assetsExtracted'], 3);
      expect(result.details['failed'], 0);
      expect(result.details['cancelled'], isFalse);
      final jsonPath = result.details['jsonPath']! as String;
      expect(p.isWithin(libraryB, jsonPath), isTrue);
      expect(p.basename(jsonPath), '$firstGeneratedId.json');
      final restored = Directory(p.join(libraryB, 'Mods'))
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => !p.isWithin(p.join(libraryB, 'Mods', 'Workshop'), f.path),
          )
          .toList();
      expect(restored, hasLength(3));
      for (final file in restored) {
        expect(p.isWithin(libraryB, file.path), isTrue);
      }
      // The source library and its archive are untouched.
      expect(File(archive).existsSync(), isTrue);
    });

    test('cleanup --dry-run only scans', () async {
      final orphan = File(p.join(libraryA, 'Mods', 'Images', 'orphan1.png'))
        ..writeAsBytesSync(const [1, 2, 3]);
      final result = await runScenario(
        request(BenchScenario.cleanup, dryRun: true),
        forbiddenRoots: [forbidden],
      );
      expectSane(result);
      expect(result.details['dryRun'], isTrue);
      expect(result.details['candidates'], 1);
      expect(result.details['candidateBytes'], 3);
      expect(result.details['scanMs'], isA<int>());
      expect(result.details.containsKey('deleteMs'), isFalse);
      expect(orphan.existsSync(), isTrue);
    });
  });

  group('safety', () {
    test('data and backups folders may not lie inside Documents', () {
      expect(
        () => checkSafety(
          request(BenchScenario.refresh, data: p.join(forbidden, 'x')),
          forbiddenRoots: [forbidden],
        ),
        throwsArgumentError,
      );
      expect(
        () => checkSafety(
          request(
            BenchScenario.backupOne,
            backupsDir: p.join(forbidden, 'TTS Mod Vault', 'Backups'),
          ),
          forbiddenRoots: [forbidden],
        ),
        throwsArgumentError,
      );
    });

    test('writing scenarios refuse a library inside Documents', () {
      final real = p.join(forbidden, 'My Games', 'Tabletop Simulator');
      expect(
        () => checkSafety(
          request(BenchScenario.import, library: real, ttsmod: 'x.ttsmod'),
          forbiddenRoots: [forbidden],
        ),
        throwsArgumentError,
      );
      expect(
        () => checkSafety(
          request(BenchScenario.cleanup, library: real),
          forbiddenRoots: [forbidden],
        ),
        throwsArgumentError,
      );
      // Read-only scenarios are allowed with a warning.
      final warnings = checkSafety(
        request(BenchScenario.cleanup, library: real, dryRun: true),
        forbiddenRoots: [forbidden],
      );
      expect(warnings, hasLength(1));
      expect(
        checkSafety(
          request(BenchScenario.refresh, library: real),
          forbiddenRoots: [forbidden],
        ),
        hasLength(1),
      );
    });

    test('required options', () {
      expect(
        () => checkSafety(request(BenchScenario.backupOne), forbiddenRoots: []),
        throwsArgumentError,
      );
      expect(
        () => checkSafety(request(BenchScenario.import), forbiddenRoots: []),
        throwsArgumentError,
      );
      expect(() => BenchScenario.parse('nope'), throwsArgumentError);
      expect(BenchScenario.parse('check-urls'), BenchScenario.checkUrls);
    });
  });
}
