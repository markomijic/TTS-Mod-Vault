// Times the refresh pipeline's bulk writes and the summary query against a
// file database on drift's background isolate (as the app runs it), with
// synthetic data shaped like the reference library (plan 10.1): 102 mods,
// ~18.8k asset rows with a few very large mods, ~8.1k cached files.
//
//   dart compile exe tool/bench/db_probe.dart -o <out>/db_probe.exe
//   db_probe.exe <scratch dir> [repeats]
import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:drift/native.dart';

import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/models/mod_ref.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(args.first)..createSync(recursive: true);
  final repeats = args.length > 1 ? int.parse(args[1]) : 2;
  final mods = _mods();
  final files = _files(mods);
  stdout.writeln(
    'mods=${mods.length} assets=${mods.fold(0, (n, m) => n + m.assets.length)} '
    'files=${files.values.fold(0, (n, f) => n + f.length)}',
  );

  for (var i = 0; i < repeats; i++) {
    final file = File(p.join(dir.path, 'probe_$i.sqlite'));
    for (final f in [
      file,
      File('${file.path}-wal'),
      File('${file.path}-shm'),
    ]) {
      if (f.existsSync()) f.deleteSync();
    }
    final db = AppDatabase.open(file);
    final sw = Stopwatch()..start();
    await db.customSelect('SELECT 1').get();
    final tOpen = sw.elapsedMilliseconds;

    sw.reset();
    await db.modsDao.upsertMods(mods);
    final tUpsertCold = sw.elapsedMilliseconds;
    sw.reset();
    await db.modsDao.upsertMods(mods);
    final tUpsertWarm = sw.elapsedMilliseconds;

    sw.reset();
    for (final type in AssetType.values) {
      await db.existingFilesDao.replaceAll(type, files[type]!);
    }
    final tFilesCold = sw.elapsedMilliseconds;
    sw.reset();
    for (final type in AssetType.values) {
      await db.existingFilesDao.replaceAll(type, files[type]!);
    }
    final tFilesWarm = sw.elapsedMilliseconds;

    sw.reset();
    final summaries = await db.libraryQueries.modSummaries(
      ModType.mod,
      ignoreAudioGlobally: true,
    );
    await db.libraryQueries.modSummaries(
      ModType.save,
      ignoreAudioGlobally: true,
    );
    final tSummary = sw.elapsedMilliseconds;
    final present = summaries.fold(0, (n, m) => n + m.summary.present);

    // Summary query shapes: the shipped one (per-type SUM(CASE) columns,
    // one query per mod type) against a plain per-(mod, type) aggregate
    // joined in Dart, and the shipped one for all types in one statement.
    sw.reset();
    for (var k = 0; k < 5; k++) {
      await db.libraryQueries.modSummaries(
        ModType.mod,
        ignoreAudioGlobally: true,
      );
    }
    final tShipped = sw.elapsedMilliseconds / 5;
    sw.reset();
    for (var k = 0; k < 5; k++) {
      await db
          .customSelect(
            'SELECT a.mod_path, a.asset_type, COUNT(*) AS total, '
            'COUNT(e.file_key) AS present FROM mod_assets a '
            'LEFT JOIN existing_files e ON e.asset_type = a.asset_type '
            'AND e.file_key = a.file_key GROUP BY a.mod_path, a.asset_type',
          )
          .get();
      await db.customSelect('SELECT * FROM mods WHERE type = 0').get();
    }
    final tPerType = sw.elapsedMilliseconds / 5;
    sw.reset();
    for (var k = 0; k < 5; k++) {
      await db
          .customSelect(
            'SELECT a.mod_path, COUNT(*) AS total, COUNT(e.file_key) AS present '
            'FROM mod_assets a LEFT JOIN existing_files e '
            'ON e.asset_type = a.asset_type AND e.file_key = a.file_key '
            'GROUP BY a.mod_path',
          )
          .get();
    }
    final tTotalsOnly = sw.elapsedMilliseconds / 5;
    sw.reset();
    for (var k = 0; k < 5; k++) {
      await db
          .customSelect(
            'SELECT COUNT(*) FROM mod_assets a LEFT JOIN existing_files e '
            'ON e.asset_type = a.asset_type AND e.file_key = a.file_key',
          )
          .get();
    }
    final tJoinOnly = sw.elapsedMilliseconds / 5;
    stdout.writeln(
      'summary shapes: shipped=${tShipped}ms perTypeAggregate=${tPerType}ms '
      'totalsOnly=${tTotalsOnly}ms joinOnly=${tJoinOnly}ms',
    );

    final wal = File('${file.path}-wal');
    stdout.writeln(
      'run $i: open=${tOpen}ms upsertCold=${tUpsertCold}ms '
      'upsertWarm=${tUpsertWarm}ms filesCold=${tFilesCold}ms '
      'filesWarm=${tFilesWarm}ms summary=${tSummary}ms '
      '(${summaries.length} mods, $present present) '
      'wal=${wal.existsSync() ? wal.lengthSync() : 0}B',
    );
    await db.close();
  }

  // Where does the asset insert time go? Fresh database per variant.
  final rows = <List<Object>>[];
  for (final mod in mods) {
    for (final asset in mod.assets) {
      rows.add([
        mod.ref.jsonPath,
        asset.url,
        asset.assetKey,
        asset.type.dbValue,
        fileKeyFromUrl(asset.url),
      ]);
    }
  }
  for (final variant in [
    'baseline',
    'multi-row VALUES, 199 rows per statement',
    '13 transactions',
    '13 transactions, wal_autocheckpoint=0',
    'synchronous=OFF',
    'sorted by pk',
    'no secondary indexes',
    'no indexes at all (rowid table copy)',
    'in-memory',
  ]) {
    final file = File(p.join(dir.path, 'variant.sqlite'));
    for (final f in [
      file,
      File('${file.path}-wal'),
      File('${file.path}-shm'),
    ]) {
      if (f.existsSync()) f.deleteSync();
    }
    final db = variant == 'in-memory'
        ? AppDatabase(NativeDatabase.memory())
        : AppDatabase.open(file);
    await db.customSelect('SELECT 1').get();
    await db.batch((b) {
      for (final item in mods) {
        b.insert(
          db.mods,
          ModsCompanion.insert(
            jsonPath: item.ref.jsonPath,
            id: item.ref.id,
            type: item.ref.type,
            folder: item.folder,
            saveName: item.saveName,
            mtimeMs: item.mtimeMs,
            sizeBytes: item.sizeBytes,
          ),
        );
      }
    });
    if (variant == 'synchronous=OFF') {
      await db.customStatement('PRAGMA synchronous = OFF');
    }
    if (variant.endsWith('wal_autocheckpoint=0')) {
      await db.customStatement('PRAGMA wal_autocheckpoint = 0');
    }
    final chunk = variant.startsWith('13 transactions') ? 1450 : 4000;
    final perChunkTransaction = variant.startsWith('13 transactions');
    if (variant.startsWith('no ')) {
      await db.customStatement('DROP INDEX mod_assets_file_key');
      await db.customStatement('DROP INDEX mod_assets_type');
    }
    var table = 'mod_assets';
    if (variant.startsWith('no indexes')) {
      table = 'mod_assets_plain';
      await db.customStatement(
        'CREATE TABLE mod_assets_plain (mod_path TEXT NOT NULL, url TEXT NOT '
        'NULL, asset_key TEXT NOT NULL, asset_type INTEGER NOT NULL, '
        'file_key TEXT NOT NULL)',
      );
    }
    final order = variant == 'sorted by pk' ? ' ORDER BY 1, 2' : '';
    Future<void> insertChunk(int start) {
      final end = start + chunk < rows.length ? start + chunk : rows.length;
      if (variant.startsWith('multi-row VALUES')) {
        // 5 columns x 199 rows = 995 bound parameters, under the old 999
        // limit. One statement per 199 rows.
        return () async {
          for (var s = start; s < end; s += 199) {
            final e = s + 199 < end ? s + 199 : end;
            final slice = rows.sublist(s, e);
            await db.customStatement(
              'INSERT OR IGNORE INTO $table '
              '(mod_path, url, asset_key, asset_type, file_key) VALUES '
              '${List.filled(slice.length, '(?, ?, ?, ?, ?)').join(', ')}',
              [for (final r in slice) ...r],
            );
          }
        }();
      }
      return db.customStatement(
        'INSERT OR IGNORE INTO $table '
        '(mod_path, url, asset_key, asset_type, file_key) '
        "SELECT json_extract(value, '\$[0]'), json_extract(value, '\$[1]'), "
        "json_extract(value, '\$[2]'), json_extract(value, '\$[3]'), "
        "json_extract(value, '\$[4]') FROM json_each(?)$order",
        [jsonEncode(rows.sublist(start, end))],
      );
    }

    final sw = Stopwatch()..start();
    if (perChunkTransaction) {
      for (var start = 0; start < rows.length; start += chunk) {
        await db.transaction(() => insertChunk(start));
      }
    } else {
      await db.transaction(() async {
        for (var start = 0; start < rows.length; start += chunk) {
          await insertChunk(start);
        }
      });
    }
    final ms = sw.elapsedMilliseconds;
    final wal = File('${file.path}-wal');
    stdout.writeln(
      'variant "$variant": insert ${rows.length} rows = ${ms}ms '
      'wal=${wal.existsSync() ? wal.lengthSync() : 0}B',
    );
    await db.close();
  }
}

List<ModUpsert> _mods() {
  const bigCounts = [1600, 1413, 1139, 763, 726];
  const total = 18839;
  final small = (total - bigCounts.fold(0, (a, b) => a + b)) ~/ 97;
  final mods = <ModUpsert>[];
  for (var m = 0; m < 102; m++) {
    final count = m < bigCounts.length ? bigCounts[m] : small;
    final type = m < 98 ? ModType.mod : ModType.save;
    final path = type == ModType.mod
        ? 'C:/TTS/Mods/Workshop/${2000000000 + m}.json'
        : 'C:/TTS/Saves/TS_Save_$m.json';
    mods.add(
      ModUpsert(
        ref: ModRef.fromPath(type, path),
        folder: type == ModType.mod ? 'Workshop' : 'Saves',
        saveName: 'Mod $m',
        epochTime: 1700000000 + m,
        mtimeMs: 1700000000000 + m,
        sizeBytes: 1000 * count,
        imagePath: null,
        assets: [for (var a = 0; a < count; a++) _asset(m, a, _typeFor(a))],
      ),
    );
  }
  return mods;
}

AssetType _typeFor(int a) {
  final r = a % 100;
  if (r < 92) return AssetType.image;
  if (r < 95) return AssetType.model;
  if (r < 97) return AssetType.pdf;
  if (r < 99) return AssetType.audio;
  return AssetType.assetBundle;
}

ModAssetInput _asset(int m, int a, AssetType type) {
  final url =
      'https://steamusercontent-a.akamaihd.net/ugc/${1000000000000 + m * 10000 + a}/'
      '${(m * 7919 + a * 104729).toRadixString(16).toUpperCase().padLeft(40, 'A')}/';
  return (url: url, assetKey: type.jsonKeys.first, type: type);
}

Map<AssetType, List<({String fileKey, String path})>> _files(
  List<ModUpsert> mods,
) {
  // ~43% of referenced images present, plus unreferenced leftovers, to land
  // near the reference counts (7,779 images, 8,151 files in total).
  final result = {
    for (final t in AssetType.values) t: <({String fileKey, String path})>[],
  };
  var n = 0;
  for (final mod in mods) {
    for (final asset in mod.assets) {
      n++;
      if (n % 7 < 3) {
        result[asset.type]!.add((
          fileKey: fileKeyFromUrl(asset.url),
          path:
              'C:/TTS/Mods/${asset.type.folderName}/${fileNameFromUrl(asset.url)}.png',
        ));
      }
    }
  }
  return result;
}
